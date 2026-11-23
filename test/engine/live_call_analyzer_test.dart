import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:scam_rakshak/engine/live_call_analyzer.dart';

const _scam = {
  'scam_digital_arrest.txt': 'digital_arrest',
  'scam_fake_kyc_otp.txt': 'fake_kyc',
  'scam_courier_customs.txt': 'courier_customs',
};
const _genuine = ['genuine_family_call.txt', 'genuine_bank_service.txt'];

List<String> _lines(String name) => File('assets/samples/live/$name')
    .readAsLinesSync()
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LiveCallAnalyzer a;

  setUpAll(() async => a = await LiveCallAnalyzer.load());
  setUp(() => a.reset());

  test('sample folder has 3 scam and 2 genuine scripts', () {
    final names = Directory('assets/samples/live').listSync().map((f) => f.uri.pathSegments.last).toSet();
    expect(names, containsAll([..._scam.keys, ..._genuine]));
    for (final n in [..._scam.keys, ..._genuine]) {
      expect(_lines(n).length, greaterThanOrEqualTo(6), reason: n);
    }
  });

  for (final e in _scam.entries) {
    test('${e.key} reaches high within the first half', () {
      final lines = _lines(e.key);
      int? highAt;
      var lastRisk = 'low';
      for (var i = 0; i < lines.length; i++) {
        final s = a.add(lines[i]);
        const order = {'low': 0, 'medium': 1, 'high': 2};
        expect(order[s.risk]!, greaterThanOrEqualTo(order[lastRisk]!), reason: 'risk never drops');
        lastRisk = s.risk;
        if (s.risk == 'high') highAt ??= i;
      }
      expect(highAt, isNotNull);
      expect(highAt! < lines.length / 2, isTrue, reason: 'high at chunk ${highAt + 1}/${lines.length}');
      final types = a.add('').matches.map((m) => m.scriptType).toSet();
      expect(types, contains(e.value));
    });
  }

  for (final g in _genuine) {
    test('$g never exceeds low', () {
      for (final l in _lines(g)) {
        final s = a.add(l);
        expect(s.risk, 'low', reason: 'after "$l": ${s.matches.map((m) => m.phrase)}');
      }
    });
  }

  test('every existing sample call (all scam categories) works chunk by chunk', () {
    final files = Directory('assets/samples').listSync().whereType<File>().where((f) => f.path.endsWith('.txt'));
    expect(files.length, greaterThanOrEqualTo(13));
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      // Split into sentence-sized chunks like a live call would arrive.
      final chunks = f.readAsStringSync().split(RegExp(r'(?<=[.?!।])\s+|\n+')).where((c) => c.trim().isNotEmpty);
      a.reset();
      var s = LiveCallState.empty;
      for (final c in chunks) {
        s = a.add(c);
        if (name.startsWith('genuine')) expect(s.risk, 'low', reason: '$name after "$c"');
      }
      if (!name.startsWith('genuine')) expect(s.risk, 'high', reason: name);
    }
  });

  group('ASR noise tolerance', () {
    test('normalises nukta, chandrabindu, punctuation and case', () {
      expect(LiveCallAnalyzer.normalizeWord('फ़्रीज़'), LiveCallAnalyzer.normalizeWord('फ्रीज'));
      expect(LiveCallAnalyzer.normalizeWord('हँ'), LiveCallAnalyzer.normalizeWord('हं'));
      expect(LiveCallAnalyzer.tokenize('  Digital,   ARREST!! ').map((t) => t.norm), ['digital', 'arrest']);
    });

    test('edit distance 1 only for tokens of 5+ characters', () {
      expect(LiveCallAnalyzer.fuzzyEquals('arrest', 'arest'), isTrue);
      expect(LiveCallAnalyzer.fuzzyEquals('digital', 'digitel'), isTrue);
      expect(LiveCallAnalyzer.fuzzyEquals('laundering', 'londering'), isFalse);
      expect(LiveCallAnalyzer.fuzzyEquals('otp', 'otb'), isFalse);
      expect(LiveCallAnalyzer.fuzzyEquals('cbi', 'cbx'), isFalse);
    });

    test('misheard phrase still matches', () {
      final s = a.add('aap digitel arest me ho');
      expect(s.matches.map((m) => m.scriptType), contains('digital_arrest'));
      expect(s.matches.first.phrase, 'digitel arest');
    });
  });

  group('accumulation', () {
    test('phrase split across chunks is found; newMatches is per chunk; dedupe', () {
      var s = a.add('this is about money');
      expect(s.matches, isEmpty);
      s = a.add('laundering case against you');
      expect(s.newMatches.map((m) => m.phrase), ['money laundering']);
      s = a.add('money laundering again');
      expect(s.newMatches, isEmpty);
      expect(s.matches.where((m) => m.scriptType == 'digital_arrest').length, 1);
      expect(s.transcript, 'this is about money laundering case against you money laundering again');
    });

    test('two different script types make it high', () {
      var s = a.add('main cbi se bol raha hoon');
      expect(s.risk, 'low');
      s = a.add('woh otp bata do');
      expect(s.risk, 'high');
      expect(s.score, 1.0);
    });

    test('one clear match is medium, pressure alone stays low', () {
      expect(a.add('urgent please').risk, 'low');
      a.reset();
      expect(a.add('your kyc update is pending').risk, 'medium');
    });

    test('negated OTP request is ignored; reset clears state', () {
      final s = a.add('never share the otp with anyone');
      expect(s.matches, isEmpty);
      a.add('digital arrest');
      a.reset();
      expect(a.add('').transcript, '');
      expect(a.add('').matches, isEmpty);
    });

    test('uses the same rule file as CallAnalyzer', () {
      final rules = jsonDecode(File(LiveCallAnalyzer.assetPath).readAsStringSync()) as Map<String, dynamic>;
      final b = LiveCallAnalyzer.fromJson(rules);
      expect(b.highLevel, (rules['levels'] as Map)['high']);
    });
  });
}
