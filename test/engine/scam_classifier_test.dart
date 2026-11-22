import 'package:flutter_test/flutter_test.dart';
import 'package:scamrakshak/engine/models.dart';
import 'package:scamrakshak/engine/scam_classifier.dart';

void main() {
  group('ScamClassifier', () {
    late ScamClassifier classifier;

    setUp(() async {
      classifier = await ScamClassifier.load();
    });

    test('Text containing OTP is classified as scam', () {
      final ScamResult result =
          classifier.classify('Your one-time OTP is 492019. Do not share.');
      expect(result.label, equals('scam'));
      expect(result.score, greaterThan(0.5));
      expect(result.reasons, isNotEmpty);
      expect(result.reasons.any((r) => r.phrase == 'otp'), isTrue);
    });

    test('Text containing KYC is classified as scam', () {
      final ScamResult result = classifier.classify(
          'Update your KYC documents immediately to continue services.');
      expect(result.label, equals('scam'));
      expect(result.score, greaterThan(0.5));
      expect(result.reasons, isNotEmpty);
      expect(result.reasons.any((r) => r.phrase == 'kyc'), isTrue);
    });

    test('Text containing urgent is classified as scam', () {
      final ScamResult result = classifier.classify(
          'URGENT: Action required on your electricity connection.');
      expect(result.label, equals('scam'));
      expect(result.score, greaterThan(0.5));
      expect(result.reasons, isNotEmpty);
      expect(result.reasons.any((r) => r.phrase == 'urgent'), isTrue);
    });

    test('Text containing blocked is classified as scam', () {
      final ScamResult result = classifier
          .classify('Your SIM card will be blocked within 24 hours.');
      expect(result.label, equals('scam'));
      expect(result.score, greaterThan(0.5));
      expect(result.reasons, isNotEmpty);
      expect(result.reasons.any((r) => r.phrase == 'blocked'), isTrue);
    });

    test('A normal message without these keywords is classified as genuine',
        () {
      final ScamResult result = classifier.classify(
          'Hello, can we meet for lunch tomorrow at the cafeteria?');
      expect(result.label, equals('genuine'));
      expect(result.score, lessThan(0.5));
      expect(result.reasons, isEmpty);
    });

    test('Keyword matching is case-insensitive', () {
      final res1 = classifier.classify('Please submit your KyC right now');
      expect(res1.label, equals('scam'));

      final res2 = classifier.classify('Your OtP code has expired');
      expect(res2.label, equals('scam'));

      final res3 = classifier.classify('This is UrGeNt');
      expect(res3.label, equals('scam'));

      final res4 = classifier.classify('Account BLOCKED');
      expect(res4.label, equals('scam'));
    });

    test('Empty and whitespace-only text is handled safely as genuine', () {
      final resEmpty = classifier.classify('');
      expect(resEmpty.label, equals('genuine'));
      expect(resEmpty.score, lessThan(0.5));
      expect(resEmpty.reasons, isEmpty);

      final resSpaces = classifier.classify('   \t\n  ');
      expect(resSpaces.label, equals('genuine'));
      expect(resSpaces.score, lessThan(0.5));
      expect(resSpaces.reasons, isEmpty);
    });
  });
}


