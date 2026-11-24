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
import 'package:scam_rakshak/core/share_intent.dart';
import 'package:scam_rakshak/engine/call_analyzer.dart';
import 'package:scam_rakshak/engine/scam_classifier.dart';
import 'package:scam_rakshak/features/call_detector/call_detector_screen.dart';
import 'package:scam_rakshak/features/message_detector/message_detector_screen.dart';

Map<String, dynamic> _json(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

class _FakeSource implements ShareSource {
  SharedItem? first;
  void Function(SharedItem)? onItem;
  _FakeSource([this.first]);
  @override
  Future<SharedItem?> initial() async => first;
  @override
  void listen(void Function(SharedItem item) cb) => onItem = cb;
}

class _Api extends ApiClient with _UploadViaTranscribe {
  final uploads = <String>[];
  bool offline = false;
  @override
  Future<Map> transcribe(File audio) async {
    uploads.add(audio.path);
    if (offline) throw const ApiOfflineException('down');
    return {'text': 'Main CBI officer bol raha hu, aapke naam pe parcel me drugs mile hai, digital arrest hoga, OTP batao', 'lang': 'hi'};
  }
}

const _scamText = 'Your SBI account KYC is pending and will be blocked today. Update now at sbi-kyc.xyz/login';

void main() {
  late ScamClassifier clf;
  late CallAnalyzer rules;
  setUpAll(() {
    clf = ScamClassifier.fromJson(_json('assets/models/scam_model.json'));
    rules = CallAnalyzer.fromJson(_json('assets/rules/call_rules.json'));
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SharedItem / channel', () {
    test('parses text, audio and errors; ignores junk', () {
      expect(SharedItem.fromMap({'type': 'text', 'text': '  hi  '})!.text, 'hi');
      expect(SharedItem.fromMap({'type': 'text', 'text': ' '}), isNull);
      final a = SharedItem.fromMap({'type': 'audio', 'path': '/c/x.m4a', 'name': 'Call.m4a'})!;
      expect([a.type, a.path, a.name], ['audio', '/c/x.m4a', 'Call.m4a']);
      expect(SharedItem.fromMap({'type': 'audio_error'})!.type, 'audio_error');
      expect(SharedItem.fromMap('x'), isNull);
      expect(SharedItem.fromMap({'type': 'image'}), isNull);
    });

    testWidgets('cold start asks MainActivity once; shares while open arrive as onShare', (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(ChannelShareSource.channel, (call) async {
        expect(call.method, 'getInitialShare');
        return {'type': 'text', 'text': 'shared at launch'};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(ChannelShareSource.channel, null));
      final src = ChannelShareSource();
      expect((await src.initial())!.text, 'shared at launch');

      final got = <SharedItem>[];
      src.listen(got.add);
      await messenger.handlePlatformMessage(
        ChannelShareSource.channel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('onShare', {'type': 'audio', 'path': '/c/a.mp3'})),
        (_) {},
      );
      expect(got.single.path, '/c/a.mp3');
    });

    test('no Android channel (desktop/tests) means no share', () async {
      expect(await ChannelShareSource().initial(), isNull);
    });
  });

  group('ShareHost routing', () {
    late _Api api;
    Widget app(ShareSource src) {
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const ShareHost(child: Scaffold(body: Text('home')))),
        GoRoute(
            path: '/message',
            builder: (_, s) => MessageDetectorScreen(initialText: s.extra is String ? s.extra as String : null)),
        GoRoute(path: '/call', builder: (_, s) => CallDetectorScreen(initialAudio: s.extra is File ? s.extra as File : null)),
      ]);
      return ProviderScope(
        overrides: [
          shareSourceProvider.overrideWithValue(src),
          apiClientProvider.overrideWithValue(api),
          scamClassifierProvider.overrideWith((ref) async => clf),
          callAnalyzerProvider.overrideWith((ref) async => rules),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
    }

    void tall(WidgetTester t) {
      t.view.physicalSize = const Size(900, 3200);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
    }

    setUp(() => api = _Api());

    testWidgets('cold start with shared text opens Check Message, prefilled and already checked', (tester) async {
      tall(tester);
      await tester.pumpWidget(app(_FakeSource(const SharedItem('text', text: _scamText))));
      await tester.pumpAndSettle();
      expect(find.byType(MessageDetectorScreen), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('msg_input'))).controller!.text, _scamText);
      expect(find.text('SCAM'), findsOneWidget);
    });

    testWidgets('text shared while the app is open also opens Check Message', (tester) async {
      tall(tester);
      final src = _FakeSource();
      await tester.pumpWidget(app(src));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      src.onItem!(const SharedItem('text', text: 'Are we meeting at 5 near the bus stand?'));
      await tester.pumpAndSettle();
      expect(find.text('LOOKS GENUINE'), findsOneWidget);
    });

    testWidgets('shared audio opens Check Call, is analysed at once, and the cache copy is deleted on close',
        (tester) async {
      tall(tester);
      final dir = Directory.systemTemp.createTempSync('sr_share_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final copy = File('${dir.path}${Platform.pathSeparator}shared_1.m4a')..writeAsBytesSync([1, 2, 3]);
      final src = _FakeSource();
      await tester.pumpWidget(app(src));
      await tester.pumpAndSettle();

      src.onItem!(SharedItem('audio', path: copy.path, name: 'Call recording.m4a'));
      await tester.pumpAndSettle();
      expect(find.byType(CallDetectorScreen), findsOneWidget);
      expect(api.uploads, [copy.path]);
      expect(find.byKey(const Key('call_risk')), findsOneWidget);
      expect(find.text('HIGH RISK'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(copy.existsSync(), isFalse);
    });

    testWidgets('shared audio while offline: clear error and a retry button', (tester) async {
      tall(tester);
      final dir = Directory.systemTemp.createTempSync('sr_share_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final copy = File('${dir.path}${Platform.pathSeparator}shared_2.amr')..writeAsBytesSync([1]);
      api.offline = true;
      await tester.pumpWidget(app(_FakeSource(SharedItem('audio', path: copy.path))));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not reach the ScamRakshak server'), findsOneWidget);
      api.offline = false;
      await tester.tap(find.byKey(const Key('call_retry_shared')));
      await tester.pumpAndSettle();
      expect(find.text('HIGH RISK'), findsOneWidget);
      expect(api.uploads, hasLength(2));
    });

    testWidgets('a recording that could not be copied shows a message', (tester) async {
      tall(tester);
      await tester.pumpWidget(app(_FakeSource(const SharedItem('audio_error'))));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be opened'), findsOneWidget);
    });
  });

  test('Android manifest declares the share targets and camera; MainActivity uses the channel', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.intent.action.SEND'));
    expect(manifest, contains('android:mimeType="text/plain"'));
    expect(manifest, contains('android:mimeType="audio/*"'));
    expect(manifest, contains('android.permission.CAMERA'));
    final activity = File('android/app/src/main/kotlin/com/scamrakshak/scam_rakshak/MainActivity.kt').readAsStringSync();
    expect(activity, contains('"scamrakshak/share"'));
    expect(activity, contains('getInitialShare'));
    expect(activity, contains('onShare'));
    expect(File('pubspec.yaml').readAsStringSync(), contains('mobile_scanner: 7.0.1'));
  });
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