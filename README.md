# ASCENDA

Lecture guidée sur un corpus d'ouvrages : un diagnostic, un chronogramme de
séances datées avec leurs pages, un quiz par séance et une révision espacée.

Trois surfaces : une API FastAPI, un site public Next.js, une application
mobile .NET MAUI.

## Arborescence

```
apps/api/           API FastAPI, console d'exploitation sur /admin
apps/web-vitrine/   site public (Next.js 16, React 19, Tailwind 4)
apps/mobile-dotnet/ application mobile (.NET MAUI 10, C#, XAML)
apps/mobile/        mise en forme de référence, servant de modèle au portage
packages/shared/    openapi.json figé et vérificateur de contrat
pipeline/           ingestion, OCR, vectorisation, dérivés pédagogiques
db/                 schema.pg.sql, migrations/, verifier.sh
infra/docker/       postgres+pgvector, minio, redis, composes
infra/caddy/        terminaison TLS
tests/              suites de vérification
data/               corpus dérivé, source de vérité de la base
```

## Ports

| Service | Port |
|---|---|
| PostgreSQL + pgvector | 5450 |
| MinIO API / console | 9250 / 9251 |
| Redis | 6390 |
| API | 8250 |
| Vitrine | 3251 |

## Installer

```bash
cp .env.example .env
cd infra/docker && docker compose --env-file ../../.env up -d
psql -h localhost -p 5450 -U ascenda -d ascenda -f ../../db/schema.pg.sql
python3 -m venv .venv && .venv/bin/pip install -r pipeline/requirements.txt
```

Les migrations de `db/migrations/` sont idempotentes :

```bash
./db/verifier.sh          # reconstruit la base à partir de rien et rejoue tout
```

## Lancer

```bash
# API
.venv/bin/pip install -r apps/api/requirements.txt
cd apps/api && PYTHONPATH=. ../../.venv/bin/python -m uvicorn app.main:app --port 8250 --reload

# Vitrine
cd apps/web-vitrine && npm install && npm run dev

# Application
cd apps/mobile-dotnet && dotnet build src/Ascenda.Mobile \
  -f net10.0-android -p:AdresseApi=http://10.0.2.2:8250
```

L'image `api` ne porte pas la recherche sémantique par défaut : elle demande
deux gigaoctets de dépendances (`apps/api/requirements-recherche.txt`). Sans
elles, l'API bascule en plein texte et le champ `mode` de la réponse le dit.

## Pipeline

```bash
.venv/bin/python pipeline/ingest/ingest.py              # fichier -> MinIO + base
.venv/bin/python pipeline/embed/embed.py                # vectorisation
.venv/bin/python pipeline/embed/embed.py --index        # index HNSW
.venv/bin/python pipeline/concepts/ancrer.py            # notions -> occurrences
.venv/bin/python pipeline/derive/importer.py            # data/ -> base, idempotent
.venv/bin/python pipeline/livre/etat.py                 # état de production
```

L'ingestion est déterministe et rejouable : `pipeline_version` permet de ne
reprendre que les documents en retard. Les dérivés pédagogiques sont produits
séparément et versionnés avec leur modèle et leur coût en jetons.

## Vérifier

```bash
./tests/lancer.sh                                       # l'API doit tourner
.venv/bin/python packages/shared/verifier_contrat.py    # contrat d'API
cd apps/mobile-dotnet && dotnet test tests/Ascenda.Noyau.Tests
```

## Déployer

```bash
cd /srv/ascenda && git fetch origin && git reset --hard origin/main
./infra/scripts/sauvegarde.sh && ./infra/scripts/migrer.sh
cd infra/docker && docker compose --env-file ../../.env \
  -f docker-compose.yml -f docker-compose.app.yml up -d --build api travailleur
```
