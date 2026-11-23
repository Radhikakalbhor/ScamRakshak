import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../quiz/quiz_screen.dart';
import 'lesson_models.dart';
import 'lesson_viewer_screen.dart';
import 'lessons_strings.dart';

/// One lesson: what the scam is, a real example, warning signs and safety steps,
/// with links to the picture cards and a topic quiz.
class LessonDetailScreen extends StatefulWidget {
  final String lessonId;
  const LessonDetailScreen({super.key, required this.lessonId});

  @override
  State<LessonDetailScreen> createState() => _LessonDetailScreenState();
}

class _LessonDetailScreenState extends State<LessonDetailScreen> {
  late Future<Lesson> _lesson;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    LessonsStrings.ensure();
    _lesson = LessonRepository.load(widget.lessonId);
    _refreshDone();
  }

  Future<void> _refreshDone() async {
    final d = await LessonProgress.completed();
    if (mounted) setState(() => _done = d.contains(widget.lessonId));
  }

  Future<void> _markDone() async {
    await LessonProgress.markDone(widget.lessonId);
    if (mounted) setState(() => _done = true);
  }

  Future<void> _openCards() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => LessonViewerScreen(lessonId: widget.lessonId)));
    await _refreshDone();
  }

  void _openQuiz() =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => QuizScreen(topic: widget.lessonId)));

  @override
  Widget build(BuildContext context) {
    LessonsStrings.ensure();
    final s = S.of(context);
    return FutureBuilder<Lesson>(
      future: _lesson,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(s.t('lessons_title'))),
            body: Center(
              child: EmptyState(
                icon: Icons.error_outline_rounded,
                color: DsColors.alertSoft,
                title: s.t('lessons_load_error'),
                action: PrimaryButton(
                  label: s.t('lessons_retry'),
                  onPressed: () {
                    final next = LessonRepository.load(widget.lessonId);
                    setState(() {
                      _lesson = next;
                    });
                  },
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) return const Scaffold(body: LoadingState());
        final l = snap.data!;
        final lang = s.locale;
        final color = lessonTopicColor(l.id);
        return Scaffold(
          appBar: AppBar(title: Text(pickLang(l.title, lang))),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(DsSpace.xl, DsSpace.s, DsSpace.xl, DsSpace.section),
              children: [
                _header(s, l, color),
                if (l.summary.isNotEmpty)
                  _section(
                    title: s.t('lesson_what'),
                    icon: Icons.info_outline_rounded,
                    child: Text(pickLang(l.summary, lang), style: DsType.reading),
                  ),
                if (l.example.isNotEmpty)
                  _section(
                    key: const Key('lesson_example'),
                    title: s.t('lesson_example'),
                    icon: Icons.format_quote_rounded,
                    background: DsColors.peach,
                    child: Text(pickLang(l.example, lang), style: DsType.reading.copyWith(fontStyle: FontStyle.italic)),
                  ),
                if (l.signs.isNotEmpty)
                  _section(
                    key: const Key('lesson_signs'),
                    title: s.t('lesson_signs'),
                    icon: Icons.warning_amber_rounded,
                    iconColor: DsColors.alert,
                    child: _bullets(l.signs, lang, Icons.error_outline_rounded, DsColors.alert),
                  ),
                if (l.steps.isNotEmpty)
                  _section(
                    key: const Key('lesson_steps'),
                    title: s.t('lesson_steps'),
                    icon: Icons.shield_outlined,
                    iconColor: DsColors.safe,
                    child: _bullets(l.steps, lang, Icons.check_circle_outline_rounded, DsColors.safe),
                  ),
                const SizedBox(height: DsSpace.s),
                PrimaryButton(
                  key: const Key('lesson_open_cards'),
                  label: '${s.t('lesson_open_cards')} (${l.cards.length})',
                  icon: Icons.style_outlined,
                  onPressed: _openCards,
                ),
                const SizedBox(height: DsSpace.s),
                if (_done)
                  PrimaryButton(
                    key: const Key('lesson_marked'),
                    label: s.t('lesson_marked'),
                    icon: Icons.check_circle_outline_rounded,
                    filled: false,
                    color: DsColors.safe,
                  )
                else
                  PrimaryButton(
                    key: const Key('lesson_mark_done'),
                    label: s.t('lesson_mark_done'),
                    icon: Icons.task_alt_rounded,
                    filled: false,
                    onPressed: _markDone,
                  ),
                const SizedBox(height: DsSpace.s),
                Align(
                  alignment: Alignment.center,
                  child: PillChip(
                    key: const Key('lesson_take_quiz'),
                    label: s.t('lesson_take_quiz'),
                    icon: Icons.quiz_outlined,
                    onTap: _openQuiz,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(S s, Lesson l, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: DsSpace.m),
    child: PastelCard(
      color: color,
      child: Row(
        children: [
          IconBadge(lessonTopicIcon(l.id), size: 64),
          const SizedBox(width: DsSpace.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pickLang(l.title, s.locale), style: DsType.cardTitle),
                const SizedBox(height: DsSpace.xs),
                Text(s.t('lessons_cat_${l.category}'), style: DsType.small),
                if (_done) ...[
                  const SizedBox(height: DsSpace.s),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: DsColors.safe, size: 18),
                      const SizedBox(width: DsSpace.xs),
                      Flexible(child: Text(s.t('lessons_done'), style: DsType.label.copyWith(color: DsColors.safe))),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _section({
    Key? key,
    required String title,
    required IconData icon,
    required Widget child,
    Color iconColor = DsColors.ink,
    Color background = DsColors.surface,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: DsSpace.m),
    child: SurfacePanel(
      key: key,
      color: background,
      padding: const EdgeInsets.all(DsSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: DsSpace.s),
              Expanded(child: Text(title, style: DsType.section)),
            ],
          ),
          const SizedBox(height: DsSpace.m),
          child,
        ],
      ),
    ),
  );

  Widget _bullets(List<Map<String, String>> items, String lang, IconData icon, Color color) => Column(
    children: [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: DsSpace.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: DsSpace.xxs),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: DsSpace.m),
              Expanded(child: Text(pickLang(item, lang), style: DsType.bodyLarge)),
            ],
          ),
        ),
    ],
  );
}
