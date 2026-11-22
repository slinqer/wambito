// The iOS engine's Dart side (lib/capture/engine/precise_engine.dart) over a fake platform: it
// drives one precise-only recording, stops by its own pauses and limits, and ends with the
// precise text (or the last partial when the precise pass fails).
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/capture/engine/precise_engine.dart';
import 'package:wambito/capture/engine/speech_engine.dart';
import 'package:wambito/capture/engine/voice_channel.dart';
import 'package:wambito/capture/engine/vosk_engine.dart';
import 'package:wambito/capture/models_download.dart';

class _FakeChannel implements VoicePlatform {
  var qualifies = true;
  var permission = true;
  final starts = <({String precisePath, String language})>[];
  var stops = 0;
  late StreamController<VoiceEvent> events;

  @override
  Future<bool> deviceQualifies({int? minRamBytes}) async => qualifies;

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Stream<VoiceEvent> startPrecise({required String precisePath, required String language}) {
    starts.add((precisePath: precisePath, language: language));
    // An onCancel, as a platform stream has one: cancelling it completes.
    events = StreamController<VoiceEvent>(onCancel: () {});
    return events.stream;
  }

  @override
  Future<void> stop() async => stops++;

  final warmUps = <({String precisePath, String language})>[];
  var warm = false;
  var warmFails = false;

  @override
  Future<bool> warmUpPrecise({required String precisePath, required String language}) async {
    if (warmFails) throw PlatformException(code: 'failed');
    warmUps.add((precisePath: precisePath, language: language));
    warm = true;
    return true;
  }

  @override
  Future<bool> isWarmPrecise({required String precisePath, required String language}) async => warm;

  void send(VoiceEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class _Store extends ModelStore {
  _Store(this.path) : super(files: _FakeChannel(), http: Dio());

  String? path;

  @override
  Future<String?> installedPath(String locale) async => path;
}

void main() {
  late _FakeChannel channel;
  late _Store store;
  late PreciseEngine engine;

  setUp(() {
    channel = _FakeChannel();
    store = _Store('/m/c');
    engine = PreciseEngine(channel: channel, models: store);
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  /// Runs [body] in fake time with a listening engine; [heard] collects the transcripts.
  void run(FakeAsync async, List<String> heard, void Function() body, {List<Object>? errors}) {
    engine.listen(locale: 'es').listen(heard.add, onError: errors?.add);
    async.flushMicrotasks();
    body();
  }

  test('available asks whether this phone qualifies', () async {
    expect(await engine.available(), isTrue);
    channel.qualifies = false;
    expect(await engine.available(), isFalse);
  });

  test('warmUp and isWarm use the installed folder and the locale', () async {
    expect(await engine.isWarm(locale: 'es'), isFalse);
    await engine.warmUp(locale: 'es');
    expect(channel.warmUps.single, (precisePath: '/m/c', language: 'es'));
    expect(await engine.isWarm(locale: 'es'), isTrue);
    store.path = null;
    expect(await engine.isWarm(locale: 'es'), isFalse);
    channel.warmFails = true;
    store.path = '/m/c';
    await engine.warmUp(locale: 'es');
  });

  test('stops 1.5 s after the last changed partial', () {
    fakeAsync((async) {
      final heard = <String>[];
      run(async, heard, () {
        channel.send(const VoiceEvent.ready());
        channel.send(const VoiceEvent.partial('dieciocho'));
        async.elapse(const Duration(seconds: 1));
        channel.send(const VoiceEvent.partial('dieciocho lukas'));
        async.elapse(const Duration(milliseconds: 1499));
        expect(channel.stops, 0);
        async.elapse(const Duration(milliseconds: 1));
        expect(channel.stops, 1);
      });
      expect(heard, ['', 'dieciocho', 'dieciocho lukas']);
    });
  });

  test('an unchanged or empty partial does not restart the pause', () {
    fakeAsync((async) {
      run(async, [], () {
        channel.send(const VoiceEvent.ready());
        channel.send(const VoiceEvent.partial('dieciocho'));
        async.elapse(const Duration(seconds: 1));
        channel.send(const VoiceEvent.partial('dieciocho'));
        async.elapse(const Duration(milliseconds: 200));
        channel.send(const VoiceEvent.partial(''));
        async.elapse(const Duration(milliseconds: 299));
        expect(channel.stops, 0);
        async.elapse(const Duration(milliseconds: 1));
        expect(channel.stops, 1);
      });
    });
  });

  test('ends with the refined text', () {
    fakeAsync((async) {
      final heard = <String>[];
      var closed = false;
      engine.listen(locale: 'es').listen(heard.add, onDone: () => closed = true);
      async.flushMicrotasks();
      channel.send(const VoiceEvent.ready());
      channel.send(const VoiceEvent.partial('dieciocho lukas'));
      channel.send(const VoiceEvent.refining());
      channel.send(const VoiceEvent.refined('dieciocho lukas almuerzo'));
      channel.send(const VoiceEvent.done());
      async.flushMicrotasks();
      expect(heard.last, 'dieciocho lukas almuerzo');
      expect(closed, isTrue);
    });
  });

  test('refine_failed keeps the last partial', () {
    fakeAsync((async) {
      final heard = <String>[];
      run(async, heard, () {
        channel.send(const VoiceEvent.ready());
        channel.send(const VoiceEvent.partial('dieciocho lukas'));
        channel.send(const VoiceEvent.refining());
        channel.send(const VoiceEvent.refineFailed('timeout'));
        channel.send(const VoiceEvent.done());
        async.flushMicrotasks();
      });
      expect(heard.last, 'dieciocho lukas');
    });
  });

  test('a full-text partial after refining stands when the precise pass fails', () {
    fakeAsync((async) {
      final heard = <String>[];
      run(async, heard, () {
        channel.send(const VoiceEvent.ready());
        channel.send(const VoiceEvent.partial('almuerzo'));
        // The native side ended the take itself (no stop from Dart), then sends the last live
        // decode with its last word.
        channel.send(const VoiceEvent.refining());
        channel.send(const VoiceEvent.partial('almuerzo 18 lukas'));
        async.elapse(const Duration(seconds: 2));
        // No pause is armed while refining: nothing stops the take again.
        expect(channel.stops, 0);
        channel.send(const VoiceEvent.refineFailed('timeout'));
        channel.send(const VoiceEvent.done());
        async.flushMicrotasks();
      });
      expect(heard.last, 'almuerzo 18 lukas');
      expect(channel.stops, 0);
    });
  });

  test('a short sentence with no partial ends with refined', () {
    fakeAsync((async) {
      final heard = <String>[];
      run(async, heard, () {
        channel.send(const VoiceEvent.ready());
        channel.send(const VoiceEvent.refining());
        channel.send(const VoiceEvent.refined('almuerzo'));
        channel.send(const VoiceEvent.done());
        async.flushMicrotasks();
      });
      expect(heard.last, 'almuerzo');
    });
  });

  test('a blank refined text keeps the last partial', () {
    fakeAsync((async) {
      final heard = <String>[];
      run(async, heard, () {
        channel.send(const VoiceEvent.ready());
        channel.send(const VoiceEvent.partial('almuerzo'));
        channel.send(const VoiceEvent.refining());
        channel.send(const VoiceEvent.refined('  '));
        channel.send(const VoiceEvent.done());
        async.flushMicrotasks();
      });
      expect(heard.last, 'almuerzo');
    });
  });

  test('nothing heard in 8 s stops', () {
    fakeAsync((async) {
      run(async, [], () {
        channel.send(const VoiceEvent.ready());
        async.elapse(const Duration(milliseconds: 7999));
        expect(channel.stops, 0);
        async.elapse(const Duration(milliseconds: 1));
        expect(channel.stops, 1);
      });
    });
  });

  test('30 s stops', () {
    fakeAsync((async) {
      run(async, [], () {
        channel.send(const VoiceEvent.ready());
        // A changing partial now and then keeps the other limits away.
        for (var i = 0; i < 29; i++) {
          channel.send(VoiceEvent.partial('palabra $i'));
          async.elapse(const Duration(seconds: 1));
        }
        expect(channel.stops, 0);
        channel.send(const VoiceEvent.partial('palabra 29'));
        async.elapse(const Duration(seconds: 1));
        expect(channel.stops, 1);
      });
    });
  });

  test('a stuck precise pass is waited at most the limit plus the margin after refining', () {
    fakeAsync((async) {
      final heard = <String>[];
      var closed = false;
      engine.listen(locale: 'es').listen(heard.add, onDone: () => closed = true);
      async.flushMicrotasks();
      channel.send(const VoiceEvent.ready());
      channel.send(const VoiceEvent.partial('almuerzo'));
      channel.send(const VoiceEvent.refining());
      final bound = refineLimit + PreciseEngine.refineMargin;
      async.elapse(bound - const Duration(milliseconds: 1));
      expect(closed, isFalse);
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(closed, isTrue);
      expect(heard.last, 'almuerzo');
    });
  });

  test('the native fallback partial just after the limit still counts', () {
    fakeAsync((async) {
      final heard = <String>[];
      var closed = false;
      engine.listen(locale: 'es').listen(heard.add, onDone: () => closed = true);
      async.flushMicrotasks();
      channel.send(const VoiceEvent.ready());
      channel.send(const VoiceEvent.partial('almuerzo 18'));
      channel.send(const VoiceEvent.refining());
      async.elapse(refineLimit + const Duration(milliseconds: 100));
      expect(closed, isFalse);
      channel.send(const VoiceEvent.partial('almuerzo 18 lukas'));
      channel.send(const VoiceEvent.refineFailed('failed'));
      channel.send(const VoiceEvent.done());
      async.flushMicrotasks();
      expect(closed, isTrue);
      expect(heard.last, 'almuerzo 18 lukas');
    });
  });

  group('errors', () {
    Future<Object?> failWith(String code) async {
      final failure = Completer<Object?>();
      engine.listen(locale: 'es').listen((_) {}, onError: failure.complete);
      await pumpEventQueue();
      channel.send(VoiceEvent.error(code));
      return failure.future;
    }

    test('permission is permissionDenied', () async {
      expect(
        await failWith('permission'),
        isA<SpeechFailure>().having((f) => f.kind, 'kind', SpeechFailureKind.permissionDenied),
      );
    });

    test('no_model is noModel', () async {
      expect(
        await failWith('no_model'),
        isA<SpeechFailure>().having((f) => f.kind, 'kind', SpeechFailureKind.noModel),
      );
    });

    test('any other code is failed', () async {
      expect(
        await failWith('audio'),
        isA<SpeechFailure>()
            .having((f) => f.kind, 'kind', SpeechFailureKind.failed)
            .having((f) => f.detail, 'detail', 'audio'),
      );
    });

    test('no installed folder is noModel, without starting', () async {
      store.path = null;
      await expectLater(
        engine.listen(locale: 'es'),
        emitsError(isA<SpeechFailure>().having((f) => f.kind, 'kind', SpeechFailureKind.noModel)),
      );
      expect(channel.starts, isEmpty);
    });

    test('a denied microphone is permissionDenied, without starting', () async {
      channel.permission = false;
      await expectLater(
        engine.listen(locale: 'es'),
        emitsError(
          isA<SpeechFailure>().having((f) => f.kind, 'kind', SpeechFailureKind.permissionDenied),
        ),
      );
      expect(channel.starts, isEmpty);
    });
  });

  test('it starts the precise recording on the folder with the locale', () async {
    final sub = engine.listen(locale: 'es').listen((_) {});
    await pumpEventQueue();
    expect(channel.starts.single, (precisePath: '/m/c', language: 'es'));
    await sub.cancel();
  });

  test('a second stop is a no-op', () {
    fakeAsync((async) {
      run(async, [], () {
        channel.send(const VoiceEvent.ready());
        unawaited(engine.stop());
        unawaited(engine.stop());
        async.flushMicrotasks();
        expect(channel.stops, 1);
      });
    });
  });

  test('levels forwards the level values', () {
    fakeAsync((async) {
      final levels = <double>[];
      engine.levels.listen(levels.add);
      run(async, [], () {
        channel.send(const VoiceEvent.ready());
        channel.send(const VoiceEvent.level(0.25));
        channel.send(const VoiceEvent.level(0.5));
        async.flushMicrotasks();
      });
      expect(levels, [0.25, 0.5]);
    });
  });

  test('refining emits true, then false when the stream closes', () {
    fakeAsync((async) {
      final states = <bool>[];
      engine.refining.listen(states.add);
      run(async, [], () {
        channel.send(const VoiceEvent.ready());
        channel.send(const VoiceEvent.refining());
        async.flushMicrotasks();
        expect(states, [true]);
        channel.send(const VoiceEvent.refined('almuerzo'));
        channel.send(const VoiceEvent.done());
        async.flushMicrotasks();
      });
      expect(states, [true, false]);
    });
  });

  group('speechEngineProvider', () {
    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [
          voiceChannelProvider.overrideWithValue(channel),
          modelStoreProvider.overrideWithValue(store),
          preciseModelStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('is the precise-only engine on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(container().read(speechEngineProvider), isA<PreciseEngine>());
    });

    test('is Vosk on Android', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(container().read(speechEngineProvider), isA<VoskEngine>());
    });
  });
}
