// Chercher un texte tel qu'on l'écrit, espaces insécables comprises.
//
// `Texte` remplace certaines espaces par des insécables pour tenir la mise en
// ligne : les finders de Flutter comparent caractère par caractère et ne
// retrouveraient plus « Accès limité à : ».

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

String _normal(String? s) => (s ?? '').replaceAll('\u00A0', ' ').replaceAll('\u2011', '-');

String? _contenu(Widget w) => switch (w) {
      Text(:final data?) => data,
      Text(:final textSpan?) => textSpan.toPlainText(),
      RichText(:final text) => text.toPlainText(),
      EditableText(:final controller) => controller.text,
      _ => null,
    };

Finder texte(String attendu) => find.byWidgetPredicate(
      (w) => w is! RichText && _contenu(w) != null && _normal(_contenu(w)) == attendu,
      description: 'texte « $attendu »',
    );

Finder texteContenant(String attendu) => find.byWidgetPredicate(
      (w) => w is! RichText && _contenu(w) != null && _normal(_contenu(w)).contains(attendu),
      description: 'texte contenant « $attendu »',
    );
