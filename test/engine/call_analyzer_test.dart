import 'package:flutter_test/flutter_test.dart';
import 'package:scamrakshak_mobile/engine/call_analyzer.dart';
import 'package:scamrakshak_mobile/engine/models.dart';

void main() {
  group('CallAnalyzer', () {
    late CallAnalyzer analyzer;

    setUp(() async {
      analyzer = await CallAnalyzer.load();
    });

    test('Transcript containing arrest returns high risk', () {
      final CallResult result = analyzer.analyze(
          'There is an arrest warrant issued against you by cyber police.');
      expect(result.risk, equals('high'));
      expect(result.matches, isNotEmpty);
      expect(result.matches.any((m) => m.phrase == 'arrest'), isTrue);
    });

    test('Transcript containing KYC returns high risk', () {
      final CallResult result = analyzer.analyze(
          'I am calling from bank headquarters regarding your KYC verification.');
      expect(result.risk, equals('high'));
      expect(result.matches, isNotEmpty);
      expect(result.matches.any((m) => m.phrase == 'kyc'), isTrue);
    });

    test('A normal call transcript returns low risk', () {
      final CallResult result = analyzer.analyze(
          'Hey, do you want to play badminton in the sports complex this evening?');
      expect(result.risk, equals('low'));
      expect(result.matches, isEmpty);
    });

    test('Keyword matching is case-insensitive', () {
      final res1 = analyzer.analyze('Digital ARREST order is in effect.');
      expect(res1.risk, equals('high'));

      final res2 =
          analyzer.analyze('Please complete your KyC details immediately.');
      expect(res2.risk, equals('high'));
    });
  });
}
