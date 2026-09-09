# ASCENDA, lecture guidée

Trois surfaces : une **API**, un **site vitrine** public, une **application**
mobile, adossées à un corpus de 78 ouvrages (15 601 pages, 11 axes).

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
db/               schema.pg.sql (canonique) · schema.sql (SQLite local)
infra/docker/     postgres+pgvector, minio, redis
docs/             MODELE-DONNEES.md · PROMPT-CLAUDE-DESIGN.md
livres/           corpus classé par axe (hors dépôt)
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
| Dérivés | 2 304 quiz · 1 798 citations · 74 fiches de lecture |
| Glossaire | 610 notions, 419 ancrées dans le texte (5 160 occurrences) |

Trois limites connues, à traiter dans le pipeline et non dans les applications :

1. **Vectorisation en cours.** La recherche est hybride : plein texte et
   vecteur, fusionnés par rang réciproque. Tant que les vecteurs manquent, elle
   reste en plein texte et le champ `mode` de la réponse le dit. Aucun
   changement côté client le jour où ils arrivent.
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
