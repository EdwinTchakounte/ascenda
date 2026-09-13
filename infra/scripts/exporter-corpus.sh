#!/usr/bin/env bash
# Exporte le corpus seul, depuis la base où il a été fabriqué.
#
# Pourquoi ce script existe : `data/` ne porte que les dérivés (quiz, citations,
# fiches). Les ouvrages, leurs chapitres et leurs passages vectorisés naissent de
# l'ingestion des PDF de `livres/`, qui ne quittent pas la machine de travail.
# Un serveur neuf ne peut donc pas reconstruire le corpus depuis le dépôt : il
# faut lui transférer ces tables.
#
# Ce qui part : les ouvrages et tout ce qui en dépend. Ce qui ne part jamais :
# les comptes, les paiements, les abonnements, les courriels, la progression.
# La base de développement en porte des milliers, fabriqués par les tests.
#
#   ./infra/scripts/exporter-corpus.sh              # → corpus.dump
#   SORTIE=/tmp/c.dump ./infra/scripts/exporter-corpus.sh
set -euo pipefail

CONTENEUR="${CONTENEUR_PG:-ascenda-postgres}"
SORTIE="${SORTIE:-corpus.dump}"
# `chunk_texte_ocr_brut` n'y est pas : c'est une sauvegarde de travail du
# pipeline de reconnaissance de texte, qu'aucune migration ne crée. L'exporter
# faisait échouer le chargement sur une table absente du serveur.
TABLES=(axis document document_axis document_pedagogy document_prerequisite
        chapter chunk concept concept_occurrence
        controversy controversy_position derivative)

args=()
for t in "${TABLES[@]}"; do args+=(--table="public.$t"); done

docker exec "$CONTENEUR" sh -c "pg_dump -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" \
  --data-only --format=custom --no-owner $(printf '%q ' "${args[@]}")" > "$SORTIE"

# Un compte de test qui partirait vers la production serait une fuite : on le
# vérifie sur l'archive elle-même, pas sur la liste ci-dessus.
if docker exec -i "$CONTENEUR" pg_restore --list < "$SORTIE" \
   | grep -E "TABLE DATA public (app_user|payment|subscription|email_log|session|refresh_token)" ; then
  echo "L'archive contient des données de comptes. Rien ne doit partir." >&2
  rm -f "$SORTIE"; exit 1
fi

echo "Corpus exporté : $SORTIE ($(du -h "$SORTIE" | cut -f1))"
docker exec -i "$CONTENEUR" pg_restore --list < "$SORTIE" | grep "TABLE DATA" | awk '{print "  " $(NF-1)}'
