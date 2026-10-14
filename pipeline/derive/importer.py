"""Import de `data/` vers la base, rejouable."""
import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import DATA, pg  # noqa: E402

MODELE_SESSION = "claude-opus-5 (hors API)"
NIL = "00000000-0000-0000-0000-000000000000"


def empreinte(contenu) -> str:
    """Empreinte stable du contenu, insensible à l'ordre des clés."""
    canon = json.dumps(contenu, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canon.encode()).hexdigest()


class Referentiel:
    """Les identifiants de la base, chargés une fois."""

    def __init__(self, conn):
        self.chapitres: dict[str, dict[str, str]] = {}
        self.titres: dict[str, str] = {}
        self.documents: set[str] = set()
        with conn.cursor() as cur:
            cur.execute("select id, title_clean, title_raw from document")
            for did, tc, tr in cur.fetchall():
                self.documents.add(str(did))
                for t in (tc, tr):
                    if t:
                        self.titres.setdefault(t.strip().lower(), str(did))
            cur.execute("select id, document_id from chapter")
            for cid, did in cur.fetchall():
                self.chapitres.setdefault(str(did), {})[str(cid)] = str(cid)

    def document(self, prefixe: str) -> str | None:
        for d in self.documents:
            if d.startswith(prefixe):
                return d
        return None

    def chapitre(self, document_id: str, prefixe: str) -> str | None:
        cibles = [c for c in self.chapitres.get(document_id, {}) if c.startswith(prefixe)]
        return cibles[0] if len(cibles) == 1 else None

    def par_titre(self, titre: str) -> str | None:
        return self.titres.get((titre or "").strip().lower())


def deposer(conn, *, document_id, chapter_id, kind, contenu, fichier, bilan, ecrire=True):
    """Pose un dérivé sur sa clé naturelle. Ne réécrit que si le contenu a changé."""
    h = empreinte(contenu)
    with conn.cursor() as cur:
        cur.execute(
            """select id, content_hash from derivative
               where document_id = %s
                 and coalesce(chapter_id, %s::uuid) = coalesce(%s::uuid, %s::uuid)
                 and kind = %s and superseded_by is null""",
            (document_id, NIL, chapter_id, NIL, kind),
        )
        existant = cur.fetchone()

        if existant and existant[1] == h:
            bilan["inchangés"] += 1
            return
        if not ecrire:
            bilan["à modifier" if existant else "à insérer"] += 1
            return

        charge = json.dumps(contenu, ensure_ascii=False)
        if existant:
            cur.execute(
                """update derivative
                      set content = %s, content_hash = %s, source_file = %s,
                          imported_at = now(), generated_at = now()
                    where id = %s""",
                (charge, h, fichier, existant[0]),
            )
            bilan["modifiés"] += 1
        else:
            cur.execute(
                """insert into derivative (document_id, chapter_id, kind, content,
                                           model_id, prompt_version, content_hash,
                                           source_file, imported_at)
                   values (%s, %s, %s, %s, %s, 'v1', %s, %s, now())""",
                (document_id, chapter_id, kind, charge, MODELE_SESSION, h, fichier),
            )
            bilan["insérés"] += 1


def importer_lots(conn, ref, dossier, motif, kind, cle_liste, bilan, doc_filtre, ecrire):
    """Les quiz et les citations arrivent par lots : un fichier, plusieurs chapitres."""
    for f in sorted((DATA / dossier).glob(motif)):
        m = re.match(rf"[qc]_([0-9a-f]{{8}})_\d+\.json$", f.name)
        if not m:
            bilan["ignorés"] += 1
            continue
        prefixe = m.group(1)
        if doc_filtre and not prefixe.startswith(doc_filtre[:8]):
            continue
        document_id = ref.document(prefixe)
        if not document_id:
            bilan["document introuvable"] += 1
            continue

        for bloc in json.loads(f.read_text()):
            court = str(bloc.get("chapitre", ""))
            chapter_id = ref.chapitre(document_id, court)
            if not chapter_id:
                bilan["chapitre introuvable"] += 1
                continue
            contenu = {cle_liste: bloc.get(cle_liste, [])}
            if bloc.get("motif"):
                contenu["motif"] = bloc["motif"]
            deposer(
                conn, document_id=document_id, chapter_id=chapter_id, kind=kind,
                contenu=contenu, fichier=f.name, bilan=bilan, ecrire=ecrire,
            )


def importer_fiches(conn, ref, bilan, doc_filtre, ecrire):
    """La fiche porte son `document_id` : le rattachement ne dépend donc pas du titre, qui peut
    diverger entre le fichier et la base. À défaut d'identifiant, on retombe sur le titre
    normalisé, et les cas non résolus sont signalés, jamais devinés.
    """
    non_resolues = []
    for f in sorted((DATA / "derivatives").glob("fiche_*.json")):
        contenu = json.loads(f.read_text())
        document_id = contenu.get("document_id") or ref.par_titre(
            contenu.get("titre_normalise", "")
        )
        if document_id and document_id not in ref.documents:
            document_id = None
        if not document_id:
            non_resolues.append((f.name, contenu.get("titre_normalise", "")))
            bilan["document introuvable"] += 1
            continue
        if doc_filtre and not document_id.startswith(doc_filtre[:8]):
            continue
        deposer(
            conn, document_id=document_id, chapter_id=None, kind="fiche_lecture",
            contenu=contenu, fichier=f.name, bilan=bilan, ecrire=ecrire,
        )
    return non_resolues


def exporter(conn, ref, doc_filtre) -> None:
    """Écrit dans `data/` les dérivés qui n'existent qu'en base."""
    condition = "d.source_file is null and d.superseded_by is null"
    params: list = []
    if doc_filtre:
        condition += " and d.document_id::text like %s"
        params.append(f"{doc_filtre}%")

    with conn.cursor() as cur:
        cur.execute(
            f"""select d.id, d.document_id, d.chapter_id, d.kind, d.content, c.ord
                from derivative d left join chapter c on c.id = d.chapter_id
                where {condition} and d.kind in ('quiz', 'citation')
                order by d.document_id, c.ord nulls last""",
            params,
        )
        lignes = cur.fetchall()

    if not lignes:
        print("Rien à exporter : tout dérivé est déjà adossé à un fichier.")
        return

    par_doc: dict[tuple[str, str], list] = {}
    for did, docid, chapid, kind, contenu, _ord in lignes:
        par_doc.setdefault((str(docid), kind), []).append((did, str(chapid), contenu))

    ecrits = 0
    for (docid, kind), blocs in sorted(par_doc.items()):
        dossier, prefixe, cle = (
            ("quiz", "q", "questions") if kind == "quiz" else ("citations", "c", "citations")
        )
        court = docid[:8]
        # On repart après le dernier lot existant pour ne rien écraser.
        existants = sorted((DATA / dossier).glob(f"{prefixe}_{court}_*.json"))
        suivant = 1
        if existants:
            suivant = max(int(f.stem.rsplit("_", 1)[1]) for f in existants) + 1
        chemin = DATA / dossier / f"{prefixe}_{court}_{suivant:02d}.json"

        lot = []
        for _did, chapid, contenu in blocs:
            bloc = {"chapitre": chapid[:8], cle: (contenu or {}).get(cle, [])}
            if (contenu or {}).get("motif"):
                bloc["motif"] = contenu["motif"]
            lot.append(bloc)
        chemin.write_text(json.dumps(lot, ensure_ascii=False, indent=1))

        with conn.cursor() as cur:
            cur.execute(
                "update derivative set source_file = %s where id = any(%s)",
                (chemin.name, [b[0] for b in blocs]),
            )
        ecrits += 1
        print(f"  {chemin.name} : {len(lot)} bloc(s)")

    conn.commit()
    print(f"\n{ecrits} fichier(s) écrit(s) dans data/.")


def main() -> None:
    p = argparse.ArgumentParser(description="Importe data/ vers la base, sans doublon.")
    p.add_argument("--doc", help="limiter à un document (préfixe)")
    p.add_argument("--verifier", action="store_true", help="ne rien écrire, dire ce qui bougerait")
    p.add_argument("--exporter", action="store_true",
                   help="écrire dans data/ les dérivés qui n'existent qu'en base")
    a = p.parse_args()
    ecrire = not a.verifier

    conn = pg()
    ref = Referentiel(conn)
    bilan: Counter = Counter()

    if a.exporter:
        exporter(conn, ref, a.doc)
        return

    importer_lots(conn, ref, "quiz", "q_*.json", "quiz", "questions", bilan, a.doc, ecrire)
    importer_lots(conn, ref, "citations", "c_*.json", "citation", "citations", bilan, a.doc, ecrire)
    non_resolues = importer_fiches(conn, ref, bilan, a.doc, ecrire)

    if ecrire:
        conn.commit()

    entete = "État des lieux (rien écrit)" if a.verifier else "Import terminé"
    print(f"\n{entete}")
    for cle in ("insérés", "modifiés", "inchangés", "à insérer", "à modifier",
                "document introuvable", "chapitre introuvable", "ignorés"):
        if bilan[cle]:
            print(f"  {cle:22} {bilan[cle]:>5}")

    if non_resolues:
        print(f"\n  {len(non_resolues)} fiche(s) non rattachée(s) :")
        for nom, titre in non_resolues:
            print(f"    {nom} : « {titre[:60]} »")
        print("    Le titre normalisé ne correspond à aucun document. "
              "Corriger le titre dans le fichier ou en base.")


if __name__ == "__main__":
    main()
