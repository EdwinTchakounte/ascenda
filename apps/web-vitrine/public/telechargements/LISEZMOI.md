# Fichiers proposés au téléchargement

Trois APK, et une raison pour chacune. La page `/commencer` les détecte au
moment de la construction et annonce leur poids : rien à configurer.

| Fichier | Pour qui | Poids |
|---|---|---|
| `ascenda.apk` | les téléphones vendus depuis 2016 (arm64) | 28 Mo |
| `ascenda-32bits.apk` | les téléphones anciens ou d'entrée de gamme (armeabi-v7a) | 24 Mo |
| `ascenda-universelle.apk` | le secours : quand l'installation est refusée | 55 Mo |

L'adresse de l'API est figée à la construction : sans `--dart-define`, l'APK
appelle `localhost` et ne joindra jamais le serveur.

L'APK arm64 reste celle qu'on propose en premier. Nos lecteurs paient leur
mégaoctet, et cinquante-cinq mégaoctets sur une connexion lente, c'est une
heure.

L'universelle existe parce qu'Android refuse une APK dont l'architecture ne
correspond pas au téléphone, et qu'il le dit par « le package semble non
valide », ce qui n'aide personne à comprendre qu'il fallait l'autre fichier.
Elle contient toutes les architectures : elle s'installe partout.

## Les numéros de version

Android refuse d'installer une version dont le numéro interne est inférieur à
celui déjà posé. Les trois fichiers suivent donc une règle fixe, à partir du
numéro de construction de `pubspec.yaml` :

- 32 bits : 1000 + numéro (1011 pour la construction 11) ;
- arm64 : 2000 + numéro (2011) ;
- universelle : 3000 + numéro (3011).

L'universelle porte le plus grand numéro : elle s'installe par dessus les deux
autres, ce qui est exactement ce qu'on veut d'un secours. En sens inverse, il
faut désinstaller avant de revenir à l'arm64.

## Reconstruire

Depuis `apps/mobile`, avec le numéro de construction de `pubspec.yaml` :

```bash
flutter build apk --release --split-per-abi \
  --dart-define=API_URL=https://api.ascenda-books.online

# L'universelle : numéro de construction décalé de 3000, et sans x86, que
# personne ne porte dans sa poche.
flutter build apk --release --build-number=3011 \
  --target-platform android-arm,android-arm64 \
  --dart-define=API_URL=https://api.ascenda-books.online
```

Puis, depuis ce dossier :

```bash
cp ../../../mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk   ascenda.apk
cp ../../../mobile/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk ascenda-32bits.apk
cp ../../../mobile/build/app/outputs/flutter-apk/app-release.apk             ascenda-universelle.apk
sha256sum ascenda.apk ascenda-32bits.apk ascenda-universelle.apk > empreintes.txt
```

`empreintes.txt` sert à trancher une question qui revient : le fichier
téléchargé est-il complet ? Un téléchargement interrompu donne lui aussi « le
package semble non valide », et comparer l'empreinte le dit en une commande.

Les binaires ne sont pas versionnés : vingt à cinquante mégaoctets n'ont rien à
faire dans un dépôt de code.
