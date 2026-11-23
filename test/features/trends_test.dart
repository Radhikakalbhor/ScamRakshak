import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scam_rakshak/core/api_client.dart';
import 'package:scam_rakshak/core/providers.dart';
import 'package:scam_rakshak/engine/call_analyzer.dart';
import 'package:scam_rakshak/engine/models.dart';
import 'package:scam_rakshak/engine/scam_classifier.dart';
import 'package:scam_rakshak/features/dashboard/detection_history.dart';
import 'package:scam_rakshak/features/dashboard/trends_screen.dart';
import 'package:scam_rakshak/features/dashboard/trends_stats.dart';
import 'package:scam_rakshak/features/message_detector/message_detector_screen.dart';

Map<String, dynamic> _json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

final _now = DateTime(2026, 11, 23, 18, 0);

DetectionRecord _rec(
  String kind,
  String verdict, {
  String category = '',
  int daysAgo = 0,
  bool sample = false,
  double? score,
}) => DetectionRecord(
  kind: kind,
  verdict: verdict,
  category: verdict == 'safe' ? '' : category,
  score: score,
  sample: sample,
  time: _now.subtract(Duration(days: daysAgo, minutes: 5)),
);

final _records = [
  _rec('message', 'scam', category: 'fake_kyc', score: 0.97),
  _rec('message', 'scam', category: 'fake_kyc', daysAgo: 1, score: 0.91),
  _rec('call', 'scam', category: 'digital_arrest', daysAgo: 2),
  _rec('call', 'suspicious', category: 'lottery_prize', daysAgo: 2),
  _rec('message', 'safe', daysAgo: 3, score: 0.05),
  _rec('call', 'safe', daysAgo: 10),
  _rec('message', 'scam', category: 'phishing_link', sample: true, score: 0.9),
];

class _OfflineApi extends ApiClient {
  @override
  Future<List<Map>> getTrends() async => throw const ApiOfflineException('offline');
  @override
  Future<Map> getTrendSummary() async => throw const ApiOfflineException('offline');
  @override
  Future<List<Map>> getAlerts() async => throw const ApiOfflineException('offline');
}

/// New server: GET /trends/summary + GET /alerts.
class _SummaryApi extends ApiClient {
  @override
  Future<Map> getTrendSummary() async => {
        'min_count': 5,
        'live': {
          'total': 9,
          'by_district': [
            {'district': 'Korba', 'count': 6},
          ],
          'by_type': [
            {'type': 'fake_qr', 'count': 6},
          ],
          'by_district_type': [
            {'district': 'Korba', 'type': 'fake_qr', 'count': 6},
          ],
          'weekly': [
            {'week_start': '2026-11-09', 'count': null},
            {'week_start': '2026-11-16', 'count': 0},
            {'week_start': '2026-11-23', 'count': 6},
          ],
          'suppressed_cells': 2,
        },
        'synthetic': {
          'total': 300,
          'by_district': [
            {'district': 'Raipur', 'count': 55},
          ],
          'by_type': [
            {'type': 'otp', 'count': 23},
          ],
          'by_district_type': [],
          'weekly': [
            {'week_start': '2026-11-23', 'count': 20},
          ],
          'suppressed_cells': 0,
        },
      };

  @override
  Future<List<Map>> getAlerts() async => [
        {'kind': 'spike', 'district': 'Korba', 'type': 'fake_qr', 'recent': 6, 'baseline_weekly': 0.5, 'ratio': 6},
        {'kind': 'cluster', 'category': 'otp_request', 'size': 7},
      ];
}

/// Older server without /trends/summary (404): falls back to GET /trends, labelled as mixed data.
class _ServerApi extends ApiClient {
  @override
  Future<Map> getTrendSummary() async => throw const ApiException(404, 'not found');
  @override
  Future<List<Map>> getAlerts() async => throw const ApiException(404, 'not found');
  @override
  Future<List<Map>> getTrends() async => [
    {'district': 'Raipur', 'type': 'otp', 'count': 12},
    {'district': 'Raipur', 'type': 'call', 'count': 3},
    {'district': 'Durg', 'type': 'fake_qr', 'count': 5},
  ];
}

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Pumps frames and lets real async work complete in between.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  }
  await tester.pumpAndSettle();
}

Future<void> _seed(List<DetectionRecord> rs) async {
  SharedPreferences.setMockInitialValues({DetectionHistory.prefKey: jsonEncode(rs.map((r) => r.toJson()).toList())});
}

Widget _app({ApiClient? api}) => ProviderScope(
  overrides: [if (api != null) apiClientProvider.overrideWithValue(api)],
  child: MaterialApp(home: TrendsScreen(clock: () => _now)),
);

String _tileValue(WidgetTester tester, String key) {
  final texts = tester.widgetList<Text>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)));
  return texts.elementAt(0).data!;
}

void main() {
  group('TrendStats', () {
    test('counts, practice exclusion and category ranking', () {
      final s = TrendStats.from(_records, now: _now);
      expect(s.messages, 3);
      expect(s.calls, 3);
      expect(s.scams, 3);
      expect(s.suspicious, 1);
      expect(s.safe, 2);
      expect(s.practiceExcluded, 1);
      expect(s.categories.map((e) => '${e.key}=${e.value}'), ['fake_kyc=2', 'digital_arrest=1', 'lottery_prize=1']);
      expect(s.topCategory, 'fake_kyc');

      final withPractice = TrendStats.from(_records, now: _now, includePractice: true);
      expect(withPractice.total, 7);
      expect(withPractice.categories.map((e) => e.key), contains('phishing_link'));
    });

    test('last 7 days, oldest first, records older than a week are only in totals', () {
      final s = TrendStats.from(_records, now: _now);
      expect(s.daily, hasLength(7));
      expect(s.daily.last.day, DateTime(2026, 11, 23));
      expect(s.daily.first.day, DateTime(2026, 11, 17));
      expect(s.daily.map((d) => '${d.risky}/${d.safe}'), ['0/0', '0/0', '0/0', '0/1', '2/0', '1/0', '1/0']);
    });

    test('recent is newest first and limited', () {
      final s = TrendStats.from(_records, now: _now, recentLimit: 3);
      expect(s.recent, hasLength(3));
      expect(s.recent.first.time.isAfter(s.recent.last.time), isTrue);
    });

    test('empty input', () {
      final s = TrendStats.from([], now: _now);
      expect(s.isEmpty, isTrue);
      expect(s.topCategory, isNull);
      expect(s.daily.every((d) => d.total == 0), isTrue);
    });

    test('server rows are summed by district and type', () {
      final t = ServerTrends.fromRows([
        {'district': 'Raipur', 'type': 'otp', 'count': 12},
        {'district': 'Raipur', 'type': 'call', 'count': 3},
        {'district': 'Durg', 'type': 'otp', 'count': 5},
        {'district': 'Bad', 'type': 'otp', 'count': -1},
      ]);
      expect(t.total, 20);
      expect(t.byDistrict.first, isA<MapEntry<String, int>>().having((e) => e.key, 'key', 'Raipur'));
      expect(t.byType.first.value, 17);
    });
  });

  group('DetectionHistory', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('add / load round trip, newest first, clear', () async {
      final h = DetectionHistory();
      await h.add(_rec('message', 'safe', daysAgo: 1));
      await h.add(_rec('call', 'scam', category: 'fake_kyc'));
      final all = await h.load();
      expect(all.map((r) => r.kind), ['call', 'message']);
      expect(all.first.category, 'fake_kyc');
      await h.clear();
      expect(await h.load(), isEmpty);
    });

    test('keeps at most maxRecords', () async {
      final many = List.generate(DetectionHistory.maxRecords, (i) => _rec('message', 'safe'));
      await _seed(many);
      final h = DetectionHistory();
      await h.add(_rec('call', 'scam', category: 'otp_request'));
      final all = await h.load();
      expect(all, hasLength(DetectionHistory.maxRecords));
      expect(all.first.kind, 'call');
    });

    test('corrupt or invalid stored data is ignored', () async {
      SharedPreferences.setMockInitialValues({DetectionHistory.prefKey: '{not json'});
      expect(await DetectionHistory().load(), isEmpty);
      SharedPreferences.setMockInitialValues({
        DetectionHistory.prefKey: jsonEncode([
          {'kind': 'sms', 'verdict': 'scam', 'ts': _now.toIso8601String()},
          {'kind': 'call', 'verdict': 'safe', 'ts': _now.toIso8601String()},
        ]),
      });
      expect(await DetectionHistory().load(), hasLength(1));
    });

    test('records never contain the checked text', () {
      final r = messageRecord('My OTP is 123456', const ScamResult('scam', 0.9, []), now: _now);
      expect(jsonEncode(r.toJson()), isNot(contains('123456')));
    });
  });

  group('categorization', () {
    late CallAnalyzer analyzer;
    late ScamClassifier clf;
    setUpAll(() {
      analyzer = CallAnalyzer.fromJson(_json('assets/rules/call_rules.json'));
      clf = ScamClassifier.fromJson(_json('assets/models/scam_model.json'));
    });

    test('scam messages get the call-rule script type, a link type, or other', () {
      const kyc = 'Dear customer your SBI account will be blocked today, update KYC now bit.ly/abcd';
      final r = clf.classify(kyc);
      expect(r.label, 'scam');
      expect(messageRecord(kyc, r, analyzer: analyzer).category, 'fake_kyc');
      expect(
        messageCategory('Claim your reward at sbi-reward.xyz/claim', const ScamResult('scam', 0.9, []), analyzer),
        'phishing_link',
      );
      expect(messageCategory('hello', const ScamResult('scam', 0.6, []), analyzer), 'other');
    });

    test('genuine messages are safe with no category', () {
      final r = messageRecord('Rs 500 credited to your A/c', const ScamResult('genuine', 0.1, []), now: _now);
      expect(r.verdict, 'safe');
      expect(r.category, '');
    });

    test('call risk maps to verdicts', () {
      expect(callRecord(analyzer.analyze('You are under digital arrest, CBI case')).verdict, 'scam');
      expect(callRecord(analyzer.analyze('You are under digital arrest, CBI case')).category, 'digital_arrest');
      expect(callRecord(analyzer.analyze('OTP bataiye')).verdict, 'suspicious');
      final low = callRecord(analyzer.analyze('hello, how are you'));
      expect(low.verdict, 'safe');
      expect(low.category, '');
    });
  });

  group('TrendsScreen', () {
    testWidgets('empty state when nothing has been checked', (tester) async {
      _tallView(tester);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_app());
      await _settle(tester);

      expect(find.byKey(const Key('trends_empty')), findsOneWidget);
      expect(find.text('No checks yet'), findsOneWidget);
      expect(find.byKey(const Key('trends_tile_messages')), findsNothing);
      expect(find.byKey(const Key('trends_chart')), findsNothing);
      expect(find.byKey(const Key('trends_clear')), findsNothing);
      expect(find.byKey(const Key('trends_server_load')), findsOneWidget);
    });

    testWidgets('statistics from stored history; practice checks can be included', (tester) async {
      _tallView(tester);
      await _seed(_records);
      await tester.pumpWidget(_app());
      await _settle(tester);

      expect(_tileValue(tester, 'trends_tile_messages'), '3');
      expect(_tileValue(tester, 'trends_tile_calls'), '3');
      expect(_tileValue(tester, 'trends_tile_scams'), '4');
      expect(_tileValue(tester, 'trends_tile_safe'), '2');
      expect(find.byKey(const Key('trends_chart')), findsOneWidget);
      expect(find.text('Most common: Fake bank / KYC call'), findsOneWidget);
      expect(find.byKey(const Key('trends_learn')), findsOneWidget);
      expect(find.byKey(const Key('trends_recent')), findsOneWidget);
      expect(find.byKey(const Key('trends_practice_note')), findsOneWidget);

      await tester.tap(find.byKey(const Key('trends_include_practice')));
      await tester.pumpAndSettle();
      expect(_tileValue(tester, 'trends_tile_messages'), '4');
      expect(find.byKey(const Key('trends_cat_count_phishing_link')), findsOneWidget);
    });

    testWidgets('clear history asks first, then shows the empty state', (tester) async {
      _tallView(tester);
      await _seed(_records);
      await tester.pumpWidget(_app());
      await _settle(tester);

      await tester.tap(find.byKey(const Key('trends_clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('trends_tile_messages')), findsOneWidget);

      await tester.tap(find.byKey(const Key('trends_clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('trends_clear_ok')));
      await _settle(tester);
      expect(find.byKey(const Key('trends_empty')), findsOneWidget);
      expect(await DetectionHistory().load(), isEmpty);
    });

    testWidgets('server reports: offline message, then data', (tester) async {
      _tallView(tester);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_app(api: _OfflineApi()));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('trends_server_load')));
      await _settle(tester);
      expect(find.byKey(const Key('trends_server_offline')), findsOneWidget);

      await tester.pumpWidget(_app(api: _ServerApi()));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('trends_server_load')));
      await _settle(tester);
      expect(find.text('20 reports'), findsOneWidget);
      expect(find.text('Raipur'), findsOneWidget);
      expect(find.textContaining('sample reports'), findsOneWidget);
      expect(find.byKey(const Key('trends_src_mixed')), findsOneWidget);
    });

    testWidgets('server summary: live and synthetic data are labelled apart, weekly trend, hidden small groups, '
        'emerging-scam alerts', (tester) async {
      _tallView(tester);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(_app(api: _SummaryApi()));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('trends_server_load')));
      await _settle(tester);

      expect(find.text('Live reports'), findsOneWidget);
      expect(find.text('Synthetic demo data'), findsOneWidget);
      expect(find.textContaining('Not real incidents'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('trends_block_live')), matching: find.text('9 reports')),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('trends_block_synthetic')), matching: find.text('300 reports')),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('trends_weekly_live')), matching: find.text('<5')),
          findsOneWidget);
      expect(find.byKey(const Key('trends_suppressed_live')), findsOneWidget);
      expect(find.byKey(const Key('trends_suppressed_synthetic')), findsNothing);

      final alerts = find.byKey(const Key('trends_alerts'));
      expect(find.descendant(of: alerts, matching: find.textContaining('Korba')), findsOneWidget);
      expect(find.descendant(of: alerts, matching: find.textContaining('near-identical')), findsOneWidget);
    });

    test('summary parsing keeps suppressed weeks as null and ignores bad alerts', () {
      final sum = ServerSummary.fromJson({
        'live': {
          'total': 3,
          'weekly': [
            {'week_start': '2026-11-23', 'count': null},
          ],
        },
      });
      expect(sum.minCount, 5);
      expect(sum.live.weekly.single.count, isNull);
      expect(sum.synthetic.total, 0);
      expect(EmergingAlert.tryFrom({'kind': 'other'}), isNull);
    });
  });

  testWidgets('checking a message records it for Scam Trends (example = practice)', (tester) async {
    _tallView(tester);
    SharedPreferences.setMockInitialValues({});
    final clf = ScamClassifier.fromJson(_json('assets/models/scam_model.json'));
    final analyzer = CallAnalyzer.fromJson(_json('assets/rules/call_rules.json'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scamClassifierProvider.overrideWith((ref) async => clf),
          callAnalyzerProvider.overrideWith((ref) async => analyzer),
        ],
        child: const MaterialApp(home: MessageDetectorScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('msg_ex_en')));
    await tester.tap(find.byKey(const Key('msg_check')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('msg_input')), 'Your KYC is pending, account will be blocked today');
    await tester.tap(find.byKey(const Key('msg_check')));
    await _settle(tester);

    final saved = await DetectionHistory().load();
    expect(saved, hasLength(2));
    expect(saved.last.sample, isTrue, reason: 'example chip');
    expect(saved.first.sample, isFalse, reason: 'typed message');
    expect(saved.every((r) => r.kind == 'message'), isTrue);
  });
}
