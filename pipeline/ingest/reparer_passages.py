"""Reconstruit les passages d'un ouvrage dont le texte avait été jugé absent."""
import argparse
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RACINE / "pipeline"))
sys.path.insert(0, str(RACINE / "pipeline" / "ingest"))
from common import pg  # noqa: E402
from ingest import build_chunks, extract_epub, extract_pdf  # noqa: E402


def trouver_fichier(nom_original: str) -> Path | None:
    """Le fichier d'origine, cherché par son nom dans le corpus."""
    for p in (RACINE / "livres").rglob("*"):
        if p.is_file() and p.name == nom_original:
            return p
    # À défaut, la version passée à l'OCR, qui porte le même nom suffixé.
    tige = Path(nom_original).stem
    for p in (RACINE / "livres").rglob(f"{tige}*"):
        if p.is_file() and p.suffix.lower() in (".pdf", ".epub"):
            return p
    return None


def reparer(conn, doc_id, nom_original, plan: bool) -> dict:
    chemin = trouver_fichier(nom_original)
    if not chemin:
        return {"etat": "fichier introuvable", "passages": 0}

    if chemin.suffix.lower() == ".pdf":
        pages, _toc, _meta, n = extract_pdf(chemin)
    else:
        pages, _toc, _meta, n = extract_epub(chemin)

    caracteres = sum(len(p) for p in pages)
    morceaux = build_chunks(pages, [])
    if not morceaux:
        return {"etat": "aucun passage exploitable", "passages": 0,
                "caracteres": caracteres}

    if plan:
        return {"etat": "à réparer", "passages": len(morceaux),
                "caracteres": caracteres, "fichier": chemin.name}

    with conn.cursor() as cur:
        cur.execute("delete from chunk where document_id = %s", (doc_id,))
        for i, c in enumerate(morceaux):
            cur.execute(
                """insert into chunk (document_id, ord, page_start, page_end, text,
                                      token_count, content_hash, pipeline_version)
                   values (%s,%s,%s,%s,%s,%s,%s,1)""",
                (doc_id, i, c["page_start"], c["page_end"], c["text"],
                 c["token_count"], c["content_hash"]),
            )
        # Le document n'était pas scanné : il était simplement peu bavard.
        cur.execute(
            """update document
                  set has_text_layer = true, ocr_status = 'none',
                      extracted_chars = %s,
                      chars_per_page = %s,
                      ingested_at = now()
                where id = %s""",
            (caracteres, round(caracteres / max(1, n), 1), doc_id),
        )
    conn.commit()
    return {"etat": "réparé", "passages": len(morceaux), "caracteres": caracteres,
            "fichier": chemin.name}


def main() -> None:
    p = argparse.ArgumentParser(description="Reconstruit les passages manquants.")
    p.add_argument("--doc", help="préfixe d'identifiant")
    p.add_argument("--tous", action="store_true",
                   help="tous les documents sans passage mais avec un fichier")
    p.add_argument("--plan", action="store_true", help="montrer sans écrire")
    a = p.parse_args()
    if not (a.doc or a.tous):
        p.error("préciser --doc ou --tous")

    conn = pg()
    with conn.cursor() as cur:
        if a.doc:
            cur.execute(
                """select id, filename_original, coalesce(title_clean, title_raw)
                     from document where id::text like %s""", (a.doc + "%",))
        else:
            cur.execute(
                """select d.id, d.filename_original, coalesce(d.title_clean, d.title_raw)
                     from document d
                    where not exists (select 1 from chunk k where k.document_id = d.id)
                    order by d.page_count desc nulls last""")
        cibles = cur.fetchall()

    for doc_id, nom, titre in cibles:
        r = reparer(conn, doc_id, nom, a.plan)
        print(f"  {(titre or '')[:44]:44} {r['etat']:22} "
              f"{r['passages']:>4} passages  {r.get('caracteres', 0):>7} car.")
    if not cibles:
        print("  Aucun document sans passage.")


if __name__ == "__main__":
    main()
