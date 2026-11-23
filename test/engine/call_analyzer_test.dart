import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:scam_rakshak/engine/call_analyzer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CallAnalyzer a;
  late Map<String, dynamic> rules;

  setUpAll(() async {
    a = await CallAnalyzer.load(); // via rootBundle
    rules = jsonDecode(File('assets/rules/call_rules.json').readAsStringSync()) as Map<String, dynamic>;
  });

  Set<String> types(String t) => a.analyze(t).matches.map((m) => m.scriptType).toSet();

  group('rules file', () {
    test('defines every required script type', () {
      final defined = (rules['rules'] as List).map((r) => r['type']).toSet();
      expect(
        defined,
        containsAll([
          'fake_kyc',
          'digital_arrest',
          'courier_customs',
          'otp_request',
          'lottery_prize',
          'remote_access',
          'loan_threat',
        ]),
      );
    });

    test('uses the project risk levels (high 6, medium 3)', () {
      expect(a.highLevel, 6);
      expect(a.mediumLevel, 3);
    });

    test('load() and fromJson() agree', () {
      final b = CallAnalyzer.fromJson(rules);
      const t = 'Aapka KYC pending hai, OTP bataiye turant';
      expect(b.score(t).total, a.score(t).total);
    });

    test('invalid levels are rejected', () {
      expect(
        () => CallAnalyzer.fromJson({
          'levels': {'high': 2, 'medium': 3},
          'rules': [],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('legacy list format with a rule-level weight still works', () {
      final b = CallAnalyzer.fromJson({
        'levels': {'high': 6, 'medium': 3},
        'rules': [
          {
            'type': 'otp_request',
            'weight': 3,
            'phrases': ['otp bata*'],
          },
        ],
      });
      expect(b.score('otp batao').byType, {'otp_request': 3});
    });
  });

  group('normalize', () {
    test('lowercases, turns punctuation and danda into single spaces, trims', () {
      expect(CallAnalyzer.normalize('  Hello,   WORLD!!  ').text, 'hello world');
      expect(CallAnalyzer.normalize('OTP...bataiye?!').text, 'otp bataiye');
      expect(CallAnalyzer.normalize('खाता बंद। तुरंत॥').text, 'खाता बंद तुरंत');
      expect(CallAnalyzer.normalize('line1\nline2\tx').text, 'line1 line2 x');
    });

    test('drops nukta (combining and precomposed) and zero-width joiners', () {
      expect(CallAnalyzer.normalize('फ़्रीज़').text, CallAnalyzer.normalize('फ्रीज').text);
      expect(CallAnalyzer.normalize('फ़').text, 'फ'); // precomposed फ़ -> फ
      expect(CallAnalyzer.normalize('क्‍ष').text, 'क्ष');
    });

    test('maps every normalized character back to the original text', () {
      const src = 'Hi, OTP  Bataiye!';
      final n = CallAnalyzer.normalize(src);
      expect(n.sourceIndex, hasLength(n.text.length));
      for (var i = 0; i < n.text.length; i++) {
        if (n.text[i] != ' ') expect(src[n.sourceIndex[i]].toLowerCase(), n.text[i]);
      }
    });

    test('punctuation does not block matching', () {
      expect(types('OTP, bataiye!'), contains('otp_request'));
      expect(types('Any-Desk? no: AnyDesk.'), contains('remote_access'));
    });
  });

  group('every script type in English, Devanagari Hindi and Hinglish', () {
    const cases = <String, List<String>>{
      'fake_kyc': [
        'Sir your account will be blocked tonight',
        'आपका केवाईसी अपडेट नहीं हुआ है',
        'aapka account block ho jayega',
      ],
      'otp_request': [
        'Please tell me the OTP you received',
        'मोबाइल पर आया ओटीपी बताइए',
        'jo OTP aaya hai wo bataiye, matlab OTP bata do',
      ],
      'remote_access': ['Install TeamViewer from Play Store', 'एनीडेस्क खोलिए', 'AnyDesk app download karo'],
      'digital_arrest': ['You are under digital arrest', 'आप डिजिटल अरेस्ट में हैं', 'aapko video call pe rahna hoga'],
      'courier_customs': [
        'Your parcel has been seized with illegal items',
        'आपका पार्सल पकड़ा गया है',
        'aapka parcel pakda gaya hai',
      ],
      'lottery_prize': [
        'Congratulations, you have won a car in the lucky draw',
        'आपकी लॉटरी लगी है',
        'aapki lottery lagi hai, aapne jeeta 25 lakh',
      ],
      'loan_threat': [
        'We will send to your contacts a morphed photo',
        'तुम्हारी फोटो वायरल कर देंगे',
        'tumhare contacts ko bhej denge',
      ],
    };

    cases.forEach((type, sentences) {
      test(type, () {
        for (final s in sentences) {
          expect(types(s), contains(type), reason: s);
        }
      });
    });

    test('other existing types still work', () {
      expect(types('Press 9 or your SIM will be blocked'), contains('telecom_threat'));
      expect(types('आज रात बिजली काट दी जाएगी'), contains('electricity_bill'));
      expect(types('collect request aayegi, PIN daal do'), contains('upi_collect'));
      expect(types('यह बहुत ज़रूरी है, तुरंत करें'), contains('pressure'));
    });
  });

  group('scoring', () {
    test('scores accumulate across script types and reach each threshold', () {
      final low = a.score('Aapka KYC pending hai');
      expect(low.byType, {'fake_kyc': 2});
      expect(low.total, 2);
      expect(low.result.risk, 'low');

      final medium = a.score('Aapka KYC pending hai, OTP bataiye');
      expect(medium.byType, {'fake_kyc': 2, 'otp_request': 3});
      expect(medium.total, 5);
      expect(medium.result.risk, 'medium');

      final high = a.score('Aapka KYC pending hai, OTP bataiye turant');
      expect(high.total, 6);
      expect(high.result.risk, 'high');
    });

    test('exact boundaries: total == medium -> medium, total == high -> high', () {
      expect(a.score('OTP bataiye').total, 3);
      expect(a.analyze('OTP bataiye').risk, 'medium');
      expect(a.score('OTP bataiye, AnyDesk').total, 6);
      expect(a.analyze('OTP bataiye, AnyDesk').risk, 'high');
    });

    test('a type never scores above its cap', () {
      final s = a.score('urgent! immediately, right now, turant, jaldi karo, abhi ke abhi');
      expect(s.byType['pressure'], 2);
      expect(s.result.risk, 'low', reason: 'pressure words alone are not a scam');
    });

    test('each distinct phrase counts once', () {
      expect(a.score('OTP bataiye. OTP bataiye. OTP bataiye.').byType, {'otp_request': 3});
    });

    test('overlapping phrases count only the longest', () {
      final s = a.score('Aapka KYC update karna hai');
      expect(s.result.matches.map((m) => m.phrase), ['kyc update']);
      expect(s.byType, {'fake_kyc': 3});
    });

    test('trailing * lets the last word continue, but not the first', () {
      for (final t in ['otp batao', 'otp bataiye', 'otp batana', 'OTP बताइए']) {
        expect(types(t), contains('otp_request'), reason: t);
      }
      expect(types('otpbatao'), isEmpty);
    });

    test('matches keep the original wording and follow transcript order', () {
      final m = a.analyze('Main bank se bol raha hu, aapka KYC pending hai, OTP, bataiye turant').matches;
      expect(m.map((x) => x.phrase), ['kyc', 'otp, bataiye', 'turant']);
      expect(m.map((x) => x.scriptType), ['fake_kyc', 'otp_request', 'pressure']);
    });
  });

  group('false positives', () {
    test('short keywords need whole words (Latin and Devanagari)', () {
      expect(types('the cbitech office'), isEmpty);
      expect(types('the trainee joined'), isEmpty);
      expect(types('please call our कस्टमर केयर'), isEmpty);
      expect(types('This is CBI calling'), contains('digital_arrest'));
    });

    test('safety advice with a negator is not an OTP or app request', () {
      for (final t in [
        'Never share the OTP with anyone',
        'Please do not share OTP on calls',
        "Please don't install AnyDesk for anyone",
        'You should not enter your PIN to receive money',
      ]) {
        expect(a.score(t).total, 0, reason: t);
      }
    });

    test('ordinary calls stay low', () {
      for (final t in [
        'Hello, I am calling from the school about the parent teacher meeting on Saturday.',
        'Bhaiya aapka khana pack ho gaya hai, delivery boy 10 minute me aa jayega.',
        'नमस्ते, कल शाम को शादी में आना ज़रूर, सब लोग आपका इंतज़ार करेंगे।',
        'I won the cricket match today and my customer is happy',
        'Your loan EMI of 2,000 is due on 5th, you can pay at the branch.',
      ]) {
        expect(a.analyze(t).risk, 'low', reason: t);
      }
    });

    test('a single generic mention is not enough for medium risk', () {
      expect(a.analyze('TV pe lottery fraud ki news dekhi').risk, 'low');
      expect(a.analyze('My courier came via DHL').risk, 'low');
    });
  });

  group('empty input', () {
    for (final t in ['', '   ', '\n\t', '...!!!', '।।']) {
      test('"${t.replaceAll('\n', r'\n').replaceAll('\t', r'\t')}" is low with no matches', () {
        final s = a.score(t);
        expect(s.result.risk, 'low');
        expect(s.result.matches, isEmpty);
        expect(s.total, 0);
        expect(s.byType, isEmpty);
      });
    }
  });
}
