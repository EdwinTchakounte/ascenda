import 'package:flutter/material.dart';

import 'palette.dart';

export 'palette.dart';

abstract final class Couleurs {
  static Palette get _p => Palette.courante;
  static Color get nuit => _p.heros;
  static Color get nuitProfond => _p.herosFin;
  static Color get ardoise => Color.lerp(_p.heros, _p.herosFin, 0.5)!;
  static Color get surfaceSombre => _p.herosFin;
  static Color get or => _p.accent;
  static Color get orClair => _p.accentSurHeros;
  static Color get orTexte => _p.accentTexte;
  static Color get ivoire => _p.surface;
  static Color get ivoireCreuse => _p.surfaceCreuse;
  static Color get encre => _p.encre;
  static Color get grisChaud => _p.attenue;
  static Color get sauge => _p.succes;
  static Color get terracotta => _p.alerte;

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
  static const marqueNuit = Color(0xFF050D22);
  static const marqueOr = Color(0xFFD4A23F);
}
