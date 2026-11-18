// Tap to listening with the real engine on an Android emulator (docs/mobile/setup.md): how long
// from the tap on home's 🎤 to the sheet showing that the microphone listens, the first time in a
// process (the model is not loaded yet, "cold") and the times after ("warm"). The emulator has no
// real microphone, so this times the plumbing, not recognition. Like voice_engine_test.dart it
// needs the voice models served by a stand-in for the release, and is skipped without them:
//
//   python3 -m http.server 8765 --directory <folder with the two model zips>
//   adb -s emulator-5554 install -r -t -g build/app/outputs/flutter-apk/app-debug.apk
//   flutter test integration_test/voice_latency_test.dart -d emulator-5554 \
//     --dart-define=WAMBITO_SERVER=http://10.0.2.2:3000 \
//     --dart-define=VOICE_MODELS_URL=http://10.0.2.2:8765 \
//     --dart-define=VOICE_USED=true        # the person has captured by voice before
//
// VOICE_USED=true keeps the first-use note's flag off before the app starts, as it is for anyone
// who has captured before: the app then loads the model in the background at its start, and the
// first tap after a few idle seconds is warm. Without it the first tap is cold.
// It prints `LATENCY <label> <ms>` lines.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/capture/capture_sheet.dart';
import 'package:wambito/capture/engine/speech_engine.dart';
import 'package:wambito/capture/engine/voice_channel.dart';
import 'package:wambito/capture/engine/vosk_engine.dart';
import 'package:wambito/capture/models_download.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/main.dart' as app;

const _modelsUrl = String.fromEnvironment('VOICE_MODELS_URL');
const _voiceUsed = bool.fromEnvironment('VOICE_USED');
const _runs = int.fromEnvironment('RUNS', defaultValue: 5);

/// The real engine, noting when the microphone really records: the first event of each listen
/// (Kotlin sends it right after AudioRecord starts).
class _Timed implements SpeechEngine {
  _Timed(this._real);

  final SpeechEngine _real;
  final firstEvents = <int>[];
  final clock = Stopwatch()..start();
  var tapAt = 0;

  @override
  Future<bool> available() => _real.available();

  @override
  Future<bool> isWarm({required String locale}) => _real.isWarm(locale: locale);

  @override
  Future<void> warmUp({required String locale}) => _real.warmUp(locale: locale);

  @override
  Stream<double> get levels => _real.levels;

  @override
  Stream<bool> get refining => _real.refining;

  @override
  Future<void> stop() => _real.stop();

  @override
  Stream<String> listen({required String locale}) {
    var first = true;
    return _real.listen(locale: locale).map((text) {
      if (first) {
        first = false;
        firstEvents.add(clock.elapsedMilliseconds - tapAt);
      }
      return text;
    });
  }
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder, {Duration? step}) async {
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step ?? const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

Future<void> _startAsGuest(WidgetTester tester, ModelStore store, SpeechEngine engine) async {
  await SessionStore().clear();
  await tester.pumpWidget(
    await app.bootstrap(
      overrides: [
        modelStoreProvider.overrideWithValue(store),
        speechEngineProvider.overrideWithValue(engine),
      ],
    ),
  );
  await _pumpUntil(tester, find.byKey(const Key('entry.start')));
  for (var attempt = 0; find.byType(HomeScreen).evaluate().isEmpty; attempt++) {
    if (attempt == 8) throw TestFailure('Could not start a guest');
    await tester.tap(find.byKey(const Key('entry.start')));
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(end) && find.byType(HomeScreen).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  await _pumpUntil(tester, find.byKey(const Key('home.capture')));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'tap on home\'s 🎤 to the sheet listening, cold then warm',
    (tester) async {
      const channel = VoiceChannel();
      final store = ModelStore(files: channel, http: Dio(), releaseUrl: Uri.parse(_modelsUrl));
      for (final locale in ['en', 'es']) {
        if (await store.installedPath(locale) == null) await store.download(locale);
      }
      // Italian and Portuguese are beta voices that may not be released yet: they are kept when a
      // phone has them (the engine then also serves an it or pt sheet) and never downloaded here,
      // so a phone without them skips them instead of failing.
      for (final locale in ['it', 'pt']) {
        if (await store.installedPath(locale) == null) {
          debugPrint('no $locale voice installed: skipped');
        }
      }
      // The note's flag (lib/capture/capture_sheet.dart): off once the person has captured.
      await const FlutterSecureStorage().write(
        key: 'setting.capture.note',
        value: _voiceUsed ? 'off' : 'on',
      );
      final engine = _Timed(
        VoskEngine(
          channel: channel,
          models: store,
          precise: ModelStore(files: channel, http: Dio(), models: preciseModels),
        ),
      );
      await _startAsGuest(tester, store, engine);
      // The person looks at home for a moment: a background load has time to finish.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final listening = find.descendant(
        of: find.byType(CaptureSheet),
        matching: find.byIcon(Icons.mic),
      );
      final stopButton = find.byKey(const Key('capture.stop'));
      for (var run = 0; run < _runs; run++) {
        final clock = Stopwatch()..start();
        engine.tapAt = engine.clock.elapsedMilliseconds;
        await tester.tap(find.byKey(const Key('home.capture')));
        await _pumpUntil(tester, stopButton, step: const Duration(milliseconds: 8));
        final sheet = clock.elapsedMilliseconds;
        await _pumpUntil(tester, listening, step: const Duration(milliseconds: 8));
        final ready = clock.elapsedMilliseconds;
        // The first event can come a frame after the UI shows, when listening started warm.
        await tester.pump(const Duration(milliseconds: 100));
        debugPrint(
          'LATENCY ${run == 0 ? 'first' : 'next'} run=$run sheet=${sheet}ms '
          'listeningShown=${ready}ms micRecording=${engine.firstEvents.last}ms',
        );
        // Let it listen a moment, then close the sheet (the microphone is released).
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        Navigator.of(tester.element(find.byType(CaptureSheet))).pop();
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
    },
    skip: _modelsUrl.isEmpty,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
