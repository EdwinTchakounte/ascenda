# Déploiement

Deux fichiers, deux cycles de vie.

- `docker-compose.yml` porte le **socle** : PostgreSQL avec pgvector, MinIO,
  Redis. On y touche une fois par an.
- `docker-compose.app.yml` porte l'**application** : l'API et la vitrine. On la
  redéploie souvent.

```bash
cd infra/docker

# Socle seul, pour développer avec l'API lancée à la main
docker compose --env-file ../../.env up -d

# Tout, y compris l'API et la vitrine
docker compose --env-file ../../.env \
  -f docker-compose.yml -f docker-compose.app.yml up -d --build
```

## Avant la première mise en production

Trois réglages du `.env` ne pardonnent pas :

| Variable | Pourquoi |
|---|---|
| `JWT_SECRET` | `openssl rand -base64 48`. L'API refuse de démarrer avec la valeur de développement quand `API_ENV=prod`. |
| `PAIEMENT_TEST_AUTO_VALIDE` | Doit valoir `false`. Il valide les paiements sans encaissement. L'API refuse également de démarrer s'il est actif en production. |
| `PUBLIC_BASE_URL` | L'adresse publique de l'API. Elle sert à construire l'URL de notification envoyée à Tara : fausse, aucun paiement ne sera confirmé. |

Les migrations ne se jouent pas toutes seules. Après la première montée :

```bash
for f in db/migrations/*.sql; do
  docker exec -i ascenda-postgres psql -U ascenda -d ascenda -v ON_ERROR_STOP=1 -f - < "$f"
done
```

Elles sont idempotentes : les rejouer ne fait aucun mal, et `./db/verifier.sh`
l'établit à chaque passage de la suite en reconstruisant une base jetable de
zéro, puis en rejouant tout une seconde fois.

Les extensions PostgreSQL (`vector`, `pg_trgm`, `unaccent`, `uuid-ossp`) sont
posées par `infra/docker/initdb/00-extensions.sql`, monté dans le conteneur de
base. Sans elles, le schéma s'arrête à la première colonne `vector` : c'est le
premier symptôme d'une base montée à la main plutôt que par le compose.

## La recherche sémantique n'est pas dans l'image par défaut

L'image de l'API pèse 340 mégaoctets et ne sait chercher que par les mots. La
recherche par le sens demande `sentence-transformers` et `torch`, soit deux
gigaoctets de dépendances, plus deux gigaoctets de poids de modèle téléchargés
au premier démarrage. Sur nos connexions, c'est une décision, pas un détail.

Ce n'est pas une panne : l'API le voit, le journalise, bascule en plein texte et
l'annonce à ses clients dans le champ `mode` de la réponse. L'application mobile
affiche « par les mots » au lieu de « mots et sens ». Personne ne croit que le
moteur comprend mal ; il cherche autrement, et il le dit.

Pour l'activer :

```bash
RECHERCHE_SEMANTIQUE=true docker compose \
  -f docker-compose.yml -f docker-compose.app.yml up -d --build
```

Le volume `ascenda_modeles` conserve les poids entre deux recréations du
conteneur. Sans lui, chaque `docker compose up --force-recreate` reprend les
deux gigaoctets depuis le début.

Rappel : la vectorisation du corpus, elle, se fait hors du conteneur avec
`pipeline/embed/`. Sans vecteurs en base, la recherche reste en plein texte même
avec les dépendances installées, et le seuil est de 95 % du corpus vectorisé.

## Ce que le compose ne fait pas

**Il ne termine pas devant Internet.** Il n'y a ni certificat ni redirection
vers HTTPS. Or Tara ne signe pas ses notifications : la sécurité du webhook
repose entièrement sur le fait que son adresse est en HTTPS et connue d'eux
seuls. Un rappel de proxy inverse, Caddy ou Traefik, est donc obligatoire avant
d'encaisser le premier franc.

**Il ne sauvegarde rien.** Le volume `ascenda_pgdata` porte les comptes, les
abonnements et la progression. `data/` reconstruit le corpus, pas les
utilisateurs.

**Il ne vectorise pas.** Le modèle pèse deux gigaoctets et l'encodage prend des
heures de processeur : cela se fait une fois, hors du conteneur, avec
`pipeline/embed/`.

## Vérifier une image avant de la pousser

L'image se construit depuis la racine du dépôt, pas depuis `apps/api` : elle a
besoin de `db/migrations`.

```bash
docker build -f apps/api/Dockerfile -t ascenda-api:local .
docker run -d --name essai --network host \
  -e POSTGRES_HOST=localhost -e POSTGRES_PORT=5450 \
  -e POSTGRES_DB=ascenda -e POSTGRES_USER=ascenda -e POSTGRES_PASSWORD=... \
  -e API_ENV=dev -e JWT_SECRET=essai-local-uniquement \
  -e PAIEMENT_TEST_AUTO_VALIDE=true \
  ascenda-api:local
curl -s localhost:8250/sante
ASCENDA_API=http://127.0.0.1:8250 ./tests/lancer.sh
docker rm -f essai
```

Deux points valent d'être dits, parce qu'ils ont chacun coûté une construction :

**Le conteneur ne lit aucun `.env`.** Le fichier reste sur la machine de
développement, hors de l'image. Tout ce dont l'API a besoin passe par `-e`.
C'est aussi pourquoi `PAIEMENT_TEST_AUTO_VALIDE=true` est nécessaire pour un
essai complet : sans lui, le paiement de la suite reste en attente, l'abonnement
ne s'ouvre pas et quatre vérifications tombent. Ce n'est pas une panne, c'est le
comportement de production. Ne posez jamais ce drapeau ailleurs qu'en essai.

**La suite tourne contre l'image, pas contre le code source.** C'est le seul
moyen de voir qu'une dépendance manque au `requirements.txt` : en local, le
paquet est déjà dans le `.venv` et rien ne se voit.

## Le contexte de construction

Sans `.dockerignore`, `docker build` envoyait au démon les quatre gigaoctets et
demi du dépôt avant de lire la première instruction : le `.venv`, les
`node_modules`, les 975 mégaoctets d'artefacts Android et surtout les 889
mégaoctets de PDF du corpus. L'API lit la base, pas les fichiers sources : rien
de tout cela n'a sa place dans une image.

Le contexte pèse maintenant 24 mégaoctets, dont 19 pour l'APK proposée au
téléchargement. Une construction de l'API qui prenait plusieurs minutes se
termine en trois secondes quand les couches de dépendances sont en cache.

Le fichier exclut aussi `.env` et ses variantes. Un `.env` copié dans une image
y reste, en clair, pour quiconque sait faire `docker history`.

## L'APK dans l'image de la vitrine

`apps/web-vitrine/public/telechargements/ascenda.apk` est servie par le site et
détectée à la construction : la page `/commencer` l'annonce avec son poids réel.
Le binaire n'est pas versionné, il se dépose avant de construire l'image.

```bash
cp apps/mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
   apps/web-vitrine/public/telechargements/ascenda.apk
docker compose -f infra/docker/docker-compose.app.yml build vitrine
```

Sans ce fichier, la page dit que l'application n'est pas encore publiée, au lieu
d'afficher un bouton qui ne mène nulle part.
