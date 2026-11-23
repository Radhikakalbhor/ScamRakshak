import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scam_rakshak/core/strings.dart';
import 'package:scam_rakshak/core/theme.dart';
import 'package:scam_rakshak/features/dashboard/detection_history.dart';
import 'package:scam_rakshak/features/dashboard/trends_screen.dart';
import 'package:scam_rakshak/features/lessons/lesson_detail_screen.dart';
import 'package:scam_rakshak/features/lessons/lesson_list_screen.dart';
import 'package:scam_rakshak/features/quiz/quiz_screen.dart';

/// Builds [f] in the lazy list (scrolling down if needed), then scrolls it fully into view.
Future<void> _reveal(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) await tester.scrollUntilVisible(f, 150);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

/// Small-phone layout check (360 x 740 dp) in every language: any overflow fails the test.
void main() {
  final now = DateTime(2026, 11, 23, 12);

  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({
      DetectionHistory.prefKey: jsonEncode([
        for (final c in ['fake_kyc', 'digital_arrest', 'courier_customs', 'loan_threat', 'phishing_link', 'other'])
          DetectionRecord(kind: 'call', verdict: 'scam', category: c, time: now).toJson(),
        DetectionRecord(kind: 'message', verdict: 'safe', category: '', score: 0.02, time: now).toJson(),
        DetectionRecord(
          kind: 'call',
          verdict: 'suspicious',
          category: 'lottery_prize',
          sample: true,
          time: now,
        ).toJson(),
      ]),
    });
  });

  Future<void> pumpPhone(WidgetTester tester, Widget home, String lang) async {
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: [AppLocalizationsDelegate(lang)],
          home: home,
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    }
    await tester.pumpAndSettle();
  }

  for (final lang in S.supportedLanguages) {
    testWidgets('lesson list and detail fit a small phone ($lang)', (tester) async {
      await pumpPhone(tester, const LessonListScreen(), lang);
      expect(find.byType(LessonListScreen), findsOneWidget);
      await pumpPhone(tester, const LessonDetailScreen(lessonId: 'digital_arrest'), lang);
      await tester.scrollUntilVisible(find.byKey(const Key('lesson_take_quiz')), 300);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lesson_take_quiz')), findsOneWidget);
    });

    testWidgets('quiz intro, question and result fit a small phone ($lang)', (tester) async {
      await pumpPhone(tester, QuizScreen(random: Random(1)), lang);
      await tester.scrollUntilVisible(find.byKey(const Key('quiz_mode_quick')), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quiz_mode_quick')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        // Each new question must open at the top.
        expect(find.byKey(const Key('quiz_counter')), findsOneWidget, reason: 'question ${i + 1} not at top');
        expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, 0);
        await _reveal(tester, find.byKey(const Key('quiz_option_0')));
        await tester.tap(find.byKey(const Key('quiz_option_0')));
        await tester.pumpAndSettle();
        await _reveal(tester, find.byKey(const Key('quiz_next')));
        await tester.tap(find.byKey(const Key('quiz_next')));
        for (var k = 0; k < 3; k++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('quiz_result')), findsOneWidget);
    });

    testWidgets('scam trends with data fit a small phone ($lang)', (tester) async {
      await pumpPhone(tester, TrendsScreen(clock: () => now), lang);
      expect(find.byKey(const Key('trends_tile_scams')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('trends_server')), 300);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('trends_server')), findsOneWidget);
    });
  }
}
