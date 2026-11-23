import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
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

  void _snack(String text) => showDsToast(context, text);

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
        child: ListView(padding: const EdgeInsets.fromLTRB(DsSpace.xl, DsSpace.s, DsSpace.xl, DsSpace.section), children: [
          Text(s.t('qr_intro'), style: DsType.body),
          const SizedBox(height: DsSpace.l),
          PastelCard(
            color: DsColors.alert,
            padding: const EdgeInsets.all(DsSpace.l),
            child: Row(children: [
              const IconBadge(Icons.qr_code_2_rounded, background: DsColors.surface, foreground: DsColors.alert),
              const SizedBox(width: DsSpace.m),
              Expanded(child: Text(s.t('qr_rule'), style: DsType.title.copyWith(color: DsColors.alertInk))),
            ]),
          ),
          const SizedBox(height: DsSpace.xl),
          if (_scanner != null) ...[
            PrimaryButton(
              key: const Key('qr_scan'),
              label: s.t('qr_scan'),
              icon: Icons.qr_code_scanner_rounded,
              onPressed: _scan,
            ),
            const SizedBox(height: DsSpace.s),
          ],
          PrimaryButton(
            key: const Key('qr_scan_image'),
            label: s.t('qr_scan_image'),
            icon: Icons.image_search_rounded,
            filled: false,
            onPressed: _scanImage,
          ),
          if (_raw != null) ...[
            const SizedBox(height: DsSpace.xl),
            Text(s.t('qr_scanned_text'), style: DsType.greeting),
            const SizedBox(height: DsSpace.xs),
            SelectableText(_raw!, key: const Key('qr_raw'), style: DsType.body),
          ],
          if (_result != null) ...[const SizedBox(height: DsSpace.xl), _resultView(s, _result!)],
        ]),
      ),
    );
  }

  Widget _row(S s, String label, String? value, {Key? key}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: DsSpace.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(label, style: DsType.small)),
          Expanded(
            child: Text(value == null || value.isEmpty ? s.t('qr_missing') : value, key: key, style: DsType.title),
          ),
        ]),
      );

  Widget _resultView(S s, UpiQrResult r) {
    final verdict = switch (r.level) {
      'danger' => DsVerdict.danger,
      'caution' => DsVerdict.caution,
      _ => DsVerdict.safe,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      VerdictBanner(
        key: const Key('qr_verdict'),
        verdict: verdict,
        icon: r.level == 'ok' ? Icons.verified_user_outlined : Icons.gpp_bad_outlined,
        title: s.t('qr_level_${r.level}'),
      ),
      if (r.isUpi) ...[
        const SizedBox(height: DsSpace.m),
        SurfacePanel(
          padding: const EdgeInsets.all(DsSpace.l),
          child: Column(children: [
            _row(s, s.t('qr_payee_id'), r.pa, key: const Key('qr_pa')),
            _row(s, s.t('qr_payee_name'), r.pn, key: const Key('qr_pn')),
            if (r.am != null) _row(s, s.t('qr_amount'), '₹${r.am}'),
            if (r.tn != null) _row(s, s.t('qr_note'), r.tn),
          ]),
        ),
      ],
      const SizedBox(height: DsSpace.s),
      for (final risk in r.risks)
        Padding(
          padding: const EdgeInsets.only(top: DsSpace.s),
          child: DsListTile(
            key: Key('qr_risk_$risk'),
            color: kDangerRisks.contains(risk) ? DsColors.alertSoft : DsColors.cautionSoft,
            leading: Icon(kDangerRisks.contains(risk) ? Icons.dangerous_outlined : Icons.warning_amber_rounded,
                color: kDangerRisks.contains(risk) ? DsColors.alert : DsColors.caution),
            title: s.t('qr_risk_$risk'),
            subtitle: s.t('qr_risk_${risk}_sub'),
          ),
        ),
      if (r.level == 'ok') ...[
        const SizedBox(height: DsSpace.s),
        Text(s.t('qr_ok_note'), key: const Key('qr_ok_note'), style: DsType.body),
      ],
      if (r.level == 'danger') ...[
        const SizedBox(height: DsSpace.l),
        PrimaryButton(
          key: const Key('qr_report'),
          label: s.t('report_title'),
          icon: Icons.report_outlined,
          color: DsColors.alert,
          onPressed: () => openReport(context, type: 'fake_qr'),
        ),
      ],
    ]);
  }
}
