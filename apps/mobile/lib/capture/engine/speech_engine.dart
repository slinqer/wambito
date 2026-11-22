import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models_download.dart';
import 'precise_engine.dart';
import 'voice_channel.dart';
import 'vosk_engine.dart';

/// Turns speech into text, on the phone (spec section 6.1.4). The engine is the voice spike's
/// choice: Vosk, two passes merged (vosk_engine.dart). Capture only sees this interface, so tests
/// and the integration tests put a fixed transcript in place of audio.
abstract class SpeechEngine {
  /// Whether this phone can run the engine at all (with or without a model downloaded).
  Future<bool> available();

  /// Listens in [locale] (`es`, `en`, `it` or `pt`) until [stop], or until the person stops talking. The first
  /// event comes once the engine really listens (an empty one when nothing is heard yet), so the
  /// prompt shows only then. Each event is the transcript so far; the last one, just before the
  /// stream closes, is the final one. Fails with a [SpeechFailure].
  Stream<String> listen({required String locale});

  /// Stops listening: the stream sends the final transcript, then closes.
  Future<void> stop();

  /// Whether listening in [locale] starts at once: its model is already loaded (by [warmUp], or by
  /// an earlier sentence) and the microphone is allowed. The capture sheet then shows no "preparing"
  /// state at all.
  Future<bool> isWarm({required String locale});

  /// Loads [locale]'s model in the background, if it is downloaded, so the next [listen] does not
  /// wait for it. Never records, and never fails: when it cannot, [listen] loads it as before.
  Future<void> warmUp({required String locale});

  /// The microphone's level while [listen] runs, 0 (silence) to 1 (loud), about 25 times a second.
  /// Only the level: audio never leaves the engine. Silent when nothing listens.
  Stream<double> get levels;

  /// True from the moment the precise model starts rewriting a sentence until the [listen] stream
  /// closes, then false. Silent when nothing listens or when no precise pass runs.
  Stream<bool> get refining;
}

enum SpeechFailureKind {
  /// The person said no to the microphone.
  permissionDenied,

  /// The language's model is not downloaded.
  noModel,

  /// The engine or the microphone failed.
  failed,
}

class SpeechFailure implements Exception {
  const SpeechFailure(this.kind, [this.detail]);

  final SpeechFailureKind kind;
  final String? detail;

  @override
  String toString() => 'SpeechFailure(${kind.name}${detail == null ? '' : ', $detail'})';
}

/// The phone's speech engine: the precise model alone on iOS (precise_engine.dart), Vosk with the
/// optional precise pass on Android.
final speechEngineProvider = Provider<SpeechEngine>(
  (ref) => defaultTargetPlatform == TargetPlatform.iOS
      ? PreciseEngine(
          channel: ref.watch(voiceChannelProvider),
          models: ref.watch(modelStoreProvider),
        )
      : VoskEngine(
          channel: ref.watch(voiceChannelProvider),
          models: ref.watch(modelStoreProvider),
          precise: ref.watch(preciseModelStoreProvider),
        ),
);
