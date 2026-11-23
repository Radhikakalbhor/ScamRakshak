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

/// Report Fraud screen: 1930 / cybercrime.gov.in / Chakshu actions, scam type + district,
/// and a persistent evidence checklist.
class ReportScreen extends ConsumerStatefulWidget {
  /// One of [kReportTypes]; preselects the scam type (e.g. 'call' from the call detector).
  final String? initialType;

  /// Opens URLs; injectable for tests.
  final UrlOpener opener;

  const ReportScreen({super.key, this.initialType, this.opener = _defaultOpener});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  late String _type;
  String? _district;
  Set<String> _evidence = {};

  @override
  void initState() {
    super.initState();
    ReportStrings.ensure();
    _type = kReportTypes.contains(widget.initialType) ? widget.initialType! : 'other';
    EvidenceStore.load().then((e) {
      if (mounted) setState(() => _evidence = e);
    });
  }

  /// Fire-and-forget report to the backend; offline / server errors are ignored.
  void _silentReport() {
    final api = ref.read(apiClientProvider);
    unawaited(api.postReport(_type, _district ?? 'unknown').catchError((Object _) {}));
  }

  Future<void> _act(Uri uri) async {
    _silentReport();
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
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('report_type'),
              initialValue: _type,
              isExpanded: true,
              decoration: InputDecoration(labelText: s.t('report_type_label'), border: const OutlineInputBorder()),
              items: [
                for (final t in kReportTypes)
                  DropdownMenuItem(value: t, child: Text(s.t('report_type_$t'))),
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
              items: [
                for (final d in kChhattisgarhDistricts) DropdownMenuItem(value: d, child: Text(d)),
              ],
              onChanged: (v) => setState(() => _district = v),
            ),
            const SizedBox(height: 20),
            Text(s.t('report_actions'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            _action(
              key: const Key('report_action_1930'),
              icon: Icons.call_rounded,
              color: AppTheme.errorRed,
              title: s.t('report_call_1930'),
              sub: s.t('report_call_1930_sub'),
              uri: kHelpline1930,
            ),
            _action(
              key: const Key('report_action_cybercrime'),
              icon: Icons.local_police_rounded,
              color: AppTheme.secondaryNavy,
              title: s.t('report_cybercrime'),
              sub: s.t('report_cybercrime_sub'),
              uri: kCybercrimePortal,
            ),
            _action(
              key: const Key('report_action_chakshu'),
              icon: Icons.visibility_rounded,
              color: AppTheme.primaryTeal,
              title: s.t('report_chakshu'),
              sub: s.t('report_chakshu_sub'),
              uri: kChakshuPortal,
            ),
            const SizedBox(height: 20),
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
          ],
        ),
      ),
    );
  }

  Widget _action({
    required Key key,
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
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 16),
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
