import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models_download.dart';

/// Which of the two Vosk recognizers a result comes from.
enum VoicePass { free, grammar }

/// What the recording sends while it runs (android/.../voice/VoiceChannel.kt).
sealed class VoiceEvent {
  const VoiceEvent();

  /// The model is loaded and the microphone records: the person can start talking.
  const factory VoiceEvent.ready() = VoiceReady;

  /// The free pass's guess at the words being said right now.
  const factory VoiceEvent.partial(String text) = VoicePartial;

  /// A recognizer's result JSON at an endpoint, or at the end (`getResult()`/`getFinalResult()`).
  const factory VoiceEvent.result(VoicePass pass, String json) = VoiceResult;

  /// The microphone's level over the last 40 ms, 0 (silence) to 1 (loud). Only this number comes
  /// from the audio: the audio itself never leaves Kotlin.
  const factory VoiceEvent.level(double value) = VoiceLevel;

  /// Recording has ended and both final results were sent.
  const factory VoiceEvent.done() = VoiceDone;

  /// The model or the microphone failed.
  const factory VoiceEvent.error(String code) = VoiceError;

  /// Vosk's results are in and the precise model is rewriting the recording.
  const factory VoiceEvent.refining() = VoiceRefining;

  /// The precise model's text for the whole sentence.
  const factory VoiceEvent.refined(String text) = VoiceRefined;

  /// The precise pass gave nothing: [code] is `timeout` or `failed`. Vosk's text stands.
  const factory VoiceEvent.refineFailed(String code) = VoiceRefineFailed;

  static VoiceEvent? fromMap(Object? map) {
    if (map is! Map) return null;
    return switch (map['type']) {
      'ready' => const VoiceEvent.ready(),
      'partial' => VoiceEvent.partial(map['text'] as String? ?? ''),
      'result' => VoiceEvent.result(
        map['pass'] == 'grammar' ? VoicePass.grammar : VoicePass.free,
        map['json'] as String? ?? '',
      ),
      'level' => VoiceEvent.level((map['value'] as num?)?.toDouble() ?? 0),
      'done' => const VoiceEvent.done(),
      'error' => VoiceEvent.error(map['code'] as String? ?? 'failed'),
      'refining' => const VoiceEvent.refining(),
      'refined' => VoiceEvent.refined(map['text'] as String? ?? ''),
      'refine_failed' => VoiceEvent.refineFailed(map['code'] as String? ?? 'failed'),
      _ => null,
    };
  }
}

class VoiceReady extends VoiceEvent {
  const VoiceReady();
}

class VoicePartial extends VoiceEvent {
  const VoicePartial(this.text);
  final String text;
}

class VoiceResult extends VoiceEvent {
  const VoiceResult(this.pass, this.json);
  final VoicePass pass;
  final String json;
}

class VoiceLevel extends VoiceEvent {
  const VoiceLevel(this.value);
  final double value;
}

class VoiceDone extends VoiceEvent {
  const VoiceDone();
}

class VoiceError extends VoiceEvent {
  const VoiceError(this.code);
  final String code;
}

class VoiceRefining extends VoiceEvent {
  const VoiceRefining();
}

class VoiceRefined extends VoiceEvent {
  const VoiceRefined(this.text);
  final String text;
}

class VoiceRefineFailed extends VoiceEvent {
  const VoiceRefineFailed(this.code);
  final String code;
}

/// The Android side of listening: the microphone, the two recognizers, and the model files.
abstract interface class VoicePlatform implements ModelFiles {
  /// Whether Vosk's native library loads on this phone.
  Future<bool> supported();

  /// Whether this phone can run the precise model: arm64, at least 3 GB of RAM (or [minRamBytes],
  /// a bigger model's floor), not low-RAM, and sherpa-onnx linked.
  Future<bool> deviceQualifies({int? minRamBytes});

  /// Asks for the microphone when it has not been granted yet; true when granted.
  Future<bool> requestPermission();

  /// Loads the model at [modelPath] in the background and keeps it loaded while the process lives
  /// (until memory pressure or [releaseModels]); true once it is. Never opens the microphone.
  /// With [precisePath] (and its [language]) the precise model is loaded too.
  Future<bool> warmUp(String modelPath, {String? precisePath, String? language});

  /// Whether the model at [modelPath] (and the precise one, when given) is loaded and the
  /// microphone is allowed: listening then starts at once.
  Future<bool> isWarm(String modelPath, {String? precisePath, String? language});

  /// Records (16 kHz mono PCM16, `VOICE_RECOGNITION`) into a free and a grammar-biased recognizer
  /// on the model at [modelPath], until [stop]. With [precisePath] and [language] the recording is
  /// kept and rewritten by the precise model once recording ends ([VoiceRefining] and after).
  Stream<VoiceEvent> start({
    required String modelPath,
    required String grammar,
    String? precisePath,
    String? language,
  });

  /// iOS: loads the precise model at [precisePath] for [language] in the background; true once it
  /// is. Never opens the microphone.
  Future<bool> warmUpPrecise({required String precisePath, required String language});

  /// iOS: whether the precise model is loaded and the microphone is allowed.
  Future<bool> isWarmPrecise({required String precisePath, required String language});

  /// iOS: records into the precise model alone, with live partials while recording and the
  /// rewritten sentence after [stop] ([VoiceRefining], [VoiceRefined] or [VoiceRefineFailed],
  /// then [VoiceDone]). Never sends [VoiceResult]; a failure is a [VoiceError] with no [VoiceDone].
  Stream<VoiceEvent> startPrecise({required String precisePath, required String language});

  /// Stops recording: the final results follow, then [VoiceDone].
  Future<void> stop();
}

/// [VoicePlatform] over the `wambito/voice` channels (VoiceChannel.kt).
class VoiceChannel implements VoicePlatform {
  const VoiceChannel();

  static const _methods = MethodChannel('wambito/voice');
  static const _events = EventChannel('wambito/voice/events');

  @override
  Future<bool> supported() async {
    try {
      return await _methods.invokeMethod<bool>('supported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> deviceQualifies({int? minRamBytes}) async {
    try {
      return await _methods.invokeMethod<bool>('deviceQualifies', {'minRamBytes': ?minRamBytes}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async =>
      await _methods.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<bool> warmUp(String modelPath, {String? precisePath, String? language}) async =>
      await _methods.invokeMethod<bool>(
        'warmUp',
        _args(modelPath, precisePath: precisePath, language: language),
      ) ??
      false;

  @override
  Future<bool> isWarm(String modelPath, {String? precisePath, String? language}) async =>
      await _methods.invokeMethod<bool>(
        'isWarm',
        _args(modelPath, precisePath: precisePath, language: language),
      ) ??
      false;

  @override
  Future<bool> warmUpPrecise({required String precisePath, required String language}) async =>
      await _methods.invokeMethod<bool>('warmUp', {
        'precisePath': precisePath,
        'language': language,
      }) ??
      false;

  @override
  Future<bool> isWarmPrecise({required String precisePath, required String language}) async =>
      await _methods.invokeMethod<bool>('isWarm', {
        'precisePath': precisePath,
        'language': language,
      }) ??
      false;

  @override
  Stream<VoiceEvent> startPrecise({required String precisePath, required String language}) async* {
    await _dropStaleEvents();
    yield* _events
        .receiveBroadcastStream({'precisePath': precisePath, 'language': language})
        .map(VoiceEvent.fromMap)
        .where((e) => e != null)
        .cast<VoiceEvent>();
  }

  /// The channel's arguments; the precise ones only when there is a precise model.
  static Map<String, Object> _args(
    String modelPath, {
    String? grammar,
    String? precisePath,
    String? language,
  }) => {
    'modelPath': modelPath,
    'grammar': ?grammar,
    'precisePath': ?precisePath,
    'language': ?language,
  };

  @override
  Stream<VoiceEvent> start({
    required String modelPath,
    required String grammar,
    String? precisePath,
    String? language,
  }) async* {
    await _dropStaleEvents();
    yield* _events
        .receiveBroadcastStream(
          _args(modelPath, grammar: grammar, precisePath: precisePath, language: language),
        )
        .map(VoiceEvent.fromMap)
        .where((e) => e != null)
        .cast<VoiceEvent>();
  }

  /// Throws away what the platform sent on the event channel while nobody listened. The engine lets
  /// go of the stream the moment it has `done`, so the stream's own end (`endOfStream`, which
  /// arrives a moment later) finds no handler and the engine's channel buffers keep it for the
  /// channel's next listener: the next session's, which would end at once, unheard, with nothing
  /// recognised (the widget's 🎤 a minute after a sentence that finished by itself opened the typing
  /// field). Nothing the platform sends between two listens is meant for the next one.
  Future<void> _dropStaleEvents() =>
      // `drain` is the one call that empties a channel's buffer without listening on it; the
      // replacement it points to (`setListener`) would hand the stale message to a listener.
      // ignore: deprecated_member_use
      ui.channelBuffers.drain(_events.name, (data, callback) async => callback(null));

  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');

  @override
  Future<String> modelsDirectory() async =>
      (await _methods.invokeMethod<String>('modelsDirectory'))!;

  @override
  Future<void> unzip(String zip, String into) =>
      _methods.invokeMethod<void>('unzip', {'zip': zip, 'into': into});

  @override
  Future<void> releaseModels() => _methods.invokeMethod<void>('releaseModels');

  @override
  Future<int?> freeBytes() => _methods.invokeMethod<int>('freeBytes');
}

final voiceChannelProvider = Provider<VoicePlatform>((ref) => const VoiceChannel());
