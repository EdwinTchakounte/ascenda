
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ascenda/etat/apparence.dart';
import 'package:ascenda/theme/palette.dart';
import 'package:ascenda/theme/theme.dart';
import 'package:ascenda/widgets/selecteur_theme.dart';

double _contraste(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  for (final p in Palette.tous) {
    group('thème ${p.nom}', () {
      final paires = <String, (Color, Color, double)>{
        'titre sur fond': (p.encre, p.fond, 4.5),
        'texte sur fond': (p.texte, p.fond, 4.5),
        'texte sur carte': (p.texte, p.surface, 4.5),
        'texte secondaire sur carte': (p.attenue, p.surface, 3),
        'texte secondaire sur fond': (p.attenue, p.fond, 3),
        'or lisible sur carte': (p.accentTexte, p.surface, 3),
        'bouton principal': (p.surAccent, p.accent, 4.5),
        'texte sur carte de mise en avant': (p.surHeros, p.heros, 4.5),
        'texte secondaire sur mise en avant': (p.surHerosDoux, p.herosFin, 4.5),
        'or sur mise en avant': (p.accentSurHeros, p.heros, 3),
        'alerte sur carte': (p.alerte, p.surface, 3),
      };
      paires.forEach((nom, x) {
        test(nom, () {
          final c = _contraste(x.$1, x.$2);
          expect(c, greaterThanOrEqualTo(x.$3), reason: '$nom : ${c.toStringAsFixed(2)}');
        });
      });

      test('le thème Material porte sa palette', () {
        final theme = ThemeAscenda.depuis(p);
        expect(theme.extension<Palette>()?.id, p.id);
        expect(theme.scaffoldBackgroundColor, p.fond);
        expect(theme.brightness, p.sombre ? Brightness.dark : Brightness.light);
      });
    });
  }

  test('automatique : Ivoire le jour, Nuit quand le téléphone est sombre', () {
    const a = Apparence();
    expect(a.palette(Brightness.light).id, 'ivoire');
    expect(a.palette(Brightness.dark).id, 'nuit');
    expect(const Apparence(theme: 'sepia').palette(Brightness.dark).id, 'sepia');
    expect(const Apparence(theme: 'inconnu').palette(Brightness.light).id, 'ivoire');
  });

  testWidgets('choisir un thème le retient pour le prochain lancement', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: ThemeAscenda.clair,
        home: const Scaffold(body: Padding(padding: EdgeInsets.all(16), child: SelecteurTheme())),
      ),
    ));
    await t.tap(find.text('Forêt'));
    await t.pumpAndSettle();
    expect(await ApparenceNotifier.themeEnregistre(), 'foret');
  });
}
