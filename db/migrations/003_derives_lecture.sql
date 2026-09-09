-- Migration 003 : deux valeurs dérivées que le pipeline n'avait pas posées et
-- dont l'API a besoin à chaque requête. Idempotente.

-- ============ 1. Durée par chapitre ============
-- chapter.token_count était NULL sur les 3 720 chapitres alors que chunk.token_count
-- est renseigné partout. Sans cette valeur, impossible de découper un chronogramme
-- en séances de 30 minutes ni d'afficher une durée dans le sommaire.
UPDATE chapter c
   SET token_count = s.tokens
  FROM (SELECT chapter_id, sum(token_count) AS tokens
          FROM chunk WHERE chapter_id IS NOT NULL GROUP BY chapter_id) s
 WHERE c.id = s.chapter_id AND c.token_count IS DISTINCT FROM s.tokens;

-- ============ 2. Type d'ouvrage normalisé ============
-- 25 valeurs libres pour 78 documents : inutilisable comme filtre. On normalise
-- dans une colonne dédiée sans écraser la valeur d'origine, comme title_raw.
ALTER TABLE document_pedagogy ADD COLUMN IF NOT EXISTS doc_type_norm TEXT;

UPDATE document_pedagogy SET doc_type_norm = CASE
  WHEN doc_type ILIKE '%roman%'   OR doc_type ILIKE '%conte%'                        THEN 'roman'
  WHEN doc_type ILIKE '%manuel%'                                                     THEN 'manuel'
  WHEN doc_type ILIKE '%cours%'   OR doc_type ILIKE '%formation%'
       OR doc_type ILIKE '%scolaire%' OR doc_type ILIKE '%universitaire%'            THEN 'cours'
  WHEN doc_type ILIKE '%rapport%'                                                    THEN 'rapport'
  WHEN doc_type ILIKE '%guide%'   OR doc_type ILIKE '%tutoriel%'                     THEN 'guide'
  WHEN doc_type ILIKE '%lexique%'                                                    THEN 'lexique'
  WHEN doc_type ILIKE '%recueil%' OR doc_type ILIKE '%beau livre%'                   THEN 'recueil'
  WHEN doc_type ILIKE '%resume%'  OR doc_type ILIKE '%résumé%'                       THEN 'resume'
  WHEN doc_type ILIKE '%essai%'   OR doc_type ILIKE '%opuscule%'                     THEN 'essai'
  ELSE 'essai'
END
WHERE doc_type IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_pedagogy_type ON document_pedagogy(doc_type_norm);
CREATE INDEX IF NOT EXISTS ix_pedagogy_level ON document_pedagogy(level);
