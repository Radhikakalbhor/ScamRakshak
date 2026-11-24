import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../providers.dart';
import '../strings.dart';

/// Bumped whenever the server address is saved, so every [ServerStatusChip] re-checks.
final serverSettingsChanged = ValueNotifier<int>(0);

class ServerStrings {
  static bool _registered = false;
  static void ensure() {
    if (_registered) return;
    _registered = true;
    S.register(_map);
  }

  static const Map<String, Map<String, String>> _map = {
    'en': {
      'srv_title': 'Server settings',
      'srv_chip_ok': 'Server: connected',
      'srv_chip_bad': 'Server: not reachable',
      'srv_chip_unset': 'Server: not set',
      'srv_chip_checking': 'Server: checking…',
      'srv_version': 'App version',
      'srv_active': 'Active server',
      'srv_none': 'Not set',
      'srv_field': 'Server address',
      'srv_help':
          'Wi-Fi: run the server on your laptop, connect the phone to the same Wi-Fi and enter http://<laptop-ip>:8000.\nUSB: run "adb reverse tcp:8000 tcp:8000" on the laptop and enter http://127.0.0.1:8000.',
      'srv_test': 'Test connection',
      'srv_save': 'Save',
      'srv_testing': 'Testing…',
      'srv_test_ok': 'Connected: the server answered /health.',
      'srv_test_bad': 'Not reachable. Check the address, the Wi-Fi, that the server is running and that the laptop firewall allows port 8000.',
      'srv_invalid': 'Enter an address like http://192.168.1.5:8000',
      'srv_emulator': '10.0.2.2 only works on the Android emulator, not on a real phone.',
      'srv_saved': 'Server address saved.',
    },
    'hi': {
      'srv_title': 'सर्वर सेटिंग',
      'srv_chip_ok': 'सर्वर: जुड़ा है',
      'srv_chip_bad': 'सर्वर: नहीं मिल रहा',
      'srv_chip_unset': 'सर्वर: पता नहीं डाला',
      'srv_chip_checking': 'सर्वर: जाँच रहे हैं…',
      'srv_version': 'ऐप संस्करण',
      'srv_active': 'चालू सर्वर',
      'srv_none': 'पता नहीं डाला',
      'srv_field': 'सर्वर का पता',
      'srv_help':
          'Wi-Fi: लैपटॉप पर सर्वर चलाएँ, फोन को उसी Wi-Fi से जोड़ें और http://<लैपटॉप-IP>:8000 लिखें।\nUSB: लैपटॉप पर "adb reverse tcp:8000 tcp:8000" चलाएँ और http://127.0.0.1:8000 लिखें।',
      'srv_test': 'कनेक्शन जाँचें',
      'srv_save': 'सहेजें',
      'srv_testing': 'जाँच रहे हैं…',
      'srv_test_ok': 'जुड़ गया: सर्वर ने /health का जवाब दिया।',
      'srv_test_bad': 'सर्वर नहीं मिला। पता, Wi-Fi, सर्वर चालू है या नहीं और लैपटॉप फ़ायरवॉल में पोर्ट 8000 जाँचें।',
      'srv_invalid': 'ऐसा पता लिखें: http://192.168.1.5:8000',
      'srv_emulator': '10.0.2.2 सिर्फ़ एमुलेटर पर चलता है, असली फोन पर नहीं।',
      'srv_saved': 'सर्वर का पता सहेजा गया।',
    },
    'chh': {
      'srv_title': 'सर्वर सेटिंग',
      'srv_chip_ok': 'सर्वर: जुड़े हे',
      'srv_chip_bad': 'सर्वर: नइ मिलत हे',
      'srv_chip_unset': 'सर्वर: पता नइ डारे हे',
      'srv_chip_checking': 'सर्वर: जाँचत हन…',
      'srv_version': 'ऐप संस्करण',
      'srv_active': 'चालू सर्वर',
      'srv_none': 'पता नइ डारे हे',
      'srv_field': 'सर्वर के पता',
      'srv_help':
          'Wi-Fi: लैपटॉप म सर्वर चलावव, फोन ल ओही Wi-Fi ले जोड़व अउ http://<लैपटॉप-IP>:8000 लिखव।\nUSB: लैपटॉप म "adb reverse tcp:8000 tcp:8000" चलावव अउ http://127.0.0.1:8000 लिखव।',
      'srv_test': 'कनेक्शन जाँचव',
      'srv_save': 'सहेजव',
      'srv_testing': 'जाँचत हन…',
      'srv_test_ok': 'जुड़ गे: सर्वर ह /health के जवाब दिस।',
      'srv_test_bad': 'सर्वर नइ मिलिस। पता, Wi-Fi, सर्वर चालू हे कि नइ अउ लैपटॉप फ़ायरवॉल म पोर्ट 8000 जाँचव।',
      'srv_invalid': 'अइसन पता लिखव: http://192.168.1.5:8000',
      'srv_emulator': '10.0.2.2 सिरिफ एमुलेटर म चलथे, असली फोन म नइ।',
      'srv_saved': 'सर्वर के पता सहेजे गे।',
    },
  };
}

/// Opens the Server settings sheet (version + build, active address, edit, Test connection).
Future<void> showServerSettings(BuildContext context) {
  ServerStrings.ensure();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DsColors.page,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(DsRadius.card))),
    builder: (_) => const ServerSettingsSheet(),
  );
}

class ServerSettingsSheet extends ConsumerStatefulWidget {
  const ServerSettingsSheet({super.key});

  @override
  ConsumerState<ServerSettingsSheet> createState() => _ServerSettingsSheetState();
}

class _ServerSettingsSheetState extends ConsumerState<ServerSettingsSheet> {
  final _ctrl = TextEditingController();
  String _active = '';
  String _version = '';
  bool _testing = false;
  bool? _ok;
  String? _messageKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await ref.read(apiClientProvider).getBaseUrl();
    var version = '';
    try {
      final info = await AppInfo.load();
      version = '${info.version} (build ${info.build})';
    } catch (_) {
      version = '?';
    }
    if (!mounted) return;
    setState(() {
      _active = url;
      _version = version;
      if (_ctrl.text.isEmpty) _ctrl.text = url;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String? _typed() {
    final clean = ApiClient.normalizeBaseUrl(_ctrl.text);
    if (clean.isEmpty) {
      setState(() {
        _ok = false;
        _messageKey = 'srv_invalid';
      });
      return null;
    }
    return clean;
  }

  Future<void> _test() async {
    final url = _typed();
    if (url == null) return;
    setState(() {
      _testing = true;
      _messageKey = 'srv_testing';
      _ok = null;
    });
    final ok = await ref.read(serverProbeProvider)(url);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _ok = ok;
      _messageKey = ok ? 'srv_test_ok' : 'srv_test_bad';
    });
  }

  Future<void> _save() async {
    final url = _typed();
    if (url == null) return;
    await ref.read(apiClientProvider).setBaseUrl(url);
    serverSettingsChanged.value++;
    if (!mounted) return;
    setState(() {
      _active = url;
      _messageKey = 'srv_saved';
      _ok = true;
    });
    await _test();
  }

  @override
  Widget build(BuildContext context) {
    ServerStrings.ensure();
    final s = S.of(context);
    final emulatorHint = ApiClient.isEmulatorOnly(ApiClient.normalizeBaseUrl(_ctrl.text));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          key: const Key('server_sheet'),
          padding: const EdgeInsets.all(DsSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.t('srv_title'), style: DsType.cardTitle),
              const SizedBox(height: DsSpace.m),
              Text('${s.t('srv_version')}: $_version', key: const Key('server_version'), style: DsType.small),
              const SizedBox(height: DsSpace.xs),
              Text('${s.t('srv_active')}: ${_active.isEmpty ? s.t('srv_none') : _active}',
                  key: const Key('server_active'), style: DsType.title),
              const SizedBox(height: DsSpace.l),
              AppTextField(
                key: const Key('server_field'),
                controller: _ctrl,
                label: s.t('srv_field'),
                hint: 'http://192.168.1.5:8000',
                keyboardType: TextInputType.url,
                autocorrect: false,
                onChanged: (_) => setState(() => _messageKey = null),
              ),
              if (emulatorHint) ...[
                const SizedBox(height: DsSpace.s),
                Text(s.t('srv_emulator'), style: DsType.body.copyWith(color: DsColors.caution)),
              ],
              const SizedBox(height: DsSpace.s),
              Text(s.t('srv_help'), style: DsType.small),
              if (_messageKey != null) ...[
                const SizedBox(height: DsSpace.m),
                Text(
                  s.t(_messageKey!),
                  key: const Key('server_test_result'),
                  style: DsType.body.copyWith(
                    color: _ok == null ? DsColors.ink : (_ok! ? DsColors.safe : DsColors.alert),
                  ),
                ),
              ],
              const SizedBox(height: DsSpace.l),
              PrimaryButton(
                key: const Key('server_test'),
                label: s.t('srv_test'),
                icon: Icons.network_check_rounded,
                filled: false,
                busy: _testing,
                onPressed: _testing ? null : _test,
              ),
              const SizedBox(height: DsSpace.s),
              PrimaryButton(
                key: const Key('server_save'),
                label: s.t('srv_save'),
                icon: Icons.save_outlined,
                onPressed: _testing ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Checks GET /health of an address (injectable for tests).
final serverProbeProvider = Provider<Future<bool> Function(String url)>(
  (ref) => (url) => ApiClient(baseUrl: url).isReachable(),
);

/// "Server: connected / not reachable" chip; tap opens [showServerSettings].
class ServerStatusChip extends ConsumerStatefulWidget {
  const ServerStatusChip({super.key});

  @override
  ConsumerState<ServerStatusChip> createState() => _ServerStatusChipState();
}

class _ServerStatusChipState extends ConsumerState<ServerStatusChip> {
  bool _checking = true;
  bool _ok = false;
  bool _unset = false;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    serverSettingsChanged.addListener(_check);
    _check();
  }

  @override
  void dispose() {
    serverSettingsChanged.removeListener(_check);
    super.dispose();
  }

  Future<void> _check() async {
    final run = ++_run;
    if (mounted) setState(() => _checking = true);
    final api = ref.read(apiClientProvider);
    final url = await api.getBaseUrl();
    final ok = url.isNotEmpty && await api.isReachable();
    if (!mounted || run != _run) return;
    setState(() {
      _checking = false;
      _unset = url.isEmpty;
      _ok = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    ServerStrings.ensure();
    final s = S.of(context);
    final (key, icon, bg) = _checking
        ? ('srv_chip_checking', Icons.sync_rounded, DsColors.surface)
        : _ok
            ? ('srv_chip_ok', Icons.cloud_done_outlined, DsColors.safeSoft)
            : (_unset ? 'srv_chip_unset' : 'srv_chip_bad', Icons.cloud_off_rounded, DsColors.alertSoft);
    return PillChip(
      key: const Key('server_chip'),
      label: s.t(key),
      icon: icon,
      background: bg,
      foreground: DsColors.ink,
      semanticLabel: '${s.t(key)}. ${s.t('srv_title')}',
      onTap: () async {
        await showServerSettings(context);
        _check();
      },
    );
  }
}
