import '../../engine/models.dart';

/// A piece of transcript text, [highlighted] when it is part of a matched phrase (key words), and
/// [sentence] when it is inside a dangerous sentence (one that contains a request or scam phrase).
class TextPiece {
  final String text;
  final bool highlighted;
  final bool sentence;
  const TextPiece(this.text, this.highlighted, [this.sentence = false]);
}

/// Types that support a verdict but do not make a sentence dangerous by themselves.
const _supportingTypes = {'pressure', 'impersonation'};

final _sentenceEnd = RegExp(r'[.?!।॥\n]');

/// Pieces for the transcript view: every matched phrase (exact, fuzzy or intent match, found at its
/// position in the ORIGINAL transcript, case-insensitive) is a key piece, and the whole sentence
/// around each scam phrase (not mere pressure / pretext words) is marked as a dangerous sentence.
List<TextPiece> splitCallHighlights(String text, List<CallMatch> matches) {
  final lower = text.toLowerCase();
  if (lower.length != text.length) return [TextPiece(text, false)];
  final key = List<bool>.filled(text.length, false);
  final sent = List<bool>.filled(text.length, false);
  for (final m in matches) {
    final q = m.phrase.toLowerCase();
    if (q.isEmpty) continue;
    for (var i = lower.indexOf(q); i >= 0; i = lower.indexOf(q, i + q.length)) {
      for (var k = i; k < i + q.length; k++) {
        key[k] = true;
      }
      if (_supportingTypes.contains(m.scriptType)) continue;
      var s = i;
      while (s > 0 && !_sentenceEnd.hasMatch(text[s - 1])) {
        s--;
      }
      var e = i + q.length;
      while (e < text.length && !_sentenceEnd.hasMatch(text[e - 1])) {
        e++;
      }
      while (s < e && text[s] == ' ') {
        s++;
      }
      for (var k = s; k < e; k++) {
        sent[k] = true;
      }
    }
  }
  final out = <TextPiece>[];
  var start = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i == text.length || key[i] != key[start] || sent[i] != sent[start]) {
      if (i > start) out.add(TextPiece(text.substring(start, i), key[start], sent[start]));
      start = i;
    }
  }
  return out;
}

/// Splits [text] into pieces, marking every case-insensitive occurrence of a matched phrase.
/// Overlapping occurrences are merged.
List<TextPiece> splitHighlights(String text, Iterable<String> phrases) {
  final lower = text.toLowerCase();
  if (lower.length != text.length) return [TextPiece(text, false)];
  final mark = List<bool>.filled(text.length, false);
  for (final p in phrases) {
    final q = p.toLowerCase();
    if (q.isEmpty) continue;
    var i = lower.indexOf(q);
    while (i >= 0) {
      for (var k = i; k < i + q.length; k++) {
        mark[k] = true;
      }
      i = lower.indexOf(q, i + q.length);
    }
  }
  final out = <TextPiece>[];
  var start = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i == text.length || mark[i] != mark[start]) {
      if (i > start) out.add(TextPiece(text.substring(start, i), mark[start]));
      start = i;
    }
  }
  return out;
}

/// Most likely scam script: the scriptType with the most matches (first wins a tie), ignoring the
/// supporting signals 'pressure' and 'impersonation' unless nothing else matched.
String? mainScriptType(CallResult r) {
  const supporting = {'pressure', 'impersonation'};
  final counts = <String, int>{};
  for (final m in r.matches) {
    if (supporting.contains(m.scriptType)) continue;
    counts[m.scriptType] = (counts[m.scriptType] ?? 0) + 1;
  }
  if (counts.isEmpty) {
    if (r.matches.isEmpty) return null;
    return r.matches.any((m) => m.scriptType == 'impersonation') ? 'impersonation' : 'pressure';
  }
  String? best;
  var bestCount = 0;
  counts.forEach((type, c) {
    if (c > bestCount) {
      best = type;
      bestCount = c;
    }
  });
  return best;
}
