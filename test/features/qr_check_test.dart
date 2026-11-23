import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:scam_rakshak/core/strings.dart';
import 'package:scam_rakshak/features/qr_check/qr_check_screen.dart';
import 'package:scam_rakshak/features/qr_check/qr_check_strings.dart';
import 'package:scam_rakshak/features/qr_check/qr_scanner_page.dart';
import 'package:scam_rakshak/features/qr_check/upi_qr.dart';
import 'package:scam_rakshak/features/report/report_screen.dart';

void main() {
  group('checkUpiQr', () {
    test('normal shop QR: payee shown, no risks', () {
      final r = checkUpiQr('upi://pay?pa=rameshkirana@okaxis&pn=Ramesh Kirana Store&cu=INR');
      expect(r.isUpi, isTrue);
      expect(r.pa, 'rameshkirana@okaxis');
      expect(r.pn, 'Ramesh Kirana Store');
      expect(r.risks, isEmpty);
      expect(r.level, 'ok');
    });

    test('encoded name, upper-case keys and a phone-number ID are fine', () {
      final r = checkUpiQr('UPI://pay?PA=9876543210@ybl&PN=Sunita%20Verma');
      expect(r.pa, '9876543210@ybl');
      expect(r.pn, 'Sunita Verma');
      expect(r.level, 'ok');
    });

    test('merchant code IDs are not called a name mismatch', () {
      expect(checkUpiQr('upi://pay?pa=paytmqr2810050501011abcd@paytm&pn=Shree Medical').risks, isEmpty);
    });

    test('promises money -> danger, even with an amount and a real handle', () {
      final r = checkUpiQr('upi://pay?pa=helpdesk.refund@oksbi&pn=SBI Refund Cell&am=4999&tn=KYC refund cashback');
      expect(r.level, 'danger');
      expect(r.risks.first, 'receive_words');
      expect(r.risks, containsAll(['amount_set']));
    });

    test('name that does not match the UPI ID and an unknown handle -> caution', () {
      final r = checkUpiQr('upi://pay?pa=rk.trader77@xyzpay&pn=Gupta Medical Store');
      expect(r.risks, containsAll(['name_mismatch', 'unknown_handle']));
      expect(r.level, 'caution');
    });

    test('website QR, missing/invalid ID, collect request, foreign currency, plain text', () {
      expect(checkUpiQr('https://sbi-kyc.xyz/pay').risks, ['not_upi_link']);
      expect(checkUpiQr('https://sbi-kyc.xyz/pay').level, 'danger');
      expect(checkUpiQr('upi://pay?pn=Ramesh').risks, contains('bad_pa'));
      expect(checkUpiQr('upi://pay?pa=not-an-id&pn=X').level, 'danger');
      expect(checkUpiQr('upi://collect?pa=ram@oksbi&pn=Ram&am=100').risks, contains('collect_link'));
      expect(checkUpiQr('upi://pay?pa=ram@oksbi&pn=Ram&cu=USD').risks, contains('not_inr'));
      expect(checkUpiQr('upi://pay?pa=ram@oksbi').risks, contains('no_pn'));
      expect(checkUpiQr('hello').risks, ['not_upi']);
    });

    test('Hindi prize words are caught', () {
      expect(checkUpiQr('upi://pay?pa=ram@oksbi&pn=Ram&tn=इनाम प्राप्त करें').level, 'danger');
    });
  });

  group('QrCheckScreen', () {
    void tall(WidgetTester t) {
      t.view.physicalSize = const Size(900, 2600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
    }

    testWidgets('no paste UI: no text field, no Paste/Check button, no clipboard read', (tester) async {
      tall(tester);
      var clipboardRead = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') clipboardRead = true;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(const MaterialApp(home: QrCheckScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('qr_scan')), findsOneWidget); // camera (mobile_scanner)
      expect(find.byKey(const Key('qr_scan_image')), findsOneWidget); // image
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      expect(find.byKey(const Key('qr_paste')), findsNothing);
      expect(find.byKey(const Key('qr_input')), findsNothing);
      expect(find.byKey(const Key('qr_check')), findsNothing);
      expect(find.textContaining(RegExp('paste', caseSensitive: false)), findsNothing);
      expect(find.byIcon(Icons.content_paste_rounded), findsNothing);
      expect(clipboardRead, isFalse);
    });

    test('no paste strings left in en/hi/chh', () {
      QrCheckStrings.ensure();
      for (final lang in ['en', 'hi', 'chh']) {
        for (final key in ['qr_paste', 'qr_input_hint', 'qr_empty', 'qr_check']) {
          expect(S(lang).t(key), key, reason: '$lang/$key should be removed');
        }
        for (final key in ['qr_intro', 'qr_scan_failed', 'qr_camera_error', 'qr_camera_denied', 'qr_image_failed']) {
          final v = S(lang).t(key);
          expect(v, isNot(key));
          expect(v.toLowerCase(), isNot(contains('paste')));
          expect(v, isNot(contains('चिपका')));
        }
      }
    });

    testWidgets('camera scan result is checked at once; danger shows payee and offers Report', (tester) async {
      tall(tester);
      await tester.pumpWidget(MaterialApp(
          home: QrCheckScreen(scanner: (_) async => 'upi://pay?pa=kyc.refund@oksbi&pn=Bank Refund&am=999&tn=cashback')));
      await tester.tap(find.byKey(const Key('qr_scan')));
      await tester.pumpAndSettle();
      expect(find.text('DANGER: likely a fake QR'), findsOneWidget);
      expect(tester.widget<SelectableText>(find.byKey(const Key('qr_raw'))).data,
          'upi://pay?pa=kyc.refund@oksbi&pn=Bank Refund&am=999&tn=cashback');
      expect(tester.widget<Text>(find.byKey(const Key('qr_pa'))).data, 'kyc.refund@oksbi');
      expect(find.byKey(const Key('qr_risk_receive_words')), findsOneWidget);
      expect(find.byKey(const Key('qr_risk_amount_set')), findsOneWidget);
      await tester.tap(find.byKey(const Key('qr_report')));
      await tester.pumpAndSettle();
      expect(find.byType(ReportScreen), findsOneWidget);
    });

    testWidgets('a normal shop QR from the camera looks normal', (tester) async {
      tall(tester);
      await tester.pumpWidget(MaterialApp(
          home: QrCheckScreen(scanner: (_) async => 'upi://pay?pa=rameshkirana@okaxis&pn=Ramesh Kirana')));
      await tester.tap(find.byKey(const Key('qr_scan')));
      await tester.pumpAndSettle();
      expect(find.text('Looks like a normal UPI QR'), findsOneWidget);
      expect(find.byKey(const Key('qr_ok_note')), findsOneWidget);
    });

    testWidgets('scan cancelled or unreadable keeps the screen and says so', (tester) async {
      tall(tester);
      await tester.pumpWidget(MaterialApp(home: QrCheckScreen(scanner: (_) async => null)));
      await tester.tap(find.byKey(const Key('qr_scan')));
      await tester.pumpAndSettle();
      expect(find.text('Could not read a QR code. Try again, or use Scan from Image.'), findsOneWidget);
      expect(find.byKey(const Key('qr_verdict')), findsNothing);
    });

    testWidgets('Scan from Image: found QR goes through the same UPI checker', (tester) async {
      tall(tester);
      await tester.pumpWidget(MaterialApp(
          home: QrCheckScreen(
              imageScanner: () async =>
                  const QrImageScan(QrImageStatus.found, 'upi://pay?pa=kyc.refund@oksbi&pn=Bank Refund&tn=cashback'))));
      expect(find.text('Scan from Image'), findsOneWidget);
      await tester.tap(find.byKey(const Key('qr_scan_image')));
      await tester.pumpAndSettle();
      expect(find.text('DANGER: likely a fake QR'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('qr_pa'))).data, 'kyc.refund@oksbi');
    });

    testWidgets('Scan from Image: no QR / unreadable / cancelled are handled', (tester) async {
      tall(tester);
      var next = const QrImageScan(QrImageStatus.noQr);
      await tester.pumpWidget(MaterialApp(home: QrCheckScreen(imageScanner: () async => next)));
      await tester.tap(find.byKey(const Key('qr_scan_image')));
      await tester.pumpAndSettle();
      expect(find.text('No QR code found in this image. Try a clearer screenshot.'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(QrCheckScreen))).clearSnackBars();
      await tester.pumpAndSettle();

      next = const QrImageScan.failed('error · Attempt to invoke virtual method on a null object reference');
      await tester.tap(find.byKey(const Key('qr_scan_image')));
      await tester.pumpAndSettle();
      // Friendly message plus the real error text.
      expect(
          find.text('Could not read this image. Try another photo or screenshot.\n'
              'Error: error · Attempt to invoke virtual method on a null object reference'),
          findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(QrCheckScreen))).clearSnackBars();
      await tester.pumpAndSettle();

      next = const QrImageScan(QrImageStatus.cancelled);
      await tester.tap(find.byKey(const Key('qr_scan_image')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const Key('qr_verdict')), findsNothing);
    });
  });

  group('Scan from Image: analyzeQrImageFile (fixture test/fixtures/qr/upi_qr.png)', () {
    // The QR in the fixture (generated with segno) encodes this payload.
    const fixturePayload = 'upi://pay?pa=rameshkirana@okaxis&pn=Ramesh%20Kirana%20Store&cu=INR';
    final fixture = File('test/fixtures/qr/upi_qr.png').absolute.path;
    const channel = MethodChannel('dev.steenbakker.mobile_scanner/scanner/method');

    // ML Kit decoding is native Android code and cannot run in `flutter test`; the native
    // analyzeImage answer is mocked with what mobile_scanner 7.0.1 returns on a device.
    void mockNative(WidgetTester t, Future<Object?> Function(MethodCall) h) {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, h);
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    }

    test('the fixture payload parses as a normal UPI QR', () {
      final r = checkUpiQr(fixturePayload);
      expect(r.isUpi, isTrue);
      expect(r.pa, 'rameshkirana@okaxis');
      expect(r.pn, 'Ramesh Kirana Store');
      expect(r.level, 'ok');
    });

    testWidgets('sends the real file path with the QR format and returns the decoded text', (tester) async {
      expect(File(fixture).existsSync(), isTrue);
      MethodCall? seen;
      mockNative(tester, (call) async {
        seen = call;
        return {
          'name': 'barcode',
          'data': [
            {'rawValue': fixturePayload, 'displayValue': fixturePayload, 'format': 256},
          ],
        };
      });
      final r = await analyzeQrImageFile(fixture);
      expect(seen!.method, 'analyzeImage');
      expect((seen!.arguments as Map)['filePath'], fixture);
      expect((seen!.arguments as Map)['formats'], [BarcodeFormat.qrCode.rawValue]);
      expect(r.status, QrImageStatus.found);
      expect(r.value, fixturePayload);
    });

    testWidgets('an image that really has no QR -> noQr', (tester) async {
      mockNative(tester, (_) async => {'name': 'barcode', 'data': <Object?>[]});
      expect((await analyzeQrImageFile(File('test/fixtures/qr/no_qr.png').absolute.path)).status,
          QrImageStatus.noQr);
    });

    testWidgets('a native failure is NOT reported as "no QR"; the real error text is kept', (tester) async {
      mockNative(tester, (_) async {
        throw PlatformException(
            code: 'error',
            message: "Attempt to invoke virtual method 'yk1 li1.a(k6)' on a null object reference");
      });
      final r = await analyzeQrImageFile(fixture);
      expect(r.status, QrImageStatus.failed);
      expect(r.error, contains('null object reference'));
    });

    test('a missing file is a failure with the path in the error', () async {
      final r = await analyzeQrImageFile('/no/such/file.png');
      expect(r.status, QrImageStatus.failed);
      expect(r.error, contains('/no/such/file.png'));
    });
  });

  group('QR camera errors', () {
    test('error codes map to meaningful messages', () {
      expect(qrCameraErrorKey(MobileScannerErrorCode.permissionDenied), 'qr_camera_denied');
      expect(qrCameraErrorKey(MobileScannerErrorCode.unsupported), 'qr_camera_unsupported');
      expect(qrCameraErrorKey(MobileScannerErrorCode.genericError), 'qr_camera_error');
    });

    test('logQrCameraError prints the code and platform details with the prefix', () {
      final lines = <String>[];
      final old = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
      addTearDown(() => debugPrint = old);
      logQrCameraError(const MobileScannerException(
        errorCode: MobileScannerErrorCode.genericError,
        errorDetails: MobileScannerErrorDetails(code: 'MOBILE_SCANNER_CAMERA_ERROR', message: 'boom'),
      ));
      expect(lines.single, startsWith('[QR_CAMERA_ERROR]'));
      expect(lines.single, contains('code=genericError'));
      expect(lines.single, contains('platformCode=MOBILE_SCANNER_CAMERA_ERROR'));
      expect(lines.single, contains('message=boom'));
    });
  });

  group('QrScannerPage (mobile_scanner platform channel mocked)', () {
    const method = MethodChannel('dev.steenbakker.mobile_scanner/scanner/method');
    const events = EventChannel('dev.steenbakker.mobile_scanner/scanner/event');
    const orientation = EventChannel('dev.steenbakker.mobile_scanner/scanner/deviceOrientation');

    List<String> mockScanner(WidgetTester tester, {PlatformException? startError}) {
      final calls = <String>[];
      final m = tester.binding.defaultBinaryMessenger;
      m.setMockMethodCallHandler(method, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'state':
            return 1; // authorized
          case 'start':
            final args = call.arguments as Map;
            expect(args['facing'], CameraFacing.back.rawValue);
            expect(args['formats'], [BarcodeFormat.qrCode.rawValue]);
            if (startError != null) throw startError;
            return {
              'textureId': 7,
              'size': {'width': 1080.0, 'height': 1920.0},
              'naturalDeviceOrientation': 'PORTRAIT_UP',
              'handlesCropAndRotation': true,
              'sensorOrientation': 90,
              'currentTorchState': -1,
              'numberOfCameras': 2,
              'cameraDirection': 1,
            };
        }
        return null;
      });
      m.setMockStreamHandler(events, MockStreamHandler.inline(onListen: (_, __) {}));
      m.setMockStreamHandler(orientation, MockStreamHandler.inline(onListen: (_, __) {}));
      addTearDown(() {
        m.setMockMethodCallHandler(method, null);
        m.setMockStreamHandler(events, null);
        m.setMockStreamHandler(orientation, null);
      });
      return calls;
    }

    testWidgets('starts the back camera exactly once, QR only; stops on leave', (tester) async {
      final calls = mockScanner(tester);
      await tester.pumpWidget(const MaterialApp(home: QrScannerPage()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls.where((c) => c == 'start').length, 1);
      expect(find.byKey(const Key('qr_camera_error')), findsNothing);
      expect(find.byKey(const Key('qr_scan_page_image')), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, contains('stop'));
      expect(calls.where((c) => c == 'start').length, 1);
    });

    testWidgets('a camera start failure shows the real error code and logs it', (tester) async {
      final lines = <String>[];
      final old = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
      addTearDown(() => debugPrint = old);
      final calls = mockScanner(tester,
          startError: PlatformException(
              code: 'MOBILE_SCANNER_CAMERA_ERROR', message: 'An error occurred when opening the camera.'));
      await tester.pumpWidget(const MaterialApp(home: QrScannerPage()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('qr_camera_error')), findsOneWidget);
      final code = tester.widget<Text>(find.byKey(const Key('qr_camera_error_code'))).data!;
      expect(code, contains('genericError'));
      expect(code, contains('MOBILE_SCANNER_CAMERA_ERROR'));
      expect(lines.where((l) => l.startsWith('[QR_CAMERA_ERROR]') && l.contains('MOBILE_SCANNER_CAMERA_ERROR')),
          isNotEmpty);
      // Retry calls start again; Scan from Image stays available.
      expect(find.byKey(const Key('qr_scan_page_image')), findsOneWidget);
      await tester.tap(find.byKey(const Key('qr_camera_retry')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls.where((c) => c == 'start').length, 2);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
