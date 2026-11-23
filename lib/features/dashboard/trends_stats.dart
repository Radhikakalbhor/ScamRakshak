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
