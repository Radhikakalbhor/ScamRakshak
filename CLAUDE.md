All UI must use the shared components and tokens. Never hardcode colors, radii, fonts, font weights or spacing.

- Design system: `/design/DESIGN_SYSTEM.md`.
- Tokens: `lib/core/design/tokens.dart` (DsColors, DsRadius, DsSpace, DsType, DsWeight, DsFont, DsMotion, kDsTouch).
- Components: `lib/core/design/components.dart` (PastelCard, SurfacePanel, FeatureCard, PairRow, IconBadge, ArrowButton, PillChip, ScreenHeader, PrimaryButton, ProgressBar, Pressable, AppTextField, DsListTile, DsTabs, VerdictBanner, showDsDialog, showDsToast, EmptyState, LoadingState).
- Global theme: `lib/core/theme.dart` (built only from the tokens).
- Project rules, folder ownership and contracts: see AGENTS.md.
