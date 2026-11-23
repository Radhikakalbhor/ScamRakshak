import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(s.t('trends_clear_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('trends_cancel'))),
          FilledButton(
            key: const Key('trends_clear_ok'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.t('trends_delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(detectionHistoryProvider).clear();
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('trends_cleared'))));
  }

  Future<void> _loadServer() async {
    setState(() => _server = _ServerState.loading);
    try {
      final rows = await ref.read(apiClientProvider).getTrends();
      if (!mounted) return;
      setState(() {
        _serverData = ServerTrends.fromRows(rows);
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.t('trends_load_error'), style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _reload, child: Text(s.t('trends_retry'))),
          ],
        ),
      );
    }
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    final records = snap.data!;
    final stats = TrendStats.from(records, now: widget.clock(), includePractice: _includePractice);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Icon(Icons.phone_android_rounded, color: AppTheme.primaryTeal),
            const SizedBox(width: 8),
            Expanded(child: Text(s.t('trends_local_title'), style: Theme.of(context).textTheme.headlineSmall)),
          ],
        ),
        const SizedBox(height: 4),
        Text(s.t('trends_local_note'), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 12),
        if (stats.practiceExcluded > 0 || _includePractice) _practiceToggle(s, stats),
        if (stats.isEmpty) _empty(s) else ..._localStats(s, stats),
        const SizedBox(height: 20),
        _serverSection(s),
      ],
    );
  }

  Widget _practiceToggle(S s, TrendStats stats) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    color: AppTheme.secondaryLightBlue,
    child: Column(
      children: [
        if (stats.practiceExcluded > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.school_rounded, color: AppTheme.secondaryNavy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${stats.practiceExcluded} ${s.t('trends_practice_note')}',
                    key: const Key('trends_practice_note'),
                  ),
                ),
              ],
            ),
          ),
        SwitchListTile(
          key: const Key('trends_include_practice'),
          title: Text(s.t('trends_include_practice')),
          value: _includePractice,
          onChanged: (v) => setState(() => _includePractice = v),
        ),
      ],
    ),
  );

  Widget _empty(S s) => Card(
    key: const Key('trends_empty'),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.insights_rounded, size: 64, color: AppTheme.primaryTeal),
          const SizedBox(height: 8),
          Text(s.t('trends_empty_title'), style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(s.t('trends_empty_body'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('trends_go_message'),
            onPressed: () => _push('/message', () => const MessageDetectorScreen()),
            icon: const Icon(Icons.mark_chat_unread_rounded),
            label: Text(s.t('trends_check_message')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('trends_go_call'),
            onPressed: () => _push('/call', () => const CallDetectorScreen()),
            icon: const Icon(Icons.phone_in_talk_rounded),
            label: Text(s.t('trends_check_call')),
          ),
        ],
      ),
    ),
  );

  List<Widget> _localStats(S s, TrendStats st) => [
    _tiles(s, st),
    const SizedBox(height: 12),
    _chartCard(s, st),
    const SizedBox(height: 12),
    _categoriesCard(s, st),
    const SizedBox(height: 12),
    _recentCard(s, st),
  ];

  Widget _tiles(S s, TrendStats st) {
    final risky = st.scams + st.suspicious;
    final tiles = [
      _Tile(
        const Key('trends_tile_messages'),
        Icons.sms_rounded,
        AppTheme.primaryTeal,
        '${st.messages}',
        s.t('trends_messages'),
      ),
      _Tile(
        const Key('trends_tile_calls'),
        Icons.call_rounded,
        AppTheme.secondaryNavy,
        '${st.calls}',
        s.t('trends_calls'),
      ),
      _Tile(
        const Key('trends_tile_scams'),
        Icons.gpp_bad_rounded,
        AppTheme.errorRed,
        '$risky',
        s.t('trends_scams'),
        extra: st.suspicious > 0 ? '${st.scams} + ${st.suspicious} ${s.t('trends_suspicious_n')}' : null,
      ),
      _Tile(
        const Key('trends_tile_safe'),
        Icons.verified_user_rounded,
        AppTheme.successGreen,
        '${st.safe}',
        s.t('trends_safe'),
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 600 ? 4 : 2;
        const gap = 10.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: w, child: _tile(t))],
        );
      },
    );
  }

  Widget _tile(_Tile t) => Container(
    key: t.key,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: t.color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: t.color.withValues(alpha: 0.35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(t.icon, color: t.color),
        const SizedBox(height: 6),
        Text(
          t.value,
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: t.color),
        ),
        Text(t.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        if (t.extra != null) Text(t.extra!, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ],
    ),
  );

  Widget _card({Key? key, required String title, required IconData icon, required Widget child}) => Card(
    key: key,
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primaryTeal),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );

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
                gridData: FlGridData(drawVerticalLine: false, horizontalInterval: step),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: step,
                      getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 11)),
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
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('${d.day}/${d.month}', style: const TextStyle(fontSize: 11)),
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
                          borderRadius: BorderRadius.circular(4),
                          rodStackItems: [
                            BarChartRodStackItem(0, st.daily[i].risky.toDouble(), AppTheme.errorRed),
                            BarChartRodStackItem(
                              st.daily[i].risky.toDouble(),
                              st.daily[i].total.toDouble(),
                              AppTheme.successGreen,
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: [
              _legend(AppTheme.errorRed, s.t('trends_legend_risky')),
              _legend(AppTheme.successGreen, s.t('trends_legend_safe')),
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
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 6),
      Flexible(child: Text(label, style: const TextStyle(fontSize: 13))),
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
          ? Text(s.t('trends_no_scams'), style: const TextStyle(fontSize: 16))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  key: const Key('trends_top_category'),
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.local_fire_department_rounded, color: AppTheme.errorRed),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${s.t('trends_most_common')}: ${categoryLabel(s, top!)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final e in st.categories)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 130,
                          child: Text(categoryLabel(s, e.key), style: const TextStyle(fontSize: 14)),
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: e.value / maxCount,
                            minHeight: 12,
                            borderRadius: BorderRadius.circular(6),
                            color: AppTheme.errorRed,
                            backgroundColor: const Color(0xFFFFEBEE),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${e.value}',
                            key: Key('trends_cat_count_${e.key}'),
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (lesson != null)
                  OutlinedButton.icon(
                    key: const Key('trends_learn'),
                    onPressed: () =>
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => LessonDetailScreen(lessonId: lesson))),
                    icon: const Icon(Icons.school_rounded),
                    label: Text(s.t('trends_learn')),
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
    child: Column(children: [for (final r in st.recent) _recentRow(s, r)]),
  );

  Widget _recentRow(S s, DetectionRecord r) {
    final color = switch (r.verdict) {
      'scam' => AppTheme.errorRed,
      'suspicious' => AppTheme.warningOrange,
      _ => AppTheme.successGreen,
    };
    final title = r.isRisky ? categoryLabel(s, r.category.isEmpty ? 'other' : r.category) : s.t('trends_verdict_safe');
    final sub = [
      s.t('trends_kind_${r.kind}'),
      if (r.score != null) '${(r.score! * 100).round()}%',
      _when(s, r.time),
      if (r.sample) s.t('trends_practice_tag'),
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(r.kind == 'call' ? Icons.call_rounded : Icons.sms_rounded, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(sub),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Text(
          s.t('trends_verdict_${r.verdict}'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ server

  Widget _serverSection(S s) => _card(
    key: const Key('trends_server'),
    title: s.t('trends_server_title'),
    icon: Icons.cloud_rounded,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.t('trends_server_note'), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 12),
        ..._serverBody(s),
      ],
    ),
  );

  List<Widget> _serverBody(S s) {
    Widget loadButton() => OutlinedButton.icon(
      key: const Key('trends_server_load'),
      onPressed: _loadServer,
      icon: const Icon(Icons.cloud_download_rounded),
      label: Text(s.t('trends_server_load')),
    );
    Widget message(String key, IconData icon, Color color) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        key: Key('trends_server_$key'),
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(s.t('trends_server_$key'))),
        ],
      ),
    );
    switch (_server) {
      case _ServerState.idle:
        return [loadButton()];
      case _ServerState.loading:
        return [
          Row(
            children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(child: Text(s.t('trends_server_loading'))),
            ],
          ),
        ];
      case _ServerState.offline:
        return [message('offline', Icons.wifi_off_rounded, AppTheme.warningOrange), loadButton()];
      case _ServerState.error:
        return [message('error', Icons.error_outline_rounded, AppTheme.errorRed), loadButton()];
      case _ServerState.data:
        final d = _serverData!;
        if (d.total == 0) return [message('empty', Icons.inbox_rounded, AppTheme.textSecondary)];
        return [
          Text(
            '${d.total} ${s.t('trends_server_total')}',
            key: const Key('trends_server_total'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(s.t('trends_server_districts'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ..._bars(d.byDistrict.take(5).toList(), (k) => k, AppTheme.secondaryNavy),
          const SizedBox(height: 10),
          Text(s.t('trends_server_types'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ..._bars(d.byType, (k) => s.t('report_type_$k'), AppTheme.warningOrange),
        ];
    }
  }

  List<Widget> _bars(List<MapEntry<String, int>> rows, String Function(String) label, Color color) {
    final maxV = rows.isEmpty ? 1 : rows.first.value;
    return [
      for (final e in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(width: 120, child: Text(label(e.key), overflow: TextOverflow.ellipsis)),
              Expanded(
                child: LinearProgressIndicator(
                  value: e.value / maxV,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(5),
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.12),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 36, child: Text('${e.value}', textAlign: TextAlign.end)),
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
