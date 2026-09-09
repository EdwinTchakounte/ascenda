-- La réinitialisation de mot de passe.
--
-- Il n'y en avait aucune : quelqu'un qui perdait son mot de passe perdait son
-- compte. C'est le premier motif d'écriture au support de n'importe quel
-- service, et le seul qu'on ne pouvait pas traiter.
--
-- Un code à six chiffres plutôt qu'un lien : l'application est mobile, il
-- n'existe aujourd'hui ni site déployé ni lien profond pour rattraper un clic
-- depuis une boîte de courriel. Un code se recopie à la main et fonctionne
-- partout.
--
-- Idempotente : rejouable sans dommage.

begin;

create table if not exists password_reset (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references app_user(id) on delete cascade,
  -- Le code n'est jamais stocké en clair : quelqu'un qui lirait la table
  -- pourrait sinon prendre la main sur n'importe quel compte.
  code_hash    text not null,
  expires_at   timestamptz not null,
  used_at      timestamptz,
  -- Au delà de cinq essais, le code est mort. Six chiffres se devinent en un
  -- million de coups, ce qui est peu quand personne ne compte.
  tentatives   smallint not null default 0,
  created_at   timestamptz not null default now()
);

create index if not exists ix_reset_user on password_reset (user_id, created_at desc);
create index if not exists ix_reset_vivants on password_reset (expires_at) where used_at is null;

insert into email_template (code, objet, corps_html, corps_texte) values
('mot_de_passe_oublie',
 'Votre code de réinitialisation ASCENDA',
 '<p>Voici le code à saisir dans l''application pour choisir un nouveau mot de
  passe :</p>
  <p style="margin:24px 0;text-align:center;">
    <span style="display:inline-block;padding:14px 28px;background:#f2eee6;
                 border-radius:12px;font-size:30px;font-weight:700;
                 letter-spacing:10px;color:#0b1435;font-family:monospace;">{code}</span>
  </p>
  <p>Il est valable {minutes} minutes et ne sert qu''une fois.</p>
  <p style="margin-top:24px;color:#6b7280;font-size:13px;">Vous n''avez rien
  demandé ? Ignorez ce message : votre mot de passe actuel reste valable et
  personne n''a accès à votre compte.</p>',
 'Votre code de réinitialisation ASCENDA : {code}

Valable {minutes} minutes, une seule fois.

Vous n''avez rien demandé ? Ignorez ce message, votre mot de passe actuel reste
valable.'),

('mot_de_passe_change',
 'Votre mot de passe a été modifié',
 '<p>Le mot de passe de votre compte vient d''être changé, et toutes vos
  sessions ouvertes ont été fermées. Vous devrez vous reconnecter sur chaque
  appareil.</p>
  <p style="margin-top:24px;color:#6b7280;font-size:13px;">Ce n''est pas vous ?
  Répondez immédiatement à ce message. Tant que personne ne connaît le code
  envoyé à cette adresse, votre compte ne peut pas être repris.</p>',
 'Le mot de passe de votre compte ASCENDA vient d''être changé et toutes vos
sessions ont été fermées.

Ce n''est pas vous ? Répondez immédiatement à ce message.')

on conflict (code) do update set
  objet = excluded.objet,
  corps_html = excluded.corps_html,
  corps_texte = excluded.corps_texte,
  updated_at = now();

commit;
