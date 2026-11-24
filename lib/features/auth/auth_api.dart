import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/api_client.dart';
import 'auth_models.dart';

/// Direct HTTP client wrapper for ScamRakshak Backend Authentication and Sync APIs.
class AuthApi {
  final ApiClient _apiClient;
  final http.Client _httpClient;

  AuthApi({
    ApiClient? apiClient,
    http.Client? httpClient,
  })  : _apiClient = apiClient ?? ApiClient(),
        _httpClient = httpClient ?? http.Client();

  /// POST /auth/session: creates or retrieves user session from Firebase ID token.
  Future<UserProfile> postSession({
    required String username,
    required String locale,
    required String idToken,
  }) async {
    final base = await _apiClient.getBaseUrl();
    final uri = Uri.parse('$base/auth/session');

    try {
      final res = await _httpClient
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'username': username.trim(),
              'locale': locale.trim(),
            }),
          )
          .timeout(ApiClient.requestTimeout);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return UserProfile.fromJson(decoded);
      } else {
        throw ApiException(
          res.statusCode,
          'Auth session initialization failed with status ${res.statusCode}: ${res.body}',
        );
      }
    } on SocketException catch (e) {
      throw ApiOfflineException('Backend is unreachable.', e);
    } on TimeoutException catch (e) {
      throw ApiOfflineException('Auth session request timed out.', e);
    } on http.ClientException catch (e) {
      throw ApiOfflineException('Client network failure during auth session.', e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiOfflineException('Unexpected auth communication error: $e', e);
    }
  }

  /// GET /profile: returns user profile for the authenticated token.
  Future<UserProfile> getProfile({required String idToken}) async {
    final base = await _apiClient.getBaseUrl();
    final uri = Uri.parse('$base/profile');

    try {
      final res = await _httpClient
          .get(
            uri,
            headers: {'Authorization': 'Bearer $idToken'},
          )
          .timeout(ApiClient.requestTimeout);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return UserProfile.fromJson(decoded);
      } else {
        throw ApiException(
          res.statusCode,
          'Get profile failed with status ${res.statusCode}: ${res.body}',
        );
      }
    } on SocketException catch (e) {
      throw ApiOfflineException('Backend is unreachable.', e);
    } on TimeoutException catch (e) {
      throw ApiOfflineException('Get profile request timed out.', e);
    } on http.ClientException catch (e) {
      throw ApiOfflineException('Network failure while fetching profile.', e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiOfflineException('Unexpected profile error: $e', e);
    }
  }

  /// PUT /profile: updates district and/or language.
  Future<UserProfile> updateProfile({
    String? district,
    String? language,
    required String idToken,
  }) async {
    final base = await _apiClient.getBaseUrl();
    final uri = Uri.parse('$base/profile');

    final payload = <String, dynamic>{};
    if (district != null) payload['district'] = district;
    if (language != null) payload['language'] = language;

    try {
      final res = await _httpClient
          .put(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(payload),
          )
          .timeout(ApiClient.requestTimeout);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return UserProfile.fromJson(decoded);
      } else {
        throw ApiException(
          res.statusCode,
          'Update profile failed with status ${res.statusCode}: ${res.body}',
        );
      }
    } on SocketException catch (e) {
      throw ApiOfflineException('Backend is unreachable.', e);
    } on TimeoutException catch (e) {
      throw ApiOfflineException('Update profile request timed out.', e);
    } on http.ClientException catch (e) {
      throw ApiOfflineException('Network error during profile update.', e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiOfflineException('Unexpected error during profile update: $e', e);
    }
  }

  /// GET /sync: pulls user sync payload.
  Future<SyncDataPayload> pullSync({required String idToken}) async {
    final base = await _apiClient.getBaseUrl();
    final uri = Uri.parse('$base/sync');

    try {
      final res = await _httpClient
          .get(
            uri,
            headers: {'Authorization': 'Bearer $idToken'},
          )
          .timeout(ApiClient.requestTimeout);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return SyncDataPayload.fromJson(decoded);
      } else {
        throw ApiException(
          res.statusCode,
          'Pull sync failed with status ${res.statusCode}: ${res.body}',
        );
      }
    } on SocketException catch (e) {
      throw ApiOfflineException('Backend is unreachable.', e);
    } on TimeoutException catch (e) {
      throw ApiOfflineException('Sync pull request timed out.', e);
    } on http.ClientException catch (e) {
      throw ApiOfflineException('Network failure while pulling sync data.', e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiOfflineException('Unexpected error during sync pull: $e', e);
    }
  }

  /// PUT /sync: merges local sync data into server.
  Future<SyncDataPayload> pushSync({
    required SyncDataPayload payload,
    required String idToken,
  }) async {
    final base = await _apiClient.getBaseUrl();
    final uri = Uri.parse('$base/sync');

    try {
      final res = await _httpClient
          .put(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(payload.toJson()),
          )
          .timeout(ApiClient.requestTimeout);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return SyncDataPayload.fromJson(decoded);
      } else {
        throw ApiException(
          res.statusCode,
          'Push sync failed with status ${res.statusCode}: ${res.body}',
        );
      }
    } on SocketException catch (e) {
      throw ApiOfflineException('Backend is unreachable.', e);
    } on TimeoutException catch (e) {
      throw ApiOfflineException('Sync push request timed out.', e);
    } on http.ClientException catch (e) {
      throw ApiOfflineException('Network failure while pushing sync data.', e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiOfflineException('Unexpected error during sync push: $e', e);
    }
  }

  /// DELETE /account: deletes user account and all personal data.
  Future<bool> deleteAccount({required String idToken}) async {
    final base = await _apiClient.getBaseUrl();
    final uri = Uri.parse('$base/account');

    try {
      final res = await _httpClient
          .delete(
            uri,
            headers: {'Authorization': 'Bearer $idToken'},
          )
          .timeout(ApiClient.requestTimeout);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return true;
      } else {
        throw ApiException(
          res.statusCode,
          'Account deletion failed with status ${res.statusCode}: ${res.body}',
        );
      }
    } on SocketException catch (e) {
      throw ApiOfflineException('Backend is unreachable.', e);
    } on TimeoutException catch (e) {
      throw ApiOfflineException('Account deletion timed out.', e);
    } on http.ClientException catch (e) {
      throw ApiOfflineException('Network failure while deleting account.', e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiOfflineException('Unexpected error during account deletion: $e', e);
    }
  }
}
