#!/usr/bin/env bash
# Restauration d'ASCENDA depuis une sauvegarde.
#
#   ./infra/scripts/restaurer.sh sauvegardes/ascenda_2026-09-12_03h17.dump.gz
#
# Cette opération écrase la base en place. Elle demande confirmation, et elle la
# demande vraiment : c'est la seule commande de ce dépôt qui peut effacer des
# comptes.
set -euo pipefail

FICHIER="${1:-}"
CONTENEUR="${CONTENEUR_PG:-ascenda-postgres}"

if [ -z "$FICHIER" ] || [ ! -f "$FICHIER" ]; then
  echo "Usage : $0 <fichier.dump.gz>" >&2
  exit 1
fi

echo "Vous allez écraser la base du conteneur $CONTENEUR par :"
echo "  $FICHIER"
echo "Les comptes, abonnements et paiements actuels seront remplacés."
read -r -p "Tapez « restaurer » pour confirmer : " reponse
[ "$reponse" = "restaurer" ] || { echo "Abandon."; exit 1; }

TEMPORAIRE=$(mktemp)
trap 'rm -f "$TEMPORAIRE"' EXIT
gunzip -c "$FICHIER" > "$TEMPORAIRE"

# `--clean --if-exists` remet la base à l'état du fichier plutôt que d'empiler
# les données par-dessus les existantes.
docker exec -i "$CONTENEUR" pg_restore -U "${POSTGRES_USER:-ascenda}" \
  -d "${POSTGRES_DB:-ascenda}" --clean --if-exists --no-owner < "$TEMPORAIRE"

echo "Restauré. Vérifiez avant de rouvrir le service :"
echo "  curl -s https://api.ascenda-books.online/sante"
