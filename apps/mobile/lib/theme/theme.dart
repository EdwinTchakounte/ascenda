import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'couleurs.dart';

/// Deux thèmes conçus ensemble, pas l'un dérivé de l'autre par inversion.
///
/// Le mode clair est le défaut : c'est une application de lecture. Le mode
/// sombre sert la lecture de nuit et les écrans OLED, fréquents sur les
/// téléphones d'entrée de gamme.
abstract final class ThemeAscenda {
  static TextTheme _typo(TextTheme base, Color titre, Color corps) {
    // Fraunces dit « livre » sans être décorative ; Inter porte l'interface.
    final t = GoogleFonts.frauncesTextTheme(base);
    final c = GoogleFonts.interTextTheme(base);
    return base.copyWith(
      displayLarge: t.displayLarge?.copyWith(color: titre, fontWeight: FontWeight.w600),
      displayMedium: t.displayMedium?.copyWith(color: titre, fontWeight: FontWeight.w600),
      headlineLarge: t.headlineLarge?.copyWith(color: titre, fontWeight: FontWeight.w600, height: 1.18),
      headlineMedium: t.headlineMedium?.copyWith(color: titre, fontWeight: FontWeight.w600, height: 1.2),
      headlineSmall: t.headlineSmall?.copyWith(color: titre, fontWeight: FontWeight.w600, height: 1.25),
      titleLarge: t.titleLarge?.copyWith(color: titre, fontWeight: FontWeight.w600, fontSize: 21, height: 1.25),
      titleMedium: c.titleMedium?.copyWith(color: titre, fontWeight: FontWeight.w600, fontSize: 15.5),
      titleSmall: c.titleSmall?.copyWith(color: titre, fontWeight: FontWeight.w600),
      bodyLarge: c.bodyLarge?.copyWith(color: corps, height: 1.62, fontSize: 16),
      bodyMedium: c.bodyMedium?.copyWith(color: corps, height: 1.6, fontSize: 14.5),
      bodySmall: c.bodySmall?.copyWith(color: corps, height: 1.5, fontSize: 12.5),
      labelLarge: c.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
      labelMedium: c.labelMedium?.copyWith(letterSpacing: 0.2),
      labelSmall: c.labelSmall?.copyWith(letterSpacing: 0.6),
    );
  }

  static ThemeData get clair {
    const schema = ColorScheme.light(
      primary: Couleurs.orTexte,
      onPrimary: Colors.white,
      secondary: Couleurs.or,
      surface: Colors.white,
      onSurface: Couleurs.encre,
      surfaceContainerLowest: Couleurs.ivoire,
      surfaceContainer: Couleurs.ivoireCreuse,
      error: Couleurs.terracotta,
      outline: Couleurs.grisChaud,
    );
    return _monter(schema, Couleurs.papier, Couleurs.nuit, Couleurs.encreDouce, Couleurs.traitClair);
  }

  static ThemeData get sombre {
    const schema = ColorScheme.dark(
      primary: Couleurs.orClair,
      onPrimary: Couleurs.nuitProfond,
      secondary: Couleurs.or,
      surface: Couleurs.surfaceSombre,
      onSurface: Color(0xFFE6E9F2),
      surfaceContainerLowest: Couleurs.nuitProfond,
      surfaceContainer: Couleurs.nuit,
      error: Couleurs.terracotta,
      outline: Color(0xFF9AA3BA),
    );
    return _monter(
      schema, Couleurs.nuitProfond, const Color(0xFFF4F1E8),
      const Color(0xFFE6E9F2), Couleurs.traitSombre,
    );
  }

  static ThemeData _monter(
    ColorScheme schema, Color fond, Color titre, Color corps, Color trait,
  ) {
    final base = ThemeData(colorScheme: schema, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: fond,
      textTheme: _typo(base.textTheme, titre, corps),
      // Angles généreux, ombres diffuses, jamais de bordure dure à 1 px gris.
      cardTheme: CardThemeData(
        color: schema.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: trait),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: fond,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 22, fontWeight: FontWeight.w600, color: titre, letterSpacing: -0.2,
        ),
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: corps),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Couleurs.or,
          foregroundColor: const Color(0xFF1A1400),
          disabledBackgroundColor: Couleurs.or.withValues(alpha: 0.35),
          minimumSize: const Size(0, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          elevation: 0,
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: schema.primary,
          minimumSize: const Size(0, 54),
          side: BorderSide(color: schema.primary.withValues(alpha: 0.28)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: schema.primary,
          textStyle: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600),
          // Sans forme déclarée, le voile de survol garde les coins arrondis de
          // Material : c'est invisible tant qu'on ne survole pas, et très visible
          // dès qu'on survole.
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      inputDecorationTheme: InputDecorationTheme(
        // Un champ blanc à filet fin : un aplat beige se lit comme un bloc
        // désactivé, et une page de six champs beiges comme un formulaire
        // administratif.
        filled: true,
        fillColor: schema.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        floatingLabelStyle: GoogleFonts.inter(color: titre, fontWeight: FontWeight.w600),
        labelStyle: GoogleFonts.inter(color: Couleurs.grisChaud, fontSize: 14.5),
        helperStyle: GoogleFonts.inter(color: Couleurs.grisChaud, fontSize: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero, borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: trait.withValues(alpha: 0.16)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: titre, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(color: Couleurs.terracotta),
        ),
        hintStyle: GoogleFonts.inter(color: Couleurs.grisChaud, fontSize: 14.5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: schema.surface,
        surfaceTintColor: Colors.transparent,
        // Pas d'aplat derrière l'onglet actif : la couleur et la graisse
        // suffisent, et la barre reste légère.
        indicatorColor: Colors.transparent,
        // Sans cela, Material dessine une pastille en stade derrière l'icône
        // active : la seule forme arrondie qui restait de toute l'application.
        indicatorShape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        elevation: 0,
        height: 66,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (etats) => GoogleFonts.inter(
            fontSize: 11,
            fontWeight: etats.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: etats.contains(WidgetState.selected) ? titre : Couleurs.grisChaud,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (etats) => IconThemeData(
            size: 23,
            color: etats.contains(WidgetState.selected) ? schema.primary : Couleurs.grisChaud.withValues(alpha: 0.85),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: schema.surface,
        selectedColor: Couleurs.nuit,
        secondarySelectedColor: Couleurs.nuit,
        checkmarkColor: Colors.white,
        side: BorderSide(color: trait.withValues(alpha: 0.12)),
        labelStyle: GoogleFonts.inter(fontSize: 13, color: corps, fontWeight: FontWeight.w500),
        secondaryLabelStyle: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      dividerTheme: DividerThemeData(color: trait, thickness: 1, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Couleurs.or,
        linearMinHeight: 6,
        // Material 3 arrondit les extrémités des barres de progression.
        borderRadius: BorderRadius.zero,
      ),
      dialogTheme: DialogThemeData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        backgroundColor: schema.surface,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: Couleurs.nuit, borderRadius: BorderRadius.zero),
        textStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFE6E9F2)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(schema.primary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Couleurs.nuit,
        contentTextStyle: GoogleFonts.inter(color: const Color(0xFFE6E9F2), fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
  }
}
