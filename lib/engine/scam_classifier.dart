import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

/// Offline TF-IDF + logistic regression scam classifier.
///
/// Reproduces ml/preprocess.py + ml/train.py (sklearn TfidfVectorizer + LogisticRegression)
/// from assets/models/scam_model.json:
/// lowercase -> URLs to ' urltoken ' -> token regex (Latin + Devanagari) -> 1-2 grams ->
/// raw count * idf -> l2 normalize -> dot coef + intercept -> sigmoid.
class ScamClassifier {
  static const String assetPath = 'assets/models/scam_model.json';

  /// Number of reasons returned by [classify].
  static const int maxReasons = 5;

  /// Python's `\s` for str patterns (str.isspace); Dart/JS `\s` differs slightly
  /// (it lacks \x1c-\x1f and \x85, and adds ﻿), so URL matching uses this set instead.
  static const String _pyWhitespace =
      '\\t\\n\\x0b\\x0c\\r\\x1c-\\x1f \\x85\\xa0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000';

  final Map<String, int> _vocab;
  final List<double> _idf;
  final List<double> _coef;
  final double _intercept;
  final RegExp _url;
  final String _urlReplacement;
  final RegExp _token;
  final String _joiner;
  final int _minN;
  final int _maxN;

  /// index -> n-gram (inverse of [_vocab]), for reasons.
  final List<String> _terms;

  ScamClassifier._(
    this._vocab,
    this._idf,
    this._coef,
    this._intercept,
    this._url,
    this._urlReplacement,
    this._token,
    this._joiner,
    this._minN,
    this._maxN,
  ) : _terms = _invert(_vocab, _idf.length);

  static List<String> _invert(Map<String, int> vocab, int n) {
    final t = List<String>.filled(n, '');
    vocab.forEach((g, j) => t[j] = g);
    return t;
  }

  /// Loads the exported model from the app bundle.
  static Future<ScamClassifier> load() async {
    final raw = await rootBundle.loadString(assetPath);
    return ScamClassifier.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  factory ScamClassifier.fromJson(Map<String, dynamic> j) {
    final p = j['preprocessing'] as Map<String, dynamic>;
    final vocab = (j['vocab'] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt()));
    final idf = (j['idf'] as List).map((e) => (e as num).toDouble()).toList(growable: false);
    final coef = (j['coef'] as List).map((e) => (e as num).toDouble()).toList(growable: false);
    if (idf.length != coef.length) {
      throw FormatException('scam_model.json: idf (${idf.length}) and coef (${coef.length}) differ');
    }
    final range = (p['ngram_range'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const [1, 2];
    return ScamClassifier._(
      vocab,
      idf,
      coef,
      (j['intercept'] as num).toDouble(),
      RegExp(_pythonWhitespace(p['url_regex'] as String)),
      p['url_replacement'] as String,
      RegExp(p['token_regex'] as String),
      (p['ngram_joiner'] as String?) ?? ' ',
      range[0],
      range[1],
    );
  }

  /// Rewrites `\s` in a Python regex to Python's exact whitespace set.
  static String _pythonWhitespace(String pattern) =>
      pattern.replaceAll(r'[^\s]', '[^$_pyWhitespace]').replaceAll(r'\s', '[$_pyWhitespace]');

  /// Same as ml/preprocess.py `tokenize`.
  List<String> tokenize(String text) {
    final s = text.toLowerCase().replaceAll(_url, _urlReplacement);
    return _token.allMatches(s).map((m) => m.group(0)!).toList();
  }

  ScamResult classify(String text) {
    final toks = tokenize(text);

    // Raw term counts over in-vocabulary n-grams (sklearn word n-grams, joined by a space).
    final tf = <int, int>{};
    for (var n = _minN; n <= _maxN; n++) {
      for (var i = 0; i + n <= toks.length; i++) {
        final j = _vocab[n == 1 ? toks[i] : toks.sublist(i, i + n).join(_joiner)];
        if (j != null) tf[j] = (tf[j] ?? 0) + 1;
      }
    }

    // tf * idf, then l2 normalization.
    final w = <int, double>{};
    var sq = 0.0;
    tf.forEach((j, c) {
      final v = c * _idf[j];
      w[j] = v;
      sq += v * v;
    });
    final norm = math.sqrt(sq);

    // Logit = intercept + sum(tfidf * coef). Each term's tfidf * coef is its contribution.
    var z = _intercept;
    final contrib = <int, double>{};
    if (norm > 0) {
      w.forEach((j, v) {
        final c = v / norm * _coef[j];
        contrib[j] = c;
        z += c;
      });
    }
    final score = _sigmoid(z);

    // Reasons: n-grams present in the text that push towards scam, strongest first.
    final positive = contrib.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : _terms[a.key].compareTo(_terms[b.key]);
      });
    return ScamResult(
      score >= 0.5 ? 'scam' : 'genuine',
      score,
      positive.take(maxReasons).map((e) => Reason(_terms[e.key], e.value)).toList(growable: false),
    );
  }

  /// Numerically stable logistic function.
  static double _sigmoid(double z) {
    if (z >= 0) return 1.0 / (1.0 + math.exp(-z));
    final e = math.exp(z);
    return e / (1.0 + e);
  }
}
