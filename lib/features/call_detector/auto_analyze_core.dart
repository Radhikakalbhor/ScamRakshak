import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
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

/// Files the old "Simulate new recording" button wrote into the watched folder
/// (`ScamRakshak_demo_call_YYYYMMDD_HHMMSS.mp3`, or its `.part` while writing).
final kAppDemoFile = RegExp(r'^ScamRakshak_demo_call_\d{8}_\d{6}\.mp3(\.part)?$');

/// Any ScamRakshak demo/sample name: never a user's call recording.
bool isDemoRecordingName(String name) => name.toLowerCase().startsWith('scamrakshak_demo');

/// Android's MediaStore renames deleted/pending files to `.trashed-<expiry>-<name>` / `.pending-<expiry>-<name>`.
final _mediaStorePrefix = RegExp(r'^\.(trashed|pending)-\d+-');

/// Only genuine, finished call recordings: audio extension, not hidden (MediaStore trash/pending
/// copies, temp files), not an app demo/sample file.
bool isGenuineRecording(String path) {
  final name = fileNameOf(path);
  return isRecordingFile(path) && !name.startsWith('.') && !isDemoRecordingName(name);
}

/// Stable identity of a recording: name (without a MediaStore trash/pending prefix) + size + mtime.
/// The same recording renamed by the system keeps its identity, so it is never analysed twice.
String recordingIdentity(String path, int size, DateTime modified) =>
    'id:${fileNameOf(path).replaceFirst(_mediaStorePrefix, '')}|$size|${modified.millisecondsSinceEpoch}';

/// Where common Android phones save call recordings (shown as suggestions when they exist).
const kRecordingFolderCandidates = [
  '/storage/emulated/0/Recordings/Call', // Samsung (One UI 4+)
  '/storage/emulated/0/Call', // older Samsung
  '/storage/emulated/0/Recordings/Record/Call', // Vivo / iQOO (Android 13+)
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

  /// HIGH/MEDIUM results waiting for their full-screen warning (oldest first).
  static const kWarnQueue = 'auto_rec_warn_queue';

  /// Results whose full-screen warning was already shown (never shown again).
  static const kWarned = 'auto_rec_warned';
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

  /// Processed recordings: paths and [recordingIdentity] keys (persisted, survives restarts).
  List<String> get processed => prefs.getStringList(kProcessed) ?? const [];
  List<String> get pending => prefs.getStringList(kPending) ?? const [];

  /// True when [path] or its [identity] was analysed (or rejected) before.
  bool isProcessed(String path, [String? identity]) {
    final p = processed;
    return p.contains(path) || (identity != null && p.contains(identity));
  }

  Future<void> markProcessed(String path, {String? identity}) async {
    final keys = {path, ?identity};
    final list = [...processed.where((p) => !keys.contains(p)), ...keys];
    await prefs.setStringList(kProcessed, list.length > maxProcessed ? list.sublist(list.length - maxProcessed) : list);
    await removePending(path);
  }

  // ---- Full-screen warnings ----

  List<String> get warnQueue => prefs.getStringList(kWarnQueue) ?? const [];
  Set<String> get warnedIds => (prefs.getStringList(kWarned) ?? const []).toSet();

  /// Queues a HIGH/MEDIUM result for its one-time full-screen warning.
  Future<void> enqueueWarning(String id) async {
    if (warnQueue.contains(id) || warnedIds.contains(id)) return;
    await prefs.setStringList(kWarnQueue, [...warnQueue, id]);
  }

  /// Whether [id] still has to be shown as a full-screen warning.
  bool needsWarning(String id) => warnQueue.contains(id) && !warnedIds.contains(id) && result(id) != null;

  /// Oldest queued warning that still exists, or null.
  String? nextWarning() {
    for (final id in warnQueue) {
      if (needsWarning(id)) return id;
    }
    return null;
  }

  /// Marks the warning for [id] as shown: it is never shown again (the result stays saved).
  Future<void> markWarned(String id) async {
    await prefs.setStringList(kWarnQueue, warnQueue.where((q) => q != id).toList());
    final w = [...warnedIds.where((x) => x != id), id];
    await prefs.setStringList(kWarned, w.length > maxResults ? w.sublist(w.length - maxResults) : w);
  }

  // ---- Diagnostics (shown on the setup screen; logs are hidden on some phones) ----

  static const kDiag = 'auto_rec_diag';
  static const kLastError = 'auto_rec_last_error';
  static const maxDiag = 10;

  /// Last [maxDiag] files seen in the watched folder, newest first.
  List<FileDiagnostic> get diagnostics => [
        for (final raw in prefs.getStringList(kDiag) ?? const <String>[]) ?FileDiagnostic.tryDecode(raw),
      ];

  Future<void> noteFile(String path, bool accepted, String reason, {DateTime? now}) async {
    final d = FileDiagnostic(fileNameOf(path), accepted, reason, now ?? DateTime.now());
    final rest = diagnostics.where((x) => x.name != d.name).take(maxDiag - 1);
    await prefs.setStringList(kDiag, [d.encode(), for (final x in rest) x.encode()]);
  }

  /// Last pipeline error ("time | message"), or null.
  String? get lastError => prefs.getString(kLastError);
  Future<void> setLastError(String message, {DateTime? now}) =>
      prefs.setString(kLastError, '${(now ?? DateTime.now()).toIso8601String().substring(0, 19)} | $message');

  /// Removes saved results whose recording file matches [test] (used to purge app demo files).
  Future<int> removeResultsWhere(bool Function(StoredRecordingResult r) test) async {
    final drop = {for (final r in allResults()) if (test(r)) r.id};
    if (drop.isEmpty) return 0;
    for (final id in drop) {
      await prefs.remove('$kResultPrefix$id');
    }
    await prefs.setStringList(kResults, resultIds.where((id) => !drop.contains(id)).toList());
    await prefs.setStringList(kRead, readIds.where((id) => !drop.contains(id)).toList());
    await prefs.setStringList(kWarnQueue, warnQueue.where((id) => !drop.contains(id)).toList());
    return drop.length;
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

/// One "accepted/rejected + reason" line of the diagnostics list.
class FileDiagnostic {
  final String name;
  final bool accepted;
  final String reason;
  final DateTime at;
  const FileDiagnostic(this.name, this.accepted, this.reason, this.at);

  String encode() => jsonEncode({'n': name, 'a': accepted, 'r': reason, 't': at.millisecondsSinceEpoch});

  static FileDiagnostic? tryDecode(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return FileDiagnostic(j['n'] as String, j['a'] as bool, j['r'] as String,
          DateTime.fromMillisecondsSinceEpoch(j['t'] as int));
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

/// Logs one auto-analyze pipeline step (`adb logcat | grep "\[autoanalyze\]"`, debug builds show it;
/// some phones hide logs of release apps, so decisions are also kept in [AutoAnalyzeStore.diagnostics]).
void aaLog(String msg) => debugPrint('[autoanalyze] $msg');

/// Why a file in the watched folder was (not) picked up.
class FileDecision {
  final String path;
  final bool accepted;
  final String reason;
  const FileDecision(this.path, this.accepted, this.reason);
}

/// Decides which files in the watched folder are new, finished call recordings.
///
/// A file qualifies when it is a genuine recording ([isGenuineRecording]: audio extension, not
/// hidden/trashed/pending, not an app demo file), was modified after the toggle was turned on,
/// is bigger than [minBytes], is not processed yet (by path or by [recordingIdentity]), and its size
/// (and time) stayed the same for [stablePolls] polls in a row (the recorder has finished writing it).
class RecordingWatcher {
  static const minBytes = 20 * 1024;
  static const stablePolls = 3;

  final FolderLister list;
  final Map<String, ({int size, DateTime modified, int count})> _seen = {};

  /// The decision for every file seen in the last poll.
  List<FileDecision> lastDecisions = const [];

  RecordingWatcher({this.list = listFolder});

  /// Why [f] is not (yet) ready, or null when it qualifies on content (stability is checked after).
  static String? rejectReason(RecordingFileInfo f, DateTime since, Set<String> processed) {
    final name = fileNameOf(f.path);
    if (!isRecordingFile(f.path)) return 'not an audio recording';
    if (name.startsWith('.')) return 'hidden/system file (trashed or still pending)';
    if (isDemoRecordingName(name)) return 'ScamRakshak demo file';
    if (processed.contains(f.path) || processed.contains(recordingIdentity(f.path, f.size, f.modified))) {
      return 'already analysed';
    }
    if (!f.modified.isAfter(since)) return 'recorded before auto-analyze was switched on';
    if (f.size <= minBytes) return 'too small (${f.size} bytes)';
    return null;
  }

  /// [processed] holds processed paths and identity keys.
  Future<List<RecordingFileInfo>> poll({
    required String folder,
    required DateTime since,
    required Set<String> processed,
  }) async {
    final files = await list(folder);
    final present = <String>{};
    final ready = <RecordingFileInfo>[];
    final decisions = <FileDecision>[];
    for (final f in files) {
      final reject = rejectReason(f, since, processed);
      if (reject != null) {
        decisions.add(FileDecision(f.path, false, reject));
        continue;
      }
      present.add(f.path);
      final s = _seen[f.path];
      final count = (s != null && s.size == f.size && s.modified == f.modified) ? s.count + 1 : 1;
      _seen[f.path] = (size: f.size, modified: f.modified, count: count);
      if (count >= stablePolls) {
        ready.add(f);
        decisions.add(FileDecision(f.path, true, 'finished recording'));
      } else {
        decisions.add(FileDecision(f.path, false, 'waiting until the recorder finishes ($count/$stablePolls)'));
      }
    }
    _seen.removeWhere((k, _) => !present.contains(k));
    ready.sort((a, b) => a.modified.compareTo(b.modified));
    lastDecisions = decisions;
    return ready;
  }
}

/// Shows the result notifications.
abstract class AutoAnalyzeNotifier {
  Future<void> showVerdict(StoredRecordingResult r);
  Future<void> showOffline(String path);
  Future<void> cancelOffline(String path);
}

enum ProcessStatus { done, offline, failed, noSpeech, missing, busy, skipped }

/// Risk levels that get the full-screen warning (LOW: notification + saved alert only).
bool isWarningRisk(String risk) => risk == 'high' || risk == 'medium';

/// Uploads one finished recording, analyses the transcript and notifies.
class RecordingProcessor {
  /// Pending (offline) recordings are retried every this many polls (3 s each).
  static const retryEvery = 10;

  final AutoAnalyzeStore store;
  final ApiClient api;
  final CallTimeline timeline;
  final AutoAnalyzeNotifier notifier;
  final RecordingWatcher watcher;

  /// Called after a HIGH/MEDIUM result was saved and queued (service: tells the open app at once).
  final void Function(String resultId)? onWarning;
  final _inFlight = <String>{};
  final _lastReason = <String, String>{};
  int _ticks = 0;
  bool _cleaned = false;

  RecordingProcessor({
    required this.store,
    required this.api,
    required this.timeline,
    required this.notifier,
    RecordingWatcher? watcher,
    this.onWarning,
  }) : watcher = watcher ?? RecordingWatcher();

  /// Runs [step]; a failure is logged and kept as the last error, never stopping later steps.
  Future<bool> _step(String name, Future<void> Function() step) async {
    try {
      await step();
      return true;
    } catch (e) {
      aaLog('step "$name" failed: $e');
      try {
        await store.setLastError('$name: $e');
      } catch (_) {}
      return false;
    }
  }

  Future<void> _note(String path, bool accepted, String reason) async {
    if (_lastReason[path] == reason) return;
    _lastReason[path] = reason;
    // Keep "analysed: HIGH 90%" visible instead of the following polls' "already analysed".
    if (reason == 'already analysed') {
      final name = fileNameOf(path);
      if (store.diagnostics.any((d) => d.name == name && d.accepted)) return;
    }
    aaLog('${accepted ? 'ACCEPT' : 'skip'} ${fileNameOf(path)}: $reason');
    await _step('diagnostics', () => store.noteFile(path, accepted, reason));
  }

  /// One poll of the watched folder. Returns false when the feature is switched off.
  Future<bool> tick() async {
    await store.reload();
    final folder = store.folder;
    final since = store.enabledAt;
    if (!store.enabled || folder == null || since == null) {
      aaLog('poll: off (enabled=${store.enabled}, folder=$folder)');
      return false;
    }
    _ticks++;
    if (!_cleaned) {
      _cleaned = true;
      aaLog('watching $folder for recordings made after $since');
      await _step('demo cleanup', () async {
        final n = await cleanUpDemoRecordings(store, list: watcher.list); // left by the old Simulate button
        if (n > 0) aaLog('removed $n ScamRakshak demo file(s) from the folder');
      });
    }
    List<RecordingFileInfo> ready = const [];
    final listed = await _step('list folder', () async {
      ready = await watcher.poll(folder: folder, since: since, processed: store.processed.toSet());
    });
    if (!listed) return true;
    if (_ticks % 20 == 1) aaLog('poll #$_ticks: ${watcher.lastDecisions.length} file(s), ${ready.length} ready');
    for (final d in watcher.lastDecisions) {
      await _note(d.path, d.accepted, d.reason);
    }
    final pending = store.pending.toSet();
    bool? online;
    for (final f in ready) {
      if (pending.contains(f.path)) {
        if (_ticks % retryEvery != 0) continue;
        online ??= await api.isReachable();
        aaLog('retry ${fileNameOf(f.path)}: server ${online ? 'reachable' : 'NOT reachable'}');
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

  /// Analyses [path] at most once (by path and [recordingIdentity]). With [notify] false (opened
  /// from the app) no verdict notification and no full-screen warning are raised.
  ///
  /// Order: save -> mark processed -> queue warning -> notification -> tell the app. Every step is
  /// separate: the notification is posted even if saving or queueing failed.
  Future<({ProcessStatus status, String? id})> process(String path, {bool notify = true}) async {
    if (!_inFlight.add(path)) return (status: ProcessStatus.busy, id: null);
    try {
      final file = File(path);
      if (!await file.exists()) {
        await store.removePending(path);
        await _step('cancel offline', () => notifier.cancelOffline(path));
        return (status: ProcessStatus.missing, id: null);
      }
      if (!isGenuineRecording(path)) {
        await store.markProcessed(path); // demo/hidden/temp file: never analysed
        await _step('cancel offline', () => notifier.cancelOffline(path));
        await _note(path, false, 'not a call recording');
        return (status: ProcessStatus.skipped, id: null);
      }
      final st = await file.stat();
      final identity = recordingIdentity(path, st.size, st.modified);
      await store.reload();
      if (store.isProcessed(path, identity)) {
        await store.removePending(path);
        await _step('cancel offline', () => notifier.cancelOffline(path));
        await _note(path, false, 'already analysed');
        return (status: ProcessStatus.skipped, id: null);
      }
      // Quick /health check first: an unreachable server (wrong address, PC off, other Wi-Fi) would
      // otherwise block the watcher for the whole 5-minute upload timeout with no notification at all.
      var reachable = false;
      try {
        reachable = await api.isReachable();
      } catch (_) {}
      if (!reachable) {
        aaLog('server NOT reachable at ${await _server()}: ${fileNameOf(path)} waits');
        await _step('error', () async => store.setLastError('Server not reachable: ${await _server()}'));
        await _note(path, false, 'waiting: server not reachable (${await _server()})');
        return (status: await _offline(path, notify), id: null);
      }
      aaLog('upload ${fileNameOf(path)} (${st.size} bytes) to ${await _server()}');
      Map res;
      try {
        // Streams the original file; nothing is copied, and the server deletes its temp copy.
        res = await api.transcribeRecording(file);
      } on ApiOfflineException catch (e) {
        aaLog('upload failed: server not reachable ($e)');
        await _step('error', () async => store.setLastError('Server not reachable: ${await _server()}'));
        await _note(path, false, 'waiting: server not reachable (${await _server()})');
        return (status: await _offline(path, notify), id: null);
      } on ApiException catch (e) {
        aaLog('upload failed: HTTP ${e.statusCode} ${e.message}');
        await _step('error', () => store.setLastError('Server error ${e.statusCode}: ${e.message}'));
        if (e.statusCode >= 500) {
          await _note(path, false, 'waiting: server error ${e.statusCode}');
          return (status: await _offline(path, notify), id: null);
        }
        await store.markProcessed(path, identity: identity); // unsupported / broken file: never retry
        await _step('cancel offline', () => notifier.cancelOffline(path));
        await _note(path, false, 'server could not read it (${e.statusCode})');
        return (status: ProcessStatus.failed, id: null);
      }
      final text = (res['text'] ?? '').toString().trim();
      aaLog('transcribed ${fileNameOf(path)}: ${text.length} chars');
      await store.reload();
      // Another isolate (app "Analyze now" vs. the service) finished it meanwhile: keep one result.
      if (store.isProcessed(path, identity)) return (status: ProcessStatus.skipped, id: null);
      if (text.isEmpty) {
        await store.markProcessed(path, identity: identity);
        await _step('cancel offline', () => notifier.cancelOffline(path));
        await _note(path, false, 'no speech in the recording');
        return (status: ProcessStatus.noSpeech, id: null);
      }
      final analysis = timeline.analyze(text);
      final pct = (analysis.score * 100).round();
      aaLog('analysed ${fileNameOf(path)}: ${analysis.risk.toUpperCase()} $pct%');
      final warn = notify && isWarningRisk(analysis.risk);

      // 1. Save to Recording Alerts first (nothing is lost if the app is killed later).
      String? id;
      await _step('save result', () async => id = await store.saveResult(path, analysis));
      // 2. Never analyse it again.
      await _step('mark processed', () => store.markProcessed(path, identity: identity));
      // 3. Queue the one-time full-screen warning (HIGH/MEDIUM).
      if (warn && id != null) await _step('queue warning', () => store.enqueueWarning(id!));
      await _step('cancel offline', () => notifier.cancelOffline(path));
      // 4. The verdict notification: posted even if the steps above failed.
      if (notify) {
        final shown = (id == null ? null : _safeResult(id!)) ??
            StoredRecordingResult(id ?? 'unsaved', path, DateTime.now(), analysis);
        final ok = await _step('post notification', () => notifier.showVerdict(shown));
        aaLog(ok ? 'notification posted (${analysis.risk})' : 'notification FAILED');
      }
      // 5. Tell the open app to show the warning now (no-op when the app is closed).
      if (warn && id != null) {
        await _step('notify app', () async => onWarning?.call(id!));
        aaLog('warning queued for result $id');
      }
      await _note(path, true, 'analysed: ${analysis.risk.toUpperCase()} $pct%');
      return (status: ProcessStatus.done, id: id);
    } catch (e) {
      aaLog('process ${fileNameOf(path)} crashed: $e');
      await _step('error', () => store.setLastError('${fileNameOf(path)}: $e'));
      return (status: ProcessStatus.failed, id: null);
    } finally {
      _inFlight.remove(path);
    }
  }

  StoredRecordingResult? _safeResult(String id) {
    try {
      return store.result(id);
    } catch (_) {
      return null;
    }
  }

  Future<String> _server() async {
    try {
      return await api.getBaseUrl();
    } catch (_) {
      return '?';
    }
  }

  Future<ProcessStatus> _offline(String path, bool notify) async {
    final already = store.pending.contains(path);
    await store.addPending(path); // stays unprocessed
    if (notify && !already) {
      final ok = await _step('post offline notification', () => notifier.showOffline(path));
      aaLog(ok ? 'offline notification posted' : 'offline notification FAILED');
    }
    return ProcessStatus.offline;
  }
}

/// Removes what the old "Simulate new recording" button left: its demo files in the watched folder
/// (only exact [kAppDemoFile] names, never user files) and their results in the alert history.
/// Returns the number of files deleted.
Future<int> cleanUpDemoRecordings(AutoAnalyzeStore store, {FolderLister list = listFolder}) async {
  await store.removeResultsWhere((r) => isDemoRecordingName(r.fileName));
  final folder = store.folder;
  if (folder == null) return 0;
  var n = 0;
  try {
    for (final f in await list(folder)) {
      if (!kAppDemoFile.hasMatch(fileNameOf(f.path))) continue;
      try {
        await File(f.path).delete();
        n++;
      } catch (_) {}
      await store.markProcessed(f.path);
    }
  } catch (_) {}
  return n;
}

/// Bundled sample transcript used by the DEMO warning (never written to the watched folder).
const kDemoTranscriptAsset = 'assets/samples/live/scam_fake_kyc_otp.txt';

/// DEMO: analyses the bundled sample scam call in memory. Nothing is saved, queued or notified.
Future<CallTimelineResult> demoWarningResult(AssetBundle bundle, CallTimeline timeline) async =>
    timeline.analyze(await bundle.loadString(kDemoTranscriptAsset));

/// Stable 31-bit id for a notification about [key] (same in every isolate and run).
int stableNotificationId(String key) {
  var h = 0x811c9dc5;
  for (final c in utf8.encode(key)) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return h == 0 ? 1 : h;
}
