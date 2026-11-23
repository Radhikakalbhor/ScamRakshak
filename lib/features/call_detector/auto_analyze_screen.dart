import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import 'auto_analyze_core.dart';
import 'auto_analyze_service.dart';
import 'auto_analyze_strings.dart';

/// Lists which [kRecordingFolderCandidates] exist on this phone. Overridable in tests.
final recordingFolderCandidatesProvider = FutureProvider<List<String>>((ref) async {
  final exists = ref.read(folderExistsProvider);
  final out = <String>[];
  for (final c in kRecordingFolderCandidates) {
    try {
      if (await exists(c)) out.add(c);
    } catch (_) {}
  }
  return out;
});

/// Whether a folder exists and can be read. Overridable in tests.
final folderExistsProvider = Provider<Future<bool> Function(String)>((ref) => (p) => Directory(p).exists());

/// Setup and settings for "Auto-analyze new call recordings": consent, folder, permissions, toggle.
class AutoAnalyzeScreen extends ConsumerStatefulWidget {
  const AutoAnalyzeScreen({super.key});

  @override
  ConsumerState<AutoAnalyzeScreen> createState() => _AutoAnalyzeScreenState();
}

class _AutoAnalyzeScreenState extends ConsumerState<AutoAnalyzeScreen> with WidgetsBindingObserver {
  AutoAnalyzeStore? _store;
  bool _files = false;
  bool _notif = false;
  bool _battery = false;
  bool _folderOk = false;
  bool _busy = false;
  String _server = '';

  AutoAnalyzePlatform get _platform => ref.read(autoAnalyzePlatformProvider);

  @override
  void initState() {
    super.initState();
    AutoAnalyzeStrings.ensure();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Returning from a system settings page (All files access, battery) re-checks everything.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<bool> _safe(Future<bool> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return false;
    }
  }

  Future<void> _refresh() async {
    final store = await ref.read(autoAnalyzeStoreProvider.future);
    await store.reload();
    final files = await _safe(_platform.hasAllFilesAccess);
    final notif = await _safe(_platform.hasNotificationPermission);
    final battery = await _safe(_platform.isBatteryUnrestricted);
    final folder = store.folder;
    final exists = ref.read(folderExistsProvider);
    final folderOk = folder != null && await _safe(() => exists(folder));
    String server = '';
    try {
      server = await ref.read(apiClientProvider).getBaseUrl();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _store = store;
      _files = files;
      _notif = notif;
      _battery = battery;
      _folderOk = folderOk;
      _server = server;
    });
  }

  void _snack(String key) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).t(key))));

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
  }

  Future<void> _setFolder(String path) async {
    await _store!.setFolder(path);
  }

  Future<void> _toggle(bool on) => _run(() async {
        final store = _store!;
        if (!on) {
          await store.setEnabled(false);
          try {
            await _platform.stopService();
          } catch (_) {}
          return;
        }
        await store.setEnabled(true);
        final ok = await _safe(() => _platform.startService(ref.read(localeProvider)));
        if (!ok) {
          await store.setEnabled(false);
          if (mounted) _snack('auto_start_failed');
        }
      });

  Future<void> _simulate() => _run(() async {
        try {
          await simulateRecording(_store!.folder!, DefaultAssetBundle.of(context));
          if (mounted) _snack('auto_simulate_done');
        } catch (_) {
          if (mounted) _snack('auto_simulate_failed');
        }
      });

  @override
  Widget build(BuildContext context) {
    AutoAnalyzeStrings.ensure();
    final s = S.of(context);
    final store = _store;
    if (store == null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.t('auto_title'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final consent = store.consent;
    final folder = store.folder;
    final ready = consent && folder != null && _folderOk && _files && _notif;
    final on = store.enabled;
    final candidates = ref.watch(recordingFolderCandidatesProvider).valueOrNull ?? const <String>[];

    return Scaffold(
      appBar: AppBar(title: Text(s.t('auto_title'))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            key: const Key('auto_consent'),
            color: consent ? null : const Color(0xFFFFF8E1),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Icon(Icons.privacy_tip_rounded, color: AppTheme.primaryTeal),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.t('auto_consent_title'), style: Theme.of(context).textTheme.titleLarge)),
                ]),
                const SizedBox(height: 8),
                Text(s.t('auto_consent'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(s.t('auto_consent_more'), style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 10),
                if (consent)
                  Row(children: [
                    const Icon(Icons.check_circle_rounded, color: AppTheme.successGreen),
                    const SizedBox(width: 6),
                    Expanded(child: Text(s.t('auto_consent_agree'))),
                  ])
                else
                  FilledButton(
                    key: const Key('auto_agree'),
                    onPressed: _busy ? null : () => _run(() => store.setConsent(true)),
                    child: Text(s.t('auto_consent_agree')),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          _step(
            n: 1,
            done: folder != null && _folderOk,
            enabled: consent,
            title: s.t('auto_step_folder'),
            body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(folder ?? s.t('auto_step_folder_none'),
                  key: const Key('auto_folder'), style: const TextStyle(color: AppTheme.textSecondary)),
              if (folder != null && !_folderOk)
                Text(s.t('auto_step_folder_missing'), style: const TextStyle(color: AppTheme.errorRed)),
              if (candidates.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(s.t('auto_step_folder_found')),
                Wrap(spacing: 6, children: [
                  for (final c in candidates)
                    ActionChip(
                      label: Text(c.replaceFirst('/storage/emulated/0/', '')),
                      onPressed: !consent || _busy ? null : () => _run(() => _setFolder(c)),
                    ),
                ]),
              ],
              const SizedBox(height: 6),
              OutlinedButton.icon(
                key: const Key('auto_pick_folder'),
                onPressed: !consent || _busy
                    ? null
                    : () => _run(() async {
                          final p = await _platform.pickFolder();
                          if (p != null && p.isNotEmpty) await _setFolder(p);
                        }),
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(s.t('auto_step_folder_pick')),
              ),
            ]),
          ),
          _step(
            n: 2,
            done: _files,
            enabled: consent,
            title: s.t('auto_step_files'),
            body: _permissionBody(s, 'auto_step_files_help', 'auto_allow_files', _files,
                () => _run(() async => _platform.requestAllFilesAccess())),
          ),
          _step(
            n: 3,
            done: _notif,
            enabled: consent,
            title: s.t('auto_step_notif'),
            body: _permissionBody(s, 'auto_step_notif_help', 'auto_allow_notif', _notif,
                () => _run(() async => _platform.requestNotificationPermission())),
          ),
          _step(
            n: 4,
            done: _battery,
            enabled: consent,
            title: s.t('auto_step_battery'),
            body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _permissionBody(s, 'auto_step_battery_help', 'auto_allow_battery', _battery,
                  () => _run(() async => _platform.requestBatteryUnrestricted())),
              TextButton.icon(
                key: const Key('auto_app_settings'),
                onPressed: !consent ? null : () => _run(_platform.openSettings),
                icon: const Icon(Icons.settings_rounded),
                label: Text(s.t('auto_open_settings')),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              key: const Key('auto_toggle'),
              value: on,
              onChanged: _busy || (!on && !ready) ? null : _toggle,
              title: Text(s.t('auto_toggle'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              subtitle: Text(s.t(on ? 'auto_toggle_sub_on' : (ready ? 'auto_toggle_sub_ready' : 'auto_toggle_sub_off'))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text('${s.t('auto_server')}: $_server', style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          const Divider(height: 24),
          OutlinedButton.icon(
            key: const Key('auto_simulate'),
            onPressed: _busy || !on || folder == null ? null : _simulate,
            icon: const Icon(Icons.bug_report_rounded),
            label: Text(s.t('auto_simulate')),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(s.t('auto_simulate_help'), style: const TextStyle(color: AppTheme.textSecondary)),
          ),
        ]),
      ),
    );
  }

  Widget _permissionBody(S s, String helpKey, String buttonKey, bool granted, VoidCallback onAllow) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.t(helpKey), style: const TextStyle(color: AppTheme.textSecondary)),
        if (!granted) ...[
          const SizedBox(height: 6),
          FilledButton.tonal(
            key: Key(buttonKey),
            onPressed: _busy || !(_store?.consent ?? false) ? null : onAllow,
            child: Text(s.t('auto_allow')),
          ),
        ],
      ]);

  Widget _step({
    required int n,
    required bool done,
    required bool enabled,
    required String title,
    required Widget body,
  }) =>
      Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Card(
          key: Key('auto_step_$n'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: done ? AppTheme.successGreen : AppTheme.primaryTeal,
                child: done
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                    : Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  body,
                ]),
              ),
            ]),
          ),
        ),
      );
}
