import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../engine/models.dart';
import '../dashboard/detection_history.dart';
import '../report/report_nav.dart';
import 'call_highlight.dart';
import 'call_strings.dart';

typedef AudioPicker = Future<File?> Function();

Future<File?> _defaultPicker() async {
  final res = await FilePicker.platform.pickFiles(type: FileType.audio);
  final path = res?.files.single.path;
  return path == null ? null : File(path);
}

/// Lists bundled sample transcripts (assets/samples/*.txt), sorted by path.
Future<List<String>> loadSamplePaths([AssetBundle? bundle]) async {
  final manifest = await AssetManifest.loadFromAssetBundle(bundle ?? rootBundle);
  return manifest.listAssets().where((a) => a.startsWith('assets/samples/') && a.endsWith('.txt')).toList()
    ..sort();
}

/// Scam call checker: transcribe a recording via the backend (or use an offline sample)
/// and analyze it with [callAnalyzerProvider].
class CallDetectorScreen extends ConsumerStatefulWidget {
  /// Picks the audio file; injectable for tests.
  final AudioPicker pickAudio;

  const CallDetectorScreen({super.key, this.pickAudio = _defaultPicker});

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
    CallStrings.ensure();
    _samples = loadSamplePaths();
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
    setState(() => _busy = true);
    String? errorKey;
    String text = '';
    try {
      final res = await ref.read(apiClientProvider).transcribe(file);
      text = (res['text'] ?? '').toString().trim();
      if (text.isEmpty) errorKey = 'call_empty_transcript';
    } on ApiOfflineException {
      errorKey = 'call_backend_offline';
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
    CallStrings.ensure();
    final s = S.of(context);
    final rules = ref.watch(callAnalyzerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.t('call_title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(s.t('call_intro'), style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('call_pick'),
              onPressed: _busy || !rules.hasValue ? null : _pickAndTranscribe,
              icon: const Icon(Icons.audio_file_rounded),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(s.t('call_pick_audio'), style: const TextStyle(fontSize: 18)),
              ),
            ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.t('call_transcribing'))),
                ]),
              ),
            if (rules.isLoading) Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.t('call_loading_rules'))),
            if (rules.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(s.t('call_rules_error'), style: const TextStyle(color: AppTheme.errorRed)),
              ),
            if (_errorKey != null) _errorBox(s.t(_errorKey!)),
            const SizedBox(height: 16),
            Text(s.t('call_samples'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            FutureBuilder<List<String>>(
              future: _samples,
              builder: (context, snap) {
                final paths = snap.data ?? const <String>[];
                return Wrap(spacing: 8, runSpacing: 4, children: [
                  for (var i = 0; i < paths.length; i++)
                    ActionChip(
                      key: Key('call_sample_$i'),
                      avatar: const Icon(Icons.record_voice_over_rounded, size: 18),
                      label: Text('${s.t('call_sample')} ${i + 1}'),
                      onPressed: _busy || !rules.hasValue ? null : () => _useSample(paths[i]),
                    ),
                ]);
              },
            ),
            if (_result != null && _transcript != null) ...[
              const SizedBox(height: 20),
              _resultView(s, _result!, _transcript!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorBox(String msg) => Container(
        key: const Key('call_error'),
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.warningOrange),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.wifi_off_rounded, color: AppTheme.warningOrange),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: const TextStyle(fontSize: 15))),
        ]),
      );

  Color _riskColor(String risk) => switch (risk) {
        'high' => AppTheme.errorRed,
        'medium' => AppTheme.warningOrange,
        _ => AppTheme.successGreen,
      };

  Widget _resultView(S s, CallResult r, String transcript) {
    final color = _riskColor(r.risk);
    final type = mainScriptType(r);
    final pieces = splitHighlights(transcript, r.matches.map((m) => m.phrase));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        key: const Key('call_risk'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(r.risk == 'low' ? Icons.verified_user_rounded : Icons.phone_locked_rounded,
              color: Colors.white, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.t('risk_${r.risk}'),
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              if (type != null && r.risk != 'low')
                Text('${s.t('call_detected_type')}: ${s.t('script_$type')}',
                    style: const TextStyle(color: Colors.white, fontSize: 17)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Text(r.risk == 'low' ? s.t('call_low_note') : s.t('call_advice_high'), style: const TextStyle(fontSize: 16)),
      const SizedBox(height: 16),
      Text(s.t('call_transcript'), style: Theme.of(context).textTheme.titleLarge),
      if (r.matches.isNotEmpty)
        Text(s.t('call_highlight_note'), style: const TextStyle(color: AppTheme.textSecondary)),
      const SizedBox(height: 6),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text.rich(
            key: const Key('call_transcript'),
            TextSpan(children: [
              for (final p in pieces)
                TextSpan(
                  text: p.text,
                  style: p.highlighted
                      ? const TextStyle(
                          backgroundColor: Color(0xFFFFCDD2),
                          color: AppTheme.errorRed,
                          fontWeight: FontWeight.bold)
                      : null,
                ),
            ]),
            style: const TextStyle(fontSize: 17, height: 1.5, color: AppTheme.textPrimary),
          ),
        ),
      ),
      if (r.risk != 'low') ...[
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('call_report'),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.errorRed),
          onPressed: () => openReport(context, type: 'call'),
          icon: const Icon(Icons.report_rounded),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(s.t('call_report'), style: const TextStyle(fontSize: 18)),
          ),
        ),
      ],
    ]);
  }
}
