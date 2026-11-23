import '../../core/strings.dart';
import 'auto_analyze_strings.dart';

/// Strings for the full-screen recording warning, its evidence card and the DEMO warning.
/// [ensure] also registers [AutoAnalyzeStrings] (and through it the call strings).
class RecordingWarningStrings {
  static bool _registered = false;

  static void ensure() {
    AutoAnalyzeStrings.ensure();
    if (_registered) return;
    _registered = true;
    S.register(_map);
  }

  static const Map<String, Map<String, String>> _map = {
    'en': {
      'warn_channel': 'Scam call warnings',
      'warn_title_high': 'SCAM CALL WARNING',
      'warn_title_medium': 'POSSIBLE SCAM CALL',
      'warn_subtitle': 'A call you recorded looks like fraud.',
      'warn_score': 'Scam score',
      'warn_type': 'Scam type',
      'warn_reasons': 'Warning words in the call',
      'warn_advice_high':
          'Do not share OTP, PIN or card details. Do not pay. Do not install any app they asked for. If you lost money, call 1930 now.',
      'warn_advice_medium': 'Be careful. Do not share OTP or PIN and do not pay until you have checked with your bank or family.',
      'warn_report': 'Report',
      'warn_dismiss': 'Dismiss',
      'warn_saved': 'Saved in Recording Alerts.',
      'warn_recording': 'Recording',
      'warn_time': 'Checked',
      'warn_demo_banner': 'DEMO – sample call, not a real recording',
      'rep_evidence_title': 'Evidence for this report',
      'rep_evidence_id': 'Alert ID',
      'rep_evidence_copy': 'Copy details',
      'rep_evidence_copied': 'Details copied. Paste them into your complaint.',
      'auto_demo': 'Show DEMO warning',
      'auto_demo_help':
          'DEMO: shows the full-screen warning for a built-in sample scam call. Nothing is added to your recordings folder or your alerts.',
      'auto_step_fsi': 'Allow full-screen warnings',
      'auto_step_fsi_help':
          'Android 14 and newer: lets a scam warning cover the screen, even when the phone is locked. Without it you still get a notification; tap it to open the warning.',
      'auto_diag_title': 'What the watcher saw (last 10 files)',
      'auto_diag_refresh': 'Refresh',
      'auto_diag_empty': 'No files seen yet.',
      'auto_diag_accepted': 'accepted',
      'auto_diag_rejected': 'not analysed',
      'auto_diag_last_error': 'Last error',
    },
    'hi': {
      'warn_channel': 'ठगी कॉल की चेतावनी',
      'warn_title_high': 'ठगी कॉल की चेतावनी',
      'warn_title_medium': 'शायद ठगी कॉल',
      'warn_subtitle': 'आपकी रिकॉर्ड की गई एक कॉल धोखाधड़ी जैसी लगती है।',
      'warn_score': 'ठगी स्कोर',
      'warn_type': 'ठगी का प्रकार',
      'warn_reasons': 'कॉल में खतरे वाले शब्द',
      'warn_advice_high':
          'OTP, PIN या कार्ड की जानकारी न दें। पैसे न भेजें। उनका बताया कोई ऐप इंस्टॉल न करें। पैसे गए हों तो अभी 1930 पर कॉल करें।',
      'warn_advice_medium': 'सावधान रहें। बैंक या परिवार से पूछे बिना OTP या PIN न दें और पैसे न भेजें।',
      'warn_report': 'शिकायत करें',
      'warn_dismiss': 'बंद करें',
      'warn_saved': 'रिकॉर्डिंग अलर्ट में सेव है।',
      'warn_recording': 'रिकॉर्डिंग',
      'warn_time': 'जांचा गया',
      'warn_demo_banner': 'डेमो – नमूना कॉल, असली रिकॉर्डिंग नहीं',
      'rep_evidence_title': 'इस शिकायत का सबूत',
      'rep_evidence_id': 'अलर्ट ID',
      'rep_evidence_copy': 'जानकारी कॉपी करें',
      'rep_evidence_copied': 'जानकारी कॉपी हो गई। इसे अपनी शिकायत में चिपकाएँ।',
      'auto_demo': 'डेमो चेतावनी दिखाएँ',
      'auto_demo_help':
          'डेमो: एक नमूना ठगी कॉल की पूरी स्क्रीन वाली चेतावनी दिखाता है। आपके रिकॉर्डिंग फ़ोल्डर या अलर्ट में कुछ नहीं जुड़ता।',
      'auto_step_fsi': 'पूरी स्क्रीन वाली चेतावनी की अनुमति दें',
      'auto_step_fsi_help':
          'Android 14 और नए फोन पर: ठगी की चेतावनी पूरी स्क्रीन पर दिख सके, फोन लॉक हो तब भी। इसके बिना भी सूचना आएगी; उसे छूकर चेतावनी खोलें।',
      'auto_diag_title': 'वॉचर ने क्या देखा (आखिरी 10 फ़ाइलें)',
      'auto_diag_refresh': 'ताज़ा करें',
      'auto_diag_empty': 'अभी कोई फ़ाइल नहीं दिखी।',
      'auto_diag_accepted': 'जांची गई',
      'auto_diag_rejected': 'नहीं जांची',
      'auto_diag_last_error': 'आखिरी गड़बड़ी',
    },
    'chh': {
      'warn_channel': 'ठगी कॉल के चेतावनी',
      'warn_title_high': 'ठगी कॉल के चेतावनी',
      'warn_title_medium': 'सायद ठगी कॉल',
      'warn_subtitle': 'तोर रिकॉर्ड करे एक कॉल धोखाधड़ी कस लागथे।',
      'warn_score': 'ठगी स्कोर',
      'warn_type': 'ठगी के किसम',
      'warn_reasons': 'कॉल म खतरा वाले सब्द',
      'warn_advice_high':
          'OTP, PIN या कार्ड के जानकारी झन दे। पइसा झन भेज। ओमन के बताय कोनो ऐप इंस्टॉल झन कर। पइसा गे हे त अभी 1930 म कॉल कर।',
      'warn_advice_medium': 'सावधान रह। बैंक या परिवार ले पूछे बिना OTP या PIN झन दे अउ पइसा झन भेज।',
      'warn_report': 'सिकायत करव',
      'warn_dismiss': 'बंद करव',
      'warn_saved': 'रिकॉर्डिंग अलर्ट म सेव हे।',
      'warn_recording': 'रिकॉर्डिंग',
      'warn_time': 'जांचे गिस',
      'warn_demo_banner': 'डेमो – नमूना कॉल, असली रिकॉर्डिंग नोहय',
      'rep_evidence_title': 'ए सिकायत के सबूत',
      'rep_evidence_id': 'अलर्ट ID',
      'rep_evidence_copy': 'जानकारी कॉपी करव',
      'rep_evidence_copied': 'जानकारी कॉपी होगे। एला अपन सिकायत म चिपकाव।',
      'auto_demo': 'डेमो चेतावनी देखाव',
      'auto_demo_help':
          'डेमो: एक नमूना ठगी कॉल के पूरा स्क्रीन वाले चेतावनी देखाथे। तोर रिकॉर्डिंग फोल्डर या अलर्ट म कुछु नइ जुड़य।',
      'auto_step_fsi': 'पूरा स्क्रीन वाले चेतावनी के अनुमति दव',
      'auto_step_fsi_help':
          'Android 14 अउ नवा फोन म: ठगी के चेतावनी पूरा स्क्रीन म दिखे, फोन लॉक होय तभो। एकर बिना घलो सूचना आही; ओला छूके चेतावनी खोलव।',
      'auto_diag_title': 'वॉचर ह का देखिस (आखिरी 10 फाइल)',
      'auto_diag_refresh': 'ताजा करव',
      'auto_diag_empty': 'अभी कोनो फाइल नइ दिखिस।',
      'auto_diag_accepted': 'जांचे गिस',
      'auto_diag_rejected': 'नइ जांचे गिस',
      'auto_diag_last_error': 'आखिरी गड़बड़ी',
    },
  };
}
