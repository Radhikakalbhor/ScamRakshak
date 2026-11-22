/// Data models for ScamRakshak detection and analysis engine.
///
/// Contracts locked in AGENTS.md.
library;

/// Represents a specific reason or indicator contributing to a scam determination.
class Reason {
  final String phrase;
  final double weight;

  const Reason({
    required this.phrase,
    required this.weight,
  });

  @override
  String toString() => 'Reason(phrase: $phrase, weight: $weight)';
}

/// Represents the classification result for a scanned message.
class ScamResult {
  final String label; // 'scam' | 'genuine'
  final double score; // 0..1 scam prob
  final List<Reason> reasons;

  const ScamResult({
    required this.label,
    required this.score,
    required this.reasons,
  });

  @override
  String toString() =>
      'ScamResult(label: $label, score: $score, reasons: $reasons)';
}

/// Represents a matched pattern or phrase detected during call transcript analysis.
class CallMatch {
  final String phrase;
  final String scriptType;

  const CallMatch({
    required this.phrase,
    required this.scriptType,
  });

  @override
  String toString() => 'CallMatch(phrase: $phrase, scriptType: $scriptType)';
}

/// Represents the overall risk evaluation of a call transcript.
class CallResult {
  final String risk; // 'high' | 'medium' | 'low'
  final List<CallMatch> matches;

  const CallResult({
    required this.risk,
    required this.matches,
  });

  @override
  String toString() => 'CallResult(risk: $risk, matches: $matches)';
}
