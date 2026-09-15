"""Transférer un ouvrage d'une base à l'autre, avec ses identifiants.

`exporter-corpus.sh` transporte tout le corpus d'un coup et refuse une base qui
a déjà des ouvrages : il sert à monter un serveur neuf. Ajouter un ouvrage à un
serveur en service est un autre besoin. Réingérer le PDF sur le serveur ne
suffit pas : les chapitres y recevraient d'autres identifiants, et les quiz,
citations et fiches rédigés sur la machine de travail, rattachés aux chapitres
d'ici, ne s'y rattacheraient plus.

Ce qui part, dans une archive JSON compressée : l'ouvrage, sa pédagogie, ses
chapitres, ses passages (avec leurs vecteurs), ses rattachements aux axes et ses
dérivés. Les axes voyagent par leur raccourci (`12-3-protection-cultures`) :
leurs identifiants diffèrent d'une base à l'autre. Ce qui ne part jamais :
comptes, séances, progression, notes.

À l'import, tout se fait dans une transaction. Un ouvrage déjà présent n'est
remplacé qu'avec `--remplacer`, et seulement si aucun lecteur n'y a encore de
séance, de note ou de surlignage : le remplacement efface en cascade.

    python -m app.outils.transferer_ouvrage exporter 0ff947f7 memento.json.gz
    python -m app.outils.transferer_ouvrage importer memento.json.gz --essai
    python -m app.outils.transferer_ouvrage importer memento.json.gz --pdf /tmp/Memento.pdf
"""
import argparse
import asyncio
import gzip
import json
import sys

from app.core.db import close_pool, connection, fetch_all, fetch_one, open_pool

VERSION = 1

# (table, requête d'export). `to_jsonb` garde chaque colonne telle quelle ;
# la colonne calculée `chunk.tsv` est retirée, la base d'arrivée la recalcule.
EXPORTS = [
    ("document", "select to_jsonb(t) from document t where id = %(d)s"),
    ("document_pedagogy", "select to_jsonb(t) from document_pedagogy t where document_id = %(d)s"),
    ("document_prerequisite", "select to_jsonb(t) from document_prerequisite t where document_id = %(d)s"),
    ("chapter", "select to_jsonb(t) from chapter t where document_id = %(d)s order by ord"),
    ("chunk", "select to_jsonb(t) - 'tsv' from chunk t where document_id = %(d)s order by ord"),
    ("derivative", "select to_jsonb(t) from derivative t where document_id = %(d)s order by generated_at"),
]
# Les tables qu'un lecteur alimente : un ouvrage qui en porte ne se remplace pas.
USAGES = [
    ("session", "select count(*) as n from session where document_id = %s"),
    ("note", "select count(*) as n from note n join chunk k on k.id = n.chunk_id where k.document_id = %s"),
    ("highlight", "select count(*) as n from highlight h join chunk k on k.id = h.chunk_id where k.document_id = %s"),
    ("progress_event", "select count(*) as n from progress_event where document_id = %s"),
]


async def exporter(prefixe: str, fichier: str) -> None:
    doc = await fetch_one("select id, title_clean from document where id::text like %s", (prefixe + "%",))
    if not doc:
        sys.exit(f"Aucun ouvrage ne commence par {prefixe}.")
    d = str(doc["id"])
    archive = {"version": VERSION, "document_id": d, "titre": doc["title_clean"], "tables": {}}
    for table, sql in EXPORTS:
        lignes = await fetch_all(sql, {"d": d})
        archive["tables"][table] = [list(l.values())[0] for l in lignes]
    archive["document_axis"] = [dict(l) for l in await fetch_all(
        """select a.slug, da.weight, da.assigned_by, da.confidence from document_axis da
             join axis a on a.id = da.axis_id where da.document_id = %s""", (d,))]
    archive["axis_chapter"] = [dict(l) for l in await fetch_all(
        """select a.slug, ac.chapter_id::text as chapter_id from axis_chapter ac
             join axis a on a.id = ac.axis_id join chapter c on c.id = ac.chapter_id
            where c.document_id = %s""", (d,))]
    # Les notions de la fiche de lecture vivent dans `concept`, sans lien à l'ouvrage.
    termes = [c["terme"] for dv in archive["tables"]["derivative"] if dv["kind"] == "fiche_lecture"
              for c in (dv["content"] or {}).get("concepts_cles", [])]
    archive["concept"] = [dict(l) for l in await fetch_all(
        "select term, definition from concept where term = any(%s)", (termes,))] if termes else []
    with gzip.open(fichier, "wt", encoding="utf-8") as f:
        json.dump(archive, f, ensure_ascii=False, default=str)
    compte = {t: len(v) for t, v in archive["tables"].items()}
    print(f"« {doc['title_clean']} » exporté dans {fichier} : {compte}, "
          f"{len(archive['document_axis'])} axes, {len(archive['axis_chapter'])} chapitres rattachés.")


async def inserer(conn, table: str, lignes: list[dict]) -> None:
    for ligne in lignes:
        await conn.execute(
            f"insert into {table} select * from jsonb_populate_record(null::{table}, %s::jsonb)"
            if table != "chunk" else
            # `tsv` est calculée : on nomme les colonnes au lieu de `select *`.
            """insert into chunk (id, document_id, chapter_id, ord, page_start, page_end, text, token_count,
                                  content_hash, pipeline_version, embedding, embed_model, est_liminaire)
               select id, document_id, chapter_id, ord, page_start, page_end, text, token_count,
                      content_hash, pipeline_version, embedding, embed_model, est_liminaire
                 from jsonb_populate_record(null::chunk, %s::jsonb)""",
            (json.dumps(ligne, ensure_ascii=False),),
        )


def deposer_pdf(chemin: str, storage_key: str) -> None:
    """Le PDF d'origine dans le stockage objet, à la clé que porte l'ouvrage.

    La console le sert depuis là ; l'API ne l'expose au lecteur que si les
    droits de l'ouvrage le permettent."""
    from minio import Minio

    from app.core.config import settings

    client = Minio(settings.minio_endpoint, access_key=settings.minio_root_user,
                   secret_key=settings.minio_root_password, secure=settings.minio_secure)
    client.fput_object(settings.minio_bucket, storage_key, chemin, content_type="application/pdf")
    print(f"PDF déposé : {storage_key}")


async def importer(fichier: str, essai: bool, remplacer: bool, pdf: str | None = None) -> None:
    with gzip.open(fichier, "rt", encoding="utf-8") as f:
        archive = json.load(f)
    if archive.get("version") != VERSION:
        sys.exit(f"Archive en version {archive.get('version')}, cet outil lit la version {VERSION}.")
    d = archive["document_id"]
    t = archive["tables"]
    slugs = {x["slug"] for x in archive["document_axis"]} | {x["slug"] for x in archive["axis_chapter"]}
    connus = {l["slug"]: l["id"] for l in await fetch_all("select id, slug from axis where slug = any(%s)", (list(slugs),))}
    manquants = sorted(slugs - set(connus))
    if manquants:
        sys.exit(f"Axes absents de cette base : {manquants}. Appliquer d'abord les migrations.")

    present = await fetch_one("select id from document where id = %s or sha256 = %s",
                              (d, t["document"][0]["sha256"]))
    if present and not remplacer:
        sys.exit("L'ouvrage est déjà dans cette base. Relancer avec --remplacer pour le remplacer.")
    if present:
        usages = {nom: (await fetch_one(sql, (str(present["id"]),)))["n"] for nom, sql in USAGES}
        if any(usages.values()):
            sys.exit(f"Des lecteurs utilisent déjà cet ouvrage ({usages}) : remplacement refusé.")

    print(f"« {archive['titre']} » : {len(t['chapter'])} chapitres, {len(t['chunk'])} passages, "
          f"{len(t['derivative'])} dérivés, {len(archive['axis_chapter'])} rattachements de chapitres.")
    if essai:
        print("Essai : rien n'est écrit." + (" L'ouvrage présent serait remplacé." if present else ""))
        return

    async with connection() as conn:
        if present:
            await conn.execute("delete from derivative where document_id = %s", (str(present["id"]),))
            await conn.execute("delete from document where id = %s", (str(present["id"]),))
        await inserer(conn, "document", t["document"])
        await inserer(conn, "document_pedagogy", t["document_pedagogy"])
        await inserer(conn, "document_prerequisite", t["document_prerequisite"])
        # Les chapitres se référencent entre eux : parents posés après coup.
        parents = {c["id"]: c.get("parent_id") for c in t["chapter"]}
        await inserer(conn, "chapter", [{**c, "parent_id": None} for c in t["chapter"]])
        for cid, pid in parents.items():
            if pid:
                await conn.execute("update chapter set parent_id = %s where id = %s", (pid, cid))
        await inserer(conn, "chunk", t["chunk"])
        # Un dérivé peut en remplacer un autre : les plus anciens d'abord, lien posé ensuite.
        remplaces = {x["id"]: x.get("superseded_by") for x in t["derivative"]}
        await inserer(conn, "derivative", [{**x, "superseded_by": None} for x in t["derivative"]])
        for did, sid in remplaces.items():
            if sid:
                await conn.execute("update derivative set superseded_by = %s where id = %s", (sid, did))
        for x in archive["document_axis"]:
            await conn.execute(
                """insert into document_axis (document_id, axis_id, weight, assigned_by, confidence)
                   values (%s, %s, %s, %s, %s)""",
                (d, connus[x["slug"]], x["weight"], x["assigned_by"], x["confidence"]))
        for x in archive["axis_chapter"]:
            await conn.execute("insert into axis_chapter (axis_id, chapter_id) values (%s, %s) on conflict do nothing",
                               (connus[x["slug"]], x["chapter_id"]))
        for c in archive["concept"]:
            await conn.execute("insert into concept (term, definition) values (%s, %s) on conflict (term) do nothing",
                               (c["term"], c["definition"]))
    verif = await fetch_one(
        """select (select count(*) from chapter where document_id = %(d)s) as chapitres,
                  (select count(*) from chunk where document_id = %(d)s) as passages,
                  (select count(*) from chunk where document_id = %(d)s and embedding is not null) as vecteurs,
                  (select count(*) from derivative where document_id = %(d)s) as derives""", {"d": d})
    print(f"Importé : {dict(verif)}")
    if pdf:
        deposer_pdf(pdf, t["document"][0]["storage_key"])


async def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sp = p.add_subparsers(dest="action", required=True)
    e = sp.add_parser("exporter"); e.add_argument("document"); e.add_argument("fichier")
    i = sp.add_parser("importer"); i.add_argument("fichier")
    i.add_argument("--essai", action="store_true"); i.add_argument("--remplacer", action="store_true")
    i.add_argument("--pdf", help="chemin du PDF d'origine, à déposer dans le stockage objet")
    a = p.parse_args()
    await open_pool()
    try:
        if a.action == "exporter":
            await exporter(a.document, a.fichier)
        else:
            await importer(a.fichier, a.essai, a.remplacer, a.pdf)
    finally:
        await close_pool()


if __name__ == "__main__":
    asyncio.run(main())
