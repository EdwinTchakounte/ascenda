-- ASCENDA : schéma V1 (SQLite local ; portable PostgreSQL)
-- Portage PG : TEXT id -> UUID, TEXT JSON -> JSONB, embedding BLOB -> vector(N),
--              strftime -> now(). Le reste est identique.
PRAGMA foreign_keys = ON;

-- ============ SYNCHRO (à porter sur toute nouvelle table) ============
--   origin_node TEXT, synced_at TEXT, dirty INTEGER DEFAULT 1

-- ============ AXES ============
CREATE TABLE axis (
  id                TEXT PRIMARY KEY,
  slug              TEXT NOT NULL UNIQUE,        -- 04-ia-societe-ethique-philosophie
  label             TEXT NOT NULL,
  description       TEXT,
  parent_id         TEXT REFERENCES axis(id),
  centroid          BLOB,                        -- pour le classement auto à l'upload
  sort_order        INTEGER,
  is_premium        INTEGER NOT NULL DEFAULT 0
);

-- ============ DOCUMENT : couches 1,2,3,7 ============
CREATE TABLE document (
  id                TEXT PRIMARY KEY,
  -- C1 identité
  sha256            TEXT NOT NULL,
  filename_original TEXT NOT NULL,
  mime              TEXT NOT NULL,
  size_bytes        INTEGER NOT NULL,
  page_count        INTEGER,
  language          TEXT,
  source            TEXT NOT NULL CHECK (source IN ('corpus_base','upload_user')),
  owner_id          TEXT REFERENCES user(id),
  visibility        TEXT NOT NULL DEFAULT 'private'
                      CHECK (visibility IN ('public','private','shared')),
  storage_key       TEXT NOT NULL,               -- chemin local puis clé S3/R2
  added_at          TEXT NOT NULL DEFAULT (datetime('now')),
  -- C2 bibliographique
  title_raw         TEXT,
  title_clean       TEXT,
  subtitle          TEXT,
  authors           TEXT,                        -- JSON []
  publisher         TEXT,
  year              INTEGER,
  isbn              TEXT,
  edition           TEXT,
  translator        TEXT,
  collection        TEXT,
  biblio_confidence REAL,                        -- 0..1 ; < 0.6 => file de validation
  biblio_validated  INTEGER NOT NULL DEFAULT 0,
  -- C3 ingestion
  has_text_layer    INTEGER,
  ocr_status        TEXT NOT NULL DEFAULT 'none'
                      CHECK (ocr_status IN ('none','needed','running','done','failed')),
  ocr_engine        TEXT,
  extraction_engine TEXT,
  extracted_chars   INTEGER,
  chars_per_page    REAL,                        -- < 400 => ocr_status = 'needed'
  quality_score     REAL,
  ingested_at       TEXT,
  pipeline_version  INTEGER NOT NULL DEFAULT 0,  -- ré-ingestion incrémentale
  -- C7 droits
  copyright_status  TEXT NOT NULL DEFAULT 'unknown'
                      CHECK (copyright_status IN
                        ('unknown','public_domain','institutional','licensed','restricted')),
  license           TEXT,
  redistributable   INTEGER NOT NULL DEFAULT 0,
  max_excerpt_chars INTEGER NOT NULL DEFAULT 1200,
  takedown_status   TEXT NOT NULL DEFAULT 'none',
  -- synchro
  origin_node       TEXT, synced_at TEXT, dirty INTEGER NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX ux_document_sha ON document(sha256, COALESCE(owner_id,''));
CREATE INDEX ix_document_pipeline  ON document(pipeline_version);
CREATE INDEX ix_document_ocr       ON document(ocr_status) WHERE ocr_status <> 'done';

-- ============ C4 pédagogique ============
CREATE TABLE document_axis (             -- multi-label : un doc a plusieurs axes
  document_id   TEXT NOT NULL REFERENCES document(id) ON DELETE CASCADE,
  axis_id       TEXT NOT NULL REFERENCES axis(id) ON DELETE CASCADE,
  weight        REAL NOT NULL DEFAULT 1.0,
  assigned_by   TEXT NOT NULL DEFAULT 'auto' CHECK (assigned_by IN ('auto','user','curator')),
  confidence    REAL,
  PRIMARY KEY (document_id, axis_id)
);

CREATE TABLE document_pedagogy (
  document_id      TEXT PRIMARY KEY REFERENCES document(id) ON DELETE CASCADE,
  level            TEXT CHECK (level IN ('debutant','intermediaire','avance')),
  doc_type         TEXT,                 -- essai|manuel|cours|roman|rapport|guide
  target_audience  TEXT,
  reading_time_min INTEGER,
  concept_density  REAL,
  central_thesis   TEXT,
  key_ideas        TEXT                  -- JSON []
);

CREATE TABLE document_prerequisite (
  document_id      TEXT NOT NULL REFERENCES document(id) ON DELETE CASCADE,
  prerequisite_id  TEXT NOT NULL REFERENCES document(id) ON DELETE CASCADE,
  strength         TEXT DEFAULT 'recommande' CHECK (strength IN ('requis','recommande')),
  PRIMARY KEY (document_id, prerequisite_id)
);

-- Mise en regard des thèses opposées (Bostrom vs « L'IA n'existe pas », Sadin vs Alexandre)
CREATE TABLE controversy (
  id          TEXT PRIMARY KEY,
  axis_id     TEXT REFERENCES axis(id),
  question    TEXT NOT NULL
);
CREATE TABLE controversy_position (
  controversy_id TEXT NOT NULL REFERENCES controversy(id) ON DELETE CASCADE,
  document_id    TEXT NOT NULL REFERENCES document(id) ON DELETE CASCADE,
  stance         TEXT NOT NULL,
  summary        TEXT,
  PRIMARY KEY (controversy_id, document_id)
);

-- ============ C5 structure ============
CREATE TABLE chapter (
  id          TEXT PRIMARY KEY,
  document_id TEXT NOT NULL REFERENCES document(id) ON DELETE CASCADE,
  ord         INTEGER NOT NULL,
  parent_id   TEXT REFERENCES chapter(id),
  title       TEXT,
  page_start  INTEGER,
  page_end    INTEGER,
  token_count INTEGER
);
CREATE INDEX ix_chapter_doc ON chapter(document_id, ord);

-- ============ C8 chunks & index ============
CREATE TABLE chunk (
  id               TEXT PRIMARY KEY,
  document_id      TEXT NOT NULL REFERENCES document(id) ON DELETE CASCADE,
  chapter_id       TEXT REFERENCES chapter(id),
  ord              INTEGER NOT NULL,
  page_start       INTEGER,
  page_end         INTEGER,
  text             TEXT NOT NULL,
  token_count      INTEGER,
  content_hash     TEXT NOT NULL,        -- ré-indexation incrémentale
  embedding        BLOB,
  embed_model      TEXT,
  pipeline_version INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX ix_chunk_doc  ON chunk(document_id, ord);
CREATE INDEX ix_chunk_hash ON chunk(content_hash);

-- ============ CONCEPTS / GLOSSAIRE ============
CREATE TABLE concept (
  id         TEXT PRIMARY KEY,
  term       TEXT NOT NULL UNIQUE,
  definition TEXT,
  axis_id    TEXT REFERENCES axis(id)
);
CREATE TABLE concept_occurrence (
  concept_id TEXT NOT NULL REFERENCES concept(id) ON DELETE CASCADE,
  chunk_id   TEXT NOT NULL REFERENCES chunk(id) ON DELETE CASCADE,
  is_definition INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (concept_id, chunk_id)
);

-- ============ C6 dérivés générés ============
CREATE TABLE derivative (
  id                 TEXT PRIMARY KEY,
  document_id        TEXT NOT NULL REFERENCES document(id) ON DELETE CASCADE,
  chapter_id         TEXT REFERENCES chapter(id),
  kind               TEXT NOT NULL CHECK (kind IN
                       ('synthese','quiz','flashcards','fiche_lecture','resume_executif')),
  level              TEXT,
  content            TEXT NOT NULL,     -- JSON
  model_id           TEXT NOT NULL,
  prompt_version     TEXT NOT NULL,
  generated_at       TEXT NOT NULL DEFAULT (datetime('now')),
  cost_tokens_in     INTEGER,
  cost_tokens_out    INTEGER,           -- alimente le pricing
  validated_by_human INTEGER NOT NULL DEFAULT 0,
  superseded_by      TEXT REFERENCES derivative(id)
);
CREATE INDEX ix_deriv_doc ON derivative(document_id, kind) WHERE superseded_by IS NULL;

-- ============ UTILISATEURS ============
CREATE TABLE user (
  id            TEXT PRIMARY KEY,
  email         TEXT UNIQUE,
  display_name  TEXT,
  plan          TEXT NOT NULL DEFAULT 'free' CHECK (plan IN ('free','premium','team')),
  plan_since    TEXT,
  plan_until    TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  origin_node   TEXT, synced_at TEXT, dirty INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE user_profile (
  user_id            TEXT PRIMARY KEY REFERENCES user(id) ON DELETE CASCADE,
  level_assessed     TEXT,
  assessed_at        TEXT,
  goal               TEXT CHECK (goal IN ('curiosite','examen','professionnel','culture')),
  weekly_minutes     INTEGER,
  reading_speed_wpm  INTEGER,            -- mesuré, alimente reading_time_min
  language           TEXT DEFAULT 'fr'
);

-- Axe = centre d'intérêt + objectif + contrainte de temps
CREATE TABLE user_axis (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  axis_id      TEXT NOT NULL REFERENCES axis(id),
  goal         TEXT,
  target_date  TEXT,
  priority     INTEGER DEFAULT 1,
  status       TEXT NOT NULL DEFAULT 'actif' CHECK (status IN ('actif','pause','termine')),
  created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============ CHRONOGRAMME ============
CREATE TABLE chronogram (
  id            TEXT PRIMARY KEY,
  user_axis_id  TEXT NOT NULL REFERENCES user_axis(id) ON DELETE CASCADE,
  version       INTEGER NOT NULL DEFAULT 1,     -- versionné à chaque replanification
  supersedes_id TEXT REFERENCES chronogram(id),
  start_date    TEXT NOT NULL,
  target_date   TEXT,
  adaptive      INTEGER NOT NULL DEFAULT 0,     -- premium
  status        TEXT NOT NULL DEFAULT 'actif'
                  CHECK (status IN ('actif','termine','abandonne','remplace')),
  generated_at  TEXT NOT NULL DEFAULT (datetime('now')),
  rationale     TEXT
);

CREATE TABLE session (
  id                  TEXT PRIMARY KEY,
  chronogram_id       TEXT NOT NULL REFERENCES chronogram(id) ON DELETE CASCADE,
  ord                 INTEGER NOT NULL,
  document_id         TEXT REFERENCES document(id),
  chapter_id          TEXT REFERENCES chapter(id),
  page_start          INTEGER,
  page_end            INTEGER,
  planned_at          TEXT,
  duration_min        INTEGER,
  objective           TEXT,
  deliverable_kind    TEXT,               -- quiz | note | synthese
  deliverable_id      TEXT,
  status              TEXT NOT NULL DEFAULT 'a_venir'
                        CHECK (status IN ('a_venir','fait','reporte','abandonne')),
  completed_at        TEXT,
  actual_duration_min INTEGER
);
CREATE INDEX ix_session_chrono ON session(chronogram_id, ord);
CREATE INDEX ix_session_due    ON session(planned_at) WHERE status = 'a_venir';

-- ============ PROGRESSION (append-only : jamais d'UPDATE) ============
CREATE TABLE progress_event (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  session_id  TEXT REFERENCES session(id),
  document_id TEXT REFERENCES document(id),
  type        TEXT NOT NULL CHECK (type IN
                ('opened_doc','read_pages','quiz_attempt','question_asked',
                 'note_created','concept_mastered','session_skipped')),
  payload     TEXT,                        -- JSON : {score, pages, concept_id...}
  at          TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX ix_progress_user ON progress_event(user_id, at);

CREATE TABLE concept_mastery (             -- répétition espacée
  user_id       TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  concept_id    TEXT NOT NULL REFERENCES concept(id) ON DELETE CASCADE,
  ease          REAL NOT NULL DEFAULT 2.5,
  interval_days INTEGER NOT NULL DEFAULT 1,
  repetitions   INTEGER NOT NULL DEFAULT 0,
  next_review_at TEXT,
  PRIMARY KEY (user_id, concept_id)
);
CREATE INDEX ix_mastery_due ON concept_mastery(user_id, next_review_at);

-- ============ NOTES & CONVERSATIONS ANCRÉES ============
CREATE TABLE note (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  document_id TEXT REFERENCES document(id),
  chunk_id    TEXT REFERENCES chunk(id),
  page        INTEGER,
  body        TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE conversation (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  user_axis_id TEXT REFERENCES user_axis(id),
  created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE message (
  id              TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
  role            TEXT NOT NULL CHECK (role IN ('user','assistant')),
  body            TEXT NOT NULL,
  citations       TEXT,                    -- JSON [{chunk_id, doc_id, page}]
  model_id        TEXT,
  cost_tokens_in  INTEGER,
  cost_tokens_out INTEGER,
  at              TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============ FREEMIUM : la table qui rend l'abonnement possible ============
CREATE TABLE usage_event (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  type        TEXT NOT NULL CHECK (type IN
                ('doc_uploaded','pages_ingested','ocr_pages','agent_question',
                 'agent_tokens','quiz_generated','synthesis_generated',
                 'chronogram_active','export_pdf')),
  quantity    INTEGER NOT NULL DEFAULT 1,
  cost_tokens INTEGER NOT NULL DEFAULT 0,
  at          TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX ix_usage_user_period ON usage_event(user_id, type, at);

CREATE TABLE plan_quota (                  -- éditable sans redéploiement
  plan       TEXT NOT NULL,
  type       TEXT NOT NULL,
  period     TEXT NOT NULL CHECK (period IN ('day','month','total')),
  max_value  INTEGER,                      -- NULL = illimité
  hard       INTEGER NOT NULL DEFAULT 1,   -- 0 = soft cap (alerte, pas blocage)
  PRIMARY KEY (plan, type, period)
);

CREATE TABLE subscription (
  id                TEXT PRIMARY KEY,
  user_id           TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  plan              TEXT NOT NULL,
  provider          TEXT,                  -- stripe | mobile_money | ...
  provider_ref      TEXT,
  status            TEXT NOT NULL CHECK (status IN
                      ('trial','active','past_due','canceled','expired')),
  current_start     TEXT,
  current_end       TEXT,
  amount_cents      INTEGER,
  currency          TEXT DEFAULT 'XAF'
);
