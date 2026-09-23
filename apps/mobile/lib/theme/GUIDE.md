# Guide d'interface de l'application

L'application a quatre thèmes (Ivoire, Nuit, Sépia, Forêt) et un mode
automatique. Chaque écran doit être juste dans les quatre : il ne choisit donc
jamais une teinte, il choisit un rôle.

## Couleurs : des rôles, pas des teintes

Lire la palette par `final p = context.palette;` (`lib/theme/palette.dart`).

| rôle | usage |
|---|---|
| `p.fond` | fond d'écran |
| `p.surface` | cartes, feuilles, champs |
| `p.surfaceCreuse` | bloc en retrait, piste de jauge, aplat secondaire |
| `p.encre` | titres, texte fort |
| `p.texte` | texte courant |
| `p.attenue` | texte secondaire, icônes discrètes |
| `p.trait` | filets et contours |
| `p.accent` / `p.surAccent` | bouton principal, élément actif (fond / texte dessus) |
| `p.accentTexte` | l'or lisible comme texte ou icône |
| `p.accentVoile` | voile doré derrière une icône ou un élément choisi |
| `p.succes`, `p.alerte` | réussite, retard ou erreur |
| `p.heros`, `p.herosFin`, `p.degradeHeros` | carte de mise en avant |
| `p.surHeros`, `p.surHerosDoux`, `p.accentSurHeros` | texte, texte secondaire, or sur la carte de mise en avant |

Interdits : `Colors.white` ou `Colors.black` comme fond ou texte (sauf texte
sur une teinte de pôle), `Color(0x...)` littéral, `Theme.of(context).brightness`
pour choisir une couleur à la main. Les anciens `Couleurs.xxx` fonctionnent
encore (ils lisent la palette) mais un écran repris passe à `context.palette`.

Les teintes de pôle (`Couleurs.pole(slug)`) sont fixes : texte blanc dessus.

## Formes

Arrondis doux partout, par `Rayons` : `petit` 10, `moyen` 14 (boutons,
champs, puces carrées), `carte` 20 (cartes), `grand` 28 (carte de mise en
avant, dialogues), `pilule` (pastilles, jauges, filtres). Aucun
`BorderRadius.zero`, aucun `BoxShape.rectangle` sans rayon.

## La matière : papier, encre, volumes (`lib/theme/papier.dart`, `lib/widgets/livre.dart`)

L'application est un atelier de lecture, pas un tableau de bord. Ce qui la
distingue :

- `FondPapier` : le grain du papier, dessiné, derrière chaque page. La coque
  l'applique aux onglets ; un écran ouvert en plein (fiche, lecteur) l'ajoute
  lui-même.
- `Filet()` et `Filet(redouble: true)` : les séparations sont des filets
  d'imprimeur, pas des `Divider` gris.
- `EtiquetteCrochet('séance du jour')` : le surtitre entre crochets, en petites
  capitales espacées.
- `Lettrine('A')` : la première lettre d'un chapitre ou d'une exergue.
- `TitreCourant('Mémento de l'agronome', folio: 'p. 244')` : l'en-tête d'une
  page de livre.
- `Fleuron()` : l'ornement qui clôt une section.
- `DosLivre`, `CouvertureLivre`, `Rayon` : un ouvrage se montre comme un volume,
  teinté par son pôle, avec ses nerfs et son filet doré. Jamais un rectangle
  gris, jamais une initiale dans un carré.

## Les icônes (`lib/theme/icones.dart`)

`IconeAscenda(Icone.volumes, taille: 24)`. Dix-huit dessins à la plume : soleil,
volumes, plume, pousse, cahier, lecteur, loupe, signet, page, cercle, cartes,
clef, sceau, jeton, boussole, question, encrier, fleche. Material n'est employé
que lorsque aucune de ces valeurs ne convient.

## Le mouvement (`lib/theme/mouvement.dart`)

- `Apparition(rang: i, child:)` : l'écran se pose bloc par bloc, une seule fois.
- `CompteurAnime(valeur)` : un chiffre monte jusqu'à sa valeur.
- `Respire(child:)` : une pulsation lente, un élément par écran au plus.
- Rien ne dépasse 420 ms, et tout s'efface sous le réglage « animations
  réduites » du téléphone.

## Les scènes dessinées (`lib/widgets/illustrations.dart`)

`Illustration(Scene.rayonVide, taille: 172)`, et `EtatMessage(..., scene:)`.
Un écran vide raconte un moment de lecture : rayon vide, lampe, graine, cercle
vide, sans réseau, laurier, page blanche, loupe vide.

## Briques (`lib/widgets/ui.dart`)

- `Surface` : la carte standard (arrondi 20, ombre légère, filet), `onTap` optionnel.
- `SurfaceHeros` : la carte de mise en avant, dégradé profond et halo doré. Une par écran au plus.
- `IconePastille(icone, couleur:, taille:)` : icône sur voile arrondi.
- `TitreSection('Titre', sousTitre:, action:, onAction:)` : titre de section.
- `Surtitre('texte')` : petites capitales dorées au-dessus d'un titre.
- `Pastille('texte', icone:, couleur:)` : étiquette sur voile, forme pilule.
- `Jauge(valeur:)` : barre de progression arrondie en dégradé d'or.
- `BoutonMenu()` et `AvatarCompte()` : en tête des onglets seulement.

## Mise en page

- Marges latérales de 20, espacement vertical régulier : 12 entre cartes d'une
  même liste, 22 à 28 entre sections.
- Un écran s'ouvre sur ce qui compte : une carte de mise en avant ou un titre
  fort en Fraunces (`headlineSmall` / `headlineMedium`), puis des sections
  titrées par `TitreSection`.
- Les listes d'éléments sont des `Surface` avec `IconePastille` à gauche, titre
  et détail au centre, chevron ou action à droite.
- Les chiffres importants se montrent grands (Fraunces), avec leur unité en
  petit et atténuée.
- Les états vides ou d'erreur passent par `EtatMessage` / `EtatErreur`.
- Rien ne déborde à 320 px de large ni avec une grande police : `maxLines` et
  `overflow` sur les textes en ligne, `Expanded` dans les rangées.

## Texte

Tout texte visible passe par `Texte` (`lib/theme/texte.dart`). En français,
sans tiret cadratin ni demi-cadratin. On ne change pas le sens des textes
existants ; on peut les raccourcir quand la mise en page l'exige.
