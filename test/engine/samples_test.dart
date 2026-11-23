import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:scam_rakshak/engine/call_analyzer.dart';
import 'package:scam_rakshak/features/call_detector/call_highlight.dart';

/// Expected outcome for every bundled sample transcript: (risk, main scam script or null).
const _expected = <String, (String, String?)>{
  // existing samples
  'bank_kyc_otp_hinglish.txt': ('high', 'fake_kyc'),
  'courier_customs_en.txt': ('high', 'courier_customs'),
  'digital_arrest_hi.txt': ('high', 'digital_arrest'),
  'genuine_bank_call_en.txt': ('low', null),
  'upi_collect_hinglish.txt': ('high', 'upi_collect'),
  // added samples
  'lottery_kbc_hinglish.txt': ('high', 'lottery_prize'),
  'anydesk_refund_en.txt': ('high', 'remote_access'),
  // reported real-world calls (caller asks for OTP / KYC number / bank details)
  'bank_otp_request_1_en.txt': ('high', 'otp_request'),
  'bank_otp_request_2_en.txt': ('high', 'otp_request'),
  'bank_otp_request_3_en.txt': ('high', 'details_request'),
  'bank_otp_request_4_en.txt': ('high', 'otp_request'),
  'loan_app_threat_hi.txt': ('high', 'loan_threat'),
  'fake_kyc_hi.txt': ('high', 'fake_kyc'),
  'customs_arrest_hinglish.txt': ('high', 'digital_arrest'),
  'genuine_delivery_hinglish.txt': ('low', null),
  'genuine_bank_alert_hi.txt': ('low', null),
  'genuine_family_call_hinglish.txt': ('low', null),
};

void main() {
  late CallAnalyzer a;
  late Map<String, String> files;

  setUpAll(() {
    a = CallAnalyzer.fromJson(
      jsonDecode(File('assets/rules/call_rules.json').readAsStringSync()) as Map<String, dynamic>,
    );
    files = {
      for (final f in Directory('assets/samples').listSync().whereType<File>().where((f) => f.path.endsWith('.txt')))
        f.uri.pathSegments.last: f.readAsStringSync(),
    };
  });

  test('there are 17 samples and every one has an expectation', () {
    expect(files.keys.toSet(), _expected.keys.toSet());
  });

  test('samples mix English, Devanagari Hindi and Hinglish', () {
    final deva = RegExp(r'[ऀ-ॿ]');
    expect(files.values.where(deva.hasMatch), hasLength(greaterThanOrEqualTo(3)));
    expect(files.values.where((t) => !deva.hasMatch(t)), hasLength(greaterThanOrEqualTo(3)));
  });

  _expected.forEach((name, exp) {
    test('$name -> ${exp.$1} risk${exp.$2 == null ? '' : ', ${exp.$2}'}', () {
      final s = a.score(files[name]!);
      expect(s.result.risk, exp.$1, reason: 'score ${s.byType}');
      if (exp.$2 != null) expect(mainScriptType(s.result), exp.$2, reason: 'score ${s.byType}');
      if (exp.$1 == 'low') expect(s.total, lessThan(a.mediumLevel));
    });
  });

  test('every matched phrase can be found in its transcript (for highlighting)', () {
    files.forEach((name, text) {
      for (final m in a.analyze(text).matches) {
        expect(text.toLowerCase(), contains(m.phrase), reason: '$name: ${m.phrase}');
      }
    });
  });
}
