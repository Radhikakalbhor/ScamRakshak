import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/call_analyzer.dart';
import '../engine/scam_classifier.dart';
import 'api_client.dart';
import 'strings.dart';

/// Provider for the API client communicating with backend.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

/// State notifier managing active app locale ('en', 'hi', 'chh')
/// and persisting changes to SharedPreferences.
class LocaleNotifier extends StateNotifier<String> {
  static const String prefKeyLocale = 'scamrakshak_selected_locale';

  LocaleNotifier([String initialLocale = S.defaultLocale])
      : super(initialLocale) {
    _loadPersistedLocale();
  }

  Future<void> _loadPersistedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLocale = prefs.getString(prefKeyLocale);
      if (savedLocale != null && S.supportedLanguages.contains(savedLocale)) {
        state = savedLocale;
      }
    } catch (_) {
      // Gracefully maintain default fallback
    }
  }

  Future<void> setLocale(String languageCode) async {
    if (!S.supportedLanguages.contains(languageCode)) return;
    state = languageCode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKeyLocale, languageCode);
    } catch (_) {
      // Ignored for offline robustness
    }
  }
}

/// Provider exposing the current active locale string ('en' | 'hi' | 'chh').
final localeProvider = StateNotifierProvider<LocaleNotifier, String>((ref) {
  return LocaleNotifier();
});

// ============================================================================
// ENGINE PROVIDERS (LOCKED CONTRACTS FROM AGENTS.md). DO NOT CHANGE SIGNATURES.
// ============================================================================

/// Offline scam message classifier (assets/models/scam_model.json), loaded once.
final scamClassifierProvider = FutureProvider<ScamClassifier>((ref) => ScamClassifier.load());

/// Offline scam call transcript analyzer (assets/rules/call_rules.json), loaded once.
final callAnalyzerProvider = FutureProvider<CallAnalyzer>((ref) => CallAnalyzer.load());
