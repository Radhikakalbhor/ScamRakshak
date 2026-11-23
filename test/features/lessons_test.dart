import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scam_rakshak/features/lessons/lesson_list_screen.dart';
import 'package:scam_rakshak/features/lessons/lesson_models.dart';

const _langs = ['en', 'hi', 'chh'];

Map<String, dynamic> _json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 4200);
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
  group('lesson content', () {
    test('covers the required scam categories', () {
      expect(
        kLessonIds,
        containsAll([
          'upi_pin',
          'otp',
          'fake_kyc',
          'digital_arrest',
          'lottery_prize',
          'loan_app',
          'phishing',
          'remote_access',
          'courier_customs',
        ]),
      );
    });

    for (final id in kLessonIds) {
      test('$id: complete in en/hi/chh', () {
        final l = Lesson.fromJson(_json('assets/lessons/$id.json'));
        expect(l.id, id);
        expect(kLessonCategories, contains(l.category));
        for (final lang in _langs) {
          expect(l.title[lang], isNotEmpty, reason: 'title $lang');
          expect(l.summary[lang], isNotEmpty, reason: 'summary $lang');
          expect(l.example[lang], isNotEmpty, reason: 'example $lang');
          for (final m in [...l.signs, ...l.steps]) {
            expect(m[lang], isNotEmpty, reason: 'sign/step $lang');
          }
          for (final c in l.cards) {
            expect(c.text[lang], isNotEmpty, reason: 'card $lang');
          }
        }
        expect(l.signs.length, greaterThanOrEqualTo(3));
        expect(l.steps.length, greaterThanOrEqualTo(3));
        expect(l.cards.length, greaterThanOrEqualTo(4));
        for (final c in l.cards) {
          expect(lessonCardIcon(c.icon), isNot(Icons.lightbulb_rounded), reason: 'unknown icon ${c.icon}');
        }
      });
    }

    test('old schema without optional fields still parses', () {
      final l = Lesson.fromJson({
        'id': 'x',
        'title': {'en': 'X'},
        'cards': [
          {
            'icon': 'sms',
            'text': {'en': 'a'},
          },
        ],
      });
      expect(l.summary, isEmpty);
      expect(l.signs, isEmpty);
      expect(l.category, 'payments');
    });

    test('search matches title or summary in the current language and English', () {
      final l = Lesson.fromJson(_json('assets/lessons/digital_arrest.json'));
      expect(l.matches('police', 'en'), isTrue);
      expect(l.matches('POLICE', 'hi'), isTrue); // English fallback
      expect(l.matches('पुलिस', 'hi'), isTrue);
      expect(l.matches('lottery', 'en'), isFalse);
      expect(l.matches('  ', 'en'), isTrue);
    });
  });

  group('LessonListScreen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      rootBundle.clear(); // cached asset futures from an earlier test's fake-async zone never complete
    });

    testWidgets('shows all lessons with progress, search and filters', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(const MaterialApp(home: LessonListScreen()));
      await _settle(tester);

      for (final id in kLessonIds) {
        expect(find.byKey(Key('lesson_tile_$id')), findsOneWidget, reason: id);
      }
      expect(find.text('0 / ${kLessonIds.length} lessons done'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('lessons_search')), 'police');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lesson_tile_digital_arrest')), findsOneWidget);
      expect(find.byKey(const Key('lesson_tile_otp')), findsNothing);

      await tester.enterText(find.byKey(const Key('lessons_search')), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('No lesson matches your search.'), findsOneWidget);
      await tester.tap(find.text('Show all lessons'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lesson_tile_otp')), findsOneWidget);

      await tester.tap(find.byKey(const Key('lessons_filter_calls')));
      await tester.pumpAndSettle();
      for (final id in kLessonIds) {
        final l = Lesson.fromJson(_json('assets/lessons/$id.json'));
        expect(find.byKey(Key('lesson_tile_$id')), l.category == 'calls' ? findsOneWidget : findsNothing, reason: id);
      }
    });

    testWidgets('open a lesson, see its sections, mark it learned, progress updates', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(const MaterialApp(home: LessonListScreen()));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('lesson_tile_fake_kyc')));
      await _settle(tester);
      expect(find.byKey(const Key('lesson_example')), findsOneWidget);
      expect(find.byKey(const Key('lesson_signs')), findsOneWidget);
      expect(find.byKey(const Key('lesson_steps')), findsOneWidget);
      expect(find.text('Warning signs'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lesson_mark_done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lesson_marked')), findsOneWidget);

      await tester.pageBack();
      await _settle(tester);
      expect(find.text('1 / ${kLessonIds.length} lessons done'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('lessons_filter_todo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lessons_filter_todo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lesson_tile_fake_kyc')), findsNothing);
      expect(find.byKey(const Key('lesson_tile_otp')), findsOneWidget);
    });

    testWidgets('finishing the picture cards also completes the lesson', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(const MaterialApp(home: LessonListScreen()));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('lesson_tile_phishing')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('lesson_open_cards')));
      await _settle(tester);

      final n = Lesson.fromJson(_json('assets/lessons/phishing.json')).cards.length;
      for (var i = 0; i < n - 1; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Lesson complete! Well done.'), findsOneWidget);
      await tester.tap(find.text('Finish'));
      await _settle(tester);

      expect(find.byKey(const Key('lesson_marked')), findsOneWidget);
      expect(await LessonProgress.completed(), {'phishing'});
    });
  });
}
