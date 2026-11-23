import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import 'lesson_detail_screen.dart';
import 'lesson_models.dart';
import 'lessons_strings.dart';

/// All safety lessons with overall progress, search and category filters.
class LessonListScreen extends StatefulWidget {
  const LessonListScreen({super.key});

  @override
  State<LessonListScreen> createState() => _LessonListScreenState();
}

class _LessonListScreenState extends State<LessonListScreen> {
  late Future<List<Lesson>> _lessons;
  Set<String> _done = {};
  String _query = '';

  /// 'all', 'todo' or a category id from [kLessonCategories].
  String _filter = 'all';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    LessonsStrings.ensure();
    _lessons = LessonRepository.loadAll();
    _refreshProgress();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refreshProgress() async {
    final d = await LessonProgress.completed();
    if (mounted) setState(() => _done = d);
  }

  Future<void> _open(Lesson l) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LessonDetailScreen(lessonId: l.id)));
    await _refreshProgress();
  }

  void _retry() {
    final next = LessonRepository.loadAll();
    setState(() {
      _lessons = next;
    });
  }

  void _clearFilters() => setState(() {
    _filter = 'all';
    _query = '';
    _search.clear();
  });

  List<Lesson> _visible(List<Lesson> all, String lang) => all.where((l) {
    if (_filter == 'todo' && _done.contains(l.id)) return false;
    if (kLessonCategories.contains(_filter) && l.category != _filter) return false;
    return l.matches(_query, lang);
  }).toList();

  @override
  Widget build(BuildContext context) {
    LessonsStrings.ensure();
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('lessons_title'))),
      body: FutureBuilder<List<Lesson>>(
        future: _lessons,
        builder: (context, snap) {
          if (snap.hasError) return _error(s);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = snap.data!;
          final visible = _visible(all, s.locale);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _progressCard(s, all.length),
              const SizedBox(height: 14),
              TextField(
                key: const Key('lessons_search'),
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: s.t('lessons_search_hint'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () => setState(() {
                            _query = '';
                            _search.clear();
                          }),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 10),
              _filters(s),
              const SizedBox(height: 12),
              if (visible.isEmpty) _noMatch(s) else _grid(visible, s),
            ],
          );
        },
      ),
    );
  }

  Widget _error(S s) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 56, color: AppTheme.errorRed),
          const SizedBox(height: 12),
          Text(s.t('lessons_load_error'), style: const TextStyle(fontSize: 18), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _retry, child: Text(s.t('lessons_retry'))),
        ],
      ),
    ),
  );

  Widget _progressCard(S s, int total) {
    final done = _done.length;
    final allDone = total > 0 && done >= total;
    return Container(
      key: const Key('lessons_progress'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppTheme.primaryTeal, AppTheme.primaryDarkTeal]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('lessons_intro'), style: const TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  s.t('lessons_your_progress'),
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$done / $total ${s.t('lessons_progress')}',
                  key: const Key('lessons_progress_text'),
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: total == 0 ? 0 : done / total,
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
            backgroundColor: Colors.white24,
            color: Colors.white,
          ),
          if (allDone) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.emoji_events_rounded, color: Colors.amberAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.t('lessons_all_done'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _filters(S s) {
    final options = ['all', ...kLessonCategories, 'todo'];
    String label(String id) => switch (id) {
      'all' => s.t('lessons_filter_all'),
      'todo' => s.t('lessons_filter_todo'),
      _ => s.t('lessons_cat_$id'),
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final id in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: Key('lessons_filter_$id'),
                label: Text(label(id)),
                avatar: kLessonCategories.contains(id) ? Icon(lessonCategoryIcon(id), size: 18) : null,
                selected: _filter == id,
                onSelected: (_) => setState(() => _filter = id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _noMatch(S s) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      children: [
        const Icon(Icons.search_off_rounded, size: 56, color: AppTheme.textSecondary),
        const SizedBox(height: 8),
        Text(s.t('lessons_no_match'), style: const TextStyle(fontSize: 17), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        TextButton(onPressed: _clearFilters, child: Text(s.t('lessons_clear_filters'))),
      ],
    ),
  );

  /// One column on phones, two on wide screens.
  Widget _grid(List<Lesson> lessons, S s) => LayoutBuilder(
    builder: (context, c) {
      final cols = c.maxWidth >= 640 ? 2 : 1;
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final l in lessons) SizedBox(width: w, child: _tile(l, s))],
      );
    },
  );

  Widget _tile(Lesson l, S s) {
    final lang = s.locale;
    final done = _done.contains(l.id);
    final color = lessonTopicColor(l.id);
    final summary = pickLang(l.summary, lang);
    return Card(
      key: Key('lesson_tile_${l.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(l),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 6, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(lessonTopicIcon(l.id), color: color, size: 32),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pickLang(l.title, lang),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.25),
                            ),
                            if (summary.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                summary,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(lessonCategoryIcon(l.category), size: 16, color: color),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    '${s.t('lessons_cat_${l.category}')} · ${l.cards.length} ${s.t('lessons_cards')}',
                                    style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      done
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_rounded, color: AppTheme.successGreen, size: 30),
                                Text(
                                  s.t('lessons_done'),
                                  style: const TextStyle(color: AppTheme.successGreen, fontSize: 12),
                                ),
                              ],
                            )
                          : const Icon(Icons.radio_button_unchecked_rounded, color: Colors.grey, size: 30),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
