import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:scam_rakshak/engine/scam_classifier.dart';

void main() {
  late ScamClassifier clf;
  late Map<String, dynamic> model;

  setUpAll(() {
    model = jsonDecode(File('assets/models/scam_model.json').readAsStringSync()) as Map<String, dynamic>;
    clf = ScamClassifier.fromJson(model);
  });

  double baseline() => 1 / (1 + math.exp(-(model['intercept'] as num).toDouble()));

  Set<String> ngrams(String text) {
    final t = clf.tokenize(text);
    return {...t, for (var i = 0; i + 1 < t.length; i++) '${t[i]} ${t[i + 1]}'};
  }

  group('tokenize (mirrors ml/preprocess.py)', () {
    test('lowercases and splits on non-word characters', () {
      expect(clf.tokenize('Hello, WORLD!! 123-abc'), ['hello', 'world', '123', 'abc']);
    });

    test('replaces http, www and bare-domain URLs with urltoken', () {
      expect(clf.tokenize('Open https://x.co/a NOW'), ['open', 'urltoken', 'now']);
      expect(clf.tokenize('go www.example.com/path?q=1 today'), ['go', 'urltoken', 'today']);
      expect(clf.tokenize('click bit.ly/abcd'), ['click', 'urltoken']);
      expect(clf.tokenize('visit sbi-kyc.xyz/verify now'), ['visit', 'urltoken', 'now']);
    });

    test('keeps Devanagari words (including matras) as single tokens', () {
      expect(clf.tokenize('आपका खाता बंद होगा'), ['आपका', 'खाता', 'बंद', 'होगा']);
      // Python's [a-z0-9ऀ-ॿ] spans U+0900-U+097F, which includes the danda, so it stays attached.
      expect(clf.tokenize('बंद होगा। तुरंत'), ['बंद', 'होगा।', 'तुरंत']);
      expect(clf.tokenize('KYC अपडेट करें'), ['kyc', 'अपडेट', 'करें']);
    });

    test('URL ends where Python \\s ends (\\x85 is whitespace, \\ufeff is not)', () {
      expect(clf.tokenize('visit http://x.co/a\u0085now'), ['visit', 'urltoken', 'now']);
      expect(clf.tokenize('visit http://x.co/a﻿now'), ['visit', 'urltoken']);
    });
  });

  group('classify', () {
    test('empty, whitespace, punctuation-only and unknown words give the intercept-only score', () {
      for (final t in ['', '   \n\t', '!!! ??? ...', 'qqqzzzxx vvvwwwyy']) {
        final r = clf.classify(t);
        expect(r.score, closeTo(baseline(), 1e-12), reason: '"$t"');
        expect(r.reasons, isEmpty, reason: '"$t"');
        expect(r.label, r.score >= 0.5 ? 'scam' : 'genuine');
      }
    });

    test('is case-insensitive and deterministic', () {
      const msg = 'Your KYC is pending, update now at sbi-kyc.xyz or account will be BLOCKED';
      expect(clf.classify(msg).score, clf.classify(msg.toLowerCase()).score);
      expect(clf.classify(msg).score, clf.classify(msg).score);
    });

    test('obvious scam vs genuine bank alert', () {
      final scam = clf.classify('Dear customer your SBI account will be blocked today, update KYC now bit.ly/abcd');
      expect(scam.label, 'scam');
      expect(scam.score, inInclusiveRange(0.5, 1.0));

      final ok = clf.classify('Rs 500 credited to your A/c XX1234 on 03-Feb. Ref 123456789012 -SBI');
      expect(ok.label, 'genuine');
      expect(ok.score, inInclusiveRange(0.0, 0.5));
    });

    test('very long input stays finite and in [0, 1]', () {
      final r = clf.classify(List.filled(5000, 'urgent kyc update otp').join(' '));
      expect(r.score.isFinite, isTrue);
      expect(r.score, inInclusiveRange(0.0, 1.0));
    });
  });

  group('reasons', () {
    const scamMsg =
        'URGENT: Dear customer, your SBI account will be blocked today. Update your KYC now at '
        'bit.ly/sbi-kyc and share the OTP to avoid suspension.';

    test('at most 5, strictly positive, sorted by tfidf x coef descending', () {
      final r = clf.classify(scamMsg);
      expect(r.reasons, isNotEmpty);
      expect(r.reasons.length, lessThanOrEqualTo(ScamClassifier.maxReasons));
      expect(ScamClassifier.maxReasons, 5);
      for (var i = 0; i < r.reasons.length; i++) {
        expect(r.reasons[i].weight, greaterThan(0));
        if (i > 0) expect(r.reasons[i - 1].weight, greaterThanOrEqualTo(r.reasons[i].weight));
      }
    });

    test('every reason is a unigram or bigram present in the text and in the vocabulary', () {
      final vocab = (model['vocab'] as Map).keys.toSet();
      final present = ngrams(scamMsg);
      for (final reason in clf.classify(scamMsg).reasons) {
        expect(present, contains(reason.phrase));
        expect(vocab, contains(reason.phrase));
      }
    });

    test('reason weight equals the term\'s contribution tfidf x coef', () {
      // Independent recomputation for the top reason from the exported model.
      final vocab = (model['vocab'] as Map).cast<String, num>();
      final idf = (model['idf'] as List).cast<num>();
      final coef = (model['coef'] as List).cast<num>();
      final toks = clf.tokenize(scamMsg);
      final counts = <String, int>{};
      for (var i = 0; i < toks.length; i++) {
        for (final g in [toks[i], if (i + 1 < toks.length) '${toks[i]} ${toks[i + 1]}']) {
          if (vocab.containsKey(g)) counts[g] = (counts[g] ?? 0) + 1;
        }
      }
      var sq = 0.0;
      counts.forEach((g, c) => sq += math.pow(c * idf[vocab[g]!.toInt()], 2));
      final top = clf.classify(scamMsg).reasons.first;
      final j = vocab[top.phrase]!.toInt();
      final expected = counts[top.phrase]! * idf[j] / math.sqrt(sq) * coef[j];
      expect(top.weight, closeTo(expected, 1e-9));
    });

    test('long scam message returns exactly 5 reasons', () {
      final long = '$scamMsg Your PAN card link is pending, click here, reward points expire, lottery prize won.';
      expect(clf.classify(long).reasons, hasLength(5));
    });
  });
}
