import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../report/report_nav.dart';
import 'auto_analyze_core.dart';
import 'auto_analyze_service.dart';
import 'auto_analyze_strings.dart';
import 'call_highlight.dart';
import 'call_timeline.dart';

final callTimelineProvider = FutureProvider<CallTimeline>((ref) => CallTimeline.load());

final autoAnalyzeNotifierProvider =
    Provider<AutoAnalyzeNotifier>((ref) => LocalAutoAnalyzeNotifier(() => ref.read(localeProvider)));

/// Result of an automatically analysed call recording, opened from its notification.
/// [payload] is the notification payload: {"result": id} or {"pending": path} (backend was offline).
class RecordingResultScreen extends ConsumerStatefulWidget {
  final String? payload;
  const RecordingResultScreen({super.key, this.payload});

  @override
  ConsumerState<RecordingResultScreen> createState() => _RecordingResultScreenState();
}

class _RecordingResultScreenState extends ConsumerState<RecordingResultScreen> {
  String? _resultId;
  String? _pendingPath;
  bool _busy = false;
  String? _errorKey;

  /// Results are written by the service isolate, so re-read shared_preferences first.
  /// Opening a result marks it read in the Live Call Guard history.
  late final Future<AutoAnalyzeStore> _store = ref.read(autoAnalyzeStoreProvider.future).then((s) async {
    await s.reload();
    final id = _resultId;
    if (id != null && s.result(id) != null) await s.markRead(id);
    return s;
  });

  @override
  void initState() {
    super.initState();
    AutoAnalyzeStrings.ensure();
    try {
      final j = jsonDecode(widget.payload ?? '') as Map<String, dynamic>;
      _resultId = j['result'] as String?;
      _pendingPath = j['pending'] as String?;
    } catch (_) {}
  }

  Future<void> _analyzeNow() async {
    final path = _pendingPath;
    if (path == null) return;
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    String? error;
    String? id;
    try {
      final store = await ref.read(autoAnalyzeStoreProvider.future);
      final processor = RecordingProcessor(
        store: store,
        api: ref.read(apiClientProvider),
        timeline: await ref.read(callTimelineProvider.future),
        notifier: ref.read(autoAnalyzeNotifierProvider),
      );
      final r = await processor.process(path, notify: false);
      id = r.id;
      if (id != null) await store.markRead(id); // seen right here
      error = switch (r.status) {
        ProcessStatus.done => null,
        ProcessStatus.offline => 'call_backend_offline',
        ProcessStatus.missing => 'auto_pending_gone',
        ProcessStatus.noSpeech => 'call_empty_transcript',
        _ => 'call_transcribe_failed',
      };
    } catch (_) {
      error = 'call_transcribe_failed';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errorKey = error;
      if (id != null) {
        _resultId = id;
        _pendingPath = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    AutoAnalyzeStrings.ensure();
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('auto_result_title'))),
      body: SafeArea(
        child: FutureBuilder<AutoAnalyzeStore>(
          future: _store,
          builder: (context, snap) {
            if (snap.hasError) return _message(s.t('auto_result_missing'));
            final st = snap.data;
            if (st == null) return const Center(child: CircularProgressIndicator());
            if (_pendingPath != null) return _pendingView(s);
            final id = _resultId;
            final saved = id == null ? null : st.result(id);
            if (saved == null) return _message(s.t('auto_result_missing'));
            return _resultView(s, saved);
          },
        ),
      ),
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, key: const Key('rec_message'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
        ),
      );

  Widget _pendingView(S s) => ListView(padding: const EdgeInsets.all(16), children: [
        Text(s.t('auto_pending_title'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(s.t('auto_pending_body'), style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        Text('${s.t('auto_result_file')}: ${fileNameOf(_pendingPath!)}',
            style: const TextStyle(color: AppTheme.textSecondary)),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('rec_analyze_now'),
          onPressed: _busy ? null : _analyzeNow,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.shield_rounded),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(_busy ? s.t('call_transcribing') : s.t('auto_pending_analyze'), style: const TextStyle(fontSize: 18)),
          ),
        ),
        if (_errorKey != null)
          Container(
            key: const Key('rec_error'),
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.warningOrange),
            ),
            child: Text(s.t(_errorKey!), style: const TextStyle(fontSize: 15)),
          ),
      ]);

  Color _color(String risk) => switch (risk) {
        'high' => AppTheme.errorRed,
        'medium' => AppTheme.warningOrange,
        _ => AppTheme.successGreen,
      };

  Widget _resultView(S s, StoredRecordingResult saved) {
    final r = saved.result;
    final color = _color(r.risk);
    final type = r.scriptType;
    final pct = (r.score * 100).round();
    final first = r.firstAlertAt;
    final pieces = splitHighlights(r.transcript, r.result.matches.map((m) => m.phrase));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        key: const Key('rec_verdict'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(r.risk == 'low' ? Icons.verified_user_rounded : Icons.phone_locked_rounded, color: Colors.white, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.t('risk_${r.risk}'),
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              if (type != null)
                Text('${s.t('call_detected_type')}: ${s.t('script_$type')}',
                    style: const TextStyle(color: Colors.white, fontSize: 17)),
              Text('${s.t('auto_result_score')}: $pct%',
                  key: const Key('rec_score'), style: const TextStyle(color: Colors.white, fontSize: 17)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(value: r.score, minHeight: 10, color: color, backgroundColor: const Color(0xFFE0E0E0)),
      ),
      const SizedBox(height: 8),
      Text('${s.t('auto_result_file')}: ${saved.fileName}', style: const TextStyle(color: AppTheme.textSecondary)),
      if (first != null) Text(s.t('auto_result_first_alert').replaceAll('{n}', '${first + 1}')),
      const SizedBox(height: 12),
      Text(r.risk == 'low' ? s.t('call_low_note') : s.t('call_advice_high'), style: const TextStyle(fontSize: 16)),
      if (r.risk != 'low') ...[
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('rec_report'),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.errorRed),
          onPressed: () => openReport(context, type: 'call'),
          icon: const Icon(Icons.report_rounded),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(s.t('call_report'), style: const TextStyle(fontSize: 18)),
          ),
        ),
      ],
      if (r.points.length > 1) ...[
        const SizedBox(height: 16),
        Text(s.t('auto_result_timeline'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        for (var i = 0; i < r.points.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(Icons.circle, size: 12, color: _color(r.points[i].risk)),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 26, child: Text('${i + 1}.', style: const TextStyle(color: AppTheme.textSecondary))),
              Expanded(
                child: Text(r.points[i].text,
                    style: TextStyle(
                        fontWeight: r.points[i].newMatches.isEmpty ? FontWeight.normal : FontWeight.bold)),
              ),
            ]),
          ),
      ],
      const SizedBox(height: 16),
      Text(s.t('call_transcript'), style: Theme.of(context).textTheme.titleLarge),
      if (r.result.matches.isNotEmpty)
        Text(s.t('call_highlight_note'), style: const TextStyle(color: AppTheme.textSecondary)),
      const SizedBox(height: 6),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text.rich(
            key: const Key('rec_transcript'),
            TextSpan(children: [
              for (final p in pieces)
                TextSpan(
                  text: p.text,
                  style: p.highlighted
                      ? const TextStyle(
                          backgroundColor: Color(0xFFFFCDD2), color: AppTheme.errorRed, fontWeight: FontWeight.bold)
                      : null,
                ),
            ]),
            style: const TextStyle(fontSize: 17, height: 1.5, color: AppTheme.textPrimary),
          ),
        ),
      ),
    ]);
  }
}

/// Wraps the home screen: routes notification taps (verdict -> result screen, "Report" -> /report)
/// and restarts the watcher if the toggle is on but the service was stopped (e.g. app update).
class AutoAnalyzeHost extends ConsumerStatefulWidget {
  final Widget child;
  const AutoAnalyzeHost({super.key, required this.child});

  @override
  ConsumerState<AutoAnalyzeHost> createState() => _AutoAnalyzeHostState();
}

class _AutoAnalyzeHostState extends ConsumerState<AutoAnalyzeHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final platform = ref.read(autoAnalyzePlatformProvider);
    try {
      await platform.listenForTaps(_onTap);
    } catch (_) {}
    try {
      final store = await ref.read(autoAnalyzeStoreProvider.future);
      if (store.enabled && !await platform.isServiceRunning()) await platform.startService(store.locale);
    } catch (_) {}
  }

  void _onTap(String? actionId, String? payload) {
    if (!mounted) return;
    if (actionId == kReportAction) {
      openReport(context, type: 'call');
      return;
    }
    if (payload == null || payload.isEmpty) return;
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.push('/call/recording', extra: payload);
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RecordingResultScreen(payload: payload)));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
