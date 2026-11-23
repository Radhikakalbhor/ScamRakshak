import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scam_rakshak/engine/scam_classifier.dart';

/// Minimal RFC 4180 CSV reader (quoted fields, "" escapes, newlines inside quotes).
List<List<String>> readCsv(String src) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < src.length; i++) {
    final c = src[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < src.length && src[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < src.length && src[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      if (row.any((f) => f.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  row.add(field.toString());
  if (row.any((f) => f.isNotEmpty)) rows.add(row);
  return rows;
}

List<Map<String, String>> readTable(String path) {
  final rows = readCsv(File(path).readAsStringSync());
  final head = rows.first;
  return [
    for (final r in rows.skip(1)) {for (var i = 0; i < head.length && i < r.length; i++) head[i]: r[i]},
  ];
}

class Metrics {
  int tp = 0, tn = 0, fp = 0, fn = 0;
  void add(bool truthScam, bool predScam) {
    if (truthScam && predScam) tp++;
    if (!truthScam && !predScam) tn++;
    if (!truthScam && predScam) fp++;
    if (truthScam && !predScam) fn++;
  }

  int get n => tp + tn + fp + fn;
  double get accuracy => n == 0 ? 0 : (tp + tn) / n;
  double get precision => tp + fp == 0 ? 0 : tp / (tp + fp);
  double get recall => tp + fn == 0 ? 0 : tp / (tp + fn);
  double get f1 => precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall);

  String md(String title) => '### $title (n=$n)\n\n'
      '| accuracy | precision | recall | F1 |\n|---|---|---|---|\n'
      '| ${accuracy.toStringAsFixed(4)} | ${precision.toStringAsFixed(4)} | ${recall.toStringAsFixed(4)} | '
      '${f1.toStringAsFixed(4)} |\n\n'
      '| true \\ pred | genuine | scam |\n|---|---|---|\n| genuine | $tn | $fp |\n| scam | $fn | $tp |\n\n';
}

const heldoutPath = 'ml/data/heldout_2026.csv';

void main() {
  late ScamClassifier clf;
  late List<Map<String, String>> heldout;

  setUpAll(() {
    clf = ScamClassifier.fromJson(
        jsonDecode(File('assets/models/scam_model.json').readAsStringSync()) as Map<String, dynamic>);
    heldout = readTable(heldoutPath);
  });

  test('held-out set: >= 100 messages, balanced, all three languages', () {
    expect(heldout.length, greaterThanOrEqualTo(100));
    for (final lang in ['en', 'hi', 'hinglish']) {
      final rows = heldout.where((r) => r['lang'] == lang).toList();
      expect(rows.length, greaterThanOrEqualTo(30), reason: lang);
      expect(rows.where((r) => r['label'] == 'scam').length, rows.length ~/ 2, reason: lang);
    }
    expect(heldout.every((r) => r['label'] == 'scam' || r['label'] == 'genuine'), isTrue);
  });

  test('held-out set shares no message with any training, tuning or earlier test data', () {
    String key(String t) => clf.tokenize(t).join(' ');
    final used = <String>[];
    for (final f in ['train.csv', 'test.csv', 'extra_train.csv', 'hindi_hinglish.csv', 'indian_english.csv']) {
      used.addAll(readTable('ml/data/$f').map((r) => r['text'] ?? ''));
    }
    // The older hand-written set (ml/handwritten_test.py) was used while tuning.
    final py = File('ml/handwritten_test.py').readAsStringSync();
    used.addAll(RegExp(r'\("((?:[^"\\]|\\.)*)", "(?:scam|genuine)"').allMatches(py).map((m) => m.group(1)!));
    used.addAll(File('lib/features/message_detector/message_examples.dart')
        .readAsStringSync()
        .split('\n')
        .where((l) => l.trim().startsWith("'"))
        .map((l) => l.trim()));

    final usedKeys = used.map(key).toSet();
    final usedSets = [for (final t in used) clf.tokenize(t).toSet()]..removeWhere((s) => s.isEmpty);
    final ownKeys = <String>{};
    for (final r in heldout) {
      final text = r['text']!;
      final k = key(text);
      expect(ownKeys.add(k), isTrue, reason: 'duplicate inside held-out: $text');
      expect(usedKeys.contains(k), isFalse, reason: 'exact overlap: $text');
      final a = clf.tokenize(text).toSet();
      var maxJ = 0.0;
      for (final b in usedSets) {
        final inter = a.intersection(b).length;
        if (inter == 0) continue;
        final j = inter / a.union(b).length;
        if (j > maxJ) maxJ = j;
      }
      expect(maxJ, lessThan(0.8), reason: 'near-duplicate (Jaccard ${maxJ.toStringAsFixed(2)}): $text');
    }
  });

  test('shipped Dart model on the held-out set: numbers match ml/results.md', () {
    final all = Metrics();
    final byLang = {'en': Metrics(), 'hi': Metrics(), 'hinglish': Metrics()};
    final errors = <String>[];
    for (final r in heldout) {
      final res = clf.classify(r['text']!);
      final truth = r['label'] == 'scam';
      final pred = res.label == 'scam';
      all.add(truth, pred);
      byLang[r['lang']]!.add(truth, pred);
      if (truth != pred) {
        errors.add('| ${r['label']} | ${res.label} | ${res.score.toStringAsFixed(2)} | ${r['lang']} | '
            '${r['text']!.replaceAll('|', '/')} |');
      }
    }
    final report = StringBuffer()
      ..write(all.md('Held-out 2026, all'))
      ..write(byLang['en']!.md('Held-out 2026, English'))
      ..write(byLang['hi']!.md('Held-out 2026, Hindi (Devanagari)'))
      ..write(byLang['hinglish']!.md('Held-out 2026, Hinglish'))
      ..write('### Held-out 2026 errors\n\n| label | pred | score | lang | text |\n|---|---|---|---|---|\n')
      ..writeAll(errors.map((e) => '$e\n'));
    // ignore: avoid_print
    print(report);

    final results = File('ml/results.md').readAsStringSync().replaceAll('\r\n', '\n');
    expect(results, contains(all.md('Held-out 2026, all')),
        reason: 'ml/results.md must report the current held-out numbers (printed above)');
    for (final l in ['English', 'Hindi (Devanagari)', 'Hinglish']) {
      final m = byLang[{'English': 'en', 'Hindi (Devanagari)': 'hi', 'Hinglish': 'hinglish'}[l]]!;
      expect(results, contains(m.md('Held-out 2026, $l')));
    }
  });
}
