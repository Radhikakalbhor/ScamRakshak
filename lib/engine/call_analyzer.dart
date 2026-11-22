import 'models.dart';

/// Stub implementation of the Call Analyzer for ScamRakshak.
///
/// Signature and contract locked in AGENTS.md.
class CallAnalyzer {
  const CallAnalyzer();

  /// Loads the call analyzer.
  ///
  /// Stub implementation that returns an initialized instance.
  static Future<CallAnalyzer> load() async {
    return const CallAnalyzer();
  }

  /// Analyzes a call [transcript] synchronously.
  ///
  /// Returns a [CallResult] with risk 'high' if [transcript] contains
  /// 'arrest' or 'kyc' (case-insensitive). Otherwise returns risk 'low'.
  CallResult analyze(String transcript) {
    final lower = transcript.toLowerCase();
    final List<CallMatch> matches = [];

    if (lower.contains('arrest')) {
      matches.add(
        const CallMatch(
          phrase: 'arrest',
          scriptType: 'digital_arrest',
        ),
      );
    }

    if (lower.contains('kyc')) {
      matches.add(
        const CallMatch(
          phrase: 'kyc',
          scriptType: 'fake_kyc',
        ),
      );
    }

    if (matches.isNotEmpty) {
      return CallResult(
        risk: 'high',
        matches: matches,
      );
    } else {
      return const CallResult(
        risk: 'low',
        matches: [],
      );
    }
  }
}
