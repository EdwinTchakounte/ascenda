-- Le droit d'administration.
--
-- Une colonne, pas une table de rôles. Il n'y a qu'un rôle et il ne se
-- distribue pas : on le pose à la main, par une requête, sur les comptes qui
-- doivent voir les paiements et les comptes des autres. Une hiérarchie de
-- permissions serait de l'architecture pour un besoin qui n'existe pas.
--
-- Il ne se demande pas depuis l'application : aucune route ne l'accorde.
--
--   update app_user set est_admin = true where email = 'vous@exemple.com';
--
-- Idempotente : rejouable sans dommage.

begin;

alter table app_user add column if not exists est_admin boolean not null default false;

-- Index partiel : les administrateurs se comptent sur une main, l'index ne
-- porte qu'eux.
create index if not exists ix_user_admin on app_user (id) where est_admin;

-- Les recherches du tableau de bord passent par la date, dans les deux sens.
create index if not exists ix_payment_date on payment (created_at desc);
create index if not exists ix_user_date on app_user (created_at desc);

commit;
