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
import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../engine/live_call_analyzer.dart';
import '../../engine/models.dart';
import '../../engine/scam_classifier.dart';
import '../call_detector/call_highlight.dart';
import '../call_detector/call_strings.dart';
import '../call_detector/call_triggers.dart';
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
      barrierColor: DsColors.alert,
      pageBuilder: (ctx, _, _) => Material(
        key: const Key('live_alert'),
        color: DsColors.alert,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DsSpace.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: IconBadge(Icons.warning_amber_rounded,
                        size: 96, background: DsColors.onDark, foreground: DsColors.alert),
                  ),
                  const SizedBox(height: DsSpace.l),
                  Text(
                    s.t('live_alert_title'),
                    textAlign: TextAlign.center,
                    style: DsType.displaySmall.copyWith(color: DsColors.onDark),
                  ),
                  const SizedBox(height: DsSpace.m),
                  Text(
                    s.t('live_alert_body'),
                    textAlign: TextAlign.center,
                    style: DsType.cardTitle.copyWith(color: DsColors.onDark),
                  ),
                  const SizedBox(height: DsSpace.section),
                  PrimaryButton(
                    key: const Key('live_alert_report'),
                    label: s.t('live_report'),
                    icon: Icons.report_outlined,
                    color: DsColors.onDark,
                    foreground: DsColors.alert,
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                  const SizedBox(height: DsSpace.m),
                  PrimaryButton(
                    key: const Key('live_alert_dismiss'),
                    label: s.t('live_dismiss'),
                    filled: false,
                    color: DsColors.onDark,
                    onPressed: () => Navigator.of(ctx).pop(false),
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
    final url = await showDsDialog<String>(
      context,
      title: s.t('live_server_title'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('live_server_help'), style: DsType.body),
          const SizedBox(height: DsSpace.m),
          AppTextField(
            key: const Key('live_server_field'),
            controller: ctrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            hint: 'http://192.168.1.5:8000',
          ),
        ],
      ),
      actions: (ctx) => [
        PrimaryButton(
          key: const Key('live_server_save'),
          label: s.t('live_server_save'),
          onPressed: () => Navigator.of(ctx).pop(ctrl.text),
        ),
        PrimaryButton(label: s.t('btn_cancel'), filled: false, onPressed: () => Navigator.of(ctx).pop()),
      ],
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
            ? const LoadingState()
            : ListView(
                padding: const EdgeInsets.fromLTRB(DsSpace.xl, DsSpace.s, DsSpace.xl, DsSpace.section),
                children: _consent! ? _main(s) : [_consentCard(s)],
              ),
      ),
    );
  }

  Widget _consentCard(S s) => PastelCard(
    key: const Key('live_consent'),
    color: DsColors.lavender,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: IconBadge(Icons.volume_up_outlined, size: 64)),
        const SizedBox(height: DsSpace.l),
        Text(s.t('live_consent_title'), textAlign: TextAlign.center, style: DsType.cardTitle),
        const SizedBox(height: DsSpace.m),
        Text(s.t('live_consent_body'), style: DsType.bodyLarge),
        const SizedBox(height: DsSpace.xl),
        PrimaryButton(key: const Key('live_agree'), label: s.t('live_agree'), onPressed: _agree),
      ],
    ),
  );

  List<Widget> _main(S s) => [
    const RecordingInboxSection(),
    const SizedBox(height: DsSpace.m),
    _modeCard(s),
    const SizedBox(height: DsSpace.m),
    if (!_demo) ...[_serverCard(s), const SizedBox(height: DsSpace.m)],
    _controls(s),
    const SizedBox(height: DsSpace.m),
    _statusCard(s),
    if (_phase == LivePhase.error && _errorKey != null) _errorCard(s),
    const SizedBox(height: DsSpace.m),
    _meter(s),
    const SizedBox(height: DsSpace.m),
    _transcriptCard(s),
  ];

  Widget _modeCard(S s) => SurfacePanel(
    padding: const EdgeInsets.symmetric(vertical: DsSpace.s, horizontal: DsSpace.xs),
    child: Material(
      type: MaterialType.transparency,
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
            title: Text(s.t('live_demo'), style: DsType.title),
            subtitle: Text(s.t(_demo ? 'live_demo_sub' : 'live_mic_sub'), style: DsType.small),
            secondary: Icon(_demo ? Icons.play_lesson_outlined : Icons.mic_none_rounded, color: DsColors.ink),
          ),
          if (_demo)
            Padding(
              padding: const EdgeInsets.fromLTRB(DsSpace.l, 0, DsSpace.l, DsSpace.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.t('live_demo_pick'), style: DsType.greeting),
                  const SizedBox(height: DsSpace.s),
                  Wrap(
                    spacing: DsSpace.s,
                    runSpacing: DsSpace.s,
                    children: [
                      for (final id in kLiveDemoScripts)
                        PillChip(
                          key: Key('live_demo_$id'),
                          label: s.t('live_demo_$id'),
                          selected: _script == id,
                          onTap: () {
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
    ),
  );

  Widget _serverCard(S s) {
    final emulatorOnly =
        _serverUrl.contains('10.0.2.2') || _serverUrl.contains('localhost') || _serverUrl.contains('127.0.0.1');
    final (icon, color, text) = _serverChecking
        ? (Icons.sync_rounded, DsColors.muted, s.t('live_server_checking'))
        : switch (_serverOk) {
            true => (Icons.cloud_done_outlined, DsColors.safe, s.t('live_server_ok')),
            false => (Icons.cloud_off_rounded, DsColors.alert, s.t('live_server_bad')),
            null => (Icons.cloud_queue_rounded, DsColors.muted, s.t('live_server_unknown')),
          };
    return SurfacePanel(
      key: const Key('live_server'),
      padding: const EdgeInsets.all(DsSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: DsSpace.s),
              Expanded(
                child: Text(text, key: const Key('live_server_status'), style: DsType.title.copyWith(color: color)),
              ),
            ],
          ),
          const SizedBox(height: DsSpace.xs),
          Text(_serverUrl, key: const Key('live_server_url'), style: DsType.body),
          if (emulatorOnly) ...[
            const SizedBox(height: DsSpace.s),
            Text(s.t('live_server_emulator_hint'), style: DsType.body.copyWith(color: DsColors.caution)),
          ],
          const SizedBox(height: DsSpace.m),
          Wrap(
            spacing: DsSpace.s,
            runSpacing: DsSpace.s,
            children: [
              PillChip(
                key: const Key('live_server_test'),
                icon: Icons.network_check_rounded,
                label: s.t('live_server_test'),
                onTap: _serverChecking || _busy ? null : _testServer,
              ),
              PillChip(
                key: const Key('live_server_edit'),
                icon: Icons.edit_outlined,
                label: s.t('live_server_change'),
                onTap: _busy ? null : _editServer,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _controls(S s) {
    if (_busy) {
      return PrimaryButton(
        key: const Key('live_stop'),
        label: s.t('live_stop'),
        icon: Icons.stop_rounded,
        color: DsColors.alert,
        onPressed: _phase == LivePhase.finishing ? null : _stop,
      );
    }
    final again = _phase == LivePhase.done || _phase == LivePhase.error;
    return PrimaryButton(
      key: const Key('live_start'),
      label: s.t(again ? (_demo ? 'live_replay' : 'live_start_again') : (_demo ? 'live_play' : 'live_start')),
      icon: again ? Icons.replay_rounded : (_demo ? Icons.play_arrow_rounded : Icons.mic_none_rounded),
      onPressed: _start,
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
      LivePhase.recording => Icons.mic_none_rounded,
      LivePhase.playing => _speaking ? Icons.volume_up_outlined : Icons.graphic_eq_rounded,
      LivePhase.checking || LivePhase.finishing => Icons.hourglass_top_rounded,
      LivePhase.done => Icons.check_circle_outline_rounded,
      LivePhase.error => Icons.error_outline_rounded,
      LivePhase.idle => Icons.info_outline_rounded,
    };
    return SurfacePanel(
      key: const Key('live_status_card'),
      padding: const EdgeInsets.all(DsSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _phase == LivePhase.error ? DsColors.alert : DsColors.brand),
              const SizedBox(width: DsSpace.s),
              Expanded(child: Text(_statusText(s), key: const Key('live_status'), style: DsType.title)),
              if (_busy && _phase != LivePhase.recording)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          if (_phase == LivePhase.recording) ...[
            const SizedBox(height: DsSpace.s),
            Row(
              children: [
                Text(s.t('live_mic_level'), style: DsType.small),
                const SizedBox(width: DsSpace.s),
                Expanded(child: ProgressBar(key: const Key('live_level'), value: _level, color: DsColors.brand)),
              ],
            ),
          ],
          if (_pending > 0) ...[
            const SizedBox(height: DsSpace.s),
            Text(s.t('live_processing').replaceAll('{n}', '$_pending'), key: const Key('live_pending'), style: DsType.small),
          ],
          if (_silentRun >= 2 && (_phase == LivePhase.recording || _phase == LivePhase.done)) ...[
            const SizedBox(height: DsSpace.s),
            Text(s.t('live_silent_hint'),
                key: const Key('live_silent_hint'), style: DsType.body.copyWith(color: DsColors.caution)),
          ],
          if (_phase != LivePhase.error && _errorDetail != null && !_demo) ...[
            const SizedBox(height: DsSpace.s),
            Text('${s.t('live_chunk_failed')} ($_errorDetail)',
                key: const Key('live_chunk_failed'), style: DsType.body.copyWith(color: DsColors.caution)),
          ],
          if (_demo && _audioFailed) ...[
            const SizedBox(height: DsSpace.s),
            Text(s.t('live_audio_failed'),
                key: const Key('live_audio_failed'), style: DsType.body.copyWith(color: DsColors.caution)),
          ],
          const SizedBox(height: DsSpace.xs),
          Text(s.t('live_not_saved'), style: DsType.small),
        ],
      ),
    );
  }

  Widget _errorCard(S s) {
    final offerDemo = !_demo;
    return Padding(
      padding: const EdgeInsets.only(top: DsSpace.m),
      child: SurfacePanel(
        key: Key('live_error_$_errorKey'),
        color: DsColors.cautionSoft,
        padding: const EdgeInsets.all(DsSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _errorKey == 'live_offline' ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
                  color: DsColors.caution,
                ),
                const SizedBox(width: DsSpace.s),
                Expanded(child: Text(s.t(_errorKey!), style: DsType.body)),
              ],
            ),
            if (_errorDetail != null) ...[
              const SizedBox(height: DsSpace.s),
              Text(_errorDetail!, style: DsType.caption),
            ],
            if (offerDemo) ...[
              const SizedBox(height: DsSpace.m),
              PrimaryButton(
                key: const Key('live_use_demo'),
                label: s.t('live_use_demo'),
                icon: Icons.play_arrow_rounded,
                filled: false,
                onPressed: () async {
                  setState(() => _demo = true);
                  await _resetToIdle();
                  await _start();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _meter(S s) {
    final verdict = riskVerdict(_risk);
    final color = verdictColor(verdict);
    final tint = switch (verdict) {
      DsVerdict.danger => DsColors.alertSoft,
      DsVerdict.caution => DsColors.cautionSoft,
      DsVerdict.safe => DsColors.safeSoft,
    };
    final type = mainScriptType(CallResult(_state.risk, _state.matches));
    final score = _risk == 'high' ? 1.0 : _state.score;
    return AnimatedContainer(
      key: const Key('live_meter'),
      duration: DsMotion.normal,
      curve: DsMotion.curve,
      padding: const EdgeInsets.all(DsSpace.xl),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(DsRadius.card),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('live_risk'), style: DsType.greeting),
          const SizedBox(height: DsSpace.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              s.t('risk_$_risk'),
              key: const Key('live_risk'),
              style: DsType.headline.copyWith(color: color, fontWeight: DsWeight.semibold),
            ),
          ),
          const SizedBox(height: DsSpace.m),
          ProgressBar(key: const Key('live_score'), value: score.clamp(0.04, 1.0).toDouble(), color: color),
          const SizedBox(height: DsSpace.m),
          Text(
            type == null ? s.t('live_no_type') : '${s.t('call_detected_type')}: ${s.t('script_$type')}',
            key: const Key('live_type'),
            style: DsType.title,
          ),
          // The SMS-trained text model scores any bank/OTP talk high, so it is only shown (and only
          // used, see combinedRisk) once the call-phrase rules have found something.
          if (_ml != null && _state.risk != 'low') ...[
            const SizedBox(height: DsSpace.s),
            Text(s.t('live_ml_score').replaceAll('{p}', '${(_ml! * 100).round()}'), key: const Key('live_ml'), style: DsType.small),
          ],
          if (_risk == 'high') ...[
            const SizedBox(height: DsSpace.s),
            Text(s.t('call_advice_high'), style: DsType.body),
          ],
        ],
      ),
    );
  }

  Widget _transcriptCard(S s) {
    final t = _state.transcript;
    return SurfacePanel(
      key: const Key('live_transcript'),
      padding: const EdgeInsets.all(DsSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('live_transcript'), style: DsType.section),
          const SizedBox(height: DsSpace.s),
          if (t.isEmpty)
            Text(
              s.t(_busy ? 'live_transcript_waiting' : 'live_transcript_empty'),
              key: const Key('live_transcript_empty'),
              style: DsType.small,
            )
          else
            Text.rich(key: const Key('live_transcript_text'), callTranscriptSpan(t, _state.matches), style: DsType.reading),
        ],
      ),
    );
  }
}
