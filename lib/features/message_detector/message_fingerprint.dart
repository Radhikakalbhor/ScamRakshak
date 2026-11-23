import 'package:shared_preferences/shared_preferences.dart';

/// Anonymous 64-bit SimHash of a message for spotting many people receiving the same new scam.
///
/// Digits become 0 and links become "url", so the same scam with different numbers or links gets
/// (nearly) the same fingerprint. Word 3-grams are hashed with FNV-1a and combined bit by bit; the message
/// text cannot be read back from the 16 hex digits.
String messageFingerprint(String text) {
  final norm = text
      .toLowerCase()
      .replaceAll(RegExp(r'(https?://|www\.)\S+|\S+\.(com|in|xyz|online|co|net|org)(/\S*)?'), ' url ')
      .replaceAll(RegExp(r'[0-9०-९]'), '0');
  final words = RegExp(r'[a-z0]+|[ऀ-ॣ०-ॿ]+').allMatches(norm).map((m) => m.group(0)!).toList();
  final shingles = <String>[
    if (words.isNotEmpty && words.length < 3) words.join(' '),
    for (var i = 0; i + 3 <= words.length; i++) words.sublist(i, i + 3).join(' '),
  ];
  final weights = List<int>.filled(64, 0);
  for (final sh in shingles) {
    final h = _fnv64(sh);
    for (var b = 0; b < 64; b++) {
      weights[b] += ((h >> b) & 1) == 1 ? 1 : -1;
    }
  }
  var fp = 0;
  for (var b = 0; b < 64; b++) {
    if (weights[b] > 0) fp |= 1 << b;
  }
  // Native ints are signed 64-bit; BigInt prints the same bits as unsigned hex.
  return BigInt.from(fp).toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

int _fnv64(String s) {
  var h = 0xcbf29ce484222325;
  for (final c in s.codeUnits) {
    h ^= c;
    h *= 0x100000001b3;
  }
  return h;
}

/// Number of differing bits between two fingerprints.
int fingerprintDistance(String a, String b) {
  var x = (BigInt.parse(a, radix: 16) ^ BigInt.parse(b, radix: 16));
  var n = 0;
  while (x > BigInt.zero) {
    n += (x & BigInt.one).toInt();
    x >>= 1;
  }
  return n;
}

/// Opt-in setting (off by default). When on, a scam verdict sends only the fingerprint and category.
class FingerprintOptIn {
  static const key = 'msg_fingerprint_optin_v1';

  static Future<bool> get() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> set(bool v) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(key, v);
    } catch (_) {}
  }
}
