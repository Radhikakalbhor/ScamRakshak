import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../dashboard/detection_history.dart';
import '../quiz/literacy_score.dart';
import 'auth_api.dart';
import 'auth_models.dart';
import 'auth_sync_service.dart';

/// Interface for Firebase Authentication operations to enable hermetic test mocking.
abstract class FirebaseAuthDelegate {
  User? get currentUser;
  Stream<User?> get authStateChanges;
  Future<String?> getIdToken({bool forceRefresh = false});
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(PhoneAuthCredential credential) verificationCompleted,
    required void Function(FirebaseAuthException exception) verificationFailed,
    required void Function(String verificationId, int? resendToken) codeSent,
    required void Function(String verificationId) codeAutoRetrievalTimeout,
    int? forceResendingToken,
    Duration timeout = const Duration(seconds: 60),
  });
  Future<UserCredential> signInWithCredential(AuthCredential credential);
  Future<void> signOut();
}

/// Production implementation of [FirebaseAuthDelegate] delegating to [FirebaseAuth.instance].
class DefaultFirebaseAuthDelegate implements FirebaseAuthDelegate {
  FirebaseAuth? _auth;
  FirebaseAuth get _instance => _auth ??= FirebaseAuth.instance;

  DefaultFirebaseAuthDelegate({FirebaseAuth? auth}) {
    _auth = auth;
  }

  @override
  User? get currentUser => _instance.currentUser;

  @override
  Stream<User?> get authStateChanges => _instance.authStateChanges();

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = _instance.currentUser;
    if (user == null) return null;
    return user.getIdToken(forceRefresh);
  }

  @override
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(PhoneAuthCredential credential) verificationCompleted,
    required void Function(FirebaseAuthException exception) verificationFailed,
    required void Function(String verificationId, int? resendToken) codeSent,
    required void Function(String verificationId) codeAutoRetrievalTimeout,
    int? forceResendingToken,
    Duration timeout = const Duration(seconds: 60),
  }) {
    return _instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: verificationCompleted,
      verificationFailed: verificationFailed,
      codeSent: codeSent,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
      forceResendingToken: forceResendingToken,
      timeout: timeout,
    );
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) {
    return _instance.signInWithCredential(credential);
  }

  @override
  Future<void> signOut() => _instance.signOut();
}

/// Authentication Repository managing Firebase sessions, backend profile synchronization,
/// and local offline queueing.
class AuthRepository {
  static const String keyCachedProfile = 'cached_user_profile_v1';
  static const String keyPendingSession = 'pending_auth_session_v1';

  final FirebaseAuthDelegate _authDelegate;
  final AuthApi _authApi;
  final ApiClient _apiClient;
  final AuthSyncService _syncService;

  AuthRepository({
    FirebaseAuthDelegate? authDelegate,
    AuthApi? authApi,
    ApiClient? apiClient,
    AuthSyncService? syncService,
  })  : _authDelegate = authDelegate ?? DefaultFirebaseAuthDelegate(),
        _authApi = authApi ?? AuthApi(),
        _apiClient = apiClient ?? ApiClient(),
        _syncService = syncService ?? AuthSyncService(authApi: authApi, apiClient: apiClient) {
    // Connect ApiClient token hook so authenticated reports send fresh ID token
    _apiClient.authTokenProvider = () => getIdToken(forceRefresh: false);
  }

  Stream<User?> get authStateChanges => _authDelegate.authStateChanges;
  User? get currentFirebaseUser => _authDelegate.currentUser;
  bool get isDefaultDelegate => _authDelegate is DefaultFirebaseAuthDelegate;

  Future<String?> getIdToken({bool forceRefresh = false}) =>
      _authDelegate.getIdToken(forceRefresh: forceRefresh);

  /// Initiates Firebase Phone number verification.
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(PhoneAuthCredential credential) verificationCompleted,
    required void Function(FirebaseAuthException exception) verificationFailed,
    required void Function(String verificationId, int? resendToken) codeSent,
    required void Function(String verificationId) codeAutoRetrievalTimeout,
    int? forceResendingToken,
  }) {
    return _authDelegate.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: verificationCompleted,
      verificationFailed: verificationFailed,
      codeSent: codeSent,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
      forceResendingToken: forceResendingToken,
    );
  }

  /// Signs in with SMS code. If backend is reachable, calls POST /auth/session and syncs.
  /// If backend is unreachable, completes login offline, queues session creation, and marks as offline-authenticated.
  Future<UserProfile> signInWithOtp({
    required String verificationId,
    required String smsCode,
    required String username,
    required String locale,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final userCredential = await _authDelegate.signInWithCredential(credential);
    final user = userCredential.user;
    if (user == null) {
      throw Exception('Firebase authentication returned an empty user.');
    }

    final idToken = await user.getIdToken();
    final verifiedPhone = user.phoneNumber ?? '';

    // Check backend reachability
    final isReachable = await _apiClient.isReachable();
    if (!isReachable || idToken == null) {
      // Backend is unreachable: Enter app in offline_authenticated state
      final offlineProfile = UserProfile(
        uid: user.uid,
        phone: verifiedPhone,
        username: username,
        district: 'unknown',
        language: locale,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        isNewUser: true,
      );

      await saveCachedProfile(offlineProfile);
      await savePendingSession(username: username, locale: locale);
      return offlineProfile;
    }

    // Backend is reachable: Call POST /auth/session
    try {
      final profile = await _authApi.postSession(
        username: username,
        locale: locale,
        idToken: idToken,
      );

      await saveCachedProfile(profile);
      await clearPendingSession();

      // Trigger background sync on successful sign-in
      try {
        await _syncService.syncAll(idToken: idToken);
      } catch (_) {}

      return profile;
    } on ApiOfflineException {
      final offlineProfile = UserProfile(
        uid: user.uid,
        phone: verifiedPhone,
        username: username,
        district: 'unknown',
        language: locale,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        isNewUser: true,
      );
      await saveCachedProfile(offlineProfile);
      await savePendingSession(username: username, locale: locale);
      return offlineProfile;
    }
  }

  /// Flushes any pending offline session creation and synchronizes user data.
  Future<UserProfile?> flushPendingSessionAndSync() async {
    final user = _authDelegate.currentUser;
    if (user == null) return null;

    final idToken = await user.getIdToken();
    if (idToken == null) return null;

    final isReachable = await _apiClient.isReachable();
    if (!isReachable) return null;

    final pending = await getPendingSession();
    UserProfile? updatedProfile;

    if (pending != null) {
      try {
        updatedProfile = await _authApi.postSession(
          username: pending['username'] ?? '',
          locale: pending['locale'] ?? 'en',
          idToken: idToken,
        );
        await saveCachedProfile(updatedProfile);
        await clearPendingSession();
      } catch (_) {
        return null;
      }
    } else {
      try {
        updatedProfile = await _authApi.getProfile(idToken: idToken);
        await saveCachedProfile(updatedProfile);
      } catch (_) {}
    }

    try {
      await _syncService.syncAll(idToken: idToken);
    } catch (_) {}

    return updatedProfile;
  }

  /// Updates district and/or language in profile.
  Future<UserProfile> updateProfile({
    String? district,
    String? language,
  }) async {
    final token = await getIdToken();
    if (token == null) {
      throw Exception('User is not signed in.');
    }

    final updated = await _authApi.updateProfile(
      district: district,
      language: language,
      idToken: token,
    );
    await saveCachedProfile(updated);
    return updated;
  }

  /// Triggers full sync manually.
  Future<SyncDataPayload> syncNow() async {
    final token = await getIdToken();
    if (token == null) {
      throw Exception('User is not signed in.');
    }
    return _syncService.syncAll(idToken: token);
  }

  /// Permanently deletes user account, erases all personal data, and signs out.
  Future<void> deleteAccount() async {
    final token = await getIdToken();
    if (token != null) {
      try {
        await _authApi.deleteAccount(idToken: token);
      } catch (_) {}
    }

    // Clear local user storage
    await clearCachedProfile();
    await clearPendingSession();
    await DetectionHistory().clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(LiteracyStore.key);
    await prefs.remove('user_synced_reports_v1');

    await _authDelegate.signOut();
  }

  /// Signs out of Firebase and clears local profile cache.
  Future<void> signOut() async {
    await clearCachedProfile();
    await clearPendingSession();
    await _authDelegate.signOut();
  }

  // --- Storage Helpers ---

  Future<void> saveCachedProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyCachedProfile, jsonEncode(profile.toJson()));
  }

  Future<UserProfile?> getCachedProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(keyCachedProfile);
      if (raw == null || raw.isEmpty) return null;
      return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyCachedProfile);
  }

  Future<void> savePendingSession({required String username, required String locale}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      keyPendingSession,
      jsonEncode({'username': username, 'locale': locale}),
    );
  }

  Future<Map<String, String>?> getPendingSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(keyPendingSession);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map;
      return {
        'username': (map['username'] ?? '').toString(),
        'locale': (map['locale'] ?? 'en').toString(),
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPendingSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyPendingSession);
  }
}
