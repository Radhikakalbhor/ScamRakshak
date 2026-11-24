import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
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

  /// The build-time address that was active when [prefKeyBaseUrl] was saved. A saved address
  /// only applies to that build, so an update with a new server (e.g. laptop -> cloud) moves
  /// phones to the new server instead of keeping an old laptop address.
  static const String prefKeySavedForBuild = 'scamrakshak_api_base_url_build';

  /// Production backend (Render). Override for local testing:
  /// `flutter build apk --dart-define=API_BASE_URL=http://<laptop-ip>:8000`.
  static const String productionBaseUrl = 'https://scamrakshak-backend.onrender.com';

  /// Android-emulator alias of the host computer. Only ever used on an emulator.
  static const String emulatorBaseUrl = 'http://10.0.2.2:8000';

  /// Kept for older callers; same as [emulatorBaseUrl].
  static const String defaultBaseUrl = emulatorBaseUrl;

  /// Server compiled into this build: --dart-define=API_BASE_URL, else [productionBaseUrl].
  static const String buildBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: productionBaseUrl);

  static const Duration requestTimeout = Duration(seconds: 25);

  /// Whether the app runs on an Android emulator (injectable for tests). Unknown -> false.
  static Future<bool> Function() isEmulator = _nativeIsEmulator;

  static bool? _emulatorCache;
  static Future<bool> _nativeIsEmulator() async {
    if (_emulatorCache != null) return _emulatorCache!;
    try {
      final info = await AppInfo.load();
      return _emulatorCache = info.isEmulator;
    } catch (_) {
      return false;
    }
  }

  final http.Client _httpClient;
  String? _customBaseUrl;

  /// Optional token provider hook for attaching Bearer tokens to authenticated requests.
  Future<String?> Function()? authTokenProvider;

  ApiClient({http.Client? httpClient, String? baseUrl, this.authTokenProvider})
      : _httpClient = httpClient ?? http.Client(),
        _customBaseUrl = baseUrl;

  /// Active server address. Order: address given in code / just saved -> the address saved in
  /// settings (kept across app updates; an emulator-only 10.0.2.2 is ignored on a real phone) ->
  /// the build-time API_BASE_URL -> 10.0.2.2 on an emulator only. '' = not set.
  Future<String> getBaseUrl() async {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) return _customBaseUrl!;
    String? saved;
    String? savedFor;
    try {
      final prefs = await SharedPreferences.getInstance();
      saved = prefs.getString(prefKeyBaseUrl);
      savedFor = prefs.getString(prefKeySavedForBuild);
    } catch (_) {}
    return resolveBaseUrl(saved: saved, savedForBuild: savedFor, buildTime: buildBaseUrl, emulator: await isEmulator());
  }

  /// Pure resolution rule behind [getBaseUrl] (tested). A saved address is used only if it was
  /// saved under the same build-time address ([savedForBuild]); older saves without that mark
  /// count only when the build has no address of its own.
  static String resolveBaseUrl({String? saved, String? savedForBuild, String buildTime = '', required bool emulator}) {
    final sameBuild = normalizeBaseUrl(savedForBuild ?? '') == normalizeBaseUrl(buildTime);
    final s = sameBuild ? normalizeBaseUrl(saved ?? '') : '';
    if (s.isNotEmpty && (emulator || !isEmulatorOnly(s))) return s;
    final b = normalizeBaseUrl(buildTime);
    if (b.isNotEmpty && (emulator || !isEmulatorOnly(b))) return b;
    return emulator ? emulatorBaseUrl : '';
  }

  /// 10.0.2.2 reaches the computer only from the Android emulator. (127.0.0.1 is fine on a real
  /// phone with `adb reverse tcp:8000 tcp:8000`.)
  static bool isEmulatorOnly(String url) => Uri.tryParse(url)?.host == '10.0.2.2';

  /// Adds http:// and drops trailing slashes; '' when it is not a usable address.
  static String normalizeBaseUrl(String raw) {
    var u = raw.trim();
    if (u.isEmpty) return '';
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    final uri = Uri.tryParse(u);
    return (uri == null || uri.host.isEmpty) ? '' : u;
  }

  /// Sets and persists a custom base URL (normalized).
  Future<void> setBaseUrl(String newUrl) async {
    final clean = normalizeBaseUrl(newUrl);
    _customBaseUrl = clean.isEmpty ? newUrl.trim() : clean;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKeyBaseUrl, _customBaseUrl!);
      await prefs.setString(prefKeySavedForBuild, buildBaseUrl);
    } catch (_) {}
  }

  Future<String> _requireBase() async {
    final base = await getBaseUrl();
    if (base.isEmpty) throw const ApiOfflineException('No server address set. Open Server settings.');
    return base;
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

  /// [transcribeRecording] with progress and cancel: [onSent] fires once the whole file has been
  /// sent (the server is then transcribing); [cancel] aborts the connection. Used by
  /// [transcribeWithChecks], the shared upload routine.
  Future<Map> transcribeUpload(
    File audio, {
    void Function()? onSent,
    UploadCancel? cancel,
    Duration timeout = const Duration(minutes: 5),
  }) =>
      _transcribe(audio, null, timeout, onSent: onSent, cancel: cancel);

  Future<Map> _transcribe(File audio, String? lang, Duration requestTimeout,
      {void Function()? onSent, UploadCancel? cancel}) async {
    final base = await _requireBase();
    final uri = Uri.parse('$base/transcribe').replace(queryParameters: lang == null ? null : {'lang': lang});

    http.Client? own;
    try {
      final request = http.MultipartRequest('POST', uri);
      final fileLength = await audio.length();
      var sent = 0;
      var told = false;
      final counted = audio.openRead().map((chunk) {
        sent += chunk.length;
        if (!told && sent >= fileLength) {
          told = true;
          onSent?.call();
        }
        return chunk;
      });

      final multipartFile = http.MultipartFile(
        'file',
        http.ByteStream(counted),
        fileLength,
        filename: audio.path.split(Platform.pathSeparator).last,
      );

      request.files.add(multipartFile);

      final http.StreamedResponse streamedResponse;
      if (cancel != null) {
        own = http.Client();
        cancel.onCancel(own.close);
        streamedResponse = await own.send(request).timeout(requestTimeout);
      } else {
        streamedResponse = await request.send().timeout(requestTimeout);
      }
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
    } finally {
      own?.close();
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
    final base = await _requireBase();
    final uri = Uri.parse('$base/reports');

    final payload = {
      'type': type,
      'district': district,
      'ts': ts,
    };

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authTokenProvider != null) {
      try {
        final token = await authTokenProvider!();
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {}
    }

    try {
      final response = await _httpClient
          .post(
            uri,
            headers: headers,
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
    final base = await _requireBase();
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
    final base = await _requireBase();
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
    final base = await _requireBase();
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

/// Cancels a running [transcribeWithChecks] / [ApiClient.transcribeUpload].
class UploadCancel {
  final _done = Completer<void>();
  final _hooks = <void Function()>[];

  bool get isCancelled => _done.isCompleted;
  Future<void> get whenCancelled => _done.future;

  void cancel() {
    if (_done.isCompleted) return;
    _done.complete();
    for (final h in _hooks) {
      try {
        h();
      } catch (_) {}
    }
    _hooks.clear();
  }

  /// Runs [hook] on cancel (at once if already cancelled).
  void onCancel(void Function() hook) => isCancelled ? hook() : _hooks.add(hook);
}

/// Thrown by [transcribeWithChecks] when the user pressed Cancel.
class UploadCancelledException implements Exception {
  const UploadCancelledException();
  @override
  String toString() => 'UploadCancelledException';
}

/// Steps of [transcribeWithChecks], for the progress text.
enum UploadStage { checking, uploading, transcribing }

/// The one upload routine for a whole recording (Check Call, shared audio): a quick /health check
/// (4 s), then the upload and transcription with a timeout. Throws [ApiOfflineException] (not
/// reachable / timed out), [ApiException] (server answered with an error) or
/// [UploadCancelledException]. Never hangs past [reachTimeout] + [timeout].
Future<Map> transcribeWithChecks(
  ApiClient api,
  File file, {
  UploadCancel? cancel,
  void Function(UploadStage stage)? onStage,
  Duration reachTimeout = const Duration(seconds: 4),
  Duration timeout = const Duration(minutes: 5),
}) async {
  Future<T> guard<T>(Future<T> f) {
    if (cancel == null) return f;
    return Future.any<T>([
      f,
      cancel.whenCancelled.then<T>((_) => throw const UploadCancelledException()),
    ]);
  }

  void stage(UploadStage s) {
    if (!(cancel?.isCancelled ?? false)) onStage?.call(s);
  }

  stage(UploadStage.checking);
  final base = await guard(api.getBaseUrl());
  if (base.isEmpty) throw const ApiOfflineException('No server address set. Open Server settings.');
  final ok = await guard(api.isReachable(timeout: reachTimeout));
  if (cancel?.isCancelled ?? false) throw const UploadCancelledException();
  if (!ok) throw ApiOfflineException('Server not reachable at $base');
  stage(UploadStage.uploading);
  try {
    return await guard(api.transcribeUpload(
      file,
      onSent: () => stage(UploadStage.transcribing),
      cancel: cancel,
      timeout: timeout,
    ));
  } on ApiOfflineException {
    if (cancel?.isCancelled ?? false) throw const UploadCancelledException();
    rethrow;
  }
}

/// App version, build number and emulator flag from Android (MainActivity "appInfo").
class AppInfo {
  final String version;
  final String build;
  final bool isEmulator;
  const AppInfo(this.version, this.build, this.isEmulator);

  static const _channel = MethodChannel('scamrakshak/alert');
  static AppInfo? _cached;

  /// Injectable for tests.
  static Future<AppInfo> Function() loader = _loadNative;

  static Future<AppInfo> load() => loader();

  static Future<AppInfo> _loadNative() async {
    if (_cached != null) return _cached!;
    // Only MainActivity answers this; elsewhere (tests, desktop) there is no emulator alias either.
    if (!Platform.isAndroid) return const AppInfo('dev', '0', false);
    final m = await _channel.invokeMapMethod<String, Object?>('appInfo');
    return _cached = AppInfo(
      '${m?['version'] ?? '?'}',
      '${m?['build'] ?? '?'}',
      m?['emulator'] == true,
    );
  }
}