#!/usr/bin/env bash
# Rapatrie le modèle de vectorisation, en résistant aux connexions qui meurent.
#
# La bibliothèque huggingface_hub attend indéfiniment quand le serveur ferme la
# connexion sans le dire : on a observé une socket en CLOSE-WAIT et quinze
# minutes sans un octet, sans qu'aucune erreur ne soit levée. curl, lui, sait
# détecter un débit mort et reprendre là où il s'est arrêté.
#
#   --speed-limit / --speed-time : abandonne si le débit passe sous 800 o/s
#                                  pendant 45 s, ce qui déclenche une reprise
#   --retry / --retry-all-errors : reprend, indéfiniment, avec un délai
#   -C -                         : reprend à l'octet où le fichier s'arrête
set -u

PARTIEL="${1:?chemin du fichier partiel}"
DESTINATION="${2:?chemin final}"
URL="https://huggingface.co/intfloat/multilingual-e5-large/resolve/main/model.safetensors"

echo "Reprise du téléchargement."
echo "  vers   : $PARTIEL"
echo "  départ : $(( $(stat -c%s "$PARTIEL" 2>/dev/null || echo 0) / 1024 / 1024 )) Mo"

# La boucle extérieure couvre le cas où curl abandonne malgré tout.
for essai in $(seq 1 200); do
  curl -sL -C - \
       --retry 50 --retry-delay 5 --retry-all-errors \
       --speed-limit 800 --speed-time 45 \
       --connect-timeout 30 \
       -o "$PARTIEL" "$URL"
  code=$?
  taille=$(stat -c%s "$PARTIEL" 2>/dev/null || echo 0)
  attendu=$(curl -sIL --max-time 30 "$URL" | grep -i '^content-length' | tail -1 | tr -d '\r' | awk '{print $2}')

  if [ -n "$attendu" ] && [ "$taille" -ge "$attendu" ]; then
    mv "$PARTIEL" "$DESTINATION"
    echo "Terminé : $(( taille / 1024 / 1024 )) Mo."
    exit 0
  fi
  echo "  essai $essai : $(( taille / 1024 / 1024 )) Mo / $(( ${attendu:-0} / 1024 / 1024 )) Mo (curl $code), reprise dans 10 s"
  sleep 10
done

echo "Abandon après 200 essais."
exit 1
