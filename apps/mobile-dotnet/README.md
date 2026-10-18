# Ascenda

Lecture guidée : un plan de lecture daté, un quiz par chapitre, et des réponses qui citent
le livre et la page. Portage .NET MAUI du client mobile, sur la même interface de
programmation.

## Organisation

```
src/Ascenda.Noyau/      modèles, client d'API, services, vues-modèles (net8.0, sans dépendance d'interface)
src/Ascenda.Mobile/     application .NET MAUI (net8.0-android)
tests/Ascenda.Noyau.Tests/  vérifications du noyau (xUnit)
.github/workflows/    construction de l'APK et dépôt de l'artefact
```

Le noyau ne référence aucune bibliothèque d'interface : il se compile et se vérifie sur
n'importe quelle machine, sans la charge de travail MAUI. L'application ne porte que les
pages, la navigation et l'accès au stockage sécurisé.

## Vérifier

```bash
dotnet test tests/Ascenda.Noyau.Tests/Ascenda.Noyau.Tests.csproj
```

## Construire l'APK

En local, une fois la charge de travail posée :

```bash
dotnet workload install maui-android
dotnet publish src/Ascenda.Mobile/Ascenda.Mobile.csproj -f net8.0-android -c Release \
  -p:AndroidPackageFormat=apk -o paquet
```

Dans la chaîne d'intégration, chaque poussée sur `main` vérifie le noyau puis construit
l'APK et la dépose en artefact sous le nom `ascenda-apk`, avec son empreinte SHA-256. Une
étiquette `v*` publie en plus une version avec le fichier attaché.

## Adresse du service

`src/Ascenda.Mobile/MauiProgram.cs` porte l'adresse de l'interface de programmation. Pour
une recette locale, la remplacer par `http://10.0.2.2:5000` et autoriser le trafic en clair
vers cette adresse seulement.

## Recette sur appareil branché

L'adresse du service est une propriété de construction. Pour viser la machine de
développement plutôt que la production :

```bash
adb reverse tcp:8250 tcp:8250
dotnet publish src/Ascenda.Mobile/Ascenda.Mobile.csproj -f net10.0-android -c Release \
  -p:AndroidPackageFormat=apk -p:AdresseApi=http://127.0.0.1:8250 \
  -p:ApplicationId=com.ascenda.dotnet.recette -o paquet-recette
```

La chaîne d'intégration produit les deux variantes : celle de production et celle de
recette, qui porte un identifiant distinct et s'installe donc à côté.

## Comparer au pixel avec l'application Flutter

```bash
./tests/test_portage.py          # les jetons ne dérivent pas
./tests/comparer_portage.py      # l'écart réel, écran par écran, sur l'appareil
```
