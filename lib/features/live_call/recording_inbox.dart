import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../call_detector/auto_analyze_core.dart';
import '../call_detector/auto_analyze_screen.dart';
import '../call_detector/auto_analyze_service.dart';
import '../call_detector/auto_analyze_strings.dart';
import '../call_detector/recording_result_screen.dart';
import 'live_call_strings.dart';

/// One snapshot of the saved recording analyses (newest first) plus recordings waiting for the server.
class RecordingInbox {
  final List<StoredRecordingResult> results;
  final Set<String> read;
  final List<String> pending;
  const RecordingInbox(this.results, this.read, this.pending);

  static const empty = RecordingInbox([], {}, []);

  int get unread => results.where((r) => !read.contains(r.id)).length;
  int get total => results.length + pending.length;
  bool get isEmpty => total == 0;
}

/// Refresh interval; the background watcher writes new results while the app is open.
const inboxRefresh = Duration(seconds: 3);

/// Live view of the history, re-read every [inboxRefresh] (results are written by the service isolate).
final recordingInboxProvider = StreamProvider.autoDispose<RecordingInbox>((ref) {
  final controller = StreamController<RecordingInbox>();
  Timer? timer;
  var closed = false;
  Future<void> load() async {
    try {
      final store = await ref.read(autoAnalyzeStoreProvider.future);
      await store.reload();
      if (!closed) controller.add(RecordingInbox(store.allResults(), store.readIds, [...store.pending.reversed]));
    } catch (_) {
      if (!closed) controller.add(RecordingInbox.empty);
    }
  }

  load();
  timer = Timer.periodic(inboxRefresh, (_) => load());
  ref.onDispose(() {
    closed = true;
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});

String _two(int v) => v.toString().padLeft(2, '0');
String inboxTime(DateTime t) => '${_two(t.day)}/${_two(t.month)}/${t.year} ${_two(t.hour)}:${_two(t.minute)}';

Color _riskColor(String risk) => switch (risk) {
      'high' => AppTheme.errorRed,
      'medium' => AppTheme.warningOrange,
      _ => AppTheme.successGreen,
    };

void _push(BuildContext context, String route, Widget fallback, {Object? extra}) {
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    router.push(route, extra: extra);
  } else {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => fallback));
  }
}

/// Opens one entry (result or waiting recording), then refreshes the list (it is now read).
Future<void> openInboxEntry(BuildContext context, WidgetRef ref, String payload) async {
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    await router.push('/call/recording', extra: payload);
  } else {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RecordingResultScreen(payload: payload)));
  }
  ref.invalidate(recordingInboxProvider);
}

void openInbox(BuildContext context) => _push(context, '/live/inbox', const RecordingInboxScreen());

/// Bell button with the number of unread recording results.
class RecordingInboxButton extends ConsumerWidget {
  const RecordingInboxButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    LiveCallStrings.ensure();
    final unread = ref.watch(recordingInboxProvider).valueOrNull?.unread ?? 0;
    return IconButton(
      key: const Key('inbox_button'),
      tooltip: S.of(context).t('inbox_button'),
      onPressed: () => openInbox(context),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread', key: const Key('inbox_badge')),
        child: const Icon(Icons.notifications_rounded),
      ),
    );
  }
}

/// One row of the history.
class RecordingInboxTile extends ConsumerWidget {
  final StoredRecordingResult? result;
  final String? pendingPath;
  final bool unread;
  const RecordingInboxTile.result(StoredRecordingResult this.result, {super.key, required this.unread})
      : pendingPath = null;
  const RecordingInboxTile.pending(String this.pendingPath, {super.key})
      : result = null,
        unread = false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AutoAnalyzeStrings.ensure();
    LiveCallStrings.ensure();
    final s = S.of(context);
    final r = result;
    if (r == null) {
      return Card(
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFFFF3E0),
            child: Icon(Icons.cloud_off_rounded, color: AppTheme.warningOrange),
          ),
          title: Text(fileNameOf(pendingPath!), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(s.t('inbox_waiting')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => openInboxEntry(context, ref, pendingPayload(pendingPath!)),
        ),
      );
    }
    final res = r.result;
    final color = _riskColor(res.risk);
    final type = res.scriptType;
    final title = type == null ? s.t('risk_${res.risk}') : '${s.t('risk_${res.risk}')} · ${s.t('script_$type')}';
    return Card(
      color: unread ? const Color(0xFFFFFBF0) : null,
      child: ListTile(
        key: Key('inbox_item_${r.id}'),
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(res.risk == 'low' ? Icons.verified_user_rounded : Icons.phone_locked_rounded, color: Colors.white),
        ),
        title: Text(title,
            style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.w600, color: color)),
        subtitle: Text(
          '${s.t('inbox_score').replaceAll('{p}', '${(res.score * 100).round()}')}\n'
          '${r.fileName}\n${inboxTime(r.at)}',
        ),
        isThreeLine: true,
        trailing: unread
            ? Container(
                key: Key('inbox_new_${r.id}'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppTheme.errorRed, borderRadius: BorderRadius.circular(10)),
                child: Text(s.t('inbox_new'),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              )
            : const Icon(Icons.chevron_right_rounded),
        onTap: () => openInboxEntry(context, ref, resultPayload(r.id)),
      ),
    );
  }
}

List<Widget> _tiles(RecordingInbox inbox, {int? limit}) {
  final out = <Widget>[
    for (final p in inbox.pending) RecordingInboxTile.pending(p, key: Key('inbox_pending_$p')),
    for (final r in inbox.results) RecordingInboxTile.result(r, unread: !inbox.read.contains(r.id)),
  ];
  return limit == null || out.length <= limit ? out : out.sublist(0, limit);
}

Widget _emptyView(BuildContext context, S s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(s.t('inbox_empty'), key: const Key('inbox_empty'), style: const TextStyle(fontSize: 15)),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        key: const Key('inbox_setup'),
        onPressed: () => _push(context, '/call/auto', const AutoAnalyzeScreen()),
        icon: const Icon(Icons.auto_mode_rounded),
        label: Text(s.t('inbox_setup')),
      ),
    ]);

/// "Recording alerts" section on the Live Call Guard screen: latest 3 results and a link to all.
class RecordingInboxSection extends ConsumerWidget {
  static const preview = 3;
  const RecordingInboxSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    LiveCallStrings.ensure();
    final s = S.of(context);
    final inbox = ref.watch(recordingInboxProvider).valueOrNull ?? RecordingInbox.empty;
    return Card(
      key: const Key('inbox_section'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.notifications_active_rounded, color: AppTheme.primaryTeal),
            const SizedBox(width: 8),
            Expanded(child: Text(s.t('inbox_title'), style: Theme.of(context).textTheme.titleLarge)),
            if (inbox.unread > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppTheme.errorRed, borderRadius: BorderRadius.circular(10)),
                child: Text(s.t('inbox_unread').replaceAll('{n}', '${inbox.unread}'),
                    key: const Key('inbox_section_unread'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
          ]),
          const SizedBox(height: 4),
          Text(s.t('inbox_section_sub'), style: const TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          if (inbox.isEmpty) _emptyView(context, s) else ..._tiles(inbox, limit: preview),
          if (inbox.total > preview)
            TextButton(
              key: const Key('inbox_see_all'),
              onPressed: () => openInbox(context),
              child: Text(s.t('inbox_see_all').replaceAll('{n}', '${inbox.total}')),
            ),
        ]),
      ),
    );
  }
}

/// Full history of automatically analysed call recordings (kept until the oldest drop out).
class RecordingInboxScreen extends ConsumerWidget {
  const RecordingInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    LiveCallStrings.ensure();
    AutoAnalyzeStrings.ensure();
    final s = S.of(context);
    final inbox = ref.watch(recordingInboxProvider);
    final data = inbox.valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('inbox_title')),
        actions: [
          if ((data?.unread ?? 0) > 0)
            IconButton(
              key: const Key('inbox_mark_all'),
              tooltip: s.t('inbox_mark_all'),
              icon: const Icon(Icons.done_all_rounded),
              onPressed: () async {
                final store = await ref.read(autoAnalyzeStoreProvider.future);
                await store.markAllRead();
                ref.invalidate(recordingInboxProvider);
              },
            ),
        ],
      ),
      body: SafeArea(
        child: data == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                key: const Key('inbox_list'),
                padding: const EdgeInsets.all(16),
                children: data.isEmpty ? [_emptyView(context, s)] : _tiles(data),
              ),
      ),
    );
  }
}
