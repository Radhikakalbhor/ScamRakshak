import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scam_rakshak/core/api_client.dart';
import 'package:scam_rakshak/core/providers.dart';
import 'package:scam_rakshak/core/router.dart';
import 'package:scam_rakshak/features/auth/auth_api.dart';
import 'package:scam_rakshak/features/auth/auth_models.dart';
import 'package:scam_rakshak/features/auth/auth_repository.dart';
import 'package:scam_rakshak/features/auth/auth_strings.dart';
import 'package:scam_rakshak/features/auth/auth_sync_service.dart';
import 'package:scam_rakshak/features/auth/screens/otp_screen.dart';
import 'package:scam_rakshak/features/auth/screens/profile_screen.dart';
import 'package:scam_rakshak/features/auth/screens/signin_screen.dart';
import 'package:scam_rakshak/features/dashboard/detection_history.dart';
import 'package:scam_rakshak/features/lessons/lesson_models.dart';
import 'package:scam_rakshak/features/quiz/literacy_score.dart';

// ============================================================================
// MOCKS FOR TESTING
// ============================================================================

class FakeUserCredential implements UserCredential {
  @override
  final User user;
  FakeUserCredential(this.user);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUser implements User {
  @override
  final String uid;
  @override
  final String? phoneNumber;
  @override
  final String? displayName;

  FakeUser({required this.uid, this.phoneNumber, this.displayName});

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'fake-token-$uid';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockFirebaseAuthDelegate implements FirebaseAuthDelegate {
  User? mockUser;
  final _controller = StreamController<User?>.broadcast();
  bool shouldFailVerification = false;
  String failureCode = 'invalid-phone-number';

  MockFirebaseAuthDelegate({this.mockUser});

  @override
  User? get currentUser => mockUser;

  @override
  Stream<User?> get authStateChanges => _controller.stream;

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    return mockUser?.getIdToken(forceRefresh);
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
  }) async {
    if (shouldFailVerification) {
      verificationFailed(FirebaseAuthException(code: failureCode, message: 'Verification failed.'));
      return;
    }
    codeSent('test-verification-id-123', 42);
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    mockUser ??= FakeUser(uid: 'test_uid_001', phoneNumber: '+919876543210', displayName: 'Test User');
    _controller.add(mockUser);
    return FakeUserCredential(mockUser!);
  }

  @override
  Future<void> signOut() async {
    mockUser = null;
    _controller.add(null);
  }
}

class MockAuthApi extends AuthApi {
  bool isOffline = false;
  UserProfile? currentProfile;
  SyncDataPayload? serverSyncState;
  bool deleteCalled = false;

  @override
  Future<UserProfile> postSession({
    required String username,
    required String locale,
    required String idToken,
  }) async {
    if (isOffline) throw const ApiOfflineException('Offline');
    currentProfile = UserProfile(
      uid: 'test_uid_001',
      phone: '+919876543210',
      username: username,
      district: 'unknown',
      language: locale,
      createdAt: '2026-11-24T00:00:00Z',
      updatedAt: '2026-11-24T00:00:00Z',
      isNewUser: true,
    );
    return currentProfile!;
  }

  @override
  Future<UserProfile> getProfile({required String idToken}) async {
    if (isOffline) throw const ApiOfflineException('Offline');
    return currentProfile ??
        const UserProfile(
          uid: 'test_uid_001',
          phone: '+919876543210',
          username: 'Test User',
          district: 'Raipur',
          language: 'hi',
          createdAt: '2026-11-24T00:00:00Z',
          updatedAt: '2026-11-24T00:00:00Z',
        );
  }

  @override
  Future<UserProfile> updateProfile({
    String? district,
    String? language,
    required String idToken,
  }) async {
    if (isOffline) throw const ApiOfflineException('Offline');
    currentProfile = currentProfile?.copyWith(
      district: district,
      language: language,
    );
    return currentProfile!;
  }

  @override
  Future<SyncDataPayload> pushSync({
    required SyncDataPayload payload,
    required String idToken,
  }) async {
    if (isOffline) throw const ApiOfflineException('Offline');
    serverSyncState = payload;
    return payload;
  }

  @override
  Future<bool> deleteAccount({required String idToken}) async {
    if (isOffline) throw const ApiOfflineException('Offline');
    deleteCalled = true;
    currentProfile = null;
    return true;
  }
}

class MockApiClient extends ApiClient {
  bool reachable = true;
  @override
  Future<bool> isReachable({Duration timeout = const Duration(seconds: 4)}) async => reachable;
}

// ============================================================================
// TESTS
// ============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStrings.ensure();
  });

  group('AuthRepository & Offline Queueing Tests', () {
    test('Online sign in initializes session and caches profile', () async {
      final mockAuth = MockFirebaseAuthDelegate();
      final mockApi = MockAuthApi();
      final mockClient = MockApiClient()..reachable = true;

      final repo = AuthRepository(
        authDelegate: mockAuth,
        authApi: mockApi,
        apiClient: mockClient,
      );

      final profile = await repo.signInWithOtp(
        verificationId: 'test-ver-id',
        smsCode: '123456',
        username: 'Ramesh',
        locale: 'hi',
      );

      expect(profile.username, 'Ramesh');
      expect(profile.language, 'hi');
      expect(profile.district, 'unknown');

      final cached = await repo.getCachedProfile();
      expect(cached, isNotNull);
      expect(cached!.phone, '+919876543210');
    });

    test('Offline sign in creates local profile, queues pending session, and sets offline_authenticated', () async {
      final mockAuth = MockFirebaseAuthDelegate();
      final mockApi = MockAuthApi()..isOffline = true;
      final mockClient = MockApiClient()..reachable = false;

      final repo = AuthRepository(
        authDelegate: mockAuth,
        authApi: mockApi,
        apiClient: mockClient,
      );

      final profile = await repo.signInWithOtp(
        verificationId: 'test-ver-id',
        smsCode: '123456',
        username: 'Suresh',
        locale: 'chh',
      );

      expect(profile.username, 'Suresh');
      expect(profile.language, 'chh');
      expect(profile.district, 'unknown');

      final pending = await repo.getPendingSession();
      expect(pending, isNotNull);
      expect(pending!['username'], 'Suresh');
      expect(pending['locale'], 'chh');
    });

    test('Flush pending session on reconnect synchronizes profile', () async {
      final mockAuth = MockFirebaseAuthDelegate(
        mockUser: FakeUser(uid: 'uid_reconnect', phoneNumber: '+919876543210'),
      );
      final mockApi = MockAuthApi();
      final mockClient = MockApiClient()..reachable = true;

      final repo = AuthRepository(
        authDelegate: mockAuth,
        authApi: mockApi,
        apiClient: mockClient,
      );

      await repo.savePendingSession(username: 'QueuedUser', locale: 'hi');
      final updated = await repo.flushPendingSessionAndSync();

      expect(updated, isNotNull);
      expect(updated!.username, 'QueuedUser');

      final pendingAfter = await repo.getPendingSession();
      expect(pendingAfter, isNull);
    });

    test('Phone immutability: updateProfile only modifies district and language', () async {
      final mockAuth = MockFirebaseAuthDelegate(
        mockUser: FakeUser(uid: 'uid_test', phoneNumber: '+919876543210'),
      );
      final mockApi = MockAuthApi()..currentProfile = const UserProfile(
        uid: 'uid_test',
        phone: '+919876543210',
        username: 'ImmutableUser',
        district: 'unknown',
        language: 'en',
        createdAt: '2026-11-24T00:00:00Z',
        updatedAt: '2026-11-24T00:00:00Z',
      );
      final mockClient = MockApiClient();

      final repo = AuthRepository(
        authDelegate: mockAuth,
        authApi: mockApi,
        apiClient: mockClient,
      );

      final updated = await repo.updateProfile(district: 'Durg', language: 'hi');
      expect(updated.phone, '+919876543210'); // Phone strictly unchanged
      expect(updated.district, 'Durg');
      expect(updated.language, 'hi');
    });

    test('Account deletion clears all local storage, calls delete API, and signs out', () async {
      final mockAuth = MockFirebaseAuthDelegate(
        mockUser: FakeUser(uid: 'uid_delete', phoneNumber: '+919876543210'),
      );
      final mockApi = MockAuthApi();
      final repo = AuthRepository(
        authDelegate: mockAuth,
        authApi: mockApi,
        apiClient: MockApiClient(),
      );

      // Seed local data
      await DetectionHistory().add(
        DetectionRecord(kind: 'message', verdict: 'scam', category: 'otp', time: DateTime.now()),
      );
      await repo.saveCachedProfile(
        const UserProfile(
          uid: 'uid_delete',
          phone: '+919876543210',
          username: 'DeleteMe',
          district: 'Raipur',
          language: 'en',
          createdAt: '',
          updatedAt: '',
        ),
      );

      await repo.deleteAccount();

      expect(mockApi.deleteCalled, isTrue);
      expect(mockAuth.currentUser, isNull);
      expect(await repo.getCachedProfile(), isNull);
      expect(await DetectionHistory().load(), isEmpty);
    });
  });

  group('Auth Sync Service Tests', () {
    test('Two-way sync pushes local items and applies merged remote items without data loss', () async {
      final mockApi = MockAuthApi();
      final service = AuthSyncService(authApi: mockApi);

      // Seed local items
      await DetectionHistory().add(
        DetectionRecord(
          kind: 'message',
          verdict: 'scam',
          category: 'fake_kyc',
          score: 0.95,
          time: DateTime.parse('2026-11-24T01:00:00Z'),
        ),
      );
      await LessonProgress.markDone('otp');

      final result = await service.syncAll(idToken: 'test-token');
      expect(result.detectionHistory.length, 1);
      expect(result.detectionHistory.first.category, 'fake_kyc');
      expect(result.lessonProgress.any((l) => l.lessonId == 'otp'), isTrue);

      // Verify DFL score was triggered
      final literacy = await LiteracyStore.load();
      expect(literacy.lessonCount, greaterThanOrEqualTo(1));
    });
  });

  group('Auth Screens Widget Tests', () {
    testWidgets('SignInScreen renders name, +91 phone, and validates inputs', (tester) async {
      final mockAuth = MockFirebaseAuthDelegate();
      final mockApi = MockAuthApi();
      final repo = AuthRepository(authDelegate: mockAuth, authApi: mockApi);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: SignInScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('signin_name_field')), findsOneWidget);
      expect(find.byKey(const Key('signin_phone_field')), findsOneWidget);
      expect(find.byKey(const Key('signin_submit_btn')), findsOneWidget);
      expect(find.text('+91'), findsOneWidget);

      // Tap submit with empty fields -> shows validation errors
      await tester.tap(find.byKey(const Key('signin_submit_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid name (1-50 characters)'), findsOneWidget);
      expect(find.text('Please enter a valid 10-digit Indian phone number'), findsOneWidget);

      // Enter invalid 9 digit phone
      await tester.enterText(find.byKey(const Key('signin_name_field')), 'Aman');
      await tester.enterText(find.byKey(const Key('signin_phone_field')), '987654321');
      await tester.tap(find.byKey(const Key('signin_submit_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid 10-digit Indian phone number'), findsOneWidget);
    });

    testWidgets('OtpScreen renders 6 digit boxes and resend timer', (tester) async {
      final mockAuth = MockFirebaseAuthDelegate();
      final mockApi = MockAuthApi();
      final repo = AuthRepository(authDelegate: mockAuth, authApi: mockApi);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: OtpScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('otp_box_0')), findsOneWidget);
      expect(find.byKey(const Key('otp_box_5')), findsOneWidget);
      expect(find.byKey(const Key('otp_verify_btn')), findsOneWidget);
      expect(find.textContaining('Resend code in'), findsOneWidget);
    });

    testWidgets('ProfileScreen shows user details, immutable phone, and sync status', (tester) async {
      final mockAuth = MockFirebaseAuthDelegate(
        mockUser: FakeUser(uid: 'u123', phoneNumber: '+919876543210'),
      );
      final mockApi = MockAuthApi();
      final repo = AuthRepository(authDelegate: mockAuth, authApi: mockApi);

      await repo.saveCachedProfile(
        const UserProfile(
          uid: 'u123',
          phone: '+919876543210',
          username: 'Vikram',
          district: 'Raipur',
          language: 'en',
          createdAt: '',
          updatedAt: '',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vikram'), findsOneWidget);
      expect(find.text('+919876543210'), findsOneWidget);
      expect(find.text('Synced'), findsOneWidget);
      expect(find.byKey(const Key('profile_save_btn')), findsOneWidget);
      expect(find.byKey(const Key('profile_logout_btn')), findsOneWidget);

      // Scroll to make delete button visible
      await tester.scrollUntilVisible(find.byKey(const Key('profile_delete_btn')), 100);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile_delete_btn')), findsOneWidget);

      // Tap delete account button -> opens confirmation dialog
      await tester.tap(find.byKey(const Key('profile_delete_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Delete Account Permanently?'), findsOneWidget);
      expect(find.byKey(const Key('confirm_delete_account_btn')), findsOneWidget);
    });
  });

  group('Router Guard & Share-Intent Preservation Tests', () {
    test('RouterAuthGuard preserves path and extra and updates redirect', () {
      final guard = RouterAuthGuard.instance;
      guard.updateAuth(false);

      expect(guard.isAuthenticated, isFalse);

      guard.savedDestinationPath = '/message';
      guard.savedDestinationExtra = 'Suspicious fraud text';

      expect(guard.savedDestinationPath, '/message');
      expect(guard.consumeSavedExtra(), 'Suspicious fraud text');
      expect(guard.savedDestinationExtra, isNull);

      guard.updateAuth(true);
      expect(guard.isAuthenticated, isTrue);
    });
  });
}
