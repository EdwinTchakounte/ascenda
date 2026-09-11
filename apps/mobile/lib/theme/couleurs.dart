import 'package:flutter/material.dart';

/// La palette d'ASCENDA, tirée du logo : un « A » doré sur bleu nuit.
///
/// L'or est un rehaut. Il marque le CTA, la progression et l'élément actif ;
/// il ne couvre jamais une surface entière. Le fond de lecture est ivoire et
/// non blanc pur : on lit dessus pendant des heures.
abstract final class Couleurs {
  static const nuitProfond = Color(0xFF050D22);
  static const nuit = Color(0xFF0B1435);
  static const ardoise = Color(0xFF223454);
  static const surfaceSombre = Color(0xFF101C3D);

  static const or = Color(0xFFD4A23F);
  static const orClair = Color(0xFFE8C070);

  /// L'or vire trop clair pour du texte sur ivoire : cette teinte assombrie
  /// passe le contraste AA sans renoncer à l'accent.
  static const orTexte = Color(0xFF9A7118);

  static const ivoire = Color(0xFFFAF8F4);
  static const ivoireCreuse = Color(0xFFF2EEE6);
  static const encre = Color(0xFF1A1F2E);
  static const grisChaud = Color(0xFF6B7280);

  static const sauge = Color(0xFF7C9A82);
  static const terracotta = Color(0xFFC4704F);

  /// La teinte d'un pôle, celle-là même qui colore sa carte sur la vitrine et
  /// le dos de ses volumes sur l'étagère. La clé est le préfixe numérique du
  /// raccourci, qui ne change jamais une fois posé.
  static const poles = <String, Color>{
    '01': Color(0xFFC08A2E), '02': Color(0xFF4A6FA5), '03': Color(0xFF5F8A6A),
    '04': Color(0xFF8A7F9E), '05': Color(0xFFC4704F), '06': Color(0xFF4F8687),
    '07': Color(0xFFA8752F), '08': Color(0xFF9E6B8A), '09': Color(0xFF6F8F57),
    '10': Color(0xFF4F7BA0), '11': Color(0xFF7A9450),
  };

  static Color? pole(String? slug) =>
      slug != null && slug.length >= 2 ? poles[slug.substring(0, 2)] : null;

  static const traitClair = Color(0x140B1435);
  static const traitSombre = Color(0x24E8C070);
}
