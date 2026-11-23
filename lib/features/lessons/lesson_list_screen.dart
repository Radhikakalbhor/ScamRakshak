import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
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
          if (!snap.hasData) return const LoadingState();
          final all = snap.data!;
          final visible = _visible(all, s.locale);
          return ListView(
            padding: const EdgeInsets.fromLTRB(DsSpace.xl, DsSpace.s, DsSpace.xl, DsSpace.section),
            children: [
              _progressCard(s, all.length),
              const SizedBox(height: DsSpace.l),
              TextField(
                key: const Key('lessons_search'),
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                style: DsType.body,
                decoration: InputDecoration(
                  hintText: s.t('lessons_search_hint'),
                  hintStyle: DsType.body.copyWith(color: DsColors.muted),
                  prefixIcon: const Icon(Icons.search_rounded, color: DsColors.ink),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: s.t('lessons_clear_filters'),
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () => setState(() {
                            _query = '';
                            _search.clear();
                          }),
                        ),
                ),
              ),
              const SizedBox(height: DsSpace.m),
              _filters(s),
              const SizedBox(height: DsSpace.l),
              if (visible.isEmpty) _noMatch(s) else _grid(visible, s),
            ],
          );
        },
      ),
    );
  }

  Widget _error(S s) => Center(
    child: EmptyState(
      icon: Icons.error_outline_rounded,
      color: DsColors.alertSoft,
      title: s.t('lessons_load_error'),
      action: PrimaryButton(label: s.t('lessons_retry'), onPressed: _retry),
    ),
  );

  Widget _progressCard(S s, int total) {
    final done = _done.length;
    final allDone = total > 0 && done >= total;
    return PastelCard(
      key: const Key('lessons_progress'),
      color: DsColors.powder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('lessons_intro'), style: DsType.body),
          const SizedBox(height: DsSpace.l),
          Row(
            children: [
              Expanded(child: Text(s.t('lessons_your_progress'), style: DsType.greeting)),
              const SizedBox(width: DsSpace.s),
              Flexible(
                child: Text(
                  '$done / $total ${s.t('lessons_progress')}',
                  key: const Key('lessons_progress_text'),
                  textAlign: TextAlign.end,
                  style: DsType.title,
                ),
              ),
            ],
          ),
          const SizedBox(height: DsSpace.s),
          ProgressBar(value: total == 0 ? 0 : done / total, color: DsColors.brand),
          if (allDone) ...[
            const SizedBox(height: DsSpace.m),
            Row(
              children: [
                const Icon(Icons.emoji_events_outlined, color: DsColors.ink),
                const SizedBox(width: DsSpace.s),
                Expanded(child: Text(s.t('lessons_all_done'), style: DsType.title)),
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
              padding: const EdgeInsets.only(right: DsSpace.s),
              child: PillChip(
                key: Key('lessons_filter_$id'),
                label: label(id),
                icon: kLessonCategories.contains(id) ? lessonCategoryIcon(id) : null,
                selected: _filter == id,
                onTap: () => setState(() => _filter = id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _noMatch(S s) => EmptyState(
    icon: Icons.search_off_rounded,
    title: s.t('lessons_no_match'),
    action: PillChip(label: s.t('lessons_clear_filters'), onTap: _clearFilters),
  );

  /// One column on phones, two on wide screens.
  Widget _grid(List<Lesson> lessons, S s) => LayoutBuilder(
    builder: (context, c) {
      final cols = c.maxWidth >= 640 ? 2 : 1;
      const gap = DsSpace.m;
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
    final summary = pickLang(l.summary, lang);
    return PastelCard(
      key: Key('lesson_tile_${l.id}'),
      color: lessonTopicColor(l.id),
      onTap: () => _open(l),
      padding: const EdgeInsets.all(DsSpace.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(lessonTopicIcon(l.id)),
          const SizedBox(width: DsSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pickLang(l.title, lang), style: DsType.titleLarge),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: DsSpace.xs),
                  Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: DsType.small),
                ],
                const SizedBox(height: DsSpace.s),
                Row(
                  children: [
                    Icon(lessonCategoryIcon(l.category), size: 16, color: DsColors.ink),
                    const SizedBox(width: DsSpace.xs),
                    Flexible(
                      child: Text(
                        '${s.t('lessons_cat_${l.category}')} · ${l.cards.length} ${s.t('lessons_cards')}',
                        style: DsType.caption.copyWith(color: DsColors.ink),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: DsSpace.s),
          done
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded, color: DsColors.safe, size: 30),
                    Text(s.t('lessons_done'), style: DsType.caption.copyWith(color: DsColors.safe)),
                  ],
                )
              : const Icon(Icons.radio_button_unchecked_rounded, color: DsColors.muted, size: 30),
        ],
      ),
    );
  }
}
