#!/usr/bin/env python3
"""L'ouvrier : il prend les travaux de la file et les exécute.

Un processus séparé de l'API, pour deux raisons. Une requête HTTP qui dure dix
minutes est une requête qui échoue, et l'image de l'API ne porte pas le
pipeline : elle sert la base, elle ne la fabrique pas. L'ouvrier, lui, a les
deux sous la main.

Il prend un travail à la fois. Sur une machine à seize gigaoctets partagés avec
PostgreSQL et l'API, deux vectorisations en parallèle ne vont pas deux fois plus
vite : elles se disputent le processeur et finissent toutes les deux en retard.

    python3 pipeline/travailleur.py            # tourne jusqu'à ce qu'on l'arrête
    python3 pipeline/travailleur.py --une-fois # prend un travail et sort
"""
import argparse
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RACINE / "pipeline"))
from common import pg  # noqa: E402

PYTHON = os.getenv("PYTHON_PIPELINE", str(RACINE / ".venv" / "bin" / "python"))
if not Path(PYTHON).exists():
    PYTHON = sys.executable

REPOS = 5  # secondes entre deux regards à la file, quand elle est vide

# Le signe de vie lu par la sonde Docker : la boucle et le battement le touchent.
# Un fichier plutôt qu'un port : l'ouvrier n'écoute rien, et n'a pas à le faire.
SIGNE_DE_VIE = Path(os.getenv("SIGNE_DE_VIE", "/tmp/ouvrier-vivant"))


def signaler_vie() -> None:
    try:
        SIGNE_DE_VIE.touch()
    except OSError:
        pass

# Ce que chaque type lance. La même table que côté API, recopiée ici parce que
# l'ouvrier ne dépend pas du code de l'API : il ne partage avec elle que la base.
COMMANDES = {
    "ingestion": ["pipeline/ingest/ingest.py"],
    "structure": ["pipeline/ingest/structure.py", "--tous"],
    "passages": ["pipeline/ingest/reparer_passages.py", "--tous"],
    "vecteurs": ["pipeline/embed/embed.py", "--lot", "128"],
    "derive": ["pipeline/derive/derive.py", "--sync"],
    "import_data": ["pipeline/derive/importer.py"],
}

_arret = False


def _stop(*_):
    """Arrêt propre : on finit le travail en cours plutôt que de le laisser à
    moitié fait, puis on sort. Un conteneur qu'on redéploie ne doit pas laisser
    une base à demi écrite."""
    global _arret
    _arret = True
    print("\nArrêt demandé. Le travail en cours va jusqu'au bout.", flush=True)


signal.signal(signal.SIGTERM, _stop)
signal.signal(signal.SIGINT, _stop)


def prendre(conn):
    """Réserve le plus ancien travail en attente.

    `for update skip locked` : deux ouvriers peuvent tourner sans jamais
    prendre le même travail, et sans qu'aucun n'attende l'autre.
    """
    with conn.cursor() as cur:
        cur.execute(
            """update travail set etat = 'en_cours', started_at = now(), battement = now()
                where id = (select id from travail where etat = 'en_attente'
                             order by created_at limit 1
                             for update skip locked)
             returning id, type, charge, document_id""",
        )
        ligne = cur.fetchone()
    conn.commit()
    return ligne


def solder(conn, travail_id, etat, journal, erreur=None, progression=100):
    with conn.cursor() as cur:
        cur.execute(
            """update travail set etat = %s, journal = %s, erreur = %s,
                      progression = %s, finished_at = now()
                where id = %s""",
            (etat, (journal or "")[-20000:], erreur, progression, travail_id),
        )
    conn.commit()


def avancer(conn, travail_id, journal, progression):
    """Écrit l'avancement pendant l'exécution.

    Sans cela, un travail de dix heures reste à zéro pour cent jusqu'à la fin,
    et on ne sait pas le distinguer d'un travail bloqué.
    """
    with conn.cursor() as cur:
        cur.execute(
            "update travail set journal = %s, progression = %s where id = %s",
            ((journal or "")[-20000:], min(99, progression), travail_id),
        )
    conn.commit()


BATTEMENT_S = 30


class Battement(threading.Thread):
    """Signale toutes les trente secondes que le travail est vivant.

    Un fil à part, avec sa propre connexion : pendant qu'un script charge un
    modèle de deux gigaoctets sans rien écrire, la boucle principale est bloquée
    sur sa sortie et ne peut rien signaler. Sans signal, la veille de l'API sait
    qu'un travail « en cours » depuis plusieurs minutes est orphelin (ouvrier tué,
    conteneur redémarré) et le remet en file.
    """

    def __init__(self, travail_id):
        super().__init__(daemon=True)
        self.travail_id = travail_id
        self.fin = threading.Event()

    def run(self):
        conn = pg()
        try:
            while not self.fin.wait(BATTEMENT_S):
                signaler_vie()
                with conn.cursor() as cur:
                    cur.execute("update travail set battement = now() where id = %s and etat = 'en_cours'",
                                (self.travail_id,))
                conn.commit()
        except Exception as exc:  # noqa: BLE001 - un battement manqué ne doit pas tuer le travail
            print(f"   battement interrompu : {exc}", flush=True)
        finally:
            conn.close()


def executer(conn, travail) -> tuple[str, str, str | None]:
    travail_id, type_, charge, document_id = travail
    commande = COMMANDES.get(type_)
    if not commande:
        return "echec", "", f"Type de travail inconnu : {type_}"

    args = [PYTHON] + commande
    # Un travail qui vise un ouvrage le passe au script, quand celui-ci sait le
    # recevoir. Les autres tournent sur tout le corpus.
    if document_id and type_ in ("vecteurs", "derive"):
        args += ["--doc", str(document_id)[:8]]
    if type_ == "derive" and (charge or {}).get("kind"):
        args += ["--kind", charge["kind"]]
    if type_ == "ingestion":
        # Un dépôt vise son fichier. Sans cela, l'ingestion ratissait tout
        # `livres/` et faisait entrer les `.ocr.pdf` posés à côté des
        # originaux, c'est à dire sept doublons d'un coup.
        f = (charge or {}).get("fichier")
        axe = (charge or {}).get("axe") or "_a-classer"
        if f:
            args += ["--fichier", f"{axe}/{f}"]
        elif (charge or {}).get("limite"):
            args += ["--limit", str(charge["limite"])]

    print(f"→ {type_} : {' '.join(args[1:])}", flush=True)
    sortie = []
    debut = time.time()
    try:
        proc = subprocess.Popen(
            args, cwd=RACINE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1,
        )
        dernier = 0.0
        for ligne in proc.stdout:
            sortie.append(ligne.rstrip())
            # On remonte l'avancement toutes les cinq secondes, pas à chaque
            # ligne : un script bavard écrirait mille fois par minute en base.
            if time.time() - dernier > 5:
                dernier = time.time()
                avancer(conn, travail_id, "\n".join(sortie), _progres(sortie))
        code = proc.wait()
    except Exception as exc:  # noqa: BLE001
        return "echec", "\n".join(sortie), str(exc)[:1000]

    duree = int(time.time() - debut)
    sortie.append(f"\n[{duree} s, code de sortie {code}]")
    if code == 0:
        return "termine", "\n".join(sortie), None
    return "echec", "\n".join(sortie), f"Le script est sorti en code {code}."


def _progres(lignes: list[str]) -> int:
    """Un pourcentage tiré de la sortie du script, quand il en donne un.

    Les scripts du pipeline écrivent « 1408/11275 (12 %) ». On lit le dernier
    qui passe plutôt que d'inventer une barre de progression fictive.
    """
    import re

    for ligne in reversed(lignes[-40:]):
        m = re.search(r"\((\d{1,3})\s*%\)", ligne)
        if m:
            return max(0, min(99, int(m.group(1))))
        m = re.search(r"(\d+)\s*/\s*(\d+)", ligne)
        if m and int(m.group(2)) > 0:
            return max(0, min(99, int(100 * int(m.group(1)) / int(m.group(2)))))
    return 1


def main():
    ap = argparse.ArgumentParser(description="Exécute les travaux de la file ASCENDA.")
    ap.add_argument("--une-fois", action="store_true",
                    help="prend un travail, l'exécute, et sort")
    a = ap.parse_args()

    conn = pg()
    print(f"Ouvrier ASCENDA. Python : {PYTHON}", flush=True)
    fait = 0
    while not _arret:
        signaler_vie()
        try:
            travail = prendre(conn)
        except Exception as exc:  # noqa: BLE001
            # Base redémarrée, réseau coupé : on attend et on se reconnecte au
            # lieu de mourir. Docker relancerait le conteneur, mais en perdant
            # une minute et en remplissant le journal de traces identiques.
            print(f"File injoignable ({type(exc).__name__}), nouvel essai dans 15 s.", flush=True)
            time.sleep(15)
            try:
                conn.close()
            except Exception:  # noqa: BLE001
                pass
            try:
                conn = pg()
            except Exception:  # noqa: BLE001
                pass
            continue
        if not travail:
            if a.une_fois:
                print("File vide.", flush=True)
                break
            time.sleep(REPOS)
            continue

        battement = Battement(travail[0])
        battement.start()
        try:
            etat, journal, erreur = executer(conn, travail)
        finally:
            battement.fin.set()
        solder(conn, travail[0], etat, journal, erreur)
        fait += 1
        print(f"   {etat}" + (f" : {erreur}" if erreur else ""), flush=True)
        if a.une_fois:
            break

    conn.close()
    print(f"{fait} travail(aux) exécuté(s).", flush=True)


if __name__ == "__main__":
    main()
