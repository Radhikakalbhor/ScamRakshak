import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Exception thrown when the API backend is unreachable or offline.
class ApiOfflineException implements Exception {
  final String message;
  final dynamic cause;

  const ApiOfflineException(this.message, [this.cause]);

  @override
  String toString() => 'ApiOfflineException: $message';
}

/// Generic exception for API response errors.
class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException ($statusCode): $message';
}

/// ApiClient communicates with the ScamRakshak FastAPI backend.
/// Meets locked contracts defined in AGENTS.md.
class ApiClient {
  static const String prefKeyBaseUrl = 'scamrakshak_api_base_url';
  static const String defaultBaseUrl = 'http://10.0.2.2:8000';
  static const Duration requestTimeout = Duration(seconds: 25);

  final http.Client _httpClient;
  String? _customBaseUrl;

  ApiClient({http.Client? httpClient, String? baseUrl})
      : _httpClient = httpClient ?? http.Client(),
        _customBaseUrl = baseUrl;

  /// Gets the active base URL from memory or SharedPreferences.
  Future<String> getBaseUrl() async {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return _customBaseUrl!;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(prefKeyBaseUrl) ?? defaultBaseUrl;
    } catch (_) {
      return defaultBaseUrl;
    }
  }

  /// Sets and persists a custom base URL.
  Future<void> setBaseUrl(String newUrl) async {
    _customBaseUrl = newUrl.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKeyBaseUrl, _customBaseUrl!);
    } catch (_) {}
  }

  /// Uploads audio for transcription using multipart/form-data.
  /// Contract: POST /transcribe (multipart 'file') -> {"text": "...", "lang": "hi"}
  Future<Map> transcribe(File audio) async {
    final base = await getBaseUrl();
    final uri = Uri.parse('$base/transcribe');

    try {
      final request = http.MultipartRequest('POST', uri);
      final fileStream = http.ByteStream(audio.openRead());
      final fileLength = await audio.length();

      final multipartFile = http.MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: audio.path.split(Platform.pathSeparator).last,
      );

      request.files.add(multipartFile);

      final streamedResponse =
          await request.send().timeout(requestTimeout);
      final response =
          await http.Response.fromStream(streamedResponse).timeout(requestTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded is Map) {
          return decoded;
        }
        return {'text': decoded.toString(), 'lang': 'en'};
      } else {
        throw ApiException(
          response.statusCode,
          'Transcribe failed with status ${response.statusCode}: ${response.body}',
        );
      }
    } on SocketException catch (e) {
      throw ApiOfflineException('Backend is unreachable. Please check your connection.', e);
    } on TimeoutException catch (e) {
      throw ApiOfflineException('Transcribe request timed out.', e);
    } on http.ClientException catch (e) {
      throw ApiOfflineException('Client network error while connecting to server.', e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiOfflineException('Unexpected communication failure: $e', e);
    }
  }

  /// Submits a fraud incident report.
  /// Contract: POST /reports {"type": "otp|fake_qr|loan_app|call|other", "district": "...", "ts": "..."}
  Future<void> postReport(String type, String district) async {
    final base = await getBaseUrl();
    final uri = Uri.parse('$base/reports');

    final payload = {
      'type': type,
      'district': district,
      'ts': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      final response = await _httpClient
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          response.statusCode,
          'Post report failed with status ${response.statusCode}: ${response.body}',
        );
      }
    } on SocketException catch (e) {
      throw ApiOfflineException('Backend is unreachable. Report could not be submitted.', e);
    } on TimeoutException catch (e) {
      throw ApiOfflineException('Report submission timed out.', e);
    } on http.ClientException catch (e) {
      throw ApiOfflineException('Network failure while submitting report.', e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiOfflineException('Unexpected network error: $e', e);
    }
  }

  /// Fetches district fraud trends from backend.
  /// Contract: GET /trends -> [{"district": "...", "type": "...", "count": 12}]
  Future<List<Map>> getTrends() async {
    final base = await getBaseUrl();
    final uri = Uri.parse('$base/trends');

    try {
      final response = await _httpClient.get(uri).timeout(requestTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded is List) {
          return decoded.whereType<Map>().toList();
        }
        return <Map>[];
      } else {
        throw ApiException(
          response.statusCode,
          'Get trends failed with status ${response.statusCode}: ${response.body}',
        );
      }
    } on SocketException catch (e) {
      throw ApiOfflineException('Backend is unreachable. Cannot load live trends.', e);
    } on TimeoutException catch (e) {
      throw ApiOfflineException('Loading trends timed out.', e);
    } on http.ClientException catch (e) {
      throw ApiOfflineException('Network failure while loading trends.', e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiOfflineException('Unexpected error loading trends: $e', e);
    }
  }
}
