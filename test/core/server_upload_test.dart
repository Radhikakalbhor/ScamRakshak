import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scam_rakshak/core/api_client.dart';
import 'package:scam_rakshak/core/providers.dart';
import 'package:scam_rakshak/core/strings.dart';
import 'package:scam_rakshak/core/theme.dart';
import 'package:scam_rakshak/core/widgets/server_settings.dart';
import 'package:scam_rakshak/engine/call_analyzer.dart';
import 'package:scam_rakshak/features/call_detector/call_detector_screen.dart';

/// Fake server for the shared upload routine.
class _Api extends ApiClient {
  bool reachable;
  String base;
  Completer<Map>? hold; // when set, the upload never finishes until completed
  int uploads = 0;
  final stagesSeen = <String>[];
  _Api({this.reachable = true, this.base = 'http://192.168.1.5:8000'});

  @override
  Future<String> getBaseUrl() async => base;
  @override
  Future<bool> isReachable({Duration timeout = const Duration(seconds: 4)}) async => reachable;
  @override
  Future<Map> transcribeUpload(File audio,
      {void Function()? onSent, UploadCancel? cancel, Duration timeout = const Duration(minutes: 5)}) async {
    uploads++;
    onSent?.call();
    if (hold != null) return hold!.future;
    return {'text': 'aapka KYC pending hai, OTP bataiye turant', 'lang': 'hi'};
  }
}

final _analyzer = CallAnalyzer.fromJson(
    jsonDecode(File('assets/rules/call_rules.json').readAsStringSync()) as Map<String, dynamic>);

Widget _app(Widget home, ApiClient api) => ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        callAnalyzerProvider.overrideWith((ref) async => _analyzer),
      ],
      child: MaterialApp(theme: AppTheme.lightTheme, localizationsDelegates: [AppLocalizationsDelegate('en')], home: home),
    );

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

void main() {
  group('server address resolution', () {
    const cloud = 'https://scamrakshak-backend.onrender.com';
    const laptop = 'http://172.16.201.41:8000';

    test('the production (Render) address is the built-in default', () {
      expect(ApiClient.productionBaseUrl, cloud);
      expect(ApiClient.resolveBaseUrl(buildTime: cloud, emulator: false), cloud);
      expect(ApiClient.resolveBaseUrl(buildTime: cloud, emulator: true), cloud);
    });

    test('an address saved under the same build wins (kept across reinstalls of that build)', () {
      expect(ApiClient.resolveBaseUrl(saved: 'http://192.168.1.9:8000', savedForBuild: cloud, buildTime: cloud, emulator: false),
          'http://192.168.1.9:8000');
    });

    test('a phone that saved the old laptop address moves to the new build server', () {
      // Saved by the laptop build (the mark = the laptop build address), or by an older app without the mark.
      expect(ApiClient.resolveBaseUrl(saved: laptop, savedForBuild: laptop, buildTime: cloud, emulator: false), cloud);
      expect(ApiClient.resolveBaseUrl(saved: laptop, savedForBuild: null, buildTime: cloud, emulator: false), cloud);
    });

    test('a real phone never gets 10.0.2.2; the emulator alias is used only when nothing else is set', () {
      expect(ApiClient.resolveBaseUrl(saved: null, buildTime: '', emulator: false), '');
      expect(ApiClient.resolveBaseUrl(saved: 'http://10.0.2.2:8000', savedForBuild: cloud, buildTime: cloud, emulator: false), cloud);
      expect(ApiClient.resolveBaseUrl(saved: null, buildTime: '', emulator: true), ApiClient.emulatorBaseUrl);
      expect(ApiClient.resolveBaseUrl(saved: 'http://10.0.2.2:8000', emulator: true), 'http://10.0.2.2:8000');
    });

    test('USB (adb reverse) 127.0.0.1 is allowed on a real phone; addresses are normalized', () {
      expect(ApiClient.resolveBaseUrl(saved: '127.0.0.1:8000/', savedForBuild: cloud, buildTime: cloud, emulator: false),
          'http://127.0.0.1:8000');
      expect(ApiClient.normalizeBaseUrl(' 192.168.1.5:8000// '), 'http://192.168.1.5:8000');
      expect(ApiClient.normalizeBaseUrl('http://'), '');
    });

    test('getBaseUrl: saved address (marked with this build) persists; an unmarked old one is replaced', () async {
      final old = ApiClient.isEmulator;
      ApiClient.isEmulator = () async => false;
      addTearDown(() => ApiClient.isEmulator = old);
      SharedPreferences.setMockInitialValues({ApiClient.prefKeyBaseUrl: laptop});
      expect(await ApiClient().getBaseUrl(), ApiClient.buildBaseUrl);
      await ApiClient().setBaseUrl('172.16.0.7:8000/');
      // A fresh client (as after reinstalling the same build) sees the saved address.
      expect(await ApiClient().getBaseUrl(), 'http://172.16.0.7:8000');
      SharedPreferences.setMockInitialValues({});
      expect(await ApiClient().getBaseUrl(), ApiClient.buildBaseUrl);
    });
    test('isReachable uses GET /health', () async {
      final seen = <Uri>[];
      final ok = ApiClient(
        baseUrl: 'http://192.168.1.5:8000',
        httpClient: MockClient((r) async {
          seen.add(r.url);
          return http.Response('{"status":"ok"}', 200);
        }),
      );
      expect(await ok.isReachable(), isTrue);
      expect(seen.single.toString(), 'http://192.168.1.5:8000/health');
      final down = ApiClient(baseUrl: 'http://192.168.1.5:8000', httpClient: MockClient((_) async => throw const SocketException('x')));
      expect(await down.isReachable(), isFalse);
    });
  });

  group('picker result handling', () {
    test('every supported call format passes, case-insensitive; others are named', () {
      for (final ext in ['m4a', 'mp3', 'wav', 'amr', 'ogg', 'aac', '3gp', 'opus']) {
        expect(checkPickedAudio(File('/x/Call_1.$ext')), isNull, reason: ext);
      }
      expect(checkPickedAudio(File('/x/CALL.M4A')), isNull);
      expect(checkPickedAudio(null), 'call_no_file');
      expect(checkPickedAudio(File('/x/notes.pdf')), 'call_ext_unsupported');
      expect(checkPickedAudio(File('/x/noext')), 'call_ext_unsupported');
      expect(audioExtension('/a.b/Call.OPUS'), 'opus');
    });

    testWidgets('a picker failure is shown as such (not "no file") and nothing is uploaded', (t) async {
      _tall(t);
      final api = _Api();
      await t.pumpWidget(_app(CallDetectorScreen(pickAudio: () async => throw const AudioPickException('no path')), api));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('call_pick')));
      await t.pumpAndSettle();
      expect(find.textContaining('could not be opened from the picker'), findsOneWidget);
      expect(find.textContaining('No file was chosen'), findsNothing);
      expect(api.uploads, 0);
    });

    testWidgets('an unsupported file is rejected before upload with the supported list', (t) async {
      _tall(t);
      final api = _Api();
      await t.pumpWidget(_app(CallDetectorScreen(pickAudio: () async => File('/x/song.flac2')), api));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('call_pick')));
      await t.pumpAndSettle();
      expect(find.textContaining('(.flac2) is not a supported call recording'), findsOneWidget);
      expect(find.textContaining('opus'), findsWidgets);
      expect(api.uploads, 0);
    });
  });

  group('shared upload routine', () {
    test('unreachable server: fails after the /health check, no upload', () async {
      final api = _Api(reachable: false);
      final stages = <UploadStage>[];
      await expectLater(
        transcribeWithChecks(api, File('x.m4a'), onStage: stages.add),
        throwsA(isA<ApiOfflineException>()),
      );
      expect(api.uploads, 0);
      expect(stages, [UploadStage.checking]);
    });

    test('no address set: clear error, no network', () async {
      final api = _Api(base: '');
      await expectLater(transcribeWithChecks(api, File('x.m4a')), throwsA(isA<ApiOfflineException>()));
      expect(api.uploads, 0);
    });

    test('stages run checking -> uploading -> transcribing', () async {
      final api = _Api();
      final stages = <UploadStage>[];
      final r = await transcribeWithChecks(api, File('x.m4a'), onStage: stages.add);
      expect(r['text'], contains('KYC'));
      expect(stages, [UploadStage.checking, UploadStage.uploading, UploadStage.transcribing]);
    });

    test('cancel stops a hanging upload at once', () async {
      final api = _Api()..hold = Completer<Map>();
      final cancel = UploadCancel();
      final f = transcribeWithChecks(api, File('x.m4a'), cancel: cancel);
      await Future<void>.delayed(Duration.zero);
      cancel.cancel();
      await expectLater(f, throwsA(isA<UploadCancelledException>()));
    });
  });

  group('Check Call screen', () {
    testWidgets('unreachable server: friendly error with the address, spinner ends', (t) async {
      _tall(t);
      final api = _Api(reachable: false);
      await t.pumpWidget(_app(CallDetectorScreen(pickAudio: () async => File('/x/Call.amr')), api));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('call_pick')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('call_error')), findsOneWidget);
      expect(find.textContaining('192.168.1.5:8000'), findsWidgets);
      expect(find.byKey(const Key('call_stage')), findsNothing);
      expect(api.uploads, 0);
    });

    testWidgets('Cancel during transcription ends the spinner and says Cancelled', (t) async {
      _tall(t);
      final api = _Api()..hold = Completer<Map>();
      await t.pumpWidget(_app(CallDetectorScreen(pickAudio: () async => File('/x/Call.opus')), api));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('call_pick')));
      await t.pump();
      await t.pump();
      expect(find.textContaining('Turning the call into text'), findsOneWidget);
      await t.tap(find.byKey(const Key('call_cancel')));
      await t.pumpAndSettle();
      expect(find.textContaining('Cancelled.'), findsOneWidget);
      expect(find.byKey(const Key('call_stage')), findsNothing);
      expect(find.byKey(const Key('call_risk')), findsNothing);
    });

    testWidgets('a recording uploads and the transcript is analysed', (t) async {
      _tall(t);
      final api = _Api();
      await t.pumpWidget(_app(CallDetectorScreen(pickAudio: () async => File('/x/Call.m4a')), api));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('call_pick')));
      await t.pumpAndSettle();
      expect(api.uploads, 1);
      expect(find.byKey(const Key('call_risk')), findsOneWidget);
    });
  });

  group('Server settings sheet', () {
    testWidgets('chip opens the sheet with version and address; Save persists, Test checks /health', (t) async {
      _tall(t);
      SharedPreferences.setMockInitialValues({});
      final old = AppInfo.loader;
      AppInfo.loader = () async => const AppInfo('1.0.0', '2015', false);
      addTearDown(() => AppInfo.loader = old);
      final probed = <String>[];
      final api = ApiClient();
      await t.pumpWidget(ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          serverProbeProvider.overrideWithValue((url) async {
            probed.add(url);
            return true;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: [AppLocalizationsDelegate('en')],
          home: const Scaffold(body: Center(child: ServerStatusChip())),
        ),
      ));
      await t.pumpAndSettle();
      // Fresh install: the built-in production address (unreachable in tests: no network).
      expect(find.text('Server: not reachable'), findsOneWidget);
      await t.tap(find.byKey(const Key('server_chip')));
      await t.pumpAndSettle();
      expect(find.text('App version: 1.0.0 (build 2015)'), findsOneWidget);
      expect(find.text('Active server: ${ApiClient.buildBaseUrl}'), findsOneWidget);
      await t.enterText(find.byKey(const Key('server_field')), '172.16.201.41:8000');
      await t.tap(find.byKey(const Key('server_test')));
      await t.pumpAndSettle();
      expect(probed.last, 'http://172.16.201.41:8000');
      expect(find.textContaining('Connected'), findsOneWidget);
      await t.tap(find.byKey(const Key('server_save')));
      await t.pumpAndSettle();
      expect(find.text('Active server: http://172.16.201.41:8000'), findsOneWidget);
      expect((await SharedPreferences.getInstance()).getString(ApiClient.prefKeyBaseUrl), 'http://172.16.201.41:8000');
    });
  });
}
