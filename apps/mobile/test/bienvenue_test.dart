
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ascenda/ecrans/auth.dart';
import 'package:ascenda/theme/couleurs.dart';
import 'package:ascenda/theme/theme.dart';

import 'outils.dart';

Future<void> _poser(WidgetTester t, Size taille, double police) async {
  t.view.physicalSize = taille * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: ThemeAscenda.clair,
    home: MediaQuery.withClampedTextScaling(
      minScaleFactor: police,
      maxScaleFactor: police,
      child: const EcranBienvenue(),
    ),
  ));
  await t.pump();
}

void main() {
  for (final (nom, taille, police) in [
    ('petit téléphone, grande police', const Size(360, 640), 1.6),
    ('téléphone courant', const Size(412, 915), 1.0),
    ('téléphone courant, grande police', const Size(393, 852), 1.3),
  ]) {
    testWidgets("l'accueil ne déborde pas : $nom", (t) async {
      await _poser(t, taille, police);
      expect(t.takeException(), isNull);
      for (final libelle in ['Créer mon compte', 'Parcourir la bibliothèque', "J'ai déjà un compte"]) {
        final bouton = texte(libelle);
        await t.scrollUntilVisible(bouton, 120, scrollable: find.byType(Scrollable).first);
        expect(bouton.hitTestable(), findsOneWidget, reason: '« $libelle » reste inaccessible');
      }
    });
  }

  testWidgets("le bouton secondaire se lit sur le fond de nuit", (t) async {
    await _poser(t, const Size(412, 915), 1.0);
    final libelle = t.widget<Text>(texte('Parcourir la bibliothèque'));
    final couleur = DefaultTextStyle.of(t.element(find.byWidget(libelle))).style.color!;
    final contraste = (couleur.computeLuminance() + 0.05) / (Couleurs.nuitProfond.computeLuminance() + 0.05);
    expect(contraste, greaterThan(7));
  });
}
