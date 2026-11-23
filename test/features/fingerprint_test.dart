import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scam_rakshak/core/api_client.dart';
import 'package:scam_rakshak/core/providers.dart';
import 'package:scam_rakshak/engine/call_analyzer.dart';
import 'package:scam_rakshak/engine/scam_classifier.dart';
import 'package:scam_rakshak/features/message_detector/message_detector_screen.dart';
import 'package:scam_rakshak/features/message_detector/message_fingerprint.dart';

Map<String, dynamic> _json(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

class _Api extends ApiClient {
  final sent = <List<String>>[];
  @override
  Future<void> postFingerprint(String fp, String category) async => sent.add([fp, category]);
}

const _scam = 'Dear customer your SBI account KYC is pending and will be blocked today. '
    'Update now at sbi-kyc-help.xyz or call 9876543210 immediately';

void main() {
  group('messageFingerprint', () {
    test('16 hex digits; numbers and links do not change it much; other scams are far away', () {
      final a = messageFingerprint(_scam);
      expect(a, matches(RegExp(r'^[0-9a-f]{16}$')));
      final b = messageFingerprint(_scam.replaceAll('9876543210', '7000112233').replaceAll('sbi-kyc-help.xyz', 'http://k.in/x'));
      expect(fingerprintDistance(a, b), lessThanOrEqualTo(6));
      final c = messageFingerprint('Congratulations! You won 25 lakh in KBC lottery. Pay 12500 registration to claim the prize');
      expect(fingerprintDistance(a, c), greaterThan(12));
      expect(messageFingerprint(_scam), a); // deterministic
    });

    test('does not contain the text', () {
      expect(messageFingerprint('hello').length, 16);
      expect(messageFingerprint(''), '0000000000000000');
    });
  });

  group('opt-in on the message screen', () {
    late ScamClassifier clf;
    late CallAnalyzer rules;
    setUpAll(() {
      clf = ScamClassifier.fromJson(_json('assets/models/scam_model.json'));
      rules = CallAnalyzer.fromJson(_json('assets/rules/call_rules.json'));
    });

    Future<_Api> pump(WidgetTester tester, Map<String, Object> prefs) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(prefs);
      final api = _Api();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          scamClassifierProvider.overrideWith((ref) async => clf),
          callAnalyzerProvider.overrideWith((ref) async => rules),
        ],
        child: const MaterialApp(home: MessageDetectorScreen()),
      ));
      await tester.pumpAndSettle();
      return api;
    }

    Future<void> check(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(const Key('msg_input')), text);
      await tester.tap(find.byKey(const Key('msg_check')));
      await tester.pumpAndSettle();
    }

    testWidgets('off by default: nothing is sent; the switch is offered for scams', (tester) async {
      final api = await pump(tester, {});
      await check(tester, _scam);
      expect(find.byKey(const Key('msg_verdict')), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('msg_fp_optin'))).value, isFalse);
      expect(api.sent, isEmpty);
    });

    testWidgets('turning it on sends only the fingerprint and category, and is remembered', (tester) async {
      final api = await pump(tester, {});
      await check(tester, _scam);
      await tester.tap(find.byKey(const Key('msg_fp_optin')));
      await tester.pumpAndSettle();
      expect(api.sent, hasLength(1));
      expect(api.sent.single[0], messageFingerprint(_scam));
      expect(api.sent.single[1], isNot(contains(' ')));
      expect((await SharedPreferences.getInstance()).getBool(FingerprintOptIn.key), isTrue);

      final api2 = await pump(tester, {FingerprintOptIn.key: true});
      await check(tester, 'Hi, are we meeting at 5 near the bus stand?'); // genuine: nothing sent
      expect(api2.sent, isEmpty);
      await check(tester, _scam);
      expect(api2.sent, hasLength(1));
    });
  });
}
