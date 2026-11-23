import 'detection_history.dart';

/// Checks on one calendar day.
class DayCount {
  final DateTime day;
  final int risky;
  final int safe;
  const DayCount(this.day, this.risky, this.safe);
  int get total => risky + safe;
}

/// Statistics shown on the Scam Trends screen, computed from [DetectionRecord]s.
class TrendStats {
  final int messages;
  final int calls;
  final int scams;
  final int suspicious;
  final int safe;

  /// Practice checks (built-in samples) that were left out.
  final int practiceExcluded;

  /// Scam categories (scam + suspicious results), most frequent first.
  final List<MapEntry<String, int>> categories;

  /// Last [days] days, oldest first, including today.
  final List<DayCount> daily;

  /// Newest first.
  final List<DetectionRecord> recent;

  const TrendStats({
    required this.messages,
    required this.calls,
    required this.scams,
    required this.suspicious,
    required this.safe,
    required this.practiceExcluded,
    required this.categories,
    required this.daily,
    required this.recent,
  });

  int get total => messages + calls;
  bool get isEmpty => total == 0;
  String? get topCategory => categories.isEmpty ? null : categories.first.key;

  factory TrendStats.from(
    List<DetectionRecord> records, {
    DateTime? now,
    bool includePractice = false,
    int days = 7,
    int recentLimit = 10,
  }) {
    final used = includePractice ? records : records.where((r) => !r.sample).toList();
    final excluded = records.length - used.length;
    final sorted = List.of(used)..sort((a, b) => b.time.compareTo(a.time));

    var messages = 0, calls = 0, scams = 0, suspicious = 0, safe = 0;
    final cats = <String, int>{};
    for (final r in sorted) {
      r.kind == 'call' ? calls++ : messages++;
      switch (r.verdict) {
        case 'scam':
          scams++;
        case 'suspicious':
          suspicious++;
        default:
          safe++;
      }
      if (r.isRisky) {
        final c = r.category.isEmpty ? 'other' : r.category;
        cats[c] = (cats[c] ?? 0) + 1;
      }
    }
    final categories = cats.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });

    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final daily = <DayCount>[];
    for (var i = days - 1; i >= 0; i--) {
      final d = DateTime(today.year, today.month, today.day - i);
      var risky = 0, ok = 0;
      for (final r in sorted) {
        final t = r.time.toLocal();
        if (t.year == d.year && t.month == d.month && t.day == d.day) {
          r.isRisky ? risky++ : ok++;
        }
      }
      daily.add(DayCount(d, risky, ok));
    }

    return TrendStats(
      messages: messages,
      calls: calls,
      scams: scams,
      suspicious: suspicious,
      safe: safe,
      practiceExcluded: excluded,
      categories: categories,
      daily: daily,
      recent: sorted.take(recentLimit).toList(),
    );
  }
}

/// One week of the server trend; [count] is null when it was suppressed (fewer than min_count).
class WeekCount {
  final DateTime weekStart;
  final int? count;
  const WeekCount(this.weekStart, this.count);
}

/// Aggregates of one data source from GET /trends/summary.
class SourceTrends {
  final int total;
  final List<MapEntry<String, int>> byDistrict;
  final List<MapEntry<String, int>> byType;
  final List<WeekCount> weekly;
  final int suppressed;
  const SourceTrends(this.total, this.byDistrict, this.byType, this.weekly, this.suppressed);

  static List<MapEntry<String, int>> _pairs(Object? list, String key) => [
        if (list is List)
          for (final e in list.whereType<Map>())
            if (e[key] != null && e['count'] is num) MapEntry(e[key].toString(), (e['count'] as num).toInt()),
      ];

  factory SourceTrends.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    final weekly = <WeekCount>[];
    final w = m['weekly'];
    if (w is List) {
      for (final e in w.whereType<Map>()) {
        final d = DateTime.tryParse('${e['week_start']}');
        if (d != null) weekly.add(WeekCount(d, (e['count'] as num?)?.toInt()));
      }
    }
    return SourceTrends(
      (m['total'] as num?)?.toInt() ?? 0,
      _pairs(m['by_district'], 'district'),
      _pairs(m['by_type'], 'type'),
      weekly,
      (m['suppressed_cells'] as num?)?.toInt() ?? 0,
    );
  }
}

/// GET /trends/summary: synthetic demo data and live reports, kept apart.
class ServerSummary {
  final int minCount;
  final SourceTrends live;
  final SourceTrends synthetic;
  const ServerSummary(this.minCount, this.live, this.synthetic);

  factory ServerSummary.fromJson(Map j) => ServerSummary(
        (j['min_count'] as num?)?.toInt() ?? 5,
        SourceTrends.fromJson(j['live']),
        SourceTrends.fromJson(j['synthetic']),
      );
}

/// One emerging-scam alert from GET /alerts.
class EmergingAlert {
  /// 'spike' (district/type rise against the trailing baseline) or 'cluster' (many near-identical messages).
  final String kind;
  final String district;
  final String type;
  final String category;
  final int count;
  final double baseline;
  const EmergingAlert(this.kind, this.district, this.type, this.category, this.count, this.baseline);

  static EmergingAlert? tryFrom(Map j) {
    final kind = j['kind'];
    if (kind == 'spike') {
      return EmergingAlert('spike', '${j['district']}', '${j['type']}', '', (j['recent'] as num?)?.toInt() ?? 0,
          (j['baseline_weekly'] as num?)?.toDouble() ?? 0);
    }
    if (kind == 'cluster') {
      return EmergingAlert('cluster', '', '', '${j['category']}', (j['size'] as num?)?.toInt() ?? 0, 0);
    }
    return null;
  }
}

/// Server report totals from GET /trends rows ({district, type, count}).
class ServerTrends {
  final List<MapEntry<String, int>> byDistrict;
  final List<MapEntry<String, int>> byType;
  final int total;
  const ServerTrends(this.byDistrict, this.byType, this.total);

  factory ServerTrends.fromRows(List<Map> rows) {
    final d = <String, int>{}, t = <String, int>{};
    var total = 0;
    for (final r in rows) {
      final c = (r['count'] as num?)?.toInt() ?? 0;
      if (c <= 0) continue;
      final district = (r['district'] ?? '').toString().trim();
      final type = (r['type'] ?? '').toString().trim();
      if (district.isNotEmpty) d[district] = (d[district] ?? 0) + c;
      if (type.isNotEmpty) t[type] = (t[type] ?? 0) + c;
      total += c;
    }
    List<MapEntry<String, int>> sorted(Map<String, int> m) => m.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return ServerTrends(sorted(d), sorted(t), total);
  }
}
