import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/components.dart';
import '../design/tokens.dart';
import '../providers.dart';

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
