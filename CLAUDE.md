All UI must follow /design/DESIGN_SYSTEM.md and use the shared components. Never introduce new colors, radii or fonts outside the tokens.

- Tokens: `lib/core/design/tokens.dart` (DsColors, DsRadius, DsSpace, DsType, DsFont, DsMotion).
- Components: `lib/core/design/components.dart` (PastelCard, IconBadge, ArrowButton, PillChip, ScreenHeader, PrimaryButton, ProgressBar, Pressable).
- Global theme: `lib/core/theme.dart` (built only from the tokens).
- Project rules, folder ownership and contracts: see AGENTS.md.
