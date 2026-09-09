#!/bin/bash
# Reprise des documents dont l'OCR incrémental (--skip-text) n'a rien donné :
# ces PDF portent une couche texte résiduelle (filigranes, numéros) qui faisait
# sauter les pages. --force-ocr rastérise et réocérise tout.
cd "$(dirname "$0")/../.."
for f in \
 "livres/05-IA-Education-Pedagogie/Enseigner avec IA-CIESD.pdf" \
 "livres/06-IA-Travail-Management-Metiers/L_intelligence artificielle dans le-tourisme.pptx.pdf" \
 "livres/05-IA-Education-Pedagogie/L_intelligence artificielle  generatives et Education_JP Berthet.pdf" \
 "livres/07-Afrique-Histoire-Pensee/L_Afrique-en-200-proverbes-Virginie-Ehonian.pdf" ; do
  [ -f "$f" ] || { echo "absent: $f"; continue; }
  out="${f%.pdf}.ocr.pdf"
  echo "→ $(basename "$f")"
  .venv/bin/ocrmypdf -l fra+eng --force-ocr --optimize 1 --jobs 4 \
      --output-type pdf "$f" "$out" && echo "   OK" || echo "   ECHEC"
done
echo "force-ocr terminé"
