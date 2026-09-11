# Vérifications

Onze suites, précédées de deux vérifications. La première reconstruit la base
à partir de rien ; la seconde confronte les appels des applications au schéma de
l'API. Cinq suites appellent ensuite l'API par HTTP, sur le corpus réel, sans bouchon :
elles ne remplacent pas des tests unitaires, elles répondent à une autre
question, « est-ce qu'un utilisateur peut faire ce que le produit lui promet,
aujourd'hui, sur ces données ». La sixième fait l'inverse et dit pourquoi
plus bas.

```bash
./tests/lancer.sh                                  # tout
.venv/bin/python tests/test_parcours.py            # une seule suite
ASCENDA_API=https://api.exemple.com ./tests/lancer.sh
```

L'API doit tourner. Chaque suite sort en code 1 si une vérification échoue.

| Suite | Ce qu'elle établit |
|---|---|
| `test_api.py` | Les 99 appels de toutes les routes : cas nominal, accès refusé sans jeton, identifiants invalides, corps malformés, quotas, droits, webhooks illisibles. Signale les routes au-dessus d'une seconde et demie. |
| `test_parcours.py` | Le trajet complet d'un utilisateur, du compte au contenu : diagnostic, chronogramme, séance du jour, lecture, quiz corrigé, agent, téléchargement, progression, paiement. |
| `test_revision.py` | La révision espacée : rater un quiz programme des notions, les réviser les éloigne, échouer les ramène. |
| `test_axes.py` | Les onze axes produisent un parcours, et le contenu de la première séance est lisible. |
| `test_paiement.py` | Les garanties du paiement, en base : les trois stratégies de rattachement, l'idempotence du webhook, la protection d'un paiement validé, la prolongation d'abonnement, la fermeture à échéance, l'abandon après vingt-quatre heures. Cette suite parle directement à la base et prend quelques minutes, à cause des pauses volontaires de la réconciliation. |
| `test_tara.py` | Le fournisseur Tara isolé, sans réseau : mise au format du numéro, table des statuts, lecture du webhook y compris ses cas tordus, contrôle du `businessId`, et la requête réellement envoyée à `dklo.co` derrière un transport bouchonné. C'est la seule suite qui n'appelle pas l'API, parce que c'est le seul morceau que nous ne pourrons pas essayer en vrai avant d'avoir un compte marchand ouvert. |
| `test_courriel.py` | Les cinq messages transactionnels et leurs déclencheurs : bienvenue à l'inscription, reçu à la validation d'un paiement, message de rejet, rappel avant échéance sans répétition, avis de fin d'abonnement. Vérifie aussi l'interrupteur d'un gabarit désactivé et le formatage des montants et des dates. Sans clé Brevo, les envois sont journalisés en `simule` : tout est réel sauf la sortie réseau. |
| `test_mot_de_passe.py` | La réinitialisation, et surtout ce qu'elle refuse : code à usage unique, cinq essais au maximum, expiration, une demande par quart d'heure, aucune fuite sur l'existence d'une adresse, révocation de toutes les sessions, second code annulant le premier, et le code jamais stocké en clair. |
| `test_enrichissement.py` | La chaîne par laquelle le corpus grandit, sans consommer un jeton : les options que le module par ouvrage passe au moteur existent bien, ce qui est déjà produit n'est pas refait, l'appareil du livre n'est pas facturé, enregistrer remplace au lieu d'empiler, et le coût s'annonce avant de se dépenser. |
| `test_exploitation.py` | Les trois interrupteurs : période de lancement qui ouvre les plafonds sans changer les plans et se referme d'elle-même à l'échéance, maintenance qui laisse passer les lectures et refuse les écritures en 503, exceptions du webhook de paiement et de la connexion. Elle rend la main quoi qu'il arrive : une suite qui laisserait la maintenance active fermerait le service. |
| `test_admin.py` | Le tableau de bord : chaque route refusée sans jeton et en 403 pour un compte ordinaire, un refus qui ne confirme pas l'existence de l'espace, des chiffres confrontés à la base, et surtout la courbe dont la somme doit égaler le compteur de la période. C'est cette dernière qui a révélé une double jointure annonçant cent six mille inscriptions pour sept cent quatre-vingt-neuf comptes. |

## La base se reconstruit à partir de rien

`./db/verifier.sh` crée une base jetable, y joue les extensions, le schéma et
les neuf migrations, puis **rejoue les migrations une seconde fois** pour
vérifier qu'elles sont idempotentes. C'est ce qu'on fera à chaque montée de
version.

Cette vérification a été écrite après coup, parce que la question ne se pose
jamais pendant des mois et se pose au pire moment. Elle avait déjà une mauvaise
réponse : une substitution automatique avait laissé sept `\g<1>` dans la
migration 002. La base de développement portait les changements, appliqués avant
la corruption, et rien ne le montrait. Un déploiement neuf aurait échoué.

## Ce que les suites ne couvrent pas

**L'interface.** Les écrans Flutter et la vitrine sont vérifiés à la main, dans
un navigateur. Rien ici ne détecte un bouton dont le texte déborde.

**La rédaction de l'agent.** Sans `ANTHROPIC_API_KEY`, l'agent renvoie ses
sources sans les mettre en phrases. `test_parcours.py` le signale comme un écart
non bloquant plutôt que de le passer sous silence.

**Le fournisseur de paiement en vrai.** Sans identifiants Tara, le fournisseur
tourne en mode simulé : aucun appel n'est jamais sorti vers `dklo.co`.
`test_tara.py` vérifie tout ce qui peut l'être sans compte marchand, c'est à dire
la forme exacte de la requête que nous enverrons et notre lecture de la réponse.
Il reste à établir que Tara se comporte comme nous le croyons : cela demande une
clé, une adresse publique en HTTPS pour recevoir le webhook, et un premier
paiement de bout en bout.

## Ces suites créent des comptes

Chacune ouvre un compte jetable en `@example.com`. Elles ne nettoient pas
derrière elles : voir ce qu'un test a produit vaut mieux que de le voir
disparaître. Pour faire le ménage :

```sql
delete from app_user where email like '%@example.com';
```
