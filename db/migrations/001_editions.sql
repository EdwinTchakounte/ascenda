-- Éditions successives d'un même ouvrage : le sha256 ne les rapproche pas
-- (fichiers différents), mais pédagogiquement c'est un seul titre.
ALTER TABLE document ADD COLUMN IF NOT EXISTS supersedes_document_id UUID REFERENCES document(id);
COMMENT ON COLUMN document.supersedes_document_id IS
  'Édition antérieure du même ouvrage. La fiche de lecture est portée par l''édition la plus récente.';
CREATE INDEX IF NOT EXISTS ix_document_supersedes ON document(supersedes_document_id)
  WHERE supersedes_document_id IS NOT NULL;
