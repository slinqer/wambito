// Add an expense on an Android emulator against the dev stack (`docker compose up -d` at the repo
// root), as docs/mobile/setup.md describes:
//
//   flutter test integration_test/add_test.dart -d emulator-5554 \
//     --dart-define=WAMBITO_SERVER=http://10.0.2.2:3000
//
// Buttons are found by key: the emulator's language decides the copy (the widget tests check the
// Spanish and English words). Amounts are typed with the digit keys only, so the guest's currency
// (decided by the phone's region) does not matter: every amount is stored as cents.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/main.dart' as app;

const _server = String.fromEnvironment('WAMBITO_SERVER', defaultValue: 'http://10.0.2.2:3000');

final _http = Dio(BaseOptions(validateStatus: (_) => true));

/// Pumps until [finder] finds something (network calls run in real time here).
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

/// Pumps until [finder] finds nothing.
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

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  // On a short phone a row or button can sit under the bottom bar: scroll it well into view first.
  final element = tester.element(finder.first);
  if (Scrollable.maybeOf(element) != null) {
    await Scrollable.ensureVisible(element, alignment: 0.3);
    await tester.pumpAndSettle();
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _pumpUntil(tester, find.byKey(Key(key)));
  await _reveal(tester, find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await _tap(tester, 'keypad.$digit');
  }
}

Options _auth(String token) => Options(headers: {'Authorization': 'Bearer $token'});

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('add an expense with the keypad, then edit its amount', (tester) async {
    await SessionStore().clear();
    await tester.pumpWidget(await app.bootstrap());
    await _tap(tester, 'entry.start');
    await _pumpUntil(tester, find.byType(HomeScreen));
    await _pumpUntil(tester, find.byKey(const Key('home.add')));

    // A category of its own, made through the API; the app learns of it when it comes back to the
    // front, as it does after a night in the background.
    final token = (await SessionStore().read())!.token;
    final name = 'Mercado ${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final made = await _http.post<Map<String, dynamic>>(
      '$_server/api/v1/categories',
      data: {'name': name, 'kind': 'expense', 'icon': '🛒', 'color': '#2fd388'},
      options: _auth(token),
    );
    expect(made.statusCode, 201, reason: '${made.data}');
    final categoryId = made.data!['id'] as String;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));

    // ＋, the amount on the keypad, the category, Guardar.
    await _tap(tester, 'home.add');
    await _pumpUntil(tester, find.byKey(Key('category.$categoryId')));
    await _type(tester, '25000');
    await _tap(tester, 'category.$categoryId');
    await _tap(tester, 'add.save');
    await _pumpUntilGone(tester, find.byKey(const Key('add.sheet')));

    // The server has it, as the app (25.000 stored as cents), called by its category.
    Future<List<dynamic>> saved() async {
      final res = await _http.get<Map<String, dynamic>>(
        '$_server/api/v1/transactions',
        options: _auth(token),
      );
      expect(res.statusCode, 200);
      return (res.data!['items'] as List<dynamic>)
          .where((t) => (t as Map<String, dynamic>)['categoryId'] == categoryId)
          .toList();
    }

    var rows = await saved();
    expect(rows, hasLength(1));
    final row = rows.single as Map<String, dynamic>;
    expect(row['amount'], -2500000);
    expect(row['name'], name);
    expect(row['source'], 'app');
    // And it is on home, without leaving it.
    await _pumpUntil(tester, find.text(name));

    // A tap on the row opens it to edit: drop the last digit, Guardar cambios.
    await tester.pump(const Duration(seconds: 9));
    await _reveal(tester, find.text(name));
    await tester.tap(find.text(name).first);
    await _pumpUntil(tester, find.byKey(const Key('add.sheet')));
    await _tap(tester, 'keypad.backspace');
    await _tap(tester, 'add.save');
    await _pumpUntilGone(tester, find.byKey(const Key('add.sheet')));

    rows = await saved();
    expect(rows, hasLength(1), reason: 'an edit changes the movement, it adds none');
    expect((rows.single as Map<String, dynamic>)['amount'], -250000);
  });
}
