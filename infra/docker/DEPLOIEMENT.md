# Mettre ASCENDA en ligne

Le domaine est **ascenda-books.online**. Ce document dit ce qu'il reste à faire
pour qu'un lecteur puisse ouvrir un compte et payer.

## 1. Les noms

Deux enregistrements, chez votre registraire, vers l'adresse IP du serveur.

| nom | type | valeur |
|---|---|---|
| `ascenda-books.online` | A | l'IP du serveur |
| `www.ascenda-books.online` | A | l'IP du serveur |
| `api.ascenda-books.online` | A | l'IP du serveur |

Ajoutez les enregistrements AAAA si le serveur a une adresse IPv6.

Caddy demande ses certificats au démarrage et refuse de partir tant qu'un nom
ne résout pas. C'est voulu : un certificat sur un nom qu'on ne contrôle pas
n'existe pas. Attendez la propagation avant de monter la pile.

## 2. Le fichier d'environnement

Copiez `.env.example` en `.env` et posez au minimum :

```bash
POSTGRES_PASSWORD=...                       # long et aléatoire
JWT_SECRET=$(openssl rand -base64 48)       # jamais la valeur par défaut
API_ENV=prod
PAIEMENT_TEST_AUTO_VALIDE=false             # sinon on ouvre l'accès sans encaisser

PUBLIC_BASE_URL=https://api.ascenda-books.online
SITE_BASE_URL=https://ascenda-books.online
API_CORS_ORIGINS=https://ascenda-books.online,https://www.ascenda-books.online

TARA_API_KEY=...
TARA_BUSINESS_ID=...
BREVO_API_KEY=...
CONTACT_EMAIL=contact@ascenda-books.online
```

L'API **refuse de démarrer** en `API_ENV=prod` si `JWT_SECRET` est resté à sa
valeur par défaut ou si `PAIEMENT_TEST_AUTO_VALIDE` est vrai. Ce n'est pas une
précaution excessive : ces deux réglages ouvrent l'un les comptes, l'autre la
caisse.

## 3. La pile

```bash
cd infra/docker
docker compose -f docker-compose.yml \
               -f docker-compose.app.yml \
               -f docker-compose.tls.yml up -d --build
```

Le troisième fichier ajoute Caddy et **retire la publication directe des ports**
de l'API et de la vitrine : sans cela, l'API resterait joignable en clair sur
8250 et toute la terminaison TLS ne servirait à rien.

Puis les migrations, une seule fois :

```bash
for f in ../../db/migrations/*.sql; do
  docker exec -i ascenda-postgres psql -U ascenda -d ascenda -v ON_ERROR_STOP=1 -f - < "$f"
done
```

## 4. Le corpus

La base montée est vide. Le corpus se charge depuis `data/`, qui est la source
de vérité :

```bash
.venv/bin/python pipeline/derive/importer.py
```

La vectorisation, elle, se fait hors du conteneur et prend des heures de
processeur. Sans elle, la recherche reste en plein texte et l'API le dit dans
le champ `mode`. Voir `pipeline/embed/`.

## 5. Déclarer le webhook chez Tara

L'adresse à leur donner :

```
https://api.ascenda-books.online/v1/paiements/webhook/tara
```

Elle doit être en HTTPS. Tara ne signe pas ses notifications : la sécurité du
webhook repose sur le fait que cette adresse est chiffrée et connue d'eux
seuls, plus la vérification du `businessId` que nous faisons de notre côté.

## 6. Vérifier

```bash
curl -s https://api.ascenda-books.online/sante
curl -s -o /dev/null -w "%{http_code}\n" https://ascenda-books.online/
curl -s https://ascenda-books.online/sitemap.xml | grep -c "<loc>"
```

La sonde de l'API interroge la base, pas seulement le processus : un `base: ok`
signifie que la connexion est réellement établie.

## Ce qui reste à faire à la main

**Les mentions légales.** Cinq champs affichent encore « à renseigner » :
forme juridique, immatriculation, adresse, téléphone, hébergeur. Ils se posent
par variables d'environnement et sont figés à la construction de l'image de la
vitrine, donc un `docker compose build vitrine` est nécessaire après les avoir
renseignés.

**L'application.** Déposez l'APK dans
`apps/web-vitrine/public/telechargements/ascenda.apk` avant de construire
l'image : la page `/commencer` la détecte et l'annonce avec son poids. Et
construisez-la contre le bon domaine :

```bash
flutter build apk --release --split-per-abi \
  --dart-define=API_URL=https://api.ascenda-books.online
```

**Les sauvegardes.** Le volume `ascenda_pgdata` porte les comptes, les
abonnements et la progression. `data/` reconstruit le corpus, pas les
utilisateurs. Rien dans ce dépôt ne sauvegarde quoi que ce soit.
