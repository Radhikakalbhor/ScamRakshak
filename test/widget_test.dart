import 'package:flutter/widgets.dart' show Key, Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scam_rakshak/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('ScamRakshak launches to the home screen', (tester) async {
    tester.view.physicalSize = const Size(1170, 7500); // 390 x 2500 dp: whole home without scrolling
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: ScamRakshakApp()));
    await tester.pumpAndSettle();

    expect(find.text('ScamRakshak'), findsOneWidget);
    for (final title in [
      'Check Message',
      'Check Call',
      'Report Fraud',
      'Open lessons',
      'Take a quiz',
      'Scam Trends',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('Language switcher changes the UI language', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ScamRakshakApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home_language_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('हिन्दी'));
    await tester.pumpAndSettle();

    expect(find.text('स्कैम रक्षक'), findsOneWidget);
    expect(find.text('Check Message'), findsNothing);
  });
}
