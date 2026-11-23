import 'dart:convert';

import '../../engine/call_analyzer.dart';
import '../../engine/live_call_analyzer.dart';
import '../../engine/models.dart';
import 'call_highlight.dart';

/// Risk after one sentence of the call (in the order it was spoken).
class TimelinePoint {
  final String text;
  final String risk;
  final double score;
  final List<CallMatch> newMatches;

  const TimelinePoint(this.text, this.risk, this.score, this.newMatches);

  Map<String, Object?> toJson() => {
        'text': text,
        'risk': risk,
        'score': score,
        'new': [for (final m in newMatches) _matchJson(m)],
      };

  factory TimelinePoint.fromJson(Map<String, dynamic> j) => TimelinePoint(
        j['text'] as String? ?? '',
        j['risk'] as String? ?? 'low',
        (j['score'] as num?)?.toDouble() ?? 0,
        [for (final m in (j['new'] as List? ?? const [])) _matchFrom(m as Map)],
      );
}

/// Full analysis of one call transcript: overall verdict, 0..1 score, matches and timeline.
class CallTimelineResult {
  /// 'high' | 'medium' | 'low'.
  final String risk;

  /// 0..1 scam score, consistent with [risk] (high >= 0.8, medium 0.5-0.79, low < 0.5).
  final double score;
  final CallResult result;
  final List<TimelinePoint> points;
  final String transcript;

  const CallTimelineResult(this.risk, this.score, this.result, this.points, this.transcript);

  /// Index of the sentence where the call first reached [risk] (null when low).
  int? get firstAlertAt {
    if (risk == 'low') return null;
    final i = points.indexWhere((p) => p.risk == risk);
    return i < 0 ? null : i;
  }

  String? get scriptType => risk == 'low' ? null : mainScriptType(result);

  Map<String, Object?> toJson() => {
        'risk': risk,
        'score': score,
        'matches': [for (final m in result.matches) _matchJson(m)],
        'points': [for (final p in points) p.toJson()],
        'transcript': transcript,
      };

  factory CallTimelineResult.fromJson(Map<String, dynamic> j) {
    final risk = j['risk'] as String? ?? 'low';
    return CallTimelineResult(
      risk,
      (j['score'] as num?)?.toDouble() ?? 0,
      CallResult(risk, [for (final m in (j['matches'] as List? ?? const [])) _matchFrom(m as Map)]),
      [for (final p in (j['points'] as List? ?? const [])) TimelinePoint.fromJson((p as Map).cast<String, dynamic>())],
      j['transcript'] as String? ?? '',
    );
  }

  String encode() => jsonEncode(toJson());
  static CallTimelineResult decode(String s) => CallTimelineResult.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

Map<String, String> _matchJson(CallMatch m) => {'phrase': m.phrase, 'type': m.scriptType};
CallMatch _matchFrom(Map m) => CallMatch(m['phrase'].toString(), m['type'].toString());

/// Analyses a whole call recording transcript sentence by sentence.
///
/// The verdict is the more severe of [CallAnalyzer] (whole text) and [LiveCallAnalyzer]
/// (fed one sentence at a time, which also yields the timeline).
class CallTimeline {
  final CallAnalyzer rules;
  final LiveCallAnalyzer live;

  CallTimeline(this.rules, this.live);

  static Future<CallTimeline> load() async => CallTimeline(await CallAnalyzer.load(), await LiveCallAnalyzer.load());

  static final _sentenceEnd = RegExp(r'(?<=[.?!।॥])\s+|\n+');

  static List<String> sentences(String transcript) =>
      transcript.split(_sentenceEnd).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  static const _rank = {'low': 0, 'medium': 1, 'high': 2};

  CallTimelineResult analyze(String transcript) {
    final text = transcript.trim();
    live.reset();
    final points = <TimelinePoint>[];
    var state = LiveCallState.empty;
    for (final s in sentences(text)) {
      state = live.add(s);
      points.add(TimelinePoint(s, state.risk, state.score, state.newMatches));
    }
    live.reset();

    final whole = rules.analyze(text);
    final risk = _rank[whole.risk]! >= _rank[state.risk]! ? whole.risk : state.risk;
    final score = switch (risk) {
      'high' => state.score.clamp(0.8, 1.0),
      'medium' => state.score.clamp(0.5, 0.79),
      _ => state.score.clamp(0.0, 0.49),
    }.toDouble();
    // Keep every phrase either analyzer found (rules first, in transcript order).
    final matches = [...whole.matches];
    for (final m in state.matches) {
      if (!matches.any((x) => x.phrase == m.phrase)) matches.add(m);
    }
    return CallTimelineResult(risk, score, CallResult(risk, matches), points, text);
  }
}
