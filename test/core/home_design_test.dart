import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scam_rakshak/core/design/tokens.dart';
import 'package:scam_rakshak/core/screens/home_screen.dart';
import 'package:scam_rakshak/core/strings.dart';
import 'package:scam_rakshak/core/theme.dart';

Future<void> _pump(WidgetTester tester, {String lang = 'en', double width = 390}) async {
  tester.view.physicalSize = Size(width * 3, 2600 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: [AppLocalizationsDelegate(lang)],
      home: const HomeScreen(),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('sections follow SPEC.md order with the exact copy', (tester) async {
    await _pump(tester);
    double y(Finder f) => tester.getTopLeft(f).dy;
    final order = [
      find.text('ScamRakshak'),
      find.text('Language / भाषा'),
      find.text('Report Fraud'),
      find.text('Check Message'),
      find.text('Check Call'),
      find.text('Digital Financial Literacy Score'),
      find.text('Scam Trends'),
    ];
    for (var i = 1; i < order.length; i++) {
      expect(y(order[i]), greaterThan(y(order[i - 1])), reason: 'section $i out of order');
    }
    // Check QR Code beside Check Message; Live Call Guard beside Check Call.
    expect(y(find.text('Check QR Code')), y(find.text('Check Message')));
    expect(tester.getTopLeft(find.text('Check QR Code')).dx, greaterThan(tester.getTopLeft(find.text('Check Message')).dx));
    expect(y(find.text('Live Call Guard')), y(find.text('Check Call')));
    for (final copy in [
      'EN',
      'हिन्दी',
      'छत्तीसगढ़ी',
      '1930',
      'Register incident & alert community',
      'Detect SMS & WhatsApp fraud',
      'Spot fake payment QR codes',
      'Analyze suspicious call transcripts',
      'From your quiz answers and the lessons you finished. Stays on this phone.',
      'Read a lesson or take the quiz to get your score.',
      'Next: read the lesson "Keep your OTP secret".',
      'Open lessons',
      'Take a quiz',
    ]) {
      expect(find.text(copy), findsOneWidget, reason: copy);
    }
    expect(find.text('0'), findsOneWidget);
    expect(find.text(' /100'), findsOneWidget);
  });

  testWidgets('accessible: labelled icon buttons, 48 dp touch targets, selected language marked', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Call 1930')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Report Fraud')), findsWidgets);
    for (final k in ['home_notifications', 'home_call_1930', 'lang_en', 'lang_hi', 'lang_chh', 'home_open_lessons', 'home_take_quiz']) {
      final size = tester.getSize(find.byKey(Key(k)));
      expect(size.height, greaterThanOrEqualTo(kDsTouch), reason: k);
      expect(size.width, greaterThanOrEqualTo(kDsTouch), reason: k);
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  for (final lang in S.supportedLanguages) {
    testWidgets('no overflow on a 360 dp phone ($lang); Devanagari uses the bundled fallback', (tester) async {
      await _pump(tester, lang: lang, width: 360);
      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(find.text(S(lang).t('home_title')));
      expect(title.style?.fontFamilyFallback, contains('Noto Sans Devanagari'));
    });
  }

  test('design system: tokens only in the design layer and the home screen', () {
    for (final path in ['lib/core/screens/home_screen.dart', 'lib/core/design/components.dart']) {
      final src = File(path).readAsStringSync();
      expect(RegExp(r'Color\(0x').hasMatch(src), isFalse, reason: '$path: raw color, use DsColors');
      expect(RegExp(r'fontFamily:').hasMatch(src), isFalse, reason: '$path: use DsType / DsFont');
      expect(RegExp(r'BorderRadius\.circular\(\d').hasMatch(src), isFalse, reason: '$path: use DsRadius');
    }
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: ${DsFont.family}'));
    for (final w in ['Light', 'Regular', 'Medium', 'SemiBold']) {
      expect(File('assets/fonts/InterTight-$w.ttf').lengthSync(), greaterThan(40000));
    }
    expect(File('design/DESIGN_SYSTEM.md').existsSync(), isTrue);
    expect(File('CLAUDE.md').readAsStringSync().trimLeft(), startsWith('All UI must follow /design/DESIGN_SYSTEM.md'));
  });
}
