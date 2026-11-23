import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart' show LocaleNotifier;
import 'call_timeline.dart';

/// Audio extensions written by phone call recorders.
const kRecordingExtensions = {'m4a', 'mp3', 'amr', 'aac', 'wav', '3gp', 'ogg'};

bool isRecordingFile(String path) {
  final dot = path.lastIndexOf('.');
  return dot > 0 && kRecordingExtensions.contains(path.substring(dot + 1).toLowerCase());
}

String fileNameOf(String path) => path.split(RegExp(r'[\\/]')).last;

/// Where common Android phones save call recordings (shown as suggestions when they exist).
const kRecordingFolderCandidates = [
  '/storage/emulated/0/Recordings/Call', // Samsung (One UI 4+)
  '/storage/emulated/0/Call', // older Samsung
  '/storage/emulated/0/Record/Call', // Vivo / iQOO
  '/storage/emulated/0/Recordings/Call recordings',
  '/storage/emulated/0/Music/Recordings/Call Recordings', // OnePlus / Oppo / Realme
  '/storage/emulated/0/MIUI/sound_recorder/call_rec', // Xiaomi
  '/storage/emulated/0/PhoneRecord', // Huawei / Honor
];

/// Settings, processed list, pending list and saved results, in shared_preferences.
/// Shared by the app and the background service isolate, so call [reload] before reading there.
class AutoAnalyzeStore {
  static const kEnabled = 'auto_rec_enabled';
  static const kEnabledAt = 'auto_rec_enabled_at';
  static const kFolder = 'auto_rec_folder';
  static const kConsent = 'auto_rec_consent_v1';
  static const kProcessed = 'auto_rec_processed';
  static const kPending = 'auto_rec_pending';
  static const kResults = 'auto_rec_results';
  static const kResultPrefix = 'auto_rec_result_';
  static const kRead = 'auto_rec_read';
  static const maxProcessed = 2000;

  /// Results kept for the history in Live Call Guard (oldest dropped beyond this).
  static const maxResults = 500;

  final SharedPreferences prefs;
  AutoAnalyzeStore(this.prefs);

  static Future<AutoAnalyzeStore> open() async => AutoAnalyzeStore(await SharedPreferences.getInstance());

  Future<void> reload() => prefs.reload();

  bool get consent => prefs.getBool(kConsent) ?? false;
  Future<void> setConsent(bool v) => prefs.setBool(kConsent, v);

  String? get folder => prefs.getString(kFolder);
  Future<void> setFolder(String path) => prefs.setString(kFolder, path);

  /// Off by default.
  bool get enabled => prefs.getBool(kEnabled) ?? false;

  /// When the toggle was last turned on; only files modified after this count.
  DateTime? get enabledAt {
    final ms = prefs.getInt(kEnabledAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setEnabled(bool on, {DateTime? now}) async {
    if (on) await prefs.setInt(kEnabledAt, (now ?? DateTime.now()).millisecondsSinceEpoch);
    await prefs.setBool(kEnabled, on);
  }

  String get locale => prefs.getString(LocaleNotifier.prefKeyLocale) ?? 'en';

  List<String> get processed => prefs.getStringList(kProcessed) ?? const [];
  List<String> get pending => prefs.getStringList(kPending) ?? const [];

  Future<void> markProcessed(String path) async {
    final list = [...processed.where((p) => p != path), path];
    await prefs.setStringList(kProcessed, list.length > maxProcessed ? list.sublist(list.length - maxProcessed) : list);
    await removePending(path);
  }

  Future<void> addPending(String path) async {
    if (pending.contains(path)) return;
    await prefs.setStringList(kPending, [...pending, path]);
  }

  Future<void> removePending(String path) async {
    if (!pending.contains(path)) return;
    await prefs.setStringList(kPending, pending.where((p) => p != path).toList());
  }

  List<String> get resultIds => prefs.getStringList(kResults) ?? const [];

  /// Saves the verdict and transcript (never audio). Keeps the newest [maxResults].
  Future<String> saveResult(String path, CallTimelineResult r, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    var id = at.millisecondsSinceEpoch.toString();
    while (prefs.containsKey('$kResultPrefix$id')) {
      id = '${int.parse(id) + 1}';
    }
    await prefs.setString(
        '$kResultPrefix$id', jsonEncode({'path': path, 'at': at.toIso8601String(), 'result': r.toJson()}));
    final ids = [...resultIds, id];
    final dropped = <String>{};
    while (ids.length > maxResults) {
      final old = ids.removeAt(0);
      dropped.add(old);
      await prefs.remove('$kResultPrefix$old');
    }
    await prefs.setStringList(kResults, ids);
    if (dropped.isNotEmpty) await prefs.setStringList(kRead, readIds.where((r) => !dropped.contains(r)).toList());
    return id;
  }

  /// Results the user has opened (in the app or from the notification).
  Set<String> get readIds => (prefs.getStringList(kRead) ?? const []).toSet();

  bool isRead(String id) => readIds.contains(id);

  Future<void> markRead(String id) async {
    final read = readIds;
    if (read.contains(id)) return;
    await prefs.setStringList(kRead, [...read, id]);
  }

  Future<void> markAllRead() => prefs.setStringList(kRead, [...resultIds]);

  int get unreadCount {
    final read = readIds;
    return resultIds.where((id) => !read.contains(id)).length;
  }

  /// Every saved result, newest first (unreadable entries skipped).
  List<StoredRecordingResult> allResults() => [
        for (final id in resultIds.reversed) ?result(id),
      ];

  StoredRecordingResult? result(String id) {
    final raw = prefs.getString('$kResultPrefix$id');
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return StoredRecordingResult(
        id,
        j['path'] as String,
        DateTime.parse(j['at'] as String),
        CallTimelineResult.fromJson((j['result'] as Map).cast<String, dynamic>()),
      );
    } catch (_) {
      return null;
    }
  }
}

class StoredRecordingResult {
  final String id;
  final String path;
  final DateTime at;
  final CallTimelineResult result;
  const StoredRecordingResult(this.id, this.path, this.at, this.result);

  String get fileName => fileNameOf(path);
}

class RecordingFileInfo {
  final String path;
  final int size;
  final DateTime modified;
  const RecordingFileInfo(this.path, this.size, this.modified);
}

typedef FolderLister = Future<List<RecordingFileInfo>> Function(String folder);

/// Lists the files directly inside [folder] (no copies, read-only).
Future<List<RecordingFileInfo>> listFolder(String folder) async {
  final dir = Directory(folder);
  if (!await dir.exists()) return const [];
  final out = <RecordingFileInfo>[];
  await for (final e in dir.list(followLinks: false)) {
    if (e is! File) continue;
    try {
      final st = await e.stat();
      out.add(RecordingFileInfo(e.path, st.size, st.modified));
    } catch (_) {}
  }
  return out;
}

/// Decides which files in the watched folder are new, finished call recordings.
///
/// A file qualifies when it has an audio extension, was modified after the toggle was turned on,
/// is bigger than [minBytes], is not processed yet, and its size (and time) stayed the same for
/// [stablePolls] polls in a row (the recorder has finished writing it).
class RecordingWatcher {
  static const minBytes = 20 * 1024;
  static const stablePolls = 3;

  final FolderLister list;
  final Map<String, ({int size, DateTime modified, int count})> _seen = {};

  RecordingWatcher({this.list = listFolder});

  Future<List<RecordingFileInfo>> poll({
    required String folder,
    required DateTime since,
    required Set<String> processed,
  }) async {
    final files = await list(folder);
    final present = <String>{};
    final ready = <RecordingFileInfo>[];
    for (final f in files) {
      if (!isRecordingFile(f.path) || processed.contains(f.path)) continue;
      if (!f.modified.isAfter(since) || f.size <= minBytes) continue;
      present.add(f.path);
      final s = _seen[f.path];
      final count = (s != null && s.size == f.size && s.modified == f.modified) ? s.count + 1 : 1;
      _seen[f.path] = (size: f.size, modified: f.modified, count: count);
      if (count >= stablePolls) ready.add(f);
    }
    _seen.removeWhere((k, _) => !present.contains(k));
    ready.sort((a, b) => a.modified.compareTo(b.modified));
    return ready;
  }
}

/// Shows the result notifications.
abstract class AutoAnalyzeNotifier {
  Future<void> showVerdict(StoredRecordingResult r);
  Future<void> showOffline(String path);
  Future<void> cancelOffline(String path);
}

enum ProcessStatus { done, offline, failed, noSpeech, missing, busy }

/// Uploads one finished recording, analyses the transcript and notifies.
class RecordingProcessor {
  /// Pending (offline) recordings are retried every this many polls (3 s each).
  static const retryEvery = 10;

  final AutoAnalyzeStore store;
  final ApiClient api;
  final CallTimeline timeline;
  final AutoAnalyzeNotifier notifier;
  final RecordingWatcher watcher;
  final _inFlight = <String>{};
  int _ticks = 0;

  RecordingProcessor({
    required this.store,
    required this.api,
    required this.timeline,
    required this.notifier,
    RecordingWatcher? watcher,
  }) : watcher = watcher ?? RecordingWatcher();

  /// One poll of the watched folder. Returns false when the feature is switched off.
  Future<bool> tick() async {
    await store.reload();
    final folder = store.folder;
    final since = store.enabledAt;
    if (!store.enabled || folder == null || since == null) return false;
    _ticks++;
    final ready = await watcher.poll(folder: folder, since: since, processed: store.processed.toSet());
    final pending = store.pending.toSet();
    bool? online;
    for (final f in ready) {
      if (pending.contains(f.path)) {
        if (_ticks % retryEvery != 0) continue;
        online ??= await api.isReachable();
        if (!online) continue;
      }
      await process(f.path);
    }
    // Pending recordings the user deleted meanwhile.
    for (final p in pending) {
      if (!File(p).existsSync()) await store.removePending(p);
    }
    return true;
  }

  /// Analyses [path]. With [notify] false (opened from the app) no verdict notification is shown.
  Future<({ProcessStatus status, String? id})> process(String path, {bool notify = true}) async {
    if (!_inFlight.add(path)) return (status: ProcessStatus.busy, id: null);
    try {
      final file = File(path);
      if (!await file.exists()) {
        await store.removePending(path);
        await notifier.cancelOffline(path);
        return (status: ProcessStatus.missing, id: null);
      }
      Map res;
      try {
        // Streams the original file; nothing is copied, and the server deletes its temp copy.
        res = await api.transcribeRecording(file);
      } on ApiOfflineException {
        return (status: await _offline(path, notify), id: null);
      } on ApiException catch (e) {
        if (e.statusCode >= 500) return (status: await _offline(path, notify), id: null);
        await store.markProcessed(path); // unsupported / broken file: never retry
        await notifier.cancelOffline(path);
        return (status: ProcessStatus.failed, id: null);
      }
      final text = (res['text'] ?? '').toString().trim();
      await store.reload();
      if (text.isEmpty) {
        await store.markProcessed(path);
        await notifier.cancelOffline(path);
        return (status: ProcessStatus.noSpeech, id: null);
      }
      final id = await store.saveResult(path, timeline.analyze(text));
      await store.markProcessed(path);
      await notifier.cancelOffline(path);
      final saved = store.result(id);
      if (notify && saved != null) await notifier.showVerdict(saved);
      return (status: ProcessStatus.done, id: id);
    } finally {
      _inFlight.remove(path);
    }
  }

  Future<ProcessStatus> _offline(String path, bool notify) async {
    final already = store.pending.contains(path);
    await store.addPending(path); // stays unprocessed
    if (notify && !already) await notifier.showOffline(path);
    return ProcessStatus.offline;
  }
}

/// Demo clips joined into one sample scam call (MP3 frames can simply be concatenated).
final kSimulateClips = [
  for (var i = 1; i <= 8; i++) 'assets/samples/live/audio/scam_fake_kyc_otp_0$i.mp3',
];

/// "Simulate new recording": writes a sample scam call into [folder] like a call recorder would.
/// Writes to a temporary name first, then renames, so it never looks half-written.
Future<File> simulateRecording(String folder, AssetBundle bundle, {DateTime? now}) async {
  final bytes = BytesBuilder(copy: false);
  for (final a in kSimulateClips) {
    final data = await bundle.load(a);
    bytes.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }
  final t = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  final sep = Platform.pathSeparator;
  final target = File('$folder${sep}ScamRakshak_demo_call_$stamp.mp3');
  final part = File('${target.path}.part');
  await part.writeAsBytes(bytes.takeBytes(), flush: true);
  return part.rename(target.path);
}

/// Stable 31-bit id for a notification about [key] (same in every isolate and run).
int stableNotificationId(String key) {
  var h = 0x811c9dc5;
  for (final c in utf8.encode(key)) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return h == 0 ? 1 : h;
}
