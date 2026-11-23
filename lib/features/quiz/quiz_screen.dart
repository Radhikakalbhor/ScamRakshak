import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../lessons/lesson_models.dart';
import '../lessons/lesson_viewer_screen.dart';
import 'quiz_models.dart';
import 'quiz_strings.dart';

enum _Phase { intro, question, result }

/// One-question-at-a-time quiz with instant feedback and a final literacy score.
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late Future<List<QuizQuestion>> _questions;
  _Phase _phase = _Phase.intro;
  int _index = 0;
  int? _picked;
  int? _latest;
  final Map<String, List<int>> _perTopic = {};
  QuizScore? _result;

  static const _green = Color(0xFF2E7D32);
  static const _red = Color(0xFFC62828);

  @override
  void initState() {
    super.initState();
    QuizStrings.ensure();
    _questions = QuizRepository.loadAll();
    QuizStore.latestScore().then((v) {
      if (mounted) setState(() => _latest = v);
    });
  }

  void _start() => setState(() {
        _phase = _Phase.question;
        _index = 0;
        _picked = null;
        _perTopic.clear();
        _result = null;
      });

  void _answer(QuizQuestion q, int i) {
    if (_picked != null) return;
    final v = _perTopic.putIfAbsent(q.topic, () => [0, 0]);
    v[1]++;
    if (i == q.answer) v[0]++;
    setState(() => _picked = i);
  }

  Future<void> _next(int total) async {
    if (_index + 1 < total) {
      setState(() {
        _index++;
        _picked = null;
      });
      return;
    }
    final r = QuizScore(Map.of(_perTopic));
    await QuizStore.save(r);
    if (!mounted) return;
    setState(() {
      _result = r;
      _latest = r.score;
      _phase = _Phase.result;
    });
  }

  @override
  Widget build(BuildContext context) {
    QuizStrings.ensure();
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('quiz_title'))),
      body: FutureBuilder<List<QuizQuestion>>(
        future: _questions,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(s.t('quiz_load_error')));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final qs = snap.data!;
          switch (_phase) {
            case _Phase.intro:
              return _intro(s);
            case _Phase.question:
              return _question(s, qs);
            case _Phase.result:
              return _resultView(s);
          }
        },
      ),
    );
  }

  Widget _intro(S s) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.psychology_rounded, size: 120, color: Color(0xFF00796B)),
          const SizedBox(height: 16),
          Text(s.t('quiz_intro'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20)),
          if (_latest != null) ...[
            const SizedBox(height: 20),
            Text('${s.t('quiz_latest')}: $_latest / 100  (${s.t(QuizScore.levelKeyFor(_latest!))})',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(s.t('quiz_start'), style: const TextStyle(fontSize: 20)),
            ),
          ),
        ],
      );

  Widget _question(S s, List<QuizQuestion> qs) {
    final lang = s.locale;
    final q = qs[_index];
    final opts = q.optionsFor(lang);
    final answered = _picked != null;
    final right = _picked == q.answer;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Icon(lessonTopicIcon(q.topic), color: lessonTopicColor(q.topic)),
          const SizedBox(width: 8),
          Text(s.t('quiz_topic_${q.topic}'),
              style: TextStyle(fontWeight: FontWeight.bold, color: lessonTopicColor(q.topic))),
          const Spacer(),
          Text('${s.t('quiz_question')} ${_index + 1} / ${qs.length}',
              style: const TextStyle(fontSize: 16)),
        ]),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: (_index + 1) / qs.length, minHeight: 8),
        const SizedBox(height: 20),
        Text(pickLang(q.q, lang), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        for (var i = 0; i < opts.length; i++) _option(opts[i], i, q, answered),
        if (answered) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (right ? _green : _red).withValues(alpha: 0.1),
              border: Border.all(color: right ? _green : _red, width: 2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(right ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: right ? _green : _red, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '${right ? s.t('quiz_correct') : s.t('quiz_wrong')}  ',
                        style: TextStyle(fontWeight: FontWeight.bold, color: right ? _green : _red)),
                    TextSpan(text: pickLang(q.explain, lang)),
                  ]), style: const TextStyle(fontSize: 17)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => _next(qs.length),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_index + 1 < qs.length ? s.t('quiz_next') : s.t('quiz_see_result'),
                  style: const TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _option(String text, int i, QuizQuestion q, bool answered) {
    Color? bg;
    Color border = Colors.grey.shade400;
    IconData? icon;
    if (answered && i == q.answer) {
      bg = _green.withValues(alpha: 0.15);
      border = _green;
      icon = Icons.check_rounded;
    } else if (answered && i == _picked) {
      bg = _red.withValues(alpha: 0.15);
      border = _red;
      icon = Icons.close_rounded;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: bg ?? Colors.white,
        shape: RoundedRectangleBorder(
            side: BorderSide(color: border, width: 2), borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: answered ? null : () => _answer(q, i),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: Text(text, style: const TextStyle(fontSize: 19))),
              if (icon != null) Icon(icon, color: border, size: 28),
            ]),
          ),
        ),
      ),
    );
  }

  Color _levelColor(String key) => switch (key) {
        'level_champion' => _green,
        'level_safe' => const Color(0xFF00796B),
        'level_aware' => const Color(0xFFE65100),
        _ => _red,
      };

  Widget _resultView(S s) {
    final r = _result!;
    final weak = r.weakestTopic;
    final c = _levelColor(r.levelKey);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(s.t('quiz_score_title'),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c),
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${r.score}',
                  style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: Colors.white)),
              const Text('/ 100', style: TextStyle(fontSize: 18, color: Colors.white70)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text('${s.t('quiz_level')}: ${s.t(r.levelKey)}',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c)),
        const SizedBox(height: 24),
        Text(s.t('quiz_breakdown'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (final id in kLessonIds)
          if (r.perTopic[id] != null) _topicRow(s, id, r.perTopic[id]!, id == weak),
        const SizedBox(height: 16),
        if (weak != null)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: lessonTopicColor(weak)),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => LessonViewerScreen(lessonId: weak))),
            icon: const Icon(Icons.menu_book_rounded),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('${s.t('quiz_revise')}: ${s.t('quiz_topic_$weak')}',
                  style: const TextStyle(fontSize: 18)),
            ),
          )
        else
          Text(s.t('quiz_all_correct'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _green)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.replay_rounded),
          label: Text(s.t('quiz_retry'), style: const TextStyle(fontSize: 18)),
        ),
      ],
    );
  }

  Widget _topicRow(S s, String id, List<int> v, bool weak) {
    final ratio = v[1] == 0 ? 0.0 : v[0] / v[1];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(lessonTopicIcon(id), color: lessonTopicColor(id)),
        const SizedBox(width: 8),
        SizedBox(
          width: 90,
          child: Text(s.t('quiz_topic_$id'),
              style: TextStyle(fontSize: 16, fontWeight: weak ? FontWeight.bold : FontWeight.normal)),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 12,
            borderRadius: BorderRadius.circular(6),
            color: ratio >= 0.8 ? _green : (ratio >= 0.6 ? const Color(0xFFE65100) : _red),
          ),
        ),
        const SizedBox(width: 8),
        Text('${v[0]}/${v[1]}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
