import '../../engine/live_call_analyzer.dart';

/// Text-model score at which an already suspicious call (medium by the phrase rules) becomes high.
const double kLiveMlEscalate = 0.8;

/// Final risk shown to the user: the call-phrase rules decide, and the offline scam text
/// classifier (assets/models/scam_model.json) can only raise a "medium" call to "high".
/// It never raises a call with no scam phrases, so genuine calls cannot be flagged by it alone.
String combinedRisk(LiveCallState s, double? mlScore) {
  if (s.risk == 'medium' && mlScore != null && mlScore >= kLiveMlEscalate) return 'high';
  return s.risk;
}
