#!/usr/bin/env bash
# Reconstruit la base à partir de rien, puis rejoue les migrations.
#
# La question à laquelle ce script répond : « le jour où l'on déploie sur une
# machine neuve, la base se construit-elle ? ». Elle ne se pose jamais pendant
# des mois, et elle se pose au pire moment.
#
# Elle avait déjà une mauvaise réponse : une substitution automatique avait
# laissé sept `\g<1>` dans la migration 002. La base de développement portait
# les changements, appliqués avant la corruption, et rien ne le montrait.
#
# Le second passage vérifie l'idempotence : rejouer une migration ne doit rien
# casser, puisque c'est ce qu'on fera à chaque montée de version.
#
#   ./db/verifier.sh
set -u
cd "$(dirname "$0")/.."

HOTE="${POSTGRES_HOST:-localhost}"
PORT="${POSTGRES_PORT:-5450}"
UTIL="${POSTGRES_USER:-ascenda}"
BASE="ascenda_verification"
export PGPASSWORD="${POSTGRES_PASSWORD:-ascenda_dev_pg}"

psql() { command psql -h "$HOTE" -p "$PORT" -U "$UTIL" -q "$@"; }

echec=0
jouer() {
  printf "  %-30s " "$(basename "$1")"
  if psql -d "$BASE" -v ON_ERROR_STOP=1 -f "$1" > /tmp/ascenda_verif.log 2>&1; then
    echo "ok"
  else
    echo "ÉCHEC"
    grep -iE "error" /tmp/ascenda_verif.log | head -2 | sed 's/^/      /'
    echec=1
  fi
}

echo "Reconstruction de la base sur une base vide"
psql -d postgres -c "drop database if exists $BASE;" > /dev/null 2>&1
psql -d postgres -c "create database $BASE;" > /dev/null 2>&1 || {
  echo "Impossible de créer $BASE. La base de développement doit tourner."; exit 1; }

jouer infra/docker/initdb/00-extensions.sql
jouer db/schema.pg.sql
for f in db/migrations/*.sql; do jouer "$f"; done

echo
echo "Rejeu des migrations : elles doivent être idempotentes"
for f in db/migrations/*.sql; do jouer "$f"; done

echo
tables=$(psql -d "$BASE" -tA -c "select count(*) from information_schema.tables where table_schema='public';")
echo "$tables tables construites."
psql -d postgres -c "drop database if exists $BASE;" > /dev/null 2>&1

if [ "$echec" -eq 0 ]; then
  echo "La base se reconstruit à partir de rien."
else
  echo "La base ne se reconstruit pas : un déploiement neuf échouerait."
fi
exit "$echec"
