/// Offline checker for UPI QR codes (`upi://pay?pa=...&pn=...`).
library;

/// Risk ids; label keys are `qr_risk_{id}` and `qr_risk_{id}_sub`.
const kDangerRisks = {'not_upi_link', 'bad_pa', 'receive_words', 'collect_link'};
const kCautionRisks = {'not_upi', 'no_pn', 'name_mismatch', 'amount_set', 'unknown_handle', 'not_inr'};

/// UPI handles (the part after @) of well-known banks and payment apps.
const kKnownUpiHandles = {
  'okaxis', 'okhdfcbank', 'okicici', 'oksbi', 'ybl', 'ibl', 'axl', 'paytm', 'ptsbi', 'pthdfc', 'ptaxis', 'ptyes',
  'upi', 'apl', 'yapl', 'rapl', 'ikwik', 'freecharge', 'airtel', 'jio', 'fbpe', 'axisbank', 'axisb', 'sbi',
  'icici', 'hdfcbank', 'hdfcbankjd', 'kotak', 'kmbl', 'pnb', 'barodampay', 'unionbank', 'uboi', 'cnrb', 'idfcbank',
  'idfcfirst', 'indus', 'yesbank', 'yesbankltd', 'waaxis', 'wahdfcbank', 'waicici', 'wasbi', 'abfspay',
  'jupiteraxis', 'superyes', 'slice', 'naviaxis', 'postbank', 'aubank', 'federal', 'fbl', 'kbl', 'rbl', 'dbs',
  'hsbc', 'sc', 'citi', 'idbi', 'mahb', 'cbin', 'iob', 'psb', 'ucobank', 'equitas', 'aubankltd', 'dlb', 'kvb',
  'tjsb', 'cboi', 'boi', 'allbank', 'andb', 'denabank', 'vijb', 'syndicate', 'obc', 'centralbank', 'indianbk',
  'airtelpaymentsbank', 'mairtel', 'payzapp', 'pockets', 'timecosmos', 'icicipay', 'hdfcbankmerchant',
  'okbizaxis', 'okbizicici', 'ezeepay', 'pingpay', 'amazonpay', 'apay', 'yescred', 'goaxb', 'tapicici',
};

/// Words that promise money to the person scanning (scanning a QR only ever pays).
final RegExp _receiveWords = RegExp(
  r'refund|cash\s*back|cashback|prize|reward|receive|recieve|lottery|winner|won\b|gift|lucky|kyc|bonus|claim|'
  r'रिफंड|कैशबैक|इनाम|पुरस्कार|प्राप्त|लॉटरी|जीत|बोनस|उपहार',
  caseSensitive: false,
);

final RegExp _vpa = RegExp(r'^[a-z0-9._\-]{2,256}@[a-z][a-z0-9.\-]{1,64}$');

class UpiQrResult {
  /// The text that was checked.
  final String raw;

  /// True when it is a `upi://pay` link.
  final bool isUpi;

  /// Payee UPI ID and name, amount, note and currency (null when absent).
  final String? pa, pn, am, tn, cu;

  /// Risk ids, most serious first (see [kDangerRisks] / [kCautionRisks]).
  final List<String> risks;

  const UpiQrResult(this.raw, this.isUpi, this.pa, this.pn, this.am, this.tn, this.cu, this.risks);

  /// 'danger' | 'caution' | 'ok'
  String get level => risks.any(kDangerRisks.contains)
      ? 'danger'
      : risks.isEmpty
          ? 'ok'
          : 'caution';

  String? get handle => pa != null && pa!.contains('@') ? pa!.split('@').last : null;
}

Map<String, String> _query(Uri u) {
  // Keys are case-insensitive in practice (some generators write PA= / PN=).
  final out = <String, String>{};
  u.queryParameters.forEach((k, v) => out[k.toLowerCase()] = v.trim());
  return out;
}

/// Letters-only lowercase tokens of a payee name, ignoring titles and very short parts.
Iterable<String> _nameTokens(String pn) => pn
    .toLowerCase()
    .split(RegExp(r'[^a-z]+'))
    .where((t) => t.length >= 3 && !const {'shri', 'smt', 'mrs', 'the', 'and', 'store', 'stores', 'shop'}.contains(t));

/// True when the payee name has no visible link to the UPI ID's name part. Only for personal-looking IDs:
/// a phone number or a long merchant code is not compared.
bool _nameMismatch(String pa, String pn) {
  final local = pa.split('@').first.toLowerCase();
  final letters = local.replaceAll(RegExp(r'[^a-z]'), '');
  if (letters.length < 3 || RegExp(r'\d{6,}').hasMatch(local)) return false;
  final tokens = _nameTokens(pn).toList();
  if (tokens.isEmpty) return false; // name in another script: cannot compare
  return !tokens.any((t) => letters.contains(t.substring(0, t.length < 4 ? t.length : 4)));
}

/// Parses and checks one scanned or pasted QR payload.
UpiQrResult checkUpiQr(String input) {
  final raw = input.trim();
  final risks = <String>[];
  // Many QR generators leave spaces unencoded in pn/tn.
  final uri = Uri.tryParse(raw.replaceAll(' ', '%20'));
  final scheme = uri?.scheme.toLowerCase() ?? '';
  if (uri == null || scheme != 'upi') {
    if (scheme == 'http' || scheme == 'https') {
      risks.add('not_upi_link');
    } else {
      risks.add('not_upi');
    }
    return UpiQrResult(raw, false, null, null, null, null, null, risks);
  }
  final q = _query(uri);
  final pa = q['pa']?.toLowerCase();
  final pn = q['pn'];
  final am = q['am'];
  final tn = q['tn'];
  final cu = q['cu'];

  // upi://collect asks YOU to approve a payment request.
  if (uri.host.toLowerCase() == 'collect') risks.add('collect_link');
  if (pa == null || !_vpa.hasMatch(pa)) risks.add('bad_pa');
  final text = '${pn ?? ''} ${tn ?? ''}';
  if (_receiveWords.hasMatch(text)) risks.add('receive_words');
  if (pn == null || pn.isEmpty) {
    risks.add('no_pn');
  } else if (pa != null && _vpa.hasMatch(pa) && _nameMismatch(pa, pn)) {
    risks.add('name_mismatch');
  }
  final amount = double.tryParse(am ?? '');
  if (amount != null && amount > 0) risks.add('amount_set');
  if (pa != null && _vpa.hasMatch(pa) && !kKnownUpiHandles.contains(pa.split('@').last)) risks.add('unknown_handle');
  if (cu != null && cu.isNotEmpty && cu.toUpperCase() != 'INR') risks.add('not_inr');

  risks.sort((a, b) => (kDangerRisks.contains(a) ? 0 : 1).compareTo(kDangerRisks.contains(b) ? 0 : 1));
  return UpiQrResult(raw, true, pa, pn, am, tn, cu, risks);
}
