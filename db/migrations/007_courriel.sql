-- Le courrier transactionnel : statut « simulé » et les gabarits.
--
-- La migration 006 avait créé les tables sans jamais les remplir, et sans code
-- pour les lire. Un membre payait, son abonnement s'ouvrait, et personne ne lui
-- écrivait. Cette migration pose les cinq messages qui manquaient.
--
-- Idempotente : rejouable sans dommage.

begin;

-- Sans BREVO_API_KEY, on journalise sans rien envoyer. Confondre cet état avec
-- « envoyé » ferait croire, en relisant le journal, que des courriels sont
-- partis alors qu'aucun n'a quitté la machine.
alter table email_log drop constraint if exists email_log_statut_check;
alter table email_log add constraint email_log_statut_check
  check (statut in ('en_attente', 'envoye', 'simule', 'echec'));

-- Les corps restent simples : <p>, <ul>, <a>. L'enveloppe visuelle est posée
-- par le code, parce qu'un CSS de courriel ne se corrige pas dans une cellule.
insert into email_template (code, objet, corps_html, corps_texte) values

('bienvenue',
 'Bienvenue sur ASCENDA, {prenom}',
 '<p>Votre compte est ouvert.</p>
  <p>La suite tient en six minutes : le diagnostic situe votre niveau et vous
  demande le temps dont vous disposez réellement. ASCENDA en tire un
  chronogramme, c''est à dire des séances datées avec leur ouvrage et leurs
  pages.</p>
  <p>La formule Découverte vous donne un axe, un chronogramme, les quiz déjà
  préparés et vingt questions par jour à l''agent. Sans carte bancaire et sans
  limite de durée.</p>
  <p style="margin-top:24px;color:#6b7280;font-size:13px;">Vous n''avez pas
  créé ce compte ? Répondez à ce message et nous le fermons.</p>',
 'Bienvenue sur ASCENDA, {prenom}.

Votre compte est ouvert. Le diagnostic prend six minutes et donne un
chronogramme : des séances datées, avec leur ouvrage et leurs pages.

Vous n''avez pas créé ce compte ? Répondez à ce message et nous le fermons.'),

('paiement_confirme',
 'Votre abonnement Ascension est actif',
 '<p>Nous avons bien reçu votre paiement de <strong>{montant}</strong>.</p>
  <ul>
    <li>Durée : {periode} mois</li>
    <li>Accès ouvert jusqu''au <strong>{fin}</strong></li>
    <li>Référence : {reference}</li>
  </ul>
  <p>Vous avez désormais les 78 ouvrages, tous les axes, la replanification
  quand la semaine ne se passe pas comme prévu, l''agent sans limite de
  questions, le pack hors ligne et les exports PDF.</p>
  <p style="margin-top:24px;color:#6b7280;font-size:13px;">Rien ne sera prélevé
  automatiquement. À l''échéance, votre compte revient simplement à la formule
  Découverte.</p>',
 'Votre abonnement Ascension est actif.

Paiement reçu : {montant}, pour {periode} mois.
Accès ouvert jusqu''au {fin}. Référence : {reference}.

Rien ne sera prélevé automatiquement. À l''échéance, votre compte revient à la
formule Découverte.'),

('paiement_rejete',
 'Votre paiement n''a pas abouti',
 '<p>Le paiement de <strong>{montant}</strong> n''est pas allé au bout.</p>
  <p>Raison indiquée : {motif}</p>
  <p>Rien n''a été débité. Vous pouvez réessayer depuis l''application, onglet
  Profil, puis « Passer à Ascension ».</p>
  <p style="margin-top:24px;color:#6b7280;font-size:13px;">Si un montant a
  pourtant quitté votre compte mobile money, répondez à ce message avec la date
  et le numéro utilisé : chaque paiement est tracé de bout en bout chez nous.</p>',
 'Votre paiement de {montant} n''a pas abouti.

Raison : {motif}. Rien n''a été débité, vous pouvez réessayer depuis
l''application.

Si un montant a pourtant quitté votre compte mobile money, répondez à ce
message avec la date et le numéro utilisé.'),

('abonnement_bientot_echu',
 'Votre accès Ascension se referme dans {jours} jours',
 '<p>Votre abonnement arrive à échéance le <strong>{fin}</strong>.</p>
  <p>Passé cette date, votre compte revient à la formule Découverte. Vous ne
  perdez rien : votre progression, vos notes et vos quiz restent en place, et
  votre chronogramme se poursuit sur l''axe que la formule Découverte
  autorise.</p>
  <p>Renouveler avant l''échéance ajoute la nouvelle période à ce qu''il reste.
  Vous ne perdez aucun jour.</p>',
 'Votre accès Ascension se referme le {fin}, dans {jours} jours.

Votre progression et vos notes restent en place. Renouveler avant l''échéance
ajoute la nouvelle période à ce qu''il reste : vous ne perdez aucun jour.'),

('abonnement_echu',
 'Votre abonnement Ascension est arrivé à terme',
 '<p>Votre accès Ascension s''est refermé le <strong>{fin}</strong>, comme
  prévu, et rien ne vous a été prélevé.</p>
  <p>Votre compte est passé à la formule Découverte. Votre progression, vos
  notes, vos quiz et vos notions en révision sont conservés tels quels.</p>
  <p>Vous pouvez reprendre Ascension quand vous le souhaitez, depuis
  l''application.</p>',
 'Votre abonnement Ascension est arrivé à terme le {fin}. Rien ne vous a été
prélevé.

Votre compte est passé à la formule Découverte. Toute votre progression est
conservée.')

on conflict (code) do update set
  objet = excluded.objet,
  corps_html = excluded.corps_html,
  corps_texte = excluded.corps_texte,
  updated_at = now();

commit;
