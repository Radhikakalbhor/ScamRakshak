import 'live_call_analyzer.dart';
import 'models.dart';

/// Result of [CallFloor.evaluate]: the minimum risk the call must get, and why.
class FloorHit {
  /// 'medium' (sensitive item + request) or 'high' (+ bank / authority pretext).
  final String level;

  /// Key phrases as they appear in the ORIGINAL transcript (item, request cue, pretext).
  final List<CallMatch> matches;

  /// Human-readable reason (debug log / tests).
  final String reason;

  const FloorHit(this.level, this.matches, this.reason);
}

/// Deterministic floor applied after the weighted score (shared by every call entry point):
///   sensitive item (OTP, PIN, CVV, password, card/account/Aadhaar/PAN number, KYC, bank details,
///   passbook) + request cue (give, share, tell, send, need, asking for, bata do, दीजिए...) in the
///   same or the adjacent sentence, within [window] tokens  => at least MEDIUM;
///   + a pretext (from ... bank, update your KYC/password/details, account blocked, police/RBI...)
///   => at least HIGH.
/// Advice ("never share your OTP", "do not give", "मत बताइए") never triggers it.
/// ASR-tolerant: spelled letters (O T P, o.t.p, K Y C), "oh tee pee", "kay why see", one-letter
/// slips of OTP/KYC (otb, kic), Devanagari folding via [LiveCallAnalyzer.tokenize].
class CallFloor {
  static const int window = 25;

  /// Minimum percentages so the shown level and percentage agree.
  static const double highMin = 0.85;
  static const double mediumMin = 0.55;

  static String _n(String w) => LiveCallAnalyzer.normalizeWord(w);
  static Set<String> _set(List<String> l) => {for (final w in l) _n(w)};

  // Single-token sensitive items -> script type.
  static final Map<String, String> _secretWords = {
    for (final w in ['otp', 'ओटीपी', 'cvv', 'सीवीवी', 'password', 'passcode', 'पासवर्ड', 'mpin', 'upipin', 'pin', 'पिन'])
      _n(w): 'otp_request',
    for (final w in ['kyc', 'केवाईसी', 'aadhaar', 'aadhar', 'adhaar', 'adhar', 'आधार', 'passbook', 'पासबुक'])
      _n(w): 'fake_kyc',
  };

  /// Short words also matched with one edit (ASR: otb, kic). Kept to these two: 'pin'/'pan' with an
  /// edit would hit everyday words.
  static const _fuzzyShort = ['otp', 'kyc'];

  /// "<word> number/details/no": card number, account number, PAN number, bank details.
  static final _needsNumber = _set(['card', 'account', 'acount', 'pan', 'bank', 'khata', 'खाता', 'कार्ड', 'बैंक', 'atm', 'debit', 'credit']);
  static final _numberWords = _set(['number', 'numbers', 'no', 'details', 'detail', 'नंबर', 'डिटेल', 'details']);

  static final _cues = _set([
    'give', 'share', 'tell', 'send', 'read', 'provide', 'confirm', 'verify', 'need', 'needs', 'want', 'asking',
    'enter', 'type', 'forward', 'say', 'chahiye', 'chahie', 'चाहिए', 'dedo', 'dijiye', 'dijie', 'दीजिए', 'दीजिये',
    'bhejo', 'bhejiye', 'भेजो', 'भेजिए', 'do', 'दो', 'de', 'दे',
  ]);
  static final _cuePrefixes = _set(['bata', 'बता', 'bol', 'बोल', 'likh', 'लिख']);

  static final _negators = _set([
    'never', 'not', 'dont', 'don', 'doesnt', 'nobody', 'mat', 'मत', 'nahi', 'nahin', 'नहीं', 'नही', 'kabhi', 'कभी', 'avoid', 'beware',
  ]);

  static final _bank = _set(['bank', 'बैंक', 'banking']);
  static final _from = _set(['from', 'se', 'से']);
  static final _update = _set(['update', 'updating', 'updated', 'अपडेट', 'renew', 'verify', 'verification', 'link', 'reactivate']);
  static final _updateTargets = _set([
    'kyc', 'केवाईसी', 'password', 'पासवर्ड', 'details', 'detail', 'statement', 'passbook', 'पासबुक', 'account', 'खाता', 'card', 'pan', 'aadhaar', 'aadhar',
  ]);
  static final _block = _set(['blocked', 'block', 'band', 'बंद', 'suspend', 'suspended', 'freeze', 'frozen', 'deactivated', 'closed']);
  static final _blockTargets = _set(['account', 'card', 'khata', 'खाता', 'sim', 'number', 'कार्ड']);
  static final _authority = _set([
    'police', 'पुलिस', 'cbi', 'rbi', 'customs', 'cyber', 'officer', 'inspector', 'court', 'trai', 'income', 'manager', 'executive',
  ]);

  static int _dist(String a, String b) {
    if ((a.length - b.length).abs() > 1) return 2;
    final d = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0));
    for (var i = 0; i <= a.length; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final c = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        d[i][j] = [d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + c].reduce((x, y) => x < y ? x : y);
      }
    }
    return d[a.length][b.length];
  }

  /// Tokens with spelled-out letters merged ("O T P" -> otp) and spoken letters ("oh tee pee").
  static List<({String norm, int start, int end, int sent})> _tokens(String text) {
    final raw = LiveCallAnalyzer.tokenize(text);
    // Sentence index per token from the original punctuation.
    final out = <({String norm, int start, int end, int sent})>[];
    var sent = 0;
    var last = 0;
    final endRe = RegExp(r'[.?!।॥\n]');
    var i = 0;
    while (i < raw.length) {
      final t = raw[i];
      if (endRe.hasMatch(text.substring(last, t.start))) sent++;
      // Spelled letters: run of 1-letter latin tokens (O T P, o.t.p, K Y C).
      var j = i;
      final buf = StringBuffer();
      while (j < raw.length && raw[j].norm.length == 1 && RegExp('[a-z]').hasMatch(raw[j].norm) && j - i < 4) {
        if (j > i && endRe.hasMatch(text.substring(raw[j - 1].end, raw[j].start)) && !text.substring(raw[j - 1].end, raw[j].start).contains('.')) break;
        buf.write(raw[j].norm);
        j++;
      }
      if (j - i >= 2) {
        out.add((norm: buf.toString(), start: t.start, end: raw[j - 1].end, sent: sent));
        last = raw[j - 1].end;
        i = j;
        continue;
      }
      // Spoken letters.
      final three = i + 2 < raw.length ? '${raw[i].norm} ${raw[i + 1].norm} ${raw[i + 2].norm}' : '';
      final spoken = const {'oh tee pee': 'otp', 'o tee pee': 'otp', 'kay why see': 'kyc', 'k why see': 'kyc', 'kay wai si': 'kyc'}[three];
      if (spoken != null) {
        out.add((norm: spoken, start: t.start, end: raw[i + 2].end, sent: sent));
        last = raw[i + 2].end;
        i += 3;
        continue;
      }
      out.add((norm: t.norm, start: t.start, end: t.end, sent: sent));
      last = t.end;
      i++;
    }
    return out;
  }

  static String? _itemType(List<({String norm, int start, int end, int sent})> t, int i) {
    var w = t[i].norm;
    if (w.endsWith('s') && w.length > 3 && _secretWords.containsKey(w.substring(0, w.length - 1))) {
      w = w.substring(0, w.length - 1); // plurals: otps, pins
    }
    if (w == _n('pin') && i + 1 < t.length && t[i + 1].norm == 'code') return null; // postal PIN code
    final direct = _secretWords[w];
    if (direct != null) return direct;
    for (final s in _fuzzyShort) {
      if (w.length >= 3 && w.length <= 4 && _dist(w, s) <= 1 && !_commonShort.contains(w)) {
        return s == 'otp' ? 'otp_request' : 'fake_kyc';
      }
    }
    if (_needsNumber.contains(w) && i + 1 < t.length && _numberWords.contains(t[i + 1].norm)) {
      return (w == _n('card') || w == 'atm' || w == 'debit' || w == 'credit') ? 'otp_request' : 'fake_kyc';
    }
    if (w == _n('bank') && i + 2 < t.length && t[i + 1].norm == 'account' && _numberWords.contains(t[i + 2].norm)) {
      return 'fake_kyc';
    }
    return null;
  }

  /// Everyday words one edit away from otp / kyc that must not count.
  static const _commonShort = {'top', 'oto', 'ott', 'kya', 'key', 'kys', 'cry', 'got', 'not', 'hot', 'pot', 'lot', 'dot', 'rot', 'out', 'opt', 'otc', 'kyo'};

  static final _needCues = _set(['need', 'needs', 'want', 'asking']);
  static final _toListener = _set(['your', 'you', 'aapka', 'aapki', 'apna', 'apni', 'आपका', 'आपकी', 'अपना', 'अपनी', 'tumhara']);
  static final _callerSubject = _set(['we', 'will', 'well', 'll', 'shall', 'i', 'im', 'hum', 'ham', 'हम', 'bank', 'system']);
  static final _listenerSubject = _set(['you', 'please', 'kindly', 'can', 'could', 'aap', 'आप', 'pls', 'plz', 'just', 'now']);
  static final _inPerson = _set(['branch', 'visit', 'shakha', 'शाखा']);

  static bool _isCue(List<({String norm, int start, int end, int sent})> t, int i) {
    final ok = _isCueWord(t, i);
    if (!ok) return false;
    // "visit the branch to verify your KYC" is a genuine instruction, not a request over the phone.
    if (t.any((x) => x.sent == t[i].sent && _inPerson.contains(x.norm))) return false;
    final w = t[i].norm;
    if (_needCues.contains(w)) {
      // "I need / I'm asking for YOUR OTP" -- not "you need to update KYC".
      for (var k = i + 1; k <= i + 3 && k < t.length; k++) {
        if (_toListener.contains(t[k].norm) || _itemType(t, k) != null) return true;
      }
      return false;
    }
    // "... an OTP to verify your number": purpose, not a request.
    if (i > 0 && t[i - 1].norm == 'to') return false;
    // "We will send you an OTP", "I will tell you" -> the caller acts, not a request.
    for (var k = i - 1; k >= i - 3 && k >= 0 && t[k].sent == t[i].sent; k--) {
      if (_listenerSubject.contains(t[k].norm)) return true;
      if (_callerSubject.contains(t[k].norm)) return false;
    }
    return true;
  }

  static bool _isCueWord(List<({String norm, int start, int end, int sent})> t, int i) {
    final w = t[i].norm;
    if (_cues.contains(w)) {
      // 'do' / 'de' only as Hindi "bata do", "de do", "OTP de": needs an item or 'bata' right before.
      if (w == 'do' || w == 'दो' || w == 'de' || w == 'दे') {
        return i > 0 && (_itemType(t, i - 1) != null || t[i - 1].norm.startsWith('bata') || t[i - 1].norm == 'de');
      }
      return true;
    }
    return _cuePrefixes.any(w.startsWith);
  }

  static bool _negatedSentence(List<({String norm, int start, int end, int sent})> t, int sent) =>
      t.any((x) => x.sent == sent && _negators.contains(x.norm));

  static int? _pretext(List<({String norm, int start, int end, int sent})> t, int from, int to) {
    bool near(int i, Set<String> targets, int span) {
      for (var k = i - span; k <= i + span; k++) {
        if (k >= 0 && k < t.length && k != i && targets.contains(t[k].norm)) return true;
      }
      return false;
    }

    for (var i = from; i < to && i < t.length; i++) {
      final w = t[i].norm;
      if (_bank.contains(w)) {
        // "from LGI Bank", "calling from State Bank of India", "bank se bol raha"
        for (var k = i - 4; k < i; k++) {
          if (k >= 0 && _from.contains(t[k].norm)) return i;
        }
        if (i + 1 < t.length && _from.contains(t[i + 1].norm)) return i;
      }
      if (_update.contains(w) && near(i, _updateTargets, 4)) return i;
      if (_block.contains(w) && near(i, _blockTargets, 4)) return i;
      if (_authority.contains(w)) return i;
    }
    return null;
  }

  static CallMatch _m(String text, int start, int end, String type) =>
      CallMatch(text.substring(start, end).toLowerCase(), type);

  /// Floor for [text] (the whole transcript so far), or null when it does not apply.
  static FloorHit? evaluate(String text) {
    final t = _tokens(text);
    if (t.isEmpty) return null;
    final items = <int, String>{};
    final cues = <int>[];
    for (var i = 0; i < t.length; i++) {
      final ty = _itemType(t, i);
      if (ty != null) items[i] = ty;
      if (_isCue(t, i)) cues.add(i);
    }
    if (items.isEmpty || cues.isEmpty) return null;
    // Every valid (item, request) pair contributes its phrases, so all request sentences are shown.
    final all = <CallMatch>[];
    String? level;
    String? reason;
    void keep(String lv, List<CallMatch> ms, String why) {
      for (final m in ms) {
        if (!all.any((x) => x.phrase == m.phrase)) all.add(m);
      }
      if (level != 'high') {
        level = lv;
        reason = why;
      }
    }

    for (final e in items.entries) {
      final ii = e.key;
      if (_negatedSentence(t, t[ii].sent)) continue;
      for (final c in cues) {
        if ((c - ii).abs() > window || (t[c].sent - t[ii].sent).abs() > 1) continue;
        if (_negatedSentence(t, t[c].sent)) continue;
        final matches = <CallMatch>[];
        // Item (with its "number/details" word) and the request (cue + up to 4 words: "give it to me").
        final itemEnd = (ii + 1 < t.length && _numberWords.contains(t[ii + 1].norm)) ? t[ii + 1].end : t[ii].end;
        matches.add(_m(text, t[ii].start, itemEnd, e.value));
        var ce = c;
        while (ce + 1 < t.length && ce - c < 4 && t[ce + 1].sent == t[c].sent && !items.containsKey(ce + 1)) {
          ce++;
        }
        matches.add(_m(text, t[c].start, t[ce].end, e.value));
        final lo = [ii, c].reduce((a, b) => a < b ? a : b);
        final hi = [ii, c].reduce((a, b) => a > b ? a : b);
        final sentLo = t[lo].sent - 1;
        final sentHi = t[hi].sent + 1;
        final from = t.indexWhere((x) => x.sent >= sentLo);
        final to = t.lastIndexWhere((x) => x.sent <= sentHi) + 1;
        var p = _pretext(t, from, to);
        // Direct demand for a one-time secret ("अपना ओटीपी बताइए", "give me your PIN"): no genuine
        // caller asks for it, so it is HIGH even without a pretext.
        if (p == null && e.value == 'otp_request' && (c - ii).abs() <= 4) {
          for (var k = ii - 1; k >= ii - 3 && k >= 0; k--) {
            if (_toListener.contains(t[k].norm)) {
              p = k;
              break;
            }
          }
        }
        if (p != null && _negatedSentence(t, t[p].sent) && t[p].sent == t[ii].sent) continue;
        if (p != null) {
          final why = 'request for ${t[ii].norm} ("${matches[1].phrase}") with pretext "${text.substring(t[p].start, t[p].end)}"';
          if (p != ii - 1 && p != ii - 2 && p != ii - 3) matches.add(_m(text, t[p].start, t[p].end, 'impersonation'));
          keep('high', matches, why);
        } else {
          keep('medium', matches, 'request for ${t[ii].norm} ("${matches[1].phrase}")');
        }
      }
    }
    return level == null ? null : FloorHit(level!, all, reason!);
  }

  static const _rank = {'low': 0, 'medium': 1, 'high': 2};

  /// True when [m] shares a word with an already found phrase (so it is not listed twice).
  static bool overlapsAny(CallMatch m, Iterable<CallMatch> found) {
    final words = LiveCallAnalyzer.tokenize(m.phrase).map((x) => x.norm).toSet();
    return found.any((f) => LiveCallAnalyzer.tokenize(f.phrase).any((x) => words.contains(x.norm)));
  }

  /// The more severe of [risk] and the floor level.
  static String raise(String risk, FloorHit? hit) =>
      hit == null || _rank[hit.level]! <= _rank[risk]! ? risk : hit.level;

  /// Score consistent with [risk]: HIGH >= [highMin], MEDIUM >= [mediumMin] (never lowers).
  static double scoreFor(String risk, double score) => switch (risk) {
        'high' => score < highMin ? highMin : score,
        'medium' => score < mediumMin ? mediumMin : score,
        _ => score,
      };
}
