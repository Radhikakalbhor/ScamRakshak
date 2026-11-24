import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/widgets/server_settings.dart';
import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../engine/models.dart';
import '../dashboard/detection_history.dart';
import '../report/report_nav.dart';
import 'auto_analyze_screen.dart';
import 'auto_analyze_strings.dart';
import 'call_highlight.dart';
import 'call_triggers.dart';

typedef AudioPicker = Future<File?> Function();

/// Call-recording formats the backend accepts (POST /transcribe).
const kCallAudioExtensions = ['m4a', 'mp3', 'wav', 'amr', 'ogg', 'aac', '3gp', 'opus'];

/// Thrown by the picker when a file was chosen but has no readable path.
class AudioPickException implements Exception {
  final String message;
  const AudioPickException(this.message);
  @override
  String toString() => message;
}

/// Extension of [path] in lower case ('' if none).
String audioExtension(String path) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// Null when [file] can be uploaded, else the string key of the problem.
String? checkPickedAudio(File? file) {
  if (file == null) return 'call_no_file';
  if (!kCallAudioExtensions.contains(audioExtension(file.path))) return 'call_ext_unsupported';
  return null;
}

Future<File?> _defaultPicker() async {
  // FileType.custom maps each extension to a MIME type; on Android .amr/.3gp/.opus often have
  // none, which hides those files or makes the picker fail. Show every file and check the
  // extension after picking instead.
  final res = await FilePicker.platform.pickFiles(type: FileType.any);
  if (res == null || res.files.isEmpty) return null; // cancelled
  final path = res.files.single.path;
  if (path == null) throw const AudioPickException('no file path from the picker');
  return File(path);
}

/// Lists bundled sample transcripts (assets/samples/*.txt), sorted by path.
Future<List<String>> loadSamplePaths([AssetBundle? bundle]) async {
  final manifest = await AssetManifest.loadFromAssetBundle(bundle ?? rootBundle);
  return manifest
      .listAssets()
      .where((a) => a.startsWith('assets/samples/') && !a.startsWith('assets/samples/live/') && a.endsWith('.txt'))
      .toList()
    ..sort();
}

/// Scam call checker: transcribe a recording via the backend (or use an offline sample)
/// and analyze it with [callAnalyzerProvider].
class CallDetectorScreen extends ConsumerStatefulWidget {
  /// Picks the audio file; injectable for tests.
  final AudioPicker pickAudio;

  /// A recording shared from another app (a private cache copy made by MainActivity). It is analysed
  /// at once and deleted when this screen closes; the original recording is never touched.
  final File? initialAudio;

  /// Whether to show the auto-analyze background card.
  final bool showAutoEntry;

  /// Whether to show the bundled sample call chips.
  final bool showSamples;

  const CallDetectorScreen({
    super.key,
    this.pickAudio = _defaultPicker,
    this.initialAudio,
    this.showAutoEntry = false,
    this.showSamples = false,
  });

  @override
  ConsumerState<CallDetectorScreen> createState() => _CallDetectorScreenState();
}

class _CallDetectorScreenState extends ConsumerState<CallDetectorScreen> {
  late final Future<List<String>> _samples;
  bool _busy = false;
  String? _errorKey;
  String? _errorDetail;
  UploadStage? _stage;
  UploadCancel? _cancel;
  String? _transcript;
  CallResult? _result;

  @override
  void initState() {
    super.initState();
    AutoAnalyzeStrings.ensure();
    _samples = loadSamplePaths();
    final shared = widget.initialAudio;
    if (shared != null) {
      _busy = true;
      ref.read(callAnalyzerProvider.future).then((_) {
        if (mounted) _transcribe(shared);
      }, onError: (Object _) {
        if (mounted) setState(() => _busy = false);
      });
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    final shared = widget.initialAudio;
    if (shared != null) {
      try {
        if (shared.existsSync()) shared.deleteSync(); // our cache copy only
      } catch (_) {}
    }
    super.dispose();
  }

  void _analyze(String transcript, {bool sample = false}) {
    final analyzer = ref.read(callAnalyzerProvider).valueOrNull;
    final result = analyzer?.analyze(transcript);
    setState(() {
      _transcript = transcript;
      _result = result;
      _errorKey = analyzer == null ? 'call_rules_error' : null;
    });
    // Feeds Scam Trends (risk + scam type only, never the transcript).
    if (result != null) recordCallCheck(ref, result, sample: sample);
  }

  Future<void> _pickAndTranscribe() async {
    setState(() {
      _errorKey = null;
      _errorDetail = null;
      _result = null;
      _transcript = null;
    });
    File? file;
    try {
      file = await widget.pickAudio();
    } catch (e) {
      debugPrint('[call] picker failed: $e');
      if (mounted) {
        setState(() {
          _errorKey = 'call_pick_failed';
          _errorDetail = '$e';
        });
      }
      return;
    }
    if (!mounted) return;
    final problem = checkPickedAudio(file);
    if (problem != null) {
      debugPrint('[call] picked ${file?.path}: $problem');
      setState(() {
        _errorKey = problem;
        _errorDetail = file == null ? null : file.path.split(RegExp(r'[\\/]')).last;
      });
      return;
    }
    await _transcribe(file!);
  }

  void _cancelUpload() => _cancel?.cancel();

  Future<void> _transcribe(File file) async {
    final cancel = _cancel = UploadCancel();
    setState(() {
      _busy = true;
      _stage = UploadStage.checking;
      _errorKey = null;
      _errorDetail = null;
      _result = null;
      _transcript = null;
    });
    String? errorKey;
    String? detail;
    String text = '';
    try {
      final res = await transcribeWithChecks(
        ref.read(apiClientProvider),
        file,
        cancel: cancel,
        onStage: (st) {
          if (mounted && identical(_cancel, cancel)) setState(() => _stage = st);
        },
      );
      text = (res['text'] ?? '').toString().trim();
      if (text.isEmpty) errorKey = 'call_empty_transcript';
    } on UploadCancelledException {
      errorKey = 'call_cancelled';
    } on ApiOfflineException catch (e) {
      final url = await ref.read(apiClientProvider).getBaseUrl();
      errorKey = url.isEmpty ? 'call_no_server' : 'call_backend_offline';
      detail = url.isEmpty ? null : '$url — ${e.message}';
    } on ApiException catch (e) {
      errorKey = switch (e.statusCode) {
        400 || 415 => 'call_format_unsupported',
        503 => 'call_server_busy',
        _ => 'call_transcribe_failed',
      };
      detail = 'HTTP ${e.statusCode}';
    } catch (e) {
      errorKey = 'call_transcribe_failed';
      detail = '$e';
    }
    debugPrint('[call] upload ${file.path}: ${errorKey ?? 'ok (${text.length} chars)'} ${detail ?? ''}');
    if (!mounted || !identical(_cancel, cancel)) return;
    setState(() {
      _busy = false;
      _stage = null;
      _cancel = null;
      _errorKey = errorKey;
      _errorDetail = detail;
    });
    if (errorKey == null) _analyze(text);
  }

  Future<void> _useSample(String path) async {
    try {
      final text = await rootBundle.loadString(path);
      if (mounted) _analyze(text.trim(), sample: true);
    } catch (_) {
      if (mounted) setState(() => _errorKey = 'call_transcribe_failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    AutoAnalyzeStrings.ensure();
    final s = S.of(context);
    final rules = ref.watch(callAnalyzerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.t('call_title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(DsSpace.xl, DsSpace.s, DsSpace.xl, DsSpace.section),
          children: [
            const Align(alignment: Alignment.centerLeft, child: ServerStatusChip()),
            const SizedBox(height: DsSpace.m),
            Text(s.t('call_intro'), style: DsType.body),
            const SizedBox(height: DsSpace.l),
            PrimaryButton(
              key: const Key('call_pick'),
              label: s.t('call_pick_audio'),
              icon: Icons.audio_file_outlined,
              busy: _busy,
              onPressed: _busy || !rules.hasValue ? null : _pickAndTranscribe,
            ),
            Padding(
              padding: const EdgeInsets.only(top: DsSpace.s),
              child: Text(
                s.t('call_needs_server').replaceAll('{formats}', kCallAudioExtensions.join(', ')),
                key: const Key('call_needs_server'),
                style: DsType.small,
              ),
            ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(top: DsSpace.m),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      s.t(switch (_stage) {
                        UploadStage.checking => 'call_stage_checking',
                        UploadStage.uploading => 'call_stage_uploading',
                        UploadStage.transcribing => 'call_stage_transcribing',
                        null => 'call_transcribing',
                      }),
                      key: const Key('call_stage'),
                      style: DsType.body,
                    ),
                  ),
                  if (_cancel != null)
                    PillChip(
                      key: const Key('call_cancel'),
                      icon: Icons.close_rounded,
                      label: s.t('call_cancel'),
                      onTap: _cancelUpload,
                    ),
                ]),
              ),
            if (rules.isLoading)
              Padding(padding: const EdgeInsets.only(top: DsSpace.s), child: Text(s.t('call_loading_rules'), style: DsType.small)),
            if (rules.hasError)
              Padding(
                padding: const EdgeInsets.only(top: DsSpace.s),
                child: Text(s.t('call_rules_error'), style: DsType.body.copyWith(color: DsColors.alert)),
              ),
            if (_errorKey != null) _errorBox(_errorText(s)),
            if (_errorKey != null && !_busy && widget.initialAudio != null && widget.initialAudio!.existsSync())
              Padding(
                padding: const EdgeInsets.only(top: DsSpace.s),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PillChip(
                    key: const Key('call_retry_shared'),
                    icon: Icons.refresh_rounded,
                    label: s.t('btn_retry'),
                    onTap: () => _transcribe(widget.initialAudio!),
                  ),
                ),
              ),
            if (widget.showAutoEntry) ...[
              const SizedBox(height: DsSpace.l),
              FeatureCard(
                key: const Key('call_auto_entry'),
                color: DsColors.mint,
                icon: Icons.auto_mode_rounded,
                title: s.t('auto_entry'),
                subtitle: s.t('auto_entry_sub'),
                onTap: () {
                  final router = GoRouter.maybeOf(context);
                  if (router != null) {
                    router.push('/call/auto');
                  } else {
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AutoAnalyzeScreen()));
                  }
                },
              ),
            ],
            if (widget.showSamples) ...[
              const SizedBox(height: DsSpace.xl),
              Text(s.t('call_samples'), style: DsType.greeting),
              const SizedBox(height: DsSpace.s),
              FutureBuilder<List<String>>(
                future: _samples,
                builder: (context, snap) {
                  final paths = snap.data ?? const <String>[];
                  return Wrap(spacing: DsSpace.s, runSpacing: DsSpace.s, children: [
                    for (var i = 0; i < paths.length; i++)
                      PillChip(
                        key: Key('call_sample_$i'),
                        icon: Icons.record_voice_over_outlined,
                        label: '${s.t('call_sample')} ${i + 1}',
                        onTap: _busy || !rules.hasValue ? null : () => _useSample(paths[i]),
                      ),
                  ]);
                },
              ),
            ],
            if (_result != null && _transcript != null) ...[
              const SizedBox(height: DsSpace.xxl),
              _resultView(s, _result!, _transcript!),
            ],
          ],
        ),
      ),
    );
  }

  String _errorText(S s) {
    final msg = s
        .t(_errorKey!)
        .replaceAll('{ext}', _errorDetail == null ? '?' : '.${audioExtension(_errorDetail!)}')
        .replaceAll('{formats}', kCallAudioExtensions.join(', '));
    return _errorDetail == null ? msg : '$msg\n($_errorDetail)';
  }

  Widget _errorBox(String msg) => Padding(
        padding: const EdgeInsets.only(top: DsSpace.m),
        child: SurfacePanel(
          key: const Key('call_error'),
          color: DsColors.cautionSoft,
          padding: const EdgeInsets.all(DsSpace.l),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.wifi_off_rounded, color: DsColors.caution),
            const SizedBox(width: DsSpace.s),
            Expanded(child: Text(msg, style: DsType.body)),
          ]),
        ),
      );

  Widget _resultView(S s, CallResult r, String transcript) {
    final type = mainScriptType(r);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      VerdictBanner(
        key: const Key('call_risk'),
        verdict: riskVerdict(r.risk),
        icon: r.risk == 'low' ? Icons.verified_user_outlined : Icons.phone_locked_outlined,
        title: s.t('risk_${r.risk}'),
        lines: [if (type != null && r.risk != 'low') '${s.t('call_detected_type')}: ${s.t('script_$type')}'],
      ),
      const SizedBox(height: DsSpace.l),
      Text(s.t(callNoteKey(r)), key: const Key('call_note'), style: DsType.body),
      if (r.matches.isNotEmpty) ...[const SizedBox(height: DsSpace.m), CallTriggerList(result: r)],
      const SizedBox(height: DsSpace.xl),
      Text(s.t('call_transcript'), style: DsType.section),
      if (r.matches.isNotEmpty) Text(s.t('call_highlight_note'), style: DsType.small),
      const SizedBox(height: DsSpace.s),
      CallTranscriptCard(transcript: transcript, matches: r.matches, textKey: const Key('call_transcript')),
      if (r.risk != 'low') ...[
        const SizedBox(height: DsSpace.l),
        PrimaryButton(
          key: const Key('call_report'),
          label: s.t('call_report'),
          icon: Icons.report_outlined,
          color: DsColors.alert,
          onPressed: () => openReport(context, type: 'call'),
        ),
      ],
    ]);
  }
}
