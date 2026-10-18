// Ce que ce fichier vérifie : qu'aucun mot ne reste seul sur la dernière ligne d'un

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ascenda/theme/texte.dart';

const _nbsp = '\u00A0';

void main() {
  test('le dernier mot emmène le précédent', () {
    expect(lisible("Le reste est libre."), "Le reste est${_nbsp}libre.");
  });

  test('les signes doubles restent collés au mot', () {
    expect(lisible('Rien : retiré'), 'Rien$_nbsp: retiré');
    expect(lisible('Vous êtes prêt ?'), 'Vous êtes prêt$_nbsp?');
    expect(lisible('« Bonjour »'), '«${_nbsp}Bonjour$_nbsp»');
  });

  test('un mot composé ne se coupe pas', () {
    expect(lisible('dans les vingt-quatre heures'), 'dans les vingt\u2011quatre${_nbsp}heures');
    expect(lisible('p. 13-21'), 'p. 13-21', reason: 'un intervalle de pages garde son tiret');
  });

  test('un libellé court est laissé tel quel', () {
    expect(lisible('Créer mon compte'), 'Créer mon compte');
  });

  test('chaque paragraphe est traité, la longueur ne change jamais', () {
    const t = "Une première phrase assez longue ici.\nUne seconde phrase qui finit par un mot.";
    final r = lisible(t);
    expect(r.length, t.length);
    expect(r.split('\n').every((p) => p.contains('$_nbsp')), isTrue);
  });

  test("une ligne trop courte pour être justifiée sans trous reste alignée à gauche", () {
    final long = 'x' * 120;
    expect(Texte.alignement(long, const TextStyle(fontSize: 14), null, largeur: 600), TextAlign.justify);
    expect(Texte.alignement(long, const TextStyle(fontSize: 14), null, largeur: 412), isNull,
        reason: 'sur un téléphone courant, la ligne est trop courte pour être justifiée sans trous');
    expect(Texte.alignement(long, const TextStyle(fontSize: 16), null, largeur: 412), isNull);
    expect(Texte.alignement(long, const TextStyle(fontSize: 14), null, largeur: 320), isNull);
  });

  testWidgets("un paragraphe est justifié, un titre ne l'est pas", (t) async {
    t.view.physicalSize = const Size(600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    const long = "Ce qui coûte à ASCENDA, c'est d'indexer des documents et de faire "
        "réfléchir l'agent. Le reste est libre, et le restera.";
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Texte(long),
          Texte(long, style: TextStyle(fontSize: 26)),
          Texte('Court'),
          Texte(long, maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      ),
    ));
    final textes = t.widgetList<Text>(find.byType(Text)).toList();
    expect(textes[0].textAlign, TextAlign.justify);
    expect(textes[1].textAlign, isNull);
    expect(textes[2].textAlign, isNull);
    expect(textes[3].textAlign, isNull, reason: 'un aperçu coupé ne se justifie pas');
  });
}
