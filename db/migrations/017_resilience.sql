-- Résilience : ce qui échoue se reprend, ce qui reste en panne se signale.
--
-- Quatre manques relevés en production :
--
-- - un courriel en échec (Brevo indisponible une minute) était perdu : la
--   trace restait, le message ne repartait jamais. `email_log` garde désormais
--   de quoi le renvoyer, et une date de prochaine tentative ;
-- - un travail interrompu (travailleur tué pendant une ingestion) restait
--   « en cours » pour toujours. Le travailleur bat désormais un signal de vie ;
-- - rien ne prévenait quand ça allait mal. Les incidents sont ouverts, suivis et
--   refermés par la veille, et chaque ouverture alerte les administrateurs une
--   seule fois ;
-- - rien ne vérifiait qu'une sauvegarde avait tourné. Le script l'inscrit ici.
--
-- Idempotente : rejouable sans dommage.

begin;

-- Courriels : la file de renvoi.
alter table email_log add column if not exists tentatives smallint not null default 1;
alter table email_log add column if not exists prochaine_tentative timestamptz;
alter table email_log add column if not exists contexte jsonb;
alter table email_log drop constraint if exists email_log_statut_check;
alter table email_log add constraint email_log_statut_check
  check (statut in ('en_attente', 'envoye', 'simule', 'echec', 'abandonne'));
create index if not exists ix_email_log_a_reprendre on email_log (prochaine_tentative)
  where statut = 'echec' and prochaine_tentative is not null;

-- Travaux : le signal de vie et le nombre de reprises.
alter table travail add column if not exists battement timestamptz;
alter table travail add column if not exists reprises smallint not null default 0;

-- Incidents : une ligne par problème, ouverte tant qu'il dure.
create table if not exists incident (
  id               uuid primary key default uuid_generate_v4(),
  cle              text not null,
  gravite          text not null check (gravite in ('info', 'attention', 'critique')),
  titre            text not null,
  detail           jsonb not null default '{}'::jsonb,
  ouvert_le        timestamptz not null default now(),
  vu_le            timestamptz not null default now(),
  clos_le          timestamptz,
  alerte_envoyee_le timestamptz
);
-- Un seul incident ouvert par clé : la veille le retrouve au lieu d'en créer un autre.
create unique index if not exists ux_incident_ouvert on incident (cle) where clos_le is null;
create index if not exists ix_incident_recent on incident (ouvert_le desc);

-- Sauvegardes : ce que le script a réellement produit.
create table if not exists sauvegarde (
  id         uuid primary key default uuid_generate_v4(),
  fichier    text not null,
  octets     bigint not null check (octets > 0),
  fini_le    timestamptz not null default now()
);
create index if not exists ix_sauvegarde_recente on sauvegarde (fini_le desc);

insert into email_template (code, objet, corps_html, corps_texte) values
('alerte_exploitation',
 '[ASCENDA] {gravite} : {titre}',
 '<p>Bonjour,</p>
  <p>La veille d''ASCENDA a ouvert un incident.</p>
  <p style="margin:18px 0;padding:14px 18px;background:#f2eee6;">
    <b>{titre}</b><br>Gravité : {gravite}<br>Ouvert le {ouvert_le}</p>
  <p>{explication}</p>
  <p>Le détail et l''historique sont dans la console, vue « Santé ». Vous recevrez
  un second message quand l''incident sera refermé.</p>',
 'La veille d''ASCENDA a ouvert un incident : {titre} ({gravite}), le {ouvert_le}.
{explication}
Détail dans la console, vue Santé.')
on conflict (code) do nothing;

insert into email_template (code, objet, corps_html, corps_texte) values
('alerte_resolue',
 '[ASCENDA] Résolu : {titre}',
 '<p>Bonjour,</p>
  <p>L''incident <b>{titre}</b>, ouvert le {ouvert_le}, est refermé depuis le {clos_le}.</p>
  <p>Durée : {duree}.</p>',
 'Incident refermé : {titre}. Ouvert le {ouvert_le}, refermé le {clos_le}. Durée : {duree}.')
on conflict (code) do nothing;

commit;
