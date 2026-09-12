#!/usr/bin/env bash
# Pose le schéma de la base, une migration après l'autre.
#
#   ./infra/scripts/migrer.sh
#
# Les identifiants sont lus à l'intérieur du conteneur Postgres, où ils sont
# déjà posés : cela évite de charger le .env dans le shell du serveur, qui
# échouerait sur les valeurs entre guillemets, et cela ne suppose pas que
# POSTGRES_USER vaille encore « ascenda ».
set -uo pipefail

RACINE="$(cd "$(dirname "$0")/../.." && pwd)"
CONTENEUR="${CONTENEUR_PG:-ascenda-postgres}"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTENEUR"; then
  echo "Le conteneur $CONTENEUR ne tourne pas." >&2
  exit 1
fi

posees=0
for f in "$RACINE"/db/migrations/*.sql; do
  nom=$(basename "$f")
  printf '  %-28s ' "$nom"
  sortie=$(docker exec -i "$CONTENEUR" \
    sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -f -' < "$f" 2>&1)
  if [ $? -eq 0 ]; then
    echo "ok"
    posees=$((posees + 1))
  else
    echo "ÉCHEC"
    echo "$sortie" | tail -6 | sed 's/^/      /'
    echo
    echo "Arrêt à $nom. Les $posees migrations précédentes sont posées." >&2
    echo "Corrigez, puis relancez : les migrations sont écrites pour être rejouables." >&2
    exit 1
  fi
done

echo
echo "$posees migrations posées."
echo
echo "── ce que la base porte maintenant ──"
# Le SQL passe par l'entrée standard plutôt que par -c : trois couches de shell
# entre ici et psql font disparaître les apostrophes, et le récapitulatif
# échouait sur une erreur de syntaxe alors que les migrations, elles, étaient
# bien posées.
docker exec -i "$CONTENEUR" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tA' <<'SQL'
select 'tables      : ' || count(*) from information_schema.tables where table_schema = 'public';
select 'extensions  : ' || string_agg(extname, ', ') from pg_extension where extname <> 'plpgsql';
select 'ouvrages    : ' || count(*) from document;
select 'axes        : ' || count(*) from axis;
SQL
