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
import 'package:scam_rakshak/engine/scam_classifier.dart';
import 'package:scam_rakshak/features/call_detector/call_detector_screen.dart';
import 'package:scam_rakshak/features/message_detector/message_detector_screen.dart';
import 'package:scam_rakshak/features/report/report_screen.dart';

Map<String, dynamic> _json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

class _OfflineApi extends ApiClient with _UploadViaTranscribe {
  @override
  Future<Map> transcribe(File audio) async => throw const ApiOfflineException('offline');

  @override
  Future<void> postReport(String type, String district) async {}
}

class _StatusApi extends ApiClient with _UploadViaTranscribe {
  final int status;
  _StatusApi(this.status);
  @override
  Future<Map> transcribe(File audio) async => throw ApiException(status, 'x');
}

class _TranscribeApi extends ApiClient with _UploadViaTranscribe {
  @override
  Future<Map> transcribe(File audio) async =>
      {'text': 'Main bank se bol raha hu, aapka KYC pending hai, OTP bataiye turant', 'lang': 'hi'};
}

/// Routes the shared upload routine (transcribeWithChecks) to the fake's transcribe().
mixin _UploadViaTranscribe on ApiClient {
  @override
  Future<bool> isReachable({Duration timeout = const Duration(seconds: 4)}) async => true;
  @override
  Future<String> getBaseUrl() async => 'http://test:8000';
  @override
  Future<Map> transcribeUpload(File audio,
          {void Function()? onSent, UploadCancel? cancel, Duration timeout = const Duration(minutes: 5)}) =>
      transcribe(audio);
}
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  late ScamClassifier clf;
  late CallAnalyzer analyzer;

  setUpAll(() {
    clf = ScamClassifier.fromJson(_json('assets/models/scam_model.json'));
    analyzer = CallAnalyzer.fromJson(_json('assets/rules/call_rules.json'));
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app(Widget home, {ApiClient? api}) => ProviderScope(
        overrides: [
          scamClassifierProvider.overrideWith((ref) async => clf),
          callAnalyzerProvider.overrideWith((ref) async => analyzer),
          if (api != null) apiClientProvider.overrideWithValue(api),
        ],
        child: MaterialApp(home: home),
      );

  group('MessageDetectorScreen', () {
    testWidgets('scam example shows SCAM verdict, reasons, advice and opens Report', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(app(const MessageDetectorScreen(), api: _OfflineApi()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('msg_ex_en')));
      await tester.tap(find.byKey(const Key('msg_check')));
      await tester.pumpAndSettle();

      expect(find.text('SCAM'), findsOneWidget);
      expect(find.textContaining('Confidence:'), findsOneWidget);
      expect(find.byType(Chip), findsWidgets);
      expect(find.text('Do not click any link in this message.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('msg_report')));
      await tester.pumpAndSettle();
      expect(find.byType(ReportScreen), findsOneWidget);
    });

    testWidgets('genuine bank alert shows LOOKS GENUINE without report button', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(app(const MessageDetectorScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('msg_ex_genuine')));
      await tester.tap(find.byKey(const Key('msg_check')));
      await tester.pumpAndSettle();

      expect(find.text('LOOKS GENUINE'), findsOneWidget);
      expect(find.byKey(const Key('msg_report')), findsNothing);
    });

    testWidgets('empty input shows a hint instead of a verdict', (tester) async {
      await tester.pumpWidget(app(const MessageDetectorScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('msg_check')));
      await tester.pump();

      expect(find.text('Please paste or type a message first.'), findsOneWidget);
      expect(find.byKey(const Key('msg_verdict')), findsNothing);
    });

    testWidgets('Check button is fully on screen on a small phone with large text', (tester) async {
      tester.view.physicalSize = const Size(720, 1520); // 360x760 dp, like a budget Vivo/Samsung
      tester.view.devicePixelRatio = 2.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(app(const MessageDetectorScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull); // no RenderFlex overflow
      final check = tester.getRect(find.byKey(const Key('msg_check')));
      expect(check.right, lessThanOrEqualTo(360));
      expect(check.left, greaterThanOrEqualTo(0));
      expect(check.bottom, lessThanOrEqualTo(760));

      await tester.enterText(find.byKey(const Key('msg_input')),
          'Your KYC is pending. Share the OTP now or your account will be blocked today.');
      await tester.tap(find.byKey(const Key('msg_check')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('msg_verdict')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const Key('msg_verdict')), findsOneWidget);
    });

    testWidgets('Paste button checks the pasted message straight away', (tester) async {
      _tallView(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return {'text': 'Your KYC is pending. Share the OTP now or your account will be blocked today.'};
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(app(const MessageDetectorScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('msg_paste')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('msg_verdict')), findsOneWidget);
    });
  });

  group('CallDetectorScreen', () {
    test('picker lists every call-recording format the backend accepts', () {
      expect(kCallAudioExtensions, containsAll(['m4a', 'mp3', 'wav', 'amr', 'ogg']));
    });

    testWidgets('says the backend is needed; unsupported file and server-starting errors are named', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(app(CallDetectorScreen(pickAudio: () async => File('x.xyz')), api: _StatusApi(400)));
      await tester.pumpAndSettle();
      expect(find.textContaining('needs the ScamRakshak server'), findsOneWidget);
      expect(find.textContaining('amr'), findsOneWidget);

      await tester.tap(find.byKey(const Key('call_pick')));
      await tester.pumpAndSettle();
      // Checked on the phone before any upload.
      expect(find.textContaining('(.xyz) is not a supported call recording'), findsOneWidget);

      // A supported extension the server still cannot read.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(CallDetectorScreen(pickAudio: () async => File('x.opus')), api: _StatusApi(400)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('call_pick')));
      await tester.pumpAndSettle();
      expect(find.textContaining('This file type cannot be read'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(CallDetectorScreen(pickAudio: () async => File('x.amr')), api: _StatusApi(503)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('call_pick')));
      await tester.pumpAndSettle();
      expect(find.textContaining('still starting up'), findsOneWidget);
    });

    testWidgets('backend offline shows friendly message suggesting samples', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(app(CallDetectorScreen(pickAudio: () async => File('x.mp3')), api: _OfflineApi()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('call_pick')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('call_error')), findsOneWidget);
      expect(find.textContaining('Could not reach the ScamRakshak server'), findsOneWidget);
      expect(find.byKey(const Key('call_risk')), findsNothing);
    });

    testWidgets('transcribed call is analyzed, highlighted and can be reported', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(app(CallDetectorScreen(pickAudio: () async => File('x.mp3')), api: _TranscribeApi()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('call_pick')));
      await tester.pumpAndSettle();

      expect(find.text('HIGH RISK'), findsOneWidget);
      expect(find.textContaining('Looks like:'), findsOneWidget);
      final rich = tester.widget<Text>(find.byKey(const Key('call_transcript')));
      final spans = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans.where((s) => s.style?.backgroundColor != null).map((s) => s.text!.toLowerCase()),
          containsAll(['kyc', 'otp bataiye']));

      await tester.tap(find.byKey(const Key('call_report')));
      await tester.pumpAndSettle();
      expect(find.byType(ReportScreen), findsOneWidget);
    });

    testWidgets('cancelled file pick shows no-file message', (tester) async {
      await tester.pumpWidget(app(CallDetectorScreen(pickAudio: () async => null), api: _OfflineApi()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('call_pick')));
      await tester.pumpAndSettle();
      expect(find.text('No file was chosen.'), findsOneWidget);
    });

    testWidgets('offline sample chips are listed from assets/samples', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(app(const CallDetectorScreen(showSamples: true)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();

      final n = Directory('assets/samples').listSync().where((f) => f.path.endsWith('.txt')).length;
      expect(find.byKey(Key('call_sample_${n - 1}')), findsOneWidget);
      expect(find.byKey(Key('call_sample_$n')), findsNothing);
    });
  });
}
