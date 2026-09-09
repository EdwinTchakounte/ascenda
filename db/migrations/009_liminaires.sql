-- Les pages liminaires, écartées de la recherche.
--
-- La recherche sémantique remontait des pages de copyright en tête de
-- résultats : un lecteur qui cherchait « colonisation et mémoire » tombait
-- d'abord sur « Dépôt légal, ISBN, mise en page ». Le vecteur ne sait pas
-- qu'un colophon ne se lit pas, et le marquage d'appareil existant porte sur
-- les chapitres, pas sur les passages.
--
-- On marque donc une fois pour toutes, en colonne, plutôt que de filtrer par
-- ILIKE à chaque requête : sur onze mille passages, une condition textuelle
-- dans le WHERE ruine l'index HNSW.
--
-- Le marquage est délibérément étroit : quatre premières pages seulement, et
-- des formules qui n'apparaissent pratiquement que sur une page de garde.
-- Vingt-deux passages sur onze mille quatre cent trois.
--
-- Idempotente : rejouable sans dommage.

begin;

alter table chunk add column if not exists est_liminaire boolean not null default false;

update chunk k
   set est_liminaire = true
 where coalesce(k.page_start, 1) <= 4
   and (k.text ilike '%dépôt légal%'
        or k.text ilike '%catalogage avant publication%'
        or k.text ilike '%interdit de reproduire%'
        or k.text ilike '%mise en page%')
   and not k.est_liminaire;

-- Index partiel : la recherche ne demande que les passages non liminaires, et
-- ils sont l'immense majorité. Indexer le petit ensemble coûte quelques pages.
create index if not exists ix_chunk_liminaire on chunk (id) where est_liminaire;

commit;
