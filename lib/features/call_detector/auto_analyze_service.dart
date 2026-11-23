import 'dart:async';
import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import 'auto_analyze_core.dart';
import 'auto_analyze_strings.dart';
import 'call_timeline.dart';

/// Notification payloads.
String resultPayload(String id) => jsonEncode({'result': id});
String pendingPayload(String path) => jsonEncode({'pending': path});

/// Notification action id that opens /report.
const kReportAction = 'report';

typedef NotificationTap = void Function(String? actionId, String? payload);

/// Permissions, folder picker, foreground service and notification taps. Faked in tests.
abstract class AutoAnalyzePlatform {
  Future<bool> hasAllFilesAccess();
  Future<bool> requestAllFilesAccess();
  Future<bool> hasNotificationPermission();
  Future<bool> requestNotificationPermission();
  Future<bool> isBatteryUnrestricted();
  Future<bool> requestBatteryUnrestricted();
  Future<void> openSettings();
  Future<String?> pickFolder();
  Future<bool> startService(String locale);
  Future<void> stopService();
  Future<bool> isServiceRunning();

  /// Calls [onTap] for the notification that launched the app and for every later tap.
  Future<void> listenForTaps(NotificationTap onTap);
}

final autoAnalyzePlatformProvider = Provider<AutoAnalyzePlatform>((ref) => PluginAutoAnalyzePlatform());

final autoAnalyzeStoreProvider = FutureProvider<AutoAnalyzeStore>((ref) => AutoAnalyzeStore.open());

class PluginAutoAnalyzePlatform implements AutoAnalyzePlatform {
  @override
  Future<bool> hasAllFilesAccess() async {
    final all = await Permission.manageExternalStorage.status;
    if (all.isGranted) return true;
    // Android 10 and older have no "All files access"; plain storage permission is enough there.
    if (all.isRestricted) return Permission.storage.isGranted;
    return false;
  }

  @override
  Future<bool> requestAllFilesAccess() async {
    final all = await Permission.manageExternalStorage.request(); // opens the system page on Android 11+
    if (all.isGranted) return true;
    if (all.isRestricted) return (await Permission.storage.request()).isGranted;
    return false;
  }

  @override
  Future<bool> hasNotificationPermission() => Permission.notification.isGranted;

  @override
  Future<bool> requestNotificationPermission() async => (await Permission.notification.request()).isGranted;

  @override
  Future<bool> isBatteryUnrestricted() => Permission.ignoreBatteryOptimizations.isGranted;

  @override
  Future<bool> requestBatteryUnrestricted() async => (await Permission.ignoreBatteryOptimizations.request()).isGranted;

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }

  @override
  Future<String?> pickFolder() => FilePicker.platform.getDirectoryPath();

  @override
  Future<bool> startService(String locale) async {
    AutoAnalyzeStrings.ensure();
    final s = S(locale);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'scamrakshak_watcher',
        channelName: s.t('auto_service_title'),
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(3000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    if (await FlutterForegroundTask.isRunningService) {
      final r = await FlutterForegroundTask.restartService();
      return r is ServiceRequestSuccess;
    }
    final r = await FlutterForegroundTask.startService(
      serviceId: 4711,
      serviceTypes: [ForegroundServiceTypes.specialUse],
      notificationTitle: s.t('auto_service_title'),
      notificationText: s.t('auto_service_text'),
      callback: autoAnalyzeServiceEntry,
    );
    return r is ServiceRequestSuccess;
  }

  @override
  Future<void> stopService() async {
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<bool> isServiceRunning() => FlutterForegroundTask.isRunningService;

  @override
  Future<void> listenForTaps(NotificationTap onTap) async {
    final plugin = await LocalAutoAnalyzeNotifier.initPlugin(
      onTap: (r) => onTap(r.actionId, r.payload),
    );
    final launch = await plugin.getNotificationAppLaunchDetails();
    final r = launch?.notificationResponse;
    if ((launch?.didNotificationLaunchApp ?? false) && r != null) onTap(r.actionId, r.payload);
  }
}

/// Posts verdict / offline notifications with flutter_local_notifications.
class LocalAutoAnalyzeNotifier implements AutoAnalyzeNotifier {
  static const channelId = 'scamrakshak_recording_results';
  static FlutterLocalNotificationsPlugin? _plugin;
  static bool _initialized = false;
  static void Function(NotificationResponse)? _onTap;

  final String Function() locale;
  LocalAutoAnalyzeNotifier(this.locale);

  /// Initializes once per isolate; a later call only re-initializes to set a new [onTap]
  /// (so posting a notification never drops the app's tap handler).
  static Future<FlutterLocalNotificationsPlugin> initPlugin({void Function(NotificationResponse)? onTap}) async {
    final p = _plugin ??= FlutterLocalNotificationsPlugin();
    if (!_initialized || onTap != null) {
      _onTap = onTap ?? _onTap;
      await p.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: _onTap,
      );
      _initialized = true;
    }
    return p;
  }

  S get _s {
    AutoAnalyzeStrings.ensure();
    return S(locale());
  }

  NotificationDetails _details({required bool report, required bool alert}) => NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _s.t('auto_notif_channel'),
          importance: Importance.high,
          priority: alert ? Priority.max : Priority.high,
          category: AndroidNotificationCategory.status,
          styleInformation: const BigTextStyleInformation(''),
          actions: [
            if (report) AndroidNotificationAction(kReportAction, _s.t('auto_notif_report'), showsUserInterface: true),
          ],
        ),
      );

  @override
  Future<void> showVerdict(StoredRecordingResult r) async {
    final p = await initPlugin();
    final s = _s;
    final res = r.result;
    final type = res.scriptType;
    final title = type == null ? s.t('risk_${res.risk}') : '${s.t('risk_${res.risk}')}: ${s.t('script_$type')}';
    final body = '${s.t('auto_notif_body').replaceAll('{p}', '${(res.score * 100).round()}')}\n${r.fileName}';
    await p.show(stableNotificationId('result:${r.id}'), title, body,
        _details(report: true, alert: res.risk == 'high'),
        payload: resultPayload(r.id));
  }

  @override
  Future<void> showOffline(String path) async {
    final p = await initPlugin();
    final s = _s;
    await p.show(stableNotificationId('pending:$path'), s.t('auto_notif_offline_title'),
        '${s.t('auto_notif_offline_body')}\n${fileNameOf(path)}', _details(report: false, alert: false),
        payload: pendingPayload(path));
  }

  @override
  Future<void> cancelOffline(String path) async {
    final p = await initPlugin();
    await p.cancel(stableNotificationId('pending:$path'));
  }
}

/// Entry point of the foreground service isolate.
@pragma('vm:entry-point')
void autoAnalyzeServiceEntry() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(AutoAnalyzeTaskHandler());
}

/// Polls the chosen folder every 3 s (ForegroundTaskEventAction.repeat(3000)).
class AutoAnalyzeTaskHandler extends TaskHandler {
  RecordingProcessor? _processor;
  bool _busy = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    AutoAnalyzeStrings.ensure();
    final store = await AutoAnalyzeStore.open();
    _processor = RecordingProcessor(
      store: store,
      api: ApiClient(),
      timeline: await CallTimeline.load(),
      notifier: LocalAutoAnalyzeNotifier(() => store.locale),
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    final p = _processor;
    if (p == null || _busy) return;
    _busy = true;
    p.tick().then((on) {
      if (!on) FlutterForegroundTask.stopService();
    }).catchError((_) {}).whenComplete(() => _busy = false);
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
