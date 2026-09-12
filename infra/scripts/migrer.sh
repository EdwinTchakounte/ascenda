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

# Pour répéter sur une base jetable sans toucher à celle du service :
#   BASE=essai ./infra/scripts/migrer.sh
if [ -n "${BASE:-}" ]; then
  exec_pg() { docker exec -i "$CONTENEUR" psql -U "${UTIL:-ascenda}" -d "$BASE" "$@"; }
else
  exec_pg() { docker exec -i "$CONTENEUR" \
    sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"' _ "$@"; }
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTENEUR"; then
  echo "Le conteneur $CONTENEUR ne tourne pas." >&2
  exit 1
fi

# Ce que le guide oubliait, et qui faisait échouer le premier déploiement : les
# migrations sont des *incréments*. La première fait un ALTER TABLE sur
# `document`, qui n'existe que si le schéma de base a été posé avant. Sur la
# machine de développement la table était là depuis des mois, et rien ne le
# montrait ; sur une base neuve, tout s'arrête à la première ligne.
#
# On pose donc, dans cet ordre : les extensions, le schéma de base, puis les
# migrations. Les trois sont rejouables.
jouer() {
  local f="$1" titre="$2"
  printf '  %-28s ' "$titre"
  local sortie
  sortie=$(exec_pg -v ON_ERROR_STOP=1 -f - < "$f" 2>&1)
  if [ $? -eq 0 ]; then
    echo "ok"
    return 0
  fi
  echo "ÉCHEC"
  echo "$sortie" | tail -6 | sed 's/^/      /'
  return 1
}

echo "── les fondations ──"
jouer "$RACINE/infra/docker/initdb/00-extensions.sql" "extensions" || exit 1

# `schema.pg.sql` écrit vingt-cinq CREATE TABLE sans IF NOT EXISTS : c'est un
# schéma initial, il suppose une base vide et n'est pas rejouable. Le poser deux
# fois échoue sur « relation axis already exists ». On regarde donc d'abord si
# la base est neuve, au lieu de l'apprendre par une erreur.
deja=$(echo "select to_regclass('public.document') is not null;" | exec_pg -tA 2>/dev/null | tr -d '[:space:]')

if [ "$deja" = "t" ]; then
  printf '  %-28s %s\n' "schéma de base" "déjà posé, ignoré"
else
  jouer "$RACINE/db/schema.pg.sql" "schéma de base" || exit 1
fi

echo
echo "── les migrations ──"
posees=0
for f in "$RACINE"/db/migrations/*.sql; do
  nom=$(basename "$f")
  if jouer "$f" "$nom"; then
    posees=$((posees + 1))
  else
    echo
    echo "Arrêt à $nom. Les $posees migrations précédentes sont posées." >&2
    echo "Corrigez, puis relancez : tout ce script est rejouable." >&2
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
exec_pg -tA <<'SQL'
select 'tables      : ' || count(*) from information_schema.tables where table_schema = 'public';
select 'extensions  : ' || string_agg(extname, ', ') from pg_extension where extname <> 'plpgsql';
select 'ouvrages    : ' || count(*) from document;
select 'axes        : ' || count(*) from axis;
SQL
