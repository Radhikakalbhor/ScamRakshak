import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import '../live_call/recording_inbox.dart';
import '../report/report_nav.dart';
import '../report/report_screen.dart';
import 'auto_analyze_core.dart';
import 'auto_analyze_service.dart';
import 'call_timeline.dart';
import 'recording_warning_strings.dart';

/// HIGH: solid alert red with white text; MEDIUM: amber with ink text (both high contrast).
const kWarnHighColor = DsColors.alert;
const kWarnMediumColor = DsColors.amber;

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
    if (!_loaded) return const Scaffold(backgroundColor: kWarnHighColor, body: LoadingState());
    if (r == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(s.t('auto_result_missing'), key: const Key('warn_missing'), style: DsType.body)),
      );
    }
    final high = r.risk == 'high';
    final bg = high ? kWarnHighColor : kWarnMediumColor;
    final fg = high ? DsColors.onDark : DsColors.ink;
    final type = r.scriptType;
    final phrases = [for (final m in r.result.matches) m.phrase].take(5).toList();
    final body = DsType.body.copyWith(color: fg, fontSize: 18);
    final small = DsType.body.copyWith(color: fg);
    final label = DsType.section.copyWith(color: fg);

    return Scaffold(
      key: Key(high ? 'warn_high' : 'warn_medium'),
      backgroundColor: bg,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(DsSpace.xl, DsSpace.l, DsSpace.xl, DsSpace.xxl), children: [
          if (widget.demo != null)
            Container(
              key: const Key('warn_demo_banner'),
              margin: const EdgeInsets.only(bottom: DsSpace.m),
              padding: const EdgeInsets.symmetric(vertical: DsSpace.s, horizontal: DsSpace.m),
              decoration: BoxDecoration(color: DsColors.ink, borderRadius: BorderRadius.circular(DsRadius.tile)),
              child: Text(s.t('warn_demo_banner'),
                  textAlign: TextAlign.center, style: DsType.label.copyWith(color: DsColors.onDark, fontSize: 17)),
            ),
          Center(
            child: IconBadge(high ? Icons.gpp_bad_outlined : Icons.warning_amber_rounded,
                size: 88, background: fg, foreground: bg),
          ),
          const SizedBox(height: DsSpace.l),
          Text(s.t(high ? 'warn_title_high' : 'warn_title_medium'),
              key: const Key('warn_title'),
              textAlign: TextAlign.center,
              style: DsType.headline.copyWith(color: fg, fontWeight: DsWeight.semibold)),
          const SizedBox(height: DsSpace.s),
          Text(s.t('warn_subtitle'), textAlign: TextAlign.center, style: body),
          const SizedBox(height: DsSpace.xl),
          Text('${s.t('warn_score')}: ${(r.score * 100).round()}%',
              key: const Key('warn_score'), textAlign: TextAlign.center, style: DsType.number.copyWith(color: fg, fontSize: 36)),
          if (type != null) ...[
            const SizedBox(height: DsSpace.s),
            Text('${s.t('warn_type')}: ${s.t('script_$type')}',
                key: const Key('warn_type'), textAlign: TextAlign.center, style: label),
          ],
          if (phrases.isNotEmpty) ...[
            const SizedBox(height: DsSpace.xl),
            Text(s.t('warn_reasons'), style: label),
            const SizedBox(height: DsSpace.s),
            Wrap(spacing: DsSpace.s, runSpacing: DsSpace.s, children: [
              for (final p in phrases)
                PillChip(label: '"$p"', background: fg, foreground: high ? kWarnHighColor : DsColors.onDark),
            ]),
          ],
          const SizedBox(height: DsSpace.xl),
          Text(s.t(high ? 'warn_advice_high' : 'warn_advice_medium'), key: const Key('warn_advice'), style: body),
          if (_saved != null) ...[
            const SizedBox(height: DsSpace.m),
            Text('${s.t('warn_recording')}: ${_saved!.fileName}', style: small),
            Text('${s.t('warn_time')}: ${_fmt(_saved!.at)}', style: small),
            Text(s.t('warn_saved'), key: const Key('warn_saved'), style: small),
          ],
          const SizedBox(height: DsSpace.xxl),
          PrimaryButton(
            key: const Key('warn_report'),
            label: s.t('warn_report'),
            icon: Icons.report_outlined,
            color: fg,
            foreground: high ? kWarnHighColor : DsColors.onDark,
            onPressed: _report,
          ),
          const SizedBox(height: DsSpace.m),
          PrimaryButton(
            key: const Key('warn_dismiss'),
            label: s.t('warn_dismiss'),
            filled: false,
            color: fg,
            onPressed: _dismiss,
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
          Container(
            key: const Key('rep_evidence'),
            decoration: const BoxDecoration(
              color: DsColors.peach,
              borderRadius: BorderRadius.vertical(top: Radius.circular(DsRadius.card)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(DsSpace.xl, DsSpace.l, DsSpace.m, DsSpace.l),
                child: Row(children: [
                  const IconBadge(Icons.attach_file_rounded),
                  const SizedBox(width: DsSpace.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(s.t('rep_evidence_title'), style: DsType.title),
                      Text('${s.t('rep_evidence_id')}: ${saved.id} · ${saved.fileName}',
                          key: const Key('rep_evidence_id'), style: DsType.body),
                      Text('${s.t('risk_${saved.result.risk}')} · ${(saved.result.score * 100).round()}% · ${_fmt(saved.at)}',
                          style: DsType.small),
                    ]),
                  ),
                  PillChip(
                    key: const Key('rep_evidence_copy'),
                    label: s.t('rep_evidence_copy'),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: recordingEvidenceText(s, saved)));
                      if (context.mounted) showDsToast(context, s.t('rep_evidence_copied'));
                    },
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
