import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scam_rakshak/core/api_client.dart';
import 'package:scam_rakshak/core/providers.dart';
import 'package:scam_rakshak/core/theme.dart';
import 'package:scam_rakshak/engine/scam_classifier.dart';
import 'package:scam_rakshak/features/lessons/lesson_list_screen.dart';
import 'package:scam_rakshak/features/lessons/lesson_models.dart';
import 'package:scam_rakshak/features/message_detector/message_detector_screen.dart';
import 'package:scam_rakshak/features/quiz/literacy_score.dart';
import 'package:scam_rakshak/features/quiz/quiz_models.dart';
import 'package:scam_rakshak/features/quiz/quiz_screen.dart';

/// Any attempt to open an HTTP connection is recorded and fails.
class _NoNetwork extends HttpOverrides {
  final attempts = <String>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts.add('HttpClient');
    throw const SocketException('network used in an offline feature');
  }
}

/// Records every backend call.
class _SpyApi extends ApiClient {
  final calls = <String>[];
  @override
  Future<Map> transcribe(File audio) async => throw StateError(calls.addAndName('transcribe'));
  @override
  Future<Map> transcribeChunk(File audio, {String? lang}) async => throw StateError(calls.addAndName('chunk'));
  @override
  Future<Map> transcribeRecording(File audio, {Duration timeout = const Duration(minutes: 5)}) async =>
      throw StateError(calls.addAndName('recording'));
  @override
  Future<bool> isReachable({Duration timeout = const Duration(seconds: 4)}) async {
    calls.add('health');
    return false;
  }

  @override
  Future<void> postReportAt(String type, String district, String ts) async => calls.add('report');
  @override
  Future<List<Map>> getTrends() async => throw StateError(calls.addAndName('trends'));
  @override
  Future<Map> getTrendSummary() async => throw StateError(calls.addAndName('summary'));
  @override
  Future<List<Map>> getAlerts() async => throw StateError(calls.addAndName('alerts'));
  @override
  Future<void> postFingerprint(String fp, String category) async => calls.add('fingerprint');
}

extension on List<String> {
  String addAndName(String s) {
    add(s);
    return s;
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  }
  await tester.pumpAndSettle();
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    rootBundle.clear();
  });

  group('LiteracyScore', () {
    test('nothing done is 0 with no data; everything perfect is 100 with no weak topic', () {
      const empty = LiteracyScore({}, {});
      expect(empty.score, 0);
      expect(empty.hasData, isFalse);
      expect(empty.levelKey, 'level_beginner');
      expect(empty.weakestTopic, kLessonIds.first);
      expect(empty.recommendation, 'lesson');

      final perfect = LiteracyScore({for (final t in kLessonIds) t: [3, 3]}, kLessonIds.toSet());
      expect(perfect.score, 100);
      expect(perfect.levelKey, 'level_champion');
      expect(perfect.weakestTopic, isNull);
      expect(perfect.recommendation, isNull);
    });

    test('quiz is 60 and lessons 40 points; untried topics count as 0; weakest topic drives the advice', () {
      // All 11 quizzes perfect, no lessons -> 60.
      expect(LiteracyScore({for (final t in kLessonIds) t: [5, 5]}, {}).score, 60);
      // All lessons, no quiz -> 40.
      expect(LiteracyScore({}, kLessonIds.toSet()).score, 40);
      // One perfect topic quiz + its lesson: 60/11 + 40/11 = 9.09 -> 9.
      final one = LiteracyScore({'otp': [5, 5]}, {'otp'});
      expect(one.score, 9);
      expect(one.weakestTopic, 'upi_pin');
      expect(one.recommendation, 'lesson');
      // Lesson done but quiz weak -> retake the quiz.
      final weakQuiz = LiteracyScore(
          {for (final t in kLessonIds) t: t == 'qr' ? [1, 5] : [5, 5]}, kLessonIds.toSet());
      expect(weakQuiz.weakestTopic, 'qr');
      expect(weakQuiz.recommendation, 'quiz');
      expect(weakQuiz.quizAccuracy, closeTo((10 * 5 + 1) / 55, 1e-9));
    });

    test('store keeps the latest result per topic, persists, and starts from the old quiz result', () async {
      SharedPreferences.setMockInitialValues({
        QuizStore.keyDetail: jsonEncode({
          'score': 50,
          'topics': {
            'otp': [1, 2],
          },
        }),
      });
      var s = await LiteracyStore.load();
      expect(s.quiz, {
        'otp': [1, 2],
      });

      await LiteracyStore.recordQuiz(const QuizScore({
        'otp': [2, 2],
        'qr': [1, 3],
      }));
      await LessonProgress.markDone('qr');
      s = await LiteracyStore.load();
      expect(s.quiz['otp'], [2, 2]);
      expect(s.quiz['qr'], [1, 3]);
      expect(s.lessonsDone, {'qr'});
      expect((await SharedPreferences.getInstance()).getString(LiteracyStore.key), isNotNull);
    });
  });

  group('home literacy card', () {
    testWidgets('shows score, level and recommendation, and updates after a quiz', (tester) async {
      _tall(tester);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: LiteracyScoreCard()))));
      await _settle(tester);
      expect(tester.widget<Text>(find.byKey(const Key('dfl_score'))).data, '0');
      expect(find.byKey(const Key('dfl_empty')), findsOneWidget);
      expect(find.textContaining('Next: read the lesson'), findsOneWidget);

      await tester.runAsync(() async {
        await LiteracyStore.recordQuiz(QuizScore({for (final t in kLessonIds) t: [4, 5]}));
        for (final t in kLessonIds) {
          await LessonProgress.markDone(t);
        }
      });
      await _settle(tester);
      // quiz 0.8 * 60 = 48, lessons 40 -> 88 (Safe)
      expect(tester.widget<Text>(find.byKey(const Key('dfl_score'))).data, '88');
      expect(find.text('Safe'), findsOneWidget);
      expect(find.textContaining('quiz again'), findsOneWidget);
      expect(find.textContaining('11/11 lessons done'), findsOneWidget);
    });
  });

  group('offline features make zero network calls', () {
    late _NoNetwork net;
    late _SpyApi api;
    late ScamClassifier clf;
    HttpOverrides? old;

    setUpAll(() {
      clf = ScamClassifier.fromJson(
          jsonDecode(File('assets/models/scam_model.json').readAsStringSync()) as Map<String, dynamic>);
    });
    setUp(() {
      net = _NoNetwork();
      api = _SpyApi();
    });

    Future<void> offline(WidgetTester tester, Widget home, Future<void> Function() drive) async {
      _tall(tester);
      old = HttpOverrides.current;
      HttpOverrides.global = net;
      addTearDown(() => HttpOverrides.global = old);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          scamClassifierProvider.overrideWith((ref) async => clf),
        ],
        child: MaterialApp(home: home),
      ));
      await _settle(tester);
      await drive();
      expect(net.attempts, isEmpty);
      expect(api.calls, isEmpty);
    }

    testWidgets('message detector', (tester) async {
      await offline(tester, const MessageDetectorScreen(), () async {
        await tester.enterText(find.byKey(const Key('msg_input')),
            'Your KYC is pending, share the OTP now or the account is blocked today http://x.in');
        await tester.tap(find.byKey(const Key('msg_check')));
        await _settle(tester);
        expect(find.byKey(const Key('msg_verdict')), findsOneWidget);
      });
    });

    testWidgets('lessons (list, open, mark done)', (tester) async {
      await offline(tester, const LessonListScreen(), () async {
        await tester.tap(find.byKey(const Key('lesson_tile_otp')));
        await _settle(tester);
        await tester.ensureVisible(find.byKey(const Key('lesson_mark_done')));
        await tester.tap(find.byKey(const Key('lesson_mark_done')));
        await _settle(tester);
        expect(find.byKey(const Key('lesson_marked')), findsOneWidget);
      });
    });

    testWidgets('quiz (a whole topic) and the literacy score', (tester) async {
      await offline(tester, QuizScreen(topic: 'otp', random: Random(1)), () async {
        for (var i = 0; i < 20; i++) {
          if (find.byKey(const Key('quiz_option_0')).evaluate().isEmpty) break;
          await tester.tap(find.byKey(const Key('quiz_option_0')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('quiz_next')));
          await _settle(tester);
        }
        expect((await tester.runAsync(LiteracyStore.load))!.topicsTried, 1);
      });
    });

    test('fonts are bundled: Noto Sans Devanagari asset, no google_fonts', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('family: ${AppTheme.fontFamily}'));
      expect(pubspec, contains('assets/fonts/NotoSansDevanagari-Regular.ttf'));
      expect(File('assets/fonts/NotoSansDevanagari-Regular.ttf').lengthSync(), greaterThan(100000));
      expect(pubspec.contains('google_fonts'), isFalse);
      expect(File('pubspec.lock').readAsStringSync().contains('google_fonts'), isFalse);
    });
  });
}
