-- Migration 006 : paiement mobile money et abonnement.
--
-- La logique est reprise du module `mail+paiement` (Tara, éprouvé en
-- production), mais le modèle est refait : celui d'origine porte des prêts, des
-- échéances et des cotisations de coopérative, ce qui n'a rien à voir avec un
-- abonnement de lecture. Ce qu'on reprend, c'est la discipline :
-- clé d'idempotence, rattachement en cascade, réconciliation, timeout 24 h.
-- Idempotente.

-- ============ 1. Tarifs, éditables sans redéploiement ============
CREATE TABLE IF NOT EXISTS plan_tarif (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  plan          TEXT NOT NULL,
  periode_mois  INTEGER NOT NULL CHECK (periode_mois > 0),
  montant       INTEGER NOT NULL CHECK (montant >= 0),
  devise        TEXT NOT NULL DEFAULT 'XAF',
  libelle       TEXT NOT NULL,
  actif         BOOLEAN NOT NULL DEFAULT true,
  UNIQUE (plan, periode_mois, devise)
);

COMMENT ON TABLE plan_tarif IS
  'Grille tarifaire. Les montants ne sont pas encore arrêtés : ces valeurs sont
   des repères, à corriger en base sans toucher au code.';

INSERT INTO plan_tarif (plan, periode_mois, montant, libelle) VALUES
  ('premium',  1, 3000,  'Ascension, un mois'),
  ('premium',  3, 8000,  'Ascension, trois mois'),
  ('premium', 12, 28000, 'Ascension, un an')
ON CONFLICT (plan, periode_mois, devise) DO NOTHING;

-- ============ 2. Le paiement ============
CREATE TABLE IF NOT EXISTS payment (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id            UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,

  -- Ce qui est acheté
  type               TEXT NOT NULL DEFAULT 'abonnement' CHECK (type IN ('abonnement')),
  plan_cible         TEXT NOT NULL DEFAULT 'premium',
  periode_mois       INTEGER NOT NULL DEFAULT 1,
  montant            INTEGER NOT NULL CHECK (montant > 0),
  devise             TEXT NOT NULL DEFAULT 'XAF',

  -- Le cycle de vie
  statut             TEXT NOT NULL DEFAULT 'en_attente'
                       CHECK (statut IN ('en_attente','valide','rejete')),
  motif_rejet        TEXT,
  date_validation    TIMESTAMPTZ,

  -- Le fournisseur
  provider_code      TEXT NOT NULL DEFAULT 'tara',
  -- Envoyée à Tara comme `productId`. C'est la clé de rattachement nº 1.
  idempotency_key    UUID NOT NULL DEFAULT uuid_generate_v4() UNIQUE,
  -- `paymentId` renvoyé par Tara. Clé de rattachement nº 2.
  reference_externe  TEXT,
  gateway_initiated_at TIMESTAMPTZ,
  gateway_reponse    JSONB,

  -- Le téléphone est la clé de rattachement nº 3, la seule qui fonctionne
  -- quand Tara ne propage pas notre productId. Stocké normalisé : 2376XXXXXXXX.
  telephone          TEXT,
  reseau             TEXT CHECK (reseau IN ('MTN','ORANGE') OR reseau IS NULL),

  subscription_id    UUID REFERENCES subscription(id) ON DELETE SET NULL,
  nb_jours_couverts  INTEGER,

  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_payment_user     ON payment(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_payment_statut   ON payment(statut) WHERE statut = 'en_attente';
CREATE INDEX IF NOT EXISTS ix_payment_ref      ON payment(reference_externe)
  WHERE reference_externe IS NOT NULL;
-- Le rattachement par téléphone ne regarde que les paiements récents en attente.
CREATE INDEX IF NOT EXISTS ix_payment_tel      ON payment(telephone, created_at DESC)
  WHERE statut = 'en_attente';

-- ============ 3. La trace ============
-- Journal append-only : tout ce qui touche un paiement laisse une ligne. C'est
-- ce qui permet de répondre à « pourquoi ce paiement a-t-il été validé ».
CREATE TABLE IF NOT EXISTS payment_event (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  payment_id  UUID REFERENCES payment(id) ON DELETE CASCADE,
  type        TEXT NOT NULL,
  source      TEXT NOT NULL CHECK (source IN
                ('api','webhook','reconciliation','admin','systeme')),
  strategie   TEXT,           -- comment le paiement a été rattaché, le cas échéant
  payload     JSONB,
  at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_payment_event ON payment_event(payment_id, at);
-- Les webhooks non rattachés sont conservés avec payment_id NULL : ils sont la
-- première chose à regarder quand un membre affirme avoir payé.
CREATE INDEX IF NOT EXISTS ix_payment_event_orphelin ON payment_event(at DESC)
  WHERE payment_id IS NULL;

-- ============ 4. L'abonnement ============
ALTER TABLE subscription ADD COLUMN IF NOT EXISTS periode_mois   INTEGER;
ALTER TABLE subscription ADD COLUMN IF NOT EXISTS auto_renouvelle BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE subscription ADD COLUMN IF NOT EXISTS closed_at      TIMESTAMPTZ;
ALTER TABLE subscription ADD COLUMN IF NOT EXISTS created_at     TIMESTAMPTZ NOT NULL DEFAULT now();
CREATE INDEX IF NOT EXISTS ix_subscription_fin ON subscription(current_end)
  WHERE status = 'active';
CREATE INDEX IF NOT EXISTS ix_subscription_user ON subscription(user_id, current_end DESC);

-- ============ 5. Notifications transactionnelles ============
-- Reprise du principe du module `mail` : le gabarit vit en base, pas dans le
-- code, et chaque envoi laisse une trace.
CREATE TABLE IF NOT EXISTS email_template (
  code        TEXT PRIMARY KEY,
  objet       TEXT NOT NULL,
  corps_html  TEXT NOT NULL,
  corps_texte TEXT,
  actif       BOOLEAN NOT NULL DEFAULT true,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS email_log (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  template     TEXT REFERENCES email_template(code) ON DELETE SET NULL,
  user_id      UUID REFERENCES app_user(id) ON DELETE SET NULL,
  destinataire TEXT NOT NULL,
  objet        TEXT NOT NULL,
  statut       TEXT NOT NULL DEFAULT 'en_attente'
                 CHECK (statut IN ('en_attente','envoye','echec')),
  erreur       TEXT,
  sent_at      TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_email_log_user ON email_log(user_id, created_at DESC);
