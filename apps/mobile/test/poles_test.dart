// Ce que ce fichier vérifie : que l'application range les sous-axes sous leur
// pôle (« Agriculture et élevage »), et que la bibliothèque filtre par pôle
// puis par sous-axe sans déborder sur un petit téléphone.
//
// Les périmètres de chapitres sont décidés par le serveur et vérifiés par
// tests/test_poles.py. Ici, on vérifie ce que le lecteur voit.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ascenda/api/client.dart';
import 'package:ascenda/api/modeles.dart';
import 'package:ascenda/ecrans/bibliotheque.dart';
import 'package:ascenda/etat/session.dart';
import 'package:ascenda/theme/theme.dart';

import 'outils.dart';

Map<String, dynamic> _axe(String slug, String label, {String? pole}) => {
      'slug': slug,
      'label': label,
      'nb_ouvrages': 1,
      'nb_pages': 58,
      'duree_estimee_min': 214,
      'premium': false,
      'ouvrages_exploitables': 1,
      'parcours_possible': true,
      'pole': pole == null ? null : {'slug': pole, 'label': 'Agriculture et élevage'},
    };

final _axes = [
  _axe('01-ia-fondamentaux-vulgarisation', "Fondamentaux de l'IA"),
  _axe('11-sciences-environnement', 'Sciences et environnement'),
  _axe('12-1-developpement-rural', 'Développement rural et filières', pole: '12-agriculture-elevage'),
  _axe('12-3-protection-cultures', 'Protection des cultures', pole: '12-agriculture-elevage'),
  _axe('12-5-elevage-sante-animale', 'Élevage et santé animale', pole: '12-agriculture-elevage'),
];

/// Un client qui répond sans réseau et retient les filtres demandés.
class _ClientFaux extends ClientApi {
  final filtres = <String?>[];

  @override
  Future<dynamic> get(String chemin, {Map<String, dynamic>? params, bool auth = true}) async {
    if (chemin == '/axes') return _axes;
    if (chemin == '/bibliotheque') {
      filtres.add(params?['axe'] as String?);
      return {
        'total': 1,
        'page': 1,
        'ouvrages': [
          {'id': 'd1', 'titre': "Mémento de l'agronome", 'auteurs': ['CIRAD', 'GRET'], 'pages': 1698},
        ],
      };
    }
    return null;
  }

  @override
  Future<bool> get aUneSession async => false;
}

void main() {
  test('les sous-axes se rangent sous leur pôle, dans l\'ordre de l\'API', () {
    final groupes = regrouperParPole(_axes.map(Axe.depuisJson).toList());
    expect(groupes.length, 3);
    expect(groupes[0].estPole, isFalse);
    expect(groupes[2].estPole, isTrue);
    expect(groupes[2].poleLabel, 'Agriculture et élevage');
    expect(groupes[2].axes.map((a) => a.slug), [
      '12-1-developpement-rural',
      '12-3-protection-cultures',
      '12-5-elevage-sante-animale',
    ]);
  });

  test('un axe sans pôle reste seul', () {
    final a = Axe.depuisJson(_axes.first);
    expect(a.poleSlug, isNull);
    expect(regrouperParPole([a]).single.axes.single.slug, a.slug);
  });

  testWidgets('la bibliothèque : une pastille pour le pôle, ses sous-axes dessous', (t) async {
    // Assez large pour que toutes les pastilles soient construites : la liste
    // horizontale ne bâtit que ce qui est à l'écran.
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final client = _ClientFaux();
    await t.pumpWidget(ProviderScope(
      overrides: [clientApiProvider.overrideWithValue(client)],
      child: MaterialApp(theme: ThemeAscenda.clair, home: const EcranBibliotheque()),
    ));
    await t.pumpAndSettle();

    // Le pôle tient en une pastille ; ses sous-axes ne sont pas encore montrés.
    await t.ensureVisible(texte('Agriculture et élevage'));
    await t.pumpAndSettle();
    expect(texte('Protection des cultures'), findsNothing);

    await t.tap(texte('Agriculture et élevage'));
    await t.pumpAndSettle();
    expect(client.filtres.last, '12-agriculture-elevage', reason: 'le pôle filtre sur tous ses sous-axes');
    expect(find.byKey(const Key('sous-axes')), findsOneWidget);
    expect(texte('Développement rural et filières'), findsOneWidget);
    // Un pôle n'a pas de fiche d'axe : pas de « Par où commencer ».
    expect(texte('Par où commencer dans cet axe'), findsNothing);

    await t.ensureVisible(texte('Protection des cultures'));
    await t.pumpAndSettle();
    await t.tap(texte('Protection des cultures'));
    await t.pumpAndSettle();
    expect(client.filtres.last, '12-3-protection-cultures');
    expect(texte('Par où commencer dans cet axe'), findsOneWidget);
    expect(find.byKey(const Key('sous-axes')), findsOneWidget, reason: 'la rangée reste ouverte');

    // Retirer le sous-axe revient au pôle, pas à « Tous ».
    await t.tap(texte('Protection des cultures'));
    await t.pumpAndSettle();
    expect(client.filtres.last, '12-agriculture-elevage');
    expect(t.takeException(), isNull);
  });
}
