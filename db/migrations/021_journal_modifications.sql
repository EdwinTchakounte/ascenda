-- Le journal des modifications : qui a changé quoi, quand, et de quelle valeur
-- vers quelle valeur.
--
-- Pourquoi en base et non dans l'API. Jusqu'ici la traçabilité était posée
-- domaine par domaine : `payment_event` pour les paiements, `email_log` pour
-- les courriels, `incident` pour les pannes, `title_source` et
-- `content_source` pour les corrections de corpus. Chacun répond bien à sa
-- question, mais tous partagent le même angle mort : ils ne voient que ce qui
-- passe par le code. Une correction faite à la main dans `psql`, un plafond
-- relevé un soir d'urgence, un compte passé administrateur : rien n'en reste.
-- Un trigger, lui, est sous l'écriture. Rien ne lui échappe.
--
-- Pourquoi une seule fonction. Elle est écrite une fois et ne prend aucun
-- paramètre de table : elle lit `tg_table_name` et `tg_op` à l'exécution, et
-- reçoit en argument les colonnes qui forment la clé. Ajouter une table à
-- surveiller tient donc en une ligne, et le jour où la capture doit changer,
-- elle change en un seul endroit.
--
-- Ce qui n'est pas surveillé, et pourquoi. `chunk` et `derivative` portent le
-- texte des ouvrages : les tracer doublerait la base pour une information que
-- `content_source` garde déjà. `chapter` change par milliers de lignes à
-- chaque passe de correction, et `title_source` garde l'original. Les tables
-- d'événements ne se modifient pas, elles s'ajoutent. Restent les tables de
-- gouvernance, celles dont une ligne modifiée change ce que vit un lecteur ou
-- ce que coûte le service.
--
-- Les secrets ne sont jamais recopiés : l'empreinte d'un mot de passe, la clé
-- chiffrée d'un fournisseur, le téléphone d'un payeur et la réponse brute de
-- la passerelle sont remplacés par « (masqué) ». Le journal dit que le champ a
-- changé, pas ce qu'il contient.
--
-- Idempotente : rejouable sans dommage.

begin;

create table if not exists journal_modification (
  id        bigserial primary key,
  au        timestamptz not null default now(),
  relation  text not null,
  operation text not null check (operation in ('insert', 'update', 'delete')),
  -- La clé primaire de la ligne touchée, rendue en texte : les clés composées
  -- se lisent « valeur / valeur ».
  cle       text,
  -- Qui agit, posé par l'API dans `app.acteur`. « systeme » quand l'écriture
  -- vient d'un script ou de la console psql.
  acteur    text not null default 'systeme',
  avant     jsonb,
  apres     jsonb,
  -- { "colonne": [ancienne valeur, nouvelle valeur] } pour les seules colonnes
  -- qui changent. C'est ce qu'on lit en premier ; `avant` et `apres` servent
  -- quand il faut reconstituer la ligne entière.
  ecart     jsonb
);

create index if not exists ix_journal_recent on journal_modification (au desc);
create index if not exists ix_journal_relation on journal_modification (relation, au desc);
create index if not exists ix_journal_acteur on journal_modification (acteur, au desc);
create index if not exists ix_journal_ligne on journal_modification (relation, cle);

create or replace function tracer_modification() returns trigger
language plpgsql as $$
declare
  -- Jamais recopiées : le journal dit qu'elles ont changé, pas leur contenu.
  masquees constant text[] := array['password_hash', 'cle_chiffree', 'telephone',
                                    'gateway_reponse'];
  -- Changer de valeur sur ces colonnes n'est pas une modification à retenir.
  techniques constant text[] := array['updated_at', 'synced_at', 'dirty', 'last_login_at'];
  avant jsonb;
  apres jsonb;
  ecart jsonb := '{}'::jsonb;
  cle text := '';
  colonne text;
  champ text;
begin
  avant := case tg_op when 'INSERT' then null else to_jsonb(old) end;
  apres := case tg_op when 'DELETE' then null else to_jsonb(new) end;

  -- L'écart se calcule avant le masquage : une clé qui change doit se voir
  -- dans le journal, même si sa valeur ne s'y lit pas.
  if tg_op = 'UPDATE' then
    for champ in select jsonb_object_keys(apres) loop
      if not (champ = any (techniques)) and avant -> champ is distinct from apres -> champ then
        ecart := ecart || jsonb_build_object(champ,
          case when champ = any (masquees)
               then jsonb_build_array('"(masqué)"'::jsonb, '"(masqué)"'::jsonb)
               else jsonb_build_array(avant -> champ, apres -> champ) end);
      end if;
    end loop;
    -- Une mise à jour qui ne change rien de notable ne laisse pas de trace :
    -- sinon le journal se remplit d'horodatages et devient illisible.
    if ecart = '{}'::jsonb then
      return null;
    end if;
  end if;

  foreach colonne in array masquees loop
    if avant ? colonne then
      avant := jsonb_set(avant, array[colonne], '"(masqué)"'::jsonb);
    end if;
    if apres ? colonne then
      apres := jsonb_set(apres, array[colonne], '"(masqué)"'::jsonb);
    end if;
  end loop;

  for i in 1 .. coalesce(array_length(tg_argv, 1), 0) loop
    cle := cle || case when i > 1 then ' / ' else '' end
                || coalesce(coalesce(apres, avant) ->> tg_argv[i - 1], '');
  end loop;

  insert into journal_modification (relation, operation, cle, acteur, avant, apres, ecart)
  values (tg_table_name, lower(tg_op), nullif(cle, ''),
          coalesce(nullif(current_setting('app.acteur', true), ''), 'systeme'),
          avant, apres, nullif(ecart, '{}'::jsonb));
  return null;
end $$;

comment on function tracer_modification() is
  'Écrit dans journal_modification toute insertion, mise à jour ou suppression. '
  'Les colonnes de la clé primaire sont passées en arguments du trigger.';

-- Les tables de gouvernance, avec les colonnes de leur clé primaire.
do $$
declare
  cible record;
  arguments text;
begin
  for cible in
    select * from (values
      ('app_user',       'id'),
      ('subscription',   'id'),
      ('payment',        'id'),
      ('code_acces',     'id'),
      ('plan_quota',     'plan,type,period'),
      ('plan_tarif',     'id'),
      ('bon_reduction',  'id'),
      ('fournisseur_ia', 'code'),
      ('reglage',        'cle'),
      ('email_template', 'code'),
      ('document',       'id'),
      ('axis',           'id'),
      ('signalement',    'id'),
      ('blocage',        'user_id,bloque_id')
    ) as t(relation, cles)
  loop
    if to_regclass(cible.relation) is null then
      raise notice 'Table absente, non surveillée : %', cible.relation;
      continue;
    end if;
    select string_agg(quote_literal(c), ', ')
      into arguments
      from unnest(string_to_array(cible.cles, ',')) as c;
    execute format('drop trigger if exists tracer_%1$s on %1$I', cible.relation);
    execute format(
      'create trigger tracer_%1$s after insert or update or delete on %1$I '
      'for each row execute function tracer_modification(%2$s)',
      cible.relation, arguments);
  end loop;
end $$;

commit;
