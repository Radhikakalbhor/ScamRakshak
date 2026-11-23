import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';

/// Report types accepted by POST /reports (AGENTS.md contract).
const List<String> kReportTypes = ['otp', 'fake_qr', 'loan_app', 'call', 'other'];

/// The 33 districts of Chhattisgarh (sent to the backend as-is).
const List<String> kChhattisgarhDistricts = [
  'Balod', 'Baloda Bazar', 'Balrampur', 'Bastar', 'Bemetara', 'Bijapur', 'Bilaspur',
  'Dantewada', 'Dhamtari', 'Durg', 'Gariaband', 'Gaurela-Pendra-Marwahi', 'Janjgir-Champa',
  'Jashpur', 'Kabirdham', 'Kanker', 'Khairagarh-Chhuikhadan-Gandai', 'Kondagaon', 'Korba',
  'Korea', 'Mahasamund', 'Manendragarh-Chirmiri-Bharatpur', 'Mohla-Manpur-Ambagarh Chowki',
  'Mungeli', 'Narayanpur', 'Raigarh', 'Raipur', 'Rajnandgaon', 'Sakti', 'Sarangarh-Bilaigarh',
  'Sukma', 'Surajpur', 'Surguja',
];

/// Evidence checklist item ids; label key is `evidence_{id}`.
const List<String> kEvidenceItems = [
  'screenshots', 'phone_number', 'transaction_id', 'date_time', 'bank_statement', 'call_recording',
];

final Uri kHelpline1930 = Uri.parse('tel:1930');
final Uri kCybercrimePortal = Uri.parse('https://cybercrime.gov.in');
final Uri kChakshuPortal = Uri.parse('https://sancharsaathi.gov.in/sfc/');

/// "I lost money" (1930, bank, cybercrime.gov.in, evidence) or "suspicious, no loss" (Chakshu).
const List<String> kReportSituations = ['lost', 'suspicious'];

/// One anonymous report count: only type, district and time (no text, number or name).
class QueuedReport {
  final String type;
  final String district;
  final String ts;
  const QueuedReport(this.type, this.district, this.ts);

  Map<String, String> toJson() => {'type': type, 'district': district, 'ts': ts};

  static QueuedReport? tryFrom(Object? j) {
    if (j is! Map) return null;
    final type = j['type'], district = j['district'], ts = j['ts'];
    if (type is! String || district is! String || ts is! String || !kReportTypes.contains(type)) return null;
    return QueuedReport(type, district, ts);
  }
}

/// Persistent queue of anonymous report counts for POST /reports. Survives restarts and is retried
/// when the backend is reachable again ([flush]).
class ReportQueue {
  static const key = 'report_queue_v1';
  static const maxItems = 200;

  static Future<List<QueuedReport>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).map(QueuedReport.tryFrom).whereType<QueuedReport>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<QueuedReport> items) async {
    final p = await SharedPreferences.getInstance();
    final kept = items.length > maxItems ? items.sublist(items.length - maxItems) : items;
    await p.setString(key, jsonEncode(kept.map((e) => e.toJson()).toList()));
  }

  static Future<void> add(String type, String district, {DateTime? now}) async {
    final items = await load();
    items.add(QueuedReport(type, district, (now ?? DateTime.now()).toUtc().toIso8601String()));
    await _save(items);
  }

  /// Sends queued reports in order. Stops at the first network failure (kept for later);
  /// drops reports the server rejects as invalid (4xx). Returns how many are still waiting.
  static Future<int> flush(ApiClient api) async {
    final items = await load();
    var sent = 0;
    for (final r in items) {
      try {
        await api.postReportAt(r.type, r.district, r.ts);
        sent++;
      } on ApiException catch (e) {
        if (e.statusCode >= 500) break;
        sent++; // invalid: never retry
      } catch (_) {
        break; // offline / timeout
      }
    }
    // Re-read: reports may have been queued while sending (new ones are appended at the end).
    final now = await load();
    final left = now.length >= sent ? now.sublist(sent) : <QueuedReport>[];
    if (sent > 0) await _save(left);
    return left.length;
  }
}

/// Persistent evidence checklist (shared_preferences).
class EvidenceStore {
  static String key(String id) => 'report_evidence_$id';

  static Future<Set<String>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return kEvidenceItems.where((id) => p.getBool(key(id)) ?? false).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> set(String id, bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key(id), value);
    } catch (_) {}
  }
}
