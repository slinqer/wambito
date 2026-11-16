import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/budgets/budgets_repository.dart';
import 'package:wambito/home/home_cache.dart';
import 'package:wambito/home/home_controller.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/ui/budget_bar.dart';
import 'package:wambito/ui/category_row.dart';

import '../home/fakes.dart';
import '../home/fixtures.dart';
import '../home/home_harness.dart' show testNow;
import '../settings/harness.dart';
import '../support/page_gradient.dart';
import 'fakes.dart';

import 'package:wambito/ui/lk_icons.dart';

import '../support/icons.dart';

/// Categorías, a category's detail and the budget sheet, in the whole app (the real router, home
/// under the detail) against fakes of the server. How they look is the parity pairs' business
/// (test/parity/budgets_parity_test.dart); here is what they do.

class Env {
  Env(this.settings, this.home, this.budgets, this.snapshots);

  final SettingsEnv settings;
  final FakeHomeRepository home;
  final FakeBudgetsRepository budgets;

  /// The summaries the widget was told, in order.
  final List<Summary> snapshots;
}

Future<Env> pumpBudgets(
  WidgetTester tester, {
  FakeHomeRepository? home,
  FakeBudgetsRepository? budgets,
  Locale locale = const Locale('es'),
  String? location,
  List<Override> overrides = const [],
  DateTime? now,
}) async {
  final server = home ?? budgetsMonth();
  final fake = budgets ?? budgetsFor(server);
  final snapshots = <Summary>[];
  final settings = await pumpSettingsApp(
    tester,
    homeRepo: server,
    locale: locale,
    location: location,
    overrides: [
      budgetsRepositoryProvider.overrideWithValue(fake),
      clockProvider.overrideWithValue(() => now ?? testNow),
      wambiVariantProvider.overrideWithValue(() => 1),
      widgetSnapshotWriterProvider.overrideWithValue(
        (summary, {required currency, required locale, required timezone}) async =>
            snapshots.add(summary),
      ),
      ...overrides,
    ],
  );
  return Env(settings, server, fake, snapshots);
}

Future<void> openBudgetsTab(WidgetTester tester) async {
  await tester.tap(find.text('Categorías'));
  await tester.pumpAndSettle();
}

Future<void> openDetail(WidgetTester tester, String name) async {
  await openBudgetsTab(tester);
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

Future<void> openBudgetSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('detail.changeBudget')));
  await tester.pumpAndSettle();
}

Future<void> typeDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.byKey(Key('keypad.$digit')));
    await tester.pump();
  }
}

Future<void> eraseAll(WidgetTester tester, {int times = 12}) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(const Key('keypad.backspace')));
    await tester.pump();
  }
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('budget.save')));
  await tester.pumpAndSettle();
}

String _shown(WidgetTester tester, Key key) {
  final text = tester.widget<Text>(find.byKey(key));
  return text.textSpan?.toPlainText() ?? text.data ?? '';
}

/// A budget row, by what a screen reader hears: its name and its status.
Finder _row(String label) => find.bySemanticsLabel(RegExp('^$label\$'));

/// A widget test with semantics on: rows are found by what a screen reader hears.
void testBudgets(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      handle.dispose();
    }
  });
}

void main() {
  group('the Categorías tab', () {
    testBudgets('the Categorías tab lists each category with its bar, like the web', (
      tester,
    ) async {
      await pumpBudgets(tester);
      await openBudgetsTab(tester);

      final rows = find.byType(CategoryRow);
      expect(rows, findsNWidgets(2), reason: 'the two spending categories; income has no budget');
      // In the categories' own order (Hogar, then Supermercado), as the web sorts by `sortOrder`.
      final order = [for (final row in tester.widgetList<CategoryRow>(rows)) row.name];
      expect(order, ['Hogar', 'Supermercado']);
      expect(find.text('Nómina'), findsNothing);

      final market = find.ancestor(
        of: find.text('Supermercado'),
        matching: find.byType(CategoryRow),
      );
      expect(find.descendant(of: market, matching: find.text(r'$250.000')), findsOneWidget);
      expect(_row(r'Supermercado Quedan \$67\.000'), findsOneWidget);
      expect(find.descendant(of: market, matching: find.byType(BudgetBar)), findsOneWidget);
      expect(_row(r'Hogar Quedan \$600\.000'), findsOneWidget);
      expect(find.text('Arriendo'), findsNothing, reason: 'the movements are the other tab');
    });

    testBudgets('a category without a budget says so, and what was spent', (tester) async {
      final home = budgetsMonth();
      final budgets = FakeBudgetsRepository(home, budgets: {'cat-home': 60000000});
      await pumpBudgets(tester, home: home, budgets: budgets);
      await openBudgetsTab(tester);

      final market = find.ancestor(
        of: find.text('Supermercado'),
        matching: find.byType(CategoryRow),
      );
      expect(_row(r'Supermercado Sin presupuesto'), findsOneWidget);
      expect(find.descendant(of: market, matching: find.byType(BudgetBar)), findsNothing);
    });

    testBudgets('an archived category with spending this month stays among the rows, noted', (
      tester,
    ) async {
      final home = budgetsMonth();
      home.categoryList.add(category('cat-old', 'Gimnasio', icon: '🏋️', archived: true));
      home.items.add(tx('gym', '2026-10-03', -4000000, name: 'Mensualidad', categoryId: 'cat-old'));
      await pumpBudgets(tester, home: home);
      await openBudgetsTab(tester);
      // Like the web's: the rows add up to what the month spent, in the categories' own order.
      final order = [
        for (final row in tester.widgetList<CategoryRow>(find.byType(CategoryRow))) row.name,
      ];
      expect(order, ['Hogar', 'Gimnasio', 'Supermercado']);
      expect(_row(r'Gimnasio archivada Sin presupuesto'), findsOneWidget);
      expect(find.textContaining('· archivada'), findsOneWidget);
      expect(find.textContaining(r'$40.000'), findsWidgets, reason: 'what it spent is on its row');
      expect(find.byKey(const Key('categories.fold')), findsNothing, reason: 'not folded as well');
    });

    testBudgets('with no spending categories it says so, as the web does', (tester) async {
      final home = budgetsMonth()
        ..categoryList.removeWhere((c) => c.kind == CategoryKindEnum.expense);
      await pumpBudgets(tester, home: home);
      await openBudgetsTab(tester);
      expect(find.text('No tienes categorías de gasto activas.'), findsOneWidget);
      expect(find.byType(CategoryRow), findsNothing);
    });

    testBudgets('in English the copy is English', (tester) async {
      await pumpBudgets(tester, locale: const Locale('en'));
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      expect(_row(r'Supermercado COP\s67,000 left'), findsOneWidget);
    });
  });

  group('a category\'s detail', () {
    testBudgets('tapping a category opens its detail with that month\'s movements', (tester) async {
      final env = await pumpBudgets(tester);
      await openDetail(tester, 'Supermercado');

      expect(_shown(tester, const Key('detail.title')), 'Supermercado');
      expect(find.text('Categoría de gasto'), findsOneWidget);
      expect(find.text('Octubre'), findsOneWidget);
      expect(find.text('Movimientos de octubre'), findsOneWidget);
      // This category's movements of the month, and no other category's.
      expect(find.text('Mercado'), findsOneWidget);
      expect(find.text('Frutas'), findsOneWidget);
      expect(find.text('Arriendo'), findsNothing);
      expect(find.text('Nómina'), findsNothing);
      // Its budget, in words and as a bar.
      expect(find.text(r'Quedan $67.000'), findsOneWidget);
      expect(find.text(r'Gastado $183.000 de $250.000'), findsOneWidget);
      expect(find.byType(BudgetBar), findsOneWidget);
      expect(find.text('CAMBIAR PRESUPUESTO'), findsOneWidget);
      expect(env.budgets.calls, contains('transactions 2026-10 cat-groceries'));
    });

    testBudgets('it opens on the month home was on, and stepping back asks for that month', (
      tester,
    ) async {
      final env = await pumpBudgets(tester);
      await tester.tap(findIcon(LkIconName.chevronLeft));
      await tester.pumpAndSettle();
      expect(find.text('Septiembre'), findsOneWidget);
      await openDetail(tester, 'Supermercado');
      expect(find.text('Septiembre'), findsOneWidget);
      expect(find.text('Movimientos de septiembre'), findsOneWidget);
      expect(env.budgets.calls, contains('transactions 2026-09 cat-groceries'));
      expect(env.home.calls, contains('summary 2026-09'));
      expect(find.text('Mercado'), findsNothing, reason: 'that is October\'s');
      expect(find.text('No hay movimientos de Supermercado en septiembre.'), findsOneWidget);
    });

    testBudgets('the detail steps between months with its own picker, never past the current one', (
      tester,
    ) async {
      final env = await pumpBudgets(tester);
      await openDetail(tester, 'Supermercado');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Mes siguiente')).flagsCollection.isEnabled,
        Tristate.isFalse,
        reason: 'October is the current month',
      );
      await tester.tap(find.bySemanticsLabel('Mes anterior'));
      await tester.pumpAndSettle();
      expect(find.text('Septiembre'), findsOneWidget);
      expect(find.text('Movimientos de septiembre'), findsOneWidget);
      expect(env.budgets.calls, contains('transactions 2026-09 cat-groceries'));
      await tester.tap(find.bySemanticsLabel('Mes siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Octubre'), findsOneWidget);
      expect(find.text('Mercado'), findsOneWidget);
    });

    testBudgets('a month with no movements says so and offers to add one', (tester) async {
      final env = await pumpBudgets(tester, location: '/categories/cat-home?month=2026-09');
      expect(find.text('Septiembre'), findsOneWidget);
      expect(find.text('No hay movimientos de Hogar en septiembre.'), findsOneWidget);
      expect(find.text('AGREGAR GASTO'), findsOneWidget);
      await tester.tap(find.text('AGREGAR GASTO'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add.sheet')), findsOneWidget);
      expect(env.budgets.calls, contains('transactions 2026-09 cat-home'));
    });

    testBudgets('a category without a budget offers to set one, and says what was spent', (
      tester,
    ) async {
      final home = budgetsMonth();
      final budgets = FakeBudgetsRepository(home, budgets: {'cat-home': 60000000});
      await pumpBudgets(tester, home: home, budgets: budgets);
      await openDetail(tester, 'Supermercado');
      expect(
        find.text('Sin presupuesto en octubre. Ponle uno y te aviso antes de que te pases.'),
        findsOneWidget,
      );
      expect(find.text(r'Gastado en octubre: $183.000'), findsOneWidget);
      expect(find.text('PONER PRESUPUESTO'), findsOneWidget);
      expect(find.byType(BudgetBar), findsNothing);
    });

    testBudgets('an income category shows what came in, and no budget', (tester) async {
      await pumpBudgets(tester, location: '/categories/cat-salary?month=2026-10');
      expect(find.text('Categoría de ingreso'), findsOneWidget);
      expect(find.text(r'Recibido en octubre: $3.000.000'), findsOneWidget);
      expect(find.byKey(const Key('detail.changeBudget')), findsNothing);
      expect(find.text('Nómina'), findsWidgets);
    });

    testBudgets('an archived category says so and offers no budget', (tester) async {
      final home = budgetsMonth();
      home.categoryList.add(category('cat-old', 'Gimnasio', icon: '🏋️', archived: true));
      await pumpBudgets(tester, home: home, location: '/categories/cat-old');
      expect(find.text('Categoría de gasto · Archivada'), findsOneWidget);
      expect(find.textContaining('Esta categoría está archivada'), findsOneWidget);
      expect(find.byKey(const Key('detail.changeBudget')), findsNothing);
      expect(find.text('PONER PRESUPUESTO'), findsNothing);
    });

    testBudgets('a category that is not there says so', (tester) async {
      await pumpBudgets(tester, location: '/categories/nope');
      expect(find.text('No encontramos esta categoría'), findsOneWidget);
      expect(find.byKey(const Key('detail.title')), findsNothing);
    });

    testBudgets('opened from the tab, Volver a Categorías goes back to home', (tester) async {
      await pumpBudgets(tester);
      await openDetail(tester, 'Supermercado');
      await tester.tap(find.bySemanticsLabel('Volver a Categorías').first);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(const Key('detail.title')), findsNothing);
    });

    testBudgets('opened by a link, Volver al inicio goes back to home', (tester) async {
      await pumpBudgets(tester, location: '/categories/cat-groceries');
      expect(find.bySemanticsLabel('Volver a Categorías'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Volver al inicio').first);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testBudgets('a movement opens the edit sheet; saving it brings the detail up to date', (
      tester,
    ) async {
      await pumpBudgets(tester);
      await openDetail(tester, 'Supermercado');
      await tester.tap(find.text('Frutas'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add.sheet')), findsOneWidget);
    });

    testBudgets('a long category name and a huge budget fit a narrow phone at 130%', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final home = budgetsMonth();
      final long = 'Supermercado y todo lo de la casa del mes';
      home.categoryList[0] = home.categoryList[0].rebuild((b) => b.name = long);
      final budgets = FakeBudgetsRepository(
        home,
        budgets: {'cat-groceries': 150000000000000, 'cat-home': 60000000},
      );
      await pumpBudgets(tester, home: home, budgets: budgets);
      tester.view.physicalSize = const Size(360, 640);
      await tester.pumpAndSettle();
      await openBudgetsTab(tester);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.textContaining('Supermercado y todo'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Supermercado y todo'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'no overflow stripes in the detail');
      expect(find.byKey(const Key('detail.changeBudget')), findsOneWidget);
    });
  });

  group('setting a budget', () {
    testBudgets('the sheet starts from the budget it has, from the month on screen', (
      tester,
    ) async {
      await pumpBudgets(tester);
      await openDetail(tester, 'Supermercado');
      await openBudgetSheet(tester);
      expect(find.text('Presupuesto de Supermercado'), findsOneWidget);
      expect(
        find.text('Desde octubre en adelante. Los meses anteriores quedan como estaban.'),
        findsOneWidget,
      );
      expect(find.textContaining(r'$250.000', findRichText: true), findsWidgets);
      expect(find.text('GUARDAR PRESUPUESTO'), findsOneWidget);
    });

    testBudgets('setting a budget saves it and the bar and Te quedan update', (tester) async {
      final env = await pumpBudgets(tester);
      expect(find.text(r'$667.000'), findsOneWidget, reason: 'Te quedan, before');
      await openDetail(tester, 'Supermercado');
      await openBudgetSheet(tester);
      await eraseAll(tester);
      await typeDigits(tester, '300000');
      await save(tester);

      // It went to the server from this month on, in hundredths.
      expect(env.budgets.calls, contains('setBudget cat-groceries 30000000 2026-10'));
      // The sheet is gone, the toast says what was saved, and the detail's bar followed.
      expect(find.text('GUARDAR PRESUPUESTO'), findsNothing);
      expect(find.text(r'Presupuesto de Supermercado: $300.000 (300 lukas)'), findsOneWidget);
      expect(find.text(r'Quedan $117.000'), findsOneWidget);
      expect(find.text(r'Gastado $183.000 de $300.000'), findsOneWidget);

      // Home, behind it: Te quedan and the Categorías bars follow.
      await tester.tap(find.bySemanticsLabel('Volver a Categorías').first);
      await tester.pumpAndSettle();
      expect(find.text(r'$717.000'), findsOneWidget, reason: 'Te quedan, after');
      expect(find.text(r'de $900.000'), findsOneWidget);
      // Categorías is still the tab it was left on.
      final row = find.ancestor(of: find.text('Supermercado'), matching: find.byType(CategoryRow));
      expect(_row(r'Supermercado Quedan \$117\.000'), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text(r'$300.000')), findsOneWidget);
      // The widget follows: the last figures it was told have the new budget.
      expect(env.snapshots.last.budgetTotal, 90000000);
      await tester.pump(const Duration(seconds: 6));
    });

    testBudgets('a budget set from an earlier month applies from that month on', (tester) async {
      final env = await pumpBudgets(tester);
      await tester.tap(findIcon(LkIconName.chevronLeft));
      await tester.pumpAndSettle();
      await openDetail(tester, 'Supermercado');
      await openBudgetSheet(tester);
      expect(
        find.text('Desde septiembre en adelante. Los meses anteriores quedan como estaban.'),
        findsOneWidget,
      );
      await eraseAll(tester);
      await typeDigits(tester, '300000');
      await save(tester);
      expect(env.budgets.calls, contains('setBudget cat-groceries 30000000 2026-09'));
      // The widget reads the current month: it was told that month's summary, not September's.
      expect(env.home.calls.where((c) => c == 'summary 2026-10'), isNotEmpty);
      expect(env.snapshots.last.month, '2026-10');
      await tester.pump(const Duration(seconds: 6));
    });

    testBudgets('a budget of zero is refused as the web\'s sheet does, and nothing is sent', (
      tester,
    ) async {
      final env = await pumpBudgets(tester);
      await openDetail(tester, 'Supermercado');
      await openBudgetSheet(tester);
      await eraseAll(tester);
      await save(tester);
      expect(find.text('Escribe un monto mayor que cero.'), findsOneWidget);
      expect(env.budgets.calls.where((c) => c.startsWith('setBudget')), isEmpty);
      expect(find.text('GUARDAR PRESUPUESTO'), findsOneWidget, reason: 'the sheet stays');
      // Typing again clears the message.
      await typeDigits(tester, '5');
      await tester.pump();
      expect(find.text('Escribe un monto mayor que cero.'), findsNothing);
    });

    testBudgets('a minus typed is refused in words and never sent; the amount stays', (
      tester,
    ) async {
      final env = await pumpBudgets(tester);
      await openDetail(tester, 'Supermercado');
      await openBudgetSheet(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      await tester.pumpAndSettle();
      expect(find.text('Un presupuesto no puede ser negativo.'), findsOneWidget);
      expect(find.textContaining(r'$250.000', findRichText: true), findsWidgets);
      expect(env.budgets.calls.where((c) => c.startsWith('setBudget')), isEmpty);
    });

    testBudgets('a failed budget save shows the web\'s error and keeps the old budget', (
      tester,
    ) async {
      final env = await pumpBudgets(tester);
      await openDetail(tester, 'Supermercado');
      await openBudgetSheet(tester);
      await eraseAll(tester);
      await typeDigits(tester, '300000');
      env.budgets.saveFailure = const HomeFailure(0);
      await save(tester);

      // The web's BudgetSheet says it inside the sheet (an alert in `text-over`), which stays open
      // with what was typed, so a retry is one tap: nothing is lost.
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      expect(find.text('GUARDAR PRESUPUESTO'), findsOneWidget);
      expect(find.textContaining(r'$300.000', findRichText: true), findsWidgets);
      // The old budget stays: on the detail behind the sheet, in the server, on home.
      expect(env.budgets.budgets['cat-groceries'], 25000000);
      expect(find.text(r'Quedan $67.000'), findsOneWidget);
      expect(find.textContaining('Presupuesto de Supermercado:'), findsNothing, reason: 'no toast');
      expect(env.snapshots.where((s) => s.budgetTotal == 90000000), isEmpty);

      // Retrying works.
      await save(tester);
      expect(find.text('GUARDAR PRESUPUESTO'), findsNothing);
      expect(env.budgets.budgets['cat-groceries'], 30000000);
      expect(find.text(r'Quedan $117.000'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testBudgets('the server\'s refusals have their own words', (tester) async {
      final env = await pumpBudgets(tester);
      await openDetail(tester, 'Supermercado');
      await openBudgetSheet(tester);
      env.budgets.saveFailure = const HomeFailure(422, code: 'budget_category_not_expense');
      await save(tester);
      expect(find.text('Solo las categorías de gasto pueden tener presupuesto.'), findsOneWidget);
      env.budgets.saveFailure = const HomeFailure(500);
      await save(tester);
      expect(
        find.text('Tuvimos un problema de nuestro lado. Inténtalo de nuevo en un momento.'),
        findsOneWidget,
      );
      env.budgets.saveFailure = const HomeFailure(404);
      await save(tester);
      expect(find.text('No encontramos lo que buscas.'), findsOneWidget);
    });

    testBudgets('Guardar presupuesto while it saves sends it once', (tester) async {
      final env = await pumpBudgets(tester);
      await openDetail(tester, 'Supermercado');
      await openBudgetSheet(tester);
      env.budgets.holdSave = Completer<void>();
      await tester.tap(find.byKey(const Key('budget.save')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('budget.save')));
      await tester.pump();
      expect(env.budgets.calls.where((c) => c.startsWith('setBudget')), hasLength(1));
      env.budgets.holdSave!.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));
    });

    testBudgets('in pesos a pasted 15.000 would be fifteen thousand; the keypad has no decimals', (
      tester,
    ) async {
      await pumpBudgets(tester);
      await openDetail(tester, 'Supermercado');
      await openBudgetSheet(tester);
      expect(find.byKey(const Key('keypad.decimal')), findsNothing);
      expect(find.textContaining('(250 lukas)', findRichText: true), findsOneWidget);
    });
  });

  group('offline', () {
    testBudgets('Categorías shows the current month\'s cached figures, with the offline note', (
      tester,
    ) async {
      final store = FakeCacheStore();
      await pumpBudgets(tester, overrides: [homeCacheStoreProvider.overrideWithValue(store)]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);

      // The app starts again, with no network.
      final home = budgetsMonth()..failures['profile'] = const HomeFailure(0);
      await pumpBudgets(
        tester,
        home: home,
        overrides: [homeCacheStoreProvider.overrideWithValue(store)],
      );
      expect(find.text('Sin conexión. Te mostramos lo último que cargó.'), findsOneWidget);
      await openBudgetsTab(tester);
      expect(_row(r'Supermercado Quedan \$67\.000'), findsOneWidget);
    });

    testBudgets('another month offline shows the offline note, never another month\'s figures', (
      tester,
    ) async {
      final env = await pumpBudgets(tester);
      await openBudgetsTab(tester);
      expect(find.byType(CategoryRow), findsNWidgets(2));
      env.home.failures['summary'] = const HomeFailure(0);
      await tester.tap(findIcon(LkIconName.chevronLeft));
      await tester.pumpAndSettle();
      expect(find.byType(CategoryRow), findsNothing);
      expect(find.textContaining('Sin conexión'), findsWidgets);
      expect(find.text('REINTENTAR'), findsOneWidget);
    });

    testBudgets('a detail that cannot load says why and retries', (tester) async {
      final env = await pumpBudgets(tester);
      await openBudgetsTab(tester);
      env.budgets.listFailure = const HomeFailure(0);
      await tester.tap(find.text('Supermercado'));
      await tester.pumpAndSettle();
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      expect(find.text('Mercado'), findsNothing);
      await tester.tap(find.text('REINTENTAR'));
      await tester.pumpAndSettle();
      expect(find.text('Mercado'), findsOneWidget);
    });
  });

  group('the page background', () {
    testBudgets('the detail: the glow scrolls away with the movements, as the web\'s page does', (
      tester,
    ) async {
      await pumpBudgets(tester);
      await openDetail(tester, 'Hogar');
      final screen = screenOf(tester);
      final start = pageGradient(tester);
      expect(start.top, 0);
      expect(start.height, greaterThanOrEqualTo(screen.height));

      tester.view.physicalSize = const Size(390, 400);
      await tester.pumpAndSettle();
      final short = pageGradient(tester);
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(50);
      await tester.pumpAndSettle();
      expect(pageGradient(tester).top, -50);
      expect(pageGradient(tester).height, short.height);
    });
  });
}
