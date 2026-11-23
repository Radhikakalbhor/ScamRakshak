# ScamRakshak Design System

Visual language taken from `design/reference-style.png` (style only; none of its content). The home
screen is the visual source of truth.

- Tokens: `lib/core/design/tokens.dart` (`DsColors`, `DsRadius`, `DsSpace`, `DsType`, `DsWeight`, `DsFont`, `DsMotion`, `kDsTouch`)
- Components: `lib/core/design/components.dart`
- Global Material theme: `lib/core/theme.dart` (built only from the tokens; legacy `AppTheme.*` names are aliases)

**All UI must use the shared components and tokens. Never hardcode colors, radii, fonts, font weights or spacing.**

## Principles
Calm, minimal, mobile-first (390 dp design width, works from 360 dp). Warm off-white page, flat pastel
surfaces, very large headings, generous space. One saturated color with meaning: **alert red**
(Report Fraud, scam / HIGH risk). Brand teal is an accent, never a full bar. Risk colors (alert,
caution, safe) are the only other strong colors and only carry risk meaning.

## Color (`DsColors`)
Page and pastels sampled from the reference image.

| Token | Hex | Use |
|---|---|---|
| `page` | `#FCFCF9` | Scaffold background |
| `surface` | `#FFFFFF` | White panels, list rows, inputs |
| `line` | `#ECEAE4` | Hairline borders, dividers |
| `track` | `#EDEBE5` | Progress track, disabled fills |
| `scrim` | `#151515` @ 60 % | Modal barrier |
| `peach` / `powder` / `mint` / `lavender` | `#FCEAC6` / `#D8EDED` / `#D8EADE` / `#E1D2FF` | Pastel cards; `pastels` = rotation order |
| `peachDeep` / `powderDeep` / `mintDeep` / `lavenderDeep` | `#B0750F` / `#3F8C8C` / `#3E8A5A` / `#7A55D0` | **Charts only** (≥ 3.9:1 vs white); `chart` = series order |
| `ink` | `#151515` | Text, dark badges, primary button |
| `muted` | `#5E5D58` | Secondary text, captions |
| `brand` | `#0F766E` | Logo badge, selected chip, focus, progress |
| `alert` / `alertSoft` | `#D92D20` / `#FDE8E6` | Scam / HIGH risk; soft tint behind ink text |
| `caution` / `cautionSoft` | `#B54708` / `#FFF1E0` | MEDIUM risk |
| `amber` | `#FFB300` | Full-screen MEDIUM warning background (ink text) |
| `safe` / `safeSoft` | `#067647` / `#E3F4EA` | LOW risk / success |
| `highlight` | `#FFE0B2` | Dangerous sentence shading in transcripts |
| `camera` | `#000000` | Camera preview surroundings only |

Contrast (WCAG 2.1, measured): ink on page 17.8 · muted on page 6.4, on pastels ≥ 4.67 · white on alert
4.8, on brand 5.5 · caution on white 5.4, on cautionSoft 4.9 · safe on white 5.7, on safeSoft 5.0 ·
ink on amber 10.2, on highlight 14.4, on alertSoft 15.5. Alert-colored text on `alertSoft` is only
4.1, so on soft tints text is ink and the color goes on icons/borders.

Mappings: home cards Message = peach, QR = powder, Call = mint, Live Call Guard = lavender. Lesson
topics rotate through `pastels`. Verdicts: `DsVerdict.danger/caution/safe` → alert/caution/safe.

## Typography (`DsFont`, `DsWeight`, `DsType`)
**Inter Tight** (Latin) + **Noto Sans Devanagari** (Hindi, Chhattisgarhi) as `fontFamilyFallback`.
Both are bundled at **400 / 500 / 600 / 700** (OFL; `assets/fonts/`), so Devanagari renders at the
same weight as Latin; no `google_fonts` (offline).

Weights: `regular` 400 only for long reading text · `medium` 500 display, headings, body, descriptions ·
`semibold` 600 section/card titles, labels, chips, buttons, captions · `bold` 700 only for small
emphasis (score numbers). Nothing heavier.

| Style | Size / weight / tracking | Use |
|---|---|---|
| `display` | 44 / 500 / -1.6, line 1.02 | Page heading |
| `headline` | 30 / 500 / -0.9 | Big card titles (Report Fraud) |
| `cardTitle` | 22 / 600 / -0.5 | Card and panel titles |
| `section` | 19 / 600 / -0.3 | Section titles |
| `title` | 17 / 600 / -0.2 | List titles, brand |
| `body` | 15 / 500, line 1.4 | Text |
| `reading` | 17 / 400, line 1.5 | Long text: lessons, transcripts |
| `small` | 13 / 500, muted | Descriptions |
| `greeting` | 14 / 600, muted | Caption above titles |
| `caption` | 12 / 600, muted | Tiny labels |
| `label` | 15 / 600 | Buttons, chips |
| `number` | 48 / 700 / -2 | Scores |

Named variants (use these instead of `copyWith(fontSize: …)`, which the token check rejects):
`displaySmall` 36/500 (full-screen alert heading) · `headlineSmall` 26/500 (flash cards) ·
`featureTitle` 20/600 (FeatureCard) · `titleLarge` 18/600 (tappable card titles) · `bodyLarge` 17/500
(quiz options, consent, inputs) · `numberSmall` 34/700 (stat tiles, small scores) · `chartTick` 11/500
and `chartMicro` 9/600 (chart labels only).

Why Inter Tight: the reference is a neo-grotesk with tight tracking at display sizes; Inter Tight is
Inter with tighter default spacing for display use, free (OFL) and available in every weight above.

## Shape, space, elevation
Radius (`DsRadius`): `card` 30 (cards, panels, dialogs) · `tile` 20 (inputs, list rows, toasts) ·
`small` 10 (tags, marks) · `pill` 999 (chips, buttons). Spacing (`DsSpace`): 2 · 4 · 8 · 12 · 16 ·
20 (screen gutter) · 28 · 32 (section). Flat: elevation 0, no shadows; white panels get a 1 px `line`
border, pastel cards none. Touch targets ≥ 48 × 48 (`kDsTouch`; Android guideline, above the 44 × 44 minimum).

## Motion (`DsMotion`)
Press: scale 0.97 in 120 ms, ease-out cubic (`Pressable`). State changes (chips, progress): 220 ms.
Screen changes: fade-forward page transition. No splash ripples.

## Components (`lib/core/design/components.dart`)
Surfaces: `PastelCard`, `SurfacePanel`, `FeatureCard`, `PairRow`. Parts: `IconBadge`, `ArrowButton`
(also the icon button, e.g. bell), `PillChip`, `ScreenHeader`, `PrimaryButton` (filled / outlined,
`color`, `busy`), `ProgressBar`, `Pressable`. Inputs and lists: `AppTextField`, `DsListTile`,
`DsTabs`. Feedback: `VerdictBanner` + `DsVerdict`, `showDsDialog`, `showDsToast`, `EmptyState`,
`LoadingState`.

## Screen-specific decisions
- Full-screen scam warning stays solid `alert` (HIGH) / `amber` (MEDIUM): it must alarm; type, radii and buttons follow the system.
- QR camera page stays on `camera` black around the preview; controls use the system.
- Scam Trends: stat tiles are the four pastels; the 7-day chart keeps `alert` / `safe` for risky /
  safe (meaning, not decoration); district, scam-type and weekly bars use the deep chart pastels.
- Quiz: the right / wrong answer uses `safe` / `alert` borders on `safeSoft` / `alertSoft`.
- Lesson topics map to the four pastels (`lessonTopicColor`).

## Token check (lint)
`dart run tool/check_design_tokens.dart` scans `lib/` and fails on raw `Color(0x…)`, `Colors.*`
(except `transparent`), `FontWeight.*`, `fontFamily:`, `fontSize:`, numeric `BorderRadius.circular`,
numeric `EdgeInsets` and legacy `AppTheme.*`. Only `tokens.dart` and `theme.dart` hold raw values.
`test/core/design_lint_test.dart` runs the same check, so `flutter test` fails on a violation. A line
that truly needs a raw value ends with `// ds-ignore: <reason>`.

## Accessibility
Icon-only controls have a `semanticLabel`; tappable cards expose one merged label; selected chips are
marked `selected`. Tests check tap targets (48 dp), labels and AA text contrast on the main screens in
English, Hindi and Chhattisgarhi (`test/core/accessibility_test.dart`, `components_test.dart`).
Devanagari uses bundled Noto Sans Devanagari at 400/500/600/700 so Hindi matches the Latin weights.
Text on soft tints (`alertSoft`, `safeSoft`, `cautionSoft`) is `ink`, never the semantic colour.

## Sources
- `design/reference-style.png` — style reference. `design/SPEC.md` — home content and order.
