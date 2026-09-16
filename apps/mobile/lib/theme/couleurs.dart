import 'package:flutter/material.dart';

import 'palette.dart';

export 'palette.dart';

/// Les couleurs d'ASCENDA, lues dans le thème choisi.
///
/// Les noms d'origine (l'or, le bleu nuit, le gris chaud) restent, mais chacun
/// désigne désormais un rôle de la [Palette] en vigueur : en thème Sépia,
/// « nuit » est le brun profond des cartes de mise en avant, et « grisChaud »
/// le texte secondaire de ce thème. Un nouvel écran lit plutôt
/// `context.palette`, qui dit le rôle au lieu de la teinte.
abstract final class Couleurs {
  static Palette get _p => Palette.courante;

  /// Le fond profond des cartes de mise en avant, et sa fin de dégradé.
  static Color get nuit => _p.heros;
  static Color get nuitProfond => _p.herosFin;
  static Color get ardoise => Color.lerp(_p.heros, _p.herosFin, 0.5)!;
  static Color get surfaceSombre => _p.herosFin;

  static Color get or => _p.accent;

  /// L'or lisible sur une carte de mise en avant.
  static Color get orClair => _p.accentSurHeros;

  /// L'or lisible comme texte sur le fond et les cartes.
  static Color get orTexte => _p.accentTexte;

  static Color get ivoire => _p.surface;
  static Color get ivoireCreuse => _p.surfaceCreuse;
  static Color get encre => _p.encre;
  static Color get grisChaud => _p.attenue;

  static Color get sauge => _p.succes;
  static Color get terracotta => _p.alerte;

  /// La teinte d'un pôle, celle-là même qui colore sa carte sur la vitrine et
  /// le dos de ses volumes sur l'étagère. La clé est le préfixe numérique du
  /// raccourci, qui ne change jamais une fois posé.
  static const poles = <String, Color>{
    '01': Color(0xFFC08A2E), '02': Color(0xFF4A6FA5), '03': Color(0xFF5F8A6A),
    '04': Color(0xFF8A7F9E), '05': Color(0xFFC4704F), '06': Color(0xFF4F8687),
    '07': Color(0xFFA8752F), '08': Color(0xFF9E6B8A), '09': Color(0xFF6F8F57),
    '10': Color(0xFF4F7BA0), '11': Color(0xFF7A9450), '12': Color(0xFF3F7D4E),
  };

  static Color? pole(String? slug) =>
      slug != null && slug.length >= 2 ? poles[slug.substring(0, 2)] : null;

  static Color get traitClair => _p.trait;
  static Color get traitSombre => _p.trait;

  static Color get papier => _p.fond;
  static Color get encreDouce => _p.texte;

  static List<BoxShadow> get ombreDouce => _p.ombreCarte;

  /// Les couleurs de la marque elle-même, qui ne suivent aucun thème : l'écran
  /// de démarrage et le logo.
  static const marqueNuit = Color(0xFF050D22);
  static const marqueOr = Color(0xFFD4A23F);
}
