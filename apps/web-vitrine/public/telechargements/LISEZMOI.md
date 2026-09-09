# Fichiers proposés au téléchargement

Déposez ici l'APK Android sous le nom exact `ascenda.apk`. La page
`/commencer` la détecte au moment de la construction et l'annonce avec son
poids. Rien d'autre à configurer.

```bash
cp ../../../mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
   ascenda.apk
```

Préférez la version `arm64-v8a` : elle couvre les téléphones vendus depuis
2016 et pèse 19 Mo, contre 55 Mo pour le fichier qui embarque toutes les
architectures. Nos lecteurs paient leur mégaoctet.

Le binaire n'est pas versionné. Il est reconstruit à chaque version depuis
`apps/mobile` :

```bash
flutter build apk --release --split-per-abi
```
