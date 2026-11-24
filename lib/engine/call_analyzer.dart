import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import 'call_floor.dart';
import 'call_intent.dart';
import 'models.dart';

/// Detailed scoring of one transcript (see [CallAnalyzer.score]).
class CallScore {
  /// Contract result: risk level + matched phrases (in transcript order).
  final CallResult result;

  /// Score per script type after applying each type's cap. Only matched types are present.
  final Map<String, int> byType;

  /// Sum of [byType]; compared against the risk levels.
  final int total;

  /// The request floor that raised the risk ([CallFloor]), if any.
  final FloorHit? floor;

  const CallScore(this.result, this.byType, this.total, [this.floor]);
}

/// A normalized transcript plus, for every normalized character, its index in the original text.
class NormalizedText {
  final String text;
  final List<int> sourceIndex;
  const NormalizedText(this.text, this.sourceIndex);
}

/// Rule-based scam-call transcript analyzer driven by assets/rules/call_rules.json.
class CallAnalyzer {
  static const String assetPath = 'assets/rules/call_rules.json';

  final List<_Phrase> _phrases; // longest first, so overlapping shorter phrases are not double counted
  final Map<String, int> _caps;
  final Set<String> _negators;
  final int _negationWindow;

  /// Caller-request intent rules ("intents" in call_rules.json); null if absent.
  final CallIntentRules? intents;

  /// Minimum total score for 'high' / 'medium' risk.
  final int highLevel;
  final int mediumLevel;

  CallAnalyzer._(this._phrases, this._caps, this._negators, this._negationWindow, this.highLevel, this.mediumLevel,
      this.intents);

  static Future<CallAnalyzer> load() async {
    final raw = await rootBundle.loadString(assetPath);
    return CallAnalyzer.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  factory CallAnalyzer.fromJson(Map<String, dynamic> j) {
    final levels = j['levels'] as Map<String, dynamic>;
    final high = (levels['high'] as num).toInt();
    final medium = (levels['medium'] as num).toInt();
    if (medium <= 0 || high <= medium) {
      throw FormatException('call_rules.json: need 0 < medium < high, got medium=$medium high=$high');
    }
    final negators = ((j['negators'] as List?) ?? const []).map((e) => normalize(e.toString()).text).toSet();
    final window = (j['negation_window'] as num?)?.toInt() ?? 2;

    final phrases = <_Phrase>[];
    final caps = <String, int>{};
    for (final r in (j['rules'] as List).cast<Map<String, dynamic>>()) {
      final type = r['type'] as String;
      final negatable = r['negatable'] == true;
      final raw = r['phrases'];
      final weighted = <MapEntry<int, String>>[];
      if (raw is Map) {
        raw.forEach((w, list) {
          for (final p in list as List) {
            weighted.add(MapEntry(int.parse(w.toString()), p.toString()));
          }
        });
      } else {
        final w = (r['weight'] as num).toInt();
        for (final p in raw as List) {
          weighted.add(MapEntry(w, p.toString()));
        }
      }
      var sum = 0;
      for (final e in weighted) {
        final phrase = _Phrase.parse(e.value, type, e.key, negatable);
        if (phrase == null) continue;
        phrases.add(phrase);
        sum += e.key;
      }
      caps[type] = (r['cap'] as num?)?.toInt() ?? sum;
    }
    phrases.sort((a, b) => b.text.length.compareTo(a.text.length));
    return CallAnalyzer._(phrases, caps, negators, window, high, medium, CallIntentRules.fromJson(j));
  }

  /// Lowercases, turns punctuation (incl. Devanagari danda) into single spaces, trims, and drops
  /// nukta / zero-width joiners so 'फ़्रीज़' and 'फ्रीज' compare equal.
  static NormalizedText normalize(String input) {
    final out = <int>[];
    final idx = <int>[];
    for (var i = 0; i < input.length; i++) {
      var c = input.codeUnitAt(i);
      if (c >= 0x41 && c <= 0x5A) c += 0x20; // A-Z
      if (c == 0x093C || c == 0x200C || c == 0x200D) continue; // nukta, ZWNJ, ZWJ
      c = _nuktaBase[c] ?? c;
      if (_isWordChar(c)) {
        out.add(c);
        idx.add(i);
      } else if (out.isNotEmpty && out.last != 0x20) {
        out.add(0x20);
        idx.add(i);
      }
    }
    if (out.isNotEmpty && out.last == 0x20) {
      out.removeLast();
      idx.removeLast();
    }
    return NormalizedText(String.fromCharCodes(out), idx);
  }

  static const Map<int, int> _nuktaBase = {
    0x0958: 0x0915, 0x0959: 0x0916, 0x095A: 0x0917, 0x095B: 0x091C, //
    0x095C: 0x0921, 0x095D: 0x0922, 0x095E: 0x092B, 0x095F: 0x092F,
  };

  static bool _isWordChar(int c) =>
      (c >= 0x61 && c <= 0x7A) ||
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x0900 && c <= 0x097F && c != 0x0964 && c != 0x0965); // Devanagari except । ॥

  CallResult analyze(String transcript) => score(transcript).result;

  /// Full scoring: matched phrases, per-type scores and total.
  ///
  /// Formula (rule evidence only; the SMS classifier is not used for calls):
  ///   phrase[type] = min(cap[type], sum of weights of distinct matched phrases of that type)
  ///   intent[type] = weight of the strongest caller-request hit of that type ([CallIntentRules])
  ///   byType[type] = max(phrase[type], intent[type])        (no double counting of the same evidence)
  ///   total        = sum of byType;  high if total >= levels.high, medium if >= levels.medium.
  CallScore score(String transcript) {
    final norm = normalize(transcript);
    final text = norm.text;
    if (text.isEmpty) return const CallScore(CallResult('low', []), {}, 0);

    final taken = <List<int>>[]; // accepted [start, end) spans in normalized text
    final found = <({int start, CallMatch match, int weight})>[];
    for (final p in _phrases) {
      for (final m in p.re.allMatches(text)) {
        if (taken.any((s) => m.start < s[1] && s[0] < m.end)) continue;
        if (p.negatable && _negated(text, m.start)) continue;
        taken.add([m.start, m.end]);
        final original = transcript.substring(norm.sourceIndex[m.start], norm.sourceIndex[m.end - 1] + 1);
        // start: offset in the original transcript (comparable with intent hits).
        found.add((start: norm.sourceIndex[m.start], match: CallMatch(original.toLowerCase(), p.type), weight: p.weight));
        break; // each distinct phrase counts once
      }
    }

    final raw = <String, int>{};
    for (final f in found) {
      raw[f.match.scriptType] = (raw[f.match.scriptType] ?? 0) + f.weight;
    }
    final byType = raw.map((t, s) => MapEntry(t, math.min(s, _caps[t] ?? s)));

    for (final h in intents?.detect(transcript) ?? const <IntentHit>[]) {
      byType[h.type] = math.max(byType[h.type] ?? 0, h.weight);
      if (!found.any((f) => duplicateMatch(f.match, h.match))) {
        found.add((start: h.start, match: h.match, weight: h.weight));
      }
    }
    final total = byType.values.fold(0, (a, b) => a + b);
    final weighted = total >= highLevel ? 'high' : (total >= mediumLevel ? 'medium' : 'low');
    // Deterministic floor after the weighted score: secret/KYC request (+ pretext) => medium/high.
    final floor = CallFloor.evaluate(transcript);
    final risk = CallFloor.raise(weighted, floor);
    if (floor != null) {
      final lower = transcript.toLowerCase();
      for (final m in floor.matches) {
        if (CallFloor.overlapsAny(m, [for (final f in found) f.match]) || found.any((f) => duplicateMatch(f.match, m))) continue;
        found.add((start: math.max(0, lower.indexOf(m.phrase)), match: m, weight: 0));
      }
    }
    found.sort((a, b) => a.start.compareTo(b.start));
    debugPrint('[detect] CallAnalyzer risk=$risk (weighted=$weighted floor=${floor?.level ?? '-'}${floor == null ? '' : ': ${floor.reason}'}) '
        'total=$total byType=$byType '
        '(medium>=$mediumLevel high>=$highLevel; byType=max(capped phrases, intent); classifier not used) '
        'matches=${[for (final f in found) '${f.match.phrase}/${f.match.scriptType}/${f.weight}']}');
    return CallScore(CallResult(risk, [for (final f in found) f.match]), byType, total, floor);
  }

  bool _negated(String text, int start) {
    if (_negators.isEmpty || start == 0) return false;
    final before = text.substring(0, start).trimRight().split(' ');
    for (var k = 0; k < _negationWindow && k < before.length; k++) {
      if (_negators.contains(before[before.length - 1 - k])) return true;
    }
    return false;
  }
}

class _Phrase {
  final String text;
  final String type;
  final int weight;
  final bool negatable;
  final RegExp re;

  _Phrase(this.text, this.type, this.weight, this.negatable, bool prefix)
    : re = RegExp('(?<![^ ])${RegExp.escape(text)}${prefix ? '[^ ]*' : ''}(?![^ ])');

  /// `otp bata*` -> prefix phrase 'otp bata'. Returns null for phrases that normalize to nothing.
  static _Phrase? parse(String raw, String type, int weight, bool negatable) {
    final trimmed = raw.trim();
    final prefix = trimmed.endsWith('*');
    final text = CallAnalyzer.normalize(prefix ? trimmed.substring(0, trimmed.length - 1) : trimmed).text;
    if (text.isEmpty || weight <= 0) return null;
    return _Phrase(text, type, weight, negatable, prefix);
  }
}
