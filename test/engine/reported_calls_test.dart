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
import 'package:scam_rakshak/engine/models.dart';
import 'package:scam_rakshak/features/call_detector/call_detector_screen.dart';
import 'package:scam_rakshak/features/call_detector/call_highlight.dart';
import 'package:scam_rakshak/features/call_detector/call_timeline.dart';
import 'package:scam_rakshak/features/call_detector/call_triggers.dart';

Map<String, dynamic> _rules() => jsonDecode(File('assets/rules/call_rules.json').readAsStringSync()) as Map<String, dynamic>;

/// The four reported transcripts, verbatim.
const kReportedCalls = [
  'I am from a bank. Please give me your 6-digit OTP and bank KYC number.',
  'Can you give me the OTP and your bank KYC number to update your bank statement?',
  'I need your OTP to update your bank details/passbook.',
  'I am Aditi from Absara Bank ... you will be having an OTP. Please give me the OTP and your bank KYC number.',
];

/// The app's three analysis entry points for a transcript.
/// - Check Call screen (file pick / shared recording / sample): CallAnalyzer.analyze
/// - Auto-analyze + recording result + full-screen warning: CallTimeline.analyze
/// - Live Call Guard: LiveCallAnalyzer.add per chunk (risk shown = combinedRisk, which only escalates)
({CallResult check, CallTimelineResult auto, LiveCallState live}) _all(String t) {
  final live = LiveCallAnalyzer.fromJson(_rules());
  var st = LiveCallState.empty;
  for (final s in CallTimeline.sentences(t)) {
    st = live.add(s);
  }
  return (
    check: CallAnalyzer.fromJson(_rules()).analyze(t),
    auto: CallTimeline(CallAnalyzer.fromJson(_rules()), LiveCallAnalyzer.fromJson(_rules())).analyze(t),
    live: st,
  );
}

/// Shown percentage must agree with the risk band on every path.
void _consistent(String risk, double score, String where) {
  final ok = switch (risk) {
    'high' => score >= 0.8,
    'medium' => score >= 0.5 && score < 0.96,
    _ => score < 0.5,
  };
  expect(ok, isTrue, reason: '$where: $risk with ${(score * 100).round()}%');
}

void _expectRisk(String t, String risk, {List<String> triggers = const []}) {
  final r = _all(t);
  expect(r.check.risk, risk, reason: 'Check Call: $t ${r.check.matches.map((m) => m.phrase).toList()}');
  expect(r.auto.risk, risk, reason: 'Auto-analyze: $t ${r.auto.result.matches.map((m) => m.phrase).toList()}');
  expect(r.live.risk, risk, reason: 'Live: $t ${r.live.matches.map((m) => m.phrase).toList()}');
  _consistent(r.auto.risk, r.auto.score, 'auto');
  _consistent(r.live.risk, r.live.score, 'live');
  for (final tr in triggers) {
    for (final (name, ms) in [('check', r.check.matches), ('auto', r.auto.result.matches), ('live', r.live.matches)]) {
      expect(ms.any((m) => m.phrase.contains(tr)), isTrue, reason: '$name trigger "$tr" in ${ms.map((m) => m.phrase)}');
    }
  }
}

void main() {
  test('trace: before/after on every entry point', () {
    for (final t in kReportedCalls) {
      final r = _all(t);
      // ignore: avoid_print
      print('"$t"\n  CheckCall=${r.check.risk} Auto=${r.auto.risk} ${(r.auto.score * 100).round()}% '
          'Live=${r.live.risk} ${(r.live.score * 100).round()}% triggers=${r.auto.result.matches.map((m) => m.phrase).toList()}');
    }
  });

  group('reported transcripts are HIGH on every entry point', () {
    test('1', () => _expectRisk(kReportedCalls[0], 'high', triggers: ['otp', 'kyc number', 'bank']));
    test('2', () => _expectRisk(kReportedCalls[1], 'high', triggers: ['give me the otp', 'kyc number']));
    test('3', () => _expectRisk(kReportedCalls[2], 'high', triggers: ['need your otp', 'bank details']));
    test('4', () => _expectRisk(kReportedCalls[3], 'high', triggers: ['give me the otp', 'kyc number']));
  });

  test('speech-to-text, spacing, numerals, Hindi and Hinglish variants', () {
    for (final t in [
      'I am from a bank. Please give me your six digit o t p and bank k y c number.',
      'I am from the bank, please give me the otb and your kic number.',
      'calling from bank kay why see department please give me your kay why see number and otp',
      'I need your O.T.P. to update your bank passbook.',
      'We need your OTP and account details to verify your bank account.',
      'मैं बैंक से बोल रहा हूँ। पासबुक अपडेट के लिए मुझे आपका ओटीपी चाहिए।',
      'Sir bank se bol raha hu, passbook update karna hai, aapka OTP chahiye.',
      'बैंक से बोल रही हूँ, अपना ओटीपी और केवाईसी नंबर बताइए।',
    ]) {
      _expectRisk(t, 'high');
    }
    _expectRisk('Hello, I need the OTP you just got.', 'medium'); // request alone, no pretext
  });

  test('negatives stay LOW (and KYC mention without a request is not HIGH)', () {
    for (final t in [
      'This is your bank. We will never need your OTP. Never share your OTP or KYC number with anyone.',
      'Bank kabhi aapka OTP nahi maangta, kisi ko mat batana.',
      'Your passbook is ready, please collect it from the branch.',
      'Your bank statement has been emailed to you.',
      'Hello bhaiya, Amazon se delivery hai. Apna pin code bata do.',
    ]) {
      _expectRisk(t, 'low');
    }
    final kyc = _all('Please complete your KYC at the branch next week.');
    expect(kyc.auto.risk, isNot('high'));
  });

  test('highlight offsets: key words and the whole dangerous sentence, mapped to the original text', () {
    final t = kReportedCalls[2];
    final r = _all(t).auto;
    final pieces = splitCallHighlights(t, r.result.matches);
    final key = [for (final p in pieces) if (p.highlighted) p.text.toLowerCase()];
    expect(key, contains('need your otp'));
    expect(key.any((k) => k.contains('bank details')), isTrue);
    // Every character of the dangerous sentence is shaded or key.
    expect(pieces.every((p) => p.highlighted || p.sentence), isTrue);
    expect(pieces.map((p) => p.text).join(), t); // offsets cover the original exactly

    final t4 = kReportedCalls[3];
    final p4 = splitCallHighlights(t4, _all(t4).auto.result.matches);
    final shaded = p4.where((p) => p.sentence || p.highlighted).map((p) => p.text).join();
    expect(shaded, contains('Please give me the OTP and your bank KYC number.'));
    expect(p4.firstWhere((p) => p.text.contains('you will be having')).sentence, isFalse); // info, not a request
  });

  testWidgets('Check Call screen (real file-pick path): HIGH, triggers listed, dangerous sentence highlighted',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('sr_call_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final audio = File('${dir.path}${Platform.pathSeparator}call.m4a')..writeAsBytesSync(List.filled(30000, 1));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_TranscriptApi(kReportedCalls[2])),
        callAnalyzerProvider.overrideWith((ref) async => CallAnalyzer.fromJson(_rules())),
      ],
      child: MaterialApp(home: CallDetectorScreen(pickAudio: () async => audio)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('call_pick')));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('HIGH RISK'), findsOneWidget);
    expect(find.byKey(const Key('call_triggers')), findsOneWidget);
    expect(find.textContaining('No strong scam signs'), findsNothing);
    final spans = <TextSpan>[];
    tester.widget<RichText>(find.descendant(of: find.byKey(const Key('call_transcript')), matching: find.byType(RichText)))
        .text
        .visitChildren((s) {
      if (s is TextSpan && s.text != null) spans.add(s);
      return true;
    });
    final keyText = spans.where((s) => s.style?.fontWeight == kKeyWordWeight).map((s) => s.text!.toLowerCase()).toList();
    expect(keyText, contains('need your otp'));
    expect(spans.every((s) => s.style?.backgroundColor != null), isTrue); // whole sentence shaded
    expect(spans.where((s) => s.style?.backgroundColor == kDangerSentenceColor), isNotEmpty);
  });
}

class _TranscriptApi extends ApiClient with _UploadViaTranscribe {
  final String text;
  _TranscriptApi(this.text);

  @override
  Future<Map> transcribe(File audio) async => {'text': text, 'lang': 'en'};

  @override
  Future<bool> isReachable({Duration timeout = const Duration(seconds: 4)}) async => true;

  @override
  Future<String> getBaseUrl() async => 'http://test:8000';
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