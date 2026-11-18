// Importing a bank file on an Android emulator against the dev stack (`docker compose up -d` at the
// repo root), as docs/mobile/setup.md describes:
//
//   flutter test integration_test/import_test.dart -d emulator-5554 \
//     --dart-define=WAMBITO_SERVER=http://10.0.2.2:3000
//
// The files go through the real `wambito/files` channel (android/.../files/FilesChannel.kt): the
// debug build lets the test stand in for the person at the system's document picker (`injectPick`
// hands the next pick a file in the app's cache), and the file is then read, bounded, off the main
// thread by the same Kotlin code a picked document goes through. Everything after it is the real
// app against the real API. The emulator's language decides the copy, so controls and messages are
// found by key.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/main.dart' as app;

/// CI's emulator draws with software rendering, and its longest gap was 866 ms with nothing wrong
/// (the script passes `CI=true` from the runner's own environment). A phone or a local emulator keeps
/// the tight limit: it is the one that notices the app doing work on the UI isolate.
const _ci = bool.fromEnvironment('CI');
const _longestFrameGap = Duration(milliseconds: _ci ? 1500 : 700);

const _server = String.fromEnvironment('WAMBITO_SERVER', defaultValue: 'http://10.0.2.2:3000');
const _files = MethodChannel('wambito/files');

final _http = Dio(BaseOptions(validateStatus: (_) => true));

Options _auth(String token) => Options(headers: {'Authorization': 'Bearer $token'});

/// `packages/importers/test/fixtures/budge-sample.csv`: 22 rows, one with a bad date.
const _sample = '''﻿Format version,Period,User ID
1,01-09-2026..31-10-2026,FAKEuserID000000000000000000

###

Date,Payment,Is paid,Amount,Currency,Account,Category,Subcategory,Goal,Description
01-09-2026,Salary,true,3000,EUR,main,Salário,,,
02-09-2026,groceries ,true,-30.70,EUR,main,Supermercado,,,
03-09-2026,electricity,true,-16,EUR,main,Casa,,,
04-09-2026,metro,true,-4.6,EUR,main,Transporte,,,
05-09-2026,cinema,true,-9.50,EUR,main,Ocio,,,
10-09-2026,coffee,true,-1.20,EUR,main,Restaurante,,,
10-09-2026,coffee,true,-1.20,EUR,main,Restaurante,,,
12-09-2026,"vitamins C, Zinc",true,-59,EUR,main,Vida,,,
15-09-2026,music streaming,true,-3.53,EUR,main,suscripciones,,,
18-09-2026,sold old lamp,true,5,EUR,main,Ocio,,,
20-09-2026,lunch,true,-12.40,EUR,main,Restaurante,,,
25-09-2026,dividends,true,14.25,EUR,main,Investimento,,,
31-02-2026,broken date,true,-1,EUR,main,Ocio,,,
01-10-2026,Salary,true,3000,EUR,main,Salário,,,
02-10-2026,flights (1/3),true,-120,EUR,main,Ocio,,,split in three payments
05-10-2026,groceries,true,-41.08,EUR,main,Supermercado,,,
08-10-2026,bus,true,-2,EUR,main,Transporte,,,
12-10-2026,dinner,true,-35,EUR,main,Restaurante,,,
15-10-2026,music streaming,true,-3.53,EUR,main,suscripciones,,,
20-10-2026,accountant,true,-61.50,EUR,main,Taxes,,,
23-10-2026,video streaming,false,-7.99,EUR,main,suscripciones,,,
28-10-2026,internet,false,-39.90,EUR,main,Casa,,,
30-10-2026,desk lamp,true,-24.99,EUR,main,Things,,,

###

Account,Account Balance,Available Balance,Credit Limit,Currency,Is savings,Description
main,1234.56,1234.56,0,EUR,false,

###
''';

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 60),
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
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder to go');
}

/// Waits for "Importamos N movimientos", and fails with the error on screen if one shows instead.
Future<void> _imported(WidgetTester tester) async {
  final started = DateTime.now();
  await _pumpUntil(
    tester,
    find.byWidgetPredicate(
      (w) => w.key == const Key('import.imported') || w.key == const Key('import.error'),
    ),
  );
  final error = find.byKey(const Key('import.error'));
  if (error.evaluate().isNotEmpty) {
    fail('the import failed: ${(tester.widget(error) as Text).data}');
  }
  // ignore: avoid_print
  print('imported after ${DateTime.now().difference(started)}');
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _pumpUntil(tester, find.byKey(Key(key)));
  final element = tester.element(find.byKey(Key(key)).first);
  if (Scrollable.maybeOf(element) != null) {
    await Scrollable.ensureVisible(element, alignment: 0.3);
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.tap(find.byKey(Key(key)));
  await tester.pump(const Duration(milliseconds: 300));
}

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

/// A file in the app's cache, for the picker to hand over.
Future<String> _file(String name, List<int> bytes) async {
  final file = File('${Directory.systemTemp.path}/$name');
  await file.writeAsBytes(bytes);
  return file.path;
}

/// What a person does: Budge, then the picker, which gives [path].
Future<void> _pick(WidgetTester tester, String path) async {
  await _files.invokeMethod<void>('injectPick', path);
  await _tap(tester, 'import.choose');
}

/// Reads [count] transactions of [month] (`YYYY-MM`), paging as the app does.
Future<int> _countIn(String token, String month) async {
  var count = 0;
  String? cursor;
  do {
    final res = await _http.get<Map<String, dynamic>>(
      '$_server/api/v1/transactions?month=$month&limit=200${cursor == null ? '' : '&cursor=$cursor'}',
      options: _auth(token),
    );
    expect(res.statusCode, 200, reason: '${res.data}');
    count += (res.data!['items'] as List).length;
    cursor = res.data!['nextCursor'] as String?;
  } while (cursor != null);
  return count;
}

String _bigFile(int rows) {
  final out = StringBuffer(_sample.split('###').first)
    ..writeln('###')
    ..writeln()
    ..writeln('Date,Payment,Is paid,Amount,Currency,Account,Category,Subcategory,Goal,Description');
  for (var i = 0; i < rows; i++) {
    final day = (i % 28 + 1).toString().padLeft(2, '0');
    out.writeln('$day-08-2026,shop $i,true,-${(i % 90) + 1}.50,EUR,main,Supermercado,,,');
  }
  out
    ..writeln()
    ..writeln('###');
  return out.toString();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('imports a Budge file through the files channel; a 2,000-row file, a malformed one and one '
      'over the limit get the web\'s limits and errors', (tester) async {
    await _startAsGuest(tester);
    await _pumpUntil(tester, find.byKey(const Key('home.add')));
    final token = (await SessionStore().read())!.token;

    GoRouter.of(tester.element(find.byType(HomeScreen))).go('/import');
    await _pumpUntil(tester, find.byKey(const Key('import.page')));
    await _tap(tester, 'import.source.budge');

    // A file over the API's 5 MB: the channel reads no further than the limit, and says so; nothing
    // is sent, and the picker is still there.
    await _pick(tester, await _file('huge.csv', List.filled(5 * 1024 * 1024 + 1, 0x41)));
    await _pumpUntil(tester, find.byKey(const Key('import.error')));
    expect(find.byKey(const Key('import.choose')), findsOneWidget);

    // A file that is not a Budge export: the API refuses it, with its message.
    await _pick(tester, await _file('notes.csv', 'hello,world\n1,2\n'.codeUnits));
    await _pumpUntilGone(tester, find.byKey(const Key('import.reading')));
    await _pumpUntil(tester, find.byKey(const Key('import.error')));
    expect(find.byKey(const Key('import.choose')), findsOneWidget);

    // The sample (22 rows, one with a bad date): the preview, then the import.
    await _pick(tester, await _file('budge-sample.csv', _sample.codeUnits));
    await _pumpUntil(tester, find.byKey(const Key('import.preview')));
    await _pumpUntil(tester, find.byKey(const Key('import.confirm')));
    expect(find.byKey(const Key('import.error')), findsNothing);
    expect(find.textContaining('budge-sample.csv'), findsOneWidget);
    // Nothing is in the account until the confirm.
    expect(await _countIn(token, '2026-09') + await _countIn(token, '2026-10'), 0);
    await _tap(tester, 'import.confirm');
    await _imported(tester);
    await _pumpUntil(tester, find.byKey(const Key('import.budgets')));
    // 12 rows in September and 10 in October went in (the bad date did not).
    expect(await _countIn(token, '2026-09'), 12);
    expect(await _countIn(token, '2026-10'), 10);
    final me = await _http.get<Map<String, dynamic>>('$_server/api/v1/me', options: _auth(token));
    expect(me.data!['currency'], 'EUR', reason: 'the empty account took the file\'s currency');
    final categories = await _http.get<List<dynamic>>(
      '$_server/api/v1/categories',
      options: _auth(token),
    );
    expect(
      (categories.data!).map((c) => (c as Map)['name']),
      containsAll(['Supermercado', 'Ocio', 'Taxes']),
    );

    // The same file again: the API knows it.
    await _tap(tester, 'import.home');
    GoRouter.of(tester.element(find.byType(HomeScreen))).go('/import');
    await _pumpUntil(tester, find.byKey(const Key('import.page')));
    await _tap(tester, 'import.source.budge');
    await _pick(tester, await _file('budge-sample.csv', _sample.codeUnits));
    await _pumpUntil(tester, find.byKey(const Key('import.error')));
    expect(find.byKey(const Key('import.confirm')), findsNothing);

    // 2,000 rows: the app only forwards the bytes. The frames keep coming while the upload and
    // the API's reading go on (no freeze: the longest gap between two frames stays short).
    final big = _bigFile(2000);
    expect(big.length, lessThan(5 * 1024 * 1024));
    var longest = Duration.zero;
    var last = DateTime.now();
    final end = DateTime.now().add(const Duration(minutes: 2));
    await _files.invokeMethod<void>('injectPick', await _file('big.csv', big.codeUnits));
    await _tap(tester, 'import.choose');
    while (find.byKey(const Key('import.confirm')).evaluate().isEmpty &&
        DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 16));
      final now = DateTime.now();
      // The test's own wait is 16 ms a frame: a gap far beyond that is the app being busy.
      final gap = now.difference(last) - const Duration(milliseconds: 16);
      if (gap > longest) longest = gap;
      last = now;
      await Future<void>.delayed(const Duration(milliseconds: 16));
      last = DateTime.now();
    }
    expect(find.byKey(const Key('import.confirm')), findsOneWidget);
    expect(longest, lessThan(_longestFrameGap), reason: 'the UI froze');
    await _tap(tester, 'import.confirm');
    await _pumpUntil(tester, find.byKey(const Key('import.imported')));
    expect(await _countIn(token, '2026-08'), 2000);

    await SessionStore().clear();
    await tester.pump(const Duration(seconds: 6));
  });
}
