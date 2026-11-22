// Recurring payments on an Android emulator against the dev stack (`docker compose up -d` at the
// repo root), as docs/mobile/setup.md describes:
//
//   flutter test integration_test/recurring_test.dart -d emulator-5554 \
//     --dart-define=WAMBITO_SERVER=http://10.0.2.2:3000
//
// It needs the notification permission given (`adb shell pm grant com.wambito.app
// android.permission.POST_NOTIFICATIONS`), because "Hoy vence…" is scheduled only for a phone that
// can post it, and the job runs for real through WorkManager. The emulator's language decides the
// copy, so buttons and fields are found by key.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/capture/parser/dates.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/main.dart' as app;
import 'package:wambito/notices/notice_platform.dart';

const _server = String.fromEnvironment('WAMBITO_SERVER', defaultValue: 'http://10.0.2.2:3000');
const _test = MethodChannel('wambito/test');
const _platform = ChannelNoticePlatform();

final _http = Dio(BaseOptions(validateStatus: (_) => true));

Options _auth(String token) => Options(headers: {'Authorization': 'Bearer $token'});

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
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
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder to go');
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  // On a short phone a control can sit under the bottom bar or the sheet's footer: scroll it well
  // into view first.
  final element = tester.element(finder.first);
  if (Scrollable.maybeOf(element) != null) {
    await Scrollable.ensureVisible(element, alignment: 0.3);
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _pumpUntil(tester, find.byKey(Key(key)));
  await _reveal(tester, find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _settle(WidgetTester tester, [int ticks = 20]) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A new guest, on the entry screen's button.
Future<void> _startAsGuest(WidgetTester tester) async {
  await SessionStore().clear();
  await tester.pumpWidget(await app.bootstrap());
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
}

Future<List<Map<String, dynamic>>> _rules(String token) async {
  final res = await _http.get<List<dynamic>>('$_server/api/v1/recurrences', options: _auth(token));
  expect(res.statusCode, 200, reason: '${res.data}');
  return res.data!.cast<Map<String, dynamic>>();
}

/// What "Hoy vence…" reads (`GET /v1/transactions?status=pending&month=`): the pending rows of a
/// recurring payment dated [today].
Future<List<String>> _dueToday(String token, String today) async {
  final res = await _http.get<Map<String, dynamic>>(
    '$_server/api/v1/transactions?status=pending&month=${today.substring(0, 7)}&limit=200',
    options: _auth(token),
  );
  expect(res.statusCode, 200, reason: '${res.data}');
  return [
    for (final item in (res.data!['items'] as List).cast<Map<String, dynamic>>())
      if (item['date'] == today && item['recurrenceId'] != null) item['name'] as String,
  ];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'create a recurring payment due today, rename it, then end it: nothing is posted for it',
    (tester) async {
      if (await _platform.permission() != NoticePermission.granted) {
        fail('Needs the notification permission: adb shell pm grant … POST_NOTIFICATIONS');
      }
      await _startAsGuest(tester);
      await _pumpUntil(tester, find.byKey(const Key('home.add')));
      final token = (await SessionStore().read())!.token;

      // "Hoy vence…" never goes out before 9:00 in the profile's zone: a zone where it is about noon.
      final offset = () {
        final hours = 12 - DateTime.now().toUtc().hour;
        return hours > 12 ? hours - 24 : (hours < -12 ? hours + 24 : hours);
      }();
      final zone = offset == 0
          ? 'Etc/GMT'
          : (offset > 0 ? 'Etc/GMT-$offset' : 'Etc/GMT+${-offset}');
      final patched = await _http.patch<Map<String, dynamic>>(
        '$_server/api/v1/me',
        data: {'timezone': zone},
        options: _auth(token),
      );
      expect(patched.statusCode, 200, reason: '${patched.data}');
      final today = todayIn(zone, DateTime.now().toUtc());
      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final name = 'Internet $suffix';
      final renamed = '$name fibra';

      // A fresh guest has no category: one of its own, made through the API (the app learns of it,
      // and of the zone, when it comes back to the front).
      final category = await _http.post<Map<String, dynamic>>(
        '$_server/api/v1/categories',
        data: {'name': 'Casa $suffix', 'kind': 'expense', 'icon': '🏠', 'color': '#3fa7ff'},
        options: _auth(token),
      );
      expect(category.statusCode, 201, reason: '${category.data}');
      final categoryId = category.data!['id'] as String;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester, 20);

      // The page, as the face menu opens it.
      GoRouter.of(tester.element(find.byType(HomeScreen))).go('/recurring');
      await _pumpUntil(tester, find.byKey(const Key('recurring.page')));
      await _pumpUntil(tester, find.byKey(const Key('recurring.add')));
      await _settle(tester, 10);

      // "Nuevo recurrente": 15 on the keypad, a name and a category; it starts today, on today's day.
      await _tap(tester, 'recurring.add');
      await _pumpUntil(tester, find.byKey(const Key('recurring.save')));
      await _tap(tester, 'keypad.1');
      await _tap(tester, 'keypad.5');
      await tester.enterText(find.byKey(const Key('recurring.name')), name);
      await tester.pump();
      await _tap(tester, 'recurring.category.$categoryId');
      await _tap(tester, 'recurring.save');
      await _pumpUntilGone(tester, find.byKey(const Key('recurring.save')));

      final made = (await _rules(token)).where((r) => r['name'] == name).single;
      expect(made['amount'], -1500);
      expect(made['categoryId'], categoryId);
      expect(made['frequency'], 'monthly');
      expect(made['dayOfMonth'], int.parse(today.substring(8)));
      expect(made['startDate'], today);
      expect(made['endDate'], isNull);
      await _pumpUntil(tester, find.text(name));
      expect(await _dueToday(token, today), [
        name,
      ], reason: 'it is due today: a pending row, today');

      // Rename it: the edit sheet opens with its name, and the PATCH keeps what it did not touch.
      await tester.tap(find.text(name).first);
      await _pumpUntil(tester, find.byKey(const Key('recurring.save')));
      await tester.enterText(find.byKey(const Key('recurring.name')), renamed);
      await tester.pump();
      await _tap(tester, 'recurring.save');
      await _pumpUntilGone(tester, find.byKey(const Key('recurring.save')));
      final saved = (await _rules(token)).where((r) => r['id'] == made['id']).single;
      expect(saved['name'], renamed);
      expect(saved['amount'], -1500);
      expect(saved['endDate'], isNull);
      expect(saved['monthOfYear'], isNull);
      await _pumpUntil(tester, find.text(renamed));
      expect(await _dueToday(token, today), [renamed], reason: 'the pending row follows the edit');

      // The app has seen a recurring payment and notices allowed: "Hoy vence…" is scheduled.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester, 20);
      expect(await _test.invokeMethod<bool>('dueScheduled'), isTrue, reason: '9:00 is scheduled');

      // End it: Eliminar recurrente, and the question.
      await tester.tap(find.text(renamed).first);
      await _pumpUntil(tester, find.byKey(const Key('recurring.delete')));
      await _tap(tester, 'recurring.delete');
      await _tap(tester, 'recurring.delete.confirm');
      await _pumpUntilGone(tester, find.text(renamed));
      await _settle(tester, 20);

      // The server no longer has it, nor its pending row for today (what the 9:00 job reads)...
      expect((await _rules(token)).where((r) => r['id'] == made['id']), isEmpty);
      expect(await _dueToday(token, today), isEmpty);
      // ...the app looked again, saw no recurring payment left and cancelled "Hoy vence…"...
      expect(await _test.invokeMethod<bool>('dueScheduled'), isFalse, reason: 'cancelled');
      // ...and the job, run for real as 9:00 would, posts nothing.
      expect(await _test.invokeMethod<String>('runDueNotice'), isNot('posted'));
      expect(await _test.invokeMethod<List<Object?>>('activeNotices'), isEmpty);

      await SessionStore().clear();
      await tester.pump(const Duration(seconds: 6));
    },
  );
}
