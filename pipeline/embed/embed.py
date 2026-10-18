"""Vectorisation du corpus ASCENDA."""
import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pipeline.common import PG, pg  # noqa: E402

MODELE = "intfloat/multilingual-e5-large"
DIMENSIONS = 1024

# e5 attend un préfixe explicite
PREFIXE_PASSAGE = "passage: "
PREFIXE_REQUETE = "query: "


def charger_modele(nom: str = MODELE):
    from sentence_transformers import SentenceTransformer

    print(f"Chargement de {nom} (premier appel : téléchargement d'environ 2 Go)...", flush=True)
    t0 = time.time()
    m = SentenceTransformer(nom)
    dim = m.get_sentence_embedding_dimension()
    if dim != DIMENSIONS:
        raise SystemExit(
            f"Le modèle produit {dim} dimensions, la colonne en attend {DIMENSIONS}. "
            f"Changer de modèle ou migrer la colonne, mais pas les deux à moitié."
        )
    print(f"Modèle prêt en {time.time() - t0:.0f} s, {dim} dimensions.", flush=True)
    return m


def chunks_a_traiter(conn, document: str | None, tout: bool) -> list[dict]:
    condition = "true" if tout else "k.embedding is null"
    params: list = []
    if document:
        condition += " and k.document_id::text like %s"
        params.append(f"{document}%")
    cur = conn.execute(
        f"""select k.id, k.text, k.content_hash
            from chunk k
            where {condition} and length(coalesce(k.text, '')) > 20
            order by k.document_id, k.ord""",
        params,
    )
    return cur.fetchall()


def vectoriser(lot_taille: int, document: str | None, tout: bool, modele_nom: str) -> None:
    from psycopg.rows import dict_row

    with pg() as conn:
        conn.row_factory = dict_row
        restants = chunks_a_traiter(conn, document, tout)
        total_corpus = conn.execute("select count(*) as n from chunk").fetchone()["n"]

    if not restants:
        print(f"Rien à faire : les {total_corpus} chunks ont déjà leur vecteur.")
        return

    print(f"{len(restants)} chunks à vectoriser sur {total_corpus}.", flush=True)
    modele = charger_modele(modele_nom)

    faits = 0
    t0 = time.time()
    for debut in range(0, len(restants), lot_taille):
        lot = restants[debut : debut + lot_taille]
        textes = [PREFIXE_PASSAGE + (c["text"] or "")[:1800] for c in lot]
        vecteurs = modele.encode(
            textes, batch_size=32, show_progress_bar=False, normalize_embeddings=True
        )
        with pg() as conn:
            with conn.cursor() as cur:
                for c, v in zip(lot, vecteurs):
                    cur.execute(
                        """update chunk
                              set embedding = %s::vector, embed_model = %s
                            where id = %s""",
                        ("[" + ",".join(f"{x:.6f}" for x in v) + "]", modele_nom, c["id"]),
                    )
            conn.commit()
        faits += len(lot)
        ecoule = time.time() - t0
        reste = (len(restants) - faits) * ecoule / max(1, faits)
        print(
            f"  {faits}/{len(restants)}  ({faits * 100 // len(restants)} %)  "
            f"{faits / max(ecoule, 1):.1f} chunks/s  reste ~{reste / 60:.0f} min",
            flush=True,
        )

    print(f"Terminé en {(time.time() - t0) / 60:.1f} min.")


def creer_index() -> None:
    """L'index HNSW ne se crée qu'une fois les vecteurs présents."""
    with pg() as conn:
        n = conn.execute("select count(*) from chunk where embedding is not null").fetchone()[0]
        if n == 0:
            print("Aucun vecteur : index non créé.")
            return
        print(f"Création de l'index HNSW sur {n} vecteurs (quelques minutes)...", flush=True)
        conn.execute(
            """create index if not exists ix_chunk_embedding
               on chunk using hnsw (embedding vector_cosine_ops)"""
        )
        conn.commit()
        print("Index prêt.")


def centroides_axes() -> None:
    """Le centroïde d'un axe est la moyenne des vecteurs de ses ouvrages."""
    with pg() as conn:
        conn.execute(
            """update axis a
                  set centroid = s.moyenne
                 from (
                   select da.axis_id, avg(k.embedding)::vector(1024) as moyenne
                     from document_axis da
                     join chunk k on k.document_id = da.document_id
                    where k.embedding is not null
                    group by da.axis_id
                 ) s
                where a.id = s.axis_id"""
        )
        conn.commit()
        n = conn.execute("select count(*) from axis where centroid is not null").fetchone()[0]
        print(f"{n} centroïdes d'axes calculés.")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description="Vectorise les chunks du corpus.")
    p.add_argument("--doc", help="préfixe d'identifiant de document (8 caractères)")
    p.add_argument("--lot", type=int, default=64, help="taille du lot d'écriture")
    p.add_argument("--tout", action="store_true", help="recalculer même les vecteurs existants")
    p.add_argument("--modele", default=MODELE)
    p.add_argument("--index", action="store_true", help="créer l'index HNSW puis sortir")
    p.add_argument("--centroides", action="store_true", help="calculer les centroïdes puis sortir")
    a = p.parse_args()

    print(f"Base : {PG['host']}:{PG['port']}/{PG['dbname']}", flush=True)
    if a.index:
        creer_index()
    elif a.centroides:
        centroides_axes()
    else:
        vectoriser(a.lot, a.doc, a.tout, a.modele)
