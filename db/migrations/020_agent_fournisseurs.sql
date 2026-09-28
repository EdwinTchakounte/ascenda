-- Le fournisseur du modèle, son modèle, sa clé et les plafonds de jetons,
-- réglables depuis la console.
--
-- Trois raisons de sortir cela du fichier d'environnement.
--
-- 1. Une clé posée dans `.env` demande un redéploiement pour changer, et c'est
--    précisément quand un fournisseur tombe ou qu'une clé fuit qu'on n'a pas
--    envie de reconstruire une image.
-- 2. Deux fournisseurs valent mieux qu'un. `ordre` dit lequel est appelé en
--    premier ; le second prend la suite quand le disjoncteur du premier est
--    ouvert. La réponse dégradée ne sert plus que si les deux sont tombés.
-- 3. Un plafond de jetons n'est pas un plafond de questions. Une question
--    coûte entre trois mille et dix mille jetons selon les passages retenus :
--    compter les questions ne dit rien de la facture, compter les jetons la
--    dit exactement.
--
-- La clé n'est jamais stockée en clair. Elle est chiffrée en AES-256-GCM avec
-- une clé dérivée de `JWT_SECRET`, et l'API ne la relit jamais vers le client :
-- la console n'en voit que les quatre derniers caractères, de quoi reconnaître
-- laquelle est posée sans pouvoir la recopier.
--
-- Idempotente : rejouable sans dommage.

begin;

create table if not exists fournisseur_ia (
  code               text primary key check (code in ('anthropic', 'openai')),
  libelle            text not null,
  modele             text not null,
  -- Chiffrée : nonce de 12 octets, puis le texte scellé.
  cle_chiffree       bytea,
  -- Les quatre derniers caractères de la clé, pour la reconnaître.
  cle_indice         text,
  actif              boolean not null default false,
  ordre              integer not null default 1 check (ordre between 1 and 9),
  max_tokens_reponse integer not null default 1400
                     check (max_tokens_reponse between 256 and 8000),
  updated_at         timestamptz not null default now(),
  updated_by         uuid references app_user(id) on delete set null
);

insert into fournisseur_ia (code, libelle, modele, ordre) values
  ('anthropic', 'Anthropic, Claude', 'claude-opus-5', 1),
  ('openai',    'OpenAI, ChatGPT',   'gpt-5',         2)
on conflict (code) do nothing;

-- Les plafonds de jetons par formule. Ordres de grandeur retenus : une question
-- coûte environ six mille jetons, donc six cent mille jetons par mois valent à
-- peu près cent questions pour un compte Découverte. Souple pour Ascension :
-- on veut être prévenu, pas couper la parole à quelqu'un qui paie.
insert into plan_quota (plan, type, period, max_value, hard) values
  ('free',    'agent_tokens', 'month',   600000, true),
  ('premium', 'agent_tokens', 'month', 20000000, false)
on conflict (plan, type, period) do nothing;

-- Un plafond de jetons porté par le code lui-même, compté depuis l'activation
-- et non remis à zéro chaque mois : c'est ce qu'il faut pour un code offert à
-- une promotion ou à un partenaire, dont on veut borner le coût total.
alter table code_acces add column if not exists plafond_tokens integer
  check (plafond_tokens is null or plafond_tokens > 0);

commit;
