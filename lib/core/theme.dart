import 'package:flutter/material.dart';

import 'design/tokens.dart';

/// App-wide theme built ONLY from the design tokens (lib/core/design/tokens.dart,
/// documented in design/DESIGN_SYSTEM.md): warm off-white page, flat pastel surfaces,
/// large radii, light tight-tracked Inter Tight with Noto Sans Devanagari fallback.
///
/// The color names below are kept as aliases so existing screens keep compiling and
/// automatically follow the design system. New code should use the Ds* tokens directly.
class AppTheme {
  // Brand / accents
  static const Color primaryTeal = DsColors.brand;
  static const Color primaryDarkTeal = DsColors.brand;
  static const Color primaryLightTeal = DsColors.powder;

  static const Color secondaryNavy = DsColors.ink;
  static const Color secondaryLightBlue = DsColors.powder;

  // Surfaces
  static const Color backgroundLight = DsColors.page;
  static const Color surfaceWhite = DsColors.surface;
  static const Color cardBorderColor = DsColors.line;

  // Semantic status colors (alert is the only saturated color in the system)
  static const Color errorRed = DsColors.alert;
  static const Color warningOrange = DsColors.caution;
  static const Color successGreen = DsColors.safe;

  // Text
  static const Color textPrimary = DsColors.ink;
  static const Color textSecondary = DsColors.muted;

  // Font (Latin); Devanagari falls back to the bundled Noto Sans Devanagari.
  static const String fontFamily = DsFont.family;
  static const List<String> fontFamilyFallback = DsFont.fallback;

  static TextStyle _t(double size, FontWeight w, {double height = 1.3, double ls = 0, Color color = DsColors.ink}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: size,
        fontWeight: w,
        height: height,
        letterSpacing: ls,
        color: color,
      );

  static ThemeData get lightTheme {
    const colorScheme = ColorScheme.light(
      primary: DsColors.brand,
      onPrimary: DsColors.onDark,
      primaryContainer: DsColors.powder,
      onPrimaryContainer: DsColors.ink,
      secondary: DsColors.ink,
      onSecondary: DsColors.onDark,
      secondaryContainer: DsColors.lavender,
      onSecondaryContainer: DsColors.ink,
      tertiaryContainer: DsColors.mint,
      surface: DsColors.surface,
      onSurface: DsColors.ink,
      onSurfaceVariant: DsColors.muted,
      outline: DsColors.line,
      outlineVariant: DsColors.line,
      error: DsColors.alert,
      onError: DsColors.alertInk,
    );
    final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(DsRadius.pill));
    final label = _t(16, DsWeight.semibold, ls: -0.1);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      scaffoldBackgroundColor: DsColors.page,
      splashFactory: NoSplash.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: DsColors.page,
        foregroundColor: DsColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: _t(20, DsWeight.semibold, ls: -0.3),
        iconTheme: const IconThemeData(color: DsColors.ink, size: 26),
      ),
      textTheme: TextTheme(
        displayLarge: DsType.display,
        displayMedium: DsType.headline,
        headlineLarge: _t(28, DsWeight.medium, height: 1.1, ls: -0.8),
        headlineMedium: _t(24, DsWeight.medium, height: 1.15, ls: -0.6),
        headlineSmall: _t(20, DsWeight.semibold, height: 1.2, ls: -0.3),
        titleLarge: _t(19, DsWeight.semibold, ls: -0.2),
        titleMedium: _t(17, DsWeight.semibold, ls: -0.1),
        bodyLarge: _t(16, DsWeight.medium, height: 1.4),
        bodyMedium: _t(14, DsWeight.medium, height: 1.4, color: DsColors.muted),
        labelLarge: label,
      ),
      cardTheme: CardThemeData(
        color: DsColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DsRadius.tile),
          side: const BorderSide(color: DsColors.line),
        ),
        margin: const EdgeInsets.symmetric(vertical: DsSpace.s, horizontal: DsSpace.m),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DsColors.ink,
          foregroundColor: DsColors.onDark,
          minimumSize: const Size(kDsTouch, 52),
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.xl, vertical: DsSpace.m),
          shape: pill,
          textStyle: label,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DsColors.ink,
          foregroundColor: DsColors.onDark,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.xl, vertical: DsSpace.m),
          shape: pill,
          textStyle: label,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DsColors.ink,
          minimumSize: const Size(kDsTouch, 48),
          side: const BorderSide(color: DsColors.ink, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.xl, vertical: DsSpace.m),
          shape: pill,
          textStyle: label,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DsColors.ink,
          minimumSize: const Size(kDsTouch, kDsTouch),
          shape: pill,
          textStyle: label,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: DsColors.surface,
        selectedColor: DsColors.brand,
        labelStyle: _t(15, DsWeight.semibold),
        secondaryLabelStyle: _t(15, DsWeight.semibold, color: DsColors.onDark),
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.m, vertical: DsSpace.s),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DsRadius.pill),
          side: const BorderSide(color: DsColors.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DsColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DsRadius.tile),
          borderSide: const BorderSide(color: DsColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DsRadius.tile),
          borderSide: const BorderSide(color: DsColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DsRadius.tile),
          borderSide: const BorderSide(color: DsColors.brand, width: 1.6),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: DsColors.ink,
        linearTrackColor: DsColors.track,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? DsColors.onDark : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? DsColors.brand : null),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: DsColors.ink,
        contentTextStyle: _t(15, DsWeight.medium, color: DsColors.onDark),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DsRadius.tile)),
      ),
      dividerTheme: const DividerThemeData(color: DsColors.line, thickness: 1),
      // Smooth, subtle screen changes (Android app).
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}
