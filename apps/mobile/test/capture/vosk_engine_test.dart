// The Vosk engine's Dart side (lib/capture/engine/vosk_engine.dart) over a fake platform channel:
// what it asks for before listening, how it turns the two passes' results into one transcript,
// and when it stops by itself.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/capture/engine/speech_engine.dart';
import 'package:wambito/capture/engine/voice_channel.dart';
import 'package:wambito/capture/engine/vosk_engine.dart';
import 'package:wambito/capture/models_download.dart';

class _FakeChannel implements VoicePlatform {
  var supportedAnswer = true;
  var permission = true;

  /// When set, the permission answer waits for it.
  Completer<bool>? permissionAnswer;
  final starts = <({String modelPath, String grammar, String? precisePath, String? language})>[];
  var stops = 0;
  StreamController<VoiceEvent>? events;

  @override
  Future<bool> supported() async => supportedAnswer;

  var qualifies = false;

  @override
  Future<bool> deviceQualifies({int? minRamBytes}) async => qualifies;

  @override
  Future<bool> requestPermission() async => permissionAnswer?.future ?? permission;

  @override
  Stream<VoiceEvent> start({
    required String modelPath,
    required String grammar,
    String? precisePath,
    String? language,
  }) {
    starts.add((
      modelPath: modelPath,
      grammar: grammar,
      precisePath: precisePath,
      language: language,
    ));
    events = StreamController<VoiceEvent>();
    return events!.stream;
  }

  @override
  Future<bool> warmUpPrecise({required String precisePath, required String language}) async =>
      false;

  @override
  Future<bool> isWarmPrecise({required String precisePath, required String language}) async =>
      false;

  @override
  Stream<VoiceEvent> startPrecise({required String precisePath, required String language}) =>
      throw UnimplementedError('iOS only');

  @override
  Future<void> stop() async {
    stops++;
  }

  /// The paths a model was asked to be loaded from, and whether one is loaded.
  final warmUps = <String>[];

  /// The precise model path and language each [warmUp] and [isWarm] came with.
  final preciseWarmUps = <({String? precisePath, String? language})>[];
  final preciseWarmChecks = <({String? precisePath, String? language})>[];
  String? loaded;
  var warmFails = false;

  @override
  Future<bool> warmUp(String modelPath, {String? precisePath, String? language}) async {
    if (warmFails) throw PlatformException(code: 'failed');
    warmUps.add(modelPath);
    preciseWarmUps.add((precisePath: precisePath, language: language));
    loaded = modelPath;
    return true;
  }

  @override
  Future<bool> isWarm(String modelPath, {String? precisePath, String? language}) async {
    preciseWarmChecks.add((precisePath: precisePath, language: language));
    return loaded == modelPath;
  }

  @override
  Future<String> modelsDirectory() async => '/models';

  @override
  Future<void> unzip(String zip, String into) async {}

  @override
  Future<void> releaseModels() async {}

  @override
  Future<int?> freeBytes() async => 1 << 40;

  void send(VoiceEvent event) => events!.add(event);

  /// What the platform does on stop: the last results of both passes, then the end.
  Future<void> finish({String free = '{"text":""}', String grammar = '{"text":""}'}) async {
    send(VoiceEvent.result(VoicePass.free, free));
    send(VoiceEvent.result(VoicePass.grammar, grammar));
    send(const VoiceEvent.done());
    await events!.close();
  }
}

class _Store extends ModelStore {
  _Store(this.path) : super(files: _FakeChannel(), http: Dio());

  String? path;

  @override
  Future<String?> installedPath(String locale) async => path;
}

String _result(List<(String, double, double)> words) =>
    '{"result":[${words.map((w) => '{"conf":1.0,"word":"${w.$1}","start":${w.$2},"end":${w.$3}}').join(',')}],'
    '"text":"${words.map((w) => w.$1).join(' ')}"}';

void main() {
  late _FakeChannel channel;
  late _Store store;
  late _Store precise;
  late VoskEngine engine;

  setUp(() {
    channel = _FakeChannel();
    store = _Store('/models/voice/vosk-model-small-es-0.42');
    precise = _Store(null);
    engine = VoskEngine(channel: channel, models: store, precise: precise);
  });

  test('available asks the platform whether Vosk runs on this phone', () async {
    expect(await engine.available(), isTrue);
    channel.supportedAnswer = false;
    expect(await engine.available(), isFalse);
  });

  test('listen without the model fails with noModel, and asks nothing else', () async {
    store.path = null;
    await expectLater(
      engine.listen(locale: 'es'),
      emitsError(isA<SpeechFailure>().having((f) => f.kind, 'kind', SpeechFailureKind.noModel)),
    );
    expect(channel.starts, isEmpty);
  });

  test('a denied microphone fails with permissionDenied, without recording', () async {
    channel.permission = false;
    await expectLater(
      engine.listen(locale: 'es'),
      emitsError(
        isA<SpeechFailure>().having((f) => f.kind, 'kind', SpeechFailureKind.permissionDenied),
      ),
    );
    expect(channel.starts, isEmpty);
  });

  test('it starts both passes on the model with the locale\'s grammar', () async {
    final heard = engine.listen(locale: 'es').toList();
    await pumpEventQueue();
    expect(channel.starts.single.modelPath, '/models/voice/vosk-model-small-es-0.42');
    expect(channel.starts.single.grammar, contains('"gasté"'));
    await channel.finish();
    await heard;
  });

  test('partials show while speaking; the end gives the merged transcript (rule v2)', () async {
    final heard = <String>[];
    final done = engine.listen(locale: 'es').listen(heard.add).asFuture<void>();
    await pumpEventQueue();
    channel.send(const VoiceEvent.partial('me de'));
    channel.send(const VoiceEvent.partial('me de ópalo'));
    // The grammar pass hits an endpoint mid-sentence: its intermediate result counts too.
    channel.send(
      VoiceEvent.result(VoicePass.grammar, _result([('medio', 0.30, 0.60), ('palo', 0.60, 1.00)])),
    );
    await pumpEventQueue();
    await channel.finish(
      free: _result([
        ('me', 0.30, 0.42),
        ('de', 0.42, 0.55),
        ('ópalo', 0.55, 1.00),
        ('en', 1.10, 1.20),
        ('el', 1.20, 1.30),
        ('éxito', 1.30, 1.80),
      ]),
      grammar: _result([('[unk]', 1.10, 1.80)]),
    );
    await done;
    expect(heard.first, 'me de');
    expect(heard.last, 'medio palo en el éxito');
  });

  test(
    'a mid-sentence grammar endpoint does not repeat the words the partial still holds',
    () async {
      final heard = <String>[];
      final done = engine.listen(locale: 'es').listen(heard.add).asFuture<void>();
      await pumpEventQueue();
      channel.send(const VoiceEvent.partial('dos euros'));
      // The grammar pass ends an utterance after "dos euros"; the free pass has not, so its next
      // partial still starts at "dos".
      channel.send(
        VoiceEvent.result(VoicePass.grammar, _result([('dos', 0.30, 0.50), ('euros', 0.50, 0.90)])),
      );
      channel.send(const VoiceEvent.partial('dos euros en'));
      channel.send(const VoiceEvent.partial('dos euros en café'));
      await pumpEventQueue();
      await channel.finish(
        free: _result([
          ('dos', 0.30, 0.50),
          ('euros', 0.50, 0.90),
          ('en', 1.00, 1.10),
          ('café', 1.10, 1.50),
        ]),
      );
      await done;
      expect(heard.where((t) => t.isNotEmpty), [
        'dos euros',
        'dos euros en',
        'dos euros en café',
        'dos euros en café',
      ]);
    },
  );

  test('after a free endpoint, the next partial follows the words already heard', () async {
    final heard = <String>[];
    final done = engine.listen(locale: 'es').listen(heard.add).asFuture<void>();
    await pumpEventQueue();
    channel.send(const VoiceEvent.partial('almuerzo'));
    channel.send(VoiceEvent.result(VoicePass.free, _result([('almuerzo', 0, 0.5)])));
    channel.send(
      VoiceEvent.result(VoicePass.grammar, _result([('quince', 0.6, 0.9), ('mil', 1.0, 1.3)])),
    );
    channel.send(const VoiceEvent.partial('quince mil'));
    await pumpEventQueue();
    await channel.finish(free: _result([('quince', 0.6, 0.9), ('mil', 1.0, 1.3)]));
    await done;
    expect(heard.where((t) => t.isNotEmpty), [
      'almuerzo',
      'almuerzo quince mil',
      'almuerzo quince mil',
    ]);
  });

  test('results from several endpoints add up, in time order', () async {
    final heard = engine.listen(locale: 'es').toList();
    await pumpEventQueue();
    channel.send(
      VoiceEvent.result(VoicePass.free, _result([('almuerzo', 0, 0.5), ('quince', 0.5, 0.9)])),
    );
    channel.send(VoiceEvent.result(VoicePass.free, _result([('mil', 1.5, 1.9)])));
    await channel.finish();
    expect((await heard).last, 'almuerzo quince mil');
  });

  test('a platform error ends the stream with a failure', () async {
    final heard = engine.listen(locale: 'es').toList();
    await pumpEventQueue();
    channel.send(const VoiceEvent.error('mic_unavailable'));
    await expectLater(
      heard,
      throwsA(isA<SpeechFailure>().having((f) => f.kind, 'kind', SpeechFailureKind.failed)),
    );
  });

  test('closing before the permission answer never starts recording', () async {
    final answer = Completer<bool>();
    channel.permissionAnswer = answer;
    final subscription = engine.listen(locale: 'es').listen((_) {});
    await pumpEventQueue();
    await subscription.cancel();
    answer.complete(true);
    await pumpEventQueue();
    expect(channel.starts, isEmpty);
  });

  test('the platform being ready shows as an empty first event', () async {
    final heard = <String>[];
    final done = engine.listen(locale: 'es').listen(heard.add).asFuture<void>();
    await pumpEventQueue();
    expect(heard, isEmpty, reason: 'nothing before the model is loaded and the mic records');
    channel.send(const VoiceEvent.ready());
    await pumpEventQueue();
    expect(heard, ['']);
    await channel.finish();
    await done;
  });

  test('stopping twice asks the platform once', () async {
    final heard = engine.listen(locale: 'es').toList();
    await pumpEventQueue();
    await engine.stop();
    await engine.stop();
    expect(channel.stops, 1);
    await channel.finish();
    await heard;
  });

  test('stop asks the platform to stop (it then sends the last results)', () async {
    final heard = engine.listen(locale: 'es').toList();
    await pumpEventQueue();
    await engine.stop();
    expect(channel.stops, 1);
    await channel.finish();
    await heard;
  });

  // In testWidgets, time is fake: pump moves it on.
  testWidgets('a pause after something was said stops by itself', (tester) async {
    engine.listen(locale: 'es').listen((_) {});
    await tester.pump();
    channel.send(VoiceEvent.result(VoicePass.free, _result([('almuerzo', 0, 0.5)])));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(channel.stops, 0);
    // Speaking again pushes the end back.
    channel.send(const VoiceEvent.partial('dieciocho'));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(channel.stops, 0);
    channel.send(VoiceEvent.result(VoicePass.free, _result([('dieciocho', 0.6, 1.0)])));
    await tester.pump(endOfSpeechPause);
    expect(channel.stops, 1);
    await channel.finish();
    await tester.pump();
  });

  testWidgets('nothing said at all stops too, counting from ready, not from the model load', (
    tester,
  ) async {
    engine.listen(locale: 'es').listen((_) {});
    await tester.pump();
    // A slow model load: the person has not been asked anything yet.
    await tester.pump(nothingHeardLimit + const Duration(seconds: 1));
    expect(channel.stops, 0);
    channel.send(const VoiceEvent.ready());
    await tester.pump(nothingHeardLimit - const Duration(seconds: 1));
    expect(channel.stops, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(channel.stops, 1);
    await channel.finish();
    await tester.pump();
  });

  testWidgets('speaking for too long stops', (tester) async {
    engine.listen(locale: 'es').listen((_) {});
    await tester.pump();
    for (var i = 0; i * 500 < longestListen.inMilliseconds; i++) {
      channel.send(VoiceEvent.partial('palabra $i'));
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(channel.stops, 1);
    await channel.finish();
    await tester.pump();
  });

  group('the precise pass', () {
    const canary = '/models/voice/canary-es';

    /// Listens with the precise model installed, collecting what the stream says.
    ({List<String> heard, Future<void> done}) listenPrecise() {
      precise.path = canary;
      final heard = <String>[];
      final done = engine.listen(locale: 'es').listen(heard.add).asFuture<void>();
      return (heard: heard, done: done);
    }

    final dos = _result([('dos', 0.30, 0.50), ('euros', 0.50, 0.90), ('en', 1.0, 1.1)]);

    test('start gets the precise path and the language when it is installed', () async {
      final l = listenPrecise();
      await pumpEventQueue();
      expect(channel.starts.single.precisePath, canary);
      expect(channel.starts.single.language, 'es');
      await channel.finish();
      await l.done;
    });

    test('no precise model: start gets no precisePath, and the stream behaves as today', () async {
      final heard = <String>[];
      final done = engine.listen(locale: 'es').listen(heard.add).asFuture<void>();
      await pumpEventQueue();
      expect(channel.starts.single.precisePath, isNull);
      await channel.finish(free: dos);
      await done;
      expect(heard.last, 'dos euros en');
    });

    test('the refined text is the last transcript', () async {
      final l = listenPrecise();
      await pumpEventQueue();
      channel.send(const VoiceEvent.partial('dos euros'));
      channel.send(VoiceEvent.result(VoicePass.free, dos));
      channel.send(VoiceEvent.result(VoicePass.grammar, '{"text":""}'));
      channel.send(const VoiceEvent.refining());
      channel.send(const VoiceEvent.refined('Dos euros en café.'));
      channel.send(const VoiceEvent.done());
      await channel.events!.close();
      await l.done;
      expect(l.heard.last, 'Dos euros en café.');
      expect(l.heard, isNot(contains('dos euros en')), reason: 'Vosk text is not shown at the end');
    });

    test('refine_failed keeps Vosk\'s text', () async {
      final l = listenPrecise();
      await pumpEventQueue();
      channel.send(VoiceEvent.result(VoicePass.free, dos));
      channel.send(const VoiceEvent.refining());
      channel.send(const VoiceEvent.refineFailed('failed'));
      channel.send(const VoiceEvent.done());
      await channel.events!.close();
      await l.done;
      expect(l.heard.last, 'dos euros en');
    });

    test('a blank refined text keeps Vosk\'s text', () async {
      final l = listenPrecise();
      await pumpEventQueue();
      channel.send(VoiceEvent.result(VoicePass.free, dos));
      channel.send(const VoiceEvent.refining());
      channel.send(const VoiceEvent.refined('  \n'));
      channel.send(const VoiceEvent.done());
      await channel.events!.close();
      await l.done;
      expect(l.heard.last, 'dos euros en');
    });

    test('done right after refining, with no refined, keeps Vosk\'s text', () async {
      final l = listenPrecise();
      await pumpEventQueue();
      channel.send(VoiceEvent.result(VoicePass.free, dos));
      channel.send(const VoiceEvent.refining());
      channel.send(const VoiceEvent.done());
      await channel.events!.close();
      await l.done;
      expect(l.heard.last, 'dos euros en');
    });

    testWidgets('falls back to Vosk\'s text after 3 s, and ignores what comes later', (
      tester,
    ) async {
      precise.path = canary;
      final heard = <String>[];
      var closed = false;
      engine.listen(locale: 'es').listen(heard.add, onDone: () => closed = true);
      await tester.pump();
      channel.send(VoiceEvent.result(VoicePass.free, dos));
      channel.send(const VoiceEvent.refining());
      await tester.pump(const Duration(milliseconds: 2900));
      expect(closed, isFalse);
      await tester.pump(const Duration(milliseconds: 200));
      // The stream's own end is delivered by the real event loop.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      expect(closed, isTrue);
      expect(heard.last, 'dos euros en');
      final count = heard.length;
      expect(channel.events!.hasListener, isFalse, reason: 'the platform stream is let go');
      // Too late: nothing more reaches the person.
      channel.send(const VoiceEvent.refined('Dos euros en café.'));
      channel.send(const VoiceEvent.done());
      await tester.pump();
      expect(heard.length, count);
    });

    test('refining reports true from the event until the stream closes, then false', () async {
      final states = <bool>[];
      engine.refining.listen(states.add);
      final l = listenPrecise();
      await pumpEventQueue();
      channel.send(VoiceEvent.result(VoicePass.free, dos));
      await pumpEventQueue();
      expect(states, isEmpty);
      channel.send(const VoiceEvent.refining());
      await pumpEventQueue();
      expect(states, [true]);
      channel.send(const VoiceEvent.refined('Dos euros.'));
      channel.send(const VoiceEvent.done());
      await channel.events!.close();
      await l.done;
      await pumpEventQueue();
      expect(states, [true, false]);
    });

    test('a listen that never refines never reports refining', () async {
      final states = <bool>[];
      engine.refining.listen(states.add);
      final done = engine.listen(locale: 'es').listen((_) {}).asFuture<void>();
      await pumpEventQueue();
      await channel.finish(free: dos);
      await done;
      await pumpEventQueue();
      expect(states, isEmpty);
    });

    test('warmUp loads canary too when installed, and isWarm asks for it', () async {
      precise.path = canary;
      await engine.warmUp(locale: 'es');
      expect(channel.warmUps, ['/models/voice/vosk-model-small-es-0.42']);
      expect(channel.preciseWarmUps.single, (precisePath: canary, language: 'es'));
      await engine.isWarm(locale: 'es');
      expect(channel.preciseWarmChecks.single, (precisePath: canary, language: 'es'));
    });

    test('warmUp without canary installed passes no precise path', () async {
      await engine.warmUp(locale: 'es');
      expect(channel.preciseWarmUps.single.precisePath, isNull);
    });
  });

  group('keeping the model loaded', () {
    test('warmUp loads the installed model through the platform, without listening', () async {
      await engine.warmUp(locale: 'es');
      expect(channel.warmUps, ['/models/voice/vosk-model-small-es-0.42']);
      expect(channel.starts, isEmpty, reason: 'nothing records until the person taps');
      expect(channel.stops, 0);
    });

    test('without a downloaded model there is nothing to load, and no error', () async {
      store.path = null;
      await engine.warmUp(locale: 'es');
      expect(channel.warmUps, isEmpty);
      expect(await engine.isWarm(locale: 'es'), isFalse);
    });

    test('a failing platform is no error either: the first listen just loads it', () async {
      channel.warmFails = true;
      await engine.warmUp(locale: 'es');
      expect(await engine.isWarm(locale: 'es'), isFalse);
    });

    test('isWarm is what the platform has loaded, for that locale\'s model', () async {
      expect(await engine.isWarm(locale: 'es'), isFalse);
      await engine.warmUp(locale: 'es');
      expect(await engine.isWarm(locale: 'es'), isTrue);
      // The platform let it go (memory pressure, the models deleted): not warm any more.
      channel.loaded = null;
      expect(await engine.isWarm(locale: 'es'), isFalse);
    });
  });

  group('the microphone level', () {
    test('level events of a listen come out on levels, in order, and not as text', () async {
      final levels = <double>[];
      final texts = <String>[];
      engine.levels.listen(levels.add);
      final done = engine.listen(locale: 'es').listen(texts.add).asFuture<void>();
      await pumpEventQueue();
      channel.send(const VoiceEvent.ready());
      channel.send(const VoiceEvent.level(0.2));
      channel.send(const VoiceEvent.level(0.7));
      await pumpEventQueue();
      expect(levels, [0.2, 0.7]);
      expect(texts, [''], reason: 'only the ready event, no text for a level');
      await channel.finish();
      await done;
    });

    test('a level event reads as a number from the channel\'s map', () {
      final event = VoiceEvent.fromMap({'type': 'level', 'value': 0.5});
      expect(event, isA<VoiceLevel>().having((e) => e.value, 'value', 0.5));
      expect(
        VoiceEvent.fromMap({'type': 'level', 'value': 1}),
        isA<VoiceLevel>().having((e) => e.value, 'value', 1.0),
      );
      expect(
        VoiceEvent.fromMap({'type': 'level'}),
        isA<VoiceLevel>().having((e) => e.value, 'value', 0.0),
      );
    });

    test('levels is silent when nothing listens', () async {
      final levels = <double>[];
      engine.levels.listen(levels.add);
      await pumpEventQueue();
      expect(levels, isEmpty);
    });
  });
}
