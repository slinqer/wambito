// Managing categories on an Android emulator against the dev stack (`docker compose up -d` at the
// repo root), as docs/mobile/setup.md describes:
//
//   flutter test integration_test/categories_test.dart -d emulator-5554 \
//     --dart-define=WAMBITO_SERVER=http://10.0.2.2:3000
//
// The emulator's language decides the copy, so buttons and fields are found by key, and the tab by
// what is the same in both languages.
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

/// What a person does with the keyboard that a field opened before reaching for a button under it:
/// puts it away. On a short phone with a soft keyboard (CI's emulator has a hardware one) the keyboard
/// covers the rest of the sheet, and a tap there would land on it.
Future<void> _dismissKeyboard(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 500));
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

Future<Map<String, dynamic>?> _category(String token, String name) async {
  final res = await _http.get<List<dynamic>>(
    '$_server/api/v1/categories?includeArchived=true',
    options: _auth(token),
  );
  expect(res.statusCode, 200);
  return res.data!.cast<Map<String, dynamic>>().where((c) => c['name'] == name).firstOrNull;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create a category from the tab, then rename, archive and restore it', (
    tester,
  ) async {
    await SessionStore().clear();
    await tester.pumpWidget(await app.bootstrap());
    await _tap(tester, 'entry.start');
    await _pumpUntil(tester, find.byType(HomeScreen));
    await _pumpUntil(tester, find.byKey(const Key('home.add')));
    final token = (await SessionStore().read())!.token;
    final name = 'Mascotas ${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final renamed = '$name y más';

    // A fresh guest has no category, and home then offers the suggestions instead of its tabs: one
    // of its own, made through the API (the app learns of it when it comes back to the front).
    final seed = await _http.post<Map<String, dynamic>>(
      '$_server/api/v1/categories',
      data: {'name': 'Casa $name', 'kind': 'expense', 'icon': '🏠', 'color': '#3fa7ff'},
      options: _auth(token),
    );
    expect(seed.statusCode, 201, reason: '${seed.data}');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));

    // Categorías (Categories), "Nueva categoría": a name and an emoji, Guardar.
    // The tab by its key: the account menu's own Categorías link is also in the tree.
    await _tap(tester, 'home.tab.budgets');
    await _tap(tester, 'categories.add');
    await _pumpUntil(tester, find.byKey(const Key('category.name')));
    await tester.enterText(find.byKey(const Key('category.name')), name);
    await _dismissKeyboard(tester);
    await tester.pump();
    await _tap(tester, 'category.glyph.🐶');
    await _tap(tester, 'category.save');
    await _pumpUntilGone(tester, find.byKey(const Key('category.save')));

    // The server has it, with what was chosen; the tab lists it.
    final made = await _category(token, name);
    expect(made, isNotNull, reason: 'the category was created on the server');
    expect(made!['icon'], '🐶');
    expect(made['kind'], 'expense');
    expect(made['archived'], false);
    await _pumpUntil(tester, find.text(name));

    // Its detail: rename it (and change its colour).
    await _reveal(tester, find.text(name));
    await tester.tap(find.text(name).first);
    await _tap(tester, 'detail.edit');
    await _pumpUntil(tester, find.byKey(const Key('category.name')));
    await tester.enterText(find.byKey(const Key('category.name')), renamed);
    await _dismissKeyboard(tester);
    await tester.pump();
    await _tap(tester, 'category.tint.blue');
    await _tap(tester, 'category.save');
    await _pumpUntilGone(tester, find.byKey(const Key('category.save')));
    final saved = await _category(token, renamed);
    expect(saved, isNotNull, reason: 'the rename reached the server');
    expect(saved!['id'], made['id']);
    expect(saved['color'], '#3fa7ff');
    expect(saved['icon'], '🐶');

    // Archive it, after the question.
    await _tap(tester, 'detail.edit');
    await _tap(tester, 'category.archive');
    await _tap(tester, 'category.archive.confirm');
    await _pumpUntil(tester, find.byKey(const Key('detail.restore')));
    expect((await _category(token, renamed))!['archived'], true);

    // And bring it back from the detail.
    await _tap(tester, 'detail.restore');
    await _pumpUntilGone(tester, find.byKey(const Key('detail.restore')));
    expect((await _category(token, renamed))!['archived'], false);
    await tester.pump(const Duration(seconds: 6));
  });
}
