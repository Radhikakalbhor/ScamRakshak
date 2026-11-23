import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Records the microphone into 16 kHz mono WAV files, one chunk at a time.
abstract class ChunkRecorder {
  /// Asks for RECORD_AUDIO if needed; false when the user refuses.
  Future<bool> hasPermission();
  Future<void> start(String path);

  /// Stops the current chunk and returns its file path.
  Future<String?> stop();

  /// Current input level in dBFS (about -160 = silence, 0 = loudest).
  Future<double> levelDb();
}

class PluginChunkRecorder implements ChunkRecorder {
  final AudioRecorder _r = AudioRecorder();

  @override
  Future<bool> hasPermission() => _r.hasPermission();

  @override
  Future<void> start(String path) => _r.start(
    const RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
      // Keep the raw speaker sound: call-style processing can mute far-away voices.
      echoCancel: false,
      noiseSuppress: false,
      autoGain: true,
      // The default (pause) stops recording as soon as a phone call takes audio focus,
      // which left every chunk silent during a real call.
      audioInterruption: AudioInterruptionMode.none,
    ),
    path: path,
  );

  @override
  Future<String?> stop() => _r.stop();

  @override
  Future<double> levelDb() async => (await _r.getAmplitude()).current;
}

/// Plays one bundled demo clip and completes when it has finished (or was stopped).
abstract class DemoAudio {
  Future<void> play(String assetPath);
  Future<void> stop();
}

class PluginDemoAudio implements DemoAudio {
  final AudioPlayer _p = AudioPlayer();
  Completer<void>? _done;

  PluginDemoAudio() {
    _p.onPlayerComplete.listen((_) => _complete());
  }

  void _complete() {
    final c = _done;
    _done = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<void> play(String assetPath) async {
    await stop();
    final c = _done = Completer<void>();
    // AssetSource paths are relative to 'assets/'.
    await _p.play(AssetSource(assetPath.replaceFirst('assets/', '')));
    // A clip is a few seconds; never hang the demo if the completion event is lost.
    await c.future.timeout(const Duration(seconds: 30), onTimeout: () {});
  }

  @override
  Future<void> stop() async {
    _complete();
    await _p.stop();
  }
}

final chunkRecorderProvider = Provider<ChunkRecorder>((ref) => PluginChunkRecorder());
final demoAudioProvider = Provider<DemoAudio>((ref) => PluginDemoAudio());

/// Folder for the short-lived chunk files.
final liveTempDirProvider = Provider<Future<Directory> Function()>((ref) => getTemporaryDirectory);

/// Keeps the screen on while listening.
final wakelockProvider = Provider<void Function(bool on)>(
  (ref) => (on) {
    (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((_) {});
  },
);
