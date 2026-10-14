#!/usr/bin/env python3
"""Ingère un ouvrage selon une structure relue à la main."""
import argparse
import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import LIVRES, pg, s3  # noqa: E402
import ingest  # noqa: E402


def verifier(structure: dict, n_pages: int) -> list[str]:
    """Ce qui rendrait la structure fausse, avant d'écrire quoi que ce soit."""
    pb = []
    precedent = 0
    for i, c in enumerate(structure["chapitres"]):
        if not (1 <= c["page"] <= n_pages):
            pb.append(f"{c['titre']} : page {c['page']} hors du document ({n_pages} pages)")
        if c["page"] < precedent:
            pb.append(f"{c['titre']} : page {c['page']} avant la précédente ({precedent})")
        precedent = c["page"]
        if i and c["niveau"] > structure["chapitres"][i - 1]["niveau"] + 1:
            pb.append(f"{c['titre']} : saute du niveau {structure['chapitres'][i - 1]['niveau']} au niveau {c['niveau']}")
    return pb


def appliquer(conn, doc_id, structure: dict) -> dict:
    chapitres_json = structure["chapitres"]
    with conn.cursor() as cur:
        cur.execute("select id, ord from chapter where document_id = %s order by ord", (doc_id,))
        ids = [r[0] for r in cur.fetchall()]
        if len(ids) != len(chapitres_json):
            raise SystemExit(f"{len(ids)} chapitres en base pour {len(chapitres_json)} décrits : rien n'est rattaché.")

        # Les titres relus : la structure peut les corriger sans réingérer.
        for cid, c in zip(ids, chapitres_json):
            cur.execute("update chapter set title = %s where id = %s and title is distinct from %s",
                        (c["titre"], cid, c["titre"]))

        # La hiérarchie : chaque chapitre a pour parent le dernier de niveau inférieur.
        pile: list[tuple[int, object]] = []
        for cid, c in zip(ids, chapitres_json):
            while pile and pile[-1][0] >= c["niveau"]:
                pile.pop()
            cur.execute("update chapter set parent_id = %s where id = %s", (pile[-1][1] if pile else None, cid))
            pile.append((c["niveau"], cid))

        cur.execute("""update chapter c set token_count = coalesce(s.n, 0)
                         from (select c2.id, sum(k.token_count) as n from chapter c2
                                 left join chunk k on k.chapter_id = c2.id
                                where c2.document_id = %s group by c2.id) s
                        where c.id = s.id""", (doc_id,))

        # Les axes : l'ouvrage entre dans chaque sous-axe cité, borné à ses chapitres.
        cur.execute("delete from document_axis where document_id = %s", (doc_id,))
        cur.execute("delete from axis_chapter where chapter_id = any(%s)", (ids,))
        par_axe = Counter()
        for cid, c in zip(ids, chapitres_json):
            if not c.get("axe"):
                continue
            cur.execute("select id from axis where slug = %s", (c["axe"],))
            a = cur.fetchone()
            if not a:
                raise SystemExit(f"Axe inconnu : {c['axe']} (migration 018 appliquée ?)")
            cur.execute("insert into axis_chapter (axis_id, chapter_id) values (%s, %s) on conflict do nothing", (a[0], cid))
            par_axe[c["axe"]] += 1
        for slug in par_axe:
            cur.execute("""insert into document_axis (document_id, axis_id, weight, assigned_by, confidence)
                           select %s, id, 1.0, 'curator', 1.0 from axis where slug = %s""", (doc_id, slug))

        cur.execute("""insert into document_pedagogy (document_id, reading_time_min)
                       select d.id, round(greatest(coalesce(sum(k.token_count), 0), d.page_count * 60) * 0.75 / 200)
                         from document d left join chunk k on k.document_id = d.id
                        where d.id = %s group by d.id
                       on conflict (document_id) do update set reading_time_min = excluded.reading_time_min""",
                    (doc_id,))

        cur.execute("""update document set title_clean = %s, authors = %s, year = %s, publisher = %s,
                              language = %s, biblio_confidence = 1.0, biblio_validated = true
                        where id = %s""",
                    (structure["titre"], json.dumps(structure.get("auteurs") or []), structure.get("annee"),
                     structure.get("editeur"), structure.get("langue") or "fr", doc_id))
    conn.commit()
    return dict(par_axe)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("structure", type=Path)
    ap.add_argument("--plan", action="store_true", help="vérifier la structure sans rien écrire")
    ap.add_argument("--force", action="store_true", help="réingérer même si l'ouvrage est déjà en base")
    a = ap.parse_args()

    structure = json.loads(a.structure.read_text())
    fichier = (LIVRES / structure["fichier"]).resolve()
    if not str(fichier).startswith(str(LIVRES.resolve())) or not fichier.is_file():
        raise SystemExit(f"Fichier introuvable dans livres/ : {structure['fichier']}")

    import pymupdf
    n_pages = pymupdf.open(fichier).page_count
    pb = verifier(structure, n_pages)
    if pb:
        print("Structure refusée :")
        for p in pb:
            print("  ", p)
        raise SystemExit(1)
    print(f"Structure vérifiée : {len(structure['chapitres'])} chapitres sur {n_pages} pages.")
    if a.plan:
        print(Counter(c.get("axe") for c in structure["chapitres"]))
        return

    # L'ingestion lit le sommaire interne du PDF : on lui donne le nôtre à la place.
    sommaire = [[c["niveau"], c["titre"], c["page"]] for c in structure["chapitres"]]
    extraire = ingest.extract_pdf

    def extraire_avec_sommaire(path):
        pages, _toc, meta, n = extraire(path)
        return pages, sommaire, meta, n

    ingest.extract_pdf = extraire_avec_sommaire
    pole = structure.get("pole", "12-agriculture-elevage")
    conn, client = pg(), s3()
    statut, doc_id, n = ingest.ingest_one(conn, client, fichier, pole, a.force)
    if statut == "skip":
        with conn.cursor() as cur:
            cur.execute("select id from document where sha256 = %s and owner_id is null", (ingest.sha256_file(fichier),))
            doc_id = cur.fetchone()[0]
        print("Déjà ingéré à cette version : structure et axes réappliqués.")
    else:
        print(f"Ingéré : {n} passages.")
    axes = appliquer(conn, doc_id, structure)
    print(f"Document {doc_id}")
    for slug, k in sorted(axes.items()):
        print(f"  {slug} : {k} chapitres")
    conn.close()


if __name__ == "__main__":
    main()
