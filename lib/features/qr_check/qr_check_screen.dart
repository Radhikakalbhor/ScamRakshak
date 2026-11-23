import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../report/report_nav.dart';
import '../report/report_strings.dart';
import 'qr_check_strings.dart';
import 'qr_scanner_page.dart';
import 'upi_qr.dart';

/// Returns the raw text of a scanned QR code, or null if cancelled.
typedef QrScanner = Future<String?> Function(BuildContext context);

/// Camera scanner used by the app (mobile_scanner). Set to null to hide the Scan button.
QrScanner? defaultQrScanner = scanQrWithCamera;

/// Picks an image/screenshot and reads the QR in it (mobile_scanner image analysis).
typedef QrImageScanner = Future<QrImageScan> Function();

/// Fake-QR checker: scan a `upi://` code with the camera or from an image, see the real payee and the
/// warning signs. Offline.
class QrCheckScreen extends StatefulWidget {
  final QrScanner? scanner;
  final QrImageScanner? imageScanner;
  const QrCheckScreen({super.key, this.scanner, this.imageScanner});

  @override
  State<QrCheckScreen> createState() => _QrCheckScreenState();
}

class _QrCheckScreenState extends State<QrCheckScreen> {
  String? _raw;
  UpiQrResult? _result;

  QrScanner? get _scanner => widget.scanner ?? defaultQrScanner;

  @override
  void initState() {
    super.initState();
    QrCheckStrings.ensure();
    ReportStrings.ensure();
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _check(String raw) => setState(() {
        _raw = raw;
        _result = checkUpiQr(raw);
      });

  Future<void> _scan() async {
    String? raw;
    try {
      raw = await _scanner!(context);
    } catch (e, st) {
      logQrCameraError(e, where: 'scanner', stack: st);
      raw = null;
    }
    if (!mounted) return;
    if (raw == null || raw.trim().isEmpty) {
      _snack(S.of(context).t('qr_scan_failed'));
      return;
    }
    _check(raw.trim());
  }

  Future<void> _scanImage() async {
    final r = await (widget.imageScanner ?? scanQrFromImage)();
    if (!mounted) return;
    final s = S.of(context);
    switch (r.status) {
      case QrImageStatus.found:
        _check(r.value!);
      case QrImageStatus.noQr:
        _snack(s.t('qr_image_no_qr'));
      case QrImageStatus.failed:
        // Friendly message + the real error text.
        _snack(r.error == null ? s.t('qr_image_failed') : '${s.t('qr_image_failed')}\n${s.t('qr_camera_error_code')}: ${r.error}');
      case QrImageStatus.cancelled:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    QrCheckStrings.ensure();
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('qr_title'))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(s.t('qr_intro'), style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.qr_code_2_rounded, color: AppTheme.warningOrange),
              const SizedBox(width: 8),
              Expanded(child: Text(s.t('qr_rule'), style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ),
          const SizedBox(height: 16),
          if (_scanner != null)
            FilledButton.icon(
              key: const Key('qr_scan'),
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(s.t('qr_scan'), style: const TextStyle(fontSize: 18)),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('qr_scan_image'),
            onPressed: _scanImage,
            icon: const Icon(Icons.image_search_rounded),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(s.t('qr_scan_image'), style: const TextStyle(fontSize: 18)),
            ),
          ),
          if (_raw != null) ...[
            const SizedBox(height: 16),
            Text(s.t('qr_scanned_text'), style: const TextStyle(color: AppTheme.textSecondary)),
            SelectableText(_raw!, key: const Key('qr_raw'), style: const TextStyle(fontSize: 15)),
          ],
          if (_result != null) ...[const SizedBox(height: 16), _resultView(s, _result!)],
        ]),
      ),
    );
  }

  Widget _row(S s, String label, String? value, {Key? key}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(color: AppTheme.textSecondary))),
          Expanded(
            child: Text(value == null || value.isEmpty ? s.t('qr_missing') : value,
                key: key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ]),
      );

  Widget _resultView(S s, UpiQrResult r) {
    final color = switch (r.level) {
      'danger' => AppTheme.errorRed,
      'caution' => AppTheme.warningOrange,
      _ => AppTheme.successGreen,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        key: const Key('qr_verdict'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Icon(r.level == 'ok' ? Icons.verified_user_rounded : Icons.gpp_bad_rounded, color: Colors.white, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Text(s.t('qr_level_${r.level}'),
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
      if (r.isUpi)
        Card(
          margin: const EdgeInsets.only(top: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              _row(s, s.t('qr_payee_id'), r.pa, key: const Key('qr_pa')),
              _row(s, s.t('qr_payee_name'), r.pn, key: const Key('qr_pn')),
              if (r.am != null) _row(s, s.t('qr_amount'), '₹${r.am}'),
              if (r.tn != null) _row(s, s.t('qr_note'), r.tn),
            ]),
          ),
        ),
      const SizedBox(height: 8),
      for (final risk in r.risks)
        Card(
          key: Key('qr_risk_$risk'),
          color: kDangerRisks.contains(risk) ? const Color(0xFFFFEBEE) : const Color(0xFFFFF8E1),
          child: ListTile(
            leading: Icon(kDangerRisks.contains(risk) ? Icons.dangerous_rounded : Icons.warning_amber_rounded,
                color: kDangerRisks.contains(risk) ? AppTheme.errorRed : AppTheme.warningOrange),
            title: Text(s.t('qr_risk_$risk'), style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(s.t('qr_risk_${risk}_sub')),
          ),
        ),
      if (r.level == 'ok') Text(s.t('qr_ok_note'), key: const Key('qr_ok_note')),
      if (r.level == 'danger') ...[
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('qr_report'),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.errorRed),
          onPressed: () => openReport(context, type: 'fake_qr'),
          icon: const Icon(Icons.report_rounded),
          label: Text(s.t('report_title')),
        ),
      ],
    ]);
  }
}
