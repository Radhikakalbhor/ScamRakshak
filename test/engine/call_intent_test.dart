import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:scam_rakshak/engine/call_analyzer.dart';
import 'package:scam_rakshak/engine/live_call_analyzer.dart';
import 'package:scam_rakshak/engine/models.dart';
import 'package:scam_rakshak/core/strings.dart';
import 'package:scam_rakshak/features/call_detector/call_highlight.dart';
import 'package:scam_rakshak/features/call_detector/call_strings.dart';
import 'package:scam_rakshak/features/call_detector/call_timeline.dart';
import 'package:scam_rakshak/features/call_detector/call_triggers.dart';

Map<String, dynamic> _rules() => jsonDecode(File('assets/rules/call_rules.json').readAsStringSync()) as Map<String, dynamic>;

const kReported = 'I am Aditi from Absara Bank ... you will be having an OTP. '
    'Please give me the OTP and your bank KYC number.';

/// Recording path: whole transcript (CallAnalyzer) + per-sentence timeline (CallTimeline).
CallTimelineResult _recording(String t) =>
    CallTimeline(CallAnalyzer.fromJson(_rules()), LiveCallAnalyzer.fromJson(_rules())).analyze(t);

/// Live path: one chunk per sentence, evidence accumulated over the call.
LiveCallState _live(String t) {
  final live = LiveCallAnalyzer.fromJson(_rules());
  var st = LiveCallState.empty;
  for (final seg in CallTimeline.sentences(t)) {
    st = live.add(seg);
  }
  return st;
}

List<String> _phrases(List<CallMatch> m) => m.map((x) => x.phrase).toList();

String Function(String lang, String key) _strings() {
  CallStrings.ensure();
  return (lang, key) => S(lang).t(key);
}

/// Asserts [risk] on both paths and that every trigger in [triggers] is reported on both.
void _both(String t, String risk, {List<String> triggers = const []}) {
  final rec = _recording(t);
  final live = _live(t);
  expect(rec.risk, risk, reason: 'recording: $t\nmatches=${_phrases(rec.result.matches)}');
  expect(live.risk, risk, reason: 'live: $t\nmatches=${_phrases(live.matches)}');
  for (final tr in triggers) {
    expect(_phrases(rec.result.matches).any((p) => p.contains(tr)), isTrue,
        reason: 'recording trigger "$tr" in ${_phrases(rec.result.matches)}');
    expect(_phrases(live.matches).any((p) => p.contains(tr)), isTrue,
        reason: 'live trigger "$tr" in ${_phrases(live.matches)}');
  }
}

void main() {
  test('diagnostic: reported transcript on both paths (rules, weights, formula, thresholds)', () {
    final rules = CallAnalyzer.fromJson(_rules());
    final s = rules.score(kReported);
    // ignore: avoid_print
    print('RECORDING (CallAnalyzer): risk=${s.result.risk} total=${s.total} byType=${s.byType} '
        '[medium>=${rules.mediumLevel} high>=${rules.highLevel}; byType=max(capped phrases, intent); total=sum] '
        'matches=${s.result.matches.map((m) => '${m.phrase}(${m.scriptType})').toList()}');
    final live = LiveCallAnalyzer.fromJson(_rules());
    for (final seg in CallTimeline.sentences(kReported)) {
      final st = live.add(seg);
      // ignore: avoid_print
      print('LIVE "$seg" -> ${st.risk} ${st.score.toStringAsFixed(2)} '
          '${st.matches.map((m) => '${m.phrase}(${m.scriptType})').toList()}');
    }
    final tl = _recording(kReported);
    // ignore: avoid_print
    print('CALL TIMELINE: ${tl.risk} ${(tl.score * 100).round()}%  (was LOW 33%: only "kyc" matched, 2 < medium 3)');
  });

  group('caller asks for OTP / KYC details', () {
    test('the reported transcript is HIGH with its triggers', () {
      _both(kReported, 'high', triggers: ['give me the otp', 'kyc number', 'bank']);
      expect(_recording(kReported).score, greaterThanOrEqualTo(0.8));
    });

    test('ASR spacing / spelling variants', () {
      for (final t in [
        'I am Aditi from Apsara bank. Please give me the o t p and your bank kyc number.',
        'This is Aditi from Absara Bank. Kindly give me the O.T.P. that came on your phone.',
        'aditi from absara bank speaking please give me the otp and kyc number', // no punctuation (ASR)
        'Hello, I am calling from the bank. Can you tell me the OTP?',
        'Bank KYC department. Just read out the OTPs to me, sir.',
        'I am from your bank. Please share the one time password you received.',
        'I am from SBI. Please confirm your CVV and card number.',
      ]) {
        _both(t, 'high');
      }
    });

    test('Hindi and Hinglish', () {
      _both('मैं अप्सरा बैंक से अदिति बोल रही हूँ। कृपया मुझे ओटीपी और अपना केवाईसी नंबर बताइए।', 'high',
          triggers: ['ओटीपी']);
      _both('मैं बैंक से बोल रही हूँ। आपके फोन पर आया ओ टी पी दीजिए।', 'high');
      _both('Main Apsara bank se Aditi bol rahi hu. Aapke phone pe OTP aaya hoga, wo OTP bata dijiye.', 'high',
          triggers: ['otp bata']);
      _both('Bank se bol raha hu, apna ATM pin aur card number bataiye jaldi.', 'high');
      _both('Sir aapka KYC pending hai, OTP share karo abhi.', 'high');
    });

    test('asking for an OTP/PIN with no pretext is at least MEDIUM on its own', () {
      _both('Hello, please tell me the OTP you just got.', 'medium', triggers: ['tell me the otp']);
      _both('Bhai jo OTP aaya hai wo bata do.', 'medium');
    });

    test('result lists plain trigger phrases, never an empty list when something matched', () {
      final r = _recording(kReported);
      expect(r.result.matches.map((m) => m.scriptType), containsAll(['otp_request', 'details_request', 'impersonation']));
      expect(r.result.matches.every((m) => m.phrase.trim().isNotEmpty), isTrue);
      expect(r.result.matches.any((m) => m.phrase.contains('.')), isFalse); // no cross-sentence spans
    });
  });

  group('other scam scripts', () {
    test('digital arrest, courier/customs, remote access, lottery, fake KYC block', () {
      _both('This is CBI crime branch. You are under digital arrest. Stay on video call and do not tell anyone.', 'high');
      _both('FedEx here. Your parcel has been seized by customs with illegal items. Pay the customs clearance fee now.',
          'high');
      _both('Please install AnyDesk and share your screen so I can process the refund. Read out the code to me.', 'high');
      _both('Congratulations, you have won a lucky draw of 25 lakh. Pay the registration fee today to get the prize money.',
          'high');
      _both('Your KYC has expired and your account will be blocked today. Tell me the OTP to update KYC.', 'high');
    });
  });

  group('hard negatives stay LOW', () {
    test('bank advisory, service, family and delivery calls', () {
      for (final t in [
        'This is Priya from your bank. Please remember, the bank will never ask for your OTP or PIN. Never share your OTP with anyone.',
        'If anyone asks for your OTP, please do not give it to them. Do not share your card number or CVV.',
        'Your new credit card has been approved. We will send you an OTP to activate it in the app.',
        'हेलो बेटा, कोई फोन पर ओटीपी मांगे तो मत देना। किसी को ओटीपी मत बताइए।',
        'बैंक कभी भी ओटीपी या पिन नहीं माँगता, ओटीपी कभी साझा न करें।',
        'Haan beta, koi phone kare to kisi ko OTP mat batana, aur seedha bank jaake puchna.',
        'Hello bhaiya, Amazon se delivery hai. Apna pin code bata do, main gali ke bahar khada hu.',
        'Hi, this is the courier. Please tell me your house number and landmark.',
      ]) {
        _both(t, 'low');
      }
    });

    test('mentioning KYC without asking for secrets stays low or medium', () {
      for (final t in [
        'Your KYC is due next month, please visit the branch with your Aadhaar and PAN card.',
        'आपका केवाईसी अगले महीने पूरा होना है, शाखा आ जाइए।',
      ]) {
        expect(_recording(t).risk, isNot('high'), reason: t);
        expect(_live(t).risk, isNot('high'), reason: t);
      }
    });
  });

  test('result text: "No strong scam signs" only when nothing matched; type label is the real script', () {
    expect(callNoteKey(const CallResult('low', [])), 'call_low_note');
    expect(callNoteKey(const CallResult('low', [CallMatch('kyc', 'fake_kyc')])), 'call_low_with_signs');
    expect(callNoteKey(const CallResult('medium', [CallMatch('tell me the otp', 'otp_request')])), 'call_advice_high');
    expect(mainScriptType(_recording(kReported).result), 'otp_request'); // not the 'bank' pretext
    final s = _strings();
    for (final lang in ['en', 'hi', 'chh']) {
      for (final k in ['script_details_request', 'script_impersonation', 'call_low_with_signs', 'call_triggers']) {
        expect(s(lang, k), isNot(k), reason: '$lang/$k');
      }
    }
    expect(s('en', 'call_low_with_signs'), isNot(contains('No strong scam signs')));
  });

  test('bundled samples keep their verdicts (scam_* high, genuine_* low) on both paths', () {
    for (final f in [
      ...Directory('assets/samples').listSync().whereType<File>(),
      ...Directory('assets/samples/live').listSync().whereType<File>(),
    ].where((f) => f.path.endsWith('.txt'))) {
      final name = f.uri.pathSegments.last;
      final t = f.readAsStringSync();
      if (name.startsWith('genuine')) {
        _both(t, 'low');
      } else if (f.path.contains('live')) {
        _both(t, 'high');
      } else {
        expect(_recording(t).risk, 'high', reason: name);
      }
    }
  });
}
