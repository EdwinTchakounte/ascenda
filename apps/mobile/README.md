# ASCENDA, l'application mobile

Flutter 3.41 · Riverpod · go_router. Consomme l'API sur le port 8250.

## Démarrer

```bash
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:8250   # émulateur Android
flutter run --dart-define=API_URL=http://localhost:8250  # iOS, bureau, web
```

`API_URL` vaut `http://localhost:8250` par défaut. Sur un appareil physique,
utiliser l'adresse IP de la machine hôte.

## Organisation

```
lib/
  theme/       palette et thèmes clair et sombre
  api/         client HTTP, modèles
  etat/        session et fournisseurs Riverpod
  ecrans/      un fichier par écran
  widgets/     composants partagés, dont les états vides et hors ligne
  routes.dart  navigation et redirections
```

## Écrans

Cinq onglets : Aujourd'hui, Bibliothèque, Agent, Progression, Profil.
Hors onglets : bienvenue, connexion, diagnostic, fiche d'ouvrage, lecteur, quiz,
chronogramme, révision, abonnement, recherche dans le corpus, glossaire et
fiche de notion, fiche d'axe, quiz d'un ouvrage, mot de passe oublié,
changement de mot de passe.

## Ce qui mérite d'être connu

**L'angle droit se pose au thème, pas écran par écran.** Material dessine ses
propres formes par défaut, et elles sont toutes arrondies : la pastille en stade
derrière l'icône active de la barre de navigation, le voile de survol des
boutons de texte, les extrémités des barres de progression, les boîtes de
dialogue, les feuilles du bas, les infobulles. Les redresser dans `theme.dart`
est le seul endroit où la règle tient sans qu'on ait à y penser à chaque écran.

**Chaque ouvrage porte la teinte de son pôle** sur le bord gauche de sa carte,
la même que sur la vitrine et que le dos de ses volumes sur l'étagère. La
palette vit dans `Couleurs.poles`, indexée par le préfixe du raccourci, qui ne
change jamais une fois posé. Une liste de soixante cartes blanches ne dit pas de
quoi elle est faite.

**On peut revoir l'application sans téléphone.** `flutter build web` puis un
serveur statique, et la charger dans un cadre de 400 par 844 : les règles de
mise en page sont les mêmes. Il faut alors ajouter l'origine du serveur à
`API_CORS_ORIGINS`, sans quoi l'application affiche « Pas de connexion ».


**Le routeur n'est pas reconstruit à chaque changement de session.** Il écoute un
`ChangeNotifier`. Le reconstruire ramenait l'application à sa route initiale, et
l'utilisateur atterrissait sur l'accueil au lieu du diagnostic après inscription.

**Les états vides, hors ligne et de quota sont dessinés, pas subis.**
`widgets/etats.dart` traduit une exception en écran compréhensible : un réseau
coupé ne dit pas la même chose qu'un quota atteint ou qu'une fonction payante.

**Les axes sans parcours possible sont désactivés dans le diagnostic.** Deux axes
du corpus n'ont aucun ouvrage découpé en chapitres : les proposer conduirait à un
échec après six questions.

**La bibliothèque se charge par pages de vingt-quatre.** Elle demandait les
soixante-dix-huit ouvrages d'un coup, ce qui faisait plusieurs secondes de page
blanche sur une connexion lente pour des titres que personne ne fait défiler
jusqu'au bout. Les pages reçues s'empilent : « charger la suite » ajoute sans
ramener le lecteur en haut. Changer un filtre repart de la première page.

**Une notion n'a d'intérêt que si elle mène au texte.** Le glossaire montre
d'abord les notions ancrées dans le corpus, avec leur nombre de passages, et
relègue en fin de liste celles qui viennent des fiches de lecture sans qu'aucun
passage ne les emploie : elles ne s'ouvrent pas, et la liste le dit au lieu de
laisser buter dessus. Sur la fiche d'une notion, le passage qui la définit porte
une pastille et arrive en tête.

**Un axe ordonne, il ne regroupe pas.** Sa fiche présente les ouvrages du plus
accessible au plus exigeant, l'ordre que suit le chronogramme, et non par ordre
alphabétique. C'est la différence entre un axe et un rayon de bibliothèque, et
elle ne se voit que si l'écran la montre.

**Rien de ce qui est vendu n'est écrit dans l'application.** Le nom des
formules, leur descriptif et leurs plafonds viennent de `/compte/formules`, que
l'API lit dans les mêmes tables que celles appliquant les limites. L'écran
d'abonnement affiche la comparaison chiffrée, et il ne montre que les compteurs
qui changent : une ligne identique des deux côtés fait douter qu'il y ait une
différence. Les textes en dur ne servent plus que de secours hors connexion.

**Un ouvrage s'ouvre aussi par ses quiz.** Un livre du corpus porte souvent
plus de deux cents questions, et on ne pouvait y accéder qu'une séance à la
fois. Le compteur « questions » de la fiche est devenu un accès, souligné pour
qu'on le distingue des deux compteurs voisins qui ne s'ouvrent pas. Le meilleur
score de chaque chapitre s'affiche en face de son titre, en trois couleurs :
acquis, à consolider, à reprendre. Les chapitres d'appareil, enregistrés avec
zéro question, sont retirés de la liste : les montrer ferait un écran où une
ligne sur trois ne se clique pas.

**Les conversations passées se rouvrent.** La liste existait sans qu'on puisse
rien en faire, ce qui est la seule chose qu'on cherche dans un historique. Le
panneau reçoit une clé qui change à chaque réouverture : sans elle, les messages
de la conversation précédente resteraient à l'écran.

**« Fermer toutes mes sessions » ferme aussi celle-ci.** Le serveur ne fait pas
d'exception pour l'appareil qui demande : il coupe tous les jetons de
rafraîchissement. Annoncer « celui-ci reste ouvert » aurait été faux, et le
mensonge se serait découvert une demi-heure plus tard par une déconnexion
inexpliquée. L'application sort donc franchement, tout de suite.

**La recherche cherche dans le texte, pas dans les titres.** Le champ de la
bibliothèque filtre les titres et les auteurs ; l'écran de recherche interroge
le contenu des 78 ouvrages, par les mots et par le sens. La frappe est
temporisée de 350 ms : sans cela, chaque lettre déclenchait une requête. L'écran
affiche par quelle voie la réponse est venue, parce qu'un moteur qui explique
comment il a trouvé se fait corriger plus vite.

**Le mot de passe se retrouve par un code, pas par un lien.** Six chiffres
envoyés par courriel, valables trente minutes, un seul usage, cinq essais. On lit
souvent ses courriels sur un autre appareil que celui où l'application tourne, et
un lien profond suppose un site déployé, ce que nous n'avons pas. L'écran ne dit
jamais si l'adresse existe : le serveur répond la même chose dans tous les cas, et
l'interface ne doit pas trahir ce qu'il tait.

**Surligner se fait depuis le menu de sélection du texte.** Les entrées natives
(copier, tout sélectionner) sont conservées : les remplacer priverait le lecteur
de gestes qu'il connaît. Les passages surlignés sont retrouvés par recherche
littérale dans le texte ; une citation qui ne s'y retrouve plus est ignorée,
parce qu'un surlignage qui ne s'affiche pas vaut mieux qu'un texte qui refuse de
s'afficher.

**Les notes se corrigent et s'effacent.** Elles ne pouvaient qu'être écrites. Une
note fausse qu'on ne peut pas corriger vaut moins que pas de note du tout : on
finit par ne plus s'y fier. Le panneau des annotations, dans le lecteur, réunit
les surlignages et les notes de l'ouvrage.

**L'abonnement passe par Tara, et l'application ne voit jamais le code.**
`ecrans/abonnement.dart` lit la grille depuis `/paiements/tarifs` : les montants
ne sont jamais recopiés dans le téléphone, sinon ils finissent par diverger de ce
qui est réellement débité. L'écran envoie le numéro et l'opérateur, Tara pousse la
demande sur le téléphone du membre, qui valide avec son code sur son propre
appareil. C'est écrit à l'écran, parce que la fraude au mobile money commence
presque toujours par quelqu'un qui réclame ce code.

Après l'envoi, l'écran interroge `/paiements/{id}` toutes les trois secondes
pendant trois minutes, puis rend la main en disant que le paiement n'est pas
perdu : la réconciliation du serveur le rattrape dans les vingt-quatre heures.
Attendre sans repère de temps pousse à payer une seconde fois, donc le compteur
est affiché.

**Un mur payant mène quelque part.** Une erreur `premium` ou de quota n'affiche
plus un bouton « Réessayer », qui donnerait le même refus : elle ouvre l'écran
d'abonnement. Même chose pour le bouton de replanification du chronogramme, qui
était grisé et ne disait pas comment le dégriser.

**La déconnexion révoque le jeton côté serveur.** Effacer les jetons du téléphone
ne fermait rien : le jeton de rafraîchissement restait valable soixante jours en
base, et sur un appareil perdu ou revendu il rouvrait le compte.

**Le lecteur suit la séance, pas le chapitre.** Quand une séance regroupe
plusieurs chapitres courts, la suite de la plage de pages est chargée sous le
chapitre courant.

## Construire pour Android

```bash
flutter build apk --release                  # un fichier, toutes les puces, 55 Mo
flutter build apk --release --split-per-abi  # un fichier par puce, bien plus léger
```

Préférez le découpage par ABI pour la distribution : nos lecteurs paient leur
mégaoctet, et un appareil n'a besoin que de sa propre architecture.

Le démon Gradle réclamait huit gigaoctets de tas dans `android/gradle.properties`,
gabarit d'une machine de compilation. Sur un poste ordinaire il se faisait tuer en
cours de route, avec pour seul message « Gradle build daemon disappeared
unexpectedly ». Ramené à trois.

## Web

`flutter build web --dart-define=API_URL=...` produit une version web utilisable
pour la recette. Le site public reste un projet Next.js distinct
(`apps/web-vitrine`), pour le référencement et le poids de la première page.
