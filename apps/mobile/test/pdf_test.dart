
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ascenda/api/client.dart';
import 'package:ascenda/ecrans/fiche_ouvrage.dart';
import 'package:ascenda/etat/fournisseurs.dart';
import 'package:ascenda/etat/session.dart';
import 'package:ascenda/theme/theme.dart';

import 'outils.dart';

class _Muet extends ClientApi {
  @override
  Future<dynamic> get(String chemin, {Map<String, dynamic>? params, bool auth = true}) async =>
      throw const HorsLigne();

  @override
  Future<bool> get aUneSession async => false;
}

Map<String, dynamic> _fiche({required bool pdf}) => {
      'id': 'doc1',
      'titre': 'La Planète invisible',
      'auteurs': ['Auteur'],
      'axes': [],
      'pedagogie': {'idees_force': []},
      'droits': {
        'lecture_integrale': pdf,
        'pdf': pdf,
        'message': pdf ? null : "Cet ouvrage n'est pas redistribuable.",
      },
      'contenu': {'chapitres': 3, 'questions': 0, 'citations': 0},
      'dialogue_avec': [],
    };

Future<void> _poser(WidgetTester t, {required bool pdf}) async {
  await t.pumpWidget(ProviderScope(
    overrides: [
      clientApiProvider.overrideWithValue(_Muet()),
      ficheOuvrageProvider('doc1').overrideWith((ref) async => _fiche(pdf: pdf)),
      sommaireProvider('doc1').overrideWith((ref) async => []),
    ],
    child: MaterialApp(theme: ThemeAscenda.clair, home: const FicheOuvrage(documentId: 'doc1')),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('un ouvrage redistribuable propose son PDF', (t) async {
    await _poser(t, pdf: true);
    expect(texte('Lire le PDF'), findsOneWidget);
  });

  testWidgets("un ouvrage protégé ne le propose pas, et dit pourquoi", (t) async {
    await _poser(t, pdf: false);
    expect(texte('Lire le PDF'), findsNothing);
    expect(texteContenant("n'est pas redistribuable"), findsOneWidget);
  });
}
