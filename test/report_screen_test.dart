import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scam_rakshak/core/api_client.dart';
import 'package:scam_rakshak/core/providers.dart';
import 'package:scam_rakshak/features/report/report_data.dart';
import 'package:scam_rakshak/features/report/report_screen.dart';

class _FakeApi extends ApiClient {
  bool offline;
  int? status;
  final List<List<String>> calls = [];
  _FakeApi({this.offline = false});

  @override
  Future<void> postReportAt(String type, String district, String ts) async {
    if (offline) throw const ApiOfflineException('offline');
    if (status != null) throw ApiException(status!, 'x');
    calls.add([type, district, ts]);
  }
}

Widget _app(_FakeApi api, {required List<Uri> opened, bool openOk = true, String? type, String? situation}) =>
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: ReportScreen(
          initialType: type,
          initialSituation: situation,
          opener: (u) async {
            opened.add(u);
            return openOk;
          },
        ),
      ),
    );

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('asks first whether money was lost; no actions until answered', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_app(_FakeApi(), opened: []));
    await tester.pumpAndSettle();
    expect(find.text('Did you lose money?'), findsOneWidget);
    expect(find.byKey(const Key('report_action_1930')), findsNothing);
    expect(find.byKey(const Key('report_action_chakshu')), findsNothing);
  });

  testWidgets('"I lost money": 1930 first, then bank, cybercrime.gov.in and the evidence checklist', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_app(_FakeApi(), opened: []));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report_situation_lost')));
    await tester.pumpAndSettle();

    double y(String k) => tester.getTopLeft(find.byKey(Key(k))).dy;
    expect(y('report_action_1930'), lessThan(y('report_step_bank')));
    expect(y('report_step_bank'), lessThan(y('report_action_cybercrime')));
    expect(find.byKey(const Key('evidence_transaction_id')), findsOneWidget);
    expect(find.byKey(const Key('report_action_chakshu')), findsNothing);
  });

  testWidgets('"suspicious, no loss": Chakshu first, block advice, and a path to 1930', (tester) async {
    _tallView(tester);
    final opened = <Uri>[];
    await tester.pumpWidget(_app(_FakeApi(), opened: opened));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report_situation_suspicious')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report_step_block')), findsOneWidget);
    expect(find.byKey(const Key('report_action_1930')), findsNothing);
    expect(find.byKey(const Key('evidence_screenshots')), findsNothing);

    await tester.tap(find.byKey(const Key('report_action_chakshu')));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://sancharsaathi.gov.in/sfc/')]);

    await tester.tap(find.byKey(const Key('report_switch_lost')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report_action_1930')), findsOneWidget);
  });

  testWidgets('1930 opens tel:1930 and sends an anonymous count (type, district, time only)', (tester) async {
    _tallView(tester);
    final api = _FakeApi();
    final opened = <Uri>[];
    await tester.pumpWidget(_app(api, opened: opened, type: 'call', situation: 'lost'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('report_action_1930')));
    await tester.pumpAndSettle();

    expect(opened, [Uri.parse('tel:1930')]);
    expect(api.calls.single.sublist(0, 2), ['call', 'unknown']);
    expect(DateTime.tryParse(api.calls.single[2]), isNotNull);
    expect(await ReportQueue.load(), isEmpty);
    expect(find.textContaining('anonymously'), findsOneWidget);
  });

  testWidgets('offline: the action still opens, the count is kept and sent on the next visit', (tester) async {
    _tallView(tester);
    final api = _FakeApi(offline: true);
    final opened = <Uri>[];
    await tester.pumpWidget(_app(api, opened: opened, situation: 'suspicious'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('report_action_chakshu')));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    expect(tester.takeException(), isNull);
    expect((await ReportQueue.load()).single.type, 'other');
    expect(find.textContaining('1 waiting'), findsOneWidget);

    // Later, online again (e.g. after a restart): opening the screen sends the queued count.
    api.offline = false;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(api, opened: opened, situation: 'suspicious'));
    await tester.pumpAndSettle();
    expect(api.calls.single.first, 'other');
    expect(await ReportQueue.load(), isEmpty);
  });

  test('queue: server errors keep reports, invalid ones are dropped, order and time are kept', () async {
    final api = _FakeApi();
    await ReportQueue.add('otp', 'Raipur', now: DateTime.utc(2026, 11, 1, 10));
    await ReportQueue.add('fake_qr', 'Durg', now: DateTime.utc(2026, 11, 2, 10));
    api.status = 503;
    expect(await ReportQueue.flush(api), 2);
    api.status = 422;
    expect(await ReportQueue.flush(api), 0);
    expect(api.calls, isEmpty);

    await ReportQueue.add('otp', 'Raipur', now: DateTime.utc(2026, 11, 1, 10));
    await ReportQueue.add('call', 'Korba', now: DateTime.utc(2026, 11, 3, 10));
    api.status = null;
    expect(await ReportQueue.flush(api), 0);
    expect(api.calls.map((c) => c[0]), ['otp', 'call']);
    expect(api.calls.first[2], '2026-11-01T10:00:00.000Z');
  });

  testWidgets('failed launch shows a fallback message', (tester) async {
    _tallView(tester);
    final opened = <Uri>[];
    await tester.pumpWidget(_app(_FakeApi(), opened: opened, openOk: false, situation: 'lost'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('report_action_cybercrime')));
    await tester.pumpAndSettle();

    expect(find.text('Could not open. Please dial 1930 yourself.'), findsOneWidget);
  });

  testWidgets('evidence checklist ticks are persisted', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_app(_FakeApi(), opened: [], situation: 'lost'));
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
