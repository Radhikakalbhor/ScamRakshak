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
  Future<Map> transcribe(File audio) => transcribeChunk(audio);

  /// Same as [transcribe], with optional language hint `?lang=hi|en|auto` (live call chunks).
  Future<Map> transcribeChunk(File audio, {String? lang}) => _transcribe(audio, lang, requestTimeout);

  /// Same as [transcribe] for a whole call recording, which can take minutes to transcribe.
  /// Streams the file as is (no copy is made).
  Future<Map> transcribeRecording(File audio, {Duration timeout = const Duration(minutes: 5)}) =>
      _transcribe(audio, null, timeout);

  Future<Map> _transcribe(File audio, String? lang, Duration requestTimeout) async {
    final base = await getBaseUrl();
    final uri = Uri.parse('$base/transcribe').replace(queryParameters: lang == null ? null : {'lang': lang});

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

  /// True when GET /health answers 2xx within [timeout].
  Future<bool> isReachable({Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final base = await getBaseUrl();
      final r = await _httpClient.get(Uri.parse('$base/health')).timeout(timeout);
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Submits a fraud incident report.
  /// Contract: POST /reports {"type": "otp|fake_qr|loan_app|call|other", "district": "...", "ts": "..."}
  Future<void> postReport(String type, String district) =>
      postReportAt(type, district, DateTime.now().toUtc().toIso8601String());

  /// Same as [postReport] with the time the report was made (used by the offline report queue,
  /// which may send it later).
  Future<void> postReportAt(String type, String district, String ts) async {
    final base = await getBaseUrl();
    final uri = Uri.parse('$base/reports');

    final payload = {
      'type': type,
      'district': district,
      'ts': ts,
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

  /// GET [path] -> decoded JSON. Same error mapping as the other calls.
  Future<Object?> _getJson(String path) async {
    final base = await getBaseUrl();
    try {
      final r = await _httpClient.get(Uri.parse('$base$path')).timeout(requestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw ApiException(r.statusCode, 'GET $path failed with status ${r.statusCode}');
      }
      return json.decode(utf8.decode(r.bodyBytes));
    } on SocketException catch (e) {
      throw ApiOfflineException('Backend is unreachable.', e);
    } on TimeoutException catch (e) {
      throw ApiOfflineException('Request timed out.', e);
    } on http.ClientException catch (e) {
      throw ApiOfflineException('Network failure.', e);
    } on ApiException {
      rethrow;
    } on FormatException catch (e) {
      throw ApiException(500, 'Bad JSON from $path: $e');
    } catch (e) {
      throw ApiOfflineException('Unexpected network error: $e', e);
    }
  }

  /// GET /trends/summary: synthetic (seeded demo) vs live report aggregates, weekly trend,
  /// counts below `min_count` suppressed. Throws [ApiException] 404 on older servers.
  Future<Map> getTrendSummary() async {
    final j = await _getJson('/trends/summary');
    if (j is Map) return j;
    throw const ApiException(500, 'Bad /trends/summary response');
  }

  /// GET /alerts -> list of emerging-scam alerts ({"kind": "spike"|"cluster", ...}).
  Future<List<Map>> getAlerts() async {
    final j = await _getJson('/alerts');
    final list = j is Map ? j['alerts'] : null;
    return list is List ? list.whereType<Map>().toList() : <Map>[];
  }

  /// POST /fingerprints: opt-in anonymous 64-bit SimHash (16 hex digits) of a scam message.
  Future<void> postFingerprint(String fp, String category) async {
    final base = await getBaseUrl();
    try {
      final r = await _httpClient
          .post(Uri.parse('$base/fingerprints'),
              headers: {'Content-Type': 'application/json'}, body: json.encode({'fp': fp, 'category': category}))
          .timeout(requestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) throw ApiException(r.statusCode, 'fingerprint rejected');
    } on SocketException catch (e) {
      throw ApiOfflineException('Backend is unreachable.', e);
    } on TimeoutException catch (e) {
      throw ApiOfflineException('Request timed out.', e);
    } on http.ClientException catch (e) {
      throw ApiOfflineException('Network failure.', e);
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
