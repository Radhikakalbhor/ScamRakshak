import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:scam_rakshak/features/call_detector/call_detector_screen.dart';
import 'package:scam_rakshak/features/call_detector/call_timeline.dart';
import 'package:scam_rakshak/features/call_detector/recording_result_screen.dart';
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
      expect(store.processed, [rec.path]);
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
      expect(notifier.offline, [rec.path]);
      expect(store.pending, [rec.path]);
      expect(store.processed, isEmpty);
      await ticks(2 * RecordingProcessor.retryEvery);
      expect(api.uploads, hasLength(1)); // not re-uploaded while the server is unreachable
      api
        ..error = null
        ..reachable = true;
      await ticks(RecordingProcessor.retryEvery);
      expect(notifier.offline, hasLength(1)); // only one "tap to analyze" notification
      expect(api.uploads, hasLength(2));
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
      expect(store.processed, [rec.path]);
      expect(store.pending, isEmpty);
      expect(notifier.verdicts, isEmpty);
    });

    test('silent recording -> processed without a verdict', () async {
      api.text = '  ';
      await ticks(3);
      expect(store.processed, [rec.path]);
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

  test('simulateRecording writes one finished sample mp3 into the folder', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = Directory.systemTemp.createTempSync('sr_sim_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = await simulateRecording(dir.path, rootBundle, now: DateTime(2026, 11, 23, 9, 5, 7));
    expect(fileNameOf(f.path), 'ScamRakshak_demo_call_20261123_090507.mp3');
    expect(dir.listSync().map((e) => e.path), [f.path]); // no .part left
    var expected = 0;
    for (final a in kSimulateClips) {
      expected += File(a).lengthSync();
    }
    expect(f.lengthSync(), expected);
    expect(f.lengthSync(), greaterThan(RecordingWatcher.minBytes));
    expect(isRecordingFile(f.path), isTrue);
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
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('auto_simulate'))).onPressed, isNull);

      await tester.tap(find.byKey(const Key('auto_toggle')));
      await tester.pumpAndSettle();
      expect(platform.calls.last, 'start:en');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AutoAnalyzeStore.kEnabled), isTrue);
      expect(prefs.getInt(AutoAnalyzeStore.kEnabledAt), isNotNull);
      expect(find.text('On. Watching the folder every 3 seconds.'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('auto_simulate'))).onPressed, isNotNull);

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
      await tester.tap(find.widgetWithText(ActionChip, 'Recordings/Call'));
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
      expect(spans.whereType<TextSpan>().any((s) => s.style?.fontWeight == FontWeight.bold), isTrue);
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
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pumpAndSettle();
      }

      await analyze();
      expect(find.byKey(const Key('rec_error')), findsOneWidget);
      api.error = null;
      await analyze();
      expect(find.text('HIGH RISK'), findsOneWidget);
      expect(rec.existsSync(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(AutoAnalyzeStore.kProcessed), [rec.path]);
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
}
