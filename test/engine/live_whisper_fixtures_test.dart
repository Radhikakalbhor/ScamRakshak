import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:scam_rakshak/engine/live_call_analyzer.dart';

/// Real faster-whisper output for the demo clips (assets/samples/live/audio), one line per clip,
/// written by `backend/test_live_transcribe.py --dump` with the backend's live settings.
/// Checks that the analyzer copes with genuine ASR noise, not just with clean text.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LiveCallAnalyzer a;
  setUpAll(() async => a = await LiveCallAnalyzer.load());
  setUp(() => a.reset());

  List<String> lines(String model, String script) => File('test/engine/fixtures/whisper/$model/$script.txt')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();

  String run(String model, String script, {void Function(int i, LiveCallState s)? each}) {
    a.reset();
    var s = LiveCallState.empty;
    final ls = lines(model, script);
    for (var i = 0; i < ls.length; i++) {
      s = a.add(ls[i]);
      each?.call(i, s);
    }
    return s.risk;
  }

  for (final script in ['scam_digital_arrest', 'scam_fake_kyc_otp', 'scam_courier_customs']) {
    test('small model: $script reaches high within the first half', () {
      int? at;
      final n = lines('small', script).length;
      run('small', script, each: (i, s) => s.risk == 'high' ? at ??= i : null);
      expect(at, isNotNull, reason: '$script never high');
      expect(at! < n / 2, isTrue, reason: '$script high only at chunk ${at! + 1}/$n');
    });
  }

  for (final model in ['small', 'base']) {
    for (final script in ['genuine_family_call', 'genuine_bank_service']) {
      test('$model model: $script stays low', () {
        run(model, script, each: (i, s) => expect(s.risk, 'low', reason: 'chunk ${i + 1}: ${s.matches.map((m) => m.phrase)}'));
      });
    }
  }

  test('base model: English scam calls are still caught (Hindi speech is too garbled for base)', () {
    expect(run('base', 'scam_fake_kyc_otp'), 'high');
    expect(run('base', 'scam_courier_customs'), 'high');
  });
}
