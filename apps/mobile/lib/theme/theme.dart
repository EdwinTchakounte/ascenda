import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'palette.dart';

/// Le thème Material d'ASCENDA, monté depuis une [Palette].
abstract final class ThemeAscenda {
  static TextTheme _typo(TextTheme base, Palette p) {
    final t = GoogleFonts.frauncesTextTheme(base);
    final c = GoogleFonts.interTextTheme(base);
    return base.copyWith(
      // L'échelle d'un livre : un titre de page franc, des intertitres nets
      displayLarge: t.displayLarge?.copyWith(color: p.encre, fontWeight: FontWeight.w600, letterSpacing: -1.2),
      displayMedium: t.displayMedium?.copyWith(color: p.encre, fontWeight: FontWeight.w600, letterSpacing: -1),
      displaySmall: t.displaySmall?.copyWith(color: p.encre, fontWeight: FontWeight.w600, letterSpacing: -0.8),
      headlineLarge: t.headlineLarge?.copyWith(
          color: p.encre, fontWeight: FontWeight.w600, fontSize: 36, height: 1.1, letterSpacing: -0.9),
      headlineMedium: t.headlineMedium?.copyWith(
          color: p.encre, fontWeight: FontWeight.w600, fontSize: 30, height: 1.14, letterSpacing: -0.7),
      headlineSmall: t.headlineSmall?.copyWith(
          color: p.encre, fontWeight: FontWeight.w600, fontSize: 25, height: 1.2, letterSpacing: -0.45),
      titleLarge: t.titleLarge?.copyWith(color: p.encre, fontWeight: FontWeight.w600, fontSize: 22, height: 1.24, letterSpacing: -0.3),
      titleMedium: c.titleMedium?.copyWith(color: p.encre, fontWeight: FontWeight.w600, fontSize: 16, letterSpacing: -0.1),
      titleSmall: c.titleSmall?.copyWith(color: p.encre, fontWeight: FontWeight.w600),
      bodyLarge: c.bodyLarge?.copyWith(color: p.texte, height: 1.64, fontSize: 16.5),
      bodyMedium: c.bodyMedium?.copyWith(color: p.texte, height: 1.6, fontSize: 15),
      bodySmall: c.bodySmall?.copyWith(color: p.texte, height: 1.52, fontSize: 13),
      labelLarge: c.labelLarge?.copyWith(color: p.encre, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      labelMedium: c.labelMedium?.copyWith(color: p.texte, letterSpacing: 0.2),
      labelSmall: c.labelSmall?.copyWith(color: p.attenue, letterSpacing: 0.6),
    );
  }

  static ThemeData get clair => depuis(Palette.ivoire);
  static ThemeData get sombre => depuis(Palette.nuit);

  static ThemeData depuis(Palette p) {
    final schema = ColorScheme(
      brightness: p.sombre ? Brightness.dark : Brightness.light,
      primary: p.accentTexte,
      onPrimary: p.sombre ? p.surAccent : Colors.white,
      primaryContainer: p.accentVoile,
      onPrimaryContainer: p.encre,
      secondary: p.accent,
      onSecondary: p.surAccent,
      surface: p.surface,
      onSurface: p.encre,
      onSurfaceVariant: p.attenue,
      surfaceContainerLowest: p.fond,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surfaceCreuse,
      surfaceContainerHigh: p.surfaceCreuse,
      surfaceContainerHighest: p.surfaceCreuse,
      error: p.alerte,
      onError: Colors.white,
      outline: p.attenue,
      outlineVariant: p.trait,
      shadow: p.ombre,
    );
    final base = ThemeData(colorScheme: schema, useMaterial3: true);
    final inter = GoogleFonts.inter;

    return base.copyWith(
      extensions: [p],
      scaffoldBackgroundColor: p.fond,
      canvasColor: p.fond,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _typo(base.textTheme, p),
      iconTheme: IconThemeData(color: p.texte),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: Rayons.carte, side: BorderSide(color: p.trait)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.fond,
        foregroundColor: p.encre,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 25, fontWeight: FontWeight.w600, color: p.encre, letterSpacing: -0.5,
        ),
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: p.encre),
        actionsIconTheme: IconThemeData(color: p.texte),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.surAccent,
          disabledBackgroundColor: p.accent.withValues(alpha: 0.35),
          disabledForegroundColor: p.surAccent.withValues(alpha: 0.5),
          minimumSize: const Size(0, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          elevation: 0,
          textStyle: inter(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.1),
          shape: const RoundedRectangleBorder(borderRadius: Rayons.moyen),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.encre,
          minimumSize: const Size(0, 54),
          side: BorderSide(color: p.encre.withValues(alpha: 0.16)),
          textStyle: inter(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.1),
          shape: const RoundedRectangleBorder(borderRadius: Rayons.moyen),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accentTexte,
          textStyle: inter(fontSize: 14.5, fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(borderRadius: Rayons.petit),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: p.encre),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.accent,
        foregroundColor: p.surAccent,
        elevation: 2,
        shape: const RoundedRectangleBorder(borderRadius: Rayons.carte),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: p.accentVoile,
          selectedForegroundColor: p.encre,
          foregroundColor: p.texte,
          side: BorderSide(color: p.trait),
          shape: const RoundedRectangleBorder(borderRadius: Rayons.moyen),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Rayons.moyen),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.surface),
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: Rayons.moyen)),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: p.fond,
        surfaceTintColor: Colors.transparent,
        width: 312,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(5))),
        fillColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected) ? p.accentTexte : Colors.transparent,
        ),
        side: BorderSide(color: p.attenue, width: 1.4),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected) ? p.accentTexte : p.attenue,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        floatingLabelStyle: inter(color: p.encre, fontWeight: FontWeight.w600),
        labelStyle: inter(color: p.attenue, fontSize: 14.5),
        helperStyle: inter(color: p.attenue, fontSize: 12),
        prefixIconColor: p.attenue,
        suffixIconColor: p.attenue,
        border: const OutlineInputBorder(borderRadius: Rayons.moyen, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: Rayons.moyen,
          borderSide: BorderSide(color: p.trait),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Rayons.moyen,
          borderSide: BorderSide(color: p.accentTexte, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Rayons.moyen,
          borderSide: BorderSide(color: p.alerte),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: Rayons.moyen,
          borderSide: BorderSide(color: p.alerte, width: 1.6),
        ),
        hintStyle: inter(color: p.attenue, fontSize: 14.5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        // Aucune pastille derrière l'onglet actif : la coque dessine un filet
        // d'or sous l'onglet retenu, comme un signet glissé dans la page.
        indicatorColor: Colors.transparent,
        indicatorShape: const RoundedRectangleBorder(borderRadius: Rayons.pilule),
        elevation: 0,
        height: 74,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (etats) => inter(
            fontSize: 11,
            fontWeight: etats.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: etats.contains(WidgetState.selected) ? 1.1 : 0.8,
            color: etats.contains(WidgetState.selected) ? p.encre : p.attenue,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (etats) => IconThemeData(
            size: 25,
            color: etats.contains(WidgetState.selected) ? p.accentTexte : p.attenue,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.encre,
        unselectedLabelColor: p.attenue,
        indicatorColor: p.accent,
        dividerColor: p.trait,
        labelStyle: inter(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: inter(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.encre,
        secondarySelectedColor: p.encre,
        checkmarkColor: p.fond,
        side: BorderSide(color: p.trait),
        labelStyle: inter(fontSize: 13, color: p.texte, fontWeight: FontWeight.w500),
        secondaryLabelStyle: inter(fontSize: 13, color: p.fond, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: const RoundedRectangleBorder(borderRadius: Rayons.pilule),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.texte,
        textColor: p.encre,
        shape: const RoundedRectangleBorder(borderRadius: Rayons.moyen),
      ),
      dividerTheme: DividerThemeData(color: p.trait, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.surfaceCreuse,
        circularTrackColor: p.surfaceCreuse,
        linearMinHeight: 6,
        borderRadius: Rayons.pilule,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: p.surfaceCreuse,
        thumbColor: p.accent,
        overlayColor: p.accentVoile,
      ),
      dialogTheme: DialogThemeData(
        shape: const RoundedRectangleBorder(borderRadius: Rayons.grand),
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.fraunces(fontSize: 21, fontWeight: FontWeight.w600, color: p.encre),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: p.attenue.withValues(alpha: 0.4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      badgeTheme: BadgeThemeData(backgroundColor: p.alerte, textColor: Colors.white),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: p.encre, borderRadius: Rayons.petit),
        textStyle: inter(fontSize: 12, color: p.fond),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected) ? p.surAccent : p.attenue,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected) ? p.accent : p.surfaceCreuse,
        ),
        trackOutlineColor: WidgetStatePropertyAll(p.trait),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.encre,
        contentTextStyle: inter(color: p.fond, fontSize: 14),
        actionTextColor: p.accent,
        shape: const RoundedRectangleBorder(borderRadius: Rayons.moyen),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
