import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../lessons/lesson_detail_screen.dart';
import '../lessons/lesson_models.dart';
import 'quiz_models.dart';
import 'quiz_strings.dart';

enum _Phase { intro, question, result }

/// Scam-awareness quiz: choose a mode, answer one question at a time with instant feedback,
/// then see the score, level and topic breakdown.
class QuizScreen extends StatefulWidget {
  /// If set, starts a [QuizMode.topic] quiz for this lesson id right away.
  final String? topic;

  /// Source of randomness for question order (inject a seeded one in tests).
  final Random? random;

  const QuizScreen({super.key, this.topic, this.random});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<QuizQuestion>? _all;
  bool _loadFailed = false;
  _Phase _phase = _Phase.intro;
  QuizSession? _session;
  QuizScore? _result;
  int? _latest;

  static const _green = AppTheme.successGreen;
  static const _red = Color(0xFFC62828);

  @override
  void initState() {
    super.initState();
    QuizStrings.ensure();
    _load();
    QuizStore.latestScore().then((v) {
      if (mounted) setState(() => _latest = v);
    });
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final qs = await QuizRepository.loadAll();
      if (!mounted) return;
      setState(() => _all = qs);
      if (widget.topic != null) _start(QuizMode.topic, widget.topic);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  void _start(QuizMode mode, [String? topic]) {
    final all = _all;
    if (all == null) return;
    setState(() {
      _session = QuizSession.start(all, mode: mode, topic: topic, random: widget.random);
      _result = null;
      _phase = _Phase.question;
    });
  }

  void _retry() {
    final s = _session;
    if (s != null) _start(s.mode, s.topic);
  }

  void _toIntro() => setState(() {
    _phase = _Phase.intro;
    _session = null;
  });

  void _answer(int i) => setState(() => _session!.answer(i));

  Future<void> _next() async {
    final session = _session!;
    if (session.next()) {
      setState(() {});
      return;
    }
    final r = session.score;
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
      body: SafeArea(child: _body(s)),
    );
  }

  Widget _body(S s) {
    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 56, color: AppTheme.errorRed),
            const SizedBox(height: 12),
            Text(s.t('quiz_load_error'), style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text(s.t('quiz_retry'))),
          ],
        ),
      );
    }
    final all = _all;
    if (all == null) return const Center(child: CircularProgressIndicator());
    switch (_phase) {
      case _Phase.intro:
        return _intro(s, all);
      case _Phase.question:
        final session = _session!;
        if (session.isEmpty) return _emptyTopic(s);
        return _question(s, session);
      case _Phase.result:
        return _resultView(s, _result!);
    }
  }

  // ---------------------------------------------------------------- intro

  Widget _intro(S s, List<QuizQuestion> all) {
    final counts = <String, int>{};
    for (final q in all) {
      counts[q.topic] = (counts[q.topic] ?? 0) + 1;
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.psychology_rounded, size: 96, color: AppTheme.primaryTeal),
        const SizedBox(height: 12),
        Text(s.t('quiz_intro'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
        if (_latest != null) ...[
          const SizedBox(height: 14),
          Text(
            '${s.t('quiz_latest')}: $_latest / 100  (${s.t(QuizScore.levelKeyFor(_latest!))})',
            key: const Key('quiz_latest'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ],
        const SizedBox(height: 20),
        Text(s.t('quiz_choose'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _modeCard(
          key: const Key('quiz_mode_quick'),
          icon: Icons.bolt_rounded,
          color: AppTheme.primaryTeal,
          title: s.t('quiz_mode_quick'),
          subtitle: s.t('quiz_mode_quick_sub'),
          onTap: () => _start(QuizMode.quick),
        ),
        _modeCard(
          key: const Key('quiz_mode_full'),
          icon: Icons.emoji_events_rounded,
          color: const Color(0xFF6A1B9A),
          title: s.t('quiz_mode_full'),
          subtitle: '${s.t('quiz_mode_full_sub')} (${all.length} ${s.t('quiz_questions')})',
          onTap: () => _start(QuizMode.full),
        ),
        const SizedBox(height: 12),
        Text(s.t('quiz_mode_topic'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in kLessonIds)
              if ((counts[id] ?? 0) > 0)
                ActionChip(
                  key: Key('quiz_topic_$id'),
                  avatar: Icon(lessonTopicIcon(id), size: 18, color: lessonTopicColor(id)),
                  label: Text('${s.t('quiz_topic_$id')} (${counts[id]})'),
                  onPressed: () => _start(QuizMode.topic, id),
                ),
          ],
        ),
      ],
    );
  }

  Widget _modeCard({
    required Key key,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => Card(
    key: key,
    margin: const EdgeInsets.only(bottom: 10),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.play_circle_fill_rounded, color: AppTheme.primaryTeal, size: 34),
          ],
        ),
      ),
    ),
  );

  Widget _emptyTopic(S s) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(s.t('quiz_empty'), style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _toIntro, child: Text(s.t('quiz_change'))),
      ],
    ),
  );

  // ------------------------------------------------------------- question

  Widget _question(S s, QuizSession session) {
    final lang = s.locale;
    final q = session.current;
    final opts = q.optionsFor(lang);
    final answered = session.answered;
    final right = session.lastAnswerCorrect;
    return ListView(
      // Unique storage key per question so each one opens scrolled to the top
      // (a plain key would still restore the previous offset from PageStorage).
      key: PageStorageKey<String>('quiz_q_${identityHashCode(session)}_${session.index}'),
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Icon(lessonTopicIcon(q.topic), color: lessonTopicColor(q.topic)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.t('quiz_topic_${q.topic}'),
                style: TextStyle(fontWeight: FontWeight.bold, color: lessonTopicColor(q.topic)),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${s.t('quiz_question')} ${session.index + 1} / ${session.length}',
                key: const Key('quiz_counter'),
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (session.index + (answered ? 1 : 0)) / session.length,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${s.t('quiz_score_now')}: ${session.correct}',
            key: const Key('quiz_score_live'),
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryDarkTeal),
          ),
        ),
        const SizedBox(height: 12),
        Text(pickLang(q.q, lang), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600, height: 1.35)),
        const SizedBox(height: 18),
        for (var i = 0; i < opts.length; i++) _option(opts[i], i, session),
        if (answered) ...[
          const SizedBox(height: 4),
          Container(
            key: const Key('quiz_feedback'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (right ? _green : _red).withValues(alpha: 0.1),
              border: Border.all(color: right ? _green : _red, width: 2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(right ? Icons.check_circle_rounded : Icons.cancel_rounded, color: right ? _green : _red, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        right ? s.t('quiz_correct') : s.t('quiz_wrong'),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: right ? _green : _red),
                      ),
                      if (!right && q.answer < opts.length)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${s.t('quiz_correct_answer')}: ${opts[q.answer]}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                      if (q.explain.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(pickLang(q.explain, lang), style: const TextStyle(fontSize: 16, height: 1.4)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('quiz_next'),
            onPressed: _next,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                session.isLast ? s.t('quiz_see_result') : s.t('quiz_next'),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _option(String text, int i, QuizSession session) {
    final q = session.current;
    final answered = session.answered;
    Color? bg;
    Color border = Colors.grey.shade400;
    IconData? icon;
    if (answered && i == q.answer) {
      bg = _green.withValues(alpha: 0.15);
      border = _green;
      icon = Icons.check_rounded;
    } else if (answered && i == session.picked) {
      bg = _red.withValues(alpha: 0.15);
      border = _red;
      icon = Icons.close_rounded;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: Key('quiz_option_$i'),
        color: bg ?? Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border, width: 2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: answered ? null : () => _answer(i),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(child: Text(text, style: const TextStyle(fontSize: 18))),
                if (icon != null) Icon(icon, color: border, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- result

  Color _levelColor(String key) => switch (key) {
    'level_champion' => _green,
    'level_safe' => AppTheme.primaryTeal,
    'level_aware' => AppTheme.warningOrange,
    _ => _red,
  };

  Widget _resultView(S s, QuizScore r) {
    final weak = r.weakestTopic;
    final c = _levelColor(r.levelKey);
    return ListView(
      key: const Key('quiz_result'),
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          s.t('quiz_score_title'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(22),
            // The Devanagari font has tall line height; scale down instead of overflowing.
            child: FittedBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${r.score}%',
                    key: const Key('quiz_percent'),
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white, height: 1.1),
                  ),
                  Text(
                    '${r.correct} / ${r.total} ${s.t('quiz_correct_of')}',
                    key: const Key('quiz_correct_count'),
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${s.t('quiz_level')}: ${s.t(r.levelKey)}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c),
        ),
        const SizedBox(height: 6),
        Text(
          s.t('quiz_feedback_${r.levelKey}'),
          key: const Key('quiz_level_feedback'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17),
        ),
        const SizedBox(height: 22),
        Text(s.t('quiz_breakdown'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (final id in kLessonIds)
          if (r.perTopic[id] != null) _topicRow(s, id, r.perTopic[id]!, id == weak),
        const SizedBox(height: 16),
        if (weak != null)
          FilledButton.icon(
            key: const Key('quiz_revise'),
            style: FilledButton.styleFrom(backgroundColor: lessonTopicColor(weak)),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LessonDetailScreen(lessonId: weak))),
            icon: const Icon(Icons.menu_book_rounded),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('${s.t('quiz_revise')}: ${s.t('quiz_topic_$weak')}', style: const TextStyle(fontSize: 17)),
            ),
          )
        else
          Text(
            s.t('quiz_all_correct'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _green),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('quiz_retry'),
          onPressed: _retry,
          icon: const Icon(Icons.replay_rounded),
          label: Text(s.t('quiz_retry'), style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('quiz_change'),
          onPressed: _toIntro,
          child: Text(s.t('quiz_change'), style: const TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  Widget _topicRow(S s, String id, List<int> v, bool weak) {
    final ratio = v[1] == 0 ? 0.0 : v[0] / v[1];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(lessonTopicIcon(id), color: lessonTopicColor(id)),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: Text(
              s.t('quiz_topic_$id'),
              style: TextStyle(fontSize: 15, fontWeight: weak ? FontWeight.bold : FontWeight.normal),
            ),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 12,
              borderRadius: BorderRadius.circular(6),
              color: ratio >= 0.8 ? _green : (ratio >= 0.6 ? AppTheme.warningOrange : _red),
            ),
          ),
          const SizedBox(width: 8),
          Text('${v[0]}/${v[1]}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
