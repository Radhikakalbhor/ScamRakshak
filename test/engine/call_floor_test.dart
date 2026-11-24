import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:scam_rakshak/engine/call_analyzer.dart';
import 'package:scam_rakshak/engine/call_floor.dart';
import 'package:scam_rakshak/engine/live_call_analyzer.dart';
import 'package:scam_rakshak/features/call_detector/call_highlight.dart';
import 'package:scam_rakshak/features/call_detector/call_timeline.dart';
import 'package:scam_rakshak/features/call_detector/call_triggers.dart';
import 'package:scam_rakshak/features/live_call/live_risk.dart';

/// Secret/KYC request floor, through the entry points the app uses:
/// Check Call (CallAnalyzer.score), recordings / auto-analyze / share (CallTimeline.analyze) and
/// Live Call (LiveCallAnalyzer.add per chunk + combinedRisk).
void main() {
  late CallAnalyzer rules;
  late LiveCallAnalyzer live;

  setUpAll(() {
    final j = jsonDecode(File('assets/rules/call_rules.json').readAsStringSync()) as Map<String, dynamic>;
    rules = CallAnalyzer.fromJson(j);
    live = LiveCallAnalyzer.fromJson(j);
  });

  ({String check, String timeline, double score, String live, double liveScore}) all(String text) {
    final check = rules.analyze(text).risk;
    final tl = CallTimeline(rules, live).analyze(text);
    live.reset();
    var st = LiveCallState.empty;
    for (final s in CallTimeline.sentences(text)) {
      st = live.add(s);
    }
    live.reset();
    // The SMS classifier may only raise a call (combinedRisk); a high ML score cannot lower it.
    final liveRisk = combinedRisk(st, 0.99);
    expect(combinedRisk(st, 0.0), st.risk);
    return (check: check, timeline: tl.risk, score: tl.score, live: liveRisk, liveScore: st.score);
  }

  const lgi = "I'm from LGI Bank. I'm asking for your 6-digit OTP and bank KYC number to update your password. "
      'Can you please give it to me?';

  const mustBeHigh = {
    'LGI example': lgi,
    'Absara': 'I am Aditi from Absara Bank. Please give me the OTP and your bank KYC number.',
    'from a bank': 'I am from a bank. Please give me your 6-digit OTP and bank KYC number.',
    'Hinglish': 'OTP bata do aur KYC update karna hai',
    'Hindi': 'अपना ओटीपी बताइए',
    'ASR KIC': "I'm from LGI Bank. I'm asking for your six digit KIC number to update your password. Can you please give it to me?",
    'ASR O T P / K Y C': "I'm from LGI Bank. Please tell me your O T P and K Y C number.",
    'ASR o.t.p': 'Calling from State Bank. Your account will be blocked. Read out the o.t.p now.',
  };

  for (final e in mustBeHigh.entries) {
    test('HIGH on every path: ${e.key}', () {
      final r = all(e.value);
      expect(r.check, 'high', reason: 'Check Call');
      expect(r.timeline, 'high', reason: 'recording / auto-analyze / share');
      expect(r.score, greaterThanOrEqualTo(CallFloor.highMin));
      expect(r.live, 'high', reason: 'live call');
    });
  }

  test('LGI example: was LOW 33 %, now HIGH >= 85 % with the trigger phrases listed', () {
    final s = rules.score(lgi);
    expect(s.total, lessThan(rules.mediumLevel), reason: 'the weighted score alone is still low');
    expect(s.floor?.level, 'high');
    final phrases = s.result.matches.map((m) => m.phrase).toList();
    expect(phrases, containsAll(['otp', 'asking for your 6-digit']));
    expect(phrases.any((p) => p.startsWith('give it to me') || p.contains('give it')), isTrue);
    expect(callNoteKey(s.result), isNot('call_low_note'));
  });

  test('LGI example: the request sentences and key words are highlighted in the original text', () {
    final r = CallTimeline(rules, live).analyze(lgi);
    final pieces = splitCallHighlights(lgi, r.result.matches);
    final key = pieces.where((p) => p.highlighted).map((p) => p.text.toLowerCase()).join('|');
    final sentence = pieces.where((p) => p.sentence).map((p) => p.text).join();
    expect(key, contains('otp'));
    expect(key, contains('give it to me'));
    expect(sentence, contains('Can you please give it to me?'));
    expect(sentence, contains('6-digit OTP'));
  });

  const mustBeAtLeastMedium = [
    'I need your OTP to update your bank details.',
    'I need your OTP to update your passbook.',
  ];
  for (final t in mustBeAtLeastMedium) {
    test('at least MEDIUM: $t', () {
      final r = all(t);
      for (final risk in [r.check, r.timeline, r.live]) {
        expect(risk, isNot('low'));
      }
      expect(r.score, greaterThanOrEqualTo(CallFloor.mediumMin));
    });
  }

  final mustStayLow = <String, String>{
    'advice': 'Never share your OTP with anyone, even bank staff.',
    'advice hi': 'अपना ओटीपी किसी को मत बताइए।',
    'do not give': 'Do not give your PIN or OTP to anyone who calls you.',
    'genuine bank service':
        'Hello, this is a reminder from your bank that your KYC is due next month. Please visit your nearest branch '
            'with your Aadhaar card. We will never ask for your OTP or PIN.',
    'bank sends OTP': 'We will send you an OTP to verify your new mobile number.',
    'family': 'Hi beta, I reached home safely. Tell papa to call me after dinner.',
    'delivery': 'Hello, your parcel from Amazon will be delivered today between 2 and 4 pm. Please keep someone at home to receive it.',
  };
  for (final f in Directory('assets/samples/live').listSync().whereType<File>()) {
    final name = f.path.split(Platform.pathSeparator).last;
    if (name.startsWith('genuine') && name.endsWith('.txt')) mustStayLow['sample $name'] = f.readAsStringSync();
  }
  for (final e in mustStayLow.entries) {
    test('stays LOW (floor does not fire): ${e.key}', () {
      expect(CallFloor.evaluate(e.value), isNull);
      final r = all(e.value);
      expect(r.check, 'low');
      expect(r.timeline, 'low');
      expect(r.live, 'low');
    });
  }
}
