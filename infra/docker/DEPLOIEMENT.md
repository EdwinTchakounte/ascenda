# Mettre ASCENDA en ligne

Le domaine est **ascenda-books.online**. Ce document dit ce qu'il reste à faire
pour qu'un lecteur puisse ouvrir un compte et payer.

## L'ordre, et pourquoi

Six étapes, dans cet ordre précis. Deux d'entre elles ne se rattrapent pas.

1. **Les noms d'abord**, parce que la propagation prend de vingt minutes à
   quelques heures et que rien ne peut être certifié sans elle. Posez-les avant
   de toucher au serveur.
2. Le dépôt sur le serveur, par une clé de déploiement : il est privé, un clone
   en HTTPS échoue sans rien dire d'utile. Puis le `.env`.
3. La pile, puis les migrations, puis le corpus.
4. **La sauvegarde, avant la première pièce encaissée.** Une base d'utilisateurs
   perdue ne se reconstruit pas, contrairement au corpus et au logiciel.
5. Le webhook chez Tara, qui ne peut être déclaré qu'une fois l'API en HTTPS.
6. L'APK, en dernier, et seulement une fois que l'API répond.

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

## Avant de monter la pile

Une commande, sur le serveur, qui vérifie tout ce qui fait échouer un
déploiement plus loin et plus obscurément :

```bash
./infra/scripts/preparatifs.sh
```

Elle contrôle Docker, la mémoire et le disque, la résolution des trois noms vers
cette machine précisément, les ports 80 et 443, et chaque variable du `.env` :
celles qui sont vides, celles restées à leur valeur de développement, celles qui
ne sont pas en HTTPS. Elle ne montre jamais la valeur d'un secret, seulement sa
longueur.

Tant qu'elle sort en erreur, ne montez pas la pile : vous perdriez du temps à
diagnostiquer par la bande ce qu'elle dit en une ligne.

## 2. Descendre le dépôt sur le serveur

Le dépôt est privé, et il doit le rester : `data/` porte des dérivés d'ouvrages
non redistribuables. Un `git clone` en HTTPS échoue donc sans rien dire d'utile,
et le répertoire n'est pas créé.

La bonne façon est une **clé de déploiement en lecture seule**. La clé privée
naît sur le serveur et n'en sort jamais ; seule la partie publique est collée
dans GitHub. Un jeton personnel ferait aussi l'affaire, mais il donne accès à
tous vos dépôts et il finit écrit en clair dans `.git/config`.

```bash
# 1. sur le serveur : fabriquer la paire
ssh-keygen -t ed25519 -C "ascenda-deploiement" -f ~/.ssh/ascenda_deploy -N ""
cat ~/.ssh/ascenda_deploy.pub        # à copier
```

Collez cette ligne dans GitHub : dépôt → Settings → Deploy keys → Add deploy
key. Laissez « Allow write access » décoché : le serveur descend le code, il ne
le remonte jamais.

```bash
# 2. sur le serveur : dire à ssh quelle clé sert pour ce dépôt
cat >> ~/.ssh/config <<'EOF'
Host github-ascenda
  HostName github.com
  User git
  IdentityFile ~/.ssh/ascenda_deploy
  IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config

# 3. vérifier, puis cloner
ssh -T github-ascenda                # doit répondre : Hi .../ascenda! ...
mkdir -p /srv && cd /srv
git clone github-ascenda:EdwinTchakounte/ascenda.git
cd ascenda
```

Les mises à jour suivantes tiennent en `git pull`.

Ne mettez jamais `2>/dev/null` sur un `git clone` : c'est précisément le message
d'erreur qui dit pourquoi il a échoué.

## 3. Le fichier d'environnement

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

# L'adresse doit être un expéditeur validé chez Brevo, sinon tous les envois
# sont refusés : pas de reçu, pas de réinitialisation de mot de passe. Les
# guillemets ne sont pas décoratifs, le chevron fait autrement de cette ligne
# une redirection dès qu'un script fait `source .env`.
MAIL_EXPEDITEUR="ASCENDA <ne-pas-repondre@ascenda-books.online>"
```

L'API **refuse de démarrer** en `API_ENV=prod` si `JWT_SECRET` est resté à sa
valeur par défaut ou si `PAIEMENT_TEST_AUTO_VALIDE` est vrai. Ce n'est pas une
précaution excessive : ces deux réglages ouvrent l'un les comptes, l'autre la
caisse.

## 4. La pile

### Si le serveur n'héberge que ce projet

```bash
cd infra/docker
docker compose --env-file ../../.env \
               -f docker-compose.yml \
               -f docker-compose.app.yml \
               -f docker-compose.tls.yml up -d --build
```

Caddy prend les ports 80 et 443 et demande les certificats lui-même.

### Si le serveur héberge déjà d'autres projets

C'est le cas de `81.0.246.144`, où un nginx tient déjà 80 et 443 pour six
autres sites. Caddy ne peut pas les prendre : on se place derrière ce nginx,
comme les autres projets de la machine.

```bash
cd infra/docker
docker compose --env-file ../../.env \
               -f docker-compose.yml \
               -f docker-compose.app.yml \
               -f docker-compose.serveur-partage.yml up -d --build
```

Cet assemblage fait deux choses qui comptent.

**Aucun port n'est publié sur l'hôte**, pas même sur la boucle locale. Rien
n'écoute sur la machine, donc rien ne peut être atteint par un autre projet ni
par un pare-feu mal réglé. Le nginx joint les services par leur nom sur le
réseau du compose, auquel on le rattache une fois :

```bash
docker network connect ascenda_default backend-nginx-1
```

Cela ne recrée pas le conteneur et ne touche pas au compose de l'autre projet.
Le rattachement est perdu si ce conteneur est recréé : la commande est à
rejouer, comme la copie des fichiers de site.

**Le marqueur `!override` n'est pas décoratif.** Compose *ajoute* les listes de
ports quand on superpose deux fichiers, il ne les remplace pas. Sans lui, l'API
gardait son `0.0.0.0:8250`, c'est à dire une API en clair ouverte sur Internet à
côté de six projets en production. Le défaut a été trouvé au banc d'essai, pas à
la lecture.

### `--env-file`, sans quoi rien n'est lu

Compose cherche son `.env` **dans le dossier du premier fichier compose**, donc
`infra/docker/.env`. Le nôtre est à la racine du dépôt. Sans `--env-file`, toutes
les variables partent vides, Compose le signale par une quinzaine
d'avertissements, et la pile monte avec un Postgres sans mot de passe et une API
sans secret.

Ces avertissements sont la seule chose à lire dans la sortie. S'ils sont là,
arrêtez : le `--env-file` manque.

### Le piège du 127.0.0.1 vu d'un conteneur

Ma première version faisait viser `127.0.0.1:8260` au nginx. Dans un conteneur,
cette adresse désigne le conteneur lui-même, pas la machine hôte : la requête ne
serait jamais arrivée, et le symptôme aurait été un 502 sans explication.

Deuxième piège, trouvé juste après : un bloc `upstream`, ou même un nom écrit en
clair dans `proxy_pass`, est résolu **au chargement** de la configuration. nginx
aurait refusé de démarrer tant qu'ASCENDA n'était pas monté, et aurait fait
tomber les six autres sites avec lui.

La configuration passe donc par une variable et le résolveur interne de Docker,
ce qui repousse la résolution au moment de la requête. nginx démarre quoi qu'il
arrive et répond 502 le temps qu'ASCENDA remonte. La contrepartie est qu'il faut
écrire `$request_uri` soi-même : avec une variable, nginx cesse d'ajouter le
chemin d'origine.

### La configuration du nginx, en deux temps

Il y a un piège d'ordre, et il vaut mieux le connaître avant de s'y prendre.
`ascenda.conf` déclare des `ssl_certificate` qui n'existent pas encore, et nginx
refuse de recharger sur un certificat introuvable : on ne peut donc pas poser la
configuration complète d'emblée. Mais sans aucune configuration, le nginx en
place laisse tomber les noms qu'il ne connaît pas, et la validation d'ACME
n'aboutit pas non plus. Vérifié sur le serveur : un nom qu'il sert répond 404,
les nôtres n'obtiennent rien du tout.

**Premier temps**, `ascenda-acme.conf`. Il ne parle qu'en clair, ne sert que le
chemin de validation, et répond « ASCENDA arrive » au reste. Il passe `nginx -t`
sans un seul certificat.

```bash
docker cp infra/nginx/ascenda-acme.conf backend-nginx-1:/etc/nginx/conf.d/ascenda.conf
docker exec backend-nginx-1 nginx -t && docker exec backend-nginx-1 nginx -s reload
curl http://ascenda-books.online/          # doit répondre « ASCENDA arrive. »
```

**Deuxième temps**, les certificats. Sur `81.0.246.144`, il n'y a ni certbot
sur l'hôte ni conteneur certbot permanent : les certificats des autres sites
vivent dans le volume Docker `backend_certbot_certs`, et ont donc été obtenus
par un conteneur jetable. On fait pareil.

```bash
docker run --rm \
  -v backend_certbot_certs:/etc/letsencrypt \
  -v backend_certbot_www:/var/www/certbot \
  certbot/certbot certonly --webroot -w /var/www/certbot \
    -d ascenda-books.online -d www.ascenda-books.online \
    -d api.ascenda-books.online \
    --agree-tos -m contact@ascenda-books.online --no-eff-email
```

Les deux volumes sont montés en lecture seule dans le nginx et en écriture ici :
c'est certbot qui écrit, nginx qui lit.

Demandez les trois noms **en une seule fois**. Certbot range alors tout sous le
premier nom, `/etc/letsencrypt/live/ascenda-books.online/`, et c'est ce chemin
que `ascenda.conf` vise pour ses trois blocs. Trois certificats séparés, ce
serait trois renouvellements à surveiller et des chemins à corriger.

**Le renouvellement.** Ces certificats durent trois mois. Comme il n'y a pas de
certbot permanent sur cette machine, il faut le programmer :

```
33 4 * * 1 docker run --rm -v backend_certbot_certs:/etc/letsencrypt -v backend_certbot_www:/var/www/certbot certbot/certbot renew --quiet && docker exec backend-nginx-1 nginx -s reload
```

Le rechargement du nginx après coup n'est pas facultatif : un certificat
renouvelé sur le disque n'est pas un certificat servi.

**Troisième temps**, la configuration complète, qui remplace la première.

```bash
docker cp infra/nginx/ascenda.conf backend-nginx-1:/etc/nginx/conf.d/ascenda.conf
docker exec backend-nginx-1 nginx -t && docker exec backend-nginx-1 nginx -s reload
```

Elle porte les trois blocs : la vitrine, l'API avec ses cent mégaoctets de dépôt
d'ouvrage et ses cinq minutes de délai, la redirection du clair vers le chiffré,
et les limites d'essais de mot de passe.

Si `ascenda.conf` vise un seul certificat couvrant les trois noms, corrigez les
chemins `ssl_certificate` du bloc de l'API : certbot range tout sous le premier
nom demandé.

`docker cp` plutôt qu'un montage : le nginx de ce serveur appartient au projet
afrikamode, dont seul `default.conf` est monté depuis l'hôte. Ses deux autres
fichiers de site, `gathe-finance.conf` et `horus.conf`, ont été copiés de la
même façon.

**La contrepartie, qu'il faut connaître :** une recréation du conteneur efface
ces fichiers, et les trois sites concernés tombent en même temps. Gardez donc
une copie sur l'hôte et un moyen de la remettre :

```bash
mkdir -p /srv/nginx-sites
cp /srv/ascenda/infra/nginx/ascenda.conf /srv/nginx-sites/
# après toute recréation du conteneur :
for f in /srv/nginx-sites/*.conf; do docker cp "$f" backend-nginx-1:/etc/nginx/conf.d/; done
docker exec backend-nginx-1 nginx -t && docker exec backend-nginx-1 nginx -s reload
```

Avant tout cela, une commande qui dit comment ce serveur est fait :

```bash
./infra/scripts/etat-serveur.sh
```

Elle ne modifie rien. Elle donne les ports libres, les montages du nginx, les
noms qu'il sert déjà, où il range ses certificats, et ce que le DNS répond.



```bash
cd infra/docker
docker compose -f docker-compose.yml \
               -f docker-compose.app.yml \
               -f docker-compose.tls.yml up -d --build
```

La pile monte cinq services : Postgres, le stockage objet, l'API, la vitrine et
**l'ouvrier**. Ce dernier ne répond à personne : il prend les travaux inscrits
depuis la console (ingestion d'un ouvrage déposé, reconstruction des chapitres,
import de `data/`) et les exécute hors de la requête HTTP. Sans lui, les dépôts
faits depuis la console resteraient éternellement en attente. Il monte
`pipeline/`, `data/` et `livres/` depuis le dépôt cloné, ainsi que le cache des
modèles, et on lui laisse deux minutes pour finir son travail en cours à
l'arrêt.

Puis les migrations, une seule fois. Les identifiants sont lus **à l'intérieur**
du conteneur Postgres, où ils sont déjà posés : cela évite de charger le `.env`
dans le shell du serveur, ce qui échouerait sur les valeurs entre guillemets. Et
la boucle s'arrête à la première migration qui casse, au lieu d'enchaîner sur
un schéma à moitié posé.

```bash
./infra/scripts/migrer.sh
```

Le script pose trois choses, dans cet ordre : les extensions, le **schéma de
base**, puis les douze migrations.

Cet ordre n'est pas décoratif. Les migrations sont des *incréments* : la
première fait un `ALTER TABLE` sur `document`, qui n'existe que si
`db/schema.pg.sql` a été posé avant. Le guide ne mentionnait pas ce fichier, et
le premier déploiement s'est arrêté sur « relation document does not exist ». Le
défaut ne se voyait pas en développement, où la table était là depuis des mois.

Le schéma de base, lui, n'est pas rejouable : ses vingt-cinq `CREATE TABLE` sont
écrits sans `IF NOT EXISTS`, ce qui est légitime pour un schéma initial. Le
script regarde donc si `document` existe déjà et l'ignore le cas échéant, au lieu
de l'apprendre par une erreur.

Il **s'arrête à la première étape qui casse**, en montrant son erreur, au lieu
d'enchaîner et de laisser un schéma à moitié posé. L'ensemble est rejouable :
après correction, on relance sans rien défaire.

Il finit par un récapitulatif, qui est la vraie vérification :

```
── les fondations ──
  extensions                   ok
  schéma de base               ok

── les migrations ──
  001_editions.sql             ok
  ...
12 migrations posées.

── ce que la base porte maintenant ──
tables      : 36
extensions  : vector, pg_trgm, unaccent, uuid-ossp
ouvrages    : 0
axes        : 0
```

Sur une base neuve, `ouvrages` et `axes` valent zéro : c'est l'import de `data/`
qui les apporte, à l'étape suivante. Si les quatre extensions ne sont pas là, ni
la recherche ni les identifiants ne fonctionneront.

Pour répéter sur une base jetable sans toucher à celle du service :

```bash
docker exec ascenda-postgres psql -U ascenda -d postgres -c "create database essai;"
BASE=essai ./infra/scripts/migrer.sh
```

### La mémoire, sur une machine déjà chargée

`81.0.246.144` porte onze gigaoctets, dont cinq libres, et fait déjà tourner
vingt-sept conteneurs. ASCENDA en ajoute cinq. Deux points de vigilance :

**Le modèle de recherche pèse deux gigaoctets.** Il n'est pas dans l'image : il
se télécharge à la première question posée à la recherche, et se charge en
mémoire. Sur cette machine, cela consomme d'un coup un tiers de ce qui reste.

L'API est écrite pour s'en passer : elle démarre sans le modèle, et la recherche
plein texte suffit à faire tourner le produit. Elle le dit dans le champ `mode`
de ses réponses. Vous pouvez donc ouvrir sans, regarder comment la machine tient,
et ne brancher la recherche sémantique que si la mémoire le permet.

**La construction de l'image demande environ deux gigaoctets.** Avec cinq libres
et vingt-sept conteneurs qui tournent, c'est faisable mais serré. Si le build
échoue en cours, ce n'est pas un défaut du Dockerfile : construisez ailleurs et
transférez.

```bash
# sur une machine confortable
docker save ascenda-api:latest ascenda-vitrine:latest | gzip > ascenda-images.tar.gz
scp ascenda-images.tar.gz root@81.0.246.144:/srv/
# sur le serveur
gunzip -c /srv/ascenda-images.tar.gz | docker load
```

**Le disque.** Trente-trois gigaoctets libres sur quatre-vingt-seize. Les deux
images pèsent sept cent cinquante mégaoctets, le cache du modèle deux
gigaoctets, la base et le stockage objet grandissent avec les lecteurs, et les
sauvegardes s'accumulent. Posez `GARDER=14` sur la sauvegarde et surveillez.

## 5. Le corpus

La base montée est vide. Le corpus se charge depuis `data/`, qui est la source
de vérité. Un serveur n'a que Docker, pas de Python ni de `.venv` : l'import
passe donc par un service dédié, qui monte `pipeline/` et `data/` depuis le
dépôt cloné.

```bash
cd infra/docker
docker compose --env-file ../../.env -f docker-compose.yml -f docker-compose.app.yml \
  run --rm importeur --verifier    # ce qui bougerait, sans rien écrire
docker compose --env-file ../../.env -f docker-compose.yml -f docker-compose.app.yml \
  run --rm importeur               # data/ vers la base
```

L'import est idempotent : deux passages consécutifs annoncent « inchangés » sur
les 4 176 dérivés. Le service reste à l'écart des montées de pile, il ne
démarre que lorsqu'on l'appelle par son nom.

La vectorisation, elle, se fait hors du conteneur et prend des heures de
processeur. Sans elle, la recherche reste en plein texte et l'API le dit dans
le champ `mode`. Voir `pipeline/embed/`.

## 6. La console, et le premier administrateur

La console d'exploitation voyage avec l'image de l'API : il n'y a rien de plus à
déployer. Une fois la pile montée, elle est à

```
https://api.ascenda-books.online/admin
```

**Mais personne ne peut y entrer.** Sur une base neuve il n'existe aucun compte,
et le droit d'administration ne se demande par aucune route : c'est voulu, une
route qui accorde ce droit est une route qu'on attaque. Deux gestes, une seule
fois :

```bash
# 1. Créer le compte comme n'importe quel lecteur, par l'API.
curl -sS -X POST https://api.ascenda-books.online/v1/auth/inscription \
  -H 'Content-Type: application/json' \
  -d '{"email":"vous@exemple.com","mot_de_passe":"...","nom":"..."}'

# 2. Lui donner le droit, en base.
docker exec -i ascenda-postgres psql -U ascenda -d ascenda \
  -c "update app_user set est_admin = true where email = 'vous@exemple.com';"
```

Le mot de passe ne passe pas par le `.env` ni par un fichier : il est haché par
l'API à l'inscription, et personne d'autre que vous ne l'aura vu.

On ne peut pas se retirer son propre droit depuis la console. C'est le moyen le
plus simple de se verrouiller dehors un dimanche soir.

### Ce qui protège cette adresse

La console est publique au sens où son adresse répond à tout le monde : elle
sert alors sa page de connexion, et rien d'autre. Le refus opposé à un compte
ordinaire ne dit même pas qu'un espace d'administration existe.

L'API, elle, ne compte pas les essais de mot de passe ratés. Sans limite, rien
n'empêche d'en essayer dix mille par minute sur un compte d'administration.
`infra/nginx/ascenda.conf` pose donc la limite au niveau du nginx : cinq essais
par minute et par adresse sur les routes qui vérifient un mot de passe, avec une
réserve de cinq pour ne pas punir quelqu'un qui se trompe deux fois de suite. Le
reste de l'API est à trente requêtes par seconde, et le webhook de Tara n'est pas
limité du tout : c'est leur serveur qui appelle, et une notification refusée est
un paiement qu'on ne rattache pas.

Si vous voulez une serrure de plus, ajoutez dans le bloc de l'API :

```nginx
location /admin { allow VOTRE.IP.FIXE; deny all; proxy_pass http://ascenda_api; }
```

Cela suppose une adresse fixe. Sans elle, la limitation d'essais et le mot de
passe suffisent.

## Mettre en ligne sans les clés

C'est un état légitime, et il vaut mieux ouvrir avec une caisse fermée qu'avec
une caisse qui fait semblant. Ce qui se passe alors :

**Le paiement.** Sans `TARA_API_KEY`, le service refuse d'initier en production
et renvoie « le paiement n'est pas encore ouvert, votre compte reste utilisable
en attendant ». Il ne renvoie pas de référence factice : un lecteur qui croit
avoir payé et n'est jamais débité coûte plus cher qu'un bouton indisponible.

**Les courriels.** Sans `BREVO_API_KEY`, chaque envoi est journalisé en mode
`simule` et n'arrive nulle part. La console le montre dans son journal des
envois. Conséquence concrète : la réinitialisation de mot de passe est
inopérante, personne ne reçoit son lien. Dites-le sur la page contact tant que
la clé manque.

**Les mentions légales.** Elles sont figées à la construction de l'image de la
vitrine. Les laisser vides maintenant oblige à un `docker compose build vitrine`
quand vous les aurez, et à remonter le service. Ce n'est pas grave, c'est deux
minutes, mais autant le savoir.

**Ce qu'il est raisonnable de faire en attendant.** Ouvrir la période de
lancement depuis la console, vue « Les interrupteurs » : tout le corpus devient
accessible sans abonnement, ce qui rend l'absence de caisse cohérente plutôt que
frustrante.

## 7. Déclarer le webhook chez Tara

L'adresse à leur donner :

```
https://api.ascenda-books.online/v1/paiements/webhook/tara
```

Elle doit être en HTTPS. Tara ne signe pas ses notifications : la sécurité du
webhook repose sur le fait que cette adresse est chiffrée et connue d'eux
seuls, plus la vérification du `businessId` que nous faisons de notre côté.

## 8. Vérifier

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
cp apps/mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
   apps/web-vitrine/public/telechargements/ascenda.apk
```

**Ne déposez pas l'APK avant que l'API ne réponde.** La page `/commencer`
n'affiche le bouton que si le fichier est là : le mettre en place trop tôt
revient à proposer une application qui s'ouvre sur « pas de connexion ». Sans le
fichier, la page dit que l'application n'est pas encore publiée, ce qui est
exact et ne coûte personne.

L'adresse de l'API est **figée à la construction** de l'APK. Une application
construite contre `localhost` ne joindra jamais le serveur, quel que soit le
réglage côté machine : il faut la reconstruire.

**Les sauvegardes.** Le volume `ascenda_pgdata` porte les comptes, les
abonnements, les paiements et la progression. `data/` reconstruit le corpus, le
dépôt reconstruit le logiciel, mais rien ne reconstruit un utilisateur.

```bash
./infra/scripts/sauvegarde.sh                      # vers ./sauvegardes
DESTINATION=/mnt/disque GARDER=30 ./infra/scripts/sauvegarde.sh
```

Le script fait un `pg_dump` au format personnalisé et non une copie du volume :
copier des fichiers sous un moteur qui écrit donne une sauvegarde qui se
restaure une fois sur deux. Il refuse d'aboutir si l'archive porte moins de dix
tables, parce qu'une sauvegarde vide qui réussit en silence est pire que pas de
sauvegarde du tout.

À poser en crontab dès le premier jour, avant d'ouvrir la caisse :

```
17 3 * * * cd /srv/ascenda && ./infra/scripts/sauvegarde.sh >> /var/log/ascenda-sauvegarde.log 2>&1
```

La restauration écrase la base en place et demande confirmation :

```bash
./infra/scripts/restaurer.sh sauvegardes/ascenda_2026-09-12_03h17.dump.gz
```

Une sauvegarde qu'on n'a jamais restaurée n'est pas une sauvegarde. Celle-ci a
été essayée : soixante-deux mégaoctets, trente-sept tables, restaurées dans une
base jetable, mille cent soixante-treize comptes et onze mille quatre cent trois
segments retrouvés intacts. Refaites cet essai sur le serveur une fois par
trimestre.
