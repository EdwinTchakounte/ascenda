-- Les codes d'accès et le programme ambassadeur.
--
-- Deux mécanismes voisins, qui se saisissent au même endroit mais ne font pas
-- la même chose.
--
-- Un code d'accès ouvre des fonctions d'Ascension sans rien facturer : tout
-- (niveau `complet`) ou une liste choisie (niveau `limite`). Il est toujours
-- borné dans le temps. Sa date de fin referme à la fois la saisie et les accès
-- déjà accordés : un code de lancement partagé partout cesse de produire effet
-- le jour dit, sans qu'on ait à retrouver ceux qui l'ont utilisé.
--
-- Un code ambassadeur appartient à un lecteur. Quand quelqu'un crée son compte
-- avec, le propriétaire du code reçoit un bon de réduction sur son prochain
-- abonnement, et il en est prévenu.
--
-- Comme pour le lancement, personne ne change de formule : le plan reste
-- `free`, et l'accès se lit au moment de l'appliquer. Refermer un code ne
-- demande de basculer aucun compte.
--
-- Idempotente : rejouable sans dommage.

begin;

create table if not exists code_acces (
  id                uuid primary key default uuid_generate_v4(),
  code              text not null unique check (code ~ '^[A-Z0-9][A-Z0-9-]{2,30}[A-Z0-9]$'),
  libelle           text not null,
  niveau            text not null check (niveau in ('complet', 'limite')),
  -- Pour un code limité : les fonctions ouvertes, prises dans le catalogue de
  -- `app/services/acces.py`. Ignoré pour un code complet.
  fonctions         text[] not null default '{}',
  debut             timestamptz not null default now(),
  fin               timestamptz not null,
  -- Durée de l'accès à compter de l'activation. Nulle : l'accès court jusqu'à
  -- la fin du code. Dans tous les cas, jamais au delà de `fin`.
  duree_jours       integer check (duree_jours is null or duree_jours > 0),
  max_utilisations  integer check (max_utilisations is null or max_utilisations > 0),
  actif             boolean not null default true,
  cree_par          uuid references app_user(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (fin > debut),
  check (niveau = 'complet' or cardinality(fonctions) > 0)
);

create table if not exists code_acces_utilisation (
  id         uuid primary key default uuid_generate_v4(),
  code_id    uuid not null references code_acces(id) on delete cascade,
  user_id    uuid not null references app_user(id) on delete cascade,
  active_le  timestamptz not null default now(),
  fin        timestamptz not null,
  origine    text not null check (origine in ('inscription', 'compte')),
  unique (code_id, user_id)
);
create index if not exists ix_code_utilisation_user on code_acces_utilisation (user_id, fin desc);

alter table app_user add column if not exists code_parrainage text;
alter table app_user add column if not exists parrain_id uuid references app_user(id) on delete set null;
create unique index if not exists ux_app_user_code_parrainage on app_user (code_parrainage)
  where code_parrainage is not null;

create table if not exists bon_reduction (
  id          uuid primary key default uuid_generate_v4(),
  -- Le bénéficiaire : l'ambassadeur dont le code a servi.
  user_id     uuid not null references app_user(id) on delete cascade,
  filleul_id  uuid references app_user(id) on delete set null,
  motif       text not null default 'parrainage' check (motif in ('parrainage')),
  pourcent    integer not null check (pourcent between 1 and 90),
  expire_le   timestamptz not null,
  payment_id  uuid references payment(id) on delete set null,
  utilise_le  timestamptz,
  -- Posé quand l'application a montré la bonne nouvelle : c'est ce qui la fait
  -- apparaître une fois, et une seule.
  vu_le       timestamptz,
  created_at  timestamptz not null default now()
);
-- Un filleul ne rapporte qu'une fois.
create unique index if not exists ux_bon_filleul on bon_reduction (filleul_id)
  where filleul_id is not null;
create index if not exists ix_bon_disponible on bon_reduction (user_id, expire_le)
  where utilise_le is null;

alter table payment add column if not exists montant_brut integer;
alter table payment add column if not exists reduction_pourcent integer;
alter table payment add column if not exists bon_id uuid references bon_reduction(id) on delete set null;

insert into reglage (cle, valeur, description) values
('parrainage',
 '{"actif": true, "pourcent": 20, "validite_jours": 180}'::jsonb,
 'Réduction offerte à l''ambassadeur pour chaque compte créé avec son code.')
on conflict (cle) do nothing;

insert into email_template (code, objet, corps_html, corps_texte) values
('parrainage_recompense',
 '{prenom_filleul} vous a rejoint : {pourcent} % sur votre prochain abonnement',
 '<p>Bonjour {prenom},</p>
  <p>{prenom_filleul} vient de créer son compte ASCENDA avec votre code
  ambassadeur <b>{code}</b>. Merci de faire lire autour de vous.</p>
  <p style="margin:24px 0;text-align:center;">
    <span style="display:inline-block;padding:14px 28px;background:#f2eee6;
                 font-size:28px;font-weight:700;color:#0b1435;">-{pourcent} %</span>
  </p>
  <p>La réduction s''applique toute seule à votre prochain abonnement Ascension,
  jusqu''au {expire_le}. Vous la verrez sur l''écran de paiement, avant de
  valider.</p>
  <p style="margin-top:24px;color:#6b7280;font-size:13px;">Retrouvez votre code et
  vos réductions dans l''application, rubrique Profil puis Codes et avantages.</p>',
 'Bonjour {prenom},

{prenom_filleul} vient de créer son compte ASCENDA avec votre code ambassadeur {code}.

Vous gagnez {pourcent} % sur votre prochain abonnement Ascension, jusqu''au {expire_le}.
La réduction s''applique toute seule sur l''écran de paiement.')
on conflict (code) do nothing;

commit;
