import 'package:flutter/material.dart';

import '../../core/strings.dart';
import 'lesson_models.dart';
import 'lesson_viewer_screen.dart';
import 'lessons_strings.dart';

/// List of the 4 safety lessons with completion ticks.
class LessonListScreen extends StatefulWidget {
  const LessonListScreen({super.key});

  @override
  State<LessonListScreen> createState() => _LessonListScreenState();
}

class _LessonListScreenState extends State<LessonListScreen> {
  late Future<List<Lesson>> _lessons;
  Set<String> _done = {};

  @override
  void initState() {
    super.initState();
    LessonsStrings.ensure();
    _lessons = LessonRepository.loadAll();
    _refreshProgress();
  }

  Future<void> _refreshProgress() async {
    final d = await LessonProgress.completed();
    if (mounted) setState(() => _done = d);
  }

  Future<void> _open(Lesson l) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LessonViewerScreen(lessonId: l.id)),
    );
    await _refreshProgress();
  }

  @override
  Widget build(BuildContext context) {
    LessonsStrings.ensure();
    final s = S.of(context);
    final lang = s.locale;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('lessons_title'))),
      body: FutureBuilder<List<Lesson>>(
        future: _lessons,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(s.t('lessons_load_error')));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final lessons = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(s.t('lessons_intro'), style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: lessons.isEmpty ? 0 : _done.length / lessons.length,
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
              ),
              const SizedBox(height: 6),
              Text('${_done.length} / ${lessons.length} ${s.t('lessons_progress')}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              for (final l in lessons) _tile(l, lang, s),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(Lesson l, String lang, S s) {
    final done = _done.contains(l.id);
    final color = lessonTopicColor(l.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(l),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
                child: Icon(lessonTopicIcon(l.id), color: Colors.white, size: 38),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pickLang(l.title, lang),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${l.cards.length} ${s.t('lessons_cards')}',
                        style: const TextStyle(fontSize: 15)),
                  ],
                ),
              ),
              done
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 36),
                      Text(s.t('lessons_done'), style: const TextStyle(color: Color(0xFF2E7D32))),
                    ])
                  : const Icon(Icons.radio_button_unchecked_rounded, color: Colors.grey, size: 36),
            ],
          ),
        ),
      ),
    );
  }
}
