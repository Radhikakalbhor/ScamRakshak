import 'package:flutter/material.dart';

/// ScamRakshak localization class S.
/// Supports English ('en'), Hindi ('hi'), and Chhattisgarhi ('chh').
/// Features can register additional localized strings using [S.register].
class S {
  final String locale;
  const S(this.locale);

  static const String defaultLocale = 'en';
  static const List<String> supportedLanguages = ['en', 'hi', 'chh'];

  // Global translation registry: language -> key -> value
  static final Map<String, Map<String, String>> _registry = {
    'en': {
      'app_name': 'ScamRakshak',
      'app_tagline': 'Your Guardian Against Digital Fraud',
      'offline_badge': 'Offline Protected',
      'select_language': 'Language / भाषा',

      // Home Navigation Tiles
      'check_message': 'Check Message',
      'check_message_sub': 'Detect SMS & WhatsApp fraud',
      'check_call': 'Check Call',
      'check_call_sub': 'Analyze suspicious call transcripts',
      'live_call': 'Live Call Guard',
      'live_call_sub': 'Microphone + speakerphone; may not work on all phones',
      'report_fraud': 'Report Fraud',
      'report_fraud_sub': 'Register incident & alert community',
      'learn': 'Learn',
      'learn_sub': 'Digital payment safety cards',
      'quiz': 'Quiz',
      'quiz_sub': 'Test your fraud defense skills',
      'scam_trends': 'Scam Trends',
      'scam_trends_sub': 'District-level cybercrime data',

      // Common Buttons & Actions
      'btn_back': 'Back',
      'btn_continue': 'Continue',
      'btn_submit': 'Submit',
      'btn_cancel': 'Cancel',
      'btn_retry': 'Retry',
      'btn_settings': 'Settings',
      'btn_home': 'Home',

      // Placeholders & Status
      'placeholder_title': 'Coming Soon',
      'placeholder_body': 'This feature module is being connected by the team.',
    },
    'hi': {
      'app_name': 'स्कैम रक्षक',
      'app_tagline': 'डिजिटल धोखाधड़ी से आपकी सुरक्षा',
      'offline_badge': 'बिना इंटरनेट सुरक्षित',
      'select_language': 'भाषा चुनें',

      // Home Navigation Tiles
      'check_message': 'संदेश जांचें',
      'check_message_sub': 'संदेश में धोखाधड़ी की पहचान करें',
      'check_call': 'कॉल जांचें',
      'check_call_sub': 'संदेहास्पद कॉल की बातचीत परखें',
      'live_call': 'लाइव कॉल रक्षक',
      'live_call_sub': 'माइक + स्पीकरफ़ोन से; हर फोन पर काम न करे',
      'report_fraud': 'धोखाधड़ी की शिकायत',
      'report_fraud_sub': 'ठगी की रपट दर्ज करें व सजग रहें',
      'learn': 'सुरक्षा सीखें',
      'learn_sub': 'आसान डिजिटल सुरक्षा पाठ',
      'quiz': 'प्रश्नोत्तरी',
      'quiz_sub': 'अपनी सुरक्षा समझ परखें',
      'scam_trends': 'ठगी के रुझान',
      'scam_trends_sub': 'जिलेवार साइबर अपराध के आंकड़े',

      // Common Buttons & Actions
      'btn_back': 'पीछे जाएं',
      'btn_continue': 'आगे बढ़ें',
      'btn_submit': 'जमा करें',
      'btn_cancel': 'रद्द करें',
      'btn_retry': 'पुनः प्रयास करें',
      'btn_settings': 'सेटिंग्स',
      'btn_home': 'मुख्य पृष्ठ',

      // Placeholders & Status
      'placeholder_title': 'शीघ्र उपलब्ध होगा',
      'placeholder_body': 'यह मॉड्यूल टीम द्वारा जोड़ा जा रहा है।',
    },
    'chh': {
      'app_name': 'स्कैम रक्षक',
      'app_tagline': 'डिजिटल ठगी ले आपमन के रक्षा',
      'offline_badge': 'बिना इंटरनेट चलहि',
      'select_language': 'भाखा चुनव',

      // Home Navigation Tiles
      'check_message': 'संदेश जांचव',
      'check_message_sub': 'संदेश म ठगी के पहचान करव',
      'check_call': 'कॉल जांचव',
      'check_call_sub': 'संदेहास्पद फोन गोठ-बात परखव',
      'live_call': 'लाइव कॉल रक्षक',
      'live_call_sub': 'माइक + स्पीकरफोन ले; हर फोन म नइ चल सकय',
      'report_fraud': 'ठगी के रपट',
      'report_fraud_sub': 'ठगी के रपट लिखवावव अउ बांचव',
      'learn': 'सुरक्षा सिखव',
      'learn_sub': 'सुरक्षित लेन-देन के आसान सीख',
      'quiz': 'सवाल-जवाब',
      'quiz_sub': 'अपन सुरक्षा समझ परखव',
      'scam_trends': 'ठगी के चाल-चलन',
      'scam_trends_sub': 'जिला अनुसार ठगी के ताजा हाल',

      // Common Buttons & Actions
      'btn_back': 'पाछू जाव',
      'btn_continue': 'आगे बढ़व',
      'btn_submit': 'जमा करव',
      'btn_cancel': 'रद्द करव',
      'btn_retry': 'फिर कोशिश करव',
      'btn_settings': 'सेटिंग्स',
      'btn_home': 'घर (मुख्य)',

      // Placeholders & Status
      'placeholder_title': 'जल्दी आही',
      'placeholder_body': 'ए मॉड्यूल म काम चालू हे, जल्दी जुड़ही।',
    },
  };

  /// Registers additional feature localization maps into the shared registry.
  /// Accepts either:
  /// - { 'en': { 'key': 'val' }, 'hi': { ... }, 'chh': { ... } }
  /// - or { 'key': { 'en': 'val', 'hi': 'val', 'chh': 'val' } }
  static void register(Map<dynamic, dynamic> map) {
    map.forEach((key, value) {
      if (value is Map) {
        final keyStr = key.toString();
        if (supportedLanguages.contains(keyStr)) {
          // Format: lang -> { key: val }
          final target = _registry.putIfAbsent(keyStr, () => <String, String>{});
          value.forEach((k, v) {
            target[k.toString()] = v.toString();
          });
        } else {
          // Format: key -> { lang: val }
          value.forEach((lang, v) {
            final langStr = lang.toString();
            final target = _registry.putIfAbsent(langStr, () => <String, String>{});
            target[keyStr] = v.toString();
          });
        }
      }
    });
  }

  /// Looks up localized string by key using the current instance's locale.
  String t(String key) {
    final langMap = _registry[locale] ?? _registry[defaultLocale] ?? const {};
    if (langMap.containsKey(key)) {
      return langMap[key]!;
    }
    // Fallback to English
    final enMap = _registry[defaultLocale] ?? const {};
    if (enMap.containsKey(key)) {
      return enMap[key]!;
    }
    return key;
  }

  /// Standard accessor via BuildContext.
  static S of(BuildContext context) {
    final localizations = Localizations.of<S>(context, S);
    if (localizations != null) {
      return localizations;
    }
    return const S(defaultLocale);
  }
}

/// LocalizationsDelegate to allow Flutter to construct and refresh [S]
/// across the widget tree when locale changes.
class AppLocalizationsDelegate extends LocalizationsDelegate<S> {
  final String activeLocale;
  const AppLocalizationsDelegate(this.activeLocale);

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<S> load(Locale locale) async => S(activeLocale);

  @override
  bool shouldReload(covariant AppLocalizationsDelegate oldWidget) =>
      oldWidget.activeLocale != activeLocale;
}
