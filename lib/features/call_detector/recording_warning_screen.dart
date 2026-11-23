import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/strings.dart';
import '../live_call/recording_inbox.dart';
import '../report/report_nav.dart';
import '../report/report_screen.dart';
import 'auto_analyze_core.dart';
import 'auto_analyze_service.dart';
import 'call_timeline.dart';
import 'recording_warning_strings.dart';

/// HIGH: deep red with white text; MEDIUM: amber with black text (both high contrast).
const kWarnHighColor = Color(0xFFB71C1C);
const kWarnMediumColor = Color(0xFFFFB300);

/// Opens the full-screen warning for a saved result (go_router when present, else Navigator).
Future<void> openRecordingWarning(BuildContext context, String id) async {
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    await router.push<void>('/call/warning', extra: id);
  } else {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RecordingWarningScreen(resultId: id)));
  }
}

/// Opens the reporting options (existing Report screen) with this recording as evidence.
Future<void> openRecordingReport(BuildContext context, String id) async {
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    await router.push<void>('/call/report', extra: id);
  } else {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RecordingReportScreen(resultId: id)));
  }
}

/// Full-screen scam warning for a newly analysed HIGH/MEDIUM recording (already saved before this
/// opens). Report and Dismiss both keep the saved alert. [RecordingWarningScreen.demo] shows a
/// sample result, labelled DEMO, that is not saved anywhere.
class RecordingWarningScreen extends ConsumerStatefulWidget {
  final String? resultId;
  final CallTimelineResult? demo;
  const RecordingWarningScreen({super.key, required String this.resultId}) : demo = null;
  const RecordingWarningScreen.demo({super.key, required CallTimelineResult this.demo}) : resultId = null;

  @override
  ConsumerState<RecordingWarningScreen> createState() => _RecordingWarningScreenState();
}

class _RecordingWarningScreenState extends ConsumerState<RecordingWarningScreen> {
  StoredRecordingResult? _saved;
  bool _loaded = false;

  /// Read once: `ref` cannot be used in dispose.
  late final AutoAnalyzePlatform _platform = ref.read(autoAnalyzePlatformProvider);

  @override
  void initState() {
    super.initState();
    RecordingWarningStrings.ensure();
    unawaited(_lock(true));
    if (widget.demo != null) {
      _loaded = true;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    unawaited(_lock(false));
    super.dispose();
  }

  /// Warning screens currently open (the next queued one opens before the previous is disposed).
  static int _open = 0;

  /// Over the lock screen only while a warning is open.
  Future<void> _lock(bool on) async {
    _open += on ? 1 : -1;
    if (!on && _open > 0) return;
    final platform = _platform;
    try {
      await platform.setShowWhenLocked(on);
    } catch (_) {}
  }

  Future<void> _load() async {
    final store = await ref.read(autoAnalyzeStoreProvider.future);
    await store.reload();
    final id = widget.resultId!;
    final saved = store.result(id);
    if (saved != null) {
      await store.markWarned(id); // once only, even if opened from an old notification
      await store.markRead(id);
    }
    if (!mounted) return;
    setState(() {
      _saved = saved;
      _loaded = true;
    });
  }

  void _report() {
    final id = widget.resultId;
    if (id == null) {
      openReport(context, type: 'call'); // DEMO: no recording to attach
    } else {
      openRecordingReport(context, id);
    }
  }

  void _dismiss() {
    if (widget.demo != null) {
      Navigator.of(context).pop();
      return;
    }
    // Close the warning (pop, so whoever opened it - e.g. the warning queue - knows it is closed),
    // then show Recording Alerts (the alert stays saved there).
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.pop();
      router.push('/live/inbox');
    } else {
      final nav = Navigator.of(context);
      nav.pop();
      nav.push(MaterialPageRoute<void>(builder: (_) => const RecordingInboxScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    RecordingWarningStrings.ensure();
    final s = S.of(context);
    final r = widget.demo ?? _saved?.result;
    if (!_loaded) return const Scaffold(backgroundColor: kWarnHighColor, body: Center(child: CircularProgressIndicator()));
    if (r == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(s.t('auto_result_missing'), key: const Key('warn_missing'))),
      );
    }
    final high = r.risk == 'high';
    final bg = high ? kWarnHighColor : kWarnMediumColor;
    final fg = high ? Colors.white : Colors.black;
    final type = r.scriptType;
    final phrases = [for (final m in r.result.matches) m.phrase].take(5).toList();
    final big = TextStyle(color: fg, fontSize: 30, fontWeight: FontWeight.w900, height: 1.15);
    final body = TextStyle(color: fg, fontSize: 19, height: 1.35);
    final label = TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.bold);

    return Scaffold(
      key: Key(high ? 'warn_high' : 'warn_medium'),
      backgroundColor: bg,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
          if (widget.demo != null)
            Container(
              key: const Key('warn_demo_banner'),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              color: Colors.black,
              child: Text(s.t('warn_demo_banner'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            ),
          Icon(high ? Icons.gpp_bad_rounded : Icons.warning_amber_rounded, color: fg, size: 88),
          const SizedBox(height: 8),
          Text(s.t(high ? 'warn_title_high' : 'warn_title_medium'),
              key: const Key('warn_title'), textAlign: TextAlign.center, style: big),
          const SizedBox(height: 6),
          Text(s.t('warn_subtitle'), textAlign: TextAlign.center, style: body),
          const SizedBox(height: 18),
          Text('${s.t('warn_score')}: ${(r.score * 100).round()}%',
              key: const Key('warn_score'), textAlign: TextAlign.center, style: big.copyWith(fontSize: 34)),
          if (type != null) ...[
            const SizedBox(height: 6),
            Text('${s.t('warn_type')}: ${s.t('script_$type')}',
                key: const Key('warn_type'), textAlign: TextAlign.center, style: label.copyWith(fontSize: 20)),
          ],
          if (phrases.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(s.t('warn_reasons'), style: label),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in phrases)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: high ? Colors.white : Colors.black,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('"$p"',
                      style: TextStyle(color: high ? kWarnHighColor : Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                ),
            ]),
          ],
          const SizedBox(height: 16),
          Text(s.t(high ? 'warn_advice_high' : 'warn_advice_medium'), key: const Key('warn_advice'), style: body),
          if (_saved != null) ...[
            const SizedBox(height: 12),
            Text('${s.t('warn_recording')}: ${_saved!.fileName}', style: body.copyWith(fontSize: 16)),
            Text('${s.t('warn_time')}: ${_fmt(_saved!.at)}', style: body.copyWith(fontSize: 16)),
            Text(s.t('warn_saved'), key: const Key('warn_saved'), style: body.copyWith(fontSize: 16)),
          ],
          const SizedBox(height: 22),
          FilledButton.icon(
            key: const Key('warn_report'),
            style: FilledButton.styleFrom(
              backgroundColor: high ? Colors.white : Colors.black,
              foregroundColor: high ? kWarnHighColor : Colors.white,
              minimumSize: const Size.fromHeight(64),
            ),
            onPressed: _report,
            icon: const Icon(Icons.report_rounded, size: 28),
            label: Text(s.t('warn_report'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('warn_dismiss'),
            style: OutlinedButton.styleFrom(
              foregroundColor: fg,
              side: BorderSide(color: fg, width: 2),
              minimumSize: const Size.fromHeight(60),
            ),
            onPressed: _dismiss,
            child: Text(s.t('warn_dismiss'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }
}

String _fmt(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}-${two(t.month)}-${t.year} ${two(t.hour)}:${two(t.minute)}';
}

/// Evidence text for a complaint (no audio; the recording stays on the phone).
String recordingEvidenceText(S s, StoredRecordingResult r) {
  final res = r.result;
  final type = res.scriptType;
  return [
    '${s.t('rep_evidence_id')}: ${r.id}',
    '${s.t('warn_recording')}: ${r.fileName}',
    '${s.t('warn_time')}: ${_fmt(r.at)}',
    '${s.t('risk_${res.risk}')} – ${s.t('warn_score')} ${(res.score * 100).round()}%',
    if (type != null) '${s.t('warn_type')}: ${s.t('script_$type')}',
    if (res.result.matches.isNotEmpty) '${s.t('warn_reasons')}: ${res.result.matches.map((m) => m.phrase).join(', ')}',
    '',
    res.transcript,
  ].join('\n');
}

/// The existing Report flow (1930, cybercrime.gov.in, Chakshu, evidence checklist) with this
/// recording pinned below as the evidence to attach (alert id, file, time, verdict, transcript).
class RecordingReportScreen extends ConsumerStatefulWidget {
  final String resultId;
  const RecordingReportScreen({super.key, required this.resultId});

  @override
  ConsumerState<RecordingReportScreen> createState() => _RecordingReportScreenState();
}

class _RecordingReportScreenState extends ConsumerState<RecordingReportScreen> {
  StoredRecordingResult? _saved;

  @override
  void initState() {
    super.initState();
    RecordingWarningStrings.ensure();
    ref.read(autoAnalyzeStoreProvider.future).then((store) async {
      await store.reload();
      if (mounted) setState(() => _saved = store.result(widget.resultId));
    });
  }

  @override
  Widget build(BuildContext context) {
    RecordingWarningStrings.ensure();
    final s = S.of(context);
    final saved = _saved;
    return Scaffold(
      body: Column(children: [
        const Expanded(child: ReportScreen(initialType: 'call')),
        if (saved != null)
          Material(
            key: const Key('rep_evidence'),
            elevation: 8,
            color: const Color(0xFFFFF3E0),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(children: [
                  const Icon(Icons.attach_file_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(s.t('rep_evidence_title'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('${s.t('rep_evidence_id')}: ${saved.id} · ${saved.fileName}',
                          key: const Key('rep_evidence_id'), style: const TextStyle(fontSize: 15)),
                      Text('${s.t('risk_${saved.result.risk}')} · ${(saved.result.score * 100).round()}% · ${_fmt(saved.at)}',
                          style: const TextStyle(fontSize: 15)),
                    ]),
                  ),
                  TextButton(
                    key: const Key('rep_evidence_copy'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: recordingEvidenceText(s, saved)));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(s.t('rep_evidence_copied'))));
                      }
                    },
                    child: Text(s.t('rep_evidence_copy')),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
