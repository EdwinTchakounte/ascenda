
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ascenda/etat/coffre.dart';
import 'package:ascenda/etat/hors_ligne.dart';

const _phrase = "La réduction de l'utilisation des pesticides est liée à la capacité d'analyser un problème au champ.";

Map<String, dynamic> _pack({String? valable}) => {
      'version': 1,
      'ouvrage': {'id': 'doc-1', 'titre': "Mémento de l'agronome", 'auteurs': ['CIRAD']},
      'compteurs': {'chapitres': 3, 'citations': 0, 'questions': 12},
      'sommaire': [
        {'id': 'c1', 'ordre': 1, 'titre': 'Le diagnostic phytosanitaire', 'page_debut': 692, 'page_fin': 692},
        {'id': 'c2', 'ordre': 2, 'titre': 'La protection intégrée', 'page_debut': 693, 'page_fin': 706},
        {'id': 'c3', 'ordre': 3, 'titre': "L'utilisation des pesticides", 'page_debut': 707, 'page_fin': 720},
      ],
      'quiz': [],
      'lecture': [
        {
          'chapitre_id': 'c2',
          'passages': [
            {'page_debut': 693, 'page_fin': 694, 'texte': _phrase},
            {'page_debut': 695, 'page_fin': 696, 'texte': 'Les auxiliaires limitent les ravageurs.'},
          ],
        },
      ],
      'lecture_valable_jusqu_au': valable ?? DateTime.now().add(const Duration(days: 30)).toIso8601String(),
    };

void main() {
  late Directory racine;
  final cle = List<int>.generate(32, (i) => i * 7 % 256);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    racine = await Directory.systemTemp.createTemp('ascenda-coffre');
  });
  tearDown(() => racine.delete(recursive: true));

  DepotHorsLigne depot([List<int>? autreCle]) =>
      DepotHorsLigne(coffre: Coffre(cle: () async => autreCle ?? cle), racine: () async => racine);

  group('le coffre', () {
    test('chiffre et déchiffre', () async {
      final coffre = Coffre(cle: () async => cle);
      final chiffre = await coffre.chiffrerTexte(_phrase);
      expect(utf8.decode(chiffre, allowMalformed: true), isNot(contains('pesticides')));
      expect(await coffre.dechiffrerTexte(chiffre), _phrase);
    });

    test('deux chiffrements du même texte diffèrent', () async {
      final coffre = Coffre(cle: () async => cle);
      expect(await coffre.chiffrerTexte(_phrase), isNot(equals(await coffre.chiffrerTexte(_phrase))));
    });

    test('refuse une donnée altérée', () async {
      final coffre = Coffre(cle: () async => cle);
      final chiffre = await coffre.chiffrerTexte(_phrase);
      chiffre[20] ^= 0xff;
      expect(() => coffre.dechiffrer(chiffre), throwsA(anything));
    });

    test("refuse la clé d'une autre installation", () async {
      final chiffre = await Coffre(cle: () async => cle).chiffrerTexte(_phrase);
      final autre = Coffre(cle: () async => List<int>.filled(32, 1));
      expect(() => autre.dechiffrer(chiffre), throwsA(anything));
    });
  });

  group('le pack hors ligne', () {
    test("s'écrit chiffré : aucune phrase du livre sur le disque", () async {
      await depot().enregistrer('doc-1', _pack());
      final fichiers = racine.listSync(recursive: true).whereType<File>().toList();
      expect(fichiers.map((f) => f.path.split('/').last), contains('doc-1.bin'));
      expect(fichiers.any((f) => f.path.endsWith('.json')), isFalse);
      for (final f in fichiers) {
        expect(latin1.decode(f.readAsBytesSync(), allowInvalid: true), isNot(contains('pesticides')));
      }
    });

    test('se relit dans l\'application', () async {
      await depot().enregistrer('doc-1', _pack());
      final pack = await depot().lire('doc-1');
      expect((pack!['lecture'] as List).length, 1);
    });

    test('ne se relit pas avec une autre clé', () async {
      await depot().enregistrer('doc-1', _pack());
      expect(await depot(List<int>.filled(32, 9)).lire('doc-1'), isNull);
    });

    test('le texte expire à sa date de validité, la fiche et les quiz restent', () async {
      await depot().enregistrer('doc-1', _pack(valable: '2026-01-01T00:00:00Z'));
      final pack = await depot().lire('doc-1', maintenant: DateTime.utc(2026, 2, 1));
      expect(pack!['lecture'], isNull);
      expect(pack['lecture_expiree'], isTrue);
      expect(pack['sommaire'], isNotEmpty);
    });

    test('le PDF se garde chiffré et se relit', () async {
      final pdf = utf8.encode('%PDF-1.4 contenu du livre');
      await depot().enregistrerPdf('doc-1', pdf);
      final brut = File('${racine.path}/pdf/doc-1.bin').readAsBytesSync();
      expect(latin1.decode(brut.sublist(0, 20), allowInvalid: true), isNot(startsWith('%PDF')));
      expect(await depot().lirePdf('doc-1'), pdf);
      expect(await depot().aPdf('doc-1'), isTrue);
    });

    test("le PDF d'un ouvrage libre reste en clair, et « retirer » l'efface aussi", () async {
      final d = depot();
      final clair = await d.fichierPdfClair('doc-2');
      await clair!.writeAsBytes(utf8.encode('%PDF-1.4 un ouvrage libre'));
      expect(await d.aPdf('doc-2'), isTrue, reason: 'le clair compte comme présent');
      await d.supprimer('doc-2');
      expect(await clair.exists(), isFalse);
      expect(await d.aPdf('doc-2'), isFalse);
    });

    test('retirer efface le pack et le PDF', () async {
      await depot().enregistrer('doc-1', _pack());
      await depot().enregistrerPdf('doc-1', [1, 2, 3]);
      await depot().supprimer('doc-1');
      expect(racine.listSync(recursive: true).whereType<File>(), isEmpty);
    });
  });

  group('lire un chapitre sans réseau', () {
    test('le chapitre se reconstitue avec ses voisins', () {
      final ch = chapitreHorsLigne(_pack(), 'c2')!;
      expect(ch['chapitre']['titre'], 'La protection intégrée');
      expect((ch['passages'] as List).first['texte'], _phrase);
      expect(ch['precedent']['id'], 'c1');
      expect(ch['suivant']['id'], 'c3');
      expect(ch['droits']['lecture_integrale'], isTrue);
      expect(ch['droits']['hors_ligne'], isTrue);
    });

    test("la fiche et le sommaire s'ouvrent depuis le pack", () {
      final pack = {
        ..._pack(),
        'quiz': [
          {'chapitre_id': 'c2', 'questions': [{}, {}, {}]},
        ],
      };
      final f = ficheHorsLigne(pack, pdf: true);
      expect(f['titre'], "Mémento de l'agronome");
      expect(f['droits']['lecture_integrale'], isTrue);
      expect(f['droits']['pdf'], isTrue);
      expect(f['contenu']['chapitres'], 3);
      final s = sommaireHorsLigne(pack);
      expect(s.map((c) => c['id']), ['c1', 'c2', 'c3']);
      expect(s[1]['nb_questions'], 3);
      expect(s.every((c) => (c['tokens'] as int) >= 300), isTrue);
    });

    test('texte expiré : la fiche le dit et ne propose plus le PDF', () {
      final f = ficheHorsLigne({..._pack(), 'lecture': null, 'lecture_expiree': true}, pdf: true);
      expect(f['droits']['lecture_integrale'], isFalse);
      expect(f['droits']['pdf'], isFalse);
      expect('${f['droits']['message']}', contains('expiré'));
    });

    test("un chapitre absent du pack n'invente rien", () {
      expect(chapitreHorsLigne(_pack(), 'c1'), isNull);
      expect(chapitreHorsLigne({..._pack(), 'lecture': null}, 'c2'), isNull);
    });
  });
}
