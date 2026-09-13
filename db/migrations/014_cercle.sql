-- Le cercle de lecteurs : amis, encouragements et échanges.
--
-- Lire seul s'abandonne vite. Le cercle permet à des lecteurs qui se
-- connaissent de se suivre, de s'encourager et de s'écrire. Il ne s'agit pas
-- d'un réseau public : on ne cherche personne par son nom, on ajoute quelqu'un
-- dont on a reçu le code ASCENDA, et l'amitié n'existe qu'une fois acceptée.
--
-- Le fil d'activité n'a pas de table : il se lit dans `progress_event`, qui
-- trace déjà les séances faites, les quiz et les notions acquises. Seuls les
-- lecteurs qui partagent leur activité y apparaissent.
--
-- La modération suit le même principe de discrétion : la console voit les
-- volumes et les signalements, et ne lit le contenu d'un message que s'il a
-- été signalé.
--
-- Idempotente : rejouable sans dommage.

begin;

alter table app_user add column if not exists partage_activite boolean not null default true;

create table if not exists amitie (
  id              uuid primary key default uuid_generate_v4(),
  demandeur_id    uuid not null references app_user(id) on delete cascade,
  destinataire_id uuid not null references app_user(id) on delete cascade,
  statut          text not null default 'en_attente'
                  check (statut in ('en_attente', 'acceptee', 'refusee')),
  created_at      timestamptz not null default now(),
  repondu_le      timestamptz,
  check (demandeur_id <> destinataire_id)
);
-- Une seule relation par paire, quel que soit le sens de la demande.
create unique index if not exists ux_amitie_paire on amitie (
  least(demandeur_id, destinataire_id), greatest(demandeur_id, destinataire_id)
);
create index if not exists ix_amitie_destinataire on amitie (destinataire_id, statut);
create index if not exists ix_amitie_demandeur on amitie (demandeur_id, statut);

create table if not exists blocage (
  user_id    uuid not null references app_user(id) on delete cascade,
  bloque_id  uuid not null references app_user(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, bloque_id),
  check (user_id <> bloque_id)
);

create table if not exists encouragement (
  id              uuid primary key default uuid_generate_v4(),
  auteur_id       uuid not null references app_user(id) on delete cascade,
  destinataire_id uuid not null references app_user(id) on delete cascade,
  genre           text not null check (genre in ('bravo', 'courage', 'defi', 'merci')),
  message         text check (message is null or char_length(message) <= 280),
  -- L'activité qui a suscité l'encouragement, quand il répond au fil.
  evenement_id    uuid references progress_event(id) on delete set null,
  created_at      timestamptz not null default now(),
  vu_le           timestamptz,
  masque_le       timestamptz,
  check (auteur_id <> destinataire_id)
);
create index if not exists ix_encouragement_destinataire on encouragement (destinataire_id, created_at desc);
create index if not exists ix_encouragement_auteur on encouragement (auteur_id, created_at desc);

create table if not exists echange (
  id              uuid primary key default uuid_generate_v4(),
  auteur_id       uuid not null references app_user(id) on delete cascade,
  destinataire_id uuid not null references app_user(id) on delete cascade,
  texte           text not null check (char_length(texte) between 1 and 2000),
  created_at      timestamptz not null default now(),
  lu_le           timestamptz,
  -- Posé par la modération : le message reste en base pour la trace, mais
  -- n'est plus montré.
  masque_le       timestamptz,
  check (auteur_id <> destinataire_id)
);
create index if not exists ix_echange_paire on echange (
  least(auteur_id, destinataire_id), greatest(auteur_id, destinataire_id), created_at desc
);
create index if not exists ix_echange_non_lus on echange (destinataire_id) where lu_le is null;
create index if not exists ix_echange_date on echange (created_at desc);

create table if not exists signalement (
  id               uuid primary key default uuid_generate_v4(),
  auteur_id        uuid not null references app_user(id) on delete cascade,
  echange_id       uuid references echange(id) on delete cascade,
  encouragement_id uuid references encouragement(id) on delete cascade,
  motif            text not null check (char_length(motif) between 3 and 500),
  created_at       timestamptz not null default now(),
  traite_le        timestamptz,
  traite_par       uuid references app_user(id) on delete set null,
  decision         text check (decision is null or decision in ('masque', 'ignore')),
  check ((echange_id is not null)::int + (encouragement_id is not null)::int = 1)
);
create unique index if not exists ux_signalement_echange on signalement (auteur_id, echange_id)
  where echange_id is not null;
create unique index if not exists ux_signalement_encouragement on signalement (auteur_id, encouragement_id)
  where encouragement_id is not null;
create index if not exists ix_signalement_ouverts on signalement (created_at) where traite_le is null;

commit;
