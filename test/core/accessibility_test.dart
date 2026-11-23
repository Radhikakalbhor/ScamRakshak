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

/// Phase 3 audit: 48 dp tap targets, labelled tap targets and AA text contrast
/// on the migrated screens, in English, Hindi and Chhattisgarhi.
void main() {
  final now = DateTime(2026, 11, 23, 12);

  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({
      DetectionHistory.prefKey: jsonEncode([
        DetectionRecord(kind: 'call', verdict: 'scam', category: 'fake_kyc', time: now).toJson(),
        DetectionRecord(kind: 'message', verdict: 'safe', category: '', score: 0.02, time: now).toJson(),
        DetectionRecord(kind: 'call', verdict: 'suspicious', category: 'lottery_prize', time: now).toJson(),
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

  Future<void> audit(WidgetTester tester) async {
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  }

  final screens = <String, Widget Function()>{
    'lesson list': () => const LessonListScreen(),
    'lesson detail': () => const LessonDetailScreen(lessonId: 'digital_arrest'),
    'quiz intro': () => QuizScreen(random: Random(1)),
    'scam trends': () => TrendsScreen(clock: () => now),
  };

  for (final lang in S.supportedLanguages) {
    for (final e in screens.entries) {
      testWidgets('${e.key}: tap targets and contrast ($lang)', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpPhone(tester, e.value(), lang);
        await audit(tester);
        handle.dispose();
      });
    }

    testWidgets('quiz question after answering: tap targets and contrast ($lang)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPhone(tester, QuizScreen(random: Random(1)), lang);
      await tester.scrollUntilVisible(find.byKey(const Key('quiz_mode_quick')), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quiz_mode_quick')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quiz_option_0')));
      await tester.pumpAndSettle();
      await audit(tester);
      handle.dispose();
    });
  }
}
