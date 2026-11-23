import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/components.dart';
import '../design/tokens.dart';
import '../providers.dart';
import '../strings.dart';

/// Language choice as design-system pill chips: EN · हिन्दी · छत्तीसगढ़ी.
/// The selected language is filled with the brand teal.
class LanguageSwitcher extends ConsumerWidget {
  /// Kept for existing callers; chips are always 44 dp tall (touch target).
  final bool compact;

  const LanguageSwitcher({super.key, this.compact = false});

  static const List<({String code, String label, String name})> languages = [
    (code: 'en', label: 'EN', name: 'English'),
    (code: 'hi', label: 'हिन्दी', name: 'Hindi'),
    (code: 'chh', label: 'छत्तीसगढ़ी', name: 'Chhattisgarhi'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeProvider);
    return Wrap(
      spacing: DsSpace.s,
      runSpacing: DsSpace.s,
      children: [
        for (final l in languages)
          PillChip(
            key: Key('lang_${l.code}'),
            label: l.label,
            selected: current == l.code,
            semanticLabel: l.name,
            onTap: current == l.code ? () {} : () => ref.read(localeProvider.notifier).setLocale(l.code),
          ),
      ],
    );
  }
}

/// Header action button that displays the active language and opens a modal
/// bottom sheet to choose between English, Hindi, and Chhattisgarhi.
class LanguageButton extends ConsumerWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeProvider);
    final currentLang = LanguageSwitcher.languages.firstWhere(
      (l) => l.code == current,
      orElse: () => LanguageSwitcher.languages.first,
    );
    final s = S.of(context);

    return Pressable(
      key: const Key('home_language_button'),
      semanticLabel: '${s.t('select_language')}: ${currentLang.name}',
      borderRadius: BorderRadius.circular(DsRadius.pill),
      onTap: () => showLanguageSheet(context, ref),
      child: Container(
        height: kDsTouch,
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.m),
        decoration: BoxDecoration(
          color: DsColors.surface,
          borderRadius: BorderRadius.circular(DsRadius.pill),
          border: Border.all(color: DsColors.line, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.translate_rounded, size: 18, color: DsColors.ink),
            const SizedBox(width: DsSpace.xs),
            Text(currentLang.label, style: DsType.label),
            const SizedBox(width: DsSpace.xxs),
            const Icon(Icons.arrow_drop_down_rounded, size: 20, color: DsColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Opens the modal sheet for language selection.
void showLanguageSheet(BuildContext context, WidgetRef ref) {
  final current = ref.read(localeProvider);
  final s = S.of(context);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: DsColors.page,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DsRadius.card)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(DsSpace.xl, DsSpace.l, DsSpace.xl, DsSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: DsColors.line,
                  borderRadius: BorderRadius.circular(DsRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: DsSpace.l),
            Text(s.t('select_language'), style: DsType.section),
            const SizedBox(height: DsSpace.m),
            for (final l in LanguageSwitcher.languages) ...[
              _LanguageTile(
                key: Key('lang_${l.code}'),
                code: l.code,
                label: l.label,
                name: l.name,
                selected: current == l.code,
                onTap: () {
                  ref.read(localeProvider.notifier).setLocale(l.code);
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: DsSpace.s),
            ],
          ],
        ),
      ),
    ),
  );
}

class _LanguageTile extends StatelessWidget {
  final String code;
  final String label;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageTile({
    super.key,
    required this.code,
    required this.label,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: name,
      borderRadius: BorderRadius.circular(DsRadius.tile),
      child: Container(
        constraints: const BoxConstraints(minHeight: kDsTouch),
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.l, vertical: DsSpace.m),
        decoration: BoxDecoration(
          color: selected ? DsColors.powder : DsColors.surface,
          borderRadius: BorderRadius.circular(DsRadius.tile),
          border: Border.all(
            color: selected ? DsColors.brand : DsColors.line,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? DsColors.brand : DsColors.track,
              ),
              child: Center(
                child: Text(
                  label,
                  style: DsType.caption.copyWith(
                    color: selected ? DsColors.onDark : DsColors.ink,
                  ),
                ),
              ),
            ),
            const SizedBox(width: DsSpace.m),
            Expanded(
              child: Text(name, style: DsType.title),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? DsColors.brand : DsColors.muted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
