import 'package:flutter/material.dart';

/// ScamRakshak design tokens. Source of truth: design/DESIGN_SYSTEM.md.
/// All UI must use these tokens. Never hardcode colors, radii, fonts, font weights or spacing.
abstract final class DsColors {
  // Surfaces (sampled from design/reference-style.png)
  static const page = Color(0xFFFCFCF9); // warm off-white page
  static const surface = Color(0xFFFFFFFF); // white panels on the page
  static const line = Color(0xFFECEAE4); // hairline borders / dividers
  static const track = Color(0xFFEDEBE5); // progress track, disabled fills
  static const scrim = Color(0x99151515); // modal barrier

  // Pastel card fills (sampled)
  static const peach = Color(0xFFFCEAC6);
  static const powder = Color(0xFFD8EDED);
  static const mint = Color(0xFFD8EADE);
  static const lavender = Color(0xFFE1D2FF);

  /// The four pastels in order, for content that needs a rotating color (lesson topics, etc.).
  static const pastels = [peach, powder, mint, lavender];

  // Chart-only deeper shades of the pastels (bars/segments; >= 3:1 against white, never for text).
  static const peachDeep = Color(0xFFB0750F);
  static const powderDeep = Color(0xFF3F8C8C);
  static const mintDeep = Color(0xFF3E8A5A);
  static const lavenderDeep = Color(0xFF7A55D0);
  static const chart = [powderDeep, peachDeep, mintDeep, lavenderDeep];

  // Ink
  static const ink = Color(0xFF151515); // headings, body, dark badges (17.8:1 on page)
  static const muted = Color(0xFF5E5D58); // secondary text (6.4:1 on page, >= 4.67:1 on every pastel)
  static const onDark = Color(0xFFFFFFFF);
  static const camera = Color(0xFF000000); // camera preview surroundings only

  // Accents (the only non-pastel colors)
  static const brand = Color(0xFF0F766E); // brand teal: logo badge, selected chip, focus (5.5:1 vs white)
  static const alert = Color(0xFFD92D20); // the one alert color: Report Fraud, scam / HIGH risk
  static const alertInk = Color(0xFFFFFFFF);
  static const alertSoft = Color(0xFFFDE8E6); // tinted background: text on it is ink; alert only for icons
  static const caution = Color(0xFFB54708); // MEDIUM risk (5.4:1 vs white)
  static const cautionSoft = Color(0xFFFFF1E0);
  static const amber = Color(0xFFFFB300); // full-screen MEDIUM warning background (with ink text)
  static const safe = Color(0xFF067647); // LOW risk / success (5.7:1 vs white)
  static const safeSoft = Color(0xFFE3F4EA);
  static const highlight = Color(0xFFFFE0B2); // shading of a dangerous sentence in transcripts
}

abstract final class DsRadius {
  static const card = 30.0; // pastel cards, panels, dialogs
  static const tile = 20.0; // inner tiles, inputs, list rows, snackbars
  static const small = 10.0; // highlight marks, tiny tags
  static const pill = 999.0; // chips, buttons
}

abstract final class DsSpace {
  static const xxs = 2.0;
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
  /// Inter Tight (Latin) + Noto Sans Devanagari (Hindi / Chhattisgarhi) fallback; both bundled
  /// at 400 / 500 / 600 / 700 so Devanagari renders at the same weight as Latin.
  static const family = 'Inter Tight';
  static const fallback = ['Noto Sans Devanagari'];
}

/// Font weights. Nothing above [semibold] except [bold] for small emphasis (score numbers).
abstract final class DsWeight {
  static const regular = FontWeight.w400; // long-form reading only (lesson text, transcripts)
  static const medium = FontWeight.w500; // display, headings, body, descriptions
  static const semibold = FontWeight.w600; // section / card titles, labels, chips, buttons, captions
  static const bold = FontWeight.w700; // score numbers only
}

/// Type scale: very large display, tight tracking; calm body.
abstract final class DsType {
  static TextStyle _s(double size, FontWeight w, double height, double ls, Color color) => TextStyle(
        fontFamily: DsFont.family,
        fontFamilyFallback: DsFont.fallback,
        fontSize: size,
        fontWeight: w,
        height: height,
        letterSpacing: ls,
        color: color,
      );

  static final display = _s(44, DsWeight.medium, 1.02, -1.6, DsColors.ink); // page heading
  static final headline = _s(30, DsWeight.medium, 1.08, -0.9, DsColors.ink); // big card title
  static final cardTitle = _s(22, DsWeight.semibold, 1.12, -0.5, DsColors.ink); // card / panel title
  static final section = _s(19, DsWeight.semibold, 1.2, -0.3, DsColors.ink); // section title
  static final title = _s(17, DsWeight.semibold, 1.25, -0.2, DsColors.ink); // list title, brand
  static final body = _s(15, DsWeight.medium, 1.4, 0, DsColors.ink); // body
  static final reading = _s(17, DsWeight.regular, 1.5, 0, DsColors.ink); // long text, transcripts
  static final small = _s(13, DsWeight.medium, 1.35, 0, DsColors.muted); // descriptions
  static final greeting = _s(14, DsWeight.semibold, 1.3, -0.1, DsColors.muted); // caption above titles
  static final caption = _s(12, DsWeight.semibold, 1.3, 0, DsColors.muted); // tiny labels
  static final label = _s(15, DsWeight.semibold, 1.2, -0.1, DsColors.ink); // buttons, chips
  static final number = _s(48, DsWeight.bold, 1.0, -2, DsColors.ink); // score numbers
}
