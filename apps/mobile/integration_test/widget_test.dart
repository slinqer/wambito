// The home-screen widget's deep links and refresh job on an Android emulator against the dev stack
// (`docker compose up -d` at the repo root), as docs/mobile/setup.md describes (spec section 6.4:
// "the widget's deep links"; 7.1):
//
//   flutter test integration_test/widget_test.dart -d emulator-5554 \
//     --dart-define=WAMBITO_SERVER=http://10.0.2.2:3000
//
// One test uses the real speech engine (🎤 twice, the first listen having ended by itself), and is
// skipped unless the voice models are served as docs/mobile/setup.md describes (it also needs the
// microphone granted: `adb shell pm grant com.wambito.app android.permission.RECORD_AUDIO`):
//
//     --dart-define=VOICE_MODELS_URL=http://10.0.2.2:8765
//
// The buttons are pressed as the widget presses them: the debug-only `wambito/test` channel starts
// the very intent the widget's ＋ and 🎤 start (launch/LaunchLinks.kt). The refresh job runs for
// real through WorkManager, reading the session where the app keeps it.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:home_widget/home_widget.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wambito/add/add_sheet.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/capture/capture_sheet.dart';
import 'package:wambito/capture/engine/speech_engine.dart';
import 'package:wambito/capture/engine/voice_channel.dart';
import 'package:wambito/capture/engine/vosk_engine.dart';
import 'package:wambito/capture/models_download.dart';
import 'package:wambito/entry/entry_screen.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/main.dart' as app;
import 'package:wambito/router.dart';

const _server = String.fromEnvironment('WAMBITO_SERVER', defaultValue: 'http://10.0.2.2:3000');
const _test = MethodChannel('wambito/test');
const _modelsUrl = String.fromEnvironment('VOICE_MODELS_URL');

final _http = Dio(BaseOptions(validateStatus: (_) => true));

Options _auth(String token) => Options(headers: {'Authorization': 'Bearer $token'});

/// Listens until stopped: the emulator has no microphone, and the test only needs "listening".
class _Listening implements SpeechEngine {
  StreamController<String>? _heard;

  @override
  Future<bool> available() async => true;

  @override
  Stream<String> listen({required String locale}) {
    final heard = _heard = StreamController<String>();
    heard.add(''); // ready
    return heard.stream;
  }

  @override
  Future<void> stop() async => _heard?.close();

  @override
  Future<bool> isWarm({required String locale}) async => false;

  @override
  Future<void> warmUp({required String locale}) async {}

  @override
  Stream<double> get levels => const Stream.empty();

  @override
  Stream<bool> get refining => const Stream.empty();
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

Future<Map<String, Object?>?> _snapshot() async {
  final json = await HomeWidget.getWidgetData<String>(widgetSnapshotKey);
  return json == null ? null : jsonDecode(json) as Map<String, Object?>;
}

/// Waits for the snapshot to satisfy [test] (the app writes it without being awaited).
Future<Map<String, Object?>> _snapshotWhere(
  WidgetTester tester,
  bool Function(Map<String, Object?> doc) test,
) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    final doc = await _snapshot();
    if (doc != null && test(doc)) return doc;
  }
  throw TestFailure('The widget snapshot never matched: ${await _snapshot()}');
}

/// A new guest on home.
Future<void> _startAsGuest(WidgetTester tester, {List<Override> overrides = const []}) async {
  await SessionStore().clear();
  await tester.pumpWidget(await app.bootstrap(overrides: overrides));
  await _pumpUntil(tester, find.byKey(const Key('entry.start')));
  // The API limits new guests from one address to a few in a row: wait and try again.
  for (var attempt = 0; find.byType(HomeScreen).evaluate().isEmpty; attempt++) {
    if (attempt == 8) throw TestFailure('Could not start a guest');
    await tester.tap(find.byKey(const Key('entry.start')));
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(end) && find.byType(HomeScreen).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  await _pumpUntil(tester, find.byKey(const Key('home.add')));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('＋ opens the add sheet', (tester) async {
    await _startAsGuest(tester);
    final clock = Stopwatch()..start();
    await _test.invokeMethod<void>('openWidgetButton', 'add');
    await _pumpUntil(tester, find.byType(AddSheet));
    await _pumpUntil(tester, find.byKey(const Key('keypad.5')));
    debugPrint('widget ＋ to keypad (warm, emulator): ${clock.elapsedMilliseconds} ms');
  });

  testWidgets('🎤 opens capture listening', (tester) async {
    await _startAsGuest(tester, overrides: [speechEngineProvider.overrideWithValue(_Listening())]);
    final clock = Stopwatch()..start();
    await _test.invokeMethod<void>('openWidgetButton', 'capture');
    await _pumpUntil(tester, find.byType(CaptureSheet));
    // The listening stage: its "stop" button shows only while the engine listens.
    await _pumpUntil(tester, find.byKey(const Key('capture.stop')));
    debugPrint('widget 🎤 to listening (warm, emulator): ${clock.elapsedMilliseconds} ms');
    expect(tester.widget<CaptureSheet>(find.byType(CaptureSheet)).listen, isTrue);
  });

  testWidgets(
    '🎤 tapped again after a listen that ended by itself listens again, with the real engine',
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
      await _startAsGuest(
        tester,
        overrides: [
          modelStoreProvider.overrideWithValue(store),
          speechEngineProvider.overrideWithValue(
            VoskEngine(
              channel: channel,
              models: store,
              precise: ModelStore(files: channel, http: Dio(), models: preciseModels),
            ),
          ),
        ],
      );
      final listening = find.byKey(const Key('capture.stop'));
      final typing = find.byKey(const Key('capture.field'));

      // The first tap listens; the sentence ends (here, by "stop": the emulator hears silence),
      // Android sends `done` and the engine lets go of the stream.
      await _test.invokeMethod<void>('openWidgetButton', 'capture');
      await _pumpUntil(tester, listening);
      await tester.tap(listening);
      await _pumpUntil(tester, typing);

      // The next tap, in the same process, must listen too and go on listening: with the old
      // stream's end still waiting in the channel buffers, the new listen ended at once, unheard.
      await _test.invokeMethod<void>('openWidgetButton', 'capture');
      await _pumpUntil(tester, listening);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(listening, findsOneWidget, reason: 'still listening three seconds on');
      expect(typing, findsNothing);
      expect(find.byType(CaptureSheet), findsOneWidget);
      await tester.tap(listening);
      await tester.pumpAndSettle();
    },
    skip: _modelsUrl.isEmpty,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets('a tap on the widget itself opens home, over a screen or a sheet, with no error', (
    tester,
  ) async {
    await _startAsGuest(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    // From Settings.
    container.read(routerProvider).go('/settings');
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsNothing);
    await _test.invokeMethod<void>('openWidgetButton', 'home');
    await _pumpUntil(tester, find.byKey(const Key('home.add')));
    expect(find.text('Page Not Found'), findsNothing);

    // With the add sheet open and empty: it gives way.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100)); // home has finished arriving
    }
    await tester.tap(find.byKey(const Key('home.add')));
    await _pumpUntil(tester, find.byType(AddSheet));
    await _test.invokeMethod<void>('openWidgetButton', 'home');
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(AddSheet), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets(
    'the intent Glance gave the widget body (glance-action data, no action) shows no "Page Not Found"',
    (tester) async {
      await _startAsGuest(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      container.read(routerProvider).go('/settings');
      await tester.pumpAndSettle();
      await _test.invokeMethod<void>('openGlanceTap');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Page Not Found'), findsNothing);
      expect(tester.takeException(), isNull);
      // The router stayed where it was: the intent's data never reached it. Home is a tap away.
      expect(container.read(routerProvider).state.uri.path, '/settings');
    },
  );

  testWidgets('wambito://capture sent to the exported launcher activity opens nothing', (
    tester,
  ) async {
    await _startAsGuest(tester, overrides: [speechEngineProvider.overrideWithValue(_Listening())]);
    // What another app can do: start the launcher activity explicitly with the link.
    await _test.invokeMethod<void>('openOnLauncherActivity', 'wambito://capture');
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(CaptureSheet), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets(
    'a token the job cannot decrypt: nothing is sent and secure storage stays exactly as it was',
    (tester) async {
      await _startAsGuest(tester);
      final before = await _snapshotWhere(tester, (doc) => doc['signedIn'] == true);
      // The stored ciphertext with one byte changed: its GCM tag no longer checks out, as with a
      // Keystore that lost its key. The app's own plugin would reset; the job must not.
      await _test.invokeMethod<void>('corruptStoredToken');
      final stored = await _test.invokeMethod<Map<Object?, Object?>>('secureStorageFiles');

      expect(await _test.invokeMethod<String>('refreshWidget'), 'token unreadable');
      expect(await _test.invokeMethod<Map<Object?, Object?>>('secureStorageFiles'), stored);
      expect(await _snapshot(), before);
      await SessionStore().clear();
    },
  );

  testWidgets('RefreshWorker updates the snapshot from GET /v1/summary with the stored session, '
      'and after sign out the widget never shows the previous figure', (tester) async {
    await _startAsGuest(tester);
    final token = (await SessionStore().read())!.token;
    // Home's load writes the snapshot, in the app's currency and language.
    final first = await _snapshotWhere(tester, (doc) => doc['signedIn'] == true);
    expect(first['v'], 3);
    // The profile's zone, which the widget reads "this month" and its midnight in.
    expect(first['timezone'], isA<String>());

    // A movement made elsewhere (the web, say): the app does not know of it.
    final summary = await _http.get<Map<String, dynamic>>(
      '$_server/api/v1/summary',
      options: _auth(token),
    );
    final month = summary.data!['month'] as String;
    final category = await _http.post<Map<String, dynamic>>(
      '$_server/api/v1/categories',
      data: {
        'name': 'Widget ${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
        'kind': 'expense',
        'icon': '🛒',
        'color': '#2fd388',
      },
      options: _auth(token),
    );
    expect(category.statusCode, 201, reason: '${category.data}');
    final made = await _http.post<Map<String, dynamic>>(
      '$_server/api/v1/transactions',
      data: {
        'name': 'Widget refresh',
        'amount': -1234500,
        'categoryId': category.data!['id'],
        'date': '$month-01',
      },
      options: _auth(token),
    );
    expect(made.statusCode, 201, reason: '${made.data}');
    final after = await _http.get<Map<String, dynamic>>(
      '$_server/api/v1/summary',
      options: _auth(token),
    );

    final outcome = await _test.invokeMethod<String>('refreshWidget');
    expect(outcome, 'refreshed');
    final refreshed = (await _snapshot())!;
    expect(refreshed['signedIn'], true);
    expect(refreshed['spent'], after.data!['spent']);
    expect(refreshed['remaining'], after.data!['remaining']);
    expect(refreshed['currency'], first['currency']);
    expect(refreshed['hideAmount'], first['hideAmount']);
    expect(refreshed['timezone'], first['timezone']);

    // Signing out: at once the widget holds no figure, and the job brings none back.
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    await container.read(sessionProvider.notifier).signOut(discardGuest: true);
    await _pumpUntil(tester, find.byType(EntryScreen));
    final signedOut = await _snapshotWhere(tester, (doc) => doc['signedIn'] == false);
    expect(signedOut.containsKey('spent'), isFalse);
    expect(signedOut.containsKey('remaining'), isFalse);

    expect(await _test.invokeMethod<String>('refreshWidget'), 'signed out');
    final still = (await _snapshot())!;
    expect(still['signedIn'], false);
    expect(still.containsKey('spent'), isFalse);
  });
}
