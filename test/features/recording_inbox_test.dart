import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scam_rakshak/core/api_client.dart';
import 'package:scam_rakshak/core/providers.dart';
import 'package:scam_rakshak/engine/call_analyzer.dart';
import 'package:scam_rakshak/engine/live_call_analyzer.dart';
import 'package:scam_rakshak/features/call_detector/auto_analyze_core.dart';
import 'package:scam_rakshak/features/call_detector/auto_analyze_screen.dart';
import 'package:scam_rakshak/features/call_detector/auto_analyze_service.dart';
import 'package:scam_rakshak/features/call_detector/call_timeline.dart';
import 'package:scam_rakshak/features/call_detector/recording_result_screen.dart';
import 'package:scam_rakshak/features/live_call/recording_inbox.dart';

Map<String, dynamic> _json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

final _timeline = CallTimeline(
  CallAnalyzer.fromJson(_json('assets/rules/call_rules.json')),
  LiveCallAnalyzer.fromJson(_json('assets/rules/call_rules.json')),
);

CallTimelineResult _analyze(String sample) =>
    _timeline.analyze(File('assets/samples/live/$sample.txt').readAsStringSync());

class _Api extends ApiClient {
  @override
  Future<Map> transcribeRecording(File audio, {Duration timeout = const Duration(minutes: 5)}) async =>
      throw const ApiOfflineException('down');
}

class _Notifier implements AutoAnalyzeNotifier {
  @override
  Future<void> showVerdict(StoredRecordingResult r) async {}
  @override
  Future<void> showOffline(String path) async {}
  @override
  Future<void> cancelOffline(String path) async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AutoAnalyzeStore history', () {
    test('results are listed newest first, unread until opened, and survive a restart', () async {
      final store = await AutoAnalyzeStore.open();
      final a = await store.saveResult('/r/a.m4a', _analyze('scam_digital_arrest'), now: DateTime(2026, 11, 20, 9));
      final b = await store.saveResult('/r/b.m4a', _analyze('genuine_family_call'), now: DateTime(2026, 11, 21, 9));
      expect(store.allResults().map((r) => r.id), [b, a]);
      expect(store.unreadCount, 2);
      await store.markRead(a);
      await store.markRead(a);
      expect(store.unreadCount, 1);
      expect(store.isRead(a), isTrue);

      // Same storage, fresh objects (as after closing and reopening the app).
      final values = (await SharedPreferences.getInstance()).getKeys();
      expect(values, containsAll(['${AutoAnalyzeStore.kResultPrefix}$a', AutoAnalyzeStore.kRead]));
      final again = AutoAnalyzeStore(await SharedPreferences.getInstance());
      expect(again.allResults().map((r) => r.result.risk), ['low', 'high']);
      expect(again.unreadCount, 1);

      await again.markAllRead();
      expect(again.unreadCount, 0);
    });

    test('keeps up to 500 results; dropped ones leave no read marks behind', () async {
      expect(AutoAnalyzeStore.maxResults, greaterThanOrEqualTo(500));
      final store = await AutoAnalyzeStore.open();
      final r = _timeline.analyze('hello');
      final first = await store.saveResult('/r/0.mp3', r, now: DateTime(2026));
      await store.markRead(first);
      for (var i = 1; i <= AutoAnalyzeStore.maxResults; i++) {
        await store.saveResult('/r/$i.mp3', r, now: DateTime(2026).add(Duration(seconds: i)));
      }
      expect(store.resultIds, hasLength(AutoAnalyzeStore.maxResults));
      expect(store.result(first), isNull);
      expect(store.readIds, isNot(contains(first)));
    });
  });

  group('Recording alerts UI', () {
    Widget app(Widget home) => ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(_Api()),
            autoAnalyzePlatformProvider.overrideWithValue(_NoPlatform()),
            autoAnalyzeNotifierProvider.overrideWithValue(_Notifier()),
            callTimelineProvider.overrideWith((ref) async => _timeline),
            folderExistsProvider.overrideWithValue((p) async => false),
            recordingFolderCandidatesProvider.overrideWith((ref) async => const <String>[]),
          ],
          child: MaterialApp(home: home),
        );

    void tall(WidgetTester t) {
      t.view.physicalSize = const Size(900, 3200);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
    }

    /// Disposes the tree so the 3-second refresh timer is cancelled.
    Future<void> done(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(inboxRefresh);
    }

    Future<(String, String)> seed(WidgetTester t) async => (await t.runAsync(() async {
          final store = await AutoAnalyzeStore.open();
          final old = await store.saveResult('/rec/Call_old.m4a', _analyze('genuine_bank_service'),
              now: DateTime(2026, 11, 20, 8, 5));
          final scam = await store.saveResult('/rec/Call_scam.m4a', _analyze('scam_fake_kyc_otp'),
              now: DateTime(2026, 11, 22, 18, 30));
          await store.markRead(old);
          return (old, scam);
        }))!;

    testWidgets('empty history explains how to fill it and links to setup', (t) async {
      tall(t);
      await t.pumpWidget(app(const RecordingInboxScreen()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('inbox_empty')), findsOneWidget);
      await t.tap(find.byKey(const Key('inbox_setup')));
      await t.pumpAndSettle();
      expect(find.byType(AutoAnalyzeScreen), findsOneWidget);
      await done(t);
    });

    testWidgets('lists every analysis newest first; opening one shows the report and marks it read', (t) async {
      tall(t);
      final (old, scam) = await seed(t);
      await t.pumpWidget(app(const RecordingInboxScreen()));
      await t.pumpAndSettle();

      final scamY = t.getTopLeft(find.byKey(Key('inbox_item_$scam'))).dy;
      final oldY = t.getTopLeft(find.byKey(Key('inbox_item_$old'))).dy;
      expect(scamY, lessThan(oldY));
      expect(find.byKey(Key('inbox_new_$scam')), findsOneWidget);
      expect(find.byKey(Key('inbox_new_$old')), findsNothing);
      expect(find.textContaining('Call_scam.m4a'), findsOneWidget);
      expect(find.textContaining('22/11/2026 18:30'), findsOneWidget);
      expect(find.textContaining('HIGH RISK'), findsOneWidget);
      expect(find.textContaining('LOW RISK'), findsOneWidget);

      await t.tap(find.byKey(Key('inbox_item_$scam')));
      await t.pumpAndSettle();
      expect(find.byType(RecordingResultScreen), findsOneWidget);
      expect(find.byKey(const Key('rec_verdict')), findsOneWidget);
      expect(find.byKey(const Key('rec_transcript')), findsOneWidget);

      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byKey(Key('inbox_new_$scam')), findsNothing); // read now
      expect(find.byKey(Key('inbox_item_$scam')), findsOneWidget); // and still kept
      await done(t);
    });

    testWidgets('bell badge counts unread; mark all as read clears it', (t) async {
      tall(t);
      await seed(t);
      await t.pumpWidget(app(Scaffold(appBar: AppBar(actions: const [RecordingInboxButton()]))));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('inbox_badge'))).data, '1');

      await t.tap(find.byKey(const Key('inbox_button')));
      await t.pumpAndSettle();
      expect(find.byType(RecordingInboxScreen), findsOneWidget);
      await t.tap(find.byKey(const Key('inbox_mark_all')));
      await t.pumpAndSettle();
      expect(find.text('NEW'), findsNothing);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('inbox_badge')).hitTestable(), findsNothing);
      await done(t);
    });

    testWidgets('a result saved by the background service appears without reopening', (t) async {
      tall(t);
      await t.pumpWidget(app(const Scaffold(body: SingleChildScrollView(child: RecordingInboxSection()))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('inbox_empty')), findsOneWidget);

      final id = await t.runAsync(() async {
        final store = await AutoAnalyzeStore.open();
        return store.saveResult('/rec/Call_new.m4a', _analyze('scam_courier_customs'));
      });
      await t.pump(inboxRefresh);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(find.byKey(Key('inbox_item_$id')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('inbox_section_unread'))).data, '1 new');
      await done(t);
    });

    testWidgets('section previews the latest 3 and links to all; waiting recordings are listed', (t) async {
      tall(t);
      await t.runAsync(() async {
        final store = await AutoAnalyzeStore.open();
        for (var i = 0; i < 4; i++) {
          await store.saveResult('/rec/Call_$i.m4a', _analyze('genuine_family_call'), now: DateTime(2026, 11, 1, i));
        }
        await store.addPending('/rec/Call_waiting.m4a');
      });
      await t.pumpWidget(app(const Scaffold(body: SingleChildScrollView(child: RecordingInboxSection()))));
      await t.pumpAndSettle();
      expect(find.byType(RecordingInboxTile), findsNWidgets(RecordingInboxSection.preview));
      expect(find.textContaining('Call_waiting.m4a'), findsOneWidget);
      expect(find.text('See all (5)'), findsOneWidget);

      await t.tap(find.byKey(const Key('inbox_see_all')));
      await t.pumpAndSettle();
      expect(find.byType(RecordingInboxTile), findsNWidgets(5));

      await t.tap(find.textContaining('Call_waiting.m4a'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rec_analyze_now')), findsOneWidget);
      await done(t);
    });
  });
}

class _NoPlatform implements AutoAnalyzePlatform {
  @override
  dynamic noSuchMethod(Invocation i) => Future.value(false);
}
