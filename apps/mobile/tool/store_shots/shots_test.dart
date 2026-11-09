// The raw phone screenshots for the store listings (docs/mobile/play.md, "Screenshots"): a guest with
// invented data, then home, adding, quick capture, the review inbox, budgets and insights. Not a test:
// run by tool/store_shots/run.sh through `flutter drive`, once per listing locale, on an emulator set
// to that locale and time zone (the guest's currency follows them) against the dev stack.
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/budgets/categories_tab.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/l10n/app_localizations.dart';
import 'package:wambito/main.dart' as app;

const _server = String.fromEnvironment('WAMBITO_SERVER', defaultValue: 'http://10.0.2.2:3000');
const _locale = String.fromEnvironment('SHOTS_LOCALE', defaultValue: 'es-CO');

final _http = Dio(
  BaseOptions(
    validateStatus: (_) => true,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
  ),
)..interceptors.add(_RetryDropped());

/// Sends a request again (the same one: the batch keeps its Idempotency-Key) when the emulator's
/// network drops it ("Software caused connection abort"), up to three times.
class _RetryDropped extends Interceptor {
  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final tries = (err.requestOptions.extra['tries'] as int?) ?? 0;
    final dropped =
        err.type == DioExceptionType.unknown ||
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout;
    if (!dropped || tries >= 3) return handler.next(err);
    await Future<void>.delayed(const Duration(seconds: 2));
    err.requestOptions.extra['tries'] = tries + 1;
    try {
      handler.resolve(await _http.fetch<dynamic>(err.requestOptions));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

/// One listing's invented data: names in its language, amounts in its currency (cents).
class _Data {
  const _Data({
    required this.currency,
    required this.unit,
    required this.expenses,
    required this.income,
    required this.budgets,
    required this.captures,
    required this.captureSource,
    required this.typed,
    required this.keypad,
  });

  final String currency;

  /// What one "unit" of the amounts below is worth in cents (COP amounts are thousands of pesos).
  final int unit;

  /// (category glyph, name, amount in units, days ago).
  final List<(String, String, int, int)> expenses;
  final (String, int) income;

  /// (category glyph, monthly budget in units).
  final List<(String, int)> budgets;

  /// (merchant, amount in units).
  final List<(String, int)> captures;
  final String captureSource;

  /// The quick capture phrase, as typed.
  final String typed;

  /// The keys typed on the add sheet's keypad (`.` is the decimal key, a comma in some languages).
  final String keypad;
}

const _cop = _Data(
  currency: 'COP',
  unit: 100000, // 1 000 pesos
  expenses: [
    ('🛒', 'Mercado de la semana', 186, 1),
    ('🍽️', 'Almuerzo', 25, 2),
    ('🚗', 'Bus', 3, 3),
    ('☂️', 'Netflix', 27, 4),
    ('🍽️', 'Domicilio', 42, 5),
    ('⭐', 'Cine', 38, 6),
    ('🛒', 'Fruver', 31, 8),
    ('🚗', 'Gasolina', 120, 9),
    ('❤️', 'Farmacia', 46, 10),
  ],
  income: ('Salario', 4200),
  budgets: [('🛒', 900), ('🍽️', 400), ('🚗', 300), ('⭐', 200)],
  captures: [('Juan Valdez', 14), ('Éxito', 87)],
  captureSource: 'google_wallet',
  typed: '15 mil en almuerzo y 3 lukas en uber',
  keypad: '18000',
);

const _eurEs = _Data(
  currency: 'EUR',
  unit: 100, // 1 euro
  expenses: [
    ('🛒', 'Compra de la semana', 64, 1),
    ('🍽️', 'Menú del día', 13, 2),
    ('🚗', 'Metro', 2, 3),
    ('☂️', 'Spotify', 11, 4),
    ('🍽️', 'Cena con amigos', 38, 5),
    ('⭐', 'Cine', 9, 6),
    ('🛒', 'Frutería', 12, 8),
    ('🚗', 'Gasolina', 55, 9),
    ('❤️', 'Farmacia', 17, 10),
  ],
  income: ('Nómina', 2100),
  budgets: [('🛒', 350), ('🍽️', 180), ('🚗', 120), ('⭐', 80)],
  captures: [('Mercadona', 23), ('Café Central', 4)],
  captureSource: 'revolut',
  typed: '12 euros en el súper y 3 en el metro',
  keypad: '12.50',
);

const _usd = _Data(
  currency: 'USD',
  unit: 100,
  expenses: [
    ('🛒', 'Weekly groceries', 86, 1),
    ('🍽️', 'Lunch', 14, 2),
    ('🚗', 'Bus pass', 3, 3),
    ('☂️', 'Netflix', 16, 4),
    ('🍽️', 'Takeout', 32, 5),
    ('⭐', 'Movies', 24, 6),
    ('🛒', 'Farmers market', 21, 8),
    ('🚗', 'Gas', 48, 9),
    ('❤️', 'Pharmacy', 19, 10),
  ],
  income: ('Paycheck', 3200),
  budgets: [('🛒', 450), ('🍽️', 220), ('🚗', 150), ('⭐', 100)],
  captures: [('Blue Bottle Coffee', 6), ('Trader Joe\'s', 38)],
  captureSource: 'google_wallet',
  typed: '15 on lunch and 3 on the bus',
  keypad: '12.50',
);

const _eurIt = _Data(
  currency: 'EUR',
  unit: 100,
  expenses: [
    ('🛒', 'Spesa della settimana', 72, 1),
    ('🍽️', 'Pranzo', 14, 2),
    ('🚗', 'Autobus', 2, 3),
    ('☂️', 'Netflix', 13, 4),
    ('🍽️', 'Pizza con amici', 28, 5),
    ('⭐', 'Cinema', 9, 6),
    ('🛒', 'Fruttivendolo', 11, 8),
    ('🚗', 'Benzina', 60, 9),
    ('❤️', 'Farmacia', 16, 10),
  ],
  income: ('Stipendio', 1900),
  budgets: [('🛒', 380), ('🍽️', 160), ('🚗', 120), ('⭐', 80)],
  captures: [('Esselunga', 27), ('Bar Roma', 3)],
  captureSource: 'revolut',
  typed: '12 euro di spesa e 3 di autobus',
  keypad: '12.50',
);

const _eurPt = _Data(
  currency: 'EUR',
  unit: 100,
  expenses: [
    ('🛒', 'Compras da semana', 68, 1),
    ('🍽️', 'Almoço', 11, 2),
    ('🚗', 'Metro', 2, 3),
    ('☂️', 'Netflix', 12, 4),
    ('🍽️', 'Jantar com amigos', 34, 5),
    ('⭐', 'Cinema', 8, 6),
    ('🛒', 'Frutaria', 10, 8),
    ('🚗', 'Gasolina', 52, 9),
    ('❤️', 'Farmácia', 15, 10),
  ],
  income: ('Salário', 1600),
  budgets: [('🛒', 320), ('🍽️', 150), ('🚗', 100), ('⭐', 70)],
  captures: [('Pastelaria Aurora', 4), ('Pingo Doce', 26)],
  captureSource: 'revolut',
  typed: '12 euros no supermercado e 3 no metro',
  keypad: '12.50',
);

_Data _dataFor(String locale) => switch (locale) {
  'es-CO' => _cop,
  'es-ES' => _eurEs,
  'en-US' => _usd,
  'it-IT' => _eurIt,
  'pt-PT' => _eurPt,
  _ => throw ArgumentError('No store data for $locale'),
};

Future<void> _pumpUntil(WidgetTester tester, Finder finder, {int seconds = 40}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _pumpUntil(tester, find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)).first);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Lets animations and network answers land: a fixed wait, not pumpAndSettle (spinners never settle).
Future<void> _rest(WidgetTester tester, [int ms = 2500]) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Closes the notices question (it comes up on its own once home has loaded) before a screenshot.
Future<void> _clearPrompts(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    final later = find.byKey(const Key('notices.askLater')).hitTestable();
    if (later.evaluate().isEmpty) return;
    await tester.tap(later.first);
    await _rest(tester, 1500);
  }
}

/// Closes the sheet that holds [inside] with its own "Cerrar" (the navigator's maybePop as a
/// fallback). Never Android's Back: with nothing left to pop it sends the app to the background, and
/// the test then waits for ever.
Future<void> _closeSheet(WidgetTester tester, Finder inside, String what) async {
  for (var i = 0; i < 3 && inside.evaluate().isNotEmpty; i++) {
    final close = find.text(AppLocalizations.of(tester.element(inside.first)).close).hitTestable();
    if (close.evaluate().isNotEmpty) {
      await tester.tap(close.last);
    } else {
      await Navigator.of(tester.element(inside.first)).maybePop();
    }
    await _rest(tester, 2000);
  }
  if (inside.evaluate().isNotEmpty) throw TestFailure('The $what sheet did not close');
}

/// A screenshot, tried up to three times: the emulator's pixel copy sometimes fails once
/// ("Could not copy the pixels").
Future<void> _shot(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  for (var attempt = 1; ; attempt++) {
    try {
      await binding.takeScreenshot(name);
      return;
    } on PlatformException {
      if (attempt == 3) rethrow;
      await _rest(tester, 1500);
    }
  }
}

String _day(int daysAgo) {
  final d = DateTime.now().subtract(Duration(days: daysAgo));
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String _key() => List.generate(4, (_) => Random().nextInt(1 << 32).toRadixString(16)).join('-');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshots ($_locale)', (tester) async {
    final data = _dataFor(_locale);
    await SessionStore().clear();
    await tester.pumpWidget(await app.bootstrap());
    await _tap(tester, 'entry.guest');
    // Whatever stands between a new guest and home: the welcome, the notices question.
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (find.byKey(const Key('home.add')).hitTestable().evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw TestFailure('Home never showed');
      await tester.pump(const Duration(milliseconds: 300));
      for (final key in ['welcome.direct', 'notices.askLater']) {
        final f = find.byKey(Key(key)).hitTestable();
        if (f.evaluate().isNotEmpty) {
          await tester.tap(f.first);
          await _rest(tester, 1500);
        }
      }
    }

    // The guest's own categories (the suggested ones, in its language), by glyph.
    final token = (await SessionStore().read())!.token;
    final auth = Options(headers: {'Authorization': 'Bearer $token'});
    final cats = await _http.get<List<dynamic>>('$_server/api/v1/categories', options: auth);
    expect(cats.statusCode, 200, reason: '${cats.data}');
    final byGlyph = <String, String>{};
    String? incomeId;
    for (final c in cats.data!.cast<Map<String, dynamic>>()) {
      byGlyph.putIfAbsent(c['icon'] as String, () => c['id'] as String);
      if (c['kind'] == 'income') incomeId ??= c['id'] as String;
    }

    // Transactions within this month only (a seed on the 5th keeps its "days ago" in the month).
    final today = DateTime.now().day;
    final items = [
      for (final (glyph, name, amount, ago) in data.expenses)
        {
          'name': name,
          // The API stores an expense as a negative amount.
          'amount': -amount * data.unit,
          'categoryId': byGlyph[glyph],
          'date': _day(min(ago, today - 1)),
          'source': 'app',
        },
      if (incomeId != null)
        {
          'name': data.income.$1,
          'amount': data.income.$2 * data.unit,
          'categoryId': incomeId,
          'date': _day(today - 1),
          'source': 'app',
        },
    ];
    final batch = await _http.post<dynamic>(
      '$_server/api/v1/transactions/batch',
      data: {'items': items},
      options: Options(headers: {...auth.headers!, 'Idempotency-Key': _key()}),
    );
    expect(batch.statusCode, 201, reason: '${batch.data}');

    final month = _day(today - 1).substring(0, 7);
    for (final (glyph, amount) in data.budgets) {
      final res = await _http.put<dynamic>(
        '$_server/api/v1/categories/${byGlyph[glyph]}/budget',
        data: {'amount': amount * data.unit, 'effectiveFrom': month},
        options: auth,
      );
      expect(res.statusCode, 200, reason: '${res.data}');
    }

    for (final (i, (merchant, amount)) in data.captures.indexed) {
      final res = await _http.post<dynamic>(
        '$_server/api/v1/captures',
        data: {
          'kind': 'expense',
          'amount': amount * data.unit,
          'currency': data.currency,
          'merchant': merchant,
          'capturedAt': DateTime.now()
              .subtract(Duration(minutes: 20 + 90 * i))
              .toUtc()
              .toIso8601String(),
          'source': data.captureSource,
        },
        options: Options(headers: {...auth.headers!, 'Idempotency-Key': _key()}),
      );
      expect(res.statusCode, anyOf(200, 201), reason: '${res.data}');
    }

    // Home picks the data up when it comes back to the front.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 300));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpUntil(tester, find.byKey(const Key('home.review')));
    await _rest(tester);
    await binding.convertFlutterSurfaceToImage();
    await _rest(tester, 500);
    await _clearPrompts(tester);
    await _shot(tester, binding, '1_home');

    // Adding by hand: the keypad and a category.
    await _clearPrompts(tester);
    await _tap(tester, 'home.add');
    for (final digit in data.keypad.split('')) {
      await _tap(tester, digit == '.' ? 'keypad.decimal' : 'keypad.$digit');
    }
    await _tap(tester, 'category.${byGlyph['🍽️']}');
    await _rest(tester);
    await _clearPrompts(tester);
    await _shot(tester, binding, '2_add');
    await _closeSheet(tester, find.byKey(const Key('add.sheet')), 'add');

    // Quick capture, typed (the voice model is not on the emulator): the phrase becomes cards.
    await _clearPrompts(tester);
    await _tap(tester, 'home.capture');
    await _rest(tester, 1500);
    // The sheet may first offer the voice model (declined) or start listening (switched to typing),
    // and changes while it opens: react to what is there until the text field shows.
    final field = find.byKey(const Key('capture.field'));
    final typeBy = DateTime.now().add(const Duration(seconds: 40));
    while (field.evaluate().isEmpty) {
      if (DateTime.now().isAfter(typeBy)) throw TestFailure('The capture field never showed');
      for (final key in ['capture.offer.decline', 'capture.type']) {
        final f = find.byKey(Key(key)).hitTestable();
        if (f.evaluate().isNotEmpty) {
          await tester.tap(f.first);
          break;
        }
      }
      await _rest(tester, 800);
    }
    await _pumpUntil(tester, find.byKey(const Key('capture.field')));
    await tester.enterText(find.byKey(const Key('capture.field')), data.typed);
    await _tap(tester, 'capture.read');
    await _pumpUntil(tester, find.byKey(const Key('capture.card.1')));
    await _rest(tester);
    await _clearPrompts(tester);
    await _shot(tester, binding, '3_capture');
    // Its first card marks it (the field is gone once the phrase is read).
    await _closeSheet(tester, find.byKey(const Key('capture.card.1')), 'capture');
    final router = GoRouter.of(tester.element(find.byType(HomeScreen)));

    // The inbox of transactions read from bank notifications.
    router.go('/');
    await _rest(tester, 1500);
    router.push('/review');
    await _pumpUntil(tester, find.byKey(const Key('review.page')));
    await _rest(tester);
    await _clearPrompts(tester);
    await _shot(tester, binding, '4_review');

    // Budgets (the app's own `/categories` address opens home's Categorías tab), then insights.
    router.go('/categories');
    await _pumpUntil(tester, find.byType(CategoriesTab));
    await _rest(tester);
    await _clearPrompts(tester);
    await _shot(tester, binding, '5_budgets');
    router.go('/insights');
    await _rest(tester, 4000);
    await _clearPrompts(tester);
    await _shot(tester, binding, '6_insights');
  });
}
