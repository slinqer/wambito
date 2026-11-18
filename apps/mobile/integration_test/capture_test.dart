// Quick capture on an Android emulator against the dev stack (`docker compose up -d` at the repo
// root), as docs/mobile/setup.md describes (spec section 6.4: "capture a sentence, with audio
// replaced by a fixed transcript" and "batch save and undo"):
//
//   flutter test integration_test/capture_test.dart -d emulator-5554 \
//     --dart-define=WAMBITO_SERVER=http://10.0.2.2:3000
//
// The speech engine is replaced by one that "hears" a fixed sentence in the app's language; the
// rest is the real app and the real API. Buttons are found by key: the emulator's language decides
// the copy.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/capture/capture_repository.dart';
import 'package:wambito/capture/engine/speech_engine.dart';
import 'package:wambito/capture/parser/parse.dart' show Draft;
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/main.dart' as app;
import 'package:wambito/ui/pressable.dart';
import 'package:wambito/ui/toast.dart';

const _server = String.fromEnvironment('WAMBITO_SERVER', defaultValue: 'http://10.0.2.2:3000');

final _http = Dio(BaseOptions(validateStatus: (_) => true));

/// Two movements of 15 000 and 3 000, said in the app's language (any currency reads them).
const _heard = {
  'es': 'gasté 15000 en almuerzo y 3000 en uber',
  'en': 'spent 15000 on lunch and 3000 on uber',
};

class _FixedTranscript implements SpeechEngine {
  @override
  Future<bool> available() async => true;

  @override
  Stream<String> listen({required String locale}) async* {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    yield _heard[locale]!;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<bool> isWarm({required String locale}) async => false;

  @override
  Future<void> warmUp({required String locale}) async {}

  @override
  Stream<double> get levels => const Stream.empty();

  @override
  Stream<bool> get refining => const Stream.empty();
}

/// The real batch route, whose first answer is lost on the way back: the server saved the rows,
/// the app never heard so (a dropped connection).
class _LoseFirstAnswer implements CaptureRepository {
  _LoseFirstAnswer(this._real);

  final CaptureRepository _real;
  final keys = <String>[];
  var _lost = false;

  @override
  Future<List<Transaction>> saveBatch(List<Draft> drafts, {required String idempotencyKey}) =>
      createBatch(captureInputs(drafts), idempotencyKey: idempotencyKey);

  @override
  Future<List<Transaction>> createBatch(
    List<CreateTransaction> items, {
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    final saved = await _real.createBatch(items, idempotencyKey: idempotencyKey);
    if (!_lost) {
      _lost = true;
      throw const HomeFailure(0);
    }
    return saved;
  }

  @override
  Future<void> undoBatch(List<String> ids) => _real.undoBatch(ids);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder to go');
}

/// Brings the widget well into view (a third of the way down), as a person scrolling to it would.
/// `ensureVisible` leaves it at the edge, where the bottom bar or the top of a short phone can still
/// cover the middle of it and the tap derives an offset that is off screen.
/// The page can still move after the first scroll (what loads above it), so it looks again that the
/// middle of the widget is on screen before the tap.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  for (var attempt = 0; attempt < 5; attempt++) {
    final element = tester.element(finder.first);
    if (Scrollable.maybeOf(element) != null) {
      await Scrollable.ensureVisible(element, alignment: 0.3);
      await tester.pump(const Duration(milliseconds: 300));
    }
    final center = tester.getCenter(finder.first);
    if (center.dy > 0 && center.dy < size.height) return;
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await _pumpUntil(tester, finder);
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

Options _auth(String token) => Options(headers: {'Authorization': 'Bearer $token'});

/// A guest on home with a category of its own, then the capture preview of the fixed sentence with
/// that category picked for both cards. Returns the token and the category id.
Future<(String, String)> _captureTwo(WidgetTester tester) async {
  await _tap(tester, 'entry.start');
  await _pumpUntil(tester, find.byType(HomeScreen));
  await _pumpUntil(tester, find.byKey(const Key('home.capture')));

  final token = (await SessionStore().read())!.token;
  final name = 'Captura ${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
  final made = await _http.post<Map<String, dynamic>>(
    '$_server/api/v1/categories',
    data: {'name': name, 'kind': 'expense', 'icon': '🎤', 'color': '#2fd388'},
    options: _auth(token),
  );
  expect(made.statusCode, 201, reason: '${made.data}');
  final categoryId = made.data!['id'] as String;
  // Home learns of it when the app comes back to the front.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump(const Duration(seconds: 2));

  await _tap(tester, 'home.capture');
  await _pumpUntil(tester, find.byKey(const Key('capture.card.1')));
  expect(find.byKey(const Key('capture.card.2')), findsNothing);
  for (final card in [0, 1]) {
    await _tap(tester, 'capture.card.$card.pick');
    await _tap(tester, 'capture.card.$card.category.$categoryId');
  }
  return (token, categoryId);
}

Future<List<Map<String, dynamic>>> _rows(String token, String categoryId) async {
  final res = await _http.get<Map<String, dynamic>>(
    '$_server/api/v1/transactions',
    options: _auth(token),
  );
  expect(res.statusCode, 200);
  return (res.data!['items'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .where((t) => t['categoryId'] == categoryId)
      .toList();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture a sentence (fixed transcript), save both at once, then Deshacer', (
    tester,
  ) async {
    await SessionStore().clear();
    await tester.pumpWidget(
      await app.bootstrap(overrides: [speechEngineProvider.overrideWithValue(_FixedTranscript())]),
    );
    final (token, categoryId) = await _captureTwo(tester);

    await _tap(tester, 'capture.save');
    await _pumpUntilGone(tester, find.byKey(const Key('capture.sheet')));

    // One toast, one Deshacer: it takes both away. (It stays 8 seconds on a timer of its own, so
    // it is looked for before the server is asked.)
    // (The phone's language names its action; it is the toast's one button.)
    final undo = find.descendant(of: find.byType(ToastLayer), matching: find.byType(Pressable));
    await _pumpUntil(tester, undo);
    expect(find.byType(ToastLayer), findsOneWidget);

    var rows = await _rows(token, categoryId);
    expect(rows.map((r) => r['amount']).toList()..sort(), [-1500000, -300000]);
    expect(rows.every((r) => r['source'] == 'app'), isTrue);

    await tester.tap(undo);
    await tester.pump(const Duration(seconds: 2));
    final end = DateTime.now().add(const Duration(seconds: 20));
    while ((rows = await _rows(token, categoryId)).isNotEmpty && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(rows, isEmpty);
  });

  testWidgets('the batch save retried after a lost response leaves exactly 2 rows', (tester) async {
    await SessionStore().clear();
    _LoseFirstAnswer? losing;
    await tester.pumpWidget(
      await app.bootstrap(
        overrides: [
          speechEngineProvider.overrideWithValue(_FixedTranscript()),
          captureRepositoryProvider.overrideWith(
            (ref) => losing = _LoseFirstAnswer(
              ApiCaptureRepository(ref.watch(apiClientProvider).api.getDefaultApi()),
            ),
          ),
        ],
      ),
    );
    final (token, categoryId) = await _captureTwo(tester);

    await _tap(tester, 'capture.save');
    // The server has the rows, the app heard nothing: the batch waits on the phone, the sheet
    // closes, and the queue sends it again a few seconds later.
    await _pumpUntilGone(tester, find.byKey(const Key('capture.sheet')));
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (losing!.keys.length < 2 && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(losing!.keys, hasLength(2));
    expect(losing!.keys[0], losing!.keys[1], reason: 'the retry sends the same Idempotency-Key');
    final rows = await _rows(token, categoryId);
    expect(rows, hasLength(2), reason: 'the retry replays the first answer, it saves nothing new');
  });
}
