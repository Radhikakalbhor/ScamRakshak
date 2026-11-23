import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import 'report_data.dart';
import 'report_strings.dart';

typedef UrlOpener = Future<bool> Function(Uri uri);

Future<bool> _defaultOpener(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Report Fraud screen. First asks whether money was lost:
/// - lost: call 1930 now, tell the bank, cybercrime.gov.in, evidence checklist;
/// - suspicious (no loss yet): Chakshu on Sanchar Saathi, block and do not reply.
/// Every action also queues an anonymous count (type + district + time) for Scam Trends,
/// kept on the phone until the server can be reached.
class ReportScreen extends ConsumerStatefulWidget {
  /// One of [kReportTypes]; preselects the scam type (e.g. 'call' from the call detector).
  final String? initialType;

  /// Opens URLs; injectable for tests.
  final UrlOpener opener;

  /// 'lost' | 'suspicious' to skip the first question.
  final String? initialSituation;

  const ReportScreen({super.key, this.initialType, this.opener = _defaultOpener, this.initialSituation});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  late String _type;
  String? _district;
  String? _situation;
  Set<String> _evidence = {};
  int _waiting = 0;

  @override
  void initState() {
    super.initState();
    ReportStrings.ensure();
    _type = kReportTypes.contains(widget.initialType) ? widget.initialType! : 'other';
    _situation = kReportSituations.contains(widget.initialSituation) ? widget.initialSituation : null;
    EvidenceStore.load().then((e) {
      if (mounted) setState(() => _evidence = e);
    });
    _flush(); // retry counts queued while offline
  }

  Future<void> _flush() async {
    int left;
    try {
      left = await ReportQueue.flush(ref.read(apiClientProvider));
    } catch (_) {
      left = (await ReportQueue.load()).length;
    }
    if (mounted) setState(() => _waiting = left);
  }

  /// Queues an anonymous count, then tries to send everything waiting. Never blocks the action.
  void _queueReport() {
    unawaited(ReportQueue.add(_type, _district ?? 'unknown').then((_) => _flush()).catchError((Object _) {}));
  }

  Future<void> _act(Uri uri) async {
    _queueReport();
    final messenger = ScaffoldMessenger.of(context);
    final failMsg = S.of(context).t('report_launch_failed');
    bool ok;
    try {
      ok = await widget.opener(uri);
    } catch (_) {
      ok = false;
    }
    if (!ok) messenger.showSnackBar(SnackBar(content: Text(failMsg)));
  }

  void _toggle(String id, bool v) {
    setState(() => v ? _evidence.add(id) : _evidence.remove(id));
    EvidenceStore.set(id, v);
  }

  @override
  Widget build(BuildContext context) {
    ReportStrings.ensure();
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('report_title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(DsSpace.xl, DsSpace.s, DsSpace.xl, DsSpace.section),
          children: [
            Text(s.t('report_intro'), style: DsType.body),
            const SizedBox(height: DsSpace.xl),
            Text(s.t('report_situation_q'), style: DsType.section),
            const SizedBox(height: DsSpace.m),
            _situationChoice(s, 'lost', Icons.money_off_rounded, DsColors.alert, DsColors.alertSoft),
            _situationChoice(s, 'suspicious', Icons.report_gmailerrorred_rounded, DsColors.caution, DsColors.cautionSoft),
            if (_situation != null) ...[
              const SizedBox(height: DsSpace.m),
              DropdownButtonFormField<String>(
                key: const Key('report_type'),
                initialValue: _type,
                isExpanded: true,
                style: DsType.body,
                borderRadius: BorderRadius.circular(DsRadius.tile),
                decoration: InputDecoration(labelText: s.t('report_type_label')),
                items: [
                  for (final t in kReportTypes) DropdownMenuItem(value: t, child: Text(s.t('report_type_$t'))),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: DsSpace.m),
              DropdownButtonFormField<String>(
                key: const Key('report_district'),
                initialValue: _district,
                isExpanded: true,
                style: DsType.body,
                borderRadius: BorderRadius.circular(DsRadius.tile),
                hint: Text(s.t('report_district_hint'), style: DsType.body.copyWith(color: DsColors.muted)),
                decoration: InputDecoration(labelText: s.t('report_district_label')),
                items: [for (final d in kChhattisgarhDistricts) DropdownMenuItem(value: d, child: Text(d))],
                onChanged: (v) => setState(() => _district = v),
              ),
              const SizedBox(height: DsSpace.xxl),
              Text(s.t('report_actions'), style: DsType.section),
              const SizedBox(height: DsSpace.m),
              if (_situation == 'lost') ..._lostSteps(s) else ..._suspiciousSteps(s),
              _anonNote(s),
            ],
          ],
        ),
      ),
    );
  }

  Widget _situationChoice(S s, String id, IconData icon, Color color, Color tint) {
    final selected = _situation == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.s),
      child: Pressable(
        key: Key('report_situation_$id'),
        onTap: () => setState(() => _situation = id),
        child: AnimatedContainer(
          duration: DsMotion.normal,
          curve: DsMotion.curve,
          padding: const EdgeInsets.all(DsSpace.l),
          decoration: BoxDecoration(
            color: selected ? tint : DsColors.surface,
            borderRadius: BorderRadius.circular(DsRadius.card),
            border: Border.all(color: selected ? color : DsColors.line, width: selected ? 2 : 1),
          ),
          child: Row(children: [
            IconBadge(icon, background: color),
            const SizedBox(width: DsSpace.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('report_situation_$id'), style: DsType.title),
                const SizedBox(height: DsSpace.xxs),
                Text(s.t('report_situation_${id}_sub'), style: DsType.small),
              ]),
            ),
            const SizedBox(width: DsSpace.s),
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: color),
          ]),
        ),
      ),
    );
  }

  List<Widget> _lostSteps(S s) => [
        _action(
          key: const Key('report_action_1930'),
          step: 1,
          icon: Icons.call_rounded,
          color: DsColors.alert,
          title: s.t('report_call_1930'),
          sub: s.t('report_call_1930_sub'),
          uri: kHelpline1930,
        ),
        _info(
          key: const Key('report_step_bank'),
          step: 2,
          icon: Icons.account_balance_outlined,
          title: s.t('report_bank'),
          sub: s.t('report_bank_sub'),
        ),
        _action(
          key: const Key('report_action_cybercrime'),
          step: 3,
          icon: Icons.local_police_outlined,
          color: DsColors.ink,
          title: s.t('report_cybercrime'),
          sub: s.t('report_cybercrime_sub'),
          uri: kCybercrimePortal,
        ),
        const SizedBox(height: DsSpace.m),
        Row(children: [
          Expanded(child: Text(s.t('report_evidence_title'), style: DsType.section)),
          Text('${_evidence.length}/${kEvidenceItems.length} ${s.t('report_evidence_progress')}', style: DsType.label),
        ]),
        const SizedBox(height: DsSpace.s),
        SurfacePanel(
          padding: const EdgeInsets.symmetric(vertical: DsSpace.s, horizontal: DsSpace.xs),
          child: Material(
            type: MaterialType.transparency,
            child: Column(children: [
              for (final id in kEvidenceItems)
                CheckboxListTile(
                  key: Key('evidence_$id'),
                  value: _evidence.contains(id),
                  onChanged: (v) => _toggle(id, v ?? false),
                  title: Text(s.t('evidence_$id'), style: DsType.body),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: DsColors.brand,
                ),
            ]),
          ),
        ),
      ];

  List<Widget> _suspiciousSteps(S s) => [
        _action(
          key: const Key('report_action_chakshu'),
          step: 1,
          icon: Icons.visibility_outlined,
          color: DsColors.brand,
          title: s.t('report_chakshu'),
          sub: s.t('report_chakshu_sub'),
          uri: kChakshuPortal,
        ),
        _info(
          key: const Key('report_step_block'),
          step: 2,
          icon: Icons.block_rounded,
          title: s.t('report_block'),
          sub: s.t('report_block_sub'),
        ),
        SurfacePanel(
          color: DsColors.alertSoft,
          padding: const EdgeInsets.symmetric(vertical: DsSpace.xs, horizontal: DsSpace.xs),
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              key: const Key('report_switch_lost'),
              leading: const Icon(Icons.money_off_rounded, color: DsColors.alert),
              title: Text(s.t('report_if_lost_later'), style: DsType.title),
              trailing: const Icon(Icons.chevron_right_rounded, color: DsColors.ink),
              onTap: () => setState(() => _situation = 'lost'),
            ),
          ),
        ),
      ];

  Widget _anonNote(S s) => Padding(
        padding: const EdgeInsets.only(top: DsSpace.m),
        child: Text(
          _waiting > 0 ? '${s.t('report_anon_note')} ${s.t('report_waiting').replaceAll('{n}', '$_waiting')}' : s.t('report_anon_note'),
          key: const Key('report_anon_note'),
          style: DsType.small,
        ),
      );

  Widget _stepBadge(int step) => Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: DsColors.track, shape: BoxShape.circle),
        child: Text('$step', style: DsType.caption.copyWith(color: DsColors.ink)),
      );

  Widget _info({required Key key, required int step, required IconData icon, required String title, required String sub}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: DsSpace.m),
        child: SurfacePanel(
          key: key,
          padding: const EdgeInsets.all(DsSpace.l),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _stepBadge(step),
            const SizedBox(width: DsSpace.m),
            IconBadge(icon, background: DsColors.powder, foreground: DsColors.ink),
            const SizedBox(width: DsSpace.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: DsType.title),
                const SizedBox(height: DsSpace.xs),
                Text(sub, style: DsType.small),
              ]),
            ),
          ]),
        ),
      );

  Widget _action({
    required Key key,
    required int step,
    required IconData icon,
    required Color color,
    required String title,
    required String sub,
    required Uri uri,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: DsSpace.m),
        child: SurfacePanel(
          key: key,
          onTap: () => _act(uri),
          semanticLabel: '$title. $sub',
          padding: const EdgeInsets.all(DsSpace.l),
          child: Row(children: [
            _stepBadge(step),
            const SizedBox(width: DsSpace.m),
            IconBadge(icon, background: color),
            const SizedBox(width: DsSpace.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: DsType.title),
                const SizedBox(height: DsSpace.xs),
                Text(sub, style: DsType.small),
              ]),
            ),
            const SizedBox(width: DsSpace.s),
            const ArrowButton(),
          ]),
        ),
      );
}
