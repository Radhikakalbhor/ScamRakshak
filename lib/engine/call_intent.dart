import 'live_call_analyzer.dart';
import 'models.dart';

/// One detected caller request for a sensitive item (or the pretext that backs it).
class IntentHit {
  /// [start, end) offsets in the analysed text (for the highlighted phrase).
  final int start;
  final int end;

  /// 'otp_request' (secret), 'details_request' (identifier) or 'impersonation' (pretext).
  final String type;
  final int weight;
  final String phrase;
  const IntentHit(this.start, this.end, this.type, this.weight, this.phrase);

  CallMatch get match => CallMatch(phrase, type);
}

typedef _Tok = ({String norm, int start, int end});

/// True when [b] adds no new trigger to show next to [a]: the same phrase, or the same type with one
/// phrase inside the other ('tell me the otp' vs 'please tell me the otp').
bool duplicateMatch(CallMatch a, CallMatch b) =>
    a.phrase == b.phrase ||
    (a.scriptType == b.scriptType && (a.phrase.contains(b.phrase) || b.phrase.contains(a.phrase)));

/// Intent rules: a caller REQUEST (give/share/tell/bata do/दीजिए...) near a SENSITIVE ITEM
/// (OTP, PIN, CVV, password, card/account/Aadhaar/PAN/KYC number), in English, Hindi and Hinglish,
/// tolerant of speech-to-text spacing ('o t p', 'o.t.p', 'ओ टी पी') and Devanagari spelling.
/// Configured by the "intents" section of assets/rules/call_rules.json.
///
/// Scoring (added to the phrase-rule scores by both analyzers, per type taking the larger value):
///   otp_request     = secret_weight     if a secret (OTP/PIN/CVV/password/code) is requested
///   details_request = identifier_weight if an identifier (card/account/Aadhaar/PAN/KYC no.) is requested
///   impersonation   = pretext_weight    if any request exists AND the call names a bank/KYC/police/
///                                       courier/customs pretext
/// With the defaults (4/3/3) and levels medium >= 3, high >= 6: asking for an OTP alone is MEDIUM,
/// asking for an OTP under a bank/KYC/police pretext is HIGH. Warnings ("never share your OTP",
/// "do not give", "मत बताइए") are not requests.
class CallIntentRules {
  final int window;
  final int secretWeight;
  final int identifierWeight;
  final int pretextWeight;
  final List<List<String>> verbs;
  final List<({List<String> toks, bool prefix})> secrets;
  final List<({List<String> toks, bool prefix})> identifiers;
  final List<List<String>> pretexts;
  final Set<String> negators;
  final Set<String> selfSpeakers;
  final Set<String> notSecretBefore;
  final Set<String> notSecretAfter;

  /// 'I need your OTP', 'OTP chahiye': demands, valid even with 'I' as subject.
  final List<List<String>> demandVerbs;

  /// Short items that also match one wrong letter of the same length ('otb', 'kic').
  final Set<String> fuzzyShort;

  CallIntentRules._(this.window, this.secretWeight, this.identifierWeight, this.pretextWeight, this.verbs, this.secrets,
      this.identifiers, this.pretexts, this.negators, this.selfSpeakers, this.notSecretBefore, this.notSecretAfter,
      this.demandVerbs, this.fuzzyShort);

  static List<String> _toks(String s) => LiveCallAnalyzer.tokenize(s).map((t) => t.norm).toList();

  static ({List<String> toks, bool prefix}) _item(String raw) {
    final t = raw.trim();
    final prefix = t.endsWith('*');
    return (toks: _toks(prefix ? t.substring(0, t.length - 1) : t), prefix: prefix);
  }

  static Set<String> _set(Object? list) => {for (final x in (list as List?) ?? const []) ..._toks(x.toString())};

  /// Adds a variant of every item for each speech-to-text alias of one of its words
  /// ('kyc number' -> 'kic number', 'kay why see number').
  static List<({List<String> toks, bool prefix})> _withAliases(
      List<({List<String> toks, bool prefix})> items, Map<String, List<List<String>>> aliases) {
    final out = [...items];
    for (final it in items) {
      for (var k = 0; k < it.toks.length; k++) {
        for (final alias in aliases[it.toks[k]] ?? const <List<String>>[]) {
          out.add((toks: [...it.toks.sublist(0, k), ...alias, ...it.toks.sublist(k + 1)], prefix: it.prefix));
        }
      }
    }
    return out;
  }

  /// Null when the rules file has no "intents" section.
  static CallIntentRules? fromJson(Map<String, dynamic> rules) {
    final j = rules['intents'] as Map<String, dynamic>?;
    if (j == null) return null;
    List<T> list<T>(String k, T Function(String) f) => [for (final x in (j[k] as List? ?? const [])) f(x.toString())];
    final aliases = <String, List<List<String>>>{};
    (j['aliases'] as Map? ?? const {}).forEach((k, v) {
      final key = _toks(k.toString());
      if (key.length != 1) return;
      aliases[key.single] = [for (final a in v as List) _toks(a.toString())];
    });
    final pretexts = _withAliases([for (final p in list('pretexts', _toks)) if (p.isNotEmpty) (toks: p, prefix: false)], aliases);
    return CallIntentRules._(
      (j['window'] as num?)?.toInt() ?? 6,
      (j['secret_weight'] as num?)?.toInt() ?? 4,
      (j['identifier_weight'] as num?)?.toInt() ?? 3,
      (j['pretext_weight'] as num?)?.toInt() ?? 3,
      list('request_verbs', _toks).where((v) => v.isNotEmpty).toList(),
      _withAliases(list('secret_items', _item).where((v) => v.toks.isNotEmpty).toList(), aliases),
      _withAliases(list('identifier_items', _item).where((v) => v.toks.isNotEmpty).toList(), aliases),
      [for (final p in pretexts) p.toks],
      _set(j['negators']),
      _set(j['self_speakers']),
      _set(j['not_secret_before']),
      _set(j['not_secret_after']),
      list('demand_verbs', _toks).where((v) => v.isNotEmpty).toList(),
      _set(j['fuzzy_short']),
    );
  }

  /// Finds requests and the pretext in [text].
  List<IntentHit> detect(String text) {
    final toks = LiveCallAnalyzer.tokenize(text);
    if (toks.isEmpty) return const [];
    // Sentence number of every token: a request never spans '.', '?', '!', '।' or a line break.
    final sentence = List<int>.filled(toks.length, 0);
    for (var i = 1; i < toks.length; i++) {
      final gap = text.substring(toks[i - 1].end, toks[i].start);
      sentence[i] = sentence[i - 1] + (RegExp(r'[.?!।॥\n]').hasMatch(gap) ? 1 : 0);
    }
    final real = <({int s, int e})>[];
    for (var i = 0; i < toks.length; i++) {
      for (final (list, checkSelf) in [(verbs, true), (demandVerbs, false)]) {
        final v = list.where((v) => _seqAt(toks, i, v)).firstOrNull;
        if (v == null) continue;
        // 'never share', 'do not give', 'मत बताइए' are warnings; 'we will send you an OTP' is the caller announcing.
        if (!_negatedVerb(toks, i, i + v.length) && !(checkSelf && _selfSpoken(toks, i))) {
          real.add((s: i, e: i + v.length));
        }
        break;
      }
    }
    if (real.isEmpty) return const [];

    final hits = <IntentHit>[];
    void scan(List<({List<String> toks, bool prefix})> items, String type, int weight, bool secret) {
      final seen = <String>{};
      for (var i = 0; i < toks.length; i++) {
        for (final it in items) {
          final e = _itemAt(toks, i, it.toks, it.prefix, fuzzyShort);
          if (e == null) continue;
          if (secret && i > 0 && notSecretBefore.contains(toks[i - 1].norm)) continue; // 'pin code', 'qr code'
          if (secret && e < toks.length && notSecretAfter.contains(toks[e].norm)) continue; // 'pin code'
          if (i > 0 && negators.contains(toks[i - 1].norm)) continue; // 'no otp needed'
          final v = _nearestVerb([for (final x in real) if (sentence[x.s] == sentence[i]) x], i, e);
          if (v == null) break;
          // Trigger phrase: verb..item when close ('give me the otp', 'ओटीपी बताइए'), else just the item.
          final close = (v.e <= i ? i - v.e : v.s - e) <= 3;
          final s = close && v.s < i ? v.s : i;
          final end = close && v.e > e ? v.e : e;
          final phrase = text.substring(toks[s].start, toks[end - 1].end).toLowerCase();
          if (seen.add(phrase)) hits.add(IntentHit(toks[s].start, toks[end - 1].end, type, weight, phrase));
          break;
        }
      }
    }

    scan(secrets, 'otp_request', secretWeight, true);
    scan(identifiers, 'details_request', identifierWeight, false);
    if (hits.isEmpty) return const [];
    for (var i = 0; i < toks.length; i++) {
      for (final p in pretexts) {
        final e = _itemAt(toks, i, p, false, fuzzyShort);
        if (e == null) continue;
        hits.add(IntentHit(toks[i].start, toks[e - 1].end, 'impersonation', pretextWeight,
            text.substring(toks[i].start, toks[e - 1].end).toLowerCase()));
        return hits; // one pretext is enough
      }
    }
    return hits;
  }

  ({int s, int e})? _nearestVerb(List<({int s, int e})> verbs, int is_, int ie) {
    for (final v in verbs) {
      final gap = v.e <= is_ ? is_ - v.e : (v.s >= ie ? v.s - ie : 0);
      if (gap <= window) return v;
    }
    return null;
  }

  static bool _seqAt(List<_Tok> toks, int i, List<String> seq) {
    if (i + seq.length > toks.length) return false;
    for (var k = 0; k < seq.length; k++) {
      if (toks[i + k].norm != seq[k]) return false;
    }
    return true;
  }

  /// End index when [item] starts at token [i]. A one-word item may also be spelled across up to
  /// 3 tokens ('o t p', 'ओ टी पी'); a prefix item allows a suffix ('otps'). Words of 5+ letters
  /// allow one edit ('pasword'); [fuzzyShort] items allow one wrong letter ('otb', 'kic').
  static int? _itemAt(List<_Tok> toks, int i, List<String> item, bool prefix, [Set<String> fuzzyShort = const {}]) {
    bool eq(String w, String p) {
      if (w == p) return true;
      if (prefix && w.startsWith(p) && w.length <= p.length + 2) return true;
      if (LiveCallAnalyzer.fuzzyEquals(w, p)) return true; // 5+ letters, edit distance 1
      if (!fuzzyShort.contains(p) || w.length != p.length || w.isEmpty || w[0] != p[0]) return false;
      var diff = 0;
      for (var k = 0; k < p.length; k++) {
        if (w.codeUnitAt(k) != p.codeUnitAt(k)) diff++;
      }
      return diff == 1;
    }
    if (item.length == 1) {
      var joined = '';
      for (var n = 1; n <= 3 && i + n <= toks.length; n++) {
        joined += toks[i + n - 1].norm;
        if (eq(joined, item[0])) return i + n;
        if (joined.length >= item[0].length + 2) break;
      }
      return null;
    }
    if (i + item.length > toks.length) return null;
    for (var k = 0; k < item.length; k++) {
      final last = k == item.length - 1;
      if (!(last ? eq(toks[i + k].norm, item[k]) : toks[i + k].norm == item[k])) return null;
    }
    return i + item.length;
  }

  /// 'never share', 'do not give', 'mat batana' (before) and 'साझा न करें', 'share mat karo' (after).
  bool _negatedVerb(List<_Tok> toks, int s, int e) {
    for (var k = 1; k <= 3 && s - k >= 0; k++) {
      if (negators.contains(toks[s - k].norm)) return true;
    }
    for (var k = 0; k < 2 && e + k < toks.length; k++) {
      if (negators.contains(toks[e + k].norm)) return true;
    }
    return false;
  }

  /// 'we will send you an OTP', 'main bhej raha hu': the caller announces, not asks.
  bool _selfSpoken(List<_Tok> toks, int s) {
    for (var k = 1; k <= 2 && s - k >= 0; k++) {
      if (selfSpeakers.contains(toks[s - k].norm)) return true;
    }
    return false;
  }
}
