/// Engine result types (LOCKED contract, see AGENTS.md).
library;

/// One n-gram that pushed the message towards "scam"; [weight] = its contribution to the logit.
class Reason {
  final String phrase;
  final double weight;
  const Reason(this.phrase, this.weight);

  @override
  String toString() => 'Reason($phrase, ${weight.toStringAsFixed(3)})';
}

class ScamResult {
  /// 'scam' | 'genuine'
  final String label;

  /// 0..1 scam probability.
  final double score;
  final List<Reason> reasons;
  const ScamResult(this.label, this.score, this.reasons);
}

class CallMatch {
  final String phrase;
  final String scriptType;
  const CallMatch(this.phrase, this.scriptType);
}

class CallResult {
  /// 'high' | 'medium' | 'low'
  final String risk;
  final List<CallMatch> matches;
  const CallResult(this.risk, this.matches);
}
