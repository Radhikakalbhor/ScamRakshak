import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scam_rakshak/core/api_client.dart';
import 'package:scam_rakshak/core/providers.dart';
import 'package:scam_rakshak/features/report/report_data.dart';
import 'package:scam_rakshak/features/report/report_screen.dart';

class _FakeApi extends ApiClient {
  final bool offline;
  final List<List<String>> calls = [];
  _FakeApi({this.offline = false});

  @override
  Future<void> postReport(String type, String district) async {
    calls.add([type, district]);
    if (offline) throw const ApiOfflineException('offline');
  }
}

Widget _app(_FakeApi api, {required List<Uri> opened, bool openOk = true, String? type}) => ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: ReportScreen(
          initialType: type,
          opener: (u) async {
            opened.add(u);
            return openOk;
          },
        ),
      ),
    );

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('1930 action opens tel:1930 and silently posts a report', (tester) async {
    final api = _FakeApi();
    final opened = <Uri>[];
    await tester.pumpWidget(_app(api, opened: opened, type: 'call'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('report_action_1930')));
    await tester.pumpAndSettle();

    expect(opened, [Uri.parse('tel:1930')]);
    expect(api.calls, [
      ['call', 'unknown']
    ]);
  });

  testWidgets('offline backend does not block opening the portal', (tester) async {
    _tallView(tester);
    final api = _FakeApi(offline: true);
    final opened = <Uri>[];
    await tester.pumpWidget(_app(api, opened: opened));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('report_action_chakshu')));
    await tester.pumpAndSettle();

    expect(opened, [Uri.parse('https://sancharsaathi.gov.in/sfc/')]);
    expect(api.calls.single.first, 'other');
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed launch shows a fallback message', (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(_app(_FakeApi(), opened: opened, openOk: false));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('report_action_cybercrime')));
    await tester.pumpAndSettle();

    expect(find.text('Could not open. Please dial 1930 yourself.'), findsOneWidget);
  });

  testWidgets('evidence checklist ticks are persisted', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_app(_FakeApi(), opened: []));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('evidence_transaction_id')));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(EvidenceStore.key('transaction_id')), isTrue);
    expect(find.text('1/6 ready'), findsOneWidget);
  });

  test('district list has all 33 Chhattisgarh districts', () {
    expect(kChhattisgarhDistricts.length, 33);
    expect(kChhattisgarhDistricts.toSet().length, 33);
  });
}
