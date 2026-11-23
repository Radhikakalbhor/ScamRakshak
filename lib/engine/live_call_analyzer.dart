import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

/// Running state of a live call (see AGENTS.md).
class LiveCallState {
  /// 'high' | 'medium' | 'low'
  final String risk;

  /// 0..1 scam strength (1.0 once risk is high).
  final double score;

  /// All matches so far in the call, deduped, in transcript order.
  final List<CallMatch> matches;

  /// Matches found by the latest [LiveCallAnalyzer.add] only.
  final List<CallMatch> newMatches;

  /// Running transcript (all chunks joined by spaces).
  final String transcript;

  const LiveCallState(this.risk, this.score, this.matches, this.newMatches, this.transcript);

  static const empty = LiveCallState('low', 0, [], [], '');
}

/// Incremental, ASR-noise tolerant analyzer over assets/rules/call_rules.json.
class LiveCallAnalyzer {
  static const String assetPath = 'assets/rules/call_rules.json';

  final List<_LivePhrase> _phrases; // most tokens / longest first
  final Map<String, int> _caps;
  final Set<String> _negators;
  final int _negationWindow;
  final int highLevel;
  final int mediumLevel;
  final int _maxTokens;

  final List<String> _chunks = [];
  final List<({int start, int end, int phrase, CallMatch match})> _found = [];

  LiveCallAnalyzer._(this._phrases, this._caps, this._negators, this._negationWindow, this.highLevel, this.mediumLevel)
    : _maxTokens = _phrases.fold(1, (m, p) => math.max(m, p.tokens.length));

  static Future<LiveCallAnalyzer> load() async =>
      LiveCallAnalyzer.fromJson(jsonDecode(await rootBundle.loadString(assetPath)) as Map<String, dynamic>);

  factory LiveCallAnalyzer.fromJson(Map<String, dynamic> j) {
    final levels = j['levels'] as Map<String, dynamic>;
    final high = (levels['high'] as num).toInt();
    final medium = (levels['medium'] as num).toInt();
    final negators = <String>{
      for (final n in (j['negators'] as List?) ?? const []) ...tokenize(n.toString()).map((t) => t.norm),
    };
    final window = (j['negation_window'] as num?)?.toInt() ?? 2;
    final phrases = <_LivePhrase>[];
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
        for (final p in raw as List) {
          weighted.add(MapEntry((r['weight'] as num).toInt(), p.toString()));
        }
      }
      var sum = 0;
      for (final e in weighted) {
        final t = e.value.trim();
        final prefix = t.endsWith('*');
        final toks = tokenize(prefix ? t.substring(0, t.length - 1) : t).map((x) => x.norm).toList();
        if (toks.isEmpty || e.key <= 0) continue;
        phrases.add(_LivePhrase(toks, type, e.key, negatable, prefix));
        sum += e.key;
      }
      caps[type] = (r['cap'] as num?)?.toInt() ?? sum;
    }
    phrases.sort((a, b) {
      final c = b.tokens.length.compareTo(a.tokens.length);
      return c != 0 ? c : b.tokens.join(' ').length.compareTo(a.tokens.join(' ').length);
    });
    return LiveCallAnalyzer._(phrases, caps, negators, window, high, medium);
  }

  /// Normalizes one character run: lowercase, drop nukta / ZWJ / ZWNJ / apostrophes,
  /// precomposed nukta letters -> base letter, drop chandrabindu / anusvara / visarga, and fold
  /// Devanagari letters that speech-to-text confuses (long/short vowels, aspirated/plain and
  /// retroflex/dental consonants, श/ष/स), so 'दिजितल अरेस्ट' matches 'डिजिटल अरेस्ट'.
  static String normalizeWord(String w) {
    final out = StringBuffer();
    for (final c in w.runes) {
      var x = c;
      if (x >= 0x41 && x <= 0x5A) x += 0x20;
      if (x == 0x093C || x == 0x200C || x == 0x200D || x == 0x27 || x == 0x2019) continue;
      if (x == 0x0901 || x == 0x0902 || x == 0x0903) continue;
      x = _nuktaBase[x] ?? x;
      x = _fold[x] ?? x;
      out.writeCharCode(x);
    }
    return out.toString();
  }

  static const Map<int, int> _fold = {
    // vowels: ई->इ ऊ->उ ी->ि ू->ु ऑ->ओ ॉ->ो ऍ->ए ॅ->े
    0x0908: 0x0907, 0x090A: 0x0909, 0x0940: 0x093F, 0x0942: 0x0941, //
    0x0911: 0x0913, 0x0949: 0x094B, 0x090D: 0x090F, 0x0945: 0x0947,
    // aspirated -> plain: ख घ छ झ थ ध फ भ
    0x0916: 0x0915, 0x0918: 0x0917, 0x091B: 0x091A, 0x091D: 0x091C,
    0x0925: 0x0924, 0x0927: 0x0926, 0x092B: 0x092A, 0x092D: 0x092C,
    // retroflex -> dental: ट ठ ड ढ ण
    0x091F: 0x0924, 0x0920: 0x0924, 0x0921: 0x0926, 0x0922: 0x0926, 0x0923: 0x0928,
    // sibilants: श ष -> स
    0x0936: 0x0938, 0x0937: 0x0938,
  };

  static const Map<int, int> _nuktaBase = {
    0x0958: 0x0915, 0x0959: 0x0916, 0x095A: 0x0917, 0x095B: 0x091C, //
    0x095C: 0x0921, 0x095D: 0x0922, 0x095E: 0x092B, 0x095F: 0x092F,
  };

  static bool _isWordChar(int c) =>
      (c >= 0x61 && c <= 0x7A) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x30 && c <= 0x39) ||
      c == 0x27 || c == 0x2019 || c == 0x200C || c == 0x200D ||
      (c >= 0x0900 && c <= 0x097F && c != 0x0964 && c != 0x0965);

  /// Splits [text] into normalized tokens with their [start, end) offsets in [text].
  static List<({String norm, int start, int end})> tokenize(String text) {
    final out = <({String norm, int start, int end})>[];
    var i = 0;
    while (i < text.length) {
      if (!_isWordChar(text.codeUnitAt(i))) {
        i++;
        continue;
      }
      final s = i;
      while (i < text.length && _isWordChar(text.codeUnitAt(i))) {
        i++;
      }
      final n = normalizeWord(text.substring(s, i));
      if (n.isNotEmpty) out.add((norm: n, start: s, end: i));
    }
    return out;
  }

  /// Edit distance <= 1 (Levenshtein), allowed only when both tokens have 5+ characters.
  static bool fuzzyEquals(String a, String b) {
    if (a == b) return true;
    if (a.length < 5 || b.length < 5 || (a.length - b.length).abs() > 1) return false;
    var i = 0;
    while (i < a.length && i < b.length && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    if (a.length == b.length) return a.substring(i + 1) == b.substring(i + 1);
    return a.length > b.length ? a.substring(i + 1) == b.substring(i) : a.substring(i) == b.substring(i + 1);
  }

  static bool _tokenMatches(String word, String pat, bool prefix) {
    if (fuzzyEquals(word, pat)) return true;
    if (!prefix) return false;
    if (word.startsWith(pat)) return true;
    return word.length > pat.length && fuzzyEquals(word.substring(0, pat.length), pat);
  }

  void reset() {
    _chunks.clear();
    _found.clear();
  }

  String get transcript => _chunks.join(' ');

  /// Adds one transcribed chunk and returns the updated call state.
  LiveCallState add(String chunkText) {
    final before = tokenize(transcript).length;
    final clean = chunkText.trim();
    if (clean.isNotEmpty) _chunks.add(clean);
    final text = transcript;
    final toks = tokenize(text);
    final from = math.max(0, before - _maxTokens + 1);
    final fresh = <CallMatch>[];
    final have = {for (final f in _found) f.phrase};
    for (var pi = 0; pi < _phrases.length; pi++) {
      if (have.contains(pi)) continue;
      final p = _phrases[pi];
      final n = p.tokens.length;
      for (var s = from; s + n <= toks.length; s++) {
        var ok = true;
        for (var k = 0; k < n && ok; k++) {
          ok = _tokenMatches(toks[s + k].norm, p.tokens[k], p.prefix && k == n - 1);
        }
        if (!ok) continue;
        final e = s + n;
        if (_found.any((f) => s < f.end && f.start < e)) continue;
        if (p.negatable && _negated(toks, s)) continue;
        final m = CallMatch(text.substring(toks[s].start, toks[e - 1].end).toLowerCase(), p.type);
        _found.add((start: s, end: e, phrase: pi, match: m));
        fresh.add(m);
        break;
      }
    }
    _found.sort((a, b) => a.start.compareTo(b.start));
    return _state(text, fresh);
  }

  bool _negated(List<({String norm, int start, int end})> toks, int s) {
    for (var k = 1; k <= _negationWindow && s - k >= 0; k++) {
      if (_negators.contains(toks[s - k].norm)) return true;
    }
    return false;
  }

  LiveCallState _state(String text, List<CallMatch> fresh) {
    final raw = <String, int>{};
    var strongest = 0;
    for (final f in _found) {
      final w = _phrases[f.phrase].weight;
      raw[f.match.scriptType] = (raw[f.match.scriptType] ?? 0) + w;
      if (f.match.scriptType != 'pressure') strongest = math.max(strongest, w);
    }
    final byType = raw.map((t, v) => MapEntry(t, math.min(v, _caps[t] ?? v)));
    final total = byType.values.fold(0, (a, b) => a + b);
    final strongTypes = byType.entries.where((e) => e.key != 'pressure' && e.value >= 2).length;
    final risk = (total >= highLevel || strongTypes >= 2)
        ? 'high'
        : (total >= mediumLevel || strongest >= 3 ? 'medium' : 'low');
    final score = risk == 'high' ? 1.0 : math.min(0.95, total / highLevel);
    return LiveCallState(risk, score, List.unmodifiable([for (final f in _found) f.match]), fresh, text);
  }
}

class _LivePhrase {
  final List<String> tokens;
  final String type;
  final int weight;
  final bool negatable;
  final bool prefix;
  const _LivePhrase(this.tokens, this.type, this.weight, this.negatable, this.prefix);
}
