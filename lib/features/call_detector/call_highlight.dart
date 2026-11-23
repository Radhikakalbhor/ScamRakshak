import '../../engine/models.dart';

/// A piece of transcript text, [highlighted] when it is part of a matched phrase.
class TextPiece {
  final String text;
  final bool highlighted;
  const TextPiece(this.text, this.highlighted);
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

/// Most likely scam script: the scriptType with the most matches, ignoring generic 'pressure'.
String? mainScriptType(CallResult r) {
  final counts = <String, int>{};
  for (final m in r.matches) {
    if (m.scriptType == 'pressure') continue;
    counts[m.scriptType] = (counts[m.scriptType] ?? 0) + 1;
  }
  if (counts.isEmpty) return r.matches.isEmpty ? null : 'pressure';
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
