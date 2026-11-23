import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scam_rakshak/core/api_client.dart';
import 'package:scam_rakshak/core/providers.dart';
import 'package:scam_rakshak/engine/call_analyzer.dart';
import 'package:scam_rakshak/engine/live_call_analyzer.dart';
import 'package:scam_rakshak/engine/models.dart';
import 'package:scam_rakshak/features/call_detector/auto_analyze_core.dart';
import 'package:scam_rakshak/features/call_detector/auto_analyze_screen.dart';
import 'package:scam_rakshak/features/call_detector/auto_analyze_service.dart';
import 'package:scam_rakshak/features/call_detector/call_detector_screen.dart';
import 'package:scam_rakshak/features/call_detector/call_timeline.dart';
import 'package:scam_rakshak/features/call_detector/call_triggers.dart';
import 'package:scam_rakshak/features/call_detector/recording_result_screen.dart';
import 'package:scam_rakshak/features/call_detector/recording_warning_screen.dart';
import 'package:scam_rakshak/features/live_call/recording_inbox.dart';
import 'package:scam_rakshak/features/report/report_screen.dart';

Map<String, dynamic> _json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

CallTimeline _timeline() => CallTimeline(
      CallAnalyzer.fromJson(_json('assets/rules/call_rules.json')),
      LiveCallAnalyzer.fromJson(_json('assets/rules/call_rules.json')),
    );

String _sample(String id) => File('assets/samples/live/$id.txt').readAsStringSync();

class FakeApi extends ApiClient {
  String text = 'Hello sir, this is your bank KYC team. Your account will be blocked today. Please tell me the OTP now.';
  Object? error;
  bool reachable = true;
  final uploads = <String>[];

  @override
  Future<Map> transcribeRecording(File audio, {Duration timeout = const Duration(minutes: 5)}) async {
    uploads.add(audio.path);
    if (error != null) throw error!;
    return {'text': text, 'lang': 'en'};
  }

  @override
  Future<Map> transcribe(File audio) => transcribeRecording(audio);

  @override
  Future<bool> isReachable({Duration timeout = const Duration(seconds: 4)}) async => reachable;

  @override
  Future<String> getBaseUrl() async => 'http://192.168.1.5:8000';
}

class FakeNotifier implements AutoAnalyzeNotifier {
  final verdicts = <StoredRecordingResult>[];
  final offline = <String>[];
  final cancelled = <String>[];

  @override
  Future<void> showVerdict(StoredRecordingResult r) async => verdicts.add(r);
  @override
  Future<void> showOffline(String path) async => offline.add(path);
  @override
  Future<void> cancelOffline(String path) async => cancelled.add(path);
}

class FakePlatform implements AutoAnalyzePlatform {
  bool files = false, notif = false, battery = false, running = false, startOk = true;
  String? folderToPick = '/storage/emulated/0/Recordings/Call';
  final calls = <String>[];
  NotificationTap? tap;

  @override
  Future<bool> hasAllFilesAccess() async => files;
  @override
  Future<bool> requestAllFilesAccess() async {
    calls.add('files');
    return files = true;
  }

  @override
  Future<bool> hasNotificationPermission() async => notif;
  @override
  Future<bool> requestNotificationPermission() async {
    calls.add('notif');
    return notif = true;
  }

  @override
  Future<bool> isBatteryUnrestricted() async => battery;
  @override
  Future<bool> requestBatteryUnrestricted() async {
    calls.add('battery');
    return battery = true;
  }

  @override
  Future<void> openSettings() async => calls.add('settings');
  @override
  Future<String?> pickFolder() async => folderToPick;
  @override
  Future<bool> startService(String locale) async {
    calls.add('start:$locale');
    running = startOk;
    return startOk;
  }

  @override
  Future<void> stopService() async {
    calls.add('stop');
    running = false;
  }

  @override
  Future<bool> isServiceRunning() async => running;
  @override
  Future<void> listenForTaps(NotificationTap onTap) async => tap = onTap;

  bool fsi = false;
  final lock = <bool>[];
  @override
  Future<bool> canUseFullScreenIntent() async => fsi;
  @override
  Future<void> openFullScreenIntentSettings() async => calls.add('fsi');
  @override
  Future<void> setShowWhenLocked(bool on) async => lock.add(on);
}

/// Returns a fixed verdict (to route HIGH / MEDIUM / LOW deterministically).
class FixedTimeline extends CallTimeline {
  String risk;
  FixedTimeline(this.risk) : super(_timeline().rules, _timeline().live);

  @override
  CallTimelineResult analyze(String transcript) => CallTimelineResult(
        risk,
        switch (risk) { 'high' => 0.9, 'medium' => 0.62, _ => 0.17 },
        CallResult(risk, risk == 'low' ? const [] : const [CallMatch('share the OTP', 'otp_request'), CallMatch('account blocked', 'fake_kyc')]),
        const [],
        transcript,
      );
}

void main() {
  group('CallTimeline', () {
    test('scam recordings are high with a score >= 0.8 and a timeline', () {
      final t = _timeline();
      for (final id in ['scam_digital_arrest', 'scam_fake_kyc_otp', 'scam_courier_customs']) {
        final r = t.analyze(_sample(id));
        expect(r.risk, 'high', reason: id);
        expect(r.score, greaterThanOrEqualTo(0.8), reason: id);
        expect(r.points.length, greaterThanOrEqualTo(8), reason: id); // 8 lines, some with 2 sentences
        expect(r.firstAlertAt, isNotNull, reason: id);
        expect(r.result.matches, isNotEmpty, reason: id);
        expect(r.scriptType, isNotNull, reason: id);
      }
    });

    test('genuine recordings stay low with a score below 0.5', () {
      final t = _timeline();
      for (final id in ['genuine_family_call', 'genuine_bank_service']) {
        final r = t.analyze(_sample(id));
        expect(r.risk, 'low', reason: id);
        expect(r.score, lessThan(0.5), reason: id);
        expect(r.firstAlertAt, isNull);
      }
    });

    test('older sample calls agree with CallAnalyzer or are more cautious', () {
      final t = _timeline();
      final rules = CallAnalyzer.fromJson(_json('assets/rules/call_rules.json'));
      const rank = {'low': 0, 'medium': 1, 'high': 2};
      for (final f in Directory('assets/samples').listSync().whereType<File>().where((f) => f.path.endsWith('.txt'))) {
        final text = f.readAsStringSync();
        expect(rank[t.analyze(text).risk]!, greaterThanOrEqualTo(rank[rules.analyze(text).risk]!), reason: f.path);
      }
    });

    test('result survives JSON round trip and analyze can be repeated', () {
      final t = _timeline();
      final a = t.analyze(_sample('scam_fake_kyc_otp'));
      final b = CallTimelineResult.decode(a.encode());
      expect(b.risk, a.risk);
      expect(b.score, a.score);
      expect(b.points.length, a.points.length);
      expect(b.result.matches.map((m) => m.phrase), a.result.matches.map((m) => m.phrase));
      expect(t.analyze(_sample('scam_fake_kyc_otp')).score, a.score); // no state leaks between calls
      expect(t.analyze('').risk, 'low');
    });
  });

  group('RecordingWatcher', () {
    final since = DateTime(2026, 11, 23, 10);
    late List<RecordingFileInfo> files;
    late RecordingWatcher w;
    setUp(() {
      files = [];
      w = RecordingWatcher(list: (_) async => files);
    });
    Future<List<String>> poll([Set<String> processed = const {}]) async =>
        (await w.poll(folder: '/rec', since: since, processed: processed)).map((f) => f.path).toList();

    test('qualifies only after 3 polls with the same size', () async {
      final t = since.add(const Duration(minutes: 1));
      files = [RecordingFileInfo('/rec/call.m4a', 30000, t)];
      expect(await poll(), isEmpty);
      files = [RecordingFileInfo('/rec/call.m4a', 50000, t.add(const Duration(seconds: 3)))]; // still writing
      expect(await poll(), isEmpty);
      expect(await poll(), isEmpty);
      expect(await poll(), ['/rec/call.m4a']);
    });

    test('ignores other extensions, old, small and processed files', () async {
      final t = since.add(const Duration(minutes: 1));
      files = [
        RecordingFileInfo('/rec/notes.txt', 90000, t),
        RecordingFileInfo('/rec/old.mp3', 90000, since.subtract(const Duration(minutes: 1))),
        RecordingFileInfo('/rec/tiny.amr', 20 * 1024, t),
        RecordingFileInfo('/rec/done.wav', 90000, t),
        for (final e in kRecordingExtensions) RecordingFileInfo('/rec/new.${e.toUpperCase()}', 90000, t),
      ];
      for (var i = 0; i < 2; i++) {
        await poll({'/rec/done.wav'});
      }
      expect(await poll({'/rec/done.wav'}), hasLength(kRecordingExtensions.length));
    });
  });

  group('RecordingProcessor', () {
    late Directory dir;
    late AutoAnalyzeStore store;
    late FakeApi api;
    late FakeNotifier notifier;
    late RecordingProcessor p;
    late File rec;
    late List<int> original;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('sr_rec_');
      store = await AutoAnalyzeStore.open();
      await store.setFolder(dir.path);
      await store.setEnabled(true, now: DateTime.now().subtract(const Duration(minutes: 1)));
      api = FakeApi();
      notifier = FakeNotifier();
      p = RecordingProcessor(store: store, api: api, timeline: _timeline(), notifier: notifier);
      rec = File('${dir.path}${Platform.pathSeparator}Call_9876543210.m4a')..writeAsBytesSync(List.filled(40000, 7));
      original = rec.readAsBytesSync();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> ticks(int n) async {
      for (var i = 0; i < n; i++) {
        await p.tick();
      }
    }

    void expectUntouched() {
      expect(rec.readAsBytesSync(), original);
      expect(dir.listSync().map((e) => e.path), [rec.path]); // nothing copied or left behind
    }

    test('off by default; nothing happens until the toggle is on', () async {
      SharedPreferences.setMockInitialValues({});
      final fresh = await AutoAnalyzeStore.open();
      expect(fresh.enabled, isFalse);
      expect(fresh.enabledAt, isNull);
    });

    test('new recording -> uploaded once, verdict notification, processed, file untouched', () async {
      await ticks(2);
      expect(api.uploads, isEmpty);
      await ticks(1);
      expect(api.uploads, [rec.path]);
      expect(notifier.verdicts, hasLength(1));
      final v = notifier.verdicts.single;
      expect(v.result.risk, 'high');
      expect(v.result.score, greaterThanOrEqualTo(0.8));
      expect(v.fileName, 'Call_9876543210.m4a');
      expect(store.processed, [rec.path, recordingIdentity(rec.path, rec.lengthSync(), rec.lastModifiedSync())]);
      expect(store.result(v.id)!.result.transcript, api.text);
      await ticks(5);
      expect(api.uploads, hasLength(1));
      expectUntouched();
    });

    test('recordings from before the toggle was turned on are ignored', () async {
      await store.setEnabled(true, now: DateTime.now().add(const Duration(minutes: 1)));
      await ticks(5);
      expect(api.uploads, isEmpty);
    });

    test('toggle off stops processing', () async {
      await store.setEnabled(false);
      expect(await p.tick(), isFalse);
      await ticks(4);
      expect(api.uploads, isEmpty);
    });

    test('backend offline -> one "tap to analyze" notification, stays unprocessed, retried when online', () async {
      api
        ..error = const ApiOfflineException('down')
        ..reachable = false;
      await ticks(3);
      expect(notifier.offline, [rec.path]); // reported at once (quick /health check), no 5-minute upload hang
      expect(api.uploads, isEmpty);
      expect(store.pending, [rec.path]);
      expect(store.processed, isEmpty);
      expect(store.lastError, contains('Server not reachable'));
      await ticks(2 * RecordingProcessor.retryEvery);
      expect(api.uploads, isEmpty); // not uploaded while the server is unreachable
      api
        ..error = null
        ..reachable = true;
      await ticks(RecordingProcessor.retryEvery);
      expect(notifier.offline, hasLength(1)); // only one "tap to analyze" notification
      expect(api.uploads, hasLength(1));
      expect(notifier.verdicts, hasLength(1));
      expect(store.pending, isEmpty);
      expect(notifier.cancelled, contains(rec.path));
      expectUntouched();
    });

    test('server error 500 waits like offline; 4xx is not retried', () async {
      api.error = const ApiException(500, 'boom');
      await ticks(3);
      expect(store.pending, [rec.path]);
      api.error = const ApiException(400, 'bad file');
      final r = await p.process(rec.path);
      expect(r.status, ProcessStatus.failed);
      expect(store.processed, contains(rec.path));
      expect(store.pending, isEmpty);
      expect(notifier.verdicts, isEmpty);
    });

    test('silent recording -> processed without a verdict', () async {
      api.text = '  ';
      await ticks(3);
      expect(store.processed, contains(rec.path));
      expect(notifier.verdicts, isEmpty);
    });

    test('genuine call -> low verdict', () async {
      api.text = _sample('genuine_bank_service');
      await ticks(3);
      expect(notifier.verdicts.single.result.risk, 'low');
    });

    test('deleted pending recording is dropped', () async {
      api.error = const ApiOfflineException('down');
      await ticks(3);
      rec.deleteSync();
      await p.tick();
      expect(store.pending, isEmpty);
      final r = await p.process(rec.path);
      expect(r.status, ProcessStatus.missing);
    });

    test('results are capped', () async {
      final r = _timeline().analyze('hello');
      for (var i = 0; i < AutoAnalyzeStore.maxResults + 5; i++) {
        await store.saveResult('/x/$i.mp3', r, now: DateTime(2026, 1, 1, 0, 0, i));
      }
      expect(store.resultIds, hasLength(AutoAnalyzeStore.maxResults));
      expect(store.result(store.resultIds.first)!.path, '/x/5.mp3');
    });
  });


  group('screens', () {
    late FakePlatform platform;
    late FakeApi api;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      platform = FakePlatform();
      api = FakeApi();
    });

    Widget app(Widget home) => ProviderScope(
          overrides: [
            autoAnalyzePlatformProvider.overrideWithValue(platform),
            apiClientProvider.overrideWithValue(api),
            folderExistsProvider.overrideWithValue((p) async => p.startsWith('/storage/emulated/0/Recordings')),
            recordingFolderCandidatesProvider.overrideWith((ref) async => ['/storage/emulated/0/Recordings/Call']),
            autoAnalyzeNotifierProvider.overrideWithValue(FakeNotifier()),
            callTimelineProvider.overrideWith((ref) async => _timeline()),
          ],
          child: MaterialApp(home: home),
        );

    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    bool toggleEnabled(WidgetTester tester) =>
        tester.widget<SwitchListTile>(find.byKey(const Key('auto_toggle'))).onChanged != null;

    testWidgets('setup walks through consent, folder and permissions; toggle off by default', (tester) async {
      tall(tester);
      await tester.pumpWidget(app(const AutoAnalyzeScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Original files are never copied or changed'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('auto_toggle'))).value, isFalse);
      expect(toggleEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('auto_agree')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('auto_pick_folder')));
      await tester.pumpAndSettle();
      expect(find.text('/storage/emulated/0/Recordings/Call'), findsOneWidget);
      expect(toggleEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('auto_allow_files')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('auto_allow_notif')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('auto_allow_battery')));
      await tester.pumpAndSettle();
      expect(platform.calls, ['files', 'notif', 'battery']);
      expect(find.byKey(const Key('auto_allow_files')), findsNothing);
      expect(toggleEnabled(tester), isTrue);

      await tester.tap(find.byKey(const Key('auto_toggle')));
      await tester.pumpAndSettle();
      expect(platform.calls.last, 'start:en');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AutoAnalyzeStore.kEnabled), isTrue);
      expect(prefs.getInt(AutoAnalyzeStore.kEnabledAt), isNotNull);
      expect(find.text('On. Watching the folder every 3 seconds.'), findsOneWidget);
      expect(find.byKey(const Key('auto_simulate')), findsNothing); // no more files written into the folder

      await tester.tap(find.byKey(const Key('auto_toggle')));
      await tester.pumpAndSettle();
      expect(platform.calls.last, 'stop');
      expect(prefs.getBool(AutoAnalyzeStore.kEnabled), isFalse);
    });

    testWidgets('service that fails to start leaves the toggle off with a message', (tester) async {
      tall(tester);
      SharedPreferences.setMockInitialValues({
        AutoAnalyzeStore.kConsent: true,
        AutoAnalyzeStore.kFolder: '/storage/emulated/0/Recordings/Call',
      });
      platform
        ..files = true
        ..notif = true
        ..startOk = false;
      await tester.pumpWidget(app(const AutoAnalyzeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('auto_toggle')));
      await tester.pumpAndSettle();
      expect(find.text('The watcher could not start. Please try again.'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('auto_toggle'))).value, isFalse);
    });

    testWidgets('unreadable folder blocks the toggle; suggested folder chip fixes it', (tester) async {
      tall(tester);
      SharedPreferences.setMockInitialValues({AutoAnalyzeStore.kConsent: true, AutoAnalyzeStore.kFolder: '/nope'});
      platform
        ..files = true
        ..notif = true;
      await tester.pumpWidget(app(const AutoAnalyzeScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('This folder cannot be read'), findsOneWidget);
      expect(toggleEnabled(tester), isFalse);
      await tester.tap(find.text('Recordings/Call'));
      await tester.pumpAndSettle();
      expect(toggleEnabled(tester), isTrue);
    });

    testWidgets('Check Call screen links to the setup screen', (tester) async {
      tall(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          autoAnalyzePlatformProvider.overrideWithValue(platform),
          apiClientProvider.overrideWithValue(api),
          folderExistsProvider.overrideWithValue((p) async => false),
          recordingFolderCandidatesProvider.overrideWith((ref) async => const <String>[]),
          callAnalyzerProvider.overrideWith((ref) async => CallAnalyzer.fromJson(_json('assets/rules/call_rules.json'))),
        ],
        child: const MaterialApp(home: CallDetectorScreen()),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('call_auto_entry')));
      await tester.pumpAndSettle();
      expect(find.byType(AutoAnalyzeScreen), findsOneWidget);
    });

    Future<String> saveScam() async {
      final store = await AutoAnalyzeStore.open();
      return store.saveResult('/storage/emulated/0/Recordings/Call/Call_1.m4a', _timeline().analyze(_sample('scam_digital_arrest')));
    }

    testWidgets('result screen shows verdict, score, timeline, highlights; Report opens /report', (tester) async {
      tall(tester);
      final id = await tester.runAsync(saveScam);
      await tester.pumpWidget(app(RecordingResultScreen(payload: resultPayload(id!))));
      await tester.pumpAndSettle();
      expect(find.text('HIGH RISK'), findsOneWidget);
      expect(find.textContaining('Scam score: '), findsOneWidget);
      expect(find.textContaining('Call_1.m4a'), findsOneWidget);
      expect(find.text('How the call went'), findsOneWidget);
      final spans = <InlineSpan>[];
      tester.widget<RichText>(find.descendant(of: find.byKey(const Key('rec_transcript')), matching: find.byType(RichText)))
          .text
          .visitChildren((s) {
        spans.add(s);
        return true;
      });
      expect(spans.whereType<TextSpan>().any((s) => s.style?.fontWeight == kKeyWordWeight), isTrue);
      await tester.tap(find.byKey(const Key('rec_report')));
      await tester.pumpAndSettle();
      expect(find.byType(ReportScreen), findsOneWidget);
    });

    testWidgets('unknown result shows a message', (tester) async {
      await tester.pumpWidget(app(RecordingResultScreen(payload: resultPayload('123'))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rec_message')), findsOneWidget);
    });

    testWidgets('pending recording: offline shows error, online analyses and shows the result', (tester) async {
      tall(tester);
      final dir = Directory.systemTemp.createTempSync('sr_pending_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final rec = File('${dir.path}${Platform.pathSeparator}Call_2.mp3')..writeAsBytesSync(List.filled(30000, 1));
      api.error = const ApiOfflineException('down');
      await tester.pumpWidget(app(RecordingResultScreen(payload: pendingPayload(rec.path))));
      await tester.pumpAndSettle();
      expect(find.textContaining('Call_2.mp3'), findsOneWidget);

      Future<void> analyze() async {
        await tester.tap(find.byKey(const Key('rec_analyze_now')));
        // Each real file operation (exists, stat) completes in real time, then resumes on a pump.
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
          await tester.pump();
        }
        await tester.pumpAndSettle();
      }

      await analyze();
      expect(find.byKey(const Key('rec_error')), findsOneWidget);
      api.error = null;
      await analyze();
      expect(find.text('HIGH RISK'), findsOneWidget);
      expect(rec.existsSync(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(AutoAnalyzeStore.kProcessed), contains(rec.path));
    });

    testWidgets('notification taps open the result, and the Report action opens /report', (tester) async {
      tall(tester);
      final id = await tester.runAsync(saveScam);
      await tester.pumpWidget(app(const AutoAnalyzeHost(child: Scaffold(body: Text('home')))));
      await tester.pumpAndSettle();
      expect(platform.tap, isNotNull);

      platform.tap!(null, resultPayload(id!));
      await tester.pumpAndSettle();
      expect(find.byType(RecordingResultScreen), findsOneWidget);
      expect(find.text('HIGH RISK'), findsOneWidget);

      Navigator.of(tester.element(find.byType(RecordingResultScreen))).pop();
      await tester.pumpAndSettle();
      platform.tap!(kReportAction, resultPayload(id));
      await tester.pumpAndSettle();
      expect(find.byType(ReportScreen), findsOneWidget);
    });

    testWidgets('host restarts the watcher when the toggle is on but the service is not running', (tester) async {
      SharedPreferences.setMockInitialValues({AutoAnalyzeStore.kEnabled: true});
      await tester.pumpWidget(app(const AutoAnalyzeHost(child: Text('home'))));
      await tester.pumpAndSettle();
      expect(platform.calls, ['start:en']);
    });
  });

  group('watcher qualification (demo/simulated, partial, hidden, processed)', () {
    final since = DateTime(2026, 11, 23, 10);
    final t = since.add(const Duration(minutes: 2));

    test('only genuine finished recordings qualify', () async {
      final files = [
        RecordingFileInfo('/rec/Ramesh 2026-11-23 19-31-47.m4a', 90000, t), // real recording
        RecordingFileInfo('/rec/ScamRakshak_demo_call_20261123_193059.mp3', 286848, t), // old Simulate output
        RecordingFileInfo('/rec/ScamRakshak_demo_call_20261123_193059.mp3.part', 286848, t), // partial demo
        RecordingFileInfo('/rec/call.m4a.part', 90000, t), // partial download/write
        RecordingFileInfo('/rec/.trashed-1798035356-Ramesh 2026-11-23 14-14-28.m4a', 90000, t), // MediaStore trash
        RecordingFileInfo('/rec/.pending-1798035356-call.m4a', 90000, t), // MediaStore pending
        RecordingFileInfo('/rec/.hidden.mp3', 90000, t),
      ];
      final w = RecordingWatcher(list: (_) async => files);
      List<String> ready = [];
      for (var i = 0; i < RecordingWatcher.stablePolls; i++) {
        ready = (await w.poll(folder: '/rec', since: since, processed: const {})).map((f) => f.path).toList();
      }
      expect(ready, ['/rec/Ramesh 2026-11-23 19-31-47.m4a']);
      expect(isGenuineRecording('/rec/my demo.mp3'), isTrue); // a user's own file named "demo" is fine
    });

    test('already processed (by path or by identity after a rename) is excluded', () async {
      final real = RecordingFileInfo('/rec/Ramesh 2026-11-23 19-31-47.m4a', 90000, t);
      final moved = RecordingFileInfo('/rec/Calls/Ramesh 2026-11-23 19-31-47.m4a', 90000, t);
      final id = recordingIdentity(real.path, real.size, real.modified);
      expect(recordingIdentity('/x/.trashed-123-Ramesh 2026-11-23 19-31-47.m4a', 90000, t), id);
      final w = RecordingWatcher(list: (_) async => [real, moved]);
      for (var i = 0; i < RecordingWatcher.stablePolls; i++) {
        expect(await w.poll(folder: '/rec', since: since, processed: {id}), isEmpty);
      }
    });
  });

  group('dedupe, demo cleanup and warning routing', () {
    late Directory dir;
    late AutoAnalyzeStore store;
    late FakeApi api;
    late FakeNotifier notifier;
    late File rec;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('sr_warn_');
      store = await AutoAnalyzeStore.open();
      await store.setFolder(dir.path);
      await store.setEnabled(true, now: DateTime.now().subtract(const Duration(minutes: 1)));
      api = FakeApi();
      notifier = FakeNotifier();
      rec = File('${dir.path}${Platform.pathSeparator}Call_9876543210.m4a')..writeAsBytesSync(List.filled(40000, 7));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    RecordingProcessor proc({String risk = 'high', void Function(String)? onWarning}) => RecordingProcessor(
        store: store, api: api, timeline: FixedTimeline(risk), notifier: notifier, onWarning: onWarning);

    Future<void> ticks(RecordingProcessor p, int n) async {
      for (var i = 0; i < n; i++) {
        await p.tick();
      }
    }

    test('each recording is analysed at most once, across service restarts', () async {
      await ticks(proc(), 3);
      expect(api.uploads, [rec.path]);
      // Service restarted: new processor and a freshly loaded store.
      final restarted = RecordingProcessor(
          store: await AutoAnalyzeStore.open(), api: api, timeline: FixedTimeline('high'), notifier: notifier);
      await ticks(restarted, 6);
      expect(api.uploads, hasLength(1));
      // The same recording at another path (moved, same name/size/time) is not analysed again.
      final other = Directory('${dir.path}${Platform.pathSeparator}moved')..createSync();
      final copy = File('${other.path}${Platform.pathSeparator}Call_9876543210.m4a')
        ..writeAsBytesSync(rec.readAsBytesSync());
      copy.setLastModifiedSync(rec.lastModifiedSync());
      expect((await restarted.process(copy.path)).status, ProcessStatus.skipped);
      expect(api.uploads, hasLength(1));
      expect(store.resultIds, hasLength(1));
    });

    test('demo files are never analysed; cleanup deletes only the app demo files and their alerts', () async {
      final demo = File('${dir.path}${Platform.pathSeparator}ScamRakshak_demo_call_20261123_193059.mp3')
        ..writeAsBytesSync(List.filled(286848, 1));
      final part = File('${dir.path}${Platform.pathSeparator}ScamRakshak_demo_call_20261123_141820.mp3.part')
        ..writeAsBytesSync(List.filled(1000, 1));
      final userDemo = File('${dir.path}${Platform.pathSeparator}my demo.mp3')..writeAsBytesSync(List.filled(40000, 3));
      expect((await proc().process(demo.path)).status, ProcessStatus.skipped);
      expect(api.uploads, isEmpty);
      // An old demo verdict in the alert history is removed too.
      await store.saveResult(demo.path, FixedTimeline('low').analyze('x'));
      final realId = await store.saveResult(rec.path, FixedTimeline('high').analyze('y'));
      final deleted = await cleanUpDemoRecordings(store);
      expect(deleted, 2);
      expect(demo.existsSync() || part.existsSync(), isFalse);
      expect(rec.existsSync() && userDemo.existsSync(), isTrue);
      expect(store.resultIds, [realId]);
      // The processor only analyses the real recordings.
      await ticks(proc(), 3);
      expect(api.uploads.map(fileNameOf).toSet(), {'Call_9876543210.m4a', 'my demo.mp3'});
    });

    for (final risk in ['high', 'medium', 'low']) {
      test('risk routing: $risk -> ${risk == 'low' ? 'notification only' : 'queued full-screen warning'}', () async {
        final warned = <String>[];
        await ticks(proc(risk: risk, onWarning: warned.add), 3);
        final id = store.resultIds.single;
        expect(notifier.verdicts.single.id, id);
        if (risk == 'low') {
          expect(store.warnQueue, isEmpty);
          expect(warned, isEmpty);
          expect(store.needsWarning(id), isFalse);
        } else {
          expect(store.warnQueue, [id]);
          expect(warned, [id]);
          expect(store.nextWarning(), id);
        }
      });
    }

    test('result is saved (and queued) before the notification or the warning', () async {
      final seen = <String>[];
      final checking = _CheckingNotifier(store, seen);
      final p = RecordingProcessor(
        store: store,
        api: api,
        timeline: FixedTimeline('high'),
        notifier: checking,
        onWarning: (id) => seen.add('warn:${store.result(id) != null}:${store.warnQueue.contains(id)}'),
      );
      await ticks(p, 3);
      expect(seen, ['notify:true:true', 'warn:true:true']);
    });

    test('notification still posts when saving, queueing and the app message all throw', () async {
      final broken = _BrokenStore(store.prefs);
      final p = RecordingProcessor(
        store: broken,
        api: api,
        timeline: FixedTimeline('high'),
        notifier: notifier,
        onWarning: (_) => throw StateError('app gone'),
      );
      await ticks(p, 3);
      expect(notifier.verdicts, hasLength(1));
      expect(notifier.verdicts.single.result.risk, 'high');
      expect(notifier.verdicts.single.fileName, 'Call_9876543210.m4a');
      expect(broken.lastError, contains('save result'));
    });

    test('warning step failure does not block the notification', () async {
      final p = proc(onWarning: (_) => throw StateError('app gone'));
      await ticks(p, 3);
      expect(notifier.verdicts, hasLength(1));
      expect(store.resultIds, hasLength(1)); // saved
      expect(store.warnQueue, hasLength(1)); // queued for when the app opens
    });

    test('diagnostics list: genuine accepted, demo/partial rejected with reasons', () async {
      File('${dir.path}${Platform.pathSeparator}ScamRakshak_demo_call_20261123_210600.mp3')
          .writeAsBytesSync(List.filled(40000, 1));
      File('${dir.path}${Platform.pathSeparator}call.m4a.part').writeAsBytesSync(List.filled(40000, 1));
      final p = proc(risk: 'low');
      await p.tick(); // cleanup removes the demo file on the first poll
      File('${dir.path}${Platform.pathSeparator}ScamRakshak_demo_call_20261123_210700.mp3')
          .writeAsBytesSync(List.filled(40000, 1)); // a new one appears later
      await ticks(p, 3);
      final d = {for (final x in store.diagnostics) x.name: x};
      expect(d['Call_9876543210.m4a']!.accepted, isTrue);
      expect(d['Call_9876543210.m4a']!.reason, 'analysed: LOW 17%');
      expect(d['ScamRakshak_demo_call_20261123_210700.mp3']!.reason, 'ScamRakshak demo file');
      expect(d['call.m4a.part']!.reason, 'not an audio recording');
      expect(api.uploads, [rec.path]);
      expect(store.diagnostics.length, lessThanOrEqualTo(AutoAnalyzeStore.maxDiag));
    });

    test('Analyze now from the app (notify: false) raises no warning', () async {
      final r = await proc().process(rec.path, notify: false);
      expect(r.status, ProcessStatus.done);
      expect(store.warnQueue, isEmpty);
    });
  });

  group('full-screen warning screens', () {
    late FakePlatform platform;
    late FakeApi api;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      platform = FakePlatform();
      api = FakeApi();
      // rootBundle caches the load Future from the previous test's fake-async zone; start fresh.
      rootBundle.evict(kDemoTranscriptAsset);
    });

    Widget app(Widget home) => ProviderScope(
          overrides: [
            autoAnalyzePlatformProvider.overrideWithValue(platform),
            apiClientProvider.overrideWithValue(api),
            folderExistsProvider.overrideWithValue((p) async => true),
            recordingFolderCandidatesProvider.overrideWith((ref) async => const <String>[]),
            autoAnalyzeNotifierProvider.overrideWithValue(FakeNotifier()),
            callTimelineProvider.overrideWith((ref) async => _timeline()),
          ],
          child: MaterialApp(home: home),
        );

    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<String> save(String risk, {bool queue = true, String name = 'Call_1.m4a'}) async {
      final store = await AutoAnalyzeStore.open();
      final id = await store.saveResult('/storage/emulated/0/Record/Call/$name', FixedTimeline(risk).analyze('Tell me the OTP'));
      if (queue) await store.enqueueWarning(id);
      return id;
    }

    Color bg(WidgetTester tester) => tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor!;

    testWidgets('HIGH is red, MEDIUM is amber, with score, type and trigger phrases', (tester) async {
      tall(tester);
      final high = (await tester.runAsync(() => save('high')))!;
      final medium = (await tester.runAsync(() => save('medium', name: 'Call_2.m4a')))!;
      await tester.pumpWidget(app(RecordingWarningScreen(resultId: high)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('warn_high')), findsOneWidget);
      expect(bg(tester), kWarnHighColor);
      expect(find.text('SCAM CALL WARNING'), findsOneWidget);
      expect(find.text('Scam score: 90%'), findsOneWidget);
      expect(find.text('Scam type: Asking for OTP / code'), findsOneWidget);
      expect(find.text('"share the OTP"'), findsOneWidget);
      expect(find.byKey(const Key('warn_saved')), findsOneWidget);
      expect(platform.lock, [true]); // over the lock screen while open

      // Next warning replaces the first: stays over the lock screen in between.
      await tester.pumpWidget(app(RecordingWarningScreen(key: ValueKey(medium), resultId: medium)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('warn_medium')), findsOneWidget);
      expect(bg(tester), kWarnMediumColor);
      expect(find.text('POSSIBLE SCAM CALL'), findsOneWidget);
      expect(find.text('Scam score: 62%'), findsOneWidget);
      expect(platform.lock, [true, true]);
      await tester.pumpWidget(const SizedBox());
      expect(platform.lock, [true, true, false]); // normal again once no warning is open
    });

    testWidgets('Report opens the reporting options carrying the recording; alert stays saved', (tester) async {
      tall(tester);
      final id = (await tester.runAsync(() => save('high')))!;
      await tester.pumpWidget(app(RecordingWarningScreen(resultId: id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('warn_report')));
      await tester.pumpAndSettle();
      expect(find.byType(ReportScreen), findsOneWidget);
      expect(find.byType(RecordingReportScreen), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('rep_evidence_id'))).data, 'Alert ID: $id · Call_1.m4a');
      final store = (await tester.runAsync(AutoAnalyzeStore.open))!;
      await tester.runAsync(store.reload);
      expect(store.result(id), isNotNull);
      expect(store.needsWarning(id), isFalse);
    });

    testWidgets('Dismiss closes the warning and opens Recording Alerts; alert stays saved', (tester) async {
      tall(tester);
      final id = (await tester.runAsync(() => save('high')))!;
      await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => openRecordingWarning(context, id), child: const Text('open')),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('warn_dismiss')));
      await tester.pumpAndSettle();
      expect(find.byType(RecordingWarningScreen), findsNothing);
      expect(find.byType(RecordingInboxScreen), findsOneWidget);
      expect(find.textContaining('Call_1.m4a'), findsWidgets);
      final store = (await tester.runAsync(AutoAnalyzeStore.open))!;
      await tester.runAsync(store.reload);
      expect(store.result(id), isNotNull);
    });

    testWidgets('host shows queued warnings one at a time, each once; old notification -> result, not warning',
        (tester) async {
      tall(tester);
      final first = (await tester.runAsync(() => save('high')))!;
      final second = (await tester.runAsync(() => save('medium', name: 'Call_2.m4a')))!;
      final low = (await tester.runAsync(() => save('low', queue: false, name: 'Call_3.m4a')))!;
      await tester.pumpWidget(app(const AutoAnalyzeHost(child: Scaffold(body: Text('home')))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('warn_high')), findsOneWidget); // oldest first
      Navigator.of(tester.element(find.byType(RecordingWarningScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('warn_medium')), findsOneWidget); // then the next one
      Navigator.of(tester.element(find.byType(RecordingWarningScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(RecordingWarningScreen), findsNothing);
      expect(find.text('home'), findsOneWidget);

      // Tapping the old notification of a dismissed warning opens the result, not the warning.
      platform.tap!(null, resultPayload(first, warn: true));
      await tester.pumpAndSettle();
      expect(find.byType(RecordingWarningScreen), findsNothing);
      expect(find.byType(RecordingResultScreen), findsOneWidget);
      expect(platform.lock.last, isFalse);
      Navigator.of(tester.element(find.byType(RecordingResultScreen))).pop();
      await tester.pumpAndSettle();

      // Restart (new host): nothing is shown again; LOW never had a warning.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(const AutoAnalyzeHost(child: Scaffold(body: Text('home')))));
      await tester.pumpAndSettle();
      expect(find.byType(RecordingWarningScreen), findsNothing);
      final store = (await tester.runAsync(AutoAnalyzeStore.open))!;
      await tester.runAsync(store.reload);
      expect(store.warnedIds, containsAll([first, second]));
      expect(store.warnedIds.contains(low), isFalse);
      expect(store.resultIds, hasLength(3)); // all kept
    });

    testWidgets('notification tap on a queued warning (app opened from it) shows that warning', (tester) async {
      tall(tester);
      final a = (await tester.runAsync(() => save('high')))!;
      final b = (await tester.runAsync(() => save('high', name: 'Call_2.m4a')))!;
      // Simulate both already shown except b, then tap b's notification.
      final store = (await tester.runAsync(AutoAnalyzeStore.open))!;
      await tester.runAsync(() => store.markWarned(a));
      await tester.pumpWidget(app(const AutoAnalyzeHost(child: Scaffold(body: Text('home')))));
      await tester.pumpAndSettle();
      expect(find.textContaining('Call_2.m4a'), findsOneWidget); // b shown at start
      Navigator.of(tester.element(find.byType(RecordingWarningScreen))).pop();
      await tester.pumpAndSettle();
      platform.tap!(null, resultPayload(b, warn: true));
      await tester.pumpAndSettle();
      expect(find.byType(RecordingWarningScreen), findsNothing); // shown once only
    });

    testWidgets('DEMO warning: labelled DEMO, uses no folder, saves nothing', (tester) async {
      tall(tester);
      SharedPreferences.setMockInitialValues({
        AutoAnalyzeStore.kConsent: true,
        AutoAnalyzeStore.kFolder: '/storage/emulated/0/Record/Call',
      });
      await tester.pumpWidget(app(const AutoAnalyzeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('auto_demo_warning')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('warn_demo_banner')), findsOneWidget);
      expect(find.byKey(const Key('warn_high')), findsOneWidget);
      expect(find.byKey(const Key('warn_saved')), findsNothing);
      await tester.tap(find.byKey(const Key('warn_dismiss')));
      await tester.pumpAndSettle();
      expect(find.byType(AutoAnalyzeScreen), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(AutoAnalyzeStore.kResults), isNull);
      expect(prefs.getStringList(AutoAnalyzeStore.kWarnQueue), isNull);
    });

    testWidgets('with go_router: DEMO -> Report stacks on top; real warning Report/Dismiss navigate', (tester) async {
      tall(tester);
      SharedPreferences.setMockInitialValues({AutoAnalyzeStore.kConsent: true});
      final router = GoRouter(initialLocation: '/call/auto', routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
        GoRoute(path: '/call/auto', builder: (_, _) => const AutoAnalyzeScreen()),
        GoRoute(path: '/call/warning', builder: (_, s) => RecordingWarningScreen(resultId: s.extra as String)),
        GoRoute(
            path: '/call/warning/demo',
            builder: (_, s) => RecordingWarningScreen.demo(demo: s.extra as CallTimelineResult)),
        GoRoute(path: '/call/report', builder: (_, s) => RecordingReportScreen(resultId: s.extra as String)),
        GoRoute(path: '/report', builder: (_, s) => ReportScreen(initialType: s.extra as String?)),
        GoRoute(path: '/live/inbox', builder: (_, _) => const RecordingInboxScreen()),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          autoAnalyzePlatformProvider.overrideWithValue(platform),
          apiClientProvider.overrideWithValue(api),
          folderExistsProvider.overrideWithValue((p) async => true),
          recordingFolderCandidatesProvider.overrideWith((ref) async => const <String>[]),
          callTimelineProvider.overrideWith((ref) async => _timeline()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('auto_demo_warning')));
      for (var i = 0; i < 40 && find.byType(RecordingWarningScreen).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      bool demoOnTop() =>
          router.state.uri.path == '/call/warning/demo' &&
          tester.widget<RecordingWarningScreen>(find.byType(RecordingWarningScreen)).demo != null;
      expect(demoOnTop(), isTrue,
          reason: 'path=${router.state.uri.path} warnings=${find.byType(RecordingWarningScreen).evaluate().length} '
              'auto=${find.byType(AutoAnalyzeScreen).evaluate().length} ex=${tester.takeException()}');
      await tester.tap(find.byKey(const Key('warn_report')));
      await tester.pumpAndSettle();
      expect(find.byType(ReportScreen), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(demoOnTop(), isTrue); // DEMO still under the report

      final id = (await tester.runAsync(() => save('high')))!;
      router.push('/call/warning', extra: id);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('warn_report')));
      await tester.pumpAndSettle();
      expect(find.byType(RecordingReportScreen), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('warn_dismiss')));
      await tester.pumpAndSettle();
      expect(find.byType(RecordingInboxScreen), findsOneWidget);
      expect(find.byType(RecordingWarningScreen), findsNothing);
    });

    testWidgets('with go_router: after Dismiss, a later warning still opens (no stuck queue)', (tester) async {
      tall(tester);
      final first = (await tester.runAsync(() => save('high')))!;
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const AutoAnalyzeHost(child: Scaffold(body: Text('home')))),
        GoRoute(path: '/call/warning', builder: (_, s) => RecordingWarningScreen(resultId: s.extra as String)),
        GoRoute(path: '/call/report', builder: (_, s) => RecordingReportScreen(resultId: s.extra as String)),
        GoRoute(path: '/call/recording', builder: (_, s) => RecordingResultScreen(payload: s.extra as String?)),
        GoRoute(path: '/live/inbox', builder: (_, _) => const RecordingInboxScreen()),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          autoAnalyzePlatformProvider.overrideWithValue(platform),
          apiClientProvider.overrideWithValue(api),
          autoAnalyzeNotifierProvider.overrideWithValue(FakeNotifier()),
          callTimelineProvider.overrideWith((ref) async => _timeline()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      expect(tester.widget<RecordingWarningScreen>(find.byType(RecordingWarningScreen)).resultId, first);
      await tester.tap(find.byKey(const Key('warn_dismiss')));
      await tester.pumpAndSettle();
      expect(find.byType(RecordingInboxScreen), findsOneWidget);

      // A new HIGH recording is analysed while the app is open (service -> app message / resume).
      final second = (await tester.runAsync(() => save('high', name: 'Call_2.m4a')))!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(tester.widget<RecordingWarningScreen>(find.byType(RecordingWarningScreen)).resultId, second);
    });

    testWidgets('setup screen guides to allow full-screen warnings (Android 14+)', (tester) async {
      tall(tester);
      SharedPreferences.setMockInitialValues({AutoAnalyzeStore.kConsent: true});
      await tester.pumpWidget(app(const AutoAnalyzeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Allow full-screen warnings'), findsOneWidget);
      await tester.tap(find.byKey(const Key('auto_allow_fsi')));
      await tester.pumpAndSettle();
      expect(platform.calls, contains('fsi'));
      platform.fsi = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('auto_allow_fsi')), findsNothing);
    });
  });
}

/// A store whose save and warning-queue writes fail (e.g. storage full).
class _BrokenStore extends AutoAnalyzeStore {
  _BrokenStore(super.prefs);

  @override
  Future<String> saveResult(String path, CallTimelineResult r, {DateTime? now}) => throw StateError('disk full');

  @override
  Future<void> enqueueWarning(String id) => throw StateError('disk full');
}

/// Records, at notification time, whether the result was already saved and queued.
class _CheckingNotifier implements AutoAnalyzeNotifier {
  final AutoAnalyzeStore store;
  final List<String> seen;
  _CheckingNotifier(this.store, this.seen);

  @override
  Future<void> showVerdict(StoredRecordingResult r) async =>
      seen.add('notify:${store.result(r.id) != null}:${store.warnQueue.contains(r.id)}');
  @override
  Future<void> showOffline(String path) async {}
  @override
  Future<void> cancelOffline(String path) async {}
}
