-- Migration 002 : ce dont l'API a besoin et que le schéma initial ne portait pas.
-- Idempotente : rejouable sans dommage.

-- ============ 1. Authentification ============
ALTER TABLE app_user ADD COLUMN IF NOT EXISTS password_hash  TEXT;
ALTER TABLE app_user ADD COLUMN IF NOT EXISTS is_active      BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE app_user ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE app_user ADD COLUMN IF NOT EXISTS last_login_at  TIMESTAMPTZ;
ALTER TABLE app_user ADD COLUMN IF NOT EXISTS locale         TEXT NOT NULL DEFAULT 'fr';

-- Le refresh token est stocké haché : une fuite de base ne donne pas de session.
CREATE TABLE IF NOT EXISTS refresh_token (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL UNIQUE,
  issued_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ NOT NULL,
  revoked_at  TIMESTAMPTZ,
  user_agent  TEXT,
  ip          TEXT
);
CREATE INDEX IF NOT EXISTS ix_refresh_user ON refresh_token(user_id) WHERE revoked_at IS NULL;

-- ============ 2. Recherche plein texte ancrée ============
-- Les embeddings ne sont pas encore calculés (0 / 11 395 chunks). En attendant,
-- la recherche s'appuie sur tsvector français + trigrammes, qui répondent en
-- quelques millisecondes et ne coûtent aucun appel externe.
ALTER TABLE chunk ADD COLUMN IF NOT EXISTS tsv tsvector
  GENERATED ALWAYS AS (to_tsvector('french', coalesce(text, ''))) STORED;
CREATE INDEX IF NOT EXISTS ix_chunk_tsv ON chunk USING gin (tsv);

CREATE INDEX IF NOT EXISTS ix_document_title_trgm
  ON document USING gin (coalesce(title_clean, title_raw) gin_trgm_ops);
CREATE INDEX IF NOT EXISTS ix_chapter_title_trgm
  ON chapter USING gin (coalesce(title, '') gin_trgm_ops);
CREATE INDEX IF NOT EXISTS ix_concept_term_trgm
  ON concept USING gin (term gin_trgm_ops);

-- ============ 3. Libellés d'axes lisibles ============
-- Les libellés issus du pipeline sont sans accents : ils partent à l'écran tels quels.
UPDATE axis SET label = v.label FROM (VALUES
  ('01-ia-fondamentaux-vulgarisation',     'Fondamentaux de l''IA'),
  ('02-ia-technique-academique',           'IA technique et académique'),
  ('03-ia-outils-pratique-prompting',      'Outils, pratique et prompting'),
  ('04-ia-societe-ethique-philosophie',    'IA, société et éthique'),
  ('05-ia-education-pedagogie',            'IA, éducation et pédagogie'),
  ('06-ia-travail-management-metiers',     'IA, travail et métiers'),
  ('07-afrique-histoire-pensee',           'Afrique, histoire et pensée'),
  ('08-litterature-romans',                'Littérature et romans'),
  ('09-developpement-personnel-influence', 'Développement personnel et influence'),
  ('10-economie-entrepreneuriat-finance',  'Économie, entrepreneuriat et finance'),
  ('11-sciences-environnement',            'Sciences et environnement')
) AS v(slug, label) WHERE axis.slug = v.slug;

-- ============ 4. Quotas freemium ============
-- Éditables en base sans redéploiement, comme prévu au modèle de données.
-- max_value NULL = illimité ; hard = false => on alerte sans bloquer.
INSERT INTO plan_quota (plan, type, period, max_value, hard) VALUES
  ('free',    'agent_question',      'day',   20,   true),
  ('free',    'doc_uploaded',        'month', 0,    true),
  ('free',    'ocr_pages',           'month', 0,    true),
  ('free',    'quiz_generated',      'month', 0,    true),
  ('free',    'synthesis_generated', 'month', 0,    true),
  ('free',    'chronogram_active',   'total', 1,    true),
  ('free',    'export_pdf',          'month', 0,    true),
  ('premium', 'agent_question',      'day',   400,  false),
  ('premium', 'doc_uploaded',        'month', 50,   true),
  ('premium', 'ocr_pages',           'month', 2000, true),
  ('premium', 'quiz_generated',      'month', NULL, false),
  ('premium', 'synthesis_generated', 'month', NULL, false),
  ('premium', 'chronogram_active',   'total', NULL, false),
  ('premium', 'export_pdf',          'month', NULL, false)
ON CONFLICT (plan, type, period) DO UPDATE
  SET max_value = EXCLUDED.max_value, hard = EXCLUDED.hard;

-- ============ 5. Diagnostic d'entrée ============
-- Les réponses au questionnaire sont conservées : elles justifient le niveau
-- attribué et permettront plus tard de réviser l'algorithme sur des cas réels.
CREATE TABLE IF NOT EXISTS assessment (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  answers      JSONB NOT NULL,
  level        TEXT,
  score        REAL,
  completed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_assessment_user ON assessment(user_id, completed_at DESC);

-- ============ 6. Surlignages ============
-- Distincts des notes : un surlignage n'a pas de corps de texte propre.
CREATE TABLE IF NOT EXISTS highlight (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  document_id UUID NOT NULL REFERENCES document(id) ON DELETE CASCADE,
  chunk_id    UUID REFERENCES chunk(id) ON DELETE SET NULL,
  page        INTEGER,
  quote       TEXT NOT NULL,
  color       TEXT NOT NULL DEFAULT 'or',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_highlight_user_doc ON highlight(user_id, document_id);

-- ============ 7. Compléments ============
ALTER TABLE note ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;
ALTER TABLE conversation ADD COLUMN IF NOT EXISTS title       TEXT;
ALTER TABLE conversation ADD COLUMN IF NOT EXISTS document_id UUID REFERENCES document(id) ON DELETE SET NULL;
ALTER TABLE conversation ADD COLUMN IF NOT EXISTS last_at     TIMESTAMPTZ NOT NULL DEFAULT now();
CREATE INDEX IF NOT EXISTS ix_conversation_user ON conversation(user_id, last_at DESC);
CREATE INDEX IF NOT EXISTS ix_message_conv ON message(conversation_id, at);
CREATE INDEX IF NOT EXISTS ix_note_user ON note(user_id, created_at DESC);
