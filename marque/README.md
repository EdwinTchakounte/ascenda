# La marque ASCENDA

Déclinaisons produites à partir de `logo.png` (1536 x 1024), le logo d'origine :
un « A » doré portant une comète, une étoile et une silhouette aux bras levés,
sur bleu nuit, avec le lettrage ASCENDA et la baseline « Learn. Grow. Become. ».

| Fichier | Usage |
|---|---|
| `marque-512.png` `marque-192.png` `marque-64.png` | Le « A » seul, fond transparent. En-têtes, pieds de page, icônes. |
| `logo-complet.png` | Le bloc entier, fond transparent, **lettrage blanc**. Pour les fonds sombres. |
| `logo-complet-sombre.png` | Le même, **lettrage bleu nuit**. Pour les fonds clairs. |
| `mot-clair.png` `mot-sombre.png` | Le lettrage seul, quand la marque est déjà présente à côté. |
| `favicon-32.png` `apple-touch-icon.png` `icone-512.png` | Icônes, sur fond bleu nuit. |
| `partage-1200x630.jpg` | Aperçu des partages sur les réseaux et les messageries. |

## Ce qu'il faut savoir

**Le fond a été rendu transparent en suivant la luminosité**, pas par un seuil
brutal : l'anticrénelage du logo est conservé, ce qui évite les bords en escalier
aux petites tailles.

**Le lettrage du logo d'origine est blanc.** Sur un fond clair il disparaît, d'où
la variante sombre. Ne pas se tromper de fichier est la seule précaution à
prendre.

**Les icônes d'application gardent une marge de 16 %.** Les lanceurs Android et
iOS rognent les coins ; un logo qui touche le bord paraît mal cadré.

## Où elles sont utilisées

- `apps/web-vitrine/public/images/` et `apps/web-vitrine/src/app/` (favicon, icône iOS)
- `apps/mobile/assets/marque/`, `apps/mobile/android/.../mipmap-*`,
  `apps/mobile/ios/.../AppIcon.appiconset`, `apps/mobile/web/icons/`

## Régénérer

Les déclinaisons se recalculent depuis `logo.png` avec Pillow. Si le logo change,
il faut refaire les icônes de toutes les plateformes, pas seulement les images
web : un lanceur Android garde l'ancienne icône en cache jusqu'à réinstallation.
