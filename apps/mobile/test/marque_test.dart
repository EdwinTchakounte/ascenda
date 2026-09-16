// Ce que ce fichier vérifie : que la marque est bien centrée là où elle est
// seule, et que chaque forme du thème est déclarée et arrondie avec douceur.
//
// Deux contrôles qu'aucune relecture ne remplace. Un `Center` oublié se voit
// à l'écran, mais seulement si on regarde cet écran là ; ici il se voit à
// chaque exécution. Et les formes arrondies de Material sont posées par le
// framework, pas par notre code : seule une mesure les attrape.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ascenda/ecrans/auth.dart';
import 'package:ascenda/ecrans/demarrage.dart';
import 'package:ascenda/theme/theme.dart';

Widget _sous(Widget ecran) => MaterialApp(theme: ThemeAscenda.clair, home: ecran);

/// L'écart entre le centre du widget et le centre de l'écran.
double _decentrage(WidgetTester t, Finder cible) {
  final r = t.getRect(cible);
  final ecran = t.getRect(find.byType(MaterialApp));
  return ((r.left + r.right) / 2 - (ecran.left + ecran.right) / 2).abs();
}

void main() {
  testWidgets("le logo de l'accueil est centré", (t) async {
    await t.pumpWidget(_sous(const EcranBienvenue()));
    await t.pump();
    final logo = find.byType(Image);
    expect(logo, findsWidgets);
    // Deux pixels de tolérance : un arrondi de mise en page, pas un alignement
    // à gauche, qui se compterait en dizaines.
    expect(_decentrage(t, logo.first), lessThan(2));
  });

  testWidgets("la connexion porte sa marque, centrée", (t) async {
    await t.pumpWidget(ProviderScope(child: _sous(const EcranConnexion())));
    await t.pump();
    final marque = find.byType(MarqueAscenda);
    expect(marque, findsOneWidget, reason: "l'écran ne dit plus à quoi on donne son mot de passe");
    expect(_decentrage(t, marque), lessThan(2));
  });

  testWidgets("le logo du démarrage est centré", (t) async {
    await t.pumpWidget(_sous(const EcranDemarrage()));
    await t.pump();
    expect(_decentrage(t, find.byType(Image).first), lessThan(2));
  });

  testWidgets("chaque forme du thème est déclarée et doucement arrondie", (t) async {
    final theme = ThemeAscenda.clair;
    final formes = <String, OutlinedBorder?>{
      'bouton plein': theme.filledButtonTheme.style?.shape?.resolve({}),
      'bouton contour': theme.outlinedButtonTheme.style?.shape?.resolve({}),
      'bouton texte': theme.textButtonTheme.style?.shape?.resolve({}),
      'barre de navigation': theme.navigationBarTheme.indicatorShape as OutlinedBorder?,
      'pastille': theme.chipTheme.shape,
      'dialogue': theme.dialogTheme.shape as OutlinedBorder?,
      'feuille du bas': theme.bottomSheetTheme.shape as OutlinedBorder?,
      'carte': theme.cardTheme.shape as OutlinedBorder?,
      'bandeau': theme.snackBarTheme.shape as OutlinedBorder?,
    };
    formes.forEach((nom, forme) {
      expect(forme, isNotNull, reason: '$nom : aucune forme déclarée, Material arrondira');
      expect(forme, isA<RoundedRectangleBorder>(), reason: '$nom');
      final r = (forme! as RoundedRectangleBorder).borderRadius.resolve(TextDirection.ltr);
      final rayon = [r.topLeft.x, r.topRight.x, r.bottomLeft.x, r.bottomRight.x].reduce((a, b) => a > b ? a : b);
      expect(rayon, greaterThanOrEqualTo(10), reason: '$nom : angle droit, hors du langage de l\'application');
    });
  });
}
