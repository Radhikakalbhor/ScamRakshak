import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_design_tokens.dart';

/// CLAUDE.md: never hardcode colors, radii, fonts, font weights or spacing.
/// The same check runs from the command line: `dart run tool/check_design_tokens.dart`.
void main() {
  test('lib/ has no hard-coded colours, fonts, weights, radii or spacing', () {
    final found = checkDesignTokens();
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test('the checker catches each kind of hard-coded value', () {
    bool flags(String line) => designRules.any((r) => r.pattern.hasMatch(line));
    expect(flags('color: Color(0xFF123456),'), isTrue);
    expect(flags('color: Colors.red,'), isTrue);
    expect(flags('fontWeight: FontWeight.bold,'), isTrue);
    expect(flags("fontFamily: 'Roboto',"), isTrue);
    expect(flags('style: DsType.body.copyWith(fontSize: 16),'), isTrue);
    expect(flags('borderRadius: BorderRadius.circular(12),'), isTrue);
    expect(flags('padding: const EdgeInsets.all(16),'), isTrue);
    expect(flags('color: AppTheme.errorRed,'), isTrue);
    // Token usages pass.
    expect(flags('color: DsColors.alert, borderRadius: BorderRadius.circular(DsRadius.tile),'), isFalse);
    expect(flags('padding: const EdgeInsets.fromLTRB(DsSpace.l, DsSpace.s, DsSpace.l, 0),'), isFalse);
    expect(flags('color: Colors.transparent,'), isFalse);
    expect(flags('theme: AppTheme.lightTheme,'), isFalse);
  });
}
