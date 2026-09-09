# Images de la vitrine

Toutes en **licence Unsplash** : usage commercial autorisé, aucune attribution
obligatoire, aucune autorisation à demander. La source est notée ici parce que
la règle du projet l'exige, et parce qu'une licence qu'on ne peut pas retrouver
est une licence qu'on ne peut pas défendre.

<https://unsplash.com/license>

| Fichier | Photo Unsplash | Usage |
|---|---|---|
| `lecture.jpg` | `photo-1481627834876-b7833e8f5570` | Hero, première diapositive |
| `bibliotheque.jpg` | `photo-1507842217343-583bb7270b66` | Hero, section bibliothèque |
| `etudier.jpg` | `photo-1456513080510-7bf3a84b82f8` | Hero, la méthode |
| `bureau.jpg` | `photo-1516979187457-637abb4f9353` | Section chronogramme |
| `mobile.jpg` | `photo-1524995997946-a1c2e315a42f` | Section application |

Rapatriées en 1400 px de large, qualité 70, format JPEG. Sur une connexion à
30 Ko/s, chaque image coûte quelques secondes : elles sont chargées en différé
sauf la première, et servies par le composant `next/image` qui les redimensionne
selon l'écran.
