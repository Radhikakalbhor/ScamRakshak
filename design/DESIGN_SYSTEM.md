# ScamRakshak Design System

Visual language taken from `design/reference-style.png` (style only; none of its content).
Code: tokens in `lib/core/design/tokens.dart`, components in `lib/core/design/components.dart`,
global Material theme in `lib/core/theme.dart`. **Never introduce colors, radii, spacing, fonts or
durations outside the tokens.**

## Principles
Calm, minimal, mobile-first (390 dp design width, works from 360 dp up). Warm off-white page, flat
pastel surfaces, very large light headings, generous space. Exactly one saturated color with meaning:
**alert red** (Report Fraud, scam verdicts). Brand teal is an accent, never a full bar.

## Color (`DsColors`)
Pastels and page sampled from the reference image (mode color of each region).

| Token | Hex | Use |
|---|---|---|
| `page` | `#FCFCF9` | Scaffold / page background (warm off-white) |
| `surface` | `#FFFFFF` | White panels on the page |
| `line` | `#ECEAE4` | Hairline borders, dividers |
| `track` | `#EDEBE5` | Progress track, disabled fills |
| `peach` | `#FCEAC6` | Pastel card |
| `powder` | `#D8EDED` | Pastel card (powder blue) |
| `mint` | `#D8EADE` | Pastel card |
| `lavender` | `#E1D2FF` | Pastel card / chip |
| `ink` | `#151515` | Text, dark icon badges, primary button |
| `muted` | `#5E5D58` | Greeting line, secondary text |
| `brand` | `#0F766E` | Logo badge, selected chip, focus, progress |
| `alert` | `#D92D20` | Report Fraud, scam/high-risk only |
| `caution` | `#B54708` | Medium risk text/icons |
| `safe` | `#067647` | Low risk / success |

Contrast (WCAG 2.1, all AA or better): ink on page 17.8:1 · muted on page 6.4:1, on peach 5.6,
powder 5.4, mint 5.3, lavender 4.7 · white on alert 4.8 · white on brand 5.5 · caution on white 5.4 ·
safe on white 5.7. The reference's light-grey greeting (`#BDBDBB`, 1.8:1) fails AA, so `muted` is
darker than the reference on purpose.

Feature-card color mapping (home): Check Message = peach, Check QR Code = powder,
Check Call = mint, Live Call Guard = lavender, Report Fraud = alert.

## Typography (`DsFont`, `DsType`)
**Inter Tight** (Latin; static 300/400/500/600, OFL, bundled in `assets/fonts/`) with
**Noto Sans Devanagari** as `fontFamilyFallback` for Hindi and Chhattisgarhi. Offline: no
`google_fonts`.

Why Inter Tight: the reference is a neo-grotesk set light and tightly tracked; Inter Tight is Inter
with tighter default spacing designed for large display sizes, it has true light weights, and it is
free (OFL). Plus Jakarta Sans is rounder and more geometric than the reference; Geist is close too,
but Inter Tight's built-in tight spacing matches the reference's display headings best. None of the
three has Devanagari, so a fallback is needed in every case, and Noto Sans Devanagari is already bundled.

| Style | Size / weight / tracking | Use |
|---|---|---|
| `display` | 44 / 300 / -1.6, line 1.02 | Screen title |
| `headline` | 30 / 300 / -0.9 | Big card titles (Report Fraud) |
| `cardTitle` | 22 / 400 / -0.5 | Card and panel titles |
| `title` | 18 / 500 / -0.2 | Brand name, list titles |
| `body` | 15 / 400, line 1.4 | Text |
| `label` | 15 / 500 | Buttons, chips |
| `greeting` | 14 / 400, muted | Small line above the title |
| `small` | 13 / 400, muted | Card descriptions |
| `number` | 48 / 300 / -2 | Scores |

## Shape, space, elevation
Radius (`DsRadius`): `card` 30 · `tile` 20 · `pill` 999. Spacing (`DsSpace`): 4 · 8 · 12 · 16 ·
20 (screen gutter) · 28 · 32 (section). Flat: elevation 0, no shadows; white panels get a 1 px `line`
border, pastel cards get none. Touch targets ≥ 48 × 48 (`kDsTouch`; Android guideline, above the
44 × 44 WCAG/iOS minimum).

## Motion (`DsMotion`)
Press: scale to 0.97 in 120 ms, ease-out cubic (`Pressable`). State changes (chip selection,
progress): 220 ms. Screen changes: fade-forward page transition. No splash ripples.

## Components (`lib/core/design/components.dart`)
- `PastelCard(color, onTap, child)` — flat rounded card; tappable cards use `Pressable`.
- `IconBadge(icon)` — 48 dp dark circle with a white icon (colors overridable for the alert card).
- `ArrowButton()` — 48 dp circular outline with ↗; decorative inside a card, a button with
  `onTap` + `semanticLabel` (also used for the bell).
- `PillChip(label, selected, onTap)` — soft pill; selected = brand fill.
- `ScreenHeader(leading, brand, actions, greeting, title)` — logo/brand row, actions on the right,
  muted greeting and large light title.
- `PrimaryButton(label, icon, filled)` — full-width pill; filled ink or outlined.
- `ProgressBar(value)` — 8 dp rounded bar on `track`.
- `Pressable` — press-scale wrapper with semantics.

## Accessibility
Every icon-only control has a `semanticLabel` (bell: "Notifications"; 1930: "Call 1930, cyber fraud
helpline"). Tappable cards expose one merged label (title + description). Selected language chip is
marked `selected`. Tests: `test/core/home_design_test.dart` (tap targets, labels, text contrast,
no overflow at 360 dp in en/hi/chh).

## Sources
- `design/reference-style.png` — style reference (provided in chat).
- `design/SPEC.md` — home content, labels and order.
- The layout sketch and the old app screenshot were not provided as files; placement follows
  SPEC.md's numbering.
