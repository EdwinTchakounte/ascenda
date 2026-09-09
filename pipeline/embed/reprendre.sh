#!/usr/bin/env bash
# Reprend la vectorisation là où elle s'est arrêtée, puis construit l'index et
# les centroïdes. Le modèle est déjà rapatrié : plus rien à attendre.
#
# La vectorisation s'était interrompue à 1 664 passages sur 11 403, sans trace :
# le processus vit dans le terminal qui l'a lancé et meurt avec lui. On le
# détache donc, et on écrit un journal pour savoir, plus tard, où il en était.
#
#   setsid nohup pipeline/embed/reprendre.sh > pipeline/embed/vectorisation.log 2>&1 &
set -u
cd "$(dirname "$0")/../.."

echo "[$(date '+%d/%m %H:%M')] Reprise de la vectorisation."
.venv/bin/python pipeline/embed/embed.py --lot 128 || { echo "Vectorisation en échec."; exit 1; }

echo "[$(date '+%d/%m %H:%M')] Index HNSW."
.venv/bin/python pipeline/embed/embed.py --index || exit 1

echo "[$(date '+%d/%m %H:%M')] Centroïdes des axes."
.venv/bin/python pipeline/embed/embed.py --centroides || exit 1

echo "[$(date '+%d/%m %H:%M')] Terminé. La recherche bascule en hybride au prochain démarrage de l'API."
