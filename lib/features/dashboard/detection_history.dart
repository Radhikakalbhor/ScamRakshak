import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers.dart';
import '../../engine/call_analyzer.dart';
import '../../engine/models.dart';
import '../call_detector/call_highlight.dart' show mainScriptType;

/// One message or call check done on this phone. The checked text itself is never stored.
class DetectionRecord {
  /// 'message' | 'call'
  final String kind;

  /// 'scam' | 'suspicious' | 'safe'
  final String verdict;

  /// Scam type for scam/suspicious results (call_rules.json script types, 'phishing_link' or 'other'),
  /// empty for safe results.
  final String category;

  /// Scam probability for messages (0..1); null for calls.
  final double? score;

  /// True when the check used a built-in example message or sample call (practice, not real data).
  final bool sample;

  final DateTime time;

  const DetectionRecord({
    required this.kind,
    required this.verdict,
    required this.category,
    required this.time,
    this.score,
    this.sample = false,
  });

  bool get isRisky => verdict != 'safe';

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'verdict': verdict,
    'category': category,
    if (score != null) 'score': score,
    if (sample) 'sample': true,
    'ts': time.toIso8601String(),
  };

  static DetectionRecord? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final kind = j['kind'], verdict = j['verdict'], ts = DateTime.tryParse('${j['ts']}');
    if ((kind != 'message' && kind != 'call') ||
        !const {'scam', 'suspicious', 'safe'}.contains(verdict) ||
        ts == null) {
      return null;
    }
    return DetectionRecord(
      kind: kind as String,
      verdict: verdict as String,
      category: (j['category'] ?? '').toString(),
      score: (j['score'] as num?)?.toDouble(),
      sample: j['sample'] == true,
      time: ts,
    );
  }
}

/// Detection history persisted in shared_preferences (newest first, capped at [maxRecords]).
class DetectionHistory {
  static const String prefKey = 'detection_history_v1';
  static const int maxRecords = 500;

  Future<List<DetectionRecord>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(prefKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list.map(DetectionRecord.tryFromJson).whereType<DetectionRecord>().toList();
    } catch (_) {
      return []; // corrupt or unavailable storage: behave as empty history
    }
  }

  Future<void> add(DetectionRecord r) async {
    final all = [r, ...await load()];
    final kept = all.length > maxRecords ? all.sublist(0, maxRecords) : all;
    final p = await SharedPreferences.getInstance();
    await p.setString(prefKey, jsonEncode(kept.map((e) => e.toJson()).toList()));
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(prefKey);
  }
}

final detectionHistoryProvider = Provider<DetectionHistory>((ref) => DetectionHistory());

final _url = RegExp(
  r'(https?://|www\.)\S+|\b[a-z0-9-]+\.(com|in|ly|xyz|top|link|info|net|org|co|me|site|online|app|club|live|cc|io|gl)\b',
  caseSensitive: false,
);

/// Scam type of a message, using the same call-script rules as the call checker,
/// then 'phishing_link' for scam messages with a link, else 'other'.
String messageCategory(String text, ScamResult r, CallAnalyzer? analyzer) {
  if (analyzer != null) {
    final t = mainScriptType(analyzer.analyze(text));
    if (t != null && t != 'pressure') return t;
  }
  if (r.reasons.any((x) => x.phrase.contains('urltoken')) || _url.hasMatch(text)) return 'phishing_link';
  return 'other';
}

DetectionRecord messageRecord(String text, ScamResult r, {CallAnalyzer? analyzer, bool sample = false, DateTime? now}) {
  final scam = r.label == 'scam';
  return DetectionRecord(
    kind: 'message',
    verdict: scam ? 'scam' : 'safe',
    category: scam ? messageCategory(text, r, analyzer) : '',
    score: r.score,
    sample: sample,
    time: now ?? DateTime.now(),
  );
}

DetectionRecord callRecord(CallResult r, {bool sample = false, DateTime? now}) {
  final verdict = switch (r.risk) {
    'high' => 'scam',
    'medium' => 'suspicious',
    _ => 'safe',
  };
  return DetectionRecord(
    kind: 'call',
    verdict: verdict,
    category: verdict == 'safe' ? '' : (mainScriptType(r) ?? 'other'),
    sample: sample,
    time: now ?? DateTime.now(),
  );
}

/// Saves a message check in the background. Never throws; storage problems are ignored.
Future<void> recordMessageCheck(WidgetRef ref, String text, ScamResult r, {required bool sample}) {
  final history = ref.read(detectionHistoryProvider);
  final analyzer = ref.read(callAnalyzerProvider.future);
  return () async {
    CallAnalyzer? a;
    try {
      a = await analyzer;
    } catch (_) {}
    await history.add(messageRecord(text, r, analyzer: a, sample: sample));
  }().catchError((Object _) {});
}

/// Saves a call check in the background. Never throws.
Future<void> recordCallCheck(WidgetRef ref, CallResult r, {required bool sample}) =>
    ref.read(detectionHistoryProvider).add(callRecord(r, sample: sample)).catchError((Object _) {});
