import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../lessons/lesson_models.dart';
import 'quiz_models.dart';
import 'quiz_strings.dart';

/// One overall Digital Financial Literacy Score (0-100) from quiz accuracy and lesson completion.
///
/// quiz part (max 60): latest accuracy per topic, averaged over ALL topics (an untried topic counts 0).
/// lesson part (max 40): share of lessons completed.
class LiteracyScore {
  static const quizWeight = 60;
  static const lessonWeight = 40;

  /// topic -> [correct, total] of the latest quiz answers for that topic.
  final Map<String, List<int>> quiz;
  final Set<String> lessonsDone;

  const LiteracyScore(this.quiz, this.lessonsDone);

  double topicAccuracy(String topic) {
    final v = quiz[topic];
    return v == null || v[1] == 0 ? 0 : v[0] / v[1];
  }

  int get topicsTried => kLessonIds.where((t) => (quiz[t]?[1] ?? 0) > 0).length;

  /// Average quiz accuracy over the topics actually tried (0..1), for display.
  double get quizAccuracy {
    var c = 0, n = 0;
    for (final t in kLessonIds) {
      final v = quiz[t];
      if (v == null) continue;
      c += v[0];
      n += v[1];
    }
    return n == 0 ? 0 : c / n;
  }

  int get lessonCount => kLessonIds.where(lessonsDone.contains).length;

  bool get hasData => topicsTried > 0 || lessonCount > 0;

  int get score {
    final q = kLessonIds.map(topicAccuracy).fold<double>(0, (a, b) => a + b) / kLessonIds.length;
    final l = lessonCount / kLessonIds.length;
    return (q * quizWeight + l * lessonWeight).round().clamp(0, 100);
  }

  String get levelKey => QuizScore.levelKeyFor(score);

  /// Topic to work on next: lowest mix of quiz accuracy and lesson completion (lesson order on ties).
  /// Null when every topic has a perfect quiz and a completed lesson.
  String? get weakestTopic {
    String? best;
    var bestValue = 2.0;
    for (final t in kLessonIds) {
      final v = 0.6 * topicAccuracy(t) + 0.4 * (lessonsDone.contains(t) ? 1 : 0);
      if (v < bestValue) {
        bestValue = v;
        best = t;
      }
    }
    return bestValue >= 1 ? null : best;
  }

  /// 'lesson' when the weakest topic's lesson is not done yet, otherwise 'quiz'.
  String? get recommendation {
    final t = weakestTopic;
    if (t == null) return null;
    return lessonsDone.contains(t) ? 'quiz' : 'lesson';
  }
}

/// Persists per-topic quiz results; lesson completion comes from [LessonProgress].
class LiteracyStore {
  static const key = 'dfl_topic_quiz_v1';

  static Map<String, List<int>> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final j = jsonDecode(raw);
      final m = j is Map && j['topics'] is Map ? j['topics'] as Map : j as Map;
      return {
        for (final e in m.entries)
          if (e.value is List && (e.value as List).length == 2)
            e.key.toString(): [((e.value as List)[0] as num).toInt(), ((e.value as List)[1] as num).toInt()],
      };
    } catch (_) {
      return {};
    }
  }

  static Future<Map<String, List<int>>> _quiz(SharedPreferences p) async {
    final own = p.getString(key);
    // First run after the update: start from the last quiz result saved before the score existed.
    return own != null ? _decode(own) : _decode(p.getString(QuizStore.keyDetail));
  }

  /// Latest answers per topic replace that topic's previous result.
  static Future<void> recordQuiz(QuizScore s) async {
    try {
      final p = await SharedPreferences.getInstance();
      final m = await _quiz(p);
      s.perTopic.forEach((t, v) {
        if (v[1] > 0) m[t] = [v[0], v[1]];
      });
      await p.setString(key, jsonEncode(m));
    } catch (_) {}
    learningProgressChanged.value++;
  }

  static Future<LiteracyScore> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return LiteracyScore(await _quiz(p), await LessonProgress.completed());
    } catch (_) {
      return const LiteracyScore({}, {});
    }
  }
}

class LiteracyStrings {
  static bool _done = false;
  static void ensure() {
    QuizStrings.ensure();
    if (_done) return;
    _done = true;
    S.register(const {
      'en': {
        'dfl_sub': 'From your quiz answers and the lessons you finished. Stays on this phone.',
        'dfl_empty': 'Read a lesson or take the quiz to get your score.',
        'dfl_parts': 'Quiz {q}% correct · {t}/{n} topics tried · {l}/{n} lessons done',
        'dfl_rec_lesson': 'Next: read the lesson "{topic}".',
        'dfl_rec_quiz': 'Next: take the "{topic}" quiz again.',
        'dfl_all_good': 'Excellent! Every topic is covered. Share what you know with your family.',
        'dfl_learn': 'Open lessons',
        'dfl_quiz': 'Take a quiz',
      },
      'hi': {
        'dfl_sub': 'आपके क्विज़ जवाबों और पूरे किए पाठों से। सिर्फ़ इसी फोन पर रहता है।',
        'dfl_empty': 'स्कोर पाने के लिए कोई पाठ पढ़ें या क्विज़ दें।',
        'dfl_parts': 'क्विज़ {q}% सही · {t}/{n} विषय आज़माए · {l}/{n} पाठ पूरे',
        'dfl_rec_lesson': 'आगे: "{topic}" पाठ पढ़ें।',
        'dfl_rec_quiz': 'आगे: "{topic}" क्विज़ फिर से दें।',
        'dfl_all_good': 'शाबाश! हर विषय पूरा है। अपने परिवार को भी बताएँ।',
        'dfl_learn': 'पाठ खोलें',
        'dfl_quiz': 'क्विज़ दें',
      },
      'chh': {
        'dfl_sub': 'तोर क्विज़ जवाब अउ पूरा करे पाठ ले। सिरिफ इही फोन म रहिथे।',
        'dfl_empty': 'स्कोर पाए बर कोनो पाठ पढ़ या क्विज़ दे।',
        'dfl_parts': 'क्विज़ {q}% सही · {t}/{n} बिसय देखे · {l}/{n} पाठ पूरा',
        'dfl_rec_lesson': 'आगू: "{topic}" पाठ पढ़।',
        'dfl_rec_quiz': 'आगू: "{topic}" क्विज़ फेर दे।',
        'dfl_all_good': 'बढ़िया! हर बिसय पूरा हे। अपन परिवार ल घलो बता।',
        'dfl_learn': 'पाठ खोल',
        'dfl_quiz': 'क्विज़ दे',
      },
    });
  }
}

/// Home-screen card with the overall score, level and the weakest-topic recommendation.
class LiteracyScoreCard extends StatefulWidget {
  const LiteracyScoreCard({super.key});

  @override
  State<LiteracyScoreCard> createState() => _LiteracyScoreCardState();
}

class _LiteracyScoreCardState extends State<LiteracyScoreCard> {
  LiteracyScore? _score;
  Map<String, Map<String, String>> _titles = {};

  @override
  void initState() {
    super.initState();
    learningProgressChanged.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    learningProgressChanged.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final s = await LiteracyStore.load();
    Map<String, Map<String, String>> titles = _titles;
    final t = s.weakestTopic;
    if (t != null && !titles.containsKey(t)) {
      try {
        titles = {...titles, t: (await LessonRepository.load(t)).title};
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _score = s;
        _titles = titles;
      });
    }
  }

  void _go(String route) {
    final r = GoRouter.maybeOf(context);
    if (r != null) r.push(route);
  }

  @override
  Widget build(BuildContext context) {
    LiteracyStrings.ensure();
    final s = S.of(context);
    final d = _score;
    if (d == null) return const SizedBox.shrink();
    final score = d.score;
    final color = switch (d.levelKey) {
      'level_champion' => AppTheme.successGreen,
      'level_safe' => AppTheme.primaryTeal,
      'level_aware' => AppTheme.warningOrange,
      _ => AppTheme.errorRed,
    };
    final topic = d.weakestTopic;
    final topicName = topic == null ? '' : pickLang(_titles[topic] ?? const {}, s.locale);
    final rec = switch (d.recommendation) {
      'lesson' => s.t('dfl_rec_lesson').replaceAll('{topic}', topicName.isEmpty ? topic! : topicName),
      'quiz' => s.t('dfl_rec_quiz').replaceAll('{topic}', topicName.isEmpty ? topic! : topicName),
      _ => s.t('dfl_all_good'),
    };
    final n = kLessonIds.length;
    return Card(
      key: const Key('dfl_card'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('quiz_score_title'), style: Theme.of(context).textTheme.titleLarge),
                Text(s.t('dfl_sub'), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(children: [
              Text('$score', key: const Key('dfl_score'),
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: color)),
              Text('/100', style: const TextStyle(color: AppTheme.textSecondary)),
            ]),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
                value: score / 100, minHeight: 10, color: color, backgroundColor: const Color(0xFFE0E0E0)),
          ),
          const SizedBox(height: 8),
          if (!d.hasData)
            Text(s.t('dfl_empty'), key: const Key('dfl_empty'))
          else ...[
            Row(children: [
              Container(
                key: const Key('dfl_level'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                child: Text(s.t(d.levelKey),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s
                      .t('dfl_parts')
                      .replaceAll('{q}', '${(d.quizAccuracy * 100).round()}')
                      .replaceAll('{t}', '${d.topicsTried}')
                      .replaceAll('{l}', '${d.lessonCount}')
                      .replaceAll('{n}', '$n'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 8),
          Text(rec, key: const Key('dfl_recommendation'), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              key: const Key('dfl_learn'),
              onPressed: () => _go('/lessons'),
              icon: const Icon(Icons.school_rounded),
              label: Text(s.t('dfl_learn')),
            ),
            OutlinedButton.icon(
              key: const Key('dfl_quiz'),
              onPressed: () => _go('/quiz'),
              icon: const Icon(Icons.psychology_rounded),
              label: Text(s.t('dfl_quiz')),
            ),
          ]),
        ]),
      ),
    );
  }
}
