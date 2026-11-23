import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

/// Offline TF-IDF + logistic regression scam classifier.
/// Reproduces ml/train.py exactly from assets/models/scam_model.json
/// (lowercase -> URL to ' urltoken ' -> token regex -> 1-2 grams -> tf*idf -> l2 -> logit -> sigmoid).
class ScamClassifier {
  final Map<String, int> _vocab;
  final List<double> _idf;
  final List<double> _coef;
  final double _intercept;
  final RegExp _url;
  final String _urlReplacement;
  final RegExp _token;

  /// Minimum contribution for an n-gram to be listed as a reason.
  static const double reasonThreshold = 0.05;
  static const int maxReasons = 6;

  /// index -> n-gram (inverse of [_vocab]), for reasons.
  final List<String> _terms;

  ScamClassifier._(this._vocab, this._idf, this._coef, this._intercept, this._url, this._urlReplacement,
      this._token)
      : _terms = _invert(_vocab, _idf.length);

  static List<String> _invert(Map<String, int> vocab, int n) {
    final t = List<String>.filled(n, '');
    vocab.forEach((g, j) => t[j] = g);
    return t;
  }

  static Future<ScamClassifier> load() async {
    final raw = await rootBundle.loadString('assets/models/scam_model.json');
    return ScamClassifier.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  factory ScamClassifier.fromJson(Map<String, dynamic> j) {
    final p = j['preprocessing'] as Map<String, dynamic>;
    final vocab = (j['vocab'] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt()));
    return ScamClassifier._(
      vocab,
      (j['idf'] as List).map((e) => (e as num).toDouble()).toList(growable: false),
      (j['coef'] as List).map((e) => (e as num).toDouble()).toList(growable: false),
      (j['intercept'] as num).toDouble(),
      RegExp(p['url_regex'] as String),
      p['url_replacement'] as String,
      RegExp(p['token_regex'] as String),
    );
  }

  List<String> tokenize(String text) {
    final s = text.toLowerCase().replaceAll(_url, _urlReplacement);
    return _token.allMatches(s).map((m) => m.group(0)!).toList();
  }

  ScamResult classify(String text) {
    final toks = tokenize(text);
    final tf = <int, int>{};
    void add(String g) {
      final j = _vocab[g];
      if (j != null) tf[j] = (tf[j] ?? 0) + 1;
    }

    for (var i = 0; i < toks.length; i++) {
      add(toks[i]);
      if (i + 1 < toks.length) add('${toks[i]} ${toks[i + 1]}');
    }

    var norm = 0.0;
    final w = <int, double>{};
    tf.forEach((j, c) {
      final v = c * _idf[j];
      w[j] = v;
      norm += v * v;
    });
    norm = math.sqrt(norm);

    var z = _intercept;
    final contrib = <int, double>{};
    if (norm > 0) {
      w.forEach((j, v) {
        final c = v / norm * _coef[j];
        contrib[j] = c;
        z += c;
      });
    }
    final score = 1.0 / (1.0 + math.exp(-z));

    final reasons = contrib.entries.where((e) => e.value >= reasonThreshold).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ScamResult(
      score >= 0.5 ? 'scam' : 'genuine',
      score,
      reasons.take(maxReasons).map((e) => Reason(_terms[e.key], e.value)).toList(),
    );
  }
}
