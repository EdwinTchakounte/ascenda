
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ascenda/api/client.dart';
import 'package:ascenda/api/modeles.dart';
import 'package:ascenda/ecrans/auth.dart';
import 'package:ascenda/ecrans/codes.dart';
import 'package:ascenda/etat/fournisseurs.dart';
import 'package:ascenda/etat/session.dart';
import 'package:ascenda/theme/theme.dart';
import 'package:ascenda/widgets/avantages.dart';

import 'outils.dart';

class _ClientMuet extends ClientApi {
  final appels = <String>[];

  @override
  Future<dynamic> post(String chemin, {Object? corps, bool auth = true}) async {
    appels.add(chemin);
    return null;
  }

  @override
  Future<bool> get aUneSession async => false;
}

final _fin = DateTime.now().add(const Duration(days: 12)).toUtc().toIso8601String();

Map<String, dynamic> _reponseCodes({int nouveaux = 1}) => {
      'ambassadeur': {
        'code': 'AWA-7KQ2',
        'actif': true,
        'pourcent': 20,
        'validite_jours': 180,
        'filleuls': 3,
        'message_partage': 'Crée ton compte avec mon code AWA-7KQ2.',
      },
      'acces': {
        'complet': false,
        'fonctions': ['quiz_generated', 'export_pdf'],
        'source': 'code',
        'jusqu_au': _fin,
        'codes': [
          {
            'code': 'QUIZ-ETE',
            'libelle': "Quiz de l'été",
            'niveau': 'limite',
            'fonctions': ['quiz_generated', 'export_pdf'],
            'active_le': DateTime.now().toUtc().toIso8601String(),
            'fin': _fin,
            'jours_restants': 12,
          },
        ],
      },
      'reduction_prochaine': {'pourcent': 20, 'expire_le': _fin},
      'bons': [
        {
          'id': 'b1',
          'pourcent': 20,
          'statut': 'disponible',
          'expire_le': _fin,
          'utilise_le': null,
          'gagne_le': DateTime.now().toUtc().toIso8601String(),
          'filleul': 'Fanta',
          'nouveau': nouveaux > 0,
        },
        {
          'id': 'b0',
          'pourcent': 20,
          'statut': 'utilise',
          'expire_le': _fin,
          'utilise_le': DateTime.now().toUtc().toIso8601String(),
          'gagne_le': DateTime.now().toUtc().toIso8601String(),
          'filleul': 'Paul',
          'nouveau': false,
        },
      ],
      'nouveaux': nouveaux,
      'fonctions': [
        {'cle': 'quiz_generated', 'libelle': 'Quiz à la demande'},
        {'cle': 'export_pdf', 'libelle': 'Export PDF'},
      ],
    };

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('les accès lus depuis l\'API', () {
    test('un code limité n\'ouvre que ses fonctions', () {
      final u = Utilisateur.depuisJson({
        'id': '1',
        'email': 'a@example.com',
        'nom': 'Awa',
        'plan': 'free',
        'acces': _reponseCodes()['acces'],
      });
      expect(u.estPremium, isFalse);
      expect(u.accesComplet, isFalse);
      expect(u.aAcces('export_pdf'), isTrue);
      expect(u.aAcces('chronogramme_adaptatif'), isFalse);
      expect(u.acces!.codes.single.joursRestants, 12);
    });

    test('un code complet ouvre tout sans changer le plan', () {
      final u = Utilisateur.depuisJson({
        'id': '1',
        'plan': 'free',
        'acces': {'complet': true, 'fonctions': [], 'source': 'code', 'codes': []},
      });
      expect(u.estPremium, isFalse);
      expect(u.accesComplet, isTrue);
      expect(u.aAcces('chronogramme_adaptatif'), isTrue);
    });

    test('un abonné a tout, même sans description d\'accès', () {
      final u = Utilisateur.depuisJson({'id': '1', 'plan': 'premium'});
      expect(u.aAcces('export_pdf'), isTrue);
    });

    test('la réduction change le montant dû, pas le tarif affiché barré', () {
      final g = Tarifs.depuisJson({
        'moyens': [],
        'reduction': {'pourcent': 20, 'expire_le': _fin},
        'formules': [
          {'periode_mois': 1, 'montant': 3000, 'montant_reduit': 2400, 'devise': 'XAF', 'libelle': 'Un mois', 'par_mois': 3000},
        ],
      });
      expect(g.reductionPourcent, 20);
      expect(g.formules.single.montantDu, 2400);
      String plat(String v) => v.replaceAll(RegExp(r'\s'), ' ');
      expect(plat(g.formules.single.montantLisible), '3 000 XAF');
      expect(plat(g.formules.single.montantDuLisible), '2 400 XAF');
    });

    test('sans réduction, on paie le tarif', () {
      final f = Formule.depuisJson({'periode_mois': 1, 'montant': 3000, 'devise': 'XAF', 'par_mois': 3000});
      expect(f.montantReduit, isNull);
      expect(f.montantDu, 3000);
    });
  });

  Widget monter(Widget ecran, _ClientMuet client, {int nouveaux = 1, double largeur = 360}) {
    return ProviderScope(
      overrides: [
        clientApiProvider.overrideWithValue(client),
        codesProvider.overrideWith((ref) async => CodesEtAvantages.depuisJson(_reponseCodes(nouveaux: nouveaux))),
      ],
      child: MediaQuery(
        data: MediaQueryData(size: Size(largeur, 780)),
        child: MaterialApp(theme: ThemeAscenda.clair, home: Scaffold(body: ecran)),
      ),
    );
  }

  testWidgets("l'écran des codes montre l'accès, le code à partager et la réduction", (t) async {
    t.view.physicalSize = const Size(360, 780);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final client = _ClientMuet();

    await t.pumpWidget(monter(const EcranCodes(), client));
    await t.pumpAndSettle();

    expect(texte('AWA-7KQ2'), findsOneWidget);
    expect(texte("Quiz de l'été"), findsOneWidget);
    expect(texte('Accès limité à :'), findsOneWidget);
    expect(texte('Export PDF'), findsOneWidget);
    expect(texte('3'), findsOneWidget, reason: 'le nombre de lecteurs invités');

    await t.scrollUntilVisible(texte('Grâce à Fanta'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(texte('Nouveau'), findsOneWidget);
    expect(texte('Grâce à Paul'), findsOneWidget);
    expect(client.appels, contains('/codes/bons/vus'));
    expect(t.takeException(), isNull);
  });

  testWidgets('sans nouveauté, rien n\'est signalé', (t) async {
    final client = _ClientMuet();
    await t.pumpWidget(monter(const EcranCodes(), client, nouveaux: 0));
    await t.pumpAndSettle();
    expect(client.appels, isNot(contains('/codes/bons/vus')));
  });

  testWidgets("le bandeau d'accueil annonce la réduction gagnée", (t) async {
    final client = _ClientMuet();
    await t.pumpWidget(monter(const BandeauRecompense(), client));
    await t.pumpAndSettle();
    expect(texteContenant('Fanta a rejoint ASCENDA avec votre code'), findsOneWidget);
    expect(texteContenant('-20 %'), findsOneWidget);
  });

  testWidgets("et disparaît une fois vue", (t) async {
    final client = _ClientMuet();
    await t.pumpWidget(monter(const BandeauRecompense(), client, nouveaux: 0));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('bandeau-recompense')), findsNothing);
  });

  testWidgets("l'inscription propose le champ de code, la connexion non", (t) async {
    final client = _ClientMuet();
    await t.pumpWidget(ProviderScope(
      overrides: [clientApiProvider.overrideWithValue(client)],
      child: MaterialApp(theme: ThemeAscenda.clair, home: const EcranConnexion()),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('code-inscription')), findsOneWidget);
    await t.ensureVisible(texte("J'ai déjà un compte"));
    await t.pumpAndSettle();
    await t.tap(texte("J'ai déjà un compte"));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('code-inscription')), findsNothing);
  });

  test('la session transmet le code saisi et rend le message du serveur', () async {
    final client = _ClientInscription();
    final notifier = SessionNotifier(client);
    final message = await notifier.inscription('a@example.com', 'motdepasse', 'Awa', code: ' awa-7kq2 ');
    expect(client.corps?['code'], 'awa-7kq2');
    expect(message, 'Vous avez rejoint ASCENDA grâce à Awa.');
    expect(notifier.state.utilisateur?.accesComplet, isTrue);
  });
}

class _ClientInscription extends ClientApi {
  Map<String, dynamic>? corps;

  @override
  Future<bool> get aUneSession async => false;

  @override
  Future<void> enregistrerJetons(String acces, String refresh) async {}

  @override
  Future<void> garderProfil(Map<String, dynamic> j) async {}

  @override
  Future<dynamic> post(String chemin, {Object? corps, bool auth = true}) async {
    this.corps = corps as Map<String, dynamic>?;
    return {
      'utilisateur': {
        'id': '1',
        'email': 'a@example.com',
        'plan': 'free',
        'acces': {'complet': true, 'fonctions': [], 'source': 'code', 'codes': []},
      },
      'jetons': {'access_token': 'a', 'refresh_token': 'r'},
      'code_applique': {'type': 'parrainage', 'message': 'Vous avez rejoint ASCENDA grâce à Awa.'},
    };
  }
}
