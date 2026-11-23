import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
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
const kCallAudioExtensions = ['m4a', 'mp3', 'wav', 'amr', 'ogg', 'aac', '3gp'];

Future<File?> _defaultPicker() async {
  // FileType.audio hides .amr/.3gp on some phones, so list the extensions explicitly.
  final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: kCallAudioExtensions);
  final path = res?.files.single.path;
  return path == null ? null : File(path);
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

  const CallDetectorScreen({super.key, this.pickAudio = _defaultPicker, this.initialAudio});

  @override
  ConsumerState<CallDetectorScreen> createState() => _CallDetectorScreenState();
}

class _CallDetectorScreenState extends ConsumerState<CallDetectorScreen> {
  late final Future<List<String>> _samples;
  bool _busy = false;
  String? _errorKey;
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
      _result = null;
      _transcript = null;
    });
    File? file;
    try {
      file = await widget.pickAudio();
    } catch (_) {
      file = null;
    }
    if (!mounted) return;
    if (file == null) {
      setState(() => _errorKey = 'call_no_file');
      return;
    }
    await _transcribe(file);
  }

  Future<void> _transcribe(File file) async {
    setState(() {
      _busy = true;
      _errorKey = null;
      _result = null;
      _transcript = null;
    });
    String? errorKey;
    String text = '';
    try {
      final res = await ref.read(apiClientProvider).transcribe(file);
      text = (res['text'] ?? '').toString().trim();
      if (text.isEmpty) errorKey = 'call_empty_transcript';
    } on ApiOfflineException {
      errorKey = 'call_backend_offline';
    } on ApiException catch (e) {
      errorKey = switch (e.statusCode) {
        400 || 415 => 'call_format_unsupported',
        503 => 'call_server_busy',
        _ => 'call_transcribe_failed',
      };
    } catch (_) {
      errorKey = 'call_transcribe_failed';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errorKey = errorKey;
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
                child: Text(s.t('call_transcribing'), style: DsType.body),
              ),
            if (rules.isLoading)
              Padding(padding: const EdgeInsets.only(top: DsSpace.s), child: Text(s.t('call_loading_rules'), style: DsType.small)),
            if (rules.hasError)
              Padding(
                padding: const EdgeInsets.only(top: DsSpace.s),
                child: Text(s.t('call_rules_error'), style: DsType.body.copyWith(color: DsColors.alert)),
              ),
            if (_errorKey != null) _errorBox(s.t(_errorKey!)),
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
            if (_result != null && _transcript != null) ...[
              const SizedBox(height: DsSpace.xxl),
              _resultView(s, _result!, _transcript!),
            ],
          ],
        ),
      ),
    );
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
