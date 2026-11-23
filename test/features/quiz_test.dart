import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scam_rakshak/features/lessons/lesson_models.dart';
import 'package:scam_rakshak/features/quiz/quiz_models.dart';
import 'package:scam_rakshak/features/quiz/quiz_screen.dart';

List<QuizQuestion> _loadAll() => [
  for (final id in kLessonIds)
    for (final q in (jsonDecode(File('assets/quiz/$id.json').readAsStringSync())['questions'] as List))
      QuizQuestion.fromJson(id, Map<String, dynamic>.from(q as Map)),
];

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Pumps frames and lets real asset I/O complete in between (routes build lazily, so loads start late).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  }
  await tester.pumpAndSettle();
}

void main() {
  late List<QuizQuestion> all;
  setUpAll(() => all = _loadAll());

  group('quiz content', () {
    test('every lesson has a quiz with valid, fully translated questions', () {
      for (final id in kLessonIds) {
        final qs = all.where((q) => q.topic == id).toList();
        expect(qs.length, greaterThanOrEqualTo(3), reason: id);
        for (final q in qs) {
          final n = q.optionsFor('en').length;
          expect(n, greaterThanOrEqualTo(2));
          expect(q.answer, inInclusiveRange(0, n - 1));
          for (final lang in ['en', 'hi', 'chh']) {
            expect(q.q[lang], isNotEmpty, reason: '$id q $lang');
            expect(q.explain[lang], isNotEmpty, reason: '$id explain $lang');
            expect(q.options[lang]?.length, n, reason: '$id options $lang');
          }
        }
      }
    });
  });

  group('QuizSession', () {
    test('quick mode: 10 distinct random questions; same seed gives same order', () {
      final a = QuizSession.start(all, mode: QuizMode.quick, random: Random(3));
      final b = QuizSession.start(all, mode: QuizMode.quick, random: Random(3));
      expect(a.length, QuizSession.quickCount);
      expect(a.questions.toSet().length, a.length);
      expect(a.questions, b.questions);
    });

    test('full mode has every question; topic mode only that topic', () {
      expect(QuizSession.start(all, mode: QuizMode.full, random: Random(1)).questions.toSet(), all.toSet());
      final t = QuizSession.start(all, mode: QuizMode.topic, topic: 'loan_app', random: Random(1));
      expect(t.length, all.where((q) => q.topic == 'loan_app').length);
      expect(t.questions.every((q) => q.topic == 'loan_app'), isTrue);
      expect(QuizSession.start(all, mode: QuizMode.topic, topic: 'nope').isEmpty, isTrue);
    });

    test('scoring, one answer per question, and end of quiz', () {
      final s = QuizSession.start(all, mode: QuizMode.topic, topic: 'otp', random: Random(2));
      expect(() => s.next(), throwsStateError);

      expect(s.answer(s.current.answer), isTrue);
      expect(s.answer((s.current.answer + 1) % 3), isTrue, reason: 'second tap is ignored');
      expect(s.correct, 1);
      expect(s.next(), isTrue);

      final wrong = (s.current.answer + 1) % s.current.optionsFor('en').length;
      expect(s.answer(wrong), isFalse);
      expect(s.lastAnswerCorrect, isFalse);
      while (s.next()) {
        s.answer(s.current.answer);
      }
      expect(s.isLast, isTrue);
      expect(s.correct, s.length - 1);
      expect(s.score.perTopic['otp'], [s.length - 1, s.length]);
      expect(s.score.score, ((s.length - 1) * 100 / s.length).round());
      expect(s.score.weakestTopic, 'otp');
    });
  });

  group('QuizScreen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      rootBundle.clear(); // cached asset futures from an earlier test's fake-async zone never complete
    });

    testWidgets('modes are offered on the intro screen', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(const MaterialApp(home: QuizScreen()));
      await _settle(tester);
      expect(find.byKey(const Key('quiz_mode_quick')), findsOneWidget);
      expect(find.byKey(const Key('quiz_mode_full')), findsOneWidget);
      for (final id in kLessonIds) {
        expect(find.byKey(Key('quiz_topic_$id')), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('quiz_mode_quick')));
      await tester.pumpAndSettle();
      expect(find.text('Question 1 / ${QuizSession.quickCount}'), findsOneWidget);
    });

    testWidgets('answer, feedback with explanation, score, result, retry and change quiz', (tester) async {
      _tallView(tester);
      const seed = 7;
      // Same questions and seed as the screen, to know the right answers.
      final expected = QuizSession.start(all, mode: QuizMode.topic, topic: 'lottery_prize', random: Random(seed));
      final n = expected.length;

      await tester.pumpWidget(
        MaterialApp(
          home: QuizScreen(topic: 'lottery_prize', random: Random(seed)),
        ),
      );
      await _settle(tester);
      expect(find.text('Question 1 / $n'), findsOneWidget);

      // Q1: right answer.
      var q = expected.questions[0];
      await tester.tap(find.byKey(Key('quiz_option_${q.answer}')));
      await tester.pumpAndSettle();
      expect(find.text('Correct!'), findsOneWidget);
      expect(find.text(q.explain['en']!), findsOneWidget);
      expect(find.text('Score: 1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('quiz_next')));
      await tester.pumpAndSettle();

      // Q2: wrong answer shows the correct one.
      q = expected.questions[1];
      final wrong = (q.answer + 1) % q.optionsFor('en').length;
      await tester.tap(find.byKey(Key('quiz_option_$wrong')));
      await tester.pumpAndSettle();
      expect(find.text('Wrong'), findsOneWidget);
      expect(find.text('Correct answer: ${q.optionsFor('en')[q.answer]}'), findsOneWidget);
      expect(find.text(q.explain['en']!), findsOneWidget);
      expect(find.text('Score: 1'), findsOneWidget);

      // Remaining: right answers.
      for (var i = 2; i < n; i++) {
        await tester.tap(find.byKey(const Key('quiz_next')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('quiz_option_${expected.questions[i].answer}')));
        await tester.pumpAndSettle();
      }
      expect(find.text('See my score'), findsOneWidget);
      await tester.tap(find.byKey(const Key('quiz_next')));
      await _settle(tester);

      final pct = ((n - 1) * 100 / n).round();
      expect(find.byKey(const Key('quiz_result')), findsOneWidget);
      expect(find.text('$pct%'), findsOneWidget);
      expect(find.text('${n - 1} / $n correct'), findsOneWidget);
      expect(find.byKey(const Key('quiz_level_feedback')), findsOneWidget);
      expect(find.byKey(const Key('quiz_revise')), findsOneWidget);
      expect((await SharedPreferences.getInstance()).getInt(QuizStore.keyScore), pct);

      // Retry reshuffles, so find each question by the text on screen.
      await tester.tap(find.byKey(const Key('quiz_retry')));
      await tester.pumpAndSettle();
      expect(find.text('Question 1 / $n'), findsOneWidget);
      expect(find.text('Score: 0'), findsOneWidget);

      Future<void> answerShownCorrectly() async {
        final shown = expected.questions.singleWhere((q) => find.text(q.q['en']!).evaluate().isNotEmpty);
        await tester.tap(find.byKey(Key('quiz_option_${shown.answer}')));
        await tester.pumpAndSettle();
      }

      await answerShownCorrectly();
      for (var i = 1; i < n; i++) {
        await tester.tap(find.byKey(const Key('quiz_next')));
        await tester.pumpAndSettle();
        await answerShownCorrectly();
      }
      expect(find.text('Score: $n'), findsOneWidget);
      await tester.tap(find.byKey(const Key('quiz_next')));
      await _settle(tester);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('All topics perfect! You are a Champion.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('quiz_change')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quiz_mode_quick')), findsOneWidget);
      expect(find.textContaining('Your last score: 100 / 100'), findsOneWidget);
    });
  });
}
