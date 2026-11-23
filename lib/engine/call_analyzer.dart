import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

/// Rule-based scam-call transcript analyzer driven by assets/rules/call_rules.json.
class CallAnalyzer {
  final List<_Rule> _rules;
  final int _high;
  final int _medium;

  CallAnalyzer._(this._rules, this._high, this._medium);

  static Future<CallAnalyzer> load() async {
    final raw = await rootBundle.loadString('assets/rules/call_rules.json');
    return CallAnalyzer.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  factory CallAnalyzer.fromJson(Map<String, dynamic> j) {
    final levels = j['levels'] as Map<String, dynamic>;
    final rules = (j['rules'] as List).map((r) {
      final m = r as Map<String, dynamic>;
      return _Rule(
        m['type'] as String,
        (m['weight'] as num).toInt(),
        (m['phrases'] as List).map((p) => _Phrase(p.toString().toLowerCase())).toList(),
      );
    }).toList();
    return CallAnalyzer._(rules, (levels['high'] as num).toInt(), (levels['medium'] as num).toInt());
  }

  CallResult analyze(String transcript) {
    final text = transcript.toLowerCase();
    final matches = <CallMatch>[];
    final seen = <String>{};
    var total = 0;
    for (final r in _rules) {
      for (final p in r.phrases) {
        if (seen.contains(p.text) || !p.matches(text)) continue;
        seen.add(p.text);
        matches.add(CallMatch(p.text, r.type));
        total += r.weight;
      }
    }
    final risk = total >= _high ? 'high' : (total >= _medium ? 'medium' : 'low');
    return CallResult(risk, matches);
  }
}

class _Rule {
  final String type;
  final int weight;
  final List<_Phrase> phrases;
  _Rule(this.type, this.weight, this.phrases);
}

class _Phrase {
  final String text;
  final RegExp? _re;

  _Phrase(this.text)
      : _re = RegExp(r'[a-z0-9]').hasMatch(text)
            ? RegExp('(?<![a-z0-9])${RegExp.escape(text)}(?![a-z0-9])')
            : null;

  bool matches(String lower) => _re != null ? _re.hasMatch(lower) : lower.contains(text);
}
