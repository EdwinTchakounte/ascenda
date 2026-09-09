-- Migration 005 : rendre l'import des dérivés rejouable.
--
-- `data/` est la source de vérité, la base est la couche de service. Il faut
-- donc pouvoir rejouer l'import sans dupliquer. Aujourd'hui 4 214 lignes
-- couvrent 4 176 clés naturelles : 38 doublons produits par des enregistrements
-- successifs du même lot. Idempotente.

-- ============ 1. Traçabilité de l'origine ============
ALTER TABLE derivative ADD COLUMN IF NOT EXISTS content_hash TEXT;
ALTER TABLE derivative ADD COLUMN IF NOT EXISTS source_file  TEXT;
ALTER TABLE derivative ADD COLUMN IF NOT EXISTS imported_at  TIMESTAMPTZ;

COMMENT ON COLUMN derivative.content_hash IS
  'sha256 du contenu normalisé. Permet de sauter un import inchangé.';
COMMENT ON COLUMN derivative.source_file IS
  'Fichier de data/ dont ce dérivé provient. Vide si produit directement en base.';

-- ============ 2. Solder les doublons ============
-- On garde le plus récent de chaque clé et on marque les précédents comme
-- remplacés : `superseded_by` existe pour cela, on ne supprime rien.
WITH classes AS (
  SELECT id,
         first_value(id) OVER (
           PARTITION BY document_id,
                        coalesce(chapter_id, '00000000-0000-0000-0000-000000000000'::uuid),
                        kind
           ORDER BY generated_at DESC, id DESC
         ) AS gardee
    FROM derivative
   WHERE superseded_by IS NULL
)
UPDATE derivative d
   SET superseded_by = c.gardee
  FROM classes c
 WHERE d.id = c.id AND c.gardee <> d.id;

-- ============ 3. La contrainte qui empêche le retour du problème ============
CREATE UNIQUE INDEX IF NOT EXISTS ux_derivative_naturelle
  ON derivative (
    document_id,
    coalesce(chapter_id, '00000000-0000-0000-0000-000000000000'::uuid),
    kind
  )
  WHERE superseded_by IS NULL;

CREATE INDEX IF NOT EXISTS ix_derivative_source ON derivative(source_file)
  WHERE source_file IS NOT NULL;

-- ============ 4. Les types de dérivés attendus ============
-- `compte_rendu` rejoint la liste : c'est le document de restitution par
-- chapitre demandé pour le module par ouvrage.
ALTER TABLE derivative DROP CONSTRAINT IF EXISTS derivative_kind_check;
ALTER TABLE derivative ADD CONSTRAINT derivative_kind_check CHECK (kind IN (
  'synthese', 'quiz', 'flashcards', 'fiche_lecture',
  'resume_executif', 'citation', 'compte_rendu'
));
