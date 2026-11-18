// Categorías on an Android emulator against the dev stack (`docker compose up -d` at the repo
// root), as docs/mobile/setup.md describes:
//
//   flutter test integration_test/budgets_test.dart -d emulator-5554 \
//     --dart-define=WAMBITO_SERVER=http://10.0.2.2:3000
//
// The emulator's language decides the copy, so buttons are found by key, and the tab and the
// category by what is the same in both languages. Amounts are typed with the digit keys only, so
// the guest's currency (decided by the phone's region) does not matter: every amount is cents.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/main.dart' as app;

const _server = String.fromEnvironment('WAMBITO_SERVER', defaultValue: 'http://10.0.2.2:3000');

final _http = Dio(BaseOptions(validateStatus: (_) => true));

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

/// Waits for [finder], scrolling the page down while it is not built yet: a new account starts
/// with the eight suggested categories, so one made by the test comes after them, below the fold.
Future<void> _scrollUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final page = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
    if (page.evaluate().isNotEmpty) {
      await tester.drag(page.first, const Offset(0, -300), warnIfMissed: false);
    }
  }
  throw TestFailure('Timed out waiting for $finder');
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

Options _auth(String token) => Options(headers: {'Authorization': 'Bearer $token'});

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('set a category budget from its detail, and the server and home follow', (
    tester,
  ) async {
    await SessionStore().clear();
    await tester.pumpWidget(await app.bootstrap());
    await _tap(tester, 'entry.start');
    await _pumpUntil(tester, find.byType(HomeScreen));
    await _pumpUntil(tester, find.byKey(const Key('home.add')));

    // A spending category of its own, made through the API; the app learns of it when it comes
    // back to the front.
    final token = (await SessionStore().read())!.token;
    final name = 'Casa ${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final made = await _http.post<Map<String, dynamic>>(
      '$_server/api/v1/categories',
      data: {'name': name, 'kind': 'expense', 'icon': '🏠', 'color': '#3fa7ff'},
      options: _auth(token),
    );
    expect(made.statusCode, 201, reason: '${made.data}');
    final categoryId = made.data!['id'] as String;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));

    // Categorías (Categories), the category, its detail.
    // The tab by its key: the account menu's own Categorías link is also in the tree.
    await _tap(tester, 'home.tab.budgets');
    await _scrollUntil(tester, find.text(name));
    await _reveal(tester, find.text(name));
    await tester.tap(find.text(name).first);
    await _tap(tester, 'detail.changeBudget');

    // 30000 on the keypad, Guardar.
    for (final digit in '30000'.split('')) {
      await _tap(tester, 'keypad.$digit');
    }
    await _tap(tester, 'budget.save');
    await _pumpUntilGone(tester, find.byKey(const Key('budget.save')));

    // The server has it from this month on, as cents.
    final res = await _http.get<List<dynamic>>('$_server/api/v1/categories', options: _auth(token));
    expect(res.statusCode, 200);
    final saved = res.data!.cast<Map<String, dynamic>>().firstWhere((c) => c['id'] == categoryId);
    expect(saved['currentBudget'], 3000000);

    // And the app shows it: the detail's figures, then home's row (Te quedan follows through the
    // same refresh).
    await _pumpUntil(tester, find.byKey(const Key('detail.budget')));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(
      find.bySemanticsLabel(RegExp(r'^(Volver a Categorías|Back to Categories)$')).first,
    );
    await tester.pumpAndSettle();
    final summary = await _http.get<Map<String, dynamic>>(
      '$_server/api/v1/summary',
      options: _auth(token),
    );
    final line = (summary.data!['categories'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((c) => c['categoryId'] == categoryId);
    expect(line['budget'], 3000000);
    expect(summary.data!['budgetTotal'], greaterThanOrEqualTo(3000000));
    expect(find.text(name), findsWidgets);
    await tester.pump(const Duration(seconds: 6));
  });
}
