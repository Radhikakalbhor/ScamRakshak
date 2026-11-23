import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:scam_rakshak/engine/scam_classifier.dart';

/// Dart inference must reproduce the Python (sklearn) reference probabilities.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tolerance = 1e-4;
  late ScamClassifier clf;
  late List<Map<String, dynamic>> samples;

  setUpAll(() async {
    clf = await ScamClassifier.load(); // real asset path via rootBundle
    final ref = jsonDecode(File('assets/models/parity_samples.json').readAsStringSync()) as Map<String, dynamic>;
    samples = (ref['samples'] as List).cast<Map<String, dynamic>>();
  });

  test('reference file has 50 samples', () => expect(samples, hasLength(50)));

  test('all 50 Python probabilities match within $tolerance', () {
    var maxErr = 0.0;
    final failures = <String>[];
    for (final s in samples) {
      final expected = (s['scam_prob'] as num).toDouble();
      final actual = clf.classify(s['text'] as String).score;
      final err = (actual - expected).abs();
      if (err > maxErr) maxErr = err;
      if (err > tolerance) failures.add('${s['text']}: dart=$actual python=$expected');
    }
    // ignore: avoid_print
    print('parity: ${samples.length} samples, max abs error = ${maxErr.toStringAsExponential(3)}');
    expect(failures, isEmpty);
    expect(maxErr, lessThanOrEqualTo(tolerance));
  });

  test('predicted label agrees with the Python probability for every sample', () {
    for (final s in samples) {
      final r = clf.classify(s['text'] as String);
      final expected = (s['scam_prob'] as num) >= 0.5 ? 'scam' : 'genuine';
      expect(r.label, expected, reason: s['text'] as String);
    }
  });

  test('parity covers en, hi and Hinglish samples', () {
    expect(samples.map((s) => s['lang']).toSet(), containsAll(['en', 'hi']));
    expect(samples.length, greaterThanOrEqualTo(3));
  });
}
