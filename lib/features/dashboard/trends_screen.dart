import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../call_detector/call_detector_screen.dart';
import '../call_detector/call_strings.dart';
import '../lessons/lesson_detail_screen.dart';
import '../message_detector/message_detector_screen.dart';
import '../report/report_strings.dart';
import 'detection_history.dart';
import 'trends_stats.dart';
import 'trends_strings.dart';

/// Scam category -> lesson that teaches it (for "Learn how to stay safe").
const Map<String, String> kCategoryLesson = {
  'otp_request': 'otp',
  'upi_collect': 'upi_pin',
  'fake_kyc': 'fake_kyc',
  'digital_arrest': 'digital_arrest',
  'courier_customs': 'courier_customs',
  'remote_access': 'remote_access',
  'lottery_prize': 'lottery_prize',
  'loan_threat': 'loan_app',
  'phishing_link': 'phishing',
  'electricity_bill': 'phishing',
  'telecom_threat': 'phishing',
};

String categoryLabel(S s, String id) =>
    (id == 'phishing_link' || id == 'other') ? s.t('trends_cat_$id') : s.t('script_$id');

enum _ServerState { idle, loading, offline, error, data }

/// Scam Trends: statistics from the checks done on this phone, plus optional server reports.
class TrendsScreen extends ConsumerStatefulWidget {
  /// Current time source (inject in tests).
  final DateTime Function() clock;
  const TrendsScreen({super.key, this.clock = DateTime.now});

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  late Future<List<DetectionRecord>> _records;
  bool _includePractice = false;
  _ServerState _server = _ServerState.idle;
  ServerTrends? _serverData;

  /// From GET /trends/summary (null on older servers, then [_serverData] is shown as "mixed").
  ServerSummary? _summary;
  List<EmergingAlert> _alerts = const [];

  @override
  void initState() {
    super.initState();
    _ensureStrings();
    _records = ref.read(detectionHistoryProvider).load();
  }

  void _ensureStrings() {
    TrendsStrings.ensure();
    CallStrings.ensure();
    ReportStrings.ensure();
  }

  void _reload() {
    final next = ref.read(detectionHistoryProvider).load();
    setState(() {
      _records = next;
    });
  }

  Future<void> _push(String route, Widget Function() fallback) async {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      await router.push(route);
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => fallback()));
    }
    if (mounted) _reload();
  }

  Future<void> _clear() async {
    final s = S.of(context);
    final ok = await showDsDialog<bool>(
      context,
      title: s.t('trends_clear'),
      content: Text(s.t('trends_clear_confirm'), style: DsType.body),
      actions: (ctx) => [
        PrimaryButton(
          key: const Key('trends_clear_ok'),
          label: s.t('trends_delete'),
          icon: Icons.delete_sweep_rounded,
          color: DsColors.alert,
          onPressed: () => Navigator.pop(ctx, true),
        ),
        PrimaryButton(label: s.t('trends_cancel'), filled: false, onPressed: () => Navigator.pop(ctx, false)),
      ],
    );
    if (ok != true || !mounted) return;
    await ref.read(detectionHistoryProvider).clear();
    if (!mounted) return;
    _reload();
    showDsToast(context, s.t('trends_cleared'));
  }

  Future<void> _loadServer() async {
    setState(() => _server = _ServerState.loading);
    final api = ref.read(apiClientProvider);
    try {
      ServerSummary? summary;
      ServerTrends? rowsData;
      try {
        summary = ServerSummary.fromJson(await api.getTrendSummary());
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
        rowsData = ServerTrends.fromRows(await api.getTrends()); // older server: one mixed total
      }
      var alerts = const <EmergingAlert>[];
      try {
        alerts = (await api.getAlerts()).map(EmergingAlert.tryFrom).whereType<EmergingAlert>().toList();
      } catch (_) {} // alerts are optional
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _serverData = rowsData;
        _alerts = alerts;
        _server = _ServerState.data;
      });
    } on ApiOfflineException {
      if (mounted) setState(() => _server = _ServerState.offline);
    } catch (_) {
      if (mounted) setState(() => _server = _ServerState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureStrings();
    final s = S.of(context);
    return FutureBuilder<List<DetectionRecord>>(
      future: _records,
      builder: (context, snap) {
        final records = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(s.t('scam_trends')),
            actions: [
              if (records != null && records.isNotEmpty)
                IconButton(
                  key: const Key('trends_clear'),
                  tooltip: s.t('trends_clear'),
                  icon: const Icon(Icons.delete_sweep_rounded),
                  onPressed: _clear,
                ),
            ],
          ),
          body: SafeArea(child: _body(s, snap)),
        );
      },
    );
  }

  Widget _body(S s, AsyncSnapshot<List<DetectionRecord>> snap) {
    if (snap.hasError) {
      return Center(
        child: EmptyState(
          icon: Icons.error_outline_rounded,
          color: DsColors.alertSoft,
          title: s.t('trends_load_error'),
          action: PrimaryButton(label: s.t('trends_retry'), onPressed: _reload),
        ),
      );
    }
    if (!snap.hasData) return const LoadingState();
    final records = snap.data!;
    final stats = TrendStats.from(records, now: widget.clock(), includePractice: _includePractice);
    return ListView(
      padding: const EdgeInsets.fromLTRB(DsSpace.xl, DsSpace.s, DsSpace.xl, DsSpace.section),
      children: [
        Row(
          children: [
            const IconBadge(Icons.phone_android_rounded, size: kDsTouch, background: DsColors.powder),
            const SizedBox(width: DsSpace.m),
            Expanded(child: Text(s.t('trends_local_title'), style: DsType.cardTitle)),
          ],
        ),
        const SizedBox(height: DsSpace.s),
        Text(s.t('trends_local_note'), style: DsType.small),
        const SizedBox(height: DsSpace.l),
        if (stats.practiceExcluded > 0 || _includePractice) _practiceToggle(s, stats),
        if (stats.isEmpty) _empty(s) else ..._localStats(s, stats),
        const SizedBox(height: DsSpace.xl),
        _serverSection(s),
      ],
    );
  }

  Widget _practiceToggle(S s, TrendStats stats) => Padding(
    padding: const EdgeInsets.only(bottom: DsSpace.m),
    child: SurfacePanel(
      color: DsColors.powder,
      padding: const EdgeInsets.symmetric(vertical: DsSpace.s, horizontal: DsSpace.xs),
      child: Column(
        children: [
          if (stats.practiceExcluded > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(DsSpace.l, DsSpace.s, DsSpace.l, 0),
              child: Row(
                children: [
                  const Icon(Icons.school_rounded, color: DsColors.ink),
                  const SizedBox(width: DsSpace.s),
                  Expanded(
                    child: Text(
                      '${stats.practiceExcluded} ${s.t('trends_practice_note')}',
                      key: const Key('trends_practice_note'),
                      style: DsType.body,
                    ),
                  ),
                ],
              ),
            ),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const Key('trends_include_practice'),
              title: Text(s.t('trends_include_practice'), style: DsType.title),
              value: _includePractice,
              onChanged: (v) => setState(() => _includePractice = v),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _empty(S s) => SurfacePanel(
    key: const Key('trends_empty'),
    child: EmptyState(
      icon: Icons.insights_rounded,
      title: s.t('trends_empty_title'),
      message: s.t('trends_empty_body'),
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrimaryButton(
            key: const Key('trends_go_message'),
            label: s.t('trends_check_message'),
            icon: Icons.mark_chat_unread_rounded,
            onPressed: () => _push('/message', () => const MessageDetectorScreen()),
          ),
          const SizedBox(height: DsSpace.s),
          PrimaryButton(
            key: const Key('trends_go_call'),
            label: s.t('trends_check_call'),
            icon: Icons.phone_in_talk_rounded,
            filled: false,
            onPressed: () => _push('/call', () => const CallDetectorScreen()),
          ),
        ],
      ),
    ),
  );

  List<Widget> _localStats(S s, TrendStats st) => [
    _tiles(s, st),
    const SizedBox(height: DsSpace.m),
    _chartCard(s, st),
    const SizedBox(height: DsSpace.m),
    _categoriesCard(s, st),
    const SizedBox(height: DsSpace.m),
    _recentCard(s, st),
  ];

  Widget _tiles(S s, TrendStats st) {
    final risky = st.scams + st.suspicious;
    final tiles = [
      _Tile(const Key('trends_tile_messages'), Icons.sms_rounded, DsColors.powder, '${st.messages}', s.t('trends_messages')),
      _Tile(const Key('trends_tile_calls'), Icons.call_rounded, DsColors.lavender, '${st.calls}', s.t('trends_calls')),
      _Tile(
        const Key('trends_tile_scams'),
        Icons.gpp_bad_rounded,
        DsColors.peach,
        '$risky',
        s.t('trends_scams'),
        extra: st.suspicious > 0 ? '${st.scams} + ${st.suspicious} ${s.t('trends_suspicious_n')}' : null,
      ),
      _Tile(const Key('trends_tile_safe'), Icons.verified_user_rounded, DsColors.mint, '${st.safe}', s.t('trends_safe')),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 600 ? 4 : 2;
        const gap = DsSpace.m;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: w, child: _tile(t))],
        );
      },
    );
  }

  Widget _tile(_Tile t) => PastelCard(
    key: t.key,
    color: t.color,
    padding: const EdgeInsets.all(DsSpace.l),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconBadge(t.icon, size: 40),
        const SizedBox(height: DsSpace.s),
        Text(t.value, style: DsType.numberSmall),
        Text(t.label, style: DsType.label),
        if (t.extra != null) Text(t.extra!, style: DsType.caption.copyWith(color: DsColors.ink)),
      ],
    ),
  );

  Widget _card({Key? key, required String title, required IconData icon, required Widget child}) => SurfacePanel(
    key: key,
    padding: const EdgeInsets.all(DsSpace.l),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: DsColors.ink),
            const SizedBox(width: DsSpace.s),
            Expanded(child: Text(title, style: DsType.section)),
          ],
        ),
        const SizedBox(height: DsSpace.m),
        child,
      ],
    ),
  );

  static final _axis = DsType.chartTick;

  Widget _chartCard(S s, TrendStats st) {
    final maxTotal = st.daily.fold<int>(0, (m, d) => math.max(m, d.total));
    final maxY = math.max(1, maxTotal).toDouble();
    final step = math.max(1, (maxY / 4).ceil()).toDouble();
    return _card(
      key: const Key('trends_chart'),
      title: s.t('trends_last7'),
      icon: Icons.bar_chart_rounded,
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(enabled: false),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: step,
                  getDrawingHorizontalLine: (_) => const FlLine(color: DsColors.line, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: step,
                      getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: _axis),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= st.daily.length) return const SizedBox.shrink();
                        final d = st.daily[i].day;
                        return Padding(
                          padding: const EdgeInsets.only(top: DsSpace.xs),
                          child: Text('${d.day}/${d.month}', style: _axis),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < st.daily.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: st.daily[i].total.toDouble(),
                          width: 16,
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(DsRadius.small / 2),
                          rodStackItems: [
                            BarChartRodStackItem(0, st.daily[i].risky.toDouble(), DsColors.alert),
                            BarChartRodStackItem(
                              st.daily[i].risky.toDouble(),
                              st.daily[i].total.toDouble(),
                              DsColors.safe,
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: DsSpace.s),
          Wrap(
            spacing: DsSpace.l,
            children: [
              _legend(DsColors.alert, s.t('trends_legend_risky')),
              _legend(DsColors.safe, s.t('trends_legend_safe')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(Color c, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(DsRadius.small / 3)),
      ),
      const SizedBox(width: DsSpace.s),
      Flexible(child: Text(label, style: DsType.small.copyWith(color: DsColors.ink))),
    ],
  );

  Widget _categoriesCard(S s, TrendStats st) {
    final top = st.topCategory;
    final maxCount = st.categories.isEmpty ? 1 : st.categories.first.value;
    final lesson = top == null ? null : kCategoryLesson[top];
    return _card(
      key: const Key('trends_categories'),
      title: s.t('trends_categories'),
      icon: Icons.category_rounded,
      child: st.categories.isEmpty
          ? Text(s.t('trends_no_scams'), style: DsType.body)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  key: const Key('trends_top_category'),
                  padding: const EdgeInsets.all(DsSpace.m),
                  margin: const EdgeInsets.only(bottom: DsSpace.m),
                  decoration: BoxDecoration(color: DsColors.alertSoft, borderRadius: BorderRadius.circular(DsRadius.tile)),
                  child: Row(
                    children: [
                      const Icon(Icons.local_fire_department_rounded, color: DsColors.alert),
                      const SizedBox(width: DsSpace.s),
                      Expanded(
                        child: Text('${s.t('trends_most_common')}: ${categoryLabel(s, top!)}', style: DsType.title),
                      ),
                    ],
                  ),
                ),
                for (final e in st.categories)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DsSpace.m),
                    child: Row(
                      children: [
                        SizedBox(width: 130, child: Text(categoryLabel(s, e.key), style: DsType.small.copyWith(color: DsColors.ink))),
                        Expanded(child: ProgressBar(value: e.value / maxCount, color: DsColors.alert)),
                        const SizedBox(width: DsSpace.s),
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${e.value}',
                            key: Key('trends_cat_count_${e.key}'),
                            textAlign: TextAlign.end,
                            style: DsType.label,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (lesson != null)
                  PrimaryButton(
                    key: const Key('trends_learn'),
                    label: s.t('trends_learn'),
                    icon: Icons.school_rounded,
                    filled: false,
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => LessonDetailScreen(lessonId: lesson))),
                  ),
              ],
            ),
    );
  }

  String _when(S s, DateTime t) {
    final now = widget.clock();
    final l = t.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(l.year, l.month, l.day);
    final hm = '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    final diff = today.difference(day).inDays;
    if (diff == 0) return '${s.t('trends_today')} $hm';
    if (diff == 1) return '${s.t('trends_yesterday')} $hm';
    return '${l.day}/${l.month}/${l.year}';
  }

  Widget _recentCard(S s, TrendStats st) => _card(
    key: const Key('trends_recent'),
    title: s.t('trends_recent'),
    icon: Icons.history_rounded,
    child: Column(
      children: [
        for (final r in st.recent)
          Padding(padding: const EdgeInsets.only(bottom: DsSpace.s), child: _recentRow(s, r)),
      ],
    ),
  );

  Widget _recentRow(S s, DetectionRecord r) {
    final (color, soft) = switch (r.verdict) {
      'scam' => (DsColors.alert, DsColors.alertSoft),
      'suspicious' => (DsColors.caution, DsColors.cautionSoft),
      _ => (DsColors.safe, DsColors.safeSoft),
    };
    final title = r.isRisky ? categoryLabel(s, r.category.isEmpty ? 'other' : r.category) : s.t('trends_verdict_safe');
    final sub = [
      s.t('trends_kind_${r.kind}'),
      if (r.score != null) '${(r.score! * 100).round()}%',
      _when(s, r.time),
      if (r.sample) s.t('trends_practice_tag'),
    ].join(' · ');
    return DsListTile(
      leading: IconBadge(
        r.kind == 'call' ? Icons.call_rounded : Icons.sms_rounded,
        size: 40,
        background: soft,
        foreground: color,
      ),
      title: title,
      subtitle: sub,
      trailing: _pill(s.t('trends_verdict_${r.verdict}'), color),
    );
  }

  Widget _pill(String text, Color color, {Key? key}) => Container(
    key: key,
    padding: const EdgeInsets.symmetric(horizontal: DsSpace.m, vertical: DsSpace.xs),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(DsRadius.pill)),
    child: Text(text, style: DsType.caption.copyWith(color: DsColors.onDark)),
  );

  // ------------------------------------------------------------------ server

  Widget _serverSection(S s) => _card(
    key: const Key('trends_server'),
    title: s.t('trends_server_title'),
    icon: Icons.cloud_rounded,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.t('trends_server_note'), style: DsType.small),
        const SizedBox(height: DsSpace.m),
        ..._serverBody(s),
      ],
    ),
  );

  List<Widget> _serverBody(S s) {
    Widget loadButton() => PrimaryButton(
      key: const Key('trends_server_load'),
      label: s.t('trends_server_load'),
      icon: Icons.cloud_download_rounded,
      filled: false,
      onPressed: _loadServer,
    );
    Widget message(String key, IconData icon, Color color) => Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.m),
      child: Row(
        key: Key('trends_server_$key'),
        children: [
          Icon(icon, color: color),
          const SizedBox(width: DsSpace.s),
          Expanded(child: Text(s.t('trends_server_$key'), style: DsType.body)),
        ],
      ),
    );
    switch (_server) {
      case _ServerState.idle:
        return [loadButton()];
      case _ServerState.loading:
        return [LoadingState(message: s.t('trends_server_loading'))];
      case _ServerState.offline:
        return [message('offline', Icons.wifi_off_rounded, DsColors.caution), loadButton()];
      case _ServerState.error:
        return [message('error', Icons.error_outline_rounded, DsColors.alert), loadButton()];
      case _ServerState.data:
        final sum = _summary;
        if (sum != null) {
          return [
            _alertsCard(s),
            _sourceBlock(s, 'live', sum.live, sum.minCount, DsColors.brand),
            const SizedBox(height: DsSpace.m),
            _sourceBlock(s, 'synthetic', sum.synthetic, sum.minCount, DsColors.muted),
            const SizedBox(height: DsSpace.s),
            loadButton(),
          ];
        }
        final d = _serverData!;
        if (d.total == 0) return [message('empty', Icons.inbox_rounded, DsColors.muted)];
        return [
          _sourceChip(s, 'mixed', DsColors.caution),
          const SizedBox(height: DsSpace.s),
          Text('${d.total} ${s.t('trends_server_total')}', key: const Key('trends_server_total'), style: DsType.cardTitle),
          const SizedBox(height: DsSpace.m),
          Text(s.t('trends_server_districts'), style: DsType.title),
          const SizedBox(height: DsSpace.s),
          ..._bars(d.byDistrict.take(5).toList(), (k) => k, DsColors.powderDeep),
          const SizedBox(height: DsSpace.m),
          Text(s.t('trends_server_types'), style: DsType.title),
          const SizedBox(height: DsSpace.s),
          ..._bars(d.byType, (k) => s.t('report_type_$k'), DsColors.peachDeep),
        ];
    }
  }

  Widget _sourceChip(S s, String source, Color color) =>
      Align(alignment: Alignment.centerLeft, child: _pill(s.t('trends_src_$source'), color, key: Key('trends_src_$source')));

  /// One labelled data source: total, districts, scam types, weekly trend, privacy note.
  Widget _sourceBlock(S s, String source, SourceTrends d, int minCount, Color color) => Container(
        key: Key('trends_block_$source'),
        padding: const EdgeInsets.all(DsSpace.m),
        decoration: BoxDecoration(
          color: DsColors.page,
          border: Border.all(color: DsColors.line),
          borderRadius: BorderRadius.circular(DsRadius.tile),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sourceChip(s, source, color),
          const SizedBox(height: DsSpace.xs),
          Text(s.t('trends_src_${source}_note'), style: DsType.small),
          const SizedBox(height: DsSpace.s),
          Text('${d.total} ${s.t('trends_server_total')}', key: Key('trends_total_$source'), style: DsType.cardTitle),
          if (d.total == 0)
            Text(s.t('trends_src_none'), style: DsType.body)
          else ...[
            if (d.byDistrict.isNotEmpty) ...[
              const SizedBox(height: DsSpace.m),
              Text(s.t('trends_server_districts'), style: DsType.title),
              const SizedBox(height: DsSpace.s),
              ..._bars(d.byDistrict.take(5).toList(), (k) => k, DsColors.powderDeep),
            ],
            if (d.byType.isNotEmpty) ...[
              const SizedBox(height: DsSpace.m),
              Text(s.t('trends_server_types'), style: DsType.title),
              const SizedBox(height: DsSpace.s),
              ..._bars(d.byType, (k) => s.t('report_type_$k'), DsColors.peachDeep),
            ],
            if (d.weekly.isNotEmpty) ...[
              const SizedBox(height: DsSpace.m),
              Text(s.t('trends_weekly'), style: DsType.title),
              const SizedBox(height: DsSpace.s),
              _weekly(s, d.weekly, minCount, source == 'live' ? DsColors.lavenderDeep : DsColors.muted, source),
            ],
          ],
          if (d.suppressed > 0) ...[
            const SizedBox(height: DsSpace.s),
            Text(
              s.t('trends_suppressed').replaceAll('{n}', '$minCount').replaceAll('{k}', '${d.suppressed}'),
              key: Key('trends_suppressed_$source'),
              style: DsType.caption,
            ),
          ],
        ]),
      );

  /// Weekly bars; a suppressed week shows "<5" and no bar.
  Widget _weekly(S s, List<WeekCount> weeks, int minCount, Color color, String source) {
    final maxV = weeks.fold<int>(1, (m, w) => math.max(m, w.count ?? 0));
    return SizedBox(
      height: 96,
      child: Row(
        key: Key('trends_weekly_$source'),
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final w in weeks)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DsSpace.xxs),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(w.count == null ? '<$minCount' : '${w.count}',
                      style: DsType.chartMicro,
                      maxLines: 1,
                      overflow: TextOverflow.clip),
                  Container(
                    height: w.count == null ? 2 : 56.0 * (w.count! / maxV),
                    decoration: BoxDecoration(
                      color: w.count == null ? DsColors.track : color,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(DsSpace.xs)),
                    ),
                  ),
                  Text('${w.weekStart.day}/${w.weekStart.month}', style: DsType.chartMicro.copyWith(color: DsColors.muted), maxLines: 1),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _alertsCard(S s) => Container(
        key: const Key('trends_alerts'),
        margin: const EdgeInsets.only(bottom: DsSpace.m),
        padding: const EdgeInsets.all(DsSpace.m),
        decoration: BoxDecoration(
          color: _alerts.isEmpty ? DsColors.page : DsColors.alertSoft,
          border: Border.all(color: _alerts.isEmpty ? DsColors.line : DsColors.alertSoft),
          borderRadius: BorderRadius.circular(DsRadius.tile),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(_alerts.isEmpty ? Icons.notifications_none_rounded : Icons.campaign_rounded,
                color: _alerts.isEmpty ? DsColors.muted : DsColors.alert),
            const SizedBox(width: DsSpace.s),
            Expanded(child: Text(s.t('trends_alerts_title'), style: DsType.title)),
          ]),
          const SizedBox(height: DsSpace.s),
          if (_alerts.isEmpty)
            Text(s.t('trends_alerts_none'), style: DsType.body)
          else
            for (final a in _alerts)
              Padding(
                padding: const EdgeInsets.only(bottom: DsSpace.s),
                child: Text(
                  a.kind == 'spike'
                      ? s
                          .t('trends_alert_spike')
                          .replaceAll('{type}', s.t('report_type_${a.type}'))
                          .replaceAll('{district}', a.district)
                          .replaceAll('{recent}', '${a.count}')
                          .replaceAll('{base}', a.baseline.toStringAsFixed(1))
                      : s
                          .t('trends_alert_cluster')
                          .replaceAll('{cat}', categoryLabel(s, a.category))
                          .replaceAll('{size}', '${a.count}'),
                  key: Key('trends_alert_${a.kind}_${a.district}${a.type}${a.category}'),
                  style: DsType.body,
                ),
              ),
        ]),
      );

  List<Widget> _bars(List<MapEntry<String, int>> rows, String Function(String) label, Color color) {
    final maxV = rows.isEmpty ? 1 : rows.first.value;
    return [
      for (final e in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: DsSpace.s),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(label(e.key), overflow: TextOverflow.ellipsis, style: DsType.small.copyWith(color: DsColors.ink)),
              ),
              Expanded(child: ProgressBar(value: e.value / maxV, color: color)),
              const SizedBox(width: DsSpace.s),
              SizedBox(width: 36, child: Text('${e.value}', textAlign: TextAlign.end, style: DsType.label)),
            ],
          ),
        ),
    ];
  }
}

class _Tile {
  final Key key;
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String? extra;
  const _Tile(this.key, this.icon, this.color, this.value, this.label, {this.extra});
}
