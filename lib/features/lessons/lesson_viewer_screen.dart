import 'package:flutter/material.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import 'lesson_models.dart';
import 'lessons_strings.dart';

/// Swipeable card viewer for one lesson. Marks the lesson done when the last card is reached.
class LessonViewerScreen extends StatefulWidget {
  final String lessonId;
  const LessonViewerScreen({super.key, required this.lessonId});

  @override
  State<LessonViewerScreen> createState() => _LessonViewerScreenState();
}

class _LessonViewerScreenState extends State<LessonViewerScreen> {
  final PageController _pc = PageController();
  late Future<Lesson> _lesson;
  int _page = 0;
  bool _marked = false;

  @override
  void initState() {
    super.initState();
    LessonsStrings.ensure();
    _lesson = LessonRepository.load(widget.lessonId);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _onPage(int i, int total) {
    setState(() => _page = i);
    if (i == total - 1 && !_marked) {
      _marked = true;
      LessonProgress.markDone(widget.lessonId);
    }
  }

  void _go(int delta) => _pc.animateToPage(_page + delta,
      duration: DsMotion.normal, curve: DsMotion.curve);

  @override
  Widget build(BuildContext context) {
    LessonsStrings.ensure();
    final s = S.of(context);
    return FutureBuilder<Lesson>(
      future: _lesson,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: EmptyState(icon: Icons.error_outline_rounded, color: DsColors.alertSoft, title: s.t('lessons_load_error')),
            ),
          );
        }
        if (!snap.hasData) {
          return const Scaffold(body: LoadingState());
        }
        final l = snap.data!;
        final n = l.cards.length;
        if (n == 1 && !_marked) {
          _marked = true;
          LessonProgress.markDone(widget.lessonId);
        }
        final last = _page == n - 1;
        return Scaffold(
          appBar: AppBar(title: Text(pickLang(l.title, s.locale))),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pc,
                    itemCount: n,
                    onPageChanged: (i) => _onPage(i, n),
                    itemBuilder: (_, i) => _card(l.cards[i], i, n, s.locale),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    n,
                    (i) => AnimatedContainer(
                      duration: DsMotion.normal,
                      curve: DsMotion.curve,
                      margin: const EdgeInsets.all(DsSpace.xs),
                      width: i == _page ? 22 : 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: i == _page ? DsColors.ink : DsColors.track,
                        borderRadius: BorderRadius.circular(DsRadius.pill),
                      ),
                    ),
                  ),
                ),
                if (last)
                  Padding(
                    padding: const EdgeInsets.only(top: DsSpace.s),
                    child: Text(s.t('lesson_completed'), style: DsType.title.copyWith(color: DsColors.safe)),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(DsSpace.xl, DsSpace.s, DsSpace.xl, DsSpace.l),
                  child: Row(
                    children: [
                      Expanded(
                        child: PrimaryButton(
                          label: s.t('lesson_prev'),
                          icon: Icons.arrow_back_rounded,
                          filled: false,
                          onPressed: _page > 0 ? () => _go(-1) : null,
                        ),
                      ),
                      const SizedBox(width: DsSpace.m),
                      Expanded(
                        child: PrimaryButton(
                          label: last ? s.t('lesson_finish') : s.t('lesson_next'),
                          icon: last ? Icons.check_rounded : Icons.arrow_forward_rounded,
                          onPressed: last ? () => Navigator.of(context).pop() : () => _go(1),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _card(LessonCard c, int i, int n, String lang) {
    final color = kCardColors[i % kCardColors.length];
    return Padding(
      padding: const EdgeInsets.all(DsSpace.l),
      child: PastelCard(
        color: color,
        padding: const EdgeInsets.all(DsSpace.xxl),
        child: Column(
          children: [
            Align(alignment: Alignment.topRight, child: Text('${i + 1} / $n', style: DsType.label)),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconBadge(lessonCardIcon(c.icon), size: 140),
                      const SizedBox(height: DsSpace.section),
                      Text(
                        pickLang(c.text, lang),
                        textAlign: TextAlign.center,
                        style: DsType.headline.copyWith(fontSize: 26, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
