import 'package:shared_preferences/shared_preferences.dart';

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
