import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.t('lessons_load_error'), style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      final next = LessonRepository.load(widget.lessonId);
                      setState(() {
                        _lesson = next;
                      });
                    },
                    child: Text(s.t('lessons_retry')),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final l = snap.data!;
        final lang = s.locale;
        final color = lessonTopicColor(l.id);
        return Scaffold(
          appBar: AppBar(title: Text(pickLang(l.title, lang))),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _header(s, l, color),
                if (l.summary.isNotEmpty)
                  _section(
                    title: s.t('lesson_what'),
                    icon: Icons.info_rounded,
                    color: color,
                    child: Text(pickLang(l.summary, lang), style: const TextStyle(fontSize: 17, height: 1.45)),
                  ),
                if (l.example.isNotEmpty)
                  _section(
                    key: const Key('lesson_example'),
                    title: s.t('lesson_example'),
                    icon: Icons.format_quote_rounded,
                    color: AppTheme.warningOrange,
                    background: const Color(0xFFFFF8E1),
                    child: Text(
                      pickLang(l.example, lang),
                      style: const TextStyle(fontSize: 16, height: 1.45, fontStyle: FontStyle.italic),
                    ),
                  ),
                if (l.signs.isNotEmpty)
                  _section(
                    key: const Key('lesson_signs'),
                    title: s.t('lesson_signs'),
                    icon: Icons.warning_amber_rounded,
                    color: AppTheme.errorRed,
                    child: _bullets(l.signs, lang, Icons.error_outline_rounded, AppTheme.errorRed),
                  ),
                if (l.steps.isNotEmpty)
                  _section(
                    key: const Key('lesson_steps'),
                    title: s.t('lesson_steps'),
                    icon: Icons.shield_rounded,
                    color: AppTheme.successGreen,
                    child: _bullets(l.steps, lang, Icons.check_circle_rounded, AppTheme.successGreen),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('lesson_open_cards'),
                  style: FilledButton.styleFrom(backgroundColor: color),
                  onPressed: _openCards,
                  icon: const Icon(Icons.style_rounded),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '${s.t('lesson_open_cards')} (${l.cards.length})',
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_done)
                  OutlinedButton.icon(
                    key: const Key('lesson_marked'),
                    onPressed: null,
                    icon: const Icon(Icons.check_circle_rounded, color: AppTheme.successGreen),
                    label: Text(s.t('lesson_marked'), style: const TextStyle(color: AppTheme.successGreen)),
                  )
                else
                  OutlinedButton.icon(
                    key: const Key('lesson_mark_done'),
                    onPressed: _markDone,
                    icon: const Icon(Icons.task_alt_rounded),
                    label: Text(s.t('lesson_mark_done')),
                  ),
                const SizedBox(height: 10),
                TextButton.icon(
                  key: const Key('lesson_take_quiz'),
                  onPressed: _openQuiz,
                  icon: const Icon(Icons.psychology_rounded),
                  label: Text(s.t('lesson_take_quiz'), style: const TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(S s, Lesson l, Color color) => Container(
    padding: const EdgeInsets.all(18),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
          child: Icon(lessonTopicIcon(l.id), color: Colors.white, size: 40),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pickLang(l.title, s.locale),
                style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(s.t('lessons_cat_${l.category}'), style: const TextStyle(color: Colors.white70, fontSize: 15)),
              if (_done) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        s.t('lessons_done'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _section({
    Key? key,
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
    Color? background,
  }) => Card(
    key: key,
    margin: const EdgeInsets.only(bottom: 12),
    color: background,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    ),
  );

  Widget _bullets(List<Map<String, String>> items, String lang, IconData icon, Color color) => Column(
    children: [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(pickLang(item, lang), style: const TextStyle(fontSize: 16, height: 1.4))),
            ],
          ),
        ),
    ],
  );
}
