import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../lessons/lesson_detail_screen.dart';
import '../lessons/lesson_models.dart';
import 'literacy_score.dart';
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

  static const _green = DsColors.safe;
  static const _red = DsColors.alert;

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
    await LiteracyStore.recordQuiz(r); // feeds the overall literacy score on the home screen
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

  static const _pad = EdgeInsets.fromLTRB(DsSpace.xl, DsSpace.s, DsSpace.xl, DsSpace.section);

  Widget _body(S s) {
    if (_loadFailed) {
      return Center(
        child: EmptyState(
          icon: Icons.error_outline_rounded,
          color: DsColors.alertSoft,
          title: s.t('quiz_load_error'),
          action: PrimaryButton(label: s.t('quiz_retry'), onPressed: _load),
        ),
      );
    }
    final all = _all;
    if (all == null) return const LoadingState();
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
      padding: _pad,
      children: [
        PastelCard(
          color: DsColors.lavender,
          child: Column(children: [
            const IconBadge(Icons.quiz_outlined, size: 72),
            const SizedBox(height: DsSpace.l),
            Text(s.t('quiz_intro'), textAlign: TextAlign.center, style: DsType.bodyLarge),
            if (_latest != null) ...[
              const SizedBox(height: DsSpace.m),
              Text(
                '${s.t('quiz_latest')}: $_latest / 100  (${s.t(QuizScore.levelKeyFor(_latest!))})',
                key: const Key('quiz_latest'),
                textAlign: TextAlign.center,
                style: DsType.title,
              ),
            ],
          ]),
        ),
        const SizedBox(height: DsSpace.xl),
        Text(s.t('quiz_choose'), style: DsType.section),
        const SizedBox(height: DsSpace.m),
        _modeCard(
          key: const Key('quiz_mode_quick'),
          icon: Icons.bolt_rounded,
          color: DsColors.mint,
          title: s.t('quiz_mode_quick'),
          subtitle: s.t('quiz_mode_quick_sub'),
          onTap: () => _start(QuizMode.quick),
        ),
        _modeCard(
          key: const Key('quiz_mode_full'),
          icon: Icons.emoji_events_outlined,
          color: DsColors.peach,
          title: s.t('quiz_mode_full'),
          subtitle: '${s.t('quiz_mode_full_sub')} (${all.length} ${s.t('quiz_questions')})',
          onTap: () => _start(QuizMode.full),
        ),
        const SizedBox(height: DsSpace.m),
        Text(s.t('quiz_mode_topic'), style: DsType.section),
        const SizedBox(height: DsSpace.m),
        Wrap(
          spacing: DsSpace.s,
          runSpacing: DsSpace.s,
          children: [
            for (final id in kLessonIds)
              if ((counts[id] ?? 0) > 0)
                PillChip(
                  key: Key('quiz_topic_$id'),
                  icon: lessonTopicIcon(id),
                  label: '${s.t('quiz_topic_$id')} (${counts[id]})',
                  background: lessonTopicColor(id),
                  onTap: () => _start(QuizMode.topic, id),
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
  }) => Padding(
    padding: const EdgeInsets.only(bottom: DsSpace.m),
    child: PastelCard(
      key: key,
      color: color,
      onTap: onTap,
      semanticLabel: '$title. $subtitle',
      padding: const EdgeInsets.all(DsSpace.l),
      child: ExcludeSemantics(
        child: Row(
          children: [
            IconBadge(icon),
            const SizedBox(width: DsSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: DsType.titleLarge),
                  const SizedBox(height: DsSpace.xxs),
                  Text(subtitle, style: DsType.small),
                ],
              ),
            ),
            const SizedBox(width: DsSpace.s),
            const ArrowButton(),
          ],
        ),
      ),
    ),
  );

  Widget _emptyTopic(S s) => Center(
    child: EmptyState(
      icon: Icons.quiz_outlined,
      title: s.t('quiz_empty'),
      action: PillChip(label: s.t('quiz_change'), onTap: _toIntro),
    ),
  );

  // ------------------------------------------------------------- question

  Widget _question(S s, QuizSession session) {
    final lang = s.locale;
    final q = session.current;
    final opts = q.optionsFor(lang);
    final answered = session.answered;
    final right = session.lastAnswerCorrect;
    final c = right ? _green : _red;
    return ListView(
      // Unique storage key per question so each one opens scrolled to the top
      // (a plain key would still restore the previous offset from PageStorage).
      key: PageStorageKey<String>('quiz_q_${identityHashCode(session)}_${session.index}'),
      padding: _pad,
      children: [
        Row(
          children: [
            IconBadge(lessonTopicIcon(q.topic), size: kDsTouch, background: lessonTopicColor(q.topic), foreground: DsColors.ink),
            const SizedBox(width: DsSpace.s),
            Expanded(child: Text(s.t('quiz_topic_${q.topic}'), style: DsType.title)),
            const SizedBox(width: DsSpace.s),
            Flexible(
              child: Text(
                '${s.t('quiz_question')} ${session.index + 1} / ${session.length}',
                key: const Key('quiz_counter'),
                textAlign: TextAlign.end,
                style: DsType.small,
              ),
            ),
          ],
        ),
        const SizedBox(height: DsSpace.m),
        ProgressBar(value: (session.index + (answered ? 1 : 0)) / session.length, color: DsColors.brand),
        const SizedBox(height: DsSpace.s),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${s.t('quiz_score_now')}: ${session.correct}',
            key: const Key('quiz_score_live'),
            style: DsType.label.copyWith(color: DsColors.brand),
          ),
        ),
        const SizedBox(height: DsSpace.m),
        Text(pickLang(q.q, lang), style: DsType.cardTitle.copyWith(height: 1.3)),
        const SizedBox(height: DsSpace.xl),
        for (var i = 0; i < opts.length; i++) _option(opts[i], i, session),
        if (answered) ...[
          const SizedBox(height: DsSpace.xs),
          Container(
            key: const Key('quiz_feedback'),
            padding: const EdgeInsets.all(DsSpace.l),
            decoration: BoxDecoration(
              color: right ? DsColors.safeSoft : DsColors.alertSoft,
              border: Border.all(color: c, width: 2),
              borderRadius: BorderRadius.circular(DsRadius.tile),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(right ? Icons.check_circle_rounded : Icons.cancel_rounded, color: c, size: 32),
                const SizedBox(width: DsSpace.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(right ? s.t('quiz_correct') : s.t('quiz_wrong'), style: DsType.section),
                      if (!right && q.answer < opts.length)
                        Padding(
                          padding: const EdgeInsets.only(top: DsSpace.xs),
                          child: Text('${s.t('quiz_correct_answer')}: ${opts[q.answer]}', style: DsType.title),
                        ),
                      if (q.explain.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: DsSpace.xs),
                          child: Text(pickLang(q.explain, lang), style: DsType.bodyLarge),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DsSpace.l),
          PrimaryButton(
            key: const Key('quiz_next'),
            label: session.isLast ? s.t('quiz_see_result') : s.t('quiz_next'),
            icon: session.isLast ? Icons.flag_outlined : Icons.arrow_forward_rounded,
            onPressed: _next,
          ),
        ],
      ],
    );
  }

  Widget _option(String text, int i, QuizSession session) {
    final q = session.current;
    final answered = session.answered;
    var bg = DsColors.surface;
    var border = DsColors.line;
    IconData? icon;
    if (answered && i == q.answer) {
      bg = DsColors.safeSoft;
      border = _green;
      icon = Icons.check_rounded;
    } else if (answered && i == session.picked) {
      bg = DsColors.alertSoft;
      border = _red;
      icon = Icons.close_rounded;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.m),
      child: Pressable(
        key: Key('quiz_option_$i'),
        onTap: answered ? null : () => _answer(i),
        semanticLabel: text,
        borderRadius: BorderRadius.circular(DsRadius.tile),
        child: AnimatedContainer(
          duration: DsMotion.normal,
          curve: DsMotion.curve,
          constraints: const BoxConstraints(minHeight: kDsTouch + DsSpace.l),
          padding: const EdgeInsets.all(DsSpace.l),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(DsRadius.tile),
            border: Border.all(color: border, width: 2),
          ),
          child: ExcludeSemantics(
            child: Row(
              children: [
                Expanded(child: Text(text, style: DsType.bodyLarge)),
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
    'level_safe' => DsColors.brand,
    'level_aware' => DsColors.caution,
    _ => _red,
  };

  Widget _resultView(S s, QuizScore r) {
    final weak = r.weakestTopic;
    final c = _levelColor(r.levelKey);
    return ListView(
      key: const Key('quiz_result'),
      padding: _pad,
      children: [
        Text(s.t('quiz_score_title'), textAlign: TextAlign.center, style: DsType.cardTitle),
        const SizedBox(height: DsSpace.l),
        Center(
          child: Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(DsSpace.xl),
            // The Devanagari font has tall line height; scale down instead of overflowing.
            child: FittedBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${r.score}%', key: const Key('quiz_percent'), style: DsType.number.copyWith(color: DsColors.onDark, height: 1.1)),
                  Text(
                    '${r.correct} / ${r.total} ${s.t('quiz_correct_of')}',
                    key: const Key('quiz_correct_count'),
                    style: DsType.body.copyWith(color: DsColors.onDark),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: DsSpace.m),
        Text(
          '${s.t('quiz_level')}: ${s.t(r.levelKey)}',
          textAlign: TextAlign.center,
          style: DsType.cardTitle.copyWith(color: c),
        ),
        const SizedBox(height: DsSpace.s),
        Text(
          s.t('quiz_feedback_${r.levelKey}'),
          key: const Key('quiz_level_feedback'),
          textAlign: TextAlign.center,
          style: DsType.bodyLarge,
        ),
        const SizedBox(height: DsSpace.xl),
        Text(s.t('quiz_breakdown'), style: DsType.section),
        const SizedBox(height: DsSpace.s),
        for (final id in kLessonIds)
          if (r.perTopic[id] != null) _topicRow(s, id, r.perTopic[id]!, id == weak),
        const SizedBox(height: DsSpace.l),
        if (weak != null)
          PrimaryButton(
            key: const Key('quiz_revise'),
            label: '${s.t('quiz_revise')}: ${s.t('quiz_topic_$weak')}',
            icon: Icons.menu_book_outlined,
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LessonDetailScreen(lessonId: weak))),
          )
        else
          Text(s.t('quiz_all_correct'), textAlign: TextAlign.center, style: DsType.title.copyWith(color: _green)),
        const SizedBox(height: DsSpace.m),
        PrimaryButton(
          key: const Key('quiz_retry'),
          label: s.t('quiz_retry'),
          icon: Icons.replay_rounded,
          filled: false,
          onPressed: _retry,
        ),
        const SizedBox(height: DsSpace.s),
        Align(
          alignment: Alignment.center,
          child: PillChip(key: const Key('quiz_change'), label: s.t('quiz_change'), onTap: _toIntro),
        ),
      ],
    );
  }

  Widget _topicRow(S s, String id, List<int> v, bool weak) {
    final ratio = v[1] == 0 ? 0.0 : v[0] / v[1];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DsSpace.s),
      child: Row(
        children: [
          Icon(lessonTopicIcon(id), color: DsColors.ink),
          const SizedBox(width: DsSpace.s),
          SizedBox(
            width: 120,
            child: Text(
              s.t('quiz_topic_$id'),
              style: DsType.body.copyWith(fontWeight: weak ? DsWeight.semibold : DsWeight.medium),
            ),
          ),
          Expanded(
            child: ProgressBar(
              value: ratio,
              color: ratio >= 0.8 ? _green : (ratio >= 0.6 ? DsColors.caution : _red),
            ),
          ),
          const SizedBox(width: DsSpace.s),
          Text('${v[0]}/${v[1]}', style: DsType.label),
        ],
      ),
    );
  }
}
