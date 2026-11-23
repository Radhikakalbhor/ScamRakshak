import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/strings.dart';
import 'qr_check_strings.dart';

/// Opens the camera and returns the first QR code's raw text, or null if the user goes back.
Future<String?> scanQrWithCamera(BuildContext context) =>
    Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScannerPage()));

/// Logs the real camera/analyzer error (code + platform details) to logcat.
void logQrCameraError(Object error, {String where = 'camera', StackTrace? stack}) {
  if (error is MobileScannerException) {
    final d = error.errorDetails;
    debugPrint('[QR_CAMERA_ERROR] $where code=${error.errorCode.name} '
        'platformCode=${d?.code} message=${d?.message} details=${d?.details}');
  } else {
    debugPrint('[QR_CAMERA_ERROR] $where ${error.runtimeType}: $error');
  }
  if (stack != null) debugPrint('[QR_CAMERA_ERROR] $stack');
}

/// User-facing message key for a camera start error.
String qrCameraErrorKey(MobileScannerErrorCode code) => switch (code) {
      MobileScannerErrorCode.permissionDenied => 'qr_camera_denied',
      MobileScannerErrorCode.unsupported => 'qr_camera_unsupported',
      _ => 'qr_camera_error',
    };

enum QrImageStatus { found, cancelled, noQr, failed }

class QrImageScan {
  final QrImageStatus status;
  final String? value;

  /// Real error text when [status] is failed (shown under the friendly message).
  final String? error;
  const QrImageScan(this.status, [this.value, this.error]);
  const QrImageScan.failed(this.error)
      : status = QrImageStatus.failed,
        value = null;
}

/// mobile_scanner 7.0.1's own method channel (the version is pinned in pubspec.yaml).
const qrScannerChannel = MethodChannel('dev.steenbakker.mobile_scanner/scanner/method');

/// Picks an image (photo picker/files; file_picker copies it to a real cache file path) and reads the
/// QR in it. Works without the live camera.
Future<QrImageScan> scanQrFromImage() async {
  String? path;
  try {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image);
    if (picked == null) return const QrImageScan(QrImageStatus.cancelled);
    path = picked.files.single.path;
  } catch (e, st) {
    logQrCameraError(e, where: 'pickImage', stack: st);
    return QrImageScan.failed('$e');
  }
  if (path == null) return const QrImageScan.failed('The picked image has no file path.');
  return analyzeQrImageFile(path);
}

/// Reads QR codes in the image file at [path] with ML Kit (via mobile_scanner's native analyzeImage,
/// which handles EXIF rotation). Calls the plugin channel directly because
/// `MobileScannerPlatform.analyzeImage` turns every native error into `null`, which looked exactly
/// like "no QR in this image" and hid the real failure.
Future<QrImageScan> analyzeQrImageFile(String path) async {
  if (!File(path).existsSync()) return QrImageScan.failed('Image file not found: $path');
  try {
    final res = await qrScannerChannel.invokeMapMethod<Object?, Object?>('analyzeImage', {
      'filePath': path,
      'formats': [BarcodeFormat.qrCode.rawValue],
    });
    final data = res?['data'];
    if (data is! List) return const QrImageScan.failed('The scanner returned no result.');
    for (final b in data) {
      if (b is! Map) continue;
      final raw = ((b['rawValue'] ?? b['displayValue']) as String?)?.trim();
      if (raw != null && raw.isNotEmpty) return QrImageScan(QrImageStatus.found, raw);
    }
    return const QrImageScan(QrImageStatus.noQr);
  } on PlatformException catch (e, st) {
    logQrCameraError(e, where: 'analyzeImage', stack: st);
    debugPrint('[QR_CAMERA_ERROR] analyzeImage native stack: ${e.stacktrace}');
    return QrImageScan.failed([e.code, if (e.message != null) e.message].join(' · '));
  } catch (e, st) {
    logQrCameraError(e, where: 'analyzeImage', stack: st);
    return QrImageScan.failed('$e');
  }
}

/// Full-screen camera view (mobile_scanner, back camera, QR only).
/// One controller per page; started once in initState; stopped on app pause and restarted on resume.
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> with WidgetsBindingObserver {
  // autoStart false: this page alone starts/stops the camera (no double start by the widget).
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  StreamSubscription<BarcodeCapture>? _sub;
  MobileScannerException? _loggedError;
  bool _done = false;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onState);
    _sub = _controller.barcodes.listen(_onDetect);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _controller.start(); // errors land in controller.value.error (see _onState)
    } catch (e, st) {
      logQrCameraError(e, where: 'start', stack: st);
    }
  }

  void _onState() {
    final err = _controller.value.error;
    if (err != null && !identical(err, _loggedError)) {
      _loggedError = err;
      logQrCameraError(err, where: 'start');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission || _done || _picking) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_start());
      case AppLifecycleState.inactive:
        unawaited(_controller.stop());
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onState);
    unawaited(_sub?.cancel());
    super.dispose();
    unawaited(_controller.dispose());
  }

  void _finish(String raw) {
    if (_done || !mounted) return;
    _done = true;
    unawaited(_controller.stop());
    Navigator.of(context).pop(raw);
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final raw = b.rawValue?.trim();
      if (raw != null && raw.isNotEmpty) return _finish(raw);
    }
  }

  Future<void> _retry() async {
    try {
      await _controller.stop();
    } catch (_) {}
    await _start();
  }

  Future<void> _fromImage() async {
    _picking = true; // the picker pauses the app; do not restart the camera underneath it
    final r = await scanQrFromImage();
    _picking = false;
    if (!mounted) return;
    if (r.status == QrImageStatus.found) return _finish(r.value!);
    if (r.status == QrImageStatus.cancelled) return;
    final s = S.of(context);
    final msg = r.status == QrImageStatus.noQr
        ? s.t('qr_image_no_qr')
        : [s.t('qr_image_failed'), if (r.error != null) '${s.t('qr_camera_error_code')}: ${r.error}'].join('\n');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _errorView(S s, MobileScannerException error) {
    final d = error.errorDetails;
    final detail = [error.errorCode.name, if (d?.code != null) d!.code, if (d?.message != null) d!.message]
        .whereType<String>()
        .join(' · ');
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.no_photography_rounded, color: Colors.white70, size: 56),
          const SizedBox(height: 12),
          Text(s.t(qrCameraErrorKey(error.errorCode)),
              key: const Key('qr_camera_error'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 17)),
          const SizedBox(height: 8),
          Text('${s.t('qr_camera_error_code')}: $detail',
              key: const Key('qr_camera_error_code'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 16),
          if (error.errorCode != MobileScannerErrorCode.permissionDenied)
            OutlinedButton.icon(
              key: const Key('qr_camera_retry'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(s.t('qr_camera_retry')),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    QrCheckStrings.ensure();
    final s = S.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(s.t('qr_scan_title'))),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          errorBuilder: (context, error) => _errorView(s, error),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            color: Colors.black54,
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(s.t('qr_scan_hint'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('qr_scan_page_image'),
                onPressed: _fromImage,
                icon: const Icon(Icons.image_search_rounded),
                label: Text(s.t('qr_scan_image')),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
