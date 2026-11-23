import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../engine/live_call_analyzer.dart';
import '../../engine/models.dart';
import '../../engine/scam_classifier.dart';
import '../call_detector/call_highlight.dart';
import '../call_detector/call_strings.dart';
import '../report/report_screen.dart';
import 'live_call_io.dart';
import 'live_call_strings.dart';
import 'live_risk.dart';
import 'recording_inbox.dart';

/// Live analyzer, loaded once from assets/rules/call_rules.json.
final liveCallAnalyzerProvider = FutureProvider<LiveCallAnalyzer>((ref) => LiveCallAnalyzer.load());

/// Bundled demo scripts: `assets/samples/live/ID.txt` (one ~6 s chunk per line) and
/// `assets/samples/live/audio/ID_NN.mp3` (the same line, spoken).
const kLiveDemoScripts = [
  'scam_digital_arrest',
  'scam_fake_kyc_otp',
  'scam_courier_customs',
  'genuine_family_call',
  'genuine_bank_service',
];

String liveDemoTextAsset(String id) => 'assets/samples/live/$id.txt';
String liveDemoClipAsset(String id, int line) =>
    'assets/samples/live/audio/${id}_${line.toString().padLeft(2, '0')}.mp3';

/// What the screen is doing right now.
enum LivePhase { idle, checking, recording, playing, finishing, done, error }

/// Listens to a call on speaker in 6 s chunks (or plays a bundled demo call) and warns
/// as soon as it sounds like a scam.
class LiveCallScreen extends ConsumerStatefulWidget {
  /// Mic chunk length; also the text-only demo pace when a clip cannot be played.
  final Duration chunk;
  const LiveCallScreen({super.key, this.chunk = const Duration(seconds: 6)});

  @override
  ConsumerState<LiveCallScreen> createState() => _LiveCallScreenState();
}

class _LiveCallScreenState extends ConsumerState<LiveCallScreen> {
  static const consentKey = 'live_call_consent_v1';

  /// Peak level (dBFS) below which a chunk counts as silence and is not uploaded.
  static const double silenceDb = -45;

  /// Consecutive failed uploads (server errors) before listening stops.
  static const int maxUploadFailures = 3;

  bool? _consent;
  bool _demo = true;
  String _script = kLiveDemoScripts.first;

  LivePhase _phase = LivePhase.idle;
  String? _errorKey;
  String? _errorDetail;
  int _part = 0;
  int _total = 0;
  int _pending = 0;
  int _silentRun = 0;
  int _uploadFailures = 0;
  double _level = 0;
  bool _audioFailed = false;
  bool _speaking = false;
  bool _warned = false;
  LiveCallState _state = LiveCallState.empty;
  double? _ml;
  String _risk = 'low';

  String _serverUrl = '';
  bool? _serverOk;
  bool _serverChecking = false;

  LiveCallAnalyzer? _analyzer;
  ScamClassifier? _classifier;
  Completer<void>? _stopSignal;
  Future<void> _uploads = Future.value();
  int _session = 0;
  bool _stopRequested = false;

  // Read once in initState: providers must not be read from dispose().
  late final DemoAudio _audio;
  late final void Function(bool) _wakelock;

  bool get _busy =>
      _phase == LivePhase.checking ||
      _phase == LivePhase.recording ||
      _phase == LivePhase.playing ||
      _phase == LivePhase.finishing;

  @override
  void initState() {
    super.initState();
    LiveCallStrings.ensure();
    CallStrings.ensure();
    _audio = ref.read(demoAudioProvider);
    _wakelock = ref.read(wakelockProvider);
    _loadConsent();
    _loadServerUrl();
  }

  Future<void> _loadConsent() async {
    var ok = false;
    try {
      ok = (await SharedPreferences.getInstance()).getBool(consentKey) ?? false;
    } catch (_) {}
    if (mounted) setState(() => _consent = ok);
  }

  Future<void> _agree() async {
    setState(() => _consent = true);
    try {
      await (await SharedPreferences.getInstance()).setBool(consentKey, true);
    } catch (_) {}
  }

  Future<void> _loadServerUrl() async {
    final url = await ref.read(apiClientProvider).getBaseUrl();
    if (mounted) setState(() => _serverUrl = url);
  }

  @override
  void dispose() {
    _session++;
    _stopRequested = true;
    if (!(_stopSignal?.isCompleted ?? true)) _stopSignal!.complete();
    _audio.stop().catchError((_) {});
    _wakelock(false);
    super.dispose();
  }

  bool _alive(int session) => mounted && session == _session;

  // ---- start / stop / reset ----------------------------------------------------------

  void _resetCall() {
    _analyzer?.reset();
    _state = LiveCallState.empty;
    _ml = null;
    _risk = 'low';
    _warned = false;
    _errorKey = null;
    _errorDetail = null;
    _part = 0;
    _total = 0;
    _pending = 0;
    _silentRun = 0;
    _uploadFailures = 0;
    _level = 0;
    _speaking = false;
    _stopRequested = false;
  }

  Future<void> _start() async {
    final session = ++_session;
    setState(() {
      _resetCall();
      _phase = _demo ? LivePhase.playing : LivePhase.checking;
    });
    try {
      _analyzer ??= await ref.read(liveCallAnalyzerProvider.future);
    } catch (_) {
      if (_alive(session)) _setError('live_engine_error');
      return;
    }
    try {
      _classifier ??= await ref.read(scamClassifierProvider.future);
    } catch (_) {
      _classifier = null; // the phrase rules still work without the text model
    }
    if (!_alive(session)) return;
    _analyzer!.reset();
    _wakelock(true);
    if (_demo) {
      await _runDemo(session);
    } else {
      await _runMic(session);
    }
  }

  /// Stop button. Demo: stops at once. Mic: stops recording, finishes the chunks already recorded.
  Future<void> _stop() async {
    _stopRequested = true;
    if (!(_stopSignal?.isCompleted ?? true)) _stopSignal!.complete();
    _wakelock(false);
    if (_phase == LivePhase.playing) {
      _session++;
      await _audio.stop().catchError((_) {});
      if (mounted) setState(() => _phase = LivePhase.done);
    } else if (_phase == LivePhase.checking) {
      _session++;
      if (mounted) setState(() => _phase = LivePhase.idle);
    }
    // LivePhase.recording: the record loop sees _stopRequested and moves to finishing/done.
  }

  /// Back to idle and an empty screen (used when the sample or mode changes).
  Future<void> _resetToIdle() async {
    _session++;
    _stopRequested = true;
    if (!(_stopSignal?.isCompleted ?? true)) _stopSignal!.complete();
    _wakelock(false);
    await _audio.stop().catchError((_) {});
    if (mounted) {
      setState(() {
        _resetCall();
        _analyzer?.reset();
        _phase = LivePhase.idle;
      });
    }
  }

  void _setError(String key, [String? detail]) {
    _session++;
    _stopRequested = true;
    if (!(_stopSignal?.isCompleted ?? true)) _stopSignal!.complete();
    _wakelock(false);
    if (!mounted) return;
    setState(() {
      _phase = LivePhase.error;
      _errorKey = key;
      _errorDetail = detail;
      _speaking = false;
    });
  }

  // ---- demo mode: bundled clips, fully offline ----------------------------------------

  Future<void> _runDemo(int session) async {
    List<String> lines;
    try {
      lines = (await rootBundle.loadString(liveDemoTextAsset(_script)))
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } catch (_) {
      lines = const [];
    }
    if (!_alive(session)) return;
    if (lines.isEmpty) {
      _setError('live_demo_load_error');
      return;
    }
    setState(() => _total = lines.length);
    for (var i = 0; i < lines.length; i++) {
      if (!_alive(session)) return;
      setState(() {
        _part = i + 1;
        _speaking = true;
      });
      var played = false;
      if (!_audioFailed) {
        try {
          await _audio.play(liveDemoClipAsset(_script, i + 1));
          played = true;
        } catch (_) {
          if (mounted) setState(() => _audioFailed = true);
        }
      }
      if (!played) await Future<void>.delayed(widget.chunk);
      if (!_alive(session)) return;
      setState(() => _speaking = false);
      _onText(lines[i]);
    }
    if (!_alive(session)) return;
    _wakelock(false);
    setState(() => _phase = LivePhase.done);
  }

  // ---- microphone mode ----------------------------------------------------------------

  Future<void> _runMic(int session) async {
    final api = ref.read(apiClientProvider);
    _serverUrl = await api.getBaseUrl();
    final reachable = await api.isReachable();
    if (!_alive(session)) return;
    setState(() => _serverOk = reachable);
    if (!reachable) {
      _setError('live_offline', _serverUrl);
      return;
    }
    final rec = ref.read(chunkRecorderProvider);
    Directory dir;
    try {
      if (!await rec.hasPermission()) {
        if (_alive(session)) _setError('live_mic_denied');
        return;
      }
      dir = await ref.read(liveTempDirProvider)();
    } catch (e) {
      if (_alive(session)) _setError('live_mic_error', '$e');
      return;
    }
    if (!_alive(session)) return;
    setState(() => _phase = LivePhase.recording);
    _uploads = Future.value();
    await _recordLoop(session, api, rec, dir);
  }

  /// Records chunk N+1 while chunk N is uploading (uploads run one after another, in order).
  Future<void> _recordLoop(int session, ApiClient api, ChunkRecorder rec, Directory dir) async {
    var n = 0;
    while (_alive(session) && !_stopRequested) {
      final path = '${dir.path}${Platform.pathSeparator}live_${session}_${n++}.wav';
      _stopSignal = Completer<void>();
      try {
        await rec.start(path);
      } catch (e) {
        _setError('live_mic_error', '$e');
        return;
      }
      if (_alive(session)) setState(() => _part = n);

      // Wait for the chunk to fill, sampling the level for the meter and the silence check.
      var peak = -160.0;
      final tick = Duration(milliseconds: math.max(1, math.min(250, widget.chunk.inMilliseconds)));
      final ticks = (widget.chunk.inMilliseconds / tick.inMilliseconds).ceil();
      for (var k = 0; k < ticks && !_stopRequested && _alive(session); k++) {
        await Future.any([Future<void>.delayed(tick), _stopSignal!.future]);
        try {
          final db = await rec.levelDb();
          if (db.isFinite) peak = math.max(peak, db);
          if (_alive(session)) setState(() => _level = ((db + 60) / 60).clamp(0.0, 1.0));
        } catch (_) {}
      }

      String? done;
      try {
        done = await rec.stop();
      } catch (_) {}
      final file = File(done ?? path);
      if (!_alive(session)) {
        _delete(file);
        return;
      }
      if (peak < silenceDb) {
        _delete(file); // nothing to transcribe
        setState(() => _silentRun++);
      } else {
        setState(() {
          _silentRun = 0;
          _pending++;
        });
        _uploads = _uploads.then((_) => _upload(session, api, file));
      }
    }
    if (!_alive(session)) return;
    _wakelock(false);
    setState(() {
      _level = 0;
      _phase = _pending > 0 ? LivePhase.finishing : LivePhase.done;
    });
  }

  Future<void> _upload(int session, ApiClient api, File file) async {
    try {
      if (!_alive(session)) return;
      final lang = ref.read(localeProvider) == 'en' ? 'auto' : 'hi';
      final r = await api.transcribeChunk(file, lang: lang);
      if (!_alive(session)) return;
      _uploadFailures = 0;
      final text = (r['text'] ?? '').toString().trim();
      if (text.isNotEmpty) _onText(text);
    } on ApiOfflineException catch (e) {
      if (_alive(session)) {
        setState(() => _serverOk = false);
        _setError('live_offline', '$_serverUrl\n${e.message}');
      }
    } on ApiException catch (e) {
      if (_alive(session)) {
        _uploadFailures++;
        if (_uploadFailures >= maxUploadFailures) {
          _setError('live_transcribe_failed', 'HTTP ${e.statusCode}');
        } else {
          setState(() => _errorDetail = 'HTTP ${e.statusCode}');
        }
      }
    } catch (e) {
      if (_alive(session)) {
        _uploadFailures++;
        if (_uploadFailures >= maxUploadFailures) _setError('live_transcribe_failed', '$e');
      }
    } finally {
      _delete(file);
      if (_alive(session)) {
        setState(() {
          _pending = math.max(0, _pending - 1);
          if (_phase == LivePhase.finishing && _pending == 0) _phase = LivePhase.done;
        });
      }
    }
  }

  void _delete(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  // ---- analysis + alert ---------------------------------------------------------------

  void _onText(String text) {
    final s = _analyzer!.add(text);
    double? ml;
    try {
      ml = _classifier?.classify(s.transcript).score;
    } catch (_) {
      ml = null;
    }
    final risk = combinedRisk(s, ml);
    setState(() {
      _state = s;
      _ml = ml;
      _risk = risk;
    });
    if (risk == 'high' && !_warned) {
      _warned = true;
      HapticFeedback.heavyImpact();
      HapticFeedback.vibrate();
      _showAlert();
    }
  }

  Future<void> _showAlert() async {
    final s = S.of(context);
    final report = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppTheme.errorRed,
      pageBuilder: (ctx, _, _) => Material(
        key: const Key('live_alert'),
        color: AppTheme.errorRed,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.warning_rounded, color: Colors.white, size: 110),
                  const SizedBox(height: 16),
                  Text(
                    s.t('live_alert_title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    s.t('live_alert_body'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 24, height: 1.4),
                  ),
                  const SizedBox(height: 36),
                  FilledButton.icon(
                    key: const Key('live_alert_report'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.errorRed,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(true),
                    icon: const Icon(Icons.report_rounded),
                    label: Text(s.t('live_report'), style: const TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const Key('live_alert_dismiss'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(s.t('live_dismiss'), style: const TextStyle(fontSize: 18)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (report == true && mounted) {
      await _stop();
      if (!mounted) return;
      final router = GoRouter.maybeOf(context);
      if (router != null) {
        router.push('/report', extra: 'call');
      } else {
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReportScreen(initialType: 'call')));
      }
    }
  }

  // ---- server address -----------------------------------------------------------------

  Future<void> _testServer() async {
    final api = ref.read(apiClientProvider);
    setState(() => _serverChecking = true);
    final url = await api.getBaseUrl();
    final ok = await api.isReachable();
    if (!mounted) return;
    setState(() {
      _serverUrl = url;
      _serverOk = ok;
      _serverChecking = false;
      if (ok && _errorKey == 'live_offline') {
        _errorKey = null;
        _phase = LivePhase.idle;
      }
    });
  }

  Future<void> _editServer() async {
    final s = S.of(context);
    final ctrl = TextEditingController(text: _serverUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('live_server_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('live_server_help'), style: const TextStyle(fontSize: 14, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('live_server_field'),
              controller: ctrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'http://192.168.1.5:8000', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(s.t('btn_cancel'))),
          FilledButton(
            key: const Key('live_server_save'),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(s.t('live_server_save')),
          ),
        ],
      ),
    );
    if (url == null || !mounted) return;
    var clean = url.trim();
    if (clean.isEmpty) return;
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) clean = 'http://$clean';
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (Uri.tryParse(clean)?.host.isEmpty ?? true) return;
    await ref.read(apiClientProvider).setBaseUrl(clean);
    await _testServer();
  }

  // ---- UI -----------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    LiveCallStrings.ensure();
    CallStrings.ensure();
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('live_title')), actions: const [RecordingInboxButton()]),
      body: SafeArea(
        child: _consent == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: _consent! ? _main(s) : [_consentCard(s)]),
      ),
    );
  }

  Widget _consentCard(S s) => Card(
    key: const Key('live_consent'),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.volume_up_rounded, size: 56, color: AppTheme.primaryTeal),
          const SizedBox(height: 12),
          Text(
            s.t('live_consent_title'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(s.t('live_consent_body'), style: const TextStyle(fontSize: 18, height: 1.45)),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('live_agree'),
            onPressed: _agree,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(s.t('live_agree'), style: const TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _main(S s) => [
    const RecordingInboxSection(),
    const SizedBox(height: 8),
    _modeCard(s),
    const SizedBox(height: 8),
    if (!_demo) _serverCard(s),
    const SizedBox(height: 8),
    _controls(s),
    const SizedBox(height: 8),
    _statusCard(s),
    if (_phase == LivePhase.error && _errorKey != null) _errorCard(s),
    const SizedBox(height: 12),
    _meter(s),
    const SizedBox(height: 12),
    _transcriptCard(s),
  ];

  Widget _modeCard(S s) => Card(
    child: Column(
      children: [
        SwitchListTile(
          key: const Key('live_demo_switch'),
          value: _demo,
          onChanged: _busy
              ? null
              : (v) {
                  setState(() => _demo = v);
                  _resetToIdle();
                },
          title: Text(s.t('live_demo'), style: const TextStyle(fontSize: 16)),
          subtitle: Text(s.t(_demo ? 'live_demo_sub' : 'live_mic_sub')),
          secondary: Icon(_demo ? Icons.play_lesson_rounded : Icons.mic_rounded),
        ),
        if (_demo)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('live_demo_pick'), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final id in kLiveDemoScripts)
                      ChoiceChip(
                        key: Key('live_demo_$id'),
                        label: Text(s.t('live_demo_$id')),
                        selected: _script == id,
                        onSelected: (_) {
                          if (_script == id) return;
                          setState(() => _script = id);
                          _resetToIdle(); // switching sample stops the current one and clears the screen
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _serverCard(S s) {
    final emulatorOnly =
        _serverUrl.contains('10.0.2.2') || _serverUrl.contains('localhost') || _serverUrl.contains('127.0.0.1');
    final (icon, color, text) = _serverChecking
        ? (Icons.sync_rounded, AppTheme.textSecondary, s.t('live_server_checking'))
        : switch (_serverOk) {
            true => (Icons.cloud_done_rounded, AppTheme.successGreen, s.t('live_server_ok')),
            false => (Icons.cloud_off_rounded, AppTheme.errorRed, s.t('live_server_bad')),
            null => (Icons.cloud_queue_rounded, AppTheme.textSecondary, s.t('live_server_unknown')),
          };
    return Card(
      key: const Key('live_server'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(text, key: const Key('live_server_status'), style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_serverUrl, key: const Key('live_server_url'), style: const TextStyle(fontFamily: 'monospace')),
            if (emulatorOnly) ...[
              const SizedBox(height: 6),
              Text(s.t('live_server_emulator_hint'), style: const TextStyle(color: AppTheme.warningOrange, height: 1.35)),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('live_server_test'),
                  onPressed: _serverChecking || _busy ? null : _testServer,
                  icon: const Icon(Icons.network_check_rounded),
                  label: Text(s.t('live_server_test')),
                ),
                TextButton.icon(
                  key: const Key('live_server_edit'),
                  onPressed: _busy ? null : _editServer,
                  icon: const Icon(Icons.edit_rounded),
                  label: Text(s.t('live_server_change')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(S s) {
    if (_busy) {
      return FilledButton.icon(
        key: const Key('live_stop'),
        style: FilledButton.styleFrom(backgroundColor: AppTheme.errorRed),
        onPressed: _phase == LivePhase.finishing ? null : _stop,
        icon: const Icon(Icons.stop_rounded, size: 30),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(s.t('live_stop'), style: const TextStyle(fontSize: 20)),
        ),
      );
    }
    final again = _phase == LivePhase.done || _phase == LivePhase.error;
    return FilledButton.icon(
      key: const Key('live_start'),
      onPressed: _start,
      icon: Icon(again ? Icons.replay_rounded : (_demo ? Icons.play_arrow_rounded : Icons.mic_rounded), size: 30),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          s.t(again ? (_demo ? 'live_replay' : 'live_start_again') : (_demo ? 'live_play' : 'live_start')),
          style: const TextStyle(fontSize: 20),
        ),
      ),
    );
  }

  String _statusText(S s) => switch (_phase) {
    LivePhase.idle => s.t(_demo ? 'live_idle_demo' : 'live_idle'),
    LivePhase.checking => s.t('live_checking'),
    LivePhase.recording => s.t('live_listening').replaceAll('{n}', '$_part'),
    LivePhase.playing =>
      s.t('live_demo_playing').replaceAll('{n}', '$_part').replaceAll('{total}', '$_total'),
    LivePhase.finishing => s.t('live_finishing'),
    LivePhase.done => s.t('live_finished'),
    LivePhase.error => s.t('live_stopped_error'),
  };

  Widget _statusCard(S s) {
    final icon = switch (_phase) {
      LivePhase.recording => Icons.mic_rounded,
      LivePhase.playing => _speaking ? Icons.volume_up_rounded : Icons.graphic_eq_rounded,
      LivePhase.checking || LivePhase.finishing => Icons.hourglass_top_rounded,
      LivePhase.done => Icons.check_circle_rounded,
      LivePhase.error => Icons.error_rounded,
      LivePhase.idle => Icons.info_outline_rounded,
    };
    return Card(
      key: const Key('live_status_card'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: _phase == LivePhase.error ? AppTheme.errorRed : AppTheme.primaryTeal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusText(s),
                    key: const Key('live_status'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (_busy && _phase != LivePhase.recording)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            if (_phase == LivePhase.recording) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(s.t('live_mic_level')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(key: const Key('live_level'), value: _level, minHeight: 8),
                  ),
                ],
              ),
            ],
            if (_pending > 0) ...[
              const SizedBox(height: 6),
              Text(
                s.t('live_processing').replaceAll('{n}', '$_pending'),
                key: const Key('live_pending'),
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ],
            if (_silentRun >= 2 && (_phase == LivePhase.recording || _phase == LivePhase.done)) ...[
              const SizedBox(height: 6),
              Text(
                s.t('live_silent_hint'),
                key: const Key('live_silent_hint'),
                style: const TextStyle(color: AppTheme.warningOrange, height: 1.35),
              ),
            ],
            if (_phase != LivePhase.error && _errorDetail != null && !_demo) ...[
              const SizedBox(height: 6),
              Text(
                '${s.t('live_chunk_failed')} ($_errorDetail)',
                key: const Key('live_chunk_failed'),
                style: const TextStyle(color: AppTheme.warningOrange),
              ),
            ],
            if (_demo && _audioFailed) ...[
              const SizedBox(height: 6),
              Text(
                s.t('live_audio_failed'),
                key: const Key('live_audio_failed'),
                style: const TextStyle(color: AppTheme.warningOrange),
              ),
            ],
            const SizedBox(height: 4),
            Text(s.t('live_not_saved'), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(S s) {
    final offerDemo = !_demo;
    return Card(
      key: Key('live_error_$_errorKey'),
      color: const Color(0xFFFFF8E1),
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _errorKey == 'live_offline' ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
                  color: AppTheme.warningOrange,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(s.t(_errorKey!), style: const TextStyle(fontSize: 16, height: 1.4))),
              ],
            ),
            if (_errorDetail != null) ...[
              const SizedBox(height: 6),
              Text(_errorDetail!, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ],
            if (offerDemo) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('live_use_demo'),
                onPressed: () async {
                  setState(() => _demo = true);
                  await _resetToIdle();
                  await _start();
                },
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(s.t('live_use_demo')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _meter(S s) {
    final color = switch (_risk) {
      'high' => AppTheme.errorRed,
      'medium' => AppTheme.warningOrange,
      _ => AppTheme.successGreen,
    };
    final type = mainScriptType(CallResult(_state.risk, _state.matches));
    final score = _risk == 'high' ? 1.0 : _state.score;
    return Card(
      key: const Key('live_meter'),
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color, width: 2)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('live_risk'), style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                s.t('risk_$_risk'),
                key: const Key('live_risk'),
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: color),
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                key: const Key('live_score'),
                value: score.clamp(0.04, 1.0),
                minHeight: 22,
                color: color,
                backgroundColor: color.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              type == null ? s.t('live_no_type') : '${s.t('call_detected_type')}: ${s.t('script_$type')}',
              key: const Key('live_type'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            // The SMS-trained text model scores any bank/OTP talk high, so it is only shown (and only
            // used, see combinedRisk) once the call-phrase rules have found something.
            if (_ml != null && _state.risk != 'low') ...[
              const SizedBox(height: 6),
              Text(
                s.t('live_ml_score').replaceAll('{p}', '${(_ml! * 100).round()}'),
                key: const Key('live_ml'),
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ],
            if (_risk == 'high') ...[
              const SizedBox(height: 8),
              Text(s.t('call_advice_high'), style: const TextStyle(fontSize: 15, height: 1.4)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _transcriptCard(S s) {
    final t = _state.transcript;
    final pieces = splitHighlights(t, _state.matches.map((m) => m.phrase));
    return Card(
      key: const Key('live_transcript'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('live_transcript'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (t.isEmpty)
              Text(
                s.t(_busy ? 'live_transcript_waiting' : 'live_transcript_empty'),
                key: const Key('live_transcript_empty'),
                style: const TextStyle(color: AppTheme.textSecondary),
              )
            else
              Text.rich(
                key: const Key('live_transcript_text'),
                TextSpan(
                  style: const TextStyle(fontSize: 17, height: 1.5, color: AppTheme.textPrimary),
                  children: [
                    for (final p in pieces)
                      TextSpan(
                        text: p.text,
                        style: p.highlighted
                            ? const TextStyle(
                                backgroundColor: Color(0xFFFFCDD2),
                                color: AppTheme.errorRed,
                                fontWeight: FontWeight.bold,
                              )
                            : null,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
