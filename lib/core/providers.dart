import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
// ENGINE PLACEHOLDER PROVIDERS (LOCKED CONTRACTS FROM AGENTS.md)
//
// These providers are temporarily typed with Object? to allow compilation
// without referencing nonexistent engine files until Radhika implements:
//
// 1. lib/engine/scam_classifier.dart:
//      static Future<ScamClassifier> ScamClassifier.load();
//      ScamResult classify(String text);
//
// 2. lib/engine/call_analyzer.dart:
//      static Future<CallAnalyzer> CallAnalyzer.load();
//      CallResult analyze(String transcript);
//
// CONTRACTS LOCKED IN AGENTS.md. DO NOT CHANGE SIGNATURES.
// ============================================================================

/// TODO: Replace Object? with ScamClassifier when lib/engine/scam_classifier.dart is ready.
final scamClassifierProvider = FutureProvider<Object?>((ref) async {
  // Placeholder implementation allowing app scaffolding and analysis to pass
  return null;
});

/// TODO: Replace Object? with CallAnalyzer when lib/engine/call_analyzer.dart is ready.
final callAnalyzerProvider = FutureProvider<Object?>((ref) async {
  // Placeholder implementation allowing app scaffolding and analysis to pass
  return null;
});
