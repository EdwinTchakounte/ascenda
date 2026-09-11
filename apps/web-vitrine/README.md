# ASCENDA, le site vitrine

Next.js 16 · React 19 · Tailwind 4. Écoute sur le port 3251.

## Démarrer

```bash
npm install
npm run dev        # http://localhost:3251 après avoir ajusté le port
npm run build && npx next start -p 3251
```

`NEXT_PUBLIC_API_URL` (dans `.env.local`) pointe vers l'API. Par défaut
`http://localhost:8250`.

## Pages

- `/` : hero, les 11 axes, l'étagère en relief, la méthode, le chronogramme en détail, les tarifs, la preuve.
- `/bibliotheque` : catalogue public, filtrable par axe.
- `/ouvrage/[id]` : la fiche d'un ouvrage, avec son balisage `Book`.
- `/axe/[slug]` : les ouvrages d'un axe, dans l'ordre où les lire.
- `/commencer` : les trois étapes, et les deux accès à l'application.
- `/connexion` : aiguillage vers l'application, qui porte les sessions.
- `/a-propos` : le projet, ses partis pris.
- `/droits` : les deux régimes du corpus et le mécanisme de plafond.
- `/retrait` : la marche à suivre pour un ayant droit, et nos délais.
- `/contact` : une adresse, un objet par type de demande.
- `/mentions-legales`, `/confidentialite` : les pages légales.
- `robots.txt` et `sitemap.xml` sont générés par `src/app/robots.ts` et `sitemap.ts`.

## Ce qui mérite d'être connu

**La troisième dimension est écrite à la main.** Le hero porte une poussière
d'étoiles en vraie perspective, les cartes d'axes s'inclinent sous le pointeur,
et la bibliothèque se présente en étagère tournante. Rien de tout cela ne passe
par une bibliothèque 3D : elle pèserait cent cinquante kilo-octets avant la
première image, et ASCENDA s'ouvre sur des connexions où cela se compte en
secondes d'attente. Ce qu'il faut savoir avant d'y toucher :

- `Poussiere3D` projette ses grains par `f / (f + z)`. Le rendu s'arrête dès que
  la section sort de l'écran ou que l'onglet passe en arrière-plan, et il ne
  démarre jamais si le système demande moins d'animation. Une seule image est
  tout de même dessinée dans ce cas : la profondeur reste, le mouvement part.
- `Relief` pose des variables CSS sur le noeud plutôt que de rendre à nouveau.
  Une grille de onze cartes qui rendrait soixante fois par seconde pour un effet
  décoratif serait payée par la batterie du lecteur. L'effet ne s'arme pas sur
  écran tactile : il n'y a pas de survol au doigt, seulement un temps d'attente
  avant que la carte réponde au clic.
- `Etagere3D` est un arc de cercle, pas une succession de vignettes inclinées.
  Chaque volume porte une tranche de pages à quatre-vingt-dix degrés du plat et
  un dos à la couleur de son pôle : de trois quarts, il se lit comme un objet.
  L'étagère tourne au doigt, à la souris, aux flèches du clavier, et toute seule
  quand personne n'y touche.
- `Apparition` ne cache jamais son contenu côté serveur. Une section invisible
  pour un moteur de recherche serait une section perdue : le masquage n'est posé
  qu'une fois le JavaScript en place, et pas du tout en mode sobre.

**La vitrine reste affichable sans l'API.** C'est une page publique : elle ne peut
pas dépendre d'un service applicatif pour exister. `lib/api.ts` porte des valeurs
de repli tirées du corpus réel, et la bibliothèque affiche un état explicite
plutôt qu'une grille vide.

**Les règles de base sont dans `@layer base`.** Une déclaration hors couche
l'emporte sur toute utilitaire Tailwind : le `color` posé sur `h1` écrasait
sinon chaque `text-…` du site, et le titre du hero devenait illisible.

**Chaque ouvrage et chaque axe porte son image de partage.** Elle est
composée à la volée par `opengraph-image.tsx` : titre, auteurs, axe, et la
mention de droits. Sans cela, les trente publications de la campagne auraient
toutes remonté la même vignette générique.

Deux règles pour ces images. **Aucune police n'est chargée depuis le réseau** :
un appel qui échoue produirait en silence une image de repli qu'on ne verrait
qu'au moment du partage, trop tard pour la corriger. Et **pas de caractère
typographique fin** : l'espace insécable étroite de `toLocaleString("fr-FR")`
n'a pas de glyphe dans la police du générateur, et « 1 497 pages » s'affichait
« 1▯497 pages ». Les milliers y sont séparés à la main.

**Le site existe pour être trouvé.** Deux pages indexées ne captent personne.
Le plan du site en compte 98 : les onze axes et les soixante-dix-huit ouvrages
s'y ajoutent, et chacun est une porte d'entrée qui arrive sur ce que le lecteur
cherchait vraiment. Une fiche d'ouvrage porte son balisage `schema.org/Book`,
sans jamais inventer un champ : ce qui n'est pas connu est absent du balisage,
pas rempli au jugé.

L'API accepte cent ouvrages par page au maximum, et le corpus tient dessous. Le
jour où il le dépassera, `sitemap.ts` devra paginer.

**Aucun lien ne doit tomber dans le vide.** Le site a longtemps eu huit liens
morts, dont `/commencer`, posé à trois endroits : c'était le bouton principal.
Un lien qui renvoie 404 sur une vitrine coûte le visiteur, pas seulement un code
HTTP. Après toute modification de la navigation, parcourez les liens internes et
vérifiez que tous répondent 200.

**Ce qui n'est pas connu s'affiche comme non connu.** `lib/editeur.ts` rassemble
l'identité de l'éditeur. Les champs que vous seul connaissez (forme juridique,
immatriculation, adresse, hébergeur) valent `null` par défaut, et les pages
légales affichent alors un encadré « à renseigner avant la mise en ligne ». Tant
qu'il est visible, la page n'est pas prête. Une mention légale inventée est pire
qu'une mention légale absente : elle donne l'apparence de la conformité tout en
étant fausse.

**Les variables `NEXT_PUBLIC_` sont figées à la construction.** Les pages légales
et `/commencer` sont pré-rendues : changer `NEXT_PUBLIC_APP_URL` ou l'identité de
l'éditeur demande un `docker compose build vitrine`, pas un redémarrage.

**Les chiffres viennent de la base.** 78 ouvrages, 15 601 pages, 11 axes, et le
volume de chaque axe sont lus à la construction, avec revalidation horaire.
