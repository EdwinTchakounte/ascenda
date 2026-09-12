#!/usr/bin/env bash
# Sauvegarde d'ASCENDA.
#
# Ce que ce script protège : les comptes, les abonnements, les paiements et la
# progression de lecture. `data/` reconstruit le corpus, le dépôt reconstruit le
# logiciel, mais rien ne reconstruit un utilisateur. Cette base est la seule
# chose du serveur qui n'existe nulle part ailleurs.
#
#   ./infra/scripts/sauvegarde.sh                 # vers ./sauvegardes
#   DESTINATION=/mnt/disque ./infra/scripts/sauvegarde.sh
#   GARDER=30 ./infra/scripts/sauvegarde.sh       # jours de rétention
#
# À poser dans une crontab, une fois par nuit :
#   17 3 * * * cd /srv/ascenda && ./infra/scripts/sauvegarde.sh >> /var/log/ascenda-sauvegarde.log 2>&1
set -euo pipefail

RACINE="$(cd "$(dirname "$0")/../.." && pwd)"
DESTINATION="${DESTINATION:-$RACINE/sauvegardes}"
GARDER="${GARDER:-14}"
CONTENEUR="${CONTENEUR_PG:-ascenda-postgres}"
HORODATAGE="$(date +%Y-%m-%d_%Hh%M)"

mkdir -p "$DESTINATION"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTENEUR"; then
  echo "Le conteneur $CONTENEUR ne tourne pas. Rien n'a été sauvegardé." >&2
  exit 1
fi

# `pg_dump` et non une copie du volume : copier des fichiers sous un moteur qui
# écrit donne une sauvegarde qui se restaure une fois sur deux. Le format
# personnalisé permet en plus de restaurer une seule table.
FICHIER="$DESTINATION/ascenda_${HORODATAGE}.dump"
echo "Sauvegarde de la base vers $FICHIER"
docker exec "$CONTENEUR" pg_dump -U "${POSTGRES_USER:-ascenda}" \
  -d "${POSTGRES_DB:-ascenda}" --format=custom --no-owner > "$FICHIER"

# Une sauvegarde qu'on n'a jamais ouverte n'est pas une sauvegarde. On vérifie
# au moins qu'elle se relit et qu'elle porte les tables attendues.
TABLES=$(docker exec -i "$CONTENEUR" pg_restore --list < "$FICHIER" | grep -c "TABLE DATA" || true)
if [ "$TABLES" -lt 10 ]; then
  echo "La sauvegarde ne porte que $TABLES tables : elle est suspecte." >&2
  exit 1
fi

gzip -f "$FICHIER"
POIDS=$(du -h "$FICHIER.gz" | cut -f1)
echo "Fait : $FICHIER.gz ($POIDS, $TABLES tables)"

# Le stockage objet porte les PDF d'origine. Ils sont lourds et se retrouvent
# dans `livres/`, donc on ne les sauvegarde pas ici : c'est un choix, pas un
# oubli. Si `livres/` n'existe plus nulle part, il faudra les ajouter.

echo "Purge au-delà de $GARDER jours"
find "$DESTINATION" -name 'ascenda_*.dump.gz' -mtime "+$GARDER" -print -delete

RESTANTES=$(find "$DESTINATION" -name 'ascenda_*.dump.gz' | wc -l)
echo "$RESTANTES sauvegarde(s) en réserve dans $DESTINATION"
