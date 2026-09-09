# ASCENDA, l'API

FastAPI + PostgreSQL. Sert la vitrine Next.js et l'application Flutter.

## Démarrer

```bash
# depuis la racine du dépôt
.venv/bin/pip install -r apps/api/requirements.txt
cd apps/api && PYTHONPATH=. ../../.venv/bin/python -m uvicorn app.main:app --port 8250 --reload
```

Documentation interactive : <http://localhost:8250/docs> · Santé : `/sante`

## Organisation

```
app/
  core/       config, pool Postgres, sécurité, dépendances, erreurs
  services/   droits, quotas, planificateur, révision espacée, agent
  routers/    une route par surface produit
  schemas/    contrats d'entrée et de sortie
```

Toutes les routes métier sont préfixées `/v1`.

## Deux décisions structurantes

**SQL écrit à la main, pas d'ORM.** `db/schema.pg.sql` fait autorité et le pipeline
d'ingestion parle déjà à cette base en SQL direct. Décrire une seconde fois le schéma
dans un ORM créerait deux vérités qui divergeraient au premier changement.

**Les droits sont un service, pas une vérification dispersée.** Sur 78 ouvrages,
7 sont redistribuables. `services/droits.py` calcule ce qui peut être servi, et le
lecteur, la recherche, le glossaire et l'agent passent tous par lui. Un plafond
d'extrait franchi devient impossible par construction plutôt que par discipline.

## Ce que fait le planificateur

`services/planner.py` compose un chronogramme **sans appeler de modèle de langage** :
le plan doit être reproductible, explicable et gratuit. Il ordonne les ouvrages selon
le niveau diagnostiqué, découpe les chapitres en séances d'une durée à peu près
constante, regroupe ce qui est trop court, et pose les séances sur des jours espacés.

Il écarte les 178 chapitres d'appareil (sommaires, bibliographies, index) identifiés
lors de la campagne de génération des quiz et enregistrés comme lots vides motivés.

## État connu

- **Recherche en plein texte, pas encore sémantique.** Les 11 395 chunks n'ont pas
  d'embedding (`chunk.embedding` est NULL partout). La recherche utilise `tsvector`
  français, qui répond en millisecondes. Le champ `mode` de la réponse vaut
  `plein_texte` ; il vaudra `semantique` quand les vecteurs seront calculés, sans que
  le contrat de sortie change.
- **Agent en mode dégradé sans `ANTHROPIC_API_KEY`.** Il renvoie alors les passages
  trouvés en le disant, plutôt qu'une réponse fabriquée.

## Variables d'environnement

Lues depuis le `.env` à la racine. En production, `JWT_SECRET` doit être posé :
l'API refuse de démarrer avec la valeur par défaut quand `API_ENV=prod`.

## Migrations

```bash
docker exec -i ascenda-postgres psql -U ascenda -d ascenda -v ON_ERROR_STOP=1 -f - < db/migrations/00X_....sql
```

Toutes les migrations sont idempotentes et rejouables.
