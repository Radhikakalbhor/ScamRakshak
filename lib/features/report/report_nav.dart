import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'report_screen.dart';

/// Opens the Report screen with an optional preselected type: through go_router ('/report')
/// when the app router is present, otherwise with a plain Navigator route (e.g. in tests).
void openReport(BuildContext context, {String? type}) {
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    router.push('/report', extra: type);
  } else {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReportScreen(initialType: type)));
  }
}

/// Best-effort report type from a message text.
String guessReportType(String text) {
  final t = text.toLowerCase();
  if (t.contains('otp') || t.contains('ओटीपी') || t.contains('pin')) return 'otp';
  if (t.contains('qr') || t.contains('क्यूआर')) return 'fake_qr';
  if (t.contains('loan') || t.contains('लोन')) return 'loan_app';
  return 'other';
}
