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

- `/` : hero, les 11 axes, la méthode, le chronogramme en détail, les tarifs, la preuve.
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

**La vitrine reste affichable sans l'API.** C'est une page publique : elle ne peut
pas dépendre d'un service applicatif pour exister. `lib/api.ts` porte des valeurs
de repli tirées du corpus réel, et la bibliothèque affiche un état explicite
plutôt qu'une grille vide.

**Les règles de base sont dans `@layer base`.** Une déclaration hors couche
l'emporte sur toute utilitaire Tailwind : le `color` posé sur `h1` écrasait
sinon chaque `text-…` du site, et le titre du hero devenait illisible.

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
