#!/usr/bin/env bash
# Attend la fin du rapatriement du modèle, puis vectorise, puis construit
# l'index et les centroïdes. Pensé pour tourner sans surveillance : sur une
# connexion à 13 Ko/s, personne ne va veiller dix heures devant un écran.
set -u
cd "$(dirname "$0")/../.."
DESTINATION="${1:?chemin du fichier de poids}"

echo "[$(date '+%H:%M')] En attente du modèle."
while [ ! -f "$DESTINATION" ]; do
  sleep 120
done
echo "[$(date '+%H:%M')] Modèle complet : $(( $(stat -c%s "$DESTINATION") / 1024 / 1024 )) Mo."

echo "[$(date '+%H:%M')] Vectorisation des 11 395 passages."
.venv/bin/python pipeline/embed/embed.py --lot 128 || { echo "Vectorisation en échec."; exit 1; }

echo "[$(date '+%H:%M')] Index HNSW."
.venv/bin/python pipeline/embed/embed.py --index

echo "[$(date '+%H:%M')] Centroïdes des axes."
.venv/bin/python pipeline/embed/embed.py --centroides

echo "[$(date '+%H:%M')] Terminé. La recherche bascule en mode hybride au prochain démarrage de l'API."
