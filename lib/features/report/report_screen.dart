import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
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
          padding: const EdgeInsets.all(16),
          children: [
            Text(s.t('report_intro'), style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 12),
            Text(s.t('report_situation_q'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            _situationChoice(s, 'lost', Icons.money_off_rounded, AppTheme.errorRed),
            _situationChoice(s, 'suspicious', Icons.report_gmailerrorred_rounded, AppTheme.warningOrange),
            if (_situation != null) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('report_type'),
                initialValue: _type,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.t('report_type_label'), border: const OutlineInputBorder()),
                items: [
                  for (final t in kReportTypes) DropdownMenuItem(value: t, child: Text(s.t('report_type_$t'))),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('report_district'),
                initialValue: _district,
                isExpanded: true,
                hint: Text(s.t('report_district_hint')),
                decoration:
                    InputDecoration(labelText: s.t('report_district_label'), border: const OutlineInputBorder()),
                items: [for (final d in kChhattisgarhDistricts) DropdownMenuItem(value: d, child: Text(d))],
                onChanged: (v) => setState(() => _district = v),
              ),
              const SizedBox(height: 20),
              Text(s.t('report_actions'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (_situation == 'lost') ..._lostSteps(s) else ..._suspiciousSteps(s),
              _anonNote(s),
            ],
          ],
        ),
      ),
    );
  }

  Widget _situationChoice(S s, String id, IconData icon, Color color) {
    final selected = _situation == id;
    return Card(
      key: Key('report_situation_$id'),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? color : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _situation = id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('report_situation_$id'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(s.t('report_situation_${id}_sub')),
              ]),
            ),
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
          color: AppTheme.errorRed,
          title: s.t('report_call_1930'),
          sub: s.t('report_call_1930_sub'),
          uri: kHelpline1930,
        ),
        _info(
          key: const Key('report_step_bank'),
          step: 2,
          icon: Icons.account_balance_rounded,
          title: s.t('report_bank'),
          sub: s.t('report_bank_sub'),
        ),
        _action(
          key: const Key('report_action_cybercrime'),
          step: 3,
          icon: Icons.local_police_rounded,
          color: AppTheme.secondaryNavy,
          title: s.t('report_cybercrime'),
          sub: s.t('report_cybercrime_sub'),
          uri: kCybercrimePortal,
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text(s.t('report_evidence_title'), style: Theme.of(context).textTheme.titleLarge)),
          Text('${_evidence.length}/${kEvidenceItems.length} ${s.t('report_evidence_progress')}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 4),
        Card(
          child: Column(children: [
            for (final id in kEvidenceItems)
              CheckboxListTile(
                key: Key('evidence_$id'),
                value: _evidence.contains(id),
                onChanged: (v) => _toggle(id, v ?? false),
                title: Text(s.t('evidence_$id'), style: const TextStyle(fontSize: 16)),
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ]),
        ),
      ];

  List<Widget> _suspiciousSteps(S s) => [
        _action(
          key: const Key('report_action_chakshu'),
          step: 1,
          icon: Icons.visibility_rounded,
          color: AppTheme.primaryTeal,
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
        Card(
          color: const Color(0xFFFFEBEE),
          child: ListTile(
            key: const Key('report_switch_lost'),
            leading: const Icon(Icons.money_off_rounded, color: AppTheme.errorRed),
            title: Text(s.t('report_if_lost_later')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => setState(() => _situation = 'lost'),
          ),
        ),
      ];

  Widget _anonNote(S s) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          _waiting > 0 ? '${s.t('report_anon_note')} ${s.t('report_waiting').replaceAll('{n}', '$_waiting')}' : s.t('report_anon_note'),
          key: const Key('report_anon_note'),
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
      );

  Widget _stepBadge(int step, Color color) => CircleAvatar(
        radius: 13,
        backgroundColor: color,
        child: Text('$step', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      );

  Widget _info({required Key key, required int step, required IconData icon, required String title, required String sub}) =>
      Card(
        key: key,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _stepBadge(step, AppTheme.textSecondary),
            const SizedBox(width: 12),
            Icon(icon, color: AppTheme.secondaryNavy, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(sub, style: Theme.of(context).textTheme.bodyMedium),
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
  }) {
    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _act(uri),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            _stepBadge(step, color),
            const SizedBox(width: 12),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(sub, style: Theme.of(context).textTheme.bodyMedium),
              ]),
            ),
            const Icon(Icons.open_in_new_rounded, color: Color(0xFF90A4AE)),
          ]),
        ),
      ),
    );
  }
}
