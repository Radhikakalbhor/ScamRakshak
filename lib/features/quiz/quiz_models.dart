import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../lessons/lesson_models.dart' show kLessonIds;

Map<String, String> _locMap(dynamic m) => (m as Map).map((k, v) => MapEntry(k.toString(), v.toString()));

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
    options: (j['options'] as Map).map((k, v) => MapEntry(k.toString(), (v as List).map((e) => e.toString()).toList())),
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
    return (j['questions'] as List).map((e) => QuizQuestion.fromJson(t, Map<String, dynamic>.from(e as Map))).toList();
  }

  /// All topics in lesson order.
  static Future<List<QuizQuestion>> loadAll() async {
    final parts = await Future.wait(kLessonIds.map(loadTopic));
    return parts.expand((e) => e).toList();
  }
}

/// quick: [QuizSession.quickCount] random questions; full: every question shuffled;
/// topic: one topic's questions shuffled.
enum QuizMode { quick, full, topic }

/// State of one quiz run: question order, current answer and running score.
class QuizSession {
  static const int quickCount = 10;

  final QuizMode mode;
  final String? topic;
  final List<QuizQuestion> questions;

  int _index = 0;
  int? _picked;
  int _correct = 0;
  final Map<String, List<int>> _perTopic = {};

  QuizSession._(this.mode, this.topic, this.questions);

  /// Builds a session from all questions. [random] makes the order reproducible in tests.
  factory QuizSession.start(List<QuizQuestion> all, {QuizMode mode = QuizMode.quick, String? topic, Random? random}) {
    final pool = mode == QuizMode.topic ? all.where((q) => q.topic == topic).toList() : List.of(all);
    pool.shuffle(random ?? Random());
    final picked = mode == QuizMode.quick ? pool.take(quickCount).toList() : pool;
    return QuizSession._(mode, topic, List.unmodifiable(picked));
  }

  int get index => _index;
  int get length => questions.length;
  bool get isEmpty => questions.isEmpty;
  QuizQuestion get current => questions[_index];
  int? get picked => _picked;
  bool get answered => _picked != null;
  bool get isLast => _index >= questions.length - 1;
  bool get lastAnswerCorrect => _picked != null && _picked == current.answer;

  /// Correct answers so far.
  int get correct => _correct;

  /// Records the answer for the current question. Returns whether it is correct.
  /// A second tap on the same question is ignored.
  bool answer(int option) {
    if (_picked != null) return lastAnswerCorrect;
    _picked = option;
    final ok = option == current.answer;
    final v = _perTopic.putIfAbsent(current.topic, () => [0, 0]);
    v[1]++;
    if (ok) {
      v[0]++;
      _correct++;
    }
    return ok;
  }

  /// Moves to the next question. Returns false when the quiz is over.
  bool next() {
    if (_picked == null) throw StateError('Answer the current question first');
    if (isLast) return false;
    _index++;
    _picked = null;
    return true;
  }

  QuizScore get score => QuizScore({for (final e in _perTopic.entries) e.key: List.of(e.value)});
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
