import 'package:flutter/material.dart';

/// Les rôles de couleur d'ASCENDA, déclinés en quatre ambiances.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.id,
    required this.nom,
    required this.sombre,
    required this.fond,
    required this.surface,
    required this.surfaceCreuse,
    required this.encre,
    required this.texte,
    required this.attenue,
    required this.trait,
    required this.accent,
    required this.surAccent,
    required this.accentTexte,
    required this.succes,
    required this.alerte,
    required this.heros,
    required this.herosFin,
    required this.surHeros,
    required this.surHerosDoux,
    required this.accentSurHeros,
    required this.ombre,
  });

  final String id;
  final String nom;
  final bool sombre;

  /// Le fond des écrans, et les cartes posées dessus.
  final Color fond;
  final Color surface;

  /// Un aplat en retrait : champ de recherche, bloc secondaire, piste de jauge.
  final Color surfaceCreuse;

  /// Titres ; texte courant ; texte secondaire.
  final Color encre;
  final Color texte;
  final Color attenue;

  /// Filets et contours, toujours discrets.
  final Color trait;

  /// L'or de la marque : le bouton principal et l'élément actif.
  final Color accent;
  final Color surAccent;

  /// L'accent lisible comme texte ou icône sur [fond] et [surface].
  final Color accentTexte;

  final Color succes;
  final Color alerte;

  /// Les grandes cartes de mise en avant (séance du jour, abonnement) : un
  /// dégradé profond, avec son texte et son accent propres.
  final Color heros;
  final Color herosFin;
  final Color surHeros;
  final Color surHerosDoux;
  final Color accentSurHeros;

  final Color ombre;

  /// L'accent posé en voile léger derrière une icône ou une pastille.
  Color get accentVoile => accentTexte.withValues(alpha: sombre ? 0.16 : 0.10);

  LinearGradient get degradeHeros => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [heros, herosFin],
      );

  List<BoxShadow> get ombreCarte => [
        BoxShadow(color: ombre.withValues(alpha: sombre ? 0.35 : 0.07), blurRadius: 28, offset: const Offset(0, 10)),
        BoxShadow(color: ombre.withValues(alpha: sombre ? 0.20 : 0.04), blurRadius: 4, offset: const Offset(0, 1)),
      ];

  List<BoxShadow> get ombreHeros => [
        BoxShadow(color: heros.withValues(alpha: sombre ? 0.45 : 0.28), blurRadius: 34, offset: const Offset(0, 16)),
      ];

  static const ivoire = Palette(
    id: 'ivoire',
    nom: 'Ivoire',
    sombre: false,
    fond: Color(0xFFF6F3EC),
    surface: Color(0xFFFFFFFF),
    surfaceCreuse: Color(0xFFEFEADF),
    encre: Color(0xFF0B1435),
    texte: Color(0xFF3A4156),
    attenue: Color(0xFF6B7080),
    trait: Color(0x170B1435),
    accent: Color(0xFFD4A23F),
    surAccent: Color(0xFF1A1400),
    accentTexte: Color(0xFF94690F),
    succes: Color(0xFF4F8060),
    alerte: Color(0xFFB9603F),
    heros: Color(0xFF16245A),
    herosFin: Color(0xFF0B1435),
    surHeros: Color(0xFFF7F4EC),
    surHerosDoux: Color(0xFFB9C1D6),
    accentSurHeros: Color(0xFFE8C070),
    ombre: Color(0xFF0B1435),
  );

  static const nuit = Palette(
    id: 'nuit',
    nom: 'Nuit',
    sombre: true,
    fond: Color(0xFF060C1F),
    surface: Color(0xFF0F1934),
    surfaceCreuse: Color(0xFF162244),
    encre: Color(0xFFF4F1E8),
    texte: Color(0xFFD3D8E6),
    attenue: Color(0xFF939CB5),
    trait: Color(0x1FE8C070),
    accent: Color(0xFFE3B456),
    surAccent: Color(0xFF1A1400),
    accentTexte: Color(0xFFEBC477),
    succes: Color(0xFF8DBB99),
    alerte: Color(0xFFE59474),
    heros: Color(0xFF243672),
    herosFin: Color(0xFF111C40),
    surHeros: Color(0xFFF7F4EC),
    surHerosDoux: Color(0xFFBAC3DC),
    accentSurHeros: Color(0xFFF0CB7E),
    ombre: Color(0xFF000000),
  );

  static const sepia = Palette(
    id: 'sepia',
    nom: 'Sépia',
    sombre: false,
    fond: Color(0xFFF1E6D0),
    surface: Color(0xFFFBF4E5),
    surfaceCreuse: Color(0xFFE7D9BD),
    encre: Color(0xFF3A2816),
    texte: Color(0xFF4F3C28),
    attenue: Color(0xFF7F6A52),
    trait: Color(0x1F3A2816),
    accent: Color(0xFFC0843A),
    surAccent: Color(0xFF211300),
    accentTexte: Color(0xFF85551A),
    succes: Color(0xFF5D7C49),
    alerte: Color(0xFFA9532F),
    heros: Color(0xFF6A4A2B),
    herosFin: Color(0xFF3A2816),
    surHeros: Color(0xFFFAF0DE),
    surHerosDoux: Color(0xFFDCC7A8),
    accentSurHeros: Color(0xFFF0C77F),
    ombre: Color(0xFF3A2816),
  );

  static const foret = Palette(
    id: 'foret',
    nom: 'Forêt',
    sombre: true,
    fond: Color(0xFF0A1712),
    surface: Color(0xFF12241B),
    surfaceCreuse: Color(0xFF1A3126),
    encre: Color(0xFFEFF4EA),
    texte: Color(0xFFCAD8CD),
    attenue: Color(0xFF8DA496),
    trait: Color(0x1FCFE3C8),
    accent: Color(0xFFD9B45A),
    surAccent: Color(0xFF191200),
    accentTexte: Color(0xFFE4C274),
    succes: Color(0xFF93C7A0),
    alerte: Color(0xFFE39A78),
    heros: Color(0xFF235138),
    herosFin: Color(0xFF12291D),
    surHeros: Color(0xFFF2F6EE),
    surHerosDoux: Color(0xFFB8CDBF),
    accentSurHeros: Color(0xFFEDCB7A),
    ombre: Color(0xFF000000),
  );

  static const tous = [ivoire, nuit, sepia, foret];

  static Palette parId(String? id) => tous.firstWhere((p) => p.id == id, orElse: () => ivoire);

  /// La palette en vigueur. Posée par l'application à chaque changement de
  /// thème ; les écrans la lisent par [Couleurs] ou par `context.palette`.
  static Palette courante = ivoire;

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(covariant Palette? other, double t) => t < 0.5 || other == null ? this : other;
}

extension PaletteDuContexte on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>() ?? Palette.courante;
}

/// Les arrondis : doux et réguliers, du plus petit au plus grand.
abstract final class Rayons {
  static const petit = BorderRadius.all(Radius.circular(10));
  static const moyen = BorderRadius.all(Radius.circular(14));
  static const carte = BorderRadius.all(Radius.circular(20));
  static const grand = BorderRadius.all(Radius.circular(28));
  static const pilule = BorderRadius.all(Radius.circular(999));
}
