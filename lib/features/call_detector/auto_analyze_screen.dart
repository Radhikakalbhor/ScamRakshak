import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import 'auto_analyze_core.dart';
import 'auto_analyze_service.dart';
import 'recording_result_screen.dart' show callTimelineProvider;
import 'recording_warning_screen.dart';
import 'recording_warning_strings.dart';

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
  bool _fsi = false;
  bool _folderOk = false;
  bool _busy = false;
  String _server = '';

  AutoAnalyzePlatform get _platform => ref.read(autoAnalyzePlatformProvider);

  @override
  void initState() {
    super.initState();
    RecordingWarningStrings.ensure();
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
    final fsi = await _safe(_platform.canUseFullScreenIntent);
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
      _fsi = fsi;
      _folderOk = folderOk;
      _server = server;
    });
  }

  void _snack(String key) => showDsToast(context, S.of(context).t(key));

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

  /// DEMO: the full-screen warning for a bundled sample call. Never touches the watched folder,
  /// the processed list or Recording Alerts, and posts no notification.
  Future<void> _demo() async {
    final bundle = DefaultAssetBundle.of(context);
    final router = GoRouter.maybeOf(context);
    final nav = Navigator.of(context);
    final result = await demoWarningResult(bundle, await ref.read(callTimelineProvider.future));
    if (!mounted) return;
    // Through go_router when present, so Report (also a go_router route) stacks on top of it.
    if (router != null) {
      await router.push<void>('/call/warning/demo', extra: result);
    } else {
      await nav.push(MaterialPageRoute<void>(builder: (_) => RecordingWarningScreen.demo(demo: result)));
    }
  }

  @override
  Widget build(BuildContext context) {
    RecordingWarningStrings.ensure();
    final s = S.of(context);
    final store = _store;
    if (store == null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.t('auto_title'))),
        body: const LoadingState(),
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
        child: ListView(padding: const EdgeInsets.fromLTRB(DsSpace.xl, DsSpace.s, DsSpace.xl, DsSpace.section), children: [
          PastelCard(
            key: const Key('auto_consent'),
            color: consent ? DsColors.mint : DsColors.peach,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const IconBadge(Icons.privacy_tip_outlined),
                const SizedBox(width: DsSpace.m),
                Expanded(child: Text(s.t('auto_consent_title'), style: DsType.cardTitle)),
              ]),
              const SizedBox(height: DsSpace.m),
              Text(s.t('auto_consent'), style: DsType.title),
              const SizedBox(height: DsSpace.s),
              Text(s.t('auto_consent_more'), style: DsType.body),
              const SizedBox(height: DsSpace.l),
              if (consent)
                Row(children: [
                  const Icon(Icons.check_circle_outline_rounded, color: DsColors.safe),
                  const SizedBox(width: DsSpace.s),
                  Expanded(child: Text(s.t('auto_consent_agree'), style: DsType.title)),
                ])
              else
                PrimaryButton(
                  key: const Key('auto_agree'),
                  label: s.t('auto_consent_agree'),
                  onPressed: _busy ? null : () => _run(() => store.setConsent(true)),
                ),
            ]),
          ),
          const SizedBox(height: DsSpace.m),
          _step(
            n: 1,
            done: folder != null && _folderOk,
            enabled: consent,
            title: s.t('auto_step_folder'),
            body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(folder ?? s.t('auto_step_folder_none'), key: const Key('auto_folder'), style: DsType.small),
              if (folder != null && !_folderOk)
                Text(s.t('auto_step_folder_missing'), style: DsType.body.copyWith(color: DsColors.alert)),
              if (candidates.isNotEmpty) ...[
                const SizedBox(height: DsSpace.s),
                Text(s.t('auto_step_folder_found'), style: DsType.small),
                const SizedBox(height: DsSpace.xs),
                Wrap(spacing: DsSpace.s, runSpacing: DsSpace.s, children: [
                  for (final c in candidates)
                    PillChip(
                      label: c.replaceFirst('/storage/emulated/0/', ''),
                      icon: Icons.folder_outlined,
                      onTap: !consent || _busy ? null : () => _run(() => _setFolder(c)),
                    ),
                ]),
              ],
              const SizedBox(height: DsSpace.s),
              PillChip(
                key: const Key('auto_pick_folder'),
                icon: Icons.folder_open_outlined,
                label: s.t('auto_step_folder_pick'),
                onTap: !consent || _busy
                    ? null
                    : () => _run(() async {
                          final p = await _platform.pickFolder();
                          if (p != null && p.isNotEmpty) await _setFolder(p);
                        }),
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
              const SizedBox(height: DsSpace.s),
              PillChip(
                key: const Key('auto_app_settings'),
                icon: Icons.settings_outlined,
                label: s.t('auto_open_settings'),
                onTap: !consent ? null : () => _run(_platform.openSettings),
              ),
            ]),
          ),
          _step(
            n: 5,
            done: _fsi,
            enabled: consent,
            title: s.t('auto_step_fsi'),
            body: _permissionBody(s, 'auto_step_fsi_help', 'auto_allow_fsi', _fsi,
                () => _run(_platform.openFullScreenIntentSettings)),
          ),
          const SizedBox(height: DsSpace.s),
          SurfacePanel(
            color: on ? DsColors.mint : DsColors.surface,
            padding: const EdgeInsets.symmetric(vertical: DsSpace.s, horizontal: DsSpace.xs),
            child: Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                key: const Key('auto_toggle'),
                value: on,
                onChanged: _busy || (!on && !ready) ? null : _toggle,
                title: Text(s.t('auto_toggle'), style: DsType.title),
                subtitle: Text(s.t(on ? 'auto_toggle_sub_on' : (ready ? 'auto_toggle_sub_ready' : 'auto_toggle_sub_off')),
                    style: DsType.small),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DsSpace.xs, vertical: DsSpace.s),
            child: Text('${s.t('auto_server')}: $_server', style: DsType.small),
          ),
          _diagnosticsCard(s, store),
          const SizedBox(height: DsSpace.xl),
          PrimaryButton(
            key: const Key('auto_demo_warning'),
            label: s.t('auto_demo'),
            icon: Icons.science_outlined,
            filled: false,
            onPressed: _busy ? null : _demo,
          ),
          Padding(
            padding: const EdgeInsets.only(top: DsSpace.s),
            child: Text(s.t('auto_demo_help'), style: DsType.small),
          ),
        ]),
      ),
    );
  }

  /// Last 10 files the watcher saw (accepted/rejected + reason) and the last error.
  Widget _diagnosticsCard(S s, AutoAnalyzeStore store) {
    final diag = store.diagnostics;
    final err = store.lastError;
    String two(int v) => v.toString().padLeft(2, '0');
    return SurfacePanel(
      key: const Key('auto_diag'),
      padding: const EdgeInsets.all(DsSpace.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(s.t('auto_diag_title'), style: DsType.section)),
          ArrowButton(
            key: const Key('auto_diag_refresh'),
            icon: Icons.refresh_rounded,
            semanticLabel: s.t('auto_diag_refresh'),
            onTap: _refresh,
          ),
        ]),
        const SizedBox(height: DsSpace.s),
        if (err != null)
          Container(
            key: const Key('auto_diag_error'),
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: DsSpace.s),
            padding: const EdgeInsets.all(DsSpace.m),
            decoration: BoxDecoration(color: DsColors.alertSoft, borderRadius: BorderRadius.circular(DsRadius.tile)),
            child: Text('${s.t('auto_diag_last_error')}: $err', style: DsType.body),
          ),
        if (diag.isEmpty) Text(s.t('auto_diag_empty'), style: DsType.small),
        for (final d in diag)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DsSpace.xs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(d.accepted ? Icons.check_circle_outline_rounded : Icons.remove_circle_outline_rounded,
                  size: 18, color: d.accepted ? DsColors.safe : DsColors.muted),
              const SizedBox(width: DsSpace.s),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: d.name, style: DsType.title.copyWith(fontSize: 15)),
                  TextSpan(
                      text: '\n${two(d.at.hour)}:${two(d.at.minute)}:${two(d.at.second)} · '
                          '${s.t(d.accepted ? 'auto_diag_accepted' : 'auto_diag_rejected')}: ${d.reason}',
                      style: DsType.small),
                ])),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _permissionBody(S s, String helpKey, String buttonKey, bool granted, VoidCallback onAllow) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.t(helpKey), style: DsType.small),
        if (!granted) ...[
          const SizedBox(height: DsSpace.s),
          PillChip(
            key: Key(buttonKey),
            label: s.t('auto_allow'),
            background: DsColors.brand,
            foreground: DsColors.onDark,
            onTap: _busy || !(_store?.consent ?? false) ? null : onAllow,
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
        child: Padding(
          padding: const EdgeInsets.only(bottom: DsSpace.s),
          child: SurfacePanel(
            key: Key('auto_step_$n'),
            padding: const EdgeInsets.all(DsSpace.l),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: done ? DsColors.safe : DsColors.ink, shape: BoxShape.circle),
                child: done
                    ? const Icon(Icons.check_rounded, color: DsColors.onDark, size: 18)
                    : Text('$n', style: DsType.caption.copyWith(color: DsColors.onDark)),
              ),
              const SizedBox(width: DsSpace.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: DsType.title),
                  const SizedBox(height: DsSpace.xs),
                  body,
                ]),
              ),
            ]),
          ),
        ),
      );
}
