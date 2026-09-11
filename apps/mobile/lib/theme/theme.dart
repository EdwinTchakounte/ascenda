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
      titleLarge: t.titleLarge?.copyWith(color: titre, fontWeight: FontWeight.w600),
      titleMedium: c.titleMedium?.copyWith(color: titre, fontWeight: FontWeight.w600),
      titleSmall: c.titleSmall?.copyWith(color: titre, fontWeight: FontWeight.w600),
      bodyLarge: c.bodyLarge?.copyWith(color: corps, height: 1.6),
      bodyMedium: c.bodyMedium?.copyWith(color: corps, height: 1.6),
      bodySmall: c.bodySmall?.copyWith(color: corps, height: 1.5),
      labelLarge: c.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      labelMedium: c.labelMedium,
      labelSmall: c.labelSmall?.copyWith(letterSpacing: 0.9),
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
    return _monter(schema, Couleurs.ivoire, Couleurs.nuit, Couleurs.encre, Couleurs.traitClair);
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
          fontSize: 20, fontWeight: FontWeight.w600, color: titre,
        ),
        iconTheme: IconThemeData(color: corps),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Couleurs.or,
          foregroundColor: const Color(0xFF1A1400),
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: GoogleFonts.inter(fontSize: 15.5, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: schema.primary,
          minimumSize: const Size(0, 52),
          side: BorderSide(color: schema.primary.withValues(alpha: 0.4)),
          textStyle: GoogleFonts.inter(fontSize: 15.5, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: schema.primary,
          textStyle: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: schema.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero, borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: trait),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(color: Couleurs.or, width: 1.6),
        ),
        hintStyle: GoogleFonts.inter(color: Couleurs.grisChaud, fontSize: 14.5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: schema.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Couleurs.or.withValues(alpha: 0.16),
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (etats) => GoogleFonts.inter(
            fontSize: 11,
            fontWeight: etats.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: etats.contains(WidgetState.selected) ? schema.primary : Couleurs.grisChaud,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (etats) => IconThemeData(
            size: 23,
            color: etats.contains(WidgetState.selected) ? schema.primary : Couleurs.grisChaud,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: schema.surfaceContainer,
        side: BorderSide(color: trait),
        labelStyle: GoogleFonts.inter(fontSize: 12.5, color: corps),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      dividerTheme: DividerThemeData(color: trait, thickness: 1, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Couleurs.or, linearMinHeight: 6,
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
