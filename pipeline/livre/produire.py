"""Le module par ouvrage : de la source au corpus servi."""
import argparse
import os
import subprocess
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RACINE / "pipeline"))
sys.path.insert(0, str(RACINE / "pipeline" / "livre"))
from common import pg  # noqa: E402
from etat import ATTENDUS, etat_document  # noqa: E402

PYTHON = str(RACINE / ".venv" / "bin" / "python")

# L'ordre compte : la fiche fixe le titre, les auteurs et le niveau
ORDRE = [
    "vecteurs",
    "fiche_lecture",
    "citation",
    "quiz",
    "compte_rendu",
    "synthese",
    "resume_executif",
]

HORS_PLAN = {"flashcards"}

# Ce qui n'a pas besoin du modèle de langage.
SANS_MODELE = {"vecteurs"}


def executer(commande: list[str], sec: bool) -> int:
    """Lance une étape. En mode plan, on montre la commande sans l'exécuter."""
    affiche = " ".join(c.replace(str(RACINE) + "/", "") for c in commande)
    if sec:
        print(f"      $ {affiche}")
        return 0
    print(f"      $ {affiche}", flush=True)
    return subprocess.call(commande, cwd=RACINE)


def etape_vecteurs(doc_id: str, e: dict, sec: bool) -> str:
    manque = e["chunks"] - e["vectorises"]
    if manque <= 0:
        return "déjà fait"
    code = executer(
        [PYTHON, "pipeline/embed/embed.py", "--doc", doc_id[:8], "--lot", "128"], sec
    )
    return "planifié" if sec else ("fait" if code == 0 else "échec")


def etape_derive(doc_id: str, kind: str, e: dict, sec: bool) -> str:
    if e["manques"].get(kind, 0) == 0:
        return "déjà fait"
    if not os.getenv("ANTHROPIC_API_KEY"):
        return "clé absente"
    code = executer(
        [PYTHON, "pipeline/derive/derive.py", "--doc", doc_id[:8], "--kind", kind, "--sync"],
        sec,
    )
    return "planifié" if sec else ("fait" if code == 0 else "échec")


def traiter(conn, doc_id: str, etapes: list[str], sec: bool) -> dict:
    e = etat_document(conn, doc_id)
    if not e:
        return {}

    print(f"\n{e['titre']}")
    print(f"  {e['utiles']} chapitres exploitables · {e['chunks']} passages "
          f"· {e['vectorises']} vectorisés")
    if e["utiles"] == 0:
        print("  Aucun chapitre exploitable : l'extraction de structure doit passer avant.")
        return {"ignore": True}

    resultats = {}
    for etape in ORDRE:
        if etape not in etapes:
            continue
        manque = (e["chunks"] - e["vectorises"]) if etape == "vecteurs" \
            else e["manques"].get(etape, 0)
        if manque == 0:
            resultats[etape] = "déjà fait"
            continue

        cible = "passages" if etape == "vecteurs" else (
            "ouvrage" if ATTENDUS.get(etape) == "ouvrage" else "chapitres")
        print(f"    {etape:16} il manque {manque} {cible}")
        resultats[etape] = (
            etape_vecteurs(doc_id, e, sec) if etape == "vecteurs"
            else etape_derive(doc_id, etape, e, sec)
        )

    # L'import referme la boucle : ce qui vient d'être écrit dans data/ entre en base.
    if not sec and any(r == "fait" for k, r in resultats.items() if k not in SANS_MODELE):
        executer([PYTHON, "pipeline/derive/importer.py", "--doc", doc_id[:8]], sec=False)

    return resultats


def main() -> None:
    p = argparse.ArgumentParser(description="Amène un ouvrage à l'état complet.")
    p.add_argument("--doc", help="préfixe d'identifiant")
    p.add_argument("--tous", action="store_true", help="tout le corpus")
    p.add_argument("--etapes", default=",".join(ORDRE),
                   help="étapes à exécuter, séparées par des virgules")
    p.add_argument("--limite", type=int, default=0, help="nombre d'ouvrages à traiter")
    p.add_argument("--plan", action="store_true",
                   help="montrer ce qui serait fait, sans rien exécuter")
    a = p.parse_args()

    if not (a.doc or a.tous):
        p.error("préciser --doc ou --tous")

    etapes = [e.strip() for e in a.etapes.split(",") if e.strip()]
    inconnues = set(etapes) - set(ORDRE)
    if inconnues:
        p.error(f"étape inconnue : {', '.join(sorted(inconnues))}. Connues : {', '.join(ORDRE)}")

    if not a.plan and not os.getenv("ANTHROPIC_API_KEY") and set(etapes) - SANS_MODELE:
        print("ANTHROPIC_API_KEY n'est pas définie : seule la vectorisation "
              "sera exécutée. Utiliser --plan pour voir le travail restant.\n")

    conn = pg()
    with conn.cursor() as cur:
        if a.doc:
            cur.execute("select id from document where id::text like %s", (a.doc + "%",))
        else:
            cur.execute(
                """select d.id from document d
                    where d.takedown_status = 'none'
                      and exists (select 1 from chapter c
                                   where c.document_id = d.id and coalesce(c.token_count,0) >= 300)
                    order by d.title_clean"""
            )
        ids = [r[0] for r in cur.fetchall()]
    if a.limite:
        ids = ids[: a.limite]

    bilan: dict[str, int] = {}
    for doc_id in ids:
        for _etape, r in (traiter(conn, str(doc_id), etapes, a.plan) or {}).items():
            bilan[r] = bilan.get(r, 0) + 1

    print(f"\n{len(ids)} ouvrage(s) parcouru(s).")
    if bilan:
        print("  " + " · ".join(f"{k} : {v}" for k, v in sorted(bilan.items())))
    if a.plan:
        print("\n  Mode plan : rien n'a été exécuté.")


if __name__ == "__main__":
    main()
