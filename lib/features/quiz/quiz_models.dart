import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../lessons/lesson_models.dart' show kLessonIds;

Map<String, String> _locMap(dynamic m) =>
    (m as Map).map((k, v) => MapEntry(k.toString(), v.toString()));

class QuizQuestion {
  final String topic;
  final Map<String, String> q;
  final Map<String, List<String>> options;
  final int answer;
  final Map<String, String> explain;

  const QuizQuestion({
    required this.topic,
    required this.q,
    required this.options,
    required this.answer,
    required this.explain,
  });

  factory QuizQuestion.fromJson(String topic, Map<String, dynamic> j) => QuizQuestion(
        topic: topic,
        q: _locMap(j['q']),
        options: (j['options'] as Map).map(
            (k, v) => MapEntry(k.toString(), (v as List).map((e) => e.toString()).toList())),
        answer: (j['answer'] as num).toInt(),
        explain: j['explain'] == null ? const {} : _locMap(j['explain']),
      );

  List<String> optionsFor(String lang) => options[lang] ?? options['en'] ?? const [];
}

class QuizRepository {
  static Future<List<QuizQuestion>> loadTopic(String topic) async {
    final raw = await rootBundle.loadString('assets/quiz/$topic.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final t = j['topic'].toString();
    return (j['questions'] as List)
        .map((e) => QuizQuestion.fromJson(t, Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// All topics in lesson order (5 questions each, 20 total).
  static Future<List<QuizQuestion>> loadAll() async {
    final parts = await Future.wait(kLessonIds.map(loadTopic));
    return parts.expand((e) => e).toList();
  }
}

class QuizScore {
  /// topic -> [correct, total]
  final Map<String, List<int>> perTopic;
  const QuizScore(this.perTopic);

  int get correct => perTopic.values.fold(0, (a, v) => a + v[0]);
  int get total => perTopic.values.fold(0, (a, v) => a + v[1]);

  /// Digital Financial Literacy Score 0..100.
  int get score => total == 0 ? 0 : (correct * 100 / total).round();

  /// String key: level_beginner | level_aware | level_safe | level_champion.
  String get levelKey => levelKeyFor(score);

  static String levelKeyFor(int score) {
    if (score >= 90) return 'level_champion';
    if (score >= 70) return 'level_safe';
    if (score >= 40) return 'level_aware';
    return 'level_beginner';
  }

  /// Topic with the lowest ratio (first in lesson order on ties); null if everything is correct.
  String? get weakestTopic {
    String? best;
    double bestRatio = 2;
    for (final id in kLessonIds) {
      final v = perTopic[id];
      if (v == null || v[1] == 0) continue;
      final r = v[0] / v[1];
      if (r < bestRatio) {
        bestRatio = r;
        best = id;
      }
    }
    return bestRatio >= 1 ? null : best;
  }

  Map<String, dynamic> toJson() => {
        'score': score,
        'level': levelKey,
        'topics': perTopic,
        'ts': DateTime.now().toIso8601String(),
      };
}

/// Latest quiz result in shared_preferences.
class QuizStore {
  static const String keyScore = 'quiz_latest_score';
  static const String keyDetail = 'quiz_latest_detail';

  static Future<void> save(QuizScore s) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(keyScore, s.score);
      await p.setString(keyDetail, jsonEncode(s.toJson()));
    } catch (_) {}
  }

  static Future<int?> latestScore() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getInt(keyScore);
    } catch (_) {
      return null;
    }
  }
}
