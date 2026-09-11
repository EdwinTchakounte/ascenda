# ASCENDA, lecture guidée

**ascenda-books.online**

Trois surfaces : une **API**, un **site vitrine** public, une **application**
mobile, adossées à un corpus de 78 ouvrages (15 601 pages, 11 axes).

L'accès aux livres n'est plus le problème : ce qui manque est un chemin dedans.
ASCENDA part d'un diagnostic de six minutes et du temps dont vous disposez
réellement, et compose un chronogramme de séances datées, avec leurs pages.
Chaque séance est suivie d'un quiz corrigé par l'extrait qui le justifie, et ce
qui est manqué revient en révision espacée.

## Mettre en ligne

La marche à suivre complète, des enregistrements DNS à la déclaration du webhook
chez Tara, est dans **[infra/docker/DEPLOIEMENT.md](infra/docker/DEPLOIEMENT.md)**.

| nom | rôle |
|---|---|
| `ascenda-books.online` | la vitrine |
| `api.ascenda-books.online` | l'API, et le point d'arrivée du webhook |

## Vérifier

```bash
./tests/lancer.sh
```

Neuf suites, précédées d'une reconstruction de la base à partir de rien et d'un
contrôle du contrat entre l'API et ses deux clients. Elles tournent sur le
corpus réel, sans bouchon. Voir [tests/README.md](tests/README.md).

## Arborescence

```
apps/
  api/            backend FastAPI : agent, chronogramme, quotas, droits
  web-vitrine/    site public (Next.js)
  mobile/         application (Flutter, mobile et web)
packages/shared/  types et contrats partagés
pipeline/
  ingest/         fichier -> MinIO + document/chapter/chunk (déterministe, sans LLM)
                  structure.py : reconstitue les chapitres des PDF sans sommaire
                  reparer_passages.py : reconstruit les passages en place
  ocr/            documents scannés -> couche texte
  embed/          vectorisation du corpus (e5-large, 1024 dimensions)
                  rapatrier.sh et enchainer.sh : téléchargement résistant aux coupures
  concepts/       ancrer.py : rattache les notions du glossaire au texte
  derive/         fiches, citations, quiz, comptes rendus + import depuis data/
  livre/          le module par ouvrage : état de production et orchestration
db/               schema.pg.sql (canonique) · migrations/ · verifier.sh
infra/docker/     postgres+pgvector, minio, redis, les composes et le déploiement
infra/caddy/      terminaison TLS, certificats automatiques
tests/            neuf suites de vérification, sur le corpus réel
docs/             MODELE-DONNEES.md · communication/ (cahier éditorial, bios)
marque/           logo et déclinaisons
livres/           corpus source classé par axe (hors dépôt)
data/             le corpus dérivé, source de vérité de la base
```

## Démarrer

```bash
cp .env.example .env            # ajuster les mots de passe et ANTHROPIC_API_KEY
cd infra/docker && docker compose --env-file ../../.env up -d
psql -h localhost -p 5450 -U ascenda -d ascenda -f ../../db/schema.pg.sql
python3 -m venv .venv && .venv/bin/pip install -r pipeline/requirements.txt
.venv/bin/python pipeline/ingest/ingest.py
```

## Ports (choisis pour cohabiter avec les autres stacks locales)

| Service | Port |
|---|---|
| PostgreSQL + pgvector | 5450 |
| MinIO API / console | 9250 / 9251 |
| Redis | 6390 |
| API | 8250 |
| Vitrine (Next.js) | 3251 |
| Application (build web Flutter, recette) | 3250 |

## Démarrer les surfaces

```bash
# API
.venv/bin/pip install -r apps/api/requirements.txt
cd apps/api && PYTHONPATH=. ../../.venv/bin/python -m uvicorn app.main:app --port 8250 --reload

# Vitrine
cd apps/web-vitrine && npm install && npm run build && npx next start -p 3251

# Application
cd apps/mobile && flutter pub get && flutter run --dart-define=API_URL=http://localhost:8250
```

Les migrations de `db/migrations/` sont idempotentes et se rejouent sans dommage :

```bash
for f in db/migrations/*.sql; do
  docker exec -i ascenda-postgres psql -U ascenda -d ascenda -v ON_ERROR_STOP=1 -f - < "$f"
done
```

## État du corpus

| | |
|---|---|
| Documents | 78, tous exploitables (15 601 pages) |
| Chapitres | 3 853 exploitables, sur 11 axes |
| Passages | 11 403 |
| Vectorisés | 11 403 sur 11 403, index HNSW et centroïdes d'axes posés |
| Dérivés | 2 304 quiz · 1 799 citations · 74 fiches de lecture |
| Glossaire | 610 notions, 419 ancrées dans le texte (5 160 occurrences) |

Le corpus est vectorisé, mais **aucun ouvrage n'est complet** : il manque 1 549
quiz, 2 054 citations et l'ensemble des comptes rendus. `pipeline/livre/etat.py`
dit où l'on en est, et `derive.py --estimer` ce que la suite coûtera.

Trois limites connues, à traiter dans le pipeline et non dans les applications :

1. **La recherche sémantique n'est pas dans l'image par défaut.** Elle demande
   deux gigaoctets de dépendances et autant de poids de modèle. Sans elles,
   l'API bascule en plein texte et le champ `mode` de la réponse le dit ; les
   clients l'affichent au lieu de laisser croire que le moteur comprend mal.
   Voir `infra/docker/README.md`.
2. **Structure reconstituée sur les 28 documents qui n'en avaient pas.**
   Vingt-sept PDF n'ont pas de sommaire interne : `pipeline/ingest/structure.py`
   les découpe en sections d'environ trente minutes, nommées « Pages 24 à 41 ».
   Ce n'est pas un sommaire et cela ne prétend pas l'être, mais c'est une
   consigne qu'un lecteur peut suivre. Les onze axes produisent désormais un
   parcours.
3. **7 ouvrages sur 78 sont redistribuables.** Pour les 71 autres, ASCENDA cite
   des extraits plafonnés avec leur page. C'est appliqué au centre de l'API,
   dans `services/droits.py`.

## Le corpus est la source, la base est le service

Les 620 fichiers de `data/` font autorité. La base ne fait que les servir.

```bash
python3 pipeline/derive/importer.py --verifier   # ce qui bougerait
python3 pipeline/derive/importer.py              # data/ -> base, idempotent
python3 pipeline/derive/importer.py --exporter   # base -> data/, ferme la boucle
```

L'import est rejouable : deux passages consécutifs donnent « inchangés » sur les
4 176 dérivés. Une contrainte d'unicité sur la clé naturelle (ouvrage, chapitre,
type) rend les doublons impossibles.

## Le module par ouvrage

```bash
python3 pipeline/livre/etat.py                       # l'état du corpus
python3 pipeline/livre/etat.py --doc 753e4ca2        # le détail d'un ouvrage
python3 pipeline/livre/produire.py --doc X --plan    # ce qui serait produit
python3 pipeline/livre/produire.py --doc X           # produire ce qui manque
```

La chaîne est reprenable : chaque étape ne produit que le manque. Ce qui est
produit va d'abord dans `data/`, puis en base.

## Vectorisation

```bash
python3 pipeline/embed/embed.py               # les chunks sans vecteur
python3 pipeline/embed/embed.py --index       # index HNSW, une fois les vecteurs posés
python3 pipeline/embed/embed.py --centroides  # centroïdes d'axes, pour le classement auto
```

## Paiement

Mobile money par Tara : MTN et Orange au Cameroun. La logique vient du module
`mail+paiement`, éprouvé en production, portée dans FastAPI plutôt que greffée
en Django. Quatre garanties, toutes vérifiées par des tests :

- une clé d'idempotence par paiement, rejouer un webhook ne crédite pas deux fois ;
- un rattachement en cascade, dont le repli par téléphone qui est le seul à
  fonctionner quand Tara ne renvoie pas notre identifiant ;
- une réconciliation périodique, avec abandon au bout de 24 heures ;
- un webhook qui répond toujours 200, pour ne pas déclencher de rejeu en boucle.

Tout laisse une trace dans `payment_event`. L'abonnement se ferme seul à
échéance : le compte repasse en `free` et les quotas referment l'accès.

## Tableau de bord d'exploitation

`/admin`, servi par l'API elle-même. Comptes ouverts et actifs, encaissé et
paiements par statut, abonnements et échéances, courriels, état du corpus, le
tout en un seul appel. Les webhooks orphelins et les courriels en échec passent
au rouge quand ils ne sont pas à zéro : le premier est peut-être l'argent de
quelqu'un. Voir [docs/EXPLOITATION.md](docs/EXPLOITATION.md).

Le droit d'administration se pose à la main en base et ne se demande par aucune
route.

## Les trois interrupteurs

Période de lancement, maintenance, version minimale d'application. Ils vivent
en base et se lisent sur `GET /v1/etat`, publique et sans jeton.

Le lancement ouvre les plafonds d'Ascension à tous **sans changer un seul
plan** : refermer revient à reculer une date, et on n'aura pas à distinguer
ensuite ceux qui ont payé de ceux à qui on avait offert. Une date de fin
referme toute seule.

La maintenance fige l'écran des applications, laisse passer les lectures et
refuse les écritures en 503. L'écran figé est une courtoisie, le 503 est la
garantie. Le webhook de Tara et la connexion restent ouverts, pour deux raisons
expliquées dans [docs/EXPLOITATION.md](docs/EXPLOITATION.md).

## Courrier transactionnel

Cinq messages par Brevo : bienvenue, reçu de paiement, rejet, rappel à sept
jours de l'échéance, avis de fin d'abonnement. Les gabarits vivent en base, ce
qui permet de corriger une faute sans redéployer, et un drapeau `actif` sert
d'interrupteur. Sans `BREVO_API_KEY`, les messages sont composés, tracés dans
`email_log` avec le statut `simule`, et ne quittent pas la machine.

La réinitialisation de mot de passe passe par un code à six chiffres, stocké
haché, valable trente minutes, à usage unique, cinq essais, une demande par
quart d'heure. Un lien profond aurait supposé un site déployé ; un code se
recopie depuis n'importe quel appareil.

## Réparer un corpus incomplet

```bash
python3 pipeline/ingest/structure.py --plan          # ce qui serait découpé
python3 pipeline/ingest/structure.py --tous          # reconstituer les chapitres
python3 pipeline/ingest/reparer_passages.py --tous   # reconstruire les passages manquants
python3 pipeline/concepts/ancrer.py                  # rattacher les notions au texte
```

Trois pièges rencontrés, corrigés, et qui se reproduiront sur un nouveau corpus :

- **La règle « moins de 400 caractères par page égale document scanné » se
  trompe** sur un recueil de proverbes, un lexique ou un beau livre. Le texte
  était parfaitement lisible, mais l'ouvrage n'a jamais reçu un seul passage.
- **La détection de chapitres par tout-majuscules attrape les pages de garde,
  les ISBN et les noms d'éditeur.** Un contrôle de vraisemblance rejette un
  découpage qui produit plus d'une section pour cinq pages, ou des titres
  répétés.
- **Le glossaire n'était rattaché à rien.** La table `concept_occurrence` était
  vide, ce qui rendait la révision espacée silencieusement inopérante.

## Pipeline

L'ingestion est **déterministe et rejouable** : aucun appel LLM, `pipeline_version`
permet de ne ré-ingérer que les documents en retard. Les dérivés pédagogiques sont
générés séparément (`pipeline/derive`) et versionnés avec leur modèle, leur version
de prompt et leur coût en tokens.
