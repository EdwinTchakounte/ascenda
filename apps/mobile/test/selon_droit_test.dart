
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ascenda/api/client.dart';
import 'package:ascenda/etat/session.dart';
import 'package:ascenda/theme/theme.dart';
import 'package:ascenda/widgets/selon_droit.dart';

import 'outils.dart';

class _ClientProfil extends ClientApi {
  _ClientProfil(this.profil);

  final Map<String, dynamic>? profil;

  @override
  Future<bool> get aUneSession async => profil != null;

  @override
  Future<dynamic> get(String chemin, {Map<String, dynamic>? params, bool auth = true}) async =>
      profil ?? (throw StateError('aucun profil'));

  @override
  Future<void> garderProfil(Map<String, dynamic> j) async {}

  @override
  Future<Map<String, dynamic>?> profilGarde() async => profil;
}

Map<String, dynamic> _profil({String plan = 'free', List<String> fonctions = const []}) => {
      'id': 'u1',
      'email': 'lecteur@example.com',
      'nom': 'Lecteur',
      'plan': plan,
      'acces': {
        'complet': plan != 'free',
        'fonctions': fonctions,
        'source': plan != 'free' ? 'abonnement' : 'aucun',
        'codes': <Map<String, dynamic>>[],
      },
    };

Widget _sous(Widget enfant, Map<String, dynamic>? profil) => ProviderScope(
      overrides: [clientApiProvider.overrideWithValue(_ClientProfil(profil))],
      child: MaterialApp(
        theme: ThemeAscenda.clair,
        home: Scaffold(body: SingleChildScrollView(child: enfant)),
      ),
    );

Future<void> monter(WidgetTester t, Widget enfant, Map<String, dynamic>? profil) async {
  await t.pumpWidget(_sous(enfant, profil));
  await t.pumpAndSettle();
}

void main() {
  const contenu = Text('Le texte réservé');

  testWidgets('le droit présent laisse passer le contenu', (t) async {
    await monter(t, const SelonDroit(fonction: 'synthesis_generated', enfant: contenu),
        _profil(fonctions: ['synthesis_generated']));
    expect(texte('Le texte réservé'), findsOneWidget);
    expect(find.byType(ContenuReserve), findsNothing);
  });

  testWidgets('le droit absent met un substitut à la place', (t) async {
    await monter(t, const SelonDroit(fonction: 'synthesis_generated', enfant: contenu), _profil());
    expect(texte('Le texte réservé'), findsNothing);
    expect(find.byType(ContenuReserve), findsOneWidget);
    expect(texte('Réservé à Ascension'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
  });

  testWidgets('un abonné voit tout sans avoir la fonction nommée', (t) async {
    await monter(t, const SelonDroit(fonction: 'export_pdf', enfant: contenu),
        _profil(plan: 'premium'));
    expect(texte('Le texte réservé'), findsOneWidget);
  });

  testWidgets('un visiteur déconnecté ne voit pas le contenu réservé', (t) async {
    await monter(t, const SelonDroit(fonction: 'export_pdf', enfant: contenu), null);
    expect(find.byType(ContenuReserve), findsOneWidget);
  });

  testWidgets('le substitut dit pourquoi et où aller', (t) async {
    var appuis = 0;
    await monter(
        t,
        SelonDroit(
          fonction: 'export_pdf',
          message: "Les exports PDF font partie d'Ascension.",
          onAbonnement: () => appuis++,
          enfant: contenu,
        ),
        _profil());
    expect(texte("Les exports PDF font partie d'Ascension."), findsOneWidget);
    await t.tap(find.text('Voir Ascension'));
    expect(appuis, 1);
  });

  testWidgets("le substitut occupe la place du contenu plutôt que de la laisser vide", (t) async {
    await monter(t,
        const SelonDroit(fonction: 'export_pdf', lignes: 5, enfant: SizedBox(height: 180)), _profil());
    final haut = t.getSize(find.byType(ContenuReserve)).height;
    expect(haut, greaterThan(120));
    expect(haut, lessThan(320));
  });

  testWidgets('un substitut fourni remplace le bloc par défaut', (t) async {
    await monter(
        t,
        const SelonDroit(
          fonction: 'export_pdf',
          substitut: Text('À vous de voir'),
          enfant: contenu,
        ),
        _profil());
    expect(texte('À vous de voir'), findsOneWidget);
    expect(find.byType(ContenuReserve), findsNothing);
  });
}
