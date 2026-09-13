# Vidéos de la vitrine

Toutes deux sous **Mixkit Stock Video Free License** : usage commercial et non
commercial autorisé, modification autorisée, attribution non obligatoire. Texte
de la licence vérifié le 13 septembre 2026 sur <https://mixkit.co/license/>
(fenêtre « Stock Video Free License »). Les vidéos marquées « Restricted » sur
Mixkit ont été écartées.

| Fichier | Vidéo Mixkit | Usage |
|---|---|---|
| `hero-large.*` | n° 1724, « A person reading a book, close up » | Hero, ordinateur et tablette |
| `hero-haute.*` | n° 21603, « Conceptual video of book pages » (format vertical) | Hero, téléphone |

Source : `https://mixkit.co/free-stock-video/book/`, fichiers 720p.

## Traitement

Encodées avec ffmpeg 7 (binaire `imageio-ffmpeg`), sans piste son :

- la dernière seconde et deux dixièmes se fond dans le début, pour que la
  boucle ne se voie pas ;
- `hero-large` en 1280 x 720, `hero-haute` en 540 x 960, 24 images/s ;
- WebM VP9 pour les navigateurs qui le lisent, MP4 H.264 (`faststart`) pour
  les autres ;
- une image d'attente JPEG extraite de la première image.

Poids : 170 Ko (WebM) et 490 Ko (MP4) pour l'ordinateur, 330 Ko et 575 Ko pour
le téléphone. La vidéo n'est jamais chargée si le visiteur demande moins
d'animation ou active l'économiseur de données.
