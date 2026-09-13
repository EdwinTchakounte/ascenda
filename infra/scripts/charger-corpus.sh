#!/usr/bin/env bash
# Charge sur le serveur le corpus exporté par exporter-corpus.sh.
#
#   ./infra/scripts/charger-corpus.sh corpus.dump
#
# Il refuse si la base porte déjà des ouvrages. Remplacer un corpus en place
# demanderait de vider `document`, et les chronogrammes, les séances et la
# progression des lecteurs y sont rattachés : un TRUNCATE en cascade les
# effacerait. Cette décision ne se prend pas dans un script.
set -euo pipefail

FICHIER="${1:-}"
CONTENEUR="${CONTENEUR_PG:-ascenda-postgres}"
[ -f "$FICHIER" ] || { echo "Usage : $0 <corpus.dump>" >&2; exit 1; }

# BASE=essai pour répéter sur une base jetable sans toucher à celle du service.
if [ -n "${BASE:-}" ]; then
  sql()     { docker exec -i "$CONTENEUR" psql -U "${UTIL:-ascenda}" -d "$BASE" -tA -v ON_ERROR_STOP=1; }
  restore() { docker exec -i "$CONTENEUR" pg_restore -U "${UTIL:-ascenda}" -d "$BASE" "$@"; }
else
  sql()     { docker exec -i "$CONTENEUR" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tA -v ON_ERROR_STOP=1'; }
  restore() { docker exec -i "$CONTENEUR" sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"' _ "$@"; }
fi

deja=$(echo "select count(*) from document;" | sql)
if [ "$deja" != "0" ]; then
  echo "La base porte déjà $deja ouvrages. Chargement refusé." >&2
  exit 1
fi

echo "Chargement, puis construction des index vectoriels : quelques minutes."
# --disable-triggers : les tables arrivent dans l'ordre de l'archive, pas dans
# celui des clés étrangères. Les contraintes sont vérifiées par les comptes
# ci-dessous, et par l'intégrité de l'archive d'origine.
restore --data-only --disable-triggers --no-owner < "$FICHIER"

sql <<'SQL'
analyze;
select 'ouvrages   : ' || count(*) from document;
select 'chapitres  : ' || count(*) from chapter;
select 'passages   : ' || count(*) || ', dont ' || count(embedding) || ' vectorisés' from chunk;
select 'axes       : ' || count(*) from axis;
select 'dérivés    : ' || count(*) from derivative;
select 'orphelins  : ' || (select count(*) from chunk c where not exists (select 1 from document d where d.id = c.document_id));
SQL
