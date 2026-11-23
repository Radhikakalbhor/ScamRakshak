import 'package:flutter/material.dart';

/// ScamRakshak design tokens. Source of truth: design/DESIGN_SYSTEM.md.
/// Never use colors, radii, spacing, fonts or durations outside these tokens.
abstract final class DsColors {
  // Surfaces (sampled from design/reference-style.png)
  static const page = Color(0xFFFCFCF9); // warm off-white page
  static const surface = Color(0xFFFFFFFF); // white panels on the page
  static const line = Color(0xFFECEAE4); // hairline borders / dividers
  static const track = Color(0xFFEDEBE5); // progress track, disabled fills

  // Pastel card fills (sampled)
  static const peach = Color(0xFFFCEAC6);
  static const powder = Color(0xFFD8EDED);
  static const mint = Color(0xFFD8EADE);
  static const lavender = Color(0xFFE1D2FF);

  // Ink
  static const ink = Color(0xFF151515); // headings, body, dark badges (17.8:1 on page)
  static const muted = Color(0xFF5E5D58); // greeting / secondary text (6.4:1 on page, >= 4.67:1 on every pastel)
  static const onDark = Color(0xFFFFFFFF);

  // Accents (the only non-pastel colors)
  static const brand = Color(0xFF0F766E); // brand teal: logo badge, selected chip, focus (5.4:1 on white)
  static const alert = Color(0xFFD92D20); // the one semantic alert color: Report Fraud, scam verdicts
  static const alertInk = Color(0xFFFFFFFF);
  static const caution = Color(0xFFB54708); // medium-risk text/icons (AA on white)
  static const safe = Color(0xFF067647); // low-risk / success
}

abstract final class DsRadius {
  static const card = 30.0; // pastel cards, panels
  static const tile = 20.0; // inner tiles, inputs
  static const pill = 999.0; // chips, buttons
}

abstract final class DsSpace {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 20.0; // screen gutter
  static const xxl = 28.0;
  static const section = 32.0;
}

/// Minimum touch target: 48 x 48 (Android guideline; also satisfies the 44 x 44 WCAG/iOS minimum).
const kDsTouch = 48.0;

abstract final class DsMotion {
  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;
  static const pressScale = 0.97;
}

abstract final class DsFont {
  /// Inter Tight (Latin) + Noto Sans Devanagari (Hindi / Chhattisgarhi) fallback; both bundled.
  static const family = 'Inter Tight';
  static const fallback = ['Noto Sans Devanagari'];
}

/// Type scale: very large light display, tight tracking; calm body.
abstract final class DsType {
  static const display = TextStyle(
      fontFamily: DsFont.family, fontFamilyFallback: DsFont.fallback,
      fontSize: 44, height: 1.02, fontWeight: FontWeight.w300, letterSpacing: -1.6, color: DsColors.ink);
  static const headline = TextStyle(
      fontFamily: DsFont.family, fontFamilyFallback: DsFont.fallback,
      fontSize: 30, height: 1.08, fontWeight: FontWeight.w300, letterSpacing: -0.9, color: DsColors.ink);
  static const cardTitle = TextStyle(
      fontFamily: DsFont.family, fontFamilyFallback: DsFont.fallback,
      fontSize: 22, height: 1.1, fontWeight: FontWeight.w400, letterSpacing: -0.5, color: DsColors.ink);
  static const title = TextStyle(
      fontFamily: DsFont.family, fontFamilyFallback: DsFont.fallback,
      fontSize: 18, height: 1.25, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: DsColors.ink);
  static const body = TextStyle(
      fontFamily: DsFont.family, fontFamilyFallback: DsFont.fallback,
      fontSize: 15, height: 1.4, fontWeight: FontWeight.w400, color: DsColors.ink);
  static const small = TextStyle(
      fontFamily: DsFont.family, fontFamilyFallback: DsFont.fallback,
      fontSize: 13, height: 1.35, fontWeight: FontWeight.w400, color: DsColors.muted);
  static const greeting = TextStyle(
      fontFamily: DsFont.family, fontFamilyFallback: DsFont.fallback,
      fontSize: 14, height: 1.3, fontWeight: FontWeight.w400, letterSpacing: -0.1, color: DsColors.muted);
  static const label = TextStyle(
      fontFamily: DsFont.family, fontFamilyFallback: DsFont.fallback,
      fontSize: 15, height: 1.2, fontWeight: FontWeight.w500, letterSpacing: -0.1, color: DsColors.ink);
  static const number = TextStyle(
      fontFamily: DsFont.family, fontFamilyFallback: DsFont.fallback,
      fontSize: 48, height: 1.0, fontWeight: FontWeight.w300, letterSpacing: -2, color: DsColors.ink);
}
