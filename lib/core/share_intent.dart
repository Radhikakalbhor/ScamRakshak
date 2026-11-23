import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'strings.dart';

/// Something shared into ScamRakshak from another app (Android ACTION_SEND).
class SharedItem {
  /// 'text' | 'audio' | 'audio_error'
  final String type;
  final String? text;

  /// For audio: a private copy in the app cache (the original is never changed).
  final String? path;
  final String? name;

  const SharedItem(this.type, {this.text, this.path, this.name});

  static SharedItem? fromMap(Object? m) {
    if (m is! Map) return null;
    final type = m['type']?.toString();
    if (type == 'text') {
      final t = m['text']?.toString().trim() ?? '';
      return t.isEmpty ? null : SharedItem('text', text: t);
    }
    if (type == 'audio') {
      final p = m['path']?.toString() ?? '';
      return p.isEmpty ? null : SharedItem('audio', path: p, name: m['name']?.toString());
    }
    if (type == 'audio_error') return const SharedItem('audio_error');
    return null;
  }
}

/// Where shares come from. [ChannelShareSource] talks to MainActivity.kt; tests use a fake.
abstract class ShareSource {
  /// The share that launched the app (cold start), once.
  Future<SharedItem?> initial();

  /// Shares received while the app is already open.
  void listen(void Function(SharedItem item) onItem);
}

class ChannelShareSource implements ShareSource {
  static const channel = MethodChannel('scamrakshak/share');

  @override
  Future<SharedItem?> initial() async {
    try {
      return SharedItem.fromMap(await channel.invokeMethod<Object?>('getInitialShare'));
    } on MissingPluginException {
      return null; // not Android (tests, desktop)
    } on PlatformException {
      return null;
    }
  }

  @override
  void listen(void Function(SharedItem item) onItem) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onShare') {
        final item = SharedItem.fromMap(call.arguments);
        if (item != null) onItem(item);
      }
      return null;
    });
  }
}

final shareSourceProvider = Provider<ShareSource>((ref) => ChannelShareSource());

const Map<String, Map<String, String>> _strings = {
  'en': {'share_audio_failed': 'The shared recording could not be opened. Choose it from Check Call instead.'},
  'hi': {'share_audio_failed': 'शेयर की गई रिकॉर्डिंग खुल नहीं पाई। कॉल जांचें में जाकर उसे चुनें।'},
  'chh': {'share_audio_failed': 'सेयर करे रिकॉर्डिंग नइ खुलिस। कॉल जांचव म जा के ओला चुन।'},
};

/// Wraps the home screen: a shared text opens Check Message (prefilled and checked), shared audio opens
/// Check Call (analysed at once). Handles both cold start and shares while the app is open.
class ShareHost extends ConsumerStatefulWidget {
  final Widget child;
  const ShareHost({super.key, required this.child});

  @override
  ConsumerState<ShareHost> createState() => _ShareHostState();
}

class _ShareHostState extends ConsumerState<ShareHost> {
  @override
  void initState() {
    super.initState();
    S.register(_strings);
    final source = ref.read(shareSourceProvider);
    source.listen(_open);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final item = await source.initial();
      if (item != null) _open(item);
    });
  }

  void _open(SharedItem item) {
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    switch (item.type) {
      case 'text':
        router?.push('/message', extra: item.text);
      case 'audio':
        router?.push('/call', extra: File(item.path!));
      default:
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(S.of(context).t('share_audio_failed'))));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
