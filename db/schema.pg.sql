-- ASCENDA : schema PostgreSQL (canonique). Genere depuis db/schema.sql
-- Prerequis : extensions vector, pg_trgm, unaccent, uuid-ossp (infra/docker/initdb)
SET client_min_messages = warning;


-- ============ SYNCHRO (à porter sur toute nouvelle table) ============
--   origin_node TEXT, synced_at TIMESTAMPTZ, dirty BOOLEAN DEFAULT 1

-- ============ AXES ============
CREATE TABLE axis (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  slug              TEXT NOT NULL UNIQUE,        -- 04-ia-societe-ethique-philosophie
  label             TEXT NOT NULL,
  description       TEXT,
  parent_id         UUID REFERENCES axis(id),
  centroid          vector(1024),                        -- pour le classement auto à l'upload
  sort_order        INTEGER,
  is_premium        BOOLEAN NOT NULL DEFAULT false
);

-- ============ UTILISATEURS ============
CREATE TABLE app_user (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email         TEXT UNIQUE,
  display_name  TEXT,
  plan          TEXT NOT NULL DEFAULT 'free' CHECK (plan IN ('free','premium','team')),
  plan_since    TIMESTAMPTZ,
  plan_until    TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  origin_node   TEXT, synced_at TIMESTAMPTZ, dirty BOOLEAN NOT NULL DEFAULT true
);

-- ============ DOCUMENT : couches 1,2,3,7 ============
CREATE TABLE document (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  -- C1 identité
  sha256            TEXT NOT NULL,
  filename_original TEXT NOT NULL,
  mime              TEXT NOT NULL,
  size_bytes        INTEGER NOT NULL,
  page_count        INTEGER,
  language          TEXT,
  source            TEXT NOT NULL CHECK (source IN ('corpus_base','upload_user')),
  owner_id          UUID REFERENCES app_user(id),
  visibility        TEXT NOT NULL DEFAULT 'private'
                      CHECK (visibility IN ('public','private','shared')),
  storage_key       TEXT NOT NULL,               -- chemin local puis clé S3/R2
  added_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- C2 bibliographique
  title_raw         TEXT,
  title_clean       TEXT,
  subtitle          TEXT,
  authors           JSONB,                        -- JSON []
  publisher         TEXT,
  year              INTEGER,
  isbn              TEXT,
  edition           TEXT,
  translator        TEXT,
  collection        TEXT,
  biblio_confidence REAL,                        -- 0..1 ; < 0.6 => file de validation
  biblio_validated  BOOLEAN NOT NULL DEFAULT false,
  -- C3 ingestion
  has_text_layer    BOOLEAN,
  ocr_status        TEXT NOT NULL DEFAULT 'none'
                      CHECK (ocr_status IN ('none','needed','running','done','failed')),
  ocr_engine        TEXT,
  extraction_engine TEXT,
  extracted_chars   INTEGER,
  chars_per_page    REAL,                        -- < 400 => ocr_status = 'needed'
  quality_score     REAL,
  ingested_at       TIMESTAMPTZ,
  pipeline_version  INTEGER NOT NULL DEFAULT 0,  -- ré-ingestion incrémentale
  -- C7 droits
  copyright_status  TEXT NOT NULL DEFAULT 'unknown'
                      CHECK (copyright_status IN
                        ('unknown','public_domain','institutional','licensed','restricted')),
  license           TEXT,
  redistributable   BOOLEAN NOT NULL DEFAULT false,
  max_excerpt_chars INTEGER NOT NULL DEFAULT 1200,
  takedown_status   TEXT NOT NULL DEFAULT 'none',
  -- synchro
  origin_node       TEXT, synced_at TIMESTAMPTZ, dirty BOOLEAN NOT NULL DEFAULT true
);
CREATE UNIQUE INDEX ux_document_sha ON document(sha256, COALESCE(owner_id, '00000000-0000-0000-0000-000000000000'::uuid));
CREATE INDEX ix_document_pipeline  ON document(pipeline_version);
CREATE INDEX ix_document_ocr       ON document(ocr_status) WHERE ocr_status <> 'done';

-- ============ C4 pédagogique ============
CREATE TABLE document_axis (             -- multi-label : un doc a plusieurs axes
  document_id   UUID NOT NULL REFERENCES document(id) ON DELETE CASCADE,
  axis_id       UUID NOT NULL REFERENCES axis(id) ON DELETE CASCADE,
  weight        REAL NOT NULL DEFAULT 1.0,
  assigned_by   TEXT NOT NULL DEFAULT 'auto' CHECK (assigned_by IN ('auto','user','curator')),
  confidence    REAL,
  PRIMARY KEY (document_id, axis_id)
);

CREATE TABLE document_pedagogy (
  document_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4() REFERENCES document(id) ON DELETE CASCADE,
  level            TEXT CHECK (level IN ('debutant','intermediaire','avance')),
  doc_type         TEXT,                 -- essai|manuel|cours|roman|rapport|guide
  target_audience  TEXT,
  reading_time_min INTEGER,
  concept_density  REAL,
  central_thesis   TEXT,
  key_ideas        JSONB                  -- JSON []
);

CREATE TABLE document_prerequisite (
  document_id      UUID NOT NULL REFERENCES document(id) ON DELETE CASCADE,
  prerequisite_id  UUID NOT NULL REFERENCES document(id) ON DELETE CASCADE,
  strength         TEXT DEFAULT 'recommande' CHECK (strength IN ('requis','recommande')),
  PRIMARY KEY (document_id, prerequisite_id)
);

-- Mise en regard des thèses opposées (Bostrom vs « L'IA n'existe pas », Sadin vs Alexandre)
CREATE TABLE controversy (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  axis_id     UUID REFERENCES axis(id),
  question    TEXT NOT NULL
);
CREATE TABLE controversy_position (
  controversy_id UUID NOT NULL REFERENCES controversy(id) ON DELETE CASCADE,
  document_id    UUID NOT NULL REFERENCES document(id) ON DELETE CASCADE,
  stance         TEXT NOT NULL,
  summary        TEXT,
  PRIMARY KEY (controversy_id, document_id)
);

-- ============ C5 structure ============
CREATE TABLE chapter (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES document(id) ON DELETE CASCADE,
  ord         INTEGER NOT NULL,
  parent_id   UUID REFERENCES chapter(id),
  title       TEXT,
  page_start  INTEGER,
  page_end    INTEGER,
  token_count INTEGER
);
CREATE INDEX ix_chapter_doc ON chapter(document_id, ord);

-- ============ C8 chunks & index ============
CREATE TABLE chunk (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id      UUID NOT NULL REFERENCES document(id) ON DELETE CASCADE,
  chapter_id       UUID REFERENCES chapter(id),
  ord              INTEGER NOT NULL,
  page_start       INTEGER,
  page_end         INTEGER,
  text             TEXT NOT NULL,
  token_count      INTEGER,
  content_hash     TEXT NOT NULL,        -- ré-indexation incrémentale
  embedding        vector(1024),
  embed_model      TEXT,
  pipeline_version INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX ix_chunk_doc  ON chunk(document_id, ord);
CREATE INDEX ix_chunk_hash ON chunk(content_hash);

-- ============ CONCEPTS / GLOSSAIRE ============
CREATE TABLE concept (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  term       TEXT NOT NULL UNIQUE,
  definition TEXT,
  axis_id    UUID REFERENCES axis(id)
);
CREATE TABLE concept_occurrence (
  concept_id UUID NOT NULL REFERENCES concept(id) ON DELETE CASCADE,
  chunk_id   UUID NOT NULL REFERENCES chunk(id) ON DELETE CASCADE,
  is_definition BOOLEAN NOT NULL DEFAULT false,
  PRIMARY KEY (concept_id, chunk_id)
);

-- ============ C6 dérivés générés ============
CREATE TABLE derivative (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id        UUID NOT NULL REFERENCES document(id) ON DELETE CASCADE,
  chapter_id         UUID REFERENCES chapter(id),
  kind               TEXT NOT NULL CHECK (kind IN
                       ('synthese','quiz','flashcards','fiche_lecture','resume_executif')),
  level              TEXT,
  content            JSONB NOT NULL,     -- JSON
  model_id           TEXT NOT NULL,
  prompt_version     TEXT NOT NULL,
  generated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  cost_tokens_in     INTEGER,
  cost_tokens_out    INTEGER,           -- alimente le pricing
  validated_by_human BOOLEAN NOT NULL DEFAULT false,
  superseded_by      UUID REFERENCES derivative(id)
);
CREATE INDEX ix_deriv_doc ON derivative(document_id, kind) WHERE superseded_by IS NULL;


CREATE TABLE user_profile (
  user_id            UUID PRIMARY KEY DEFAULT uuid_generate_v4() REFERENCES app_user(id) ON DELETE CASCADE,
  level_assessed     TEXT,
  assessed_at        TIMESTAMPTZ,
  goal               TEXT CHECK (goal IN ('curiosite','examen','professionnel','culture')),
  weekly_minutes     INTEGER,
  reading_speed_wpm  INTEGER,            -- mesuré, alimente reading_time_min
  language           TEXT DEFAULT 'fr'
);

-- Axe = centre d'intérêt + objectif + contrainte de temps
CREATE TABLE user_axis (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  axis_id      UUID NOT NULL REFERENCES axis(id),
  goal         TEXT,
  target_date  DATE,
  priority     INTEGER DEFAULT 1,
  status       TEXT NOT NULL DEFAULT 'actif' CHECK (status IN ('actif','pause','termine')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============ CHRONOGRAMME ============
CREATE TABLE chronogram (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_axis_id  UUID NOT NULL REFERENCES user_axis(id) ON DELETE CASCADE,
  version       INTEGER NOT NULL DEFAULT 1,     -- versionné à chaque replanification
  supersedes_id UUID REFERENCES chronogram(id),
  start_date    DATE NOT NULL,
  target_date   DATE,
  adaptive      BOOLEAN NOT NULL DEFAULT false,     -- premium
  status        TEXT NOT NULL DEFAULT 'actif'
                  CHECK (status IN ('actif','termine','abandonne','remplace')),
  generated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  rationale     TEXT
);

CREATE TABLE session (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  chronogram_id       UUID NOT NULL REFERENCES chronogram(id) ON DELETE CASCADE,
  ord                 INTEGER NOT NULL,
  document_id         UUID REFERENCES document(id),
  chapter_id          UUID REFERENCES chapter(id),
  page_start          INTEGER,
  page_end            INTEGER,
  planned_at          TIMESTAMPTZ,
  duration_min        INTEGER,
  objective           TEXT,
  deliverable_kind    TEXT,               -- quiz | note | synthese
  deliverable_id      TEXT,
  status              TEXT NOT NULL DEFAULT 'a_venir'
                        CHECK (status IN ('a_venir','fait','reporte','abandonne')),
  completed_at        TIMESTAMPTZ,
  actual_duration_min INTEGER
);
CREATE INDEX ix_session_chrono ON session(chronogram_id, ord);
CREATE INDEX ix_session_due    ON session(planned_at) WHERE status = 'a_venir';

-- ============ PROGRESSION (append-only : jamais d'UPDATE) ============
CREATE TABLE progress_event (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  session_id  UUID REFERENCES session(id),
  document_id UUID REFERENCES document(id),
  type        TEXT NOT NULL CHECK (type IN
                ('opened_doc','read_pages','quiz_attempt','question_asked',
                 'note_created','concept_mastered','session_skipped')),
  payload     JSONB,                        -- JSON : {score, pages, concept_id...}
  at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_progress_user ON progress_event(user_id, at);

CREATE TABLE concept_mastery (             -- répétition espacée
  user_id       UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  concept_id    UUID NOT NULL REFERENCES concept(id) ON DELETE CASCADE,
  ease          REAL NOT NULL DEFAULT 2.5,
  interval_days INTEGER NOT NULL DEFAULT 1,
  repetitions   INTEGER NOT NULL DEFAULT 0,
  next_review_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, concept_id)
);
CREATE INDEX ix_mastery_due ON concept_mastery(user_id, next_review_at);

-- ============ NOTES & CONVERSATIONS ANCRÉES ============
CREATE TABLE note (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  document_id UUID REFERENCES document(id),
  chunk_id    UUID REFERENCES chunk(id),
  page        INTEGER,
  body        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE conversation (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  user_axis_id UUID REFERENCES user_axis(id),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE message (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
  role            TEXT NOT NULL CHECK (role IN ('user','assistant')),
  body            TEXT NOT NULL,
  citations       JSONB,                    -- JSON [{chunk_id, doc_id, page}]
  model_id        TEXT,
  cost_tokens_in  INTEGER,
  cost_tokens_out INTEGER,
  at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============ FREEMIUM : la table qui rend l'abonnement possible ============
CREATE TABLE usage_event (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  type        TEXT NOT NULL CHECK (type IN
                ('doc_uploaded','pages_ingested','ocr_pages','agent_question',
                 'agent_tokens','quiz_generated','synthesis_generated',
                 'chronogram_active','export_pdf')),
  quantity    INTEGER NOT NULL DEFAULT 1,
  cost_tokens INTEGER NOT NULL DEFAULT 0,
  at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_usage_user_period ON usage_event(user_id, type, at);

CREATE TABLE plan_quota (                  -- éditable sans redéploiement
  plan       TEXT NOT NULL,
  type       TEXT NOT NULL,
  period     TEXT NOT NULL CHECK (period IN ('day','month','total')),
  max_value  INTEGER,                      -- NULL = illimité
  hard       BOOLEAN NOT NULL DEFAULT true,   -- 0 = soft cap (alerte, pas blocage)
  PRIMARY KEY (plan, type, period)
);

CREATE TABLE subscription (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  plan              TEXT NOT NULL,
  provider          TEXT,                  -- stripe | mobile_money | ...
  provider_ref      TEXT,
  status            TEXT NOT NULL CHECK (status IN
                      ('trial','active','past_due','canceled','expired')),
  current_start     TIMESTAMPTZ,
  current_end       TIMESTAMPTZ,
  amount_cents      INTEGER,
  currency          TEXT DEFAULT 'XAF'
);

-- ============ INDEX VECTORIEL (a creer apres le premier chargement) ============
-- CREATE INDEX ix_chunk_embedding ON chunk USING hnsw (embedding vector_cosine_ops);
-- CREATE INDEX ix_document_title_trgm ON document USING gin (title_clean gin_trgm_ops);

-- (migration 001) éditions successives d'un même ouvrage
-- ALTER TABLE document ADD COLUMN supersedes_document_id UUID REFERENCES document(id);
