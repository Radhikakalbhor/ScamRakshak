import 'package:flutter/material.dart';

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
      duration: const Duration(milliseconds: 300), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    LessonsStrings.ensure();
    final s = S.of(context);
    return FutureBuilder<Lesson>(
      future: _lesson,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(appBar: AppBar(), body: Center(child: Text(s.t('lessons_load_error'))));
        }
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.all(4),
                      width: i == _page ? 22 : 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: i == _page ? kCardColors[i % kCardColors.length] : Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
                if (last)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(s.t('lesson_completed'),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _page > 0 ? () => _go(-1) : null,
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: Text(s.t('lesson_prev')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: last ? () => Navigator.of(context).pop() : () => _go(1),
                          icon: Icon(last ? Icons.check_rounded : Icons.arrow_forward_rounded),
                          label: Text(last ? s.t('lesson_finish') : s.t('lesson_next')),
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
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(28)),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Text('${i + 1} / $n',
                  style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(lessonCardIcon(c.icon), size: 120, color: Colors.white),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        pickLang(c.text, lang),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 26, height: 1.4, fontWeight: FontWeight.w600),
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
