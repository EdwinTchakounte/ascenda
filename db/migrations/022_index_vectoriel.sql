-- Un index sur les vecteurs des passages.
--
-- La recherche sémantique compare la question à chaque passage avec la
-- distance cosinus de pgvector. Sans index, Postgres lit les 12 921 vecteurs
-- de 1 024 dimensions à chaque question. C'est tenable aujourd'hui, et c'est
-- le premier mur quand le corpus double : le coût croît linéairement alors
-- qu'un index HNSW le rend logarithmique.
--
-- HNSW plutôt qu'IVFFlat : il ne demande pas de choisir un nombre de listes
-- adapté au volume, donc il ne se dégrade pas à mesure que le corpus grandit,
-- et il répond mieux quand la recherche est filtrée par ouvrage ou par axe,
-- ce qui est le cas courant ici.
--
-- L'index est approché : il peut manquer un voisin. On relève donc
-- `hnsw.ef_search` au-delà du défaut pour la recherche, le temps gagné restant
-- large. `m` et `ef_construction` sont laissés par défaut, 16 et 64 : à cette
-- taille de corpus, les monter allonge la construction sans rien rendre.
--
-- Idempotente : rejouable sans dommage.

begin;

create index if not exists ix_chunk_embedding_hnsw
  on chunk using hnsw (embedding vector_cosine_ops);

commit;
