import 'models.dart';

/// Stub implementation of the Scam Classifier for ScamRakshak.
///
/// Signature and contract locked in AGENTS.md.
class ScamClassifier {
  const ScamClassifier();

  static const List<String> _scamKeywords = [
    'otp',
    'kyc',
    'urgent',
    'blocked',
  ];

  static const Map<String, double> _keywordWeights = {
    'otp': 0.95,
    'kyc': 0.90,
    'urgent': 0.75,
    'blocked': 0.80,
  };

  /// Loads the scam classifier.
  ///
  /// Stub implementation that returns an initialized instance without
  /// failing when the underlying ML model is not yet present.
  static Future<ScamClassifier> load() async {
    return const ScamClassifier();
  }

  /// Classifies [text] synchronously.
  ///
  /// Returns a [ScamResult] with label 'scam' if [text] contains any of:
  /// 'otp', 'kyc', 'urgent', 'blocked' (case-insensitive).
  /// Otherwise returns label 'genuine'.
  ScamResult classify(String text) {
    final lowerText = text.toLowerCase();
    final List<Reason> reasons = [];

    for (final keyword in _scamKeywords) {
      if (lowerText.contains(keyword)) {
        reasons.add(
          Reason(
            phrase: keyword,
            weight: _keywordWeights[keyword] ?? 0.80,
          ),
        );
      }
    }

    if (reasons.isNotEmpty) {
      final double score = (0.75 + (0.05 * reasons.length)).clamp(0.0, 0.99);
      return ScamResult(
        label: 'scam',
        score: score,
        reasons: reasons,
      );
    } else {
      return const ScamResult(
        label: 'genuine',
        score: 0.05,
        reasons: [],
      );
    }
  }
}


