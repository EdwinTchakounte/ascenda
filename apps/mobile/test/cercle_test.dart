
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ascenda/api/cercle.dart';
import 'package:ascenda/api/client.dart';
import 'package:ascenda/ecrans/cercle.dart';
import 'package:ascenda/etat/session.dart';
import 'package:ascenda/theme/theme.dart';

import 'outils.dart';

final _maintenant = DateTime.now().toUtc();
String _il(Duration d) => _maintenant.subtract(d).toIso8601String();

class _ServeurFactice extends ClientApi {
  final appels = <String>[];
  final corps = <String, Object?>{};
  final messages = <Map<String, dynamic>>[
    {'id': 'm1', 'texte': 'Tu en es où du chapitre 3 ?', 'de_moi': true, 'lu': true, 'le': _il(const Duration(hours: 2))},
    {'id': 'm2', 'texte': 'Presque fini, il est dense.', 'de_moi': false, 'lu': false, 'le': _il(const Duration(hours: 1))},
  ];

  @override
  Future<dynamic> get(String chemin, {Map<String, dynamic>? params, bool auth = true}) async {
    appels.add('GET $chemin');
    return switch (chemin) {
      '/cercle/moi' => {
          'code': 'AWA-7KQ2',
          'partage_activite': true,
          'compteurs': {'demandes': 1, 'messages': 1, 'encouragements': 1},
          'message_partage': 'Rejoins mon cercle avec le code AWA-7KQ2.',
        },
      '/cercle/demandes' => {
          'recues': [
            {'id': 'd1', 'le': _il(const Duration(hours: 3)), 'lecteur': {'id': 'u-chloe', 'nom': 'Chloé'}}
          ],
          'envoyees': [
            {'id': 'd2', 'le': _il(const Duration(days: 1)), 'lecteur': {'id': 'u-dan', 'nom': 'Dan'}}
          ],
        },
      '/cercle/encouragements' => [
          {
            'id': 'e1', 'genre': 'courage', 'message': 'Tu tiens le rythme, continue.', 'nouveau': true,
            'le': _il(const Duration(minutes: 20)), 'ouvrage': null,
            'auteur': {'id': 'u-ben', 'nom': 'Ben'},
          }
        ],
      '/cercle/fil' => [
          {
            'id': 'f1', 'genre': 'seance', 'texte': 'a terminé une séance de 30 min',
            'ouvrage': "Comment l'IA transformera notre avenir", 'le': _il(const Duration(hours: 5)),
            'lecteur': {'id': 'u-ben', 'nom': 'Ben'}, 'encourage': false,
          },
          {
            'id': 'f2', 'genre': 'quiz', 'texte': 'a réussi 8 questions sur 10 à un quiz',
            'ouvrage': null, 'le': _il(const Duration(days: 2)),
            'lecteur': {'id': 'u-ben', 'nom': 'Ben'}, 'encourage': true,
          },
        ],
      '/cercle/amis' => [
          {
            'id': 'u-ben', 'nom': 'Ben', 'non_lus': 1, 'amis_depuis': _il(const Duration(days: 9)),
            'lecture': {
              'partage': true, 'seances_semaine': 3, 'minutes_semaine': 75, 'jours_actifs_14': 6,
              'derniere_activite': _il(const Duration(hours: 5)), 'lit': "Comment l'IA transformera notre avenir",
            },
          },
          {'id': 'u-eve', 'nom': 'Ève', 'non_lus': 0, 'lecture': {'partage': false}},
        ],
      '/cercle/echanges/u-ben' => {'ami': {'id': 'u-ben', 'nom': 'Ben'}, 'messages': messages},
      _ => throw StateError('route inattendue $chemin'),
    };
  }

  @override
  Future<dynamic> post(String chemin, {Object? corps, bool auth = true}) async {
    appels.add('POST $chemin');
    this.corps[chemin] = corps;
    if (chemin == '/cercle/echanges/u-ben') {
      messages.add({'id': 'm3', 'texte': (corps as Map)['texte'], 'de_moi': true, 'lu': false,
        'le': DateTime.now().toUtc().toIso8601String()});
      return messages.last;
    }
    if (chemin == '/cercle/echanges/u-ben/lus') return {'marques': 1};
    if (chemin == '/cercle/amis') return {'statut': 'en_attente', 'ami': {'id': 'u-fanta', 'nom': 'Fanta'}};
    return {'statut': 'acceptee', 'ami': {'id': 'u-chloe', 'nom': 'Chloé'}};
  }

  @override
  Future<bool> get aUneSession async => true;
}

Widget _monter(Widget ecran, _ServeurFactice serveur) => ProviderScope(
      overrides: [clientApiProvider.overrideWithValue(serveur)],
      child: MaterialApp(theme: ThemeAscenda.clair, home: ecran),
    );

void _petitEcran(WidgetTester t) {
  t.view.physicalSize = const Size(360, 760) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets("l'onglet montre le code, les demandes, les encouragements, le fil et les amis", (t) async {
    _petitEcran(t);
    final serveur = _ServeurFactice();
    await t.pumpWidget(_monter(const EcranCercle(), serveur));
    await t.pumpAndSettle();

    expect(texte('AWA-7KQ2'), findsOneWidget);
    expect(texte('Chloé'), findsOneWidget);
    expect(texte('veut rejoindre votre cercle'), findsOneWidget);
    expect(texte('« Tu tiens le rythme, continue. »'), findsOneWidget);
    expect(serveur.appels.where((a) => a == 'POST /cercle/encouragements/vus'), hasLength(1));

    final defiler = find.byType(Scrollable).first;
    await t.scrollUntilVisible(texteContenant('a terminé une séance de 30 min'), 200, scrollable: defiler);
    expect(find.widgetWithText(OutlinedButton, 'Encourager'), findsOneWidget,
        reason: "la séance déjà encouragée n'offre plus le bouton");

    await t.scrollUntilVisible(texte('3 séances · 75 min cette semaine'), 200, scrollable: defiler);
    expect(texte('ne partage pas son activité'), findsOneWidget);
    await t.scrollUntilVisible(texteContenant('En attente de réponse : Dan'), 200, scrollable: defiler);
    await t.scrollUntilVisible(texte('Montrer ma lecture à mes amis'), 200, scrollable: defiler);
    expect(t.takeException(), isNull, reason: 'aucun débordement sur 360 pixels');
  });

  testWidgets('accepter une demande appelle la bonne route', (t) async {
    _petitEcran(t);
    final serveur = _ServeurFactice();
    await t.pumpWidget(_monter(const EcranCercle(), serveur));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Accepter'));
    await t.pumpAndSettle();
    expect(serveur.appels, contains('POST /cercle/demandes/d1/accepter'));
    expect(texteContenant('Chloé fait maintenant partie de votre cercle'), findsOneWidget);
  });

  testWidgets('ajouter un ami par son code', (t) async {
    _petitEcran(t);
    final serveur = _ServeurFactice();
    await t.pumpWidget(_monter(const EcranCercle(), serveur));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Ajouter'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'fanta-8m3p');
    await t.tap(find.widgetWithText(FilledButton, 'Envoyer'));
    await t.pumpAndSettle();
    expect(serveur.corps['/cercle/amis'], {'code': 'fanta-8m3p'});
    expect(texteContenant('Demande envoyée à Fanta'), findsOneWidget);
  });

  testWidgets('encourager une séance du fil envoie le genre et l’activité', (t) async {
    _petitEcran(t);
    final serveur = _ServeurFactice();
    await t.pumpWidget(_monter(const EcranCercle(), serveur));
    await t.pumpAndSettle();
    final bouton = find.widgetWithText(OutlinedButton, 'Encourager');
    await t.scrollUntilVisible(bouton, 200, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(bouton);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -150));
    await t.pumpAndSettle();
    await t.tap(bouton);
    await t.pumpAndSettle();
    await t.tap(texte('Courage, tu tiens le bon rythme.'));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Envoyer'));
    await t.pumpAndSettle();
    expect(serveur.corps['/cercle/encouragements'], {'ami_id': 'u-ben', 'genre': 'courage', 'evenement_id': 'f1'});
    expect(texteContenant('Encouragement envoyé à Ben'), findsOneWidget);
  });

  testWidgets('la conversation se lit du plus ancien au plus récent, et on y répond', (t) async {
    _petitEcran(t);
    final serveur = _ServeurFactice();
    await t.pumpWidget(_monter(const EcranConversation(amiId: 'u-ben', nom: 'Ben'), serveur));
    await t.pumpAndSettle();

    final ancien = t.getTopLeft(texte('Tu en es où du chapitre 3 ?'));
    final recent = t.getTopLeft(texte('Presque fini, il est dense.'));
    expect(ancien.dy, lessThan(recent.dy));
    expect(ancien.dx, greaterThan(recent.dx), reason: 'mes messages à droite, les siens à gauche');
    expect(serveur.appels, contains('POST /cercle/echanges/u-ben/lus'));

    await t.enterText(find.byType(TextField), 'Bon courage pour la fin !');
    await t.tap(find.byTooltip('Envoyer'));
    await t.pumpAndSettle();
    expect(serveur.corps['/cercle/echanges/u-ben'], {'texte': 'Bon courage pour la fin !'});
    expect(texte('Bon courage pour la fin !'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  test('les dates du fil se lisent sans calcul', () {
    final m = DateTime(2026, 9, 13, 18, 0);
    expect(ilYA(m.subtract(const Duration(seconds: 20)), maintenant: m), "à l'instant");
    expect(ilYA(m.subtract(const Duration(minutes: 12)), maintenant: m), 'il y a 12 min');
    expect(ilYA(m.subtract(const Duration(hours: 3)), maintenant: m), 'il y a 3 h');
    expect(ilYA(DateTime(2026, 9, 12, 21), maintenant: m), 'hier');
    expect(ilYA(DateTime(2026, 9, 9, 10), maintenant: m), 'il y a 4 jours');
    expect(ilYA(DateTime(2026, 8, 2), maintenant: m), 'le 02/08');
  });
}
