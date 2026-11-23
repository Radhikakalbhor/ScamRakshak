import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:scam_rakshak/engine/call_analyzer.dart';
import 'package:scam_rakshak/engine/scam_classifier.dart';
import 'package:scam_rakshak/features/call_detector/call_highlight.dart';

Map<String, dynamic> _json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  late ScamClassifier clf;
  late CallAnalyzer analyzer;

  setUpAll(() {
    clf = ScamClassifier.fromJson(_json('assets/models/scam_model.json'));
    analyzer = CallAnalyzer.fromJson(_json('assets/rules/call_rules.json'));
  });

  group('ScamClassifier', () {
    test('matches sklearn on all 50 parity samples', () {
      final parity = _json('assets/models/parity_samples.json');
      final samples = parity['samples'] as List;
      expect(samples.length, 50);
      var maxDiff = 0.0;
      for (final s in samples.cast<Map<String, dynamic>>()) {
        final diff = (clf.classify(s['text'] as String).score - (s['scam_prob'] as num).toDouble()).abs();
        if (diff > maxDiff) maxDiff = diff;
      }
      expect(maxDiff, lessThan(1e-6));
    });

    test('labels, score range and reasons', () {
      final scam = clf.classify('Dear customer your SBI account will be blocked today, update KYC now bit.ly/abcd');
      expect(scam.label, 'scam');
      expect(scam.score, inInclusiveRange(0.5, 1.0));
      expect(scam.reasons, isNotEmpty);
      expect(scam.reasons.first.weight, greaterThan(0));

      final ok = clf.classify('Rs 500 credited to your A/c XX1234 on 03-Feb. Ref 123456789012 -SBI');
      expect(ok.label, 'genuine');
      expect(ok.score, lessThan(0.5));
    });

    test('URLs become urltoken and Devanagari stays one token', () {
      expect(clf.tokenize('Open https://x.co/a NOW'), ['open', 'urltoken', 'now']);
      expect(clf.tokenize('आपका खाता'), ['आपका', 'खाता']);
    });

    test('empty text is handled', () {
      final r = clf.classify('');
      expect(r.score, inInclusiveRange(0.0, 1.0));
      expect(r.reasons, isEmpty);
    });
  });

  group('CallAnalyzer', () {
    test('all sample transcripts: scams high, genuine low', () {
      for (final f in Directory('assets/samples').listSync().whereType<File>().where((f) => f.path.endsWith('.txt'))) {
        final r = analyzer.analyze(f.readAsStringSync());
        final genuine = f.path.contains('genuine');
        expect(r.risk, genuine ? 'low' : 'high', reason: f.path);
      }
    });

    test('word boundaries: "cbi" does not match inside other words', () {
      expect(analyzer.analyze('the cbitech office').matches, isEmpty);
      expect(analyzer.analyze('This is CBI calling').matches.map((m) => m.scriptType), contains('digital_arrest'));
    });

    test('mainScriptType ignores pressure phrases', () {
      final r = analyzer.analyze('urgent! do not tell anyone. you are under digital arrest, cbi case');
      expect(mainScriptType(r), 'digital_arrest');
      expect(mainScriptType(analyzer.analyze('hello how are you')), isNull);
    });
  });

  test('splitHighlights marks phrases case-insensitively and merges overlaps', () {
    final pieces = splitHighlights('Tell me the OTP now', ['otp', 'the otp']);
    expect(pieces.map((p) => p.text).join(), 'Tell me the OTP now');
    expect(pieces.where((p) => p.highlighted).map((p) => p.text), ['the OTP']);
  });
}
