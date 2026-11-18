import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/add/add_repository.dart';
import 'package:wambito/api/gen/wambito_api.dart' show Transaction;
import 'package:wambito/budgets/budgets_repository.dart';
import 'package:wambito/budgets/category_detail_controller.dart';
import 'package:wambito/budgets/category_detail_screen.dart';
import 'package:wambito/home/home_cache.dart';
import 'package:wambito/home/home_controller.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/ui/transaction_row.dart';

import '../add/fakes.dart';
import '../home/fakes.dart';
import '../home/fixtures.dart';
import 'budgets_test.dart' show openDetail, pumpBudgets, testBudgets;
import 'fakes.dart';

/// What the detail does with its movements: those added from it, paging, delete with Deshacer, pay.

final _now = DateTime.utc(2026, 10, 22, 15);

Future<void> settle() => Future<void>.delayed(Duration.zero);

Future<void> settleAll() async {
  for (var i = 0; i < 6; i++) {
    await settle();
  }
}

Future<void> swipeLeft(WidgetTester tester, Finder row) async {
  await tester.timedDrag(row, const Offset(-300, 0), const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.text('BORRAR'));
  await tester.pumpAndSettle();
}

Future<void> typeAmount(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.byKey(Key('keypad.$digit')));
    await tester.pump();
  }
}

FakeHomeRepository monthWithNewCategory() {
  final home = budgetsMonth();
  home.categoryList.add(
    category('cat-new', 'Mascotas', icon: '🐶').rebuild((b) => b.sortOrder = 3),
  );
  return home;
}

void main() {
  group('a movement added from the detail', () {
    testBudgets('from the ＋: the row is on the detail and the bar followed', (tester) async {
      final home = budgetsMonth();
      final add = FakeAddRepository(home);
      await pumpBudgets(
        tester,
        home: home,
        location: '/categories/cat-groceries',
        overrides: [addRepositoryProvider.overrideWithValue(add)],
      );
      expect(find.text(r'Quedan $67.000'), findsOneWidget);
      expect(find.text('Café'), findsNothing);

      await tester.tap(find.byKey(const Key('home.add')));
      await tester.pumpAndSettle();
      await typeAmount(tester, '5000');
      await tester.enterText(find.byKey(const Key('add.name')), 'Café');
      await tester.tap(find.byKey(const Key('category.cat-groceries')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('add.save')));
      await tester.pumpAndSettle();

      expect(find.text('Café'), findsOneWidget, reason: 'the new row, on the detail');
      expect(find.text(r'Quedan $62.000'), findsOneWidget, reason: '67.000 less the 5.000 spent');
      expect(find.text(r'Gastado $188.000 de $250.000'), findsOneWidget);
      await tester.pump(const Duration(seconds: 11));
    });

    testBudgets(
      'from the empty month\'s button: the category is preselected, and the list and bar fill',
      (tester) async {
        final home = monthWithNewCategory();
        final budgets = FakeBudgetsRepository(
          home,
          budgets: {'cat-groceries': 25000000, 'cat-new': 10000000},
        );
        final add = FakeAddRepository(home);
        await pumpBudgets(
          tester,
          home: home,
          budgets: budgets,
          location: '/categories/cat-new',
          overrides: [addRepositoryProvider.overrideWithValue(add)],
        );
        expect(find.text('No hay movimientos de Mascotas en octubre.'), findsOneWidget);
        expect(find.text(r'Quedan $100.000'), findsOneWidget);

        await tester.tap(find.text('AGREGAR GASTO'));
        await tester.pumpAndSettle();
        await typeAmount(tester, '4000');
        await tester.enterText(find.byKey(const Key('add.name')), 'Pienso');
        await tester.tap(find.byKey(const Key('add.save')));
        await tester.pumpAndSettle();

        expect(add.calls.where((c) => c.startsWith('create')).single, endsWith('Pienso -400000'));
        expect(find.text('Pienso'), findsOneWidget);
        expect(find.text('No hay movimientos de Mascotas en octubre.'), findsNothing);
        expect(find.text(r'Quedan $96.000'), findsOneWidget);
        await tester.pump(const Duration(seconds: 11));
      },
    );
  });

  group('paging, delete with Deshacer and pay on the detail', () {
    FakeHomeRepository manyGroceries({int pageSize = 2}) {
      final home = budgetsMonth()..pageSize = pageSize;
      for (var i = 1; i <= 4; i++) {
        home.items.add(tx('g$i', '2026-10-0$i', -100000 * i, name: 'Compra $i'));
      }
      // Newest first, as the API answers.
      home.items.sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
      return home;
    }

    testBudgets('Ver más brings the next page below the rows, in order', (tester) async {
      final home = manyGroceries();
      final env = await pumpBudgets(tester, home: home, location: '/categories/cat-groceries');
      // Six movements of the category (two from the month's data, four added): two per page.
      expect(find.byType(TransactionRow), findsNWidgets(2));
      final more = find.text('VER MÁS MOVIMIENTOS');
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.byType(TransactionRow), findsNWidgets(4));
      expect(
        env.budgets.calls.where((c) => c.startsWith('transactions 2026-10 cat-groceries 2')),
        isNotEmpty,
      );
      final tops = [
        for (final row in tester.widgetList<TransactionRow>(find.byType(TransactionRow))) row.name,
      ];
      expect(tops, ['Mercado', 'Frutas', 'Compra 4', 'Compra 3']);
    });

    testBudgets('swipe left deletes, Deshacer brings the same row back', (tester) async {
      final home = budgetsMonth();
      final env = await pumpBudgets(tester, home: home, location: '/categories/cat-groceries');
      await swipeLeft(tester, find.text('Frutas'));
      expect(find.text('Frutas'), findsNothing);
      expect(find.text('Eliminado: Frutas'), findsOneWidget);
      expect(home.calls, contains('delete fruit'));

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(home.calls, contains('restore fruit'));
      expect(find.text('Frutas'), findsOneWidget);
      expect(env.budgets.calls, isNotEmpty);
      await tester.pump(const Duration(seconds: 11));
    });

    testBudgets('Deshacer still brings the row back after the person left the detail', (
      tester,
    ) async {
      final home = budgetsMonth();
      final env = await pumpBudgets(tester, home: home);
      await openDetail(tester, 'Supermercado');
      await swipeLeft(tester, find.text('Frutas'));
      expect(find.text('Eliminado: Frutas'), findsOneWidget);
      expect(home.calls, contains('delete fruit'));

      // Back on home, the toast (it sits above the router) is still there.
      env.settings.router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(CategoryDetailScreen), findsNothing);
      expect(find.text('Eliminado: Frutas'), findsOneWidget);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(home.calls, contains('restore fruit'), reason: 'the server has it back');
      expect(find.text('De vuelta: Frutas'), findsOneWidget);

      // And it is in its month: home's Movimientos lists it again.
      await tester.tap(find.text('Movimientos'));
      await tester.pumpAndSettle();
      expect(find.text('Frutas'), findsOneWidget);
      await tester.pump(const Duration(seconds: 11));
    });

    testBudgets('a delete the server refuses puts the row back and says so', (tester) async {
      final home = budgetsMonth();
      await pumpBudgets(tester, home: home, location: '/categories/cat-groceries');
      home.deleteFailure = const HomeFailure(500);
      await swipeLeft(tester, find.text('Frutas'));
      expect(find.text('Frutas'), findsOneWidget);
      expect(find.text('Algo salió mal. Inténtalo de nuevo en un momento.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 11));
    });

    testBudgets('the badge of a pending movement pays it', (tester) async {
      final home = budgetsMonth();
      await pumpBudgets(tester, home: home, location: '/categories/cat-home');
      expect(find.text('PENDIENTE'), findsOneWidget);
      await tester.tap(find.text('PENDIENTE'));
      await tester.pumpAndSettle();
      expect(home.calls, contains('markPaid rent'));
      expect(find.text('PENDIENTE'), findsNothing);
      expect(find.text('PAGADO'), findsOneWidget);
      await tester.pump(const Duration(seconds: 11));
    });

    testBudgets('a payment the server refuses puts the badge back to pending', (tester) async {
      final home = budgetsMonth();
      await pumpBudgets(tester, home: home, location: '/categories/cat-home');
      home.failures['markPaid'] = const HomeFailure(500);
      await tester.tap(find.text('PENDIENTE'));
      await tester.pumpAndSettle();
      expect(find.text('PENDIENTE'), findsOneWidget);
      expect(find.text('Algo salió mal. Inténtalo de nuevo en un momento.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 11));
    });
  });

  group('the detail\'s list keeps home\'s guards', () {
    Future<(ProviderContainer, FakeHomeRepository, FakeBudgetsRepository)> detail() async {
      final home = budgetsMonth()..pageSize = 1;
      home.items.addAll([
        tx('g1', '2026-10-03', -100000, name: 'Compra 1'),
        tx('g2', '2026-10-02', -100000, name: 'Compra 2'),
      ]);
      home.items.sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
      final budgets = budgetsFor(home);
      final container = ProviderContainer(
        overrides: [
          homeRepositoryProvider.overrideWithValue(home),
          budgetsRepositoryProvider.overrideWithValue(budgets),
          homeCacheProvider.overrideWithValue(HomeCache(FakeCacheStore(), token: 't1')),
          clockProvider.overrideWithValue(() => _now),
          widgetSnapshotWriterProvider.overrideWithValue(
            (summary, {required currency, required locale, required timezone}) async {},
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(homeProvider, (_, _) {});
      container.listen(categoryDetailProvider('cat-groceries'), (_, _) {});
      await settleAll();
      await container.read(categoryDetailProvider('cat-groceries').notifier).showMonth('2026-10');
      return (container, home, budgets);
    }

    CategoryDetailState read(ProviderContainer c) =>
        c.read(categoryDetailProvider('cat-groceries'));
    CategoryDetailController controller(ProviderContainer c) =>
        c.read(categoryDetailProvider('cat-groceries').notifier);

    /// Deshacer: home's controller brings it back, and the detail shows it where it belongs.
    Future<void> bringBack(ProviderContainer c, Transaction tx) async {
      await c.read(homeProvider.notifier).restore(tx);
      controller(c).showRestored(tx);
    }

    test('a page that lands after another month was chosen is dropped, rows and cursor', () async {
      final (container, home, _) = await detail();
      expect(read(container).items!.map((t) => t.id), ['market']);
      final cursor = read(container).nextCursor;
      expect(cursor, isNotNull);

      // Page two is slow; September is chosen, then October again while it is on its way.
      final gate = Completer<void>();
      home.holdPage = gate;
      final paging = controller(container).loadMore();
      await settle();
      await controller(container).showMonth('2026-09');
      await controller(container).showMonth('2026-10');
      home.holdPage = null;
      gate.complete();
      await paging;
      await settleAll();

      final state = read(container);
      expect(state.items!.map((t) => t.id), ['market'], reason: 'the old page was dropped');
      expect(state.nextCursor, cursor, reason: 'and the cursor is the reloaded list\'s own');
      expect(state.loadingMore, isFalse);
    });

    test(
      'Deshacer in another month does not show the row, and it is there when its month is',
      () async {
        final (container, home, _) = await detail();
        final fruit = home.items.firstWhere((t) => t.id == 'fruit');
        await controller(container).loadMore();
        await controller(container).loadMore();
        expect(read(container).items!.map((t) => t.id), contains('fruit'));
        await controller(container).remove(fruit);

        await controller(container).showMonth('2026-09');
        await bringBack(container, fruit);
        expect(read(container).items, isEmpty, reason: 'a October row is not in September\'s list');
        expect(read(container).restored, isEmpty);

        await controller(container).showMonth('2026-10');
        await controller(container).loadMore();
        await controller(container).loadMore();
        expect(read(container).items!.map((t) => t.id), contains('fruit'));
      },
    );

    test('a restored row older than the last one loaded waits for the next page', () async {
      final (container, home, _) = await detail();
      // Page one is the market only; "fruit" (5 October) is older than it, with more pages to come.
      final fruit = home.items.firstWhere((t) => t.id == 'fruit');
      await controller(container).loadMore();
      await controller(container).remove(fruit);
      await bringBack(container, fruit);
      final state = read(container);
      expect(state.nextCursor, isNotNull);
      final ids = state.items!.map((t) => t.id).toList();
      final sorted = [...state.items!]..sort((a, b) => b.date.compareTo(a.date));
      expect(ids, sorted.map((t) => t.id).toList(), reason: 'still in the API\'s order');
      // Rows older than the end of what is loaded are not above rows of the next page.
      expect(ids.contains('fruit'), isFalse);
    });

    test('a failed delete puts the row back where it was', () async {
      final (container, home, _) = await detail();
      final market = read(container).items!.first;
      home.deleteFailure = const HomeFailure(500);
      await expectLater(controller(container).remove(market), throwsA(isA<HomeFailure>()));
      expect(read(container).items!.map((t) => t.id), ['market']);
    });
  });
}
