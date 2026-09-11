-- La file des travaux longs.
--
-- Ingérer un ouvrage prend des minutes, l'OCR des heures, la vectorisation
-- davantage. Rien de tout cela ne tient dans une requête HTTP : le navigateur
-- abandonne, et celui qui a déposé le fichier ne sait plus où il en est.
--
-- On écrit donc ce qu'il y a à faire dans une table, et un ouvrier séparé le
-- prend. La table sert aussi de suivi : sans elle, déposer un fichier revient
-- à le jeter dans un puits.
--
-- Une table plutôt qu'une file dédiée : à ce débit, quelques travaux par jour,
-- PostgreSQL suffit et `select for update skip locked` empêche deux ouvriers
-- de prendre le même. Une brique de moins à surveiller sur le serveur.
--
-- Idempotente : rejouable sans dommage.

begin;

create table if not exists travail (
  id           uuid primary key default uuid_generate_v4(),
  type         text not null check (type in
                 ('ingestion', 'structure', 'passages', 'vecteurs', 'derive', 'import_data')),
  etat         text not null default 'en_attente' check (etat in
                 ('en_attente', 'en_cours', 'termine', 'echec', 'annule')),
  document_id  uuid references document(id) on delete set null,

  -- Ce qu'il faut pour exécuter : le nom du fichier déposé, le type de dérivé
  -- demandé, les options. Libre, parce que chaque type de travail a les siennes.
  charge       jsonb not null default '{}'::jsonb,

  -- La sortie du script, tronquée. C'est ce qu'on lit quand un travail échoue,
  -- et c'est la seule chose qui explique pourquoi.
  journal      text,
  erreur       text,
  progression  smallint not null default 0 check (progression between 0 and 100),

  demande_par  uuid references app_user(id) on delete set null,
  created_at   timestamptz not null default now(),
  started_at   timestamptz,
  finished_at  timestamptz
);

-- L'ouvrier prend le plus ancien en attente : un index partiel sur cet
-- ensemble, qui reste petit même quand la table grossit.
create index if not exists ix_travail_file on travail (created_at)
  where etat = 'en_attente';
create index if not exists ix_travail_recent on travail (created_at desc);

commit;
