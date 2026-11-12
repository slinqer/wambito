// The Dart side of the `wambito/voice/events` event channel (lib/capture/engine/voice_channel.dart):
// what reaches a listen from the platform, and what must never reach the next one.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/capture/engine/voice_channel.dart';

const _events = 'wambito/voice/events';
const _codec = StandardMethodCodec();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('precise-only (iOS)', iosChannelTests);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;

  setUp(() {
    calls = [];
    // Android's side of the channel: it only counts `listen` and `cancel`.
    messenger.setMockMethodCallHandler(const MethodChannel(_events), (call) async {
      calls.add(call.method);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(const MethodChannel(_events), null));

  /// What Android sends over the channel: an event, or (null) the end of the stream. It goes
  /// through the engine's channel buffers, as real platform messages do: with no listener on the
  /// channel they wait there for the next one.
  Future<void> send(Map<String, Object?>? event) async {
    TestDefaultBinaryMessengerBinding.instance.channelBuffers.push(
      _events,
      event == null ? null : _codec.encodeSuccessEnvelope(event),
      (_) {},
    );
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('events of a listen arrive, and its end closes the stream', () async {
    final seen = <VoiceEvent>[];
    var closed = false;
    VoiceChannel()
        .start(modelPath: 'm', grammar: 'g')
        .listen(seen.add, onDone: () => closed = true);
    await settle();
    await send({'type': 'ready'});
    await send({'type': 'done'});
    await settle();
    expect(seen.map((e) => e.runtimeType), [VoiceReady, VoiceDone]);
    expect(closed, isFalse);
    await send(null);
    await settle();
    expect(closed, isTrue);
  });

  test(
    'the end of a session that finished by itself is not read as the end of the next one',
    () async {
      // The first session: Android sends `done`, the engine lets go of the stream at once (it has
      // what it needs), and Android's `endOfStream` arrives a moment later, with nobody listening.
      final first = VoiceChannel().start(modelPath: 'm', grammar: 'g').listen((_) {});
      await settle();
      await send({'type': 'done'});
      await first.cancel();
      await send(null);
      await settle();

      // The next session (the widget's 🎤 a minute later, in the same process) must hear its own.
      final seen = <VoiceEvent>[];
      var closed = false;
      VoiceChannel()
          .start(modelPath: 'm', grammar: 'g')
          .listen(seen.add, onDone: () => closed = true);
      await settle();
      expect(closed, isFalse, reason: 'the old end of stream was thrown away');
      await send({'type': 'ready'});
      await settle();
      expect(seen.map((e) => e.runtimeType), [VoiceReady]);
      expect(calls, ['listen', 'cancel', 'listen']);
    },
  );

  test('fromMap reads refining, refined and refine_failed', () {
    expect(VoiceEvent.fromMap({'type': 'refining'}), isA<VoiceRefining>());
    expect(
      VoiceEvent.fromMap({'type': 'refined', 'text': 'Dos euros.'}),
      isA<VoiceRefined>().having((e) => e.text, 'text', 'Dos euros.'),
    );
    expect(
      VoiceEvent.fromMap({'type': 'refine_failed', 'code': 'timeout'}),
      isA<VoiceRefineFailed>().having((e) => e.code, 'code', 'timeout'),
    );
  });
}

void iosChannelTests() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methods = MethodChannel('wambito/voice');
  const events = MethodChannel('wambito/voice/events');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return true;
    });
    messenger.setMockMethodCallHandler(events, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  test('startPrecise sends only the precise path and the language', () async {
    final sub = const VoiceChannel()
        .startPrecise(precisePath: '/m/c', language: 'es')
        .listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final listen = calls.singleWhere((c) => c.method == 'listen');
    expect(listen.arguments, {'precisePath': '/m/c', 'language': 'es'});
    await sub.cancel();
  });

  test('warmUpPrecise sends warmUp with the precise path and the language only', () async {
    expect(await const VoiceChannel().warmUpPrecise(precisePath: '/m/c', language: 'es'), isTrue);
    expect(calls.single.method, 'warmUp');
    expect(calls.single.arguments, {'precisePath': '/m/c', 'language': 'es'});
  });

  test('isWarmPrecise sends isWarm with the precise path and the language only', () async {
    expect(await const VoiceChannel().isWarmPrecise(precisePath: '/m/c', language: 'es'), isTrue);
    expect(calls.single.method, 'isWarm');
    expect(calls.single.arguments, {'precisePath': '/m/c', 'language': 'es'});
  });
}
