import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scam_rakshak/core/api_client.dart';
import 'package:scam_rakshak/core/providers.dart';
import 'package:scam_rakshak/core/strings.dart';
import 'package:scam_rakshak/core/theme.dart';
import 'package:scam_rakshak/engine/call_analyzer.dart';
import 'package:scam_rakshak/engine/live_call_analyzer.dart';
import 'package:scam_rakshak/features/call_detector/auto_analyze_core.dart';
import 'package:scam_rakshak/features/call_detector/call_timeline.dart';
import 'package:scam_rakshak/engine/scam_classifier.dart';
import 'package:scam_rakshak/features/live_call/live_call_io.dart';
import 'package:scam_rakshak/features/live_call/live_call_screen.dart';
import 'package:scam_rakshak/features/live_call/live_risk.dart';
import 'package:scam_rakshak/features/report/report_screen.dart';

// ---- fakes ------------------------------------------------------------------------------

class FakeAudio implements DemoAudio {
  final played = <String>[];
  int stops = 0;
  bool fail = false;
  Duration length = const Duration(seconds: 1);
  Completer<void>? _c;

  @override
  Future<void> play(String assetPath) {
    if (fail) return Future.error(Exception('no audio device'));
    played.add(assetPath);
    final c = _c = Completer<void>();
    Timer(length, () => c.isCompleted ? null : c.complete());
    return c.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    final c = _c;
    if (c != null && !c.isCompleted) c.complete();
  }
}

class FakeRecorder implements ChunkRecorder {
  bool permission = true;
  bool failStart = false;
  double db = -20;
  final started = <String>[];
  String? _cur;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start(String path) async {
    if (failStart) throw Exception('mic busy');
    started.add(path);
    _cur = path;
    File(path).writeAsBytesSync(List.filled(64, 1));
  }

  @override
  Future<String?> stop() async => _cur;

  @override
  Future<double> levelDb() async => db;
}

class FakeApi extends ApiClient {
  bool reachable;
  final List<String> texts;
  Object? error;
  int failTimes = 0;
  int calls = 0;
  final existedAtUpload = <bool>[];
  final uploaded = <String>[];
  final langs = <String?>[];

  FakeApi({this.reachable = true, this.texts = const []}) : super(baseUrl: 'http://192.168.1.5:8000');

  @override
  Future<bool> isReachable({Duration timeout = const Duration(seconds: 4)}) async => reachable;

  @override
  Future<Map> transcribeChunk(File audio, {String? lang}) async {
    existedAtUpload.add(audio.existsSync());
    uploaded.add(audio.path);
    langs.add(lang);
    final i = calls++;
    if (error != null && i < failTimes) throw error!;
    return {'text': i < texts.length ? texts[i] : '', 'lang': 'hi'};
  }
}

// ---- helpers ----------------------------------------------------------------------------

List<String> scriptLines(String id) =>
    File('assets/samples/live/$id.txt').readAsLinesSync().map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

void main() {
  late LiveCallAnalyzer analyzer;
  late ScamClassifier classifier;
  late Directory tmp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    analyzer = await LiveCallAnalyzer.load();
    classifier = await ScamClassifier.load();
  });

  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({'live_call_consent_v1': true});
    tmp = Directory.systemTemp.createTempSync('live_test');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  late FakeAudio audio;
  late FakeRecorder rec;
  late FakeApi api;
  late List<bool> wake;

  Future<void> settle(WidgetTester t, {int steps = 6, Duration step = const Duration(milliseconds: 100)}) async {
    for (var i = 0; i < steps; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
      await t.pump(step);
    }
  }

  Future<void> pumpScreen(WidgetTester t, {FakeApi? withApi, String lang = 'en'}) async {
    t.view.physicalSize = const Size(1080, 4000);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    audio = FakeAudio();
    rec = FakeRecorder();
    api = withApi ?? FakeApi();
    wake = [];
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          demoAudioProvider.overrideWithValue(audio),
          chunkRecorderProvider.overrideWithValue(rec),
          liveTempDirProvider.overrideWithValue(() async => tmp),
          wakelockProvider.overrideWithValue((on) => wake.add(on)),
          liveCallAnalyzerProvider.overrideWith((ref) async => analyzer),
          scamClassifierProvider.overrideWith((ref) async => classifier),
          localeProvider.overrideWith((ref) => LocaleNotifier(lang)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: [AppLocalizationsDelegate(lang)],
          home: const LiveCallScreen(chunk: Duration(seconds: 1)),
        ),
      ),
    );
    await settle(t);
  }

  String status(WidgetTester t) => t.widget<Text>(find.byKey(const Key('live_status'))).data!;
  String risk(WidgetTester t) => t.widget<Text>(find.byKey(const Key('live_risk'))).data!;
  String transcript(WidgetTester t) {
    final f = find.byKey(const Key('live_transcript_text'));
    return f.evaluate().isEmpty ? '' : t.widget<Text>(f).textSpan!.toPlainText();
  }

  List<String> highlighted(WidgetTester t) {
    final span = t.widget<Text>(find.byKey(const Key('live_transcript_text'))).textSpan! as TextSpan;
    return [
      for (final c in span.children!.cast<TextSpan>())
        if (c.style?.backgroundColor != null) c.text!,
    ];
  }

  Future<void> dismissAlertIfShown(WidgetTester t) async {
    if (find.byKey(const Key('live_alert')).evaluate().isNotEmpty) {
      await t.tap(find.byKey(const Key('live_alert_dismiss')));
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  /// testWidgets that also disposes the screen and lets pending chunk/clip timers run out.
  void testLive(String name, Future<void> Function(WidgetTester t) body) {
    testWidgets(name, (t) async {
      await body(t);
      await t.pumpWidget(const SizedBox());
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(seconds: 1));
      }
    });
  }

  // ---- bundled assets -------------------------------------------------------------------

  test('every demo line has its own audio clip, and nothing extra', () {
    for (final id in kLiveDemoScripts) {
      final n = scriptLines(id).length;
      expect(n, greaterThanOrEqualTo(6), reason: id);
      for (var i = 1; i <= n; i++) {
        final f = File(liveDemoClipAsset(id, i));
        expect(f.existsSync(), isTrue, reason: f.path);
        expect(f.lengthSync(), greaterThan(4000), reason: '${f.path} looks empty');
      }
      expect(File(liveDemoClipAsset(id, n + 1)).existsSync(), isFalse, reason: '$id has an extra clip');
    }
  });

  test('pubspec bundles the demo text and audio folders', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/samples/live/'));
    expect(pubspec, contains('- assets/samples/live/audio/'));
  });

  group('combinedRisk (phrase rules + text classifier)', () {
    test('classifier only escalates medium, never raises low', () {
      expect(combinedRisk(const LiveCallState('low', 0, [], [], 'x'), 0.99), 'low');
      expect(combinedRisk(const LiveCallState('medium', 0.5, [], [], 'x'), 0.5), 'medium');
      expect(combinedRisk(const LiveCallState('medium', 0.5, [], [], 'x'), 0.9), 'high');
      expect(combinedRisk(const LiveCallState('high', 1, [], [], 'x'), null), 'high');
    });

    test('genuine demo calls stay low even with the classifier', () {
      for (final id in kLiveDemoScripts.where((s) => s.startsWith('genuine'))) {
        analyzer.reset();
        for (final l in scriptLines(id)) {
          final s = analyzer.add(l);
          expect(combinedRisk(s, classifier.classify(s.transcript).score), 'low', reason: '$id: $l');
        }
      }
    });
  });

  // ---- consent ---------------------------------------------------------------------------

  testLive('Live Call Guard shows the recording alerts bell and section with saved analyses', (t) async {
    final id = await t.runAsync(() async {
      final store = await AutoAnalyzeStore.open();
      return store.saveResult('/rec/Call_1.m4a',
          CallTimeline(await CallAnalyzer.load(), analyzer).analyze(scriptLines('scam_digital_arrest').join('\n')));
    });
    await pumpScreen(t);
    expect(find.byKey(const Key('inbox_button')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('inbox_badge'))).data, '1');
    expect(find.byKey(const Key('inbox_section')), findsOneWidget);
    expect(find.byKey(Key('inbox_item_$id')), findsOneWidget);
    expect(find.byKey(Key('inbox_new_$id')), findsOneWidget);
  });

  testLive('consent must be accepted once before anything else', (t) async {
    SharedPreferences.setMockInitialValues({});
    await pumpScreen(t);
    expect(find.byKey(const Key('live_consent')), findsOneWidget);
    expect(find.byKey(const Key('live_start')), findsNothing);
    await t.tap(find.byKey(const Key('live_agree')));
    await settle(t);
    expect(find.byKey(const Key('live_start')), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool('live_call_consent_v1'), isTrue);
  });

  // ---- demo mode -------------------------------------------------------------------------

  for (final id in kLiveDemoScripts) {
    final scam = id.startsWith('scam');
    testLive('demo $id: plays every clip in order, shows the transcript, ${scam ? 'alerts HIGH' : 'stays LOW'}',
        (t) async {
      await pumpScreen(t);
      expect(find.text('Choose a sample call and press Play.'), findsOneWidget);
      await t.tap(find.byKey(Key('live_demo_$id')));
      await settle(t, steps: 2);
      await t.tap(find.byKey(const Key('live_start')));
      await settle(t, steps: 3);
      expect(status(t), startsWith('Playing sample… line 1 of'));
      expect(find.byKey(const Key('live_stop')), findsOneWidget);
      expect(wake, contains(true));

      final lines = scriptLines(id);
      var alerts = 0;
      var highAt = -1;
      for (var step = 0; step < 40 && status(t) != 'Finished.'; step++) {
        await settle(t, steps: 1, step: const Duration(milliseconds: 500));
        if (find.byKey(const Key('live_alert')).evaluate().isNotEmpty) {
          alerts++;
          if (highAt < 0) highAt = audio.played.length;
          expect(find.text('Possible scam'), findsOneWidget);
          await dismissAlertIfShown(t);
        }
      }
      expect(status(t), 'Finished.');
      expect(audio.played, [for (var i = 1; i <= lines.length; i++) liveDemoClipAsset(id, i)]);
      expect(transcript(t), lines.join(' '));
      expect(find.byKey(const Key('live_start')), findsOneWidget);
      expect(find.text('Play again'), findsOneWidget);
      expect(wake.last, isFalse);
      if (scam) {
        expect(risk(t), 'HIGH RISK');
        expect(alerts, 1, reason: 'alert exactly once per call');
        expect(highAt, lessThanOrEqualTo(lines.length ~/ 2), reason: 'warned within the first half');
        expect(highlighted(t), isNotEmpty);
        expect(t.widget<Text>(find.byKey(const Key('live_type'))).data, startsWith('Looks like: '));
      } else {
        expect(risk(t), 'LOW RISK');
        expect(alerts, 0);
        expect(t.widget<Text>(find.byKey(const Key('live_type'))).data, 'No scam signs yet');
      }
      expect(find.byKey(const Key('live_ml')), scam ? findsOneWidget : findsNothing,
          reason: 'classifier score shown only once the call is suspicious');
    });
  }

  testLive('demo: stop halts playback; replay starts clean from line 1', (t) async {
    await pumpScreen(t);
    await t.tap(find.byKey(const Key('live_start')));
    await settle(t, steps: 3);
    await settle(t, steps: 3, step: const Duration(milliseconds: 500)); // ~2 lines
    await dismissAlertIfShown(t);
    final before = transcript(t);
    expect(before, isNotEmpty);
    await t.tap(find.byKey(const Key('live_stop')));
    await settle(t);
    expect(status(t), 'Finished.');
    expect(audio.stops, greaterThan(0));
    final played = audio.played.length;
    await settle(t, steps: 10, step: const Duration(milliseconds: 500));
    expect(audio.played.length, played, reason: 'nothing plays after Stop');
    expect(transcript(t), before, reason: 'no text added after Stop');

    await t.tap(find.byKey(const Key('live_start'))); // "Play again"
    await settle(t, steps: 2);
    expect(transcript(t), '', reason: 'replay clears the previous call');
    expect(risk(t), 'LOW RISK');
    expect(audio.played.last, liveDemoClipAsset(kLiveDemoScripts.first, 1));
  });

  testLive('demo: switching sample while playing stops it and resets the screen', (t) async {
    await pumpScreen(t);
    await t.tap(find.byKey(const Key('live_start')));
    await settle(t, steps: 3);
    await settle(t, steps: 4, step: const Duration(milliseconds: 500));
    await dismissAlertIfShown(t);
    await t.tap(find.byKey(const Key('live_demo_genuine_family_call')));
    await settle(t);
    expect(status(t), 'Choose a sample call and press Play.');
    expect(transcript(t), '');
    expect(risk(t), 'LOW RISK');
    final n = audio.played.length;
    await settle(t, steps: 6, step: const Duration(milliseconds: 500));
    expect(audio.played.length, n);
    await t.tap(find.byKey(const Key('live_start')));
    await settle(t, steps: 2);
    expect(audio.played.last, liveDemoClipAsset('genuine_family_call', 1));
  });

  testLive('demo: if sound cannot play, it says so and still runs on text', (t) async {
    await pumpScreen(t);
    audio.fail = true;
    await t.tap(find.byKey(const Key('live_demo_scam_courier_customs')));
    await settle(t, steps: 2);
    await t.tap(find.byKey(const Key('live_start')));
    for (var i = 0; i < 30 && status(t) != 'Finished.'; i++) {
      await settle(t, steps: 1, step: const Duration(milliseconds: 500));
      await dismissAlertIfShown(t);
    }
    expect(find.byKey(const Key('live_audio_failed')), findsOneWidget);
    expect(status(t), 'Finished.');
    expect(risk(t), 'HIGH RISK');
    expect(transcript(t), scriptLines('scam_courier_customs').join(' '));
  });

  testLive('alert vibrates; Report button stops and opens the report screen', (t) async {
    final haptics = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method.startsWith('HapticFeedback')) haptics.add(call.method);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpScreen(t);
    await t.tap(find.byKey(const Key('live_start')));
    for (var i = 0; i < 20 && find.byKey(const Key('live_alert')).evaluate().isEmpty; i++) {
      await settle(t, steps: 1, step: const Duration(milliseconds: 500));
    }
    expect(find.byKey(const Key('live_alert')), findsOneWidget);
    expect(haptics, containsAll(['HapticFeedback.vibrate']));
    await t.tap(find.byKey(const Key('live_alert_report')));
    await settle(t);
    expect(find.byType(ReportScreen), findsOneWidget);
  });

  // ---- microphone mode -------------------------------------------------------------------

  Future<void> switchToMic(WidgetTester t) async {
    await t.tap(find.byKey(const Key('live_demo_switch')));
    await settle(t, steps: 2);
    expect(find.byKey(const Key('live_server')), findsOneWidget);
  }

  testLive('mic: server unreachable -> clear error with address and a Demo button that works', (t) async {
    await pumpScreen(t, withApi: FakeApi(reachable: false));
    await switchToMic(t);
    await t.tap(find.byKey(const Key('live_start')));
    await settle(t);
    expect(find.byKey(const Key('live_error_live_offline')), findsOneWidget);
    expect(find.textContaining('http://192.168.1.5:8000'), findsWidgets);
    expect(find.text('Server not reachable'), findsOneWidget);
    expect(rec.started, isEmpty);
    await t.tap(find.byKey(const Key('live_use_demo')));
    await settle(t, steps: 4);
    expect(status(t), startsWith('Playing sample…'));
    expect(audio.played, isNotEmpty);
  });

  testLive('mic: permission refused -> clear error, nothing recorded', (t) async {
    await pumpScreen(t);
    rec.permission = false;
    await switchToMic(t);
    await t.tap(find.byKey(const Key('live_start')));
    await settle(t);
    expect(find.byKey(const Key('live_error_live_mic_denied')), findsOneWidget);
    expect(rec.started, isEmpty);
    expect(wake.last, isFalse);
  });

  testLive('mic: recorder failure -> clear error', (t) async {
    await pumpScreen(t);
    rec.failStart = true;
    await switchToMic(t);
    await t.tap(find.byKey(const Key('live_start')));
    await settle(t);
    expect(find.byKey(const Key('live_error_live_mic_error')), findsOneWidget);
  });

  testLive('mic: chunks are recorded back to back, uploaded, deleted, analysed; stop finishes cleanly',
      (t) async {
    final lines = scriptLines('scam_fake_kyc_otp');
    await pumpScreen(t, withApi: FakeApi(texts: lines));
    await switchToMic(t);
    await t.tap(find.byKey(const Key('live_start')));
    await settle(t, steps: 3);
    expect(status(t), startsWith('Listening… part'));
    expect(find.byKey(const Key('live_level')), findsOneWidget);
    var alerts = 0;
    for (var i = 0; i < 12; i++) {
      await settle(t, steps: 1, step: const Duration(milliseconds: 500));
      if (find.byKey(const Key('live_alert')).evaluate().isNotEmpty) {
        alerts++;
        await dismissAlertIfShown(t);
      }
    }
    expect(rec.started.length, greaterThanOrEqualTo(4));
    expect(api.uploaded.length, greaterThanOrEqualTo(3));
    expect(api.existedAtUpload.every((e) => e), isTrue, reason: 'file exists while uploading');
    expect(api.langs.toSet(), {'auto'}, reason: 'English UI -> auto language');
    for (final p in api.uploaded) {
      expect(File(p).existsSync(), isFalse, reason: 'chunk deleted after upload: $p');
    }
    expect(transcript(t), startsWith(lines.first));
    expect(risk(t), 'HIGH RISK');
    expect(alerts, 1);

    await t.tap(find.byKey(const Key('live_stop')));
    await settle(t, steps: 10);
    expect(status(t), 'Finished.');
    expect(wake.last, isFalse);
    expect(tmp.listSync(), isEmpty, reason: 'no audio left on the phone');
    final n = rec.started.length;
    await settle(t, steps: 6, step: const Duration(milliseconds: 500));
    expect(rec.started.length, n, reason: 'no recording after Stop');
  });

  testLive('mic: Hindi UI asks the server for Hindi', (t) async {
    await pumpScreen(t, withApi: FakeApi(texts: ['नमस्ते']), lang: 'hi');
    await switchToMic(t);
    await t.tap(find.byKey(const Key('live_start')));
    await settle(t, steps: 3);
    await settle(t, steps: 4, step: const Duration(milliseconds: 500));
    expect(api.langs.first, 'hi');
  });

  testLive('mic: silent chunks are not uploaded and a hint explains why', (t) async {
    await pumpScreen(t);
    rec.db = -90;
    await switchToMic(t);
    await t.tap(find.byKey(const Key('live_start')));
    await settle(t, steps: 3);
    await settle(t, steps: 8, step: const Duration(milliseconds: 500));
    expect(api.uploaded, isEmpty);
    expect(find.byKey(const Key('live_silent_hint')), findsOneWidget);
    await t.tap(find.byKey(const Key('live_stop')));
    await settle(t);
    expect(tmp.listSync(), isEmpty, reason: 'silent chunks are deleted');
  });

  testLive('mic: one server error is reported and listening continues; repeated errors stop', (t) async {
    final a = FakeApi(texts: ['', 'hello', 'hello'])
      ..error = const ApiException(500, 'boom')
      ..failTimes = 1;
    await pumpScreen(t, withApi: a);
    await switchToMic(t);
    await t.tap(find.byKey(const Key('live_start')));
    await settle(t, steps: 3);
    await settle(t, steps: 6, step: const Duration(milliseconds: 500));
    expect(find.byKey(const Key('live_chunk_failed')), findsOneWidget);
    expect(status(t), startsWith('Listening…'));
    await t.tap(find.byKey(const Key('live_stop')));
    await settle(t, steps: 6);

    a
      ..calls = 0
      ..failTimes = 99;
    await t.tap(find.byKey(const Key('live_start')));
    await settle(t, steps: 3);
    await settle(t, steps: 10, step: const Duration(milliseconds: 500));
    expect(find.byKey(const Key('live_error_live_transcribe_failed')), findsOneWidget);
    expect(find.textContaining('HTTP 500'), findsWidgets);
    final n = rec.started.length;
    await settle(t, steps: 4, step: const Duration(milliseconds: 500));
    expect(rec.started.length, n, reason: 'recording stopped after repeated failures');
  });

  testLive('mic: server lost mid-call -> offline error, recording stops', (t) async {
    final a = FakeApi()
      ..error = const ApiOfflineException('down')
      ..failTimes = 99;
    await pumpScreen(t, withApi: a);
    await switchToMic(t);
    await t.tap(find.byKey(const Key('live_start')));
    await settle(t, steps: 3);
    await settle(t, steps: 6, step: const Duration(milliseconds: 500));
    expect(find.byKey(const Key('live_error_live_offline')), findsOneWidget);
    final n = rec.started.length;
    await settle(t, steps: 4, step: const Duration(milliseconds: 500));
    expect(rec.started.length, n);
    expect(tmp.listSync(), isEmpty);
  });

  testLive('server address: emulator hint, change and test', (t) async {
    final a = FakeApi(reachable: false);
    await pumpScreen(t, withApi: a);
    await a.setBaseUrl('http://10.0.2.2:8000');
    await switchToMic(t);
    // Re-open to load the saved address.
    await t.tap(find.byKey(const Key('live_server_test')));
    await settle(t);
    expect(find.text('http://10.0.2.2:8000'), findsOneWidget);
    expect(find.textContaining('only work on the Android emulator'), findsOneWidget);
    expect(find.text('Server not reachable'), findsOneWidget);

    a.reachable = true;
    await t.tap(find.byKey(const Key('live_server_edit')));
    await settle(t, steps: 3);
    await t.enterText(find.byKey(const Key('live_server_field')), ' 172.16.203.18:8000/ ');
    await t.tap(find.byKey(const Key('live_server_save')));
    await settle(t);
    expect(await a.getBaseUrl(), 'http://172.16.203.18:8000');
    expect(find.text('http://172.16.203.18:8000'), findsOneWidget);
    expect(find.text('Server connected'), findsOneWidget);
    expect(find.textContaining('only work on the Android emulator'), findsNothing);
  });
}
