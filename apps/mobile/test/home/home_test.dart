import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/home/home_screen.dart' show HomeView;
import 'package:wambito/home/home_widgets.dart' show HomeTabsStrip;
import 'package:wambito/ui/segmented_control.dart';

import '../support/page_gradient.dart';
import 'fakes.dart';
import 'fixtures.dart';
import 'home_harness.dart';

/// A swipe: the finger down on [row], moved by [dx] over [ms] (a flick is fast).
Future<void> swipe(WidgetTester tester, Finder row, double dx, {int ms = 300}) async {
  await tester.timedDrag(row, Offset(dx, 0), Duration(milliseconds: ms));
  await tester.pumpAndSettle();
}

/// Takes home off the screen, and lets Riverpod drop its state, so no timer outlives the test (two
/// homes were shown in turn).
Future<void> leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
}

/// Lets the 10 s of an event line pass, so no timer outlives the test.
Future<void> endEvent(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 11));
  await tester.pumpAndSettle();
}

void main() {
  group('the month', () {
    testWidgets('home shows Te quedan with budgets and Gastado este mes without', (tester) async {
      await pumpHome(tester, monthWithBudgets());
      expect(find.text('Te quedan este mes'), findsOneWidget);
      expect(find.text('Gastado este mes'), findsNothing);
      // 2.000.000 of budget, 212.500 spent (the pending rent and the income do not count).
      expect(find.text(r'$1.787.500'), findsOneWidget);
      expect(find.text(r'Gastado $212.500'), findsOneWidget);
      expect(find.text(r'de $2.000.000'), findsOneWidget);
      expect(find.text('Octubre'), findsOneWidget);
    });

    testWidgets('without budgets it says what was spent, and that there are none', (tester) async {
      final repo = monthWithBudgets()..budgetTotal = 0;
      await pumpHome(tester, repo);
      expect(find.text('Gastado este mes'), findsOneWidget);
      expect(find.text('Te quedan este mes'), findsNothing);
      expect(find.text('Sin presupuestos todavía'), findsOneWidget);
      expect(find.text(r'$212.500'), findsOneWidget);
    });

    testWidgets('over the budgets it says Te pasaste', (tester) async {
      final repo = monthWithBudgets()..budgetTotal = 10000000;
      await pumpHome(tester, repo);
      expect(find.text('Te pasaste este mes'), findsOneWidget);
    });

    testWidgets('in English: the same figures with the code and the English copy', (tester) async {
      await pumpHome(tester, monthWithBudgets(), locale: const Locale('en'));
      expect(find.text('Left this month'), findsOneWidget);
      expect(find.text('October'), findsOneWidget);
      expect(find.text('TODAY · THU 22'), findsOneWidget);
      expect(find.text('Show more'), findsNothing);
    });

    testWidgets('writes the widget snapshot with the loaded summary', (tester) async {
      final harness = await pumpHome(tester, monthWithBudgets());
      expect(harness.snapshots, hasLength(1));
      expect(harness.snapshots.single.summary.month, '2026-10');
      expect(harness.snapshots.single.currency, 'COP');
    });
  });

  group('the movements', () {
    testWidgets('are listed by day: today first, then the past, the pending ones due last', (
      tester,
    ) async {
      await pumpHome(tester, monthWithBudgets(), size: tallPhone);
      expect(find.text('HOY · JUE 22'), findsOneWidget);
      expect(find.text('AYER · MIÉ 21'), findsOneWidget);
      expect(find.text('DOM 25 · PRÓXIMO'), findsOneWidget);
      double y(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(y('Café'), lessThan(y('Mercado')));
      expect(y('Mercado'), lessThan(y('Nómina')));
      expect(y('Nómina'), lessThan(y('Arriendo')));
      // Money: expenses with the real minus, income with a plus.
      expect(find.text('−\$4.500'), findsOneWidget);
      // The income, and the day's total (income only).
      expect(find.text(r'+$3.000.000'), findsNWidgets(2));
      expect(find.text('PENDIENTE'), findsOneWidget);
    });

    testWidgets('an empty month invites the first entry', (tester) async {
      await pumpHome(tester, FakeHomeRepository());
      expect(
        find.text('Aún no hay movimientos en Octubre. Toca ＋ y anota el primero.'),
        findsOneWidget,
      );
    });

    testWidgets('a list longer than one page shows Ver más movimientos and loads the rest', (
      tester,
    ) async {
      final repo = FakeHomeRepository(
        pageSize: 3,
        items: [
          for (var i = 9; i >= 1; i--) tx('t$i', '2026-10-0$i', -100000 * i, name: 'Gasto $i'),
        ],
      );
      await pumpHome(tester, repo, size: const Size(390, 1800));
      expect(find.text('Gasto 9'), findsOneWidget);
      expect(find.text('Gasto 7'), findsOneWidget);
      expect(find.text('Gasto 6'), findsNothing);
      expect(find.text('VER MÁS MOVIMIENTOS'), findsOneWidget);

      await tester.tap(find.text('VER MÁS MOVIMIENTOS'));
      await tester.pumpAndSettle();
      expect(find.text('Gasto 6'), findsOneWidget);
      expect(find.text('Gasto 4'), findsOneWidget);
      expect(find.text('Gasto 3'), findsNothing);
      expect(find.text('VER MÁS MOVIMIENTOS'), findsOneWidget);

      await tester.tap(find.text('VER MÁS MOVIMIENTOS'));
      await tester.pumpAndSettle();
      expect(find.text('Gasto 1'), findsOneWidget);
      expect(find.text('VER MÁS MOVIMIENTOS'), findsNothing);
      expect(repo.calls.where((c) => c.startsWith('transactions')), [
        'transactions 2026-10',
        'transactions 2026-10 3',
        'transactions 2026-10 6',
      ]);
    });

    testWidgets('a page that fails keeps the list and says so', (tester) async {
      final repo = FakeHomeRepository(
        pageSize: 1,
        items: [
          tx('a', '2026-10-02', -100, name: 'Uno'),
          tx('b', '2026-10-01', -100, name: 'Dos'),
        ],
      );
      await pumpHome(tester, repo);
      repo.failures['transactions'] = const HomeFailure(0);
      await tester.tap(find.text('VER MÁS MOVIMIENTOS'));
      await tester.pumpAndSettle();
      expect(find.text('Uno'), findsOneWidget);
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      expect(find.text('VER MÁS MOVIMIENTOS'), findsOneWidget);
    });

    testWidgets('the Movimientos tab sticks under the top while the list scrolls', (tester) async {
      final repo = FakeHomeRepository(
        items: [
          for (var i = 20; i >= 1; i--) tx('t$i', '2026-10-${i.toString().padLeft(2, '0')}', -100),
        ],
      );
      await pumpHome(tester, repo);
      final tab = find.text('Movimientos');
      expect(tab, findsOneWidget);
      final before = tester.getTopLeft(tab).dy;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tab, findsOneWidget);
      final after = tester.getTopLeft(tab).dy;
      expect(after, lessThan(before), reason: 'it moved up under the top…');
      expect(after, lessThan(60), reason: '…and stayed there');
    });
  });

  group('swipes', () {
    testWidgets('Deshacer shows as soon as the delete is done, not after the summary', (
      tester,
    ) async {
      final repo = monthWithBudgets();
      await pumpHome(tester, repo);
      // From now on the summary is slow (a bad connection).
      final gate = Completer<void>();
      repo.holdSummary = gate;

      await tester.timedDrag(
        find.text('Café'),
        const Offset(-250, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();
      expect(repo.deleted.map((t) => t.id), ['coffee']);
      expect(find.text('Eliminado: Café'), findsOneWidget);
      expect(find.text('Deshacer'), findsOneWidget);
      expect(find.text(r'Gastado $212.500'), findsOneWidget, reason: 'the summary has not arrived');

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text(r'Gastado $208.000'), findsOneWidget);
      expect(find.text('Deshacer'), findsOneWidget);
    });

    testWidgets('swipe left deletes and Deshacer within 8 s restores the same row', (tester) async {
      final repo = monthWithBudgets();
      await pumpHome(tester, repo);
      final top = tester.getTopLeft(find.text('Café')).dy;

      await swipe(tester, find.text('Café'), -250);
      expect(find.text('Café'), findsNothing);
      expect(repo.deleted.map((t) => t.id), ['coffee']);
      expect(find.text('Eliminado: Café'), findsOneWidget);
      // The summary follows: 4.500 less spent.
      expect(find.text(r'Gastado $208.000'), findsOneWidget);

      // Seven seconds in, Deshacer is still there.
      await tester.pump(const Duration(seconds: 7));
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('restore coffee'));
      expect(find.text('Café'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Café')).dy, top, reason: 'the same row, in its place');
      expect(find.text('De vuelta: Café'), findsOneWidget);
      expect(find.text(r'Gastado $212.500'), findsOneWidget);
      expect(repo.deleted, isEmpty);
    });

    testWidgets('after 8 s Deshacer is gone', (tester) async {
      final repo = monthWithBudgets();
      await pumpHome(tester, repo);
      await swipe(tester, find.text('Café'), -250);
      expect(find.text('Deshacer'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('Deshacer'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Deshacer'), findsNothing);
      expect(find.text('Café'), findsNothing);
    });

    testWidgets('a delete the server refuses brings the row back and says why', (tester) async {
      final repo = monthWithBudgets();
      await pumpHome(tester, repo);
      repo.failures['delete'] = const HomeFailure(500);
      await swipe(tester, find.text('Café'), -250);
      expect(find.text('Café'), findsOneWidget);
      expect(find.text('Algo salió mal. Inténtalo de nuevo en un momento.'), findsOneWidget);
      expect(find.text('Deshacer'), findsNothing);
    });

    testWidgets('swipe right on a pending row marks it paid', (tester) async {
      final repo = monthWithBudgets();
      await pumpHome(tester, repo, size: tallPhone);
      expect(find.text('PENDIENTE'), findsOneWidget);

      await swipe(tester, find.text('Arriendo'), 250);
      expect(repo.calls, contains('markPaid rent'));
      expect(repo.items.firstWhere((t) => t.id == 'rent').status, TransactionStatusEnum.paid);
      expect(find.text('PENDIENTE'), findsNothing);
      expect(find.text('PAGADO'), findsOneWidget);
      expect(find.textContaining('Pagado: Arriendo'), findsOneWidget);
      // The row is where it was: a swipe is not a move.
      expect(find.text('Arriendo'), findsWidgets);
      await endEvent(tester);
    });

    testWidgets('tapping the Pendiente badge pays it too', (tester) async {
      final repo = monthWithBudgets();
      await pumpHome(tester, repo, size: tallPhone);
      await tester.tap(find.text('PENDIENTE'));
      await tester.pumpAndSettle();
      expect(repo.calls.where((c) => c.startsWith('markPaid')), ['markPaid rent']);
      expect(find.text('PAGADO'), findsOneWidget);
      await endEvent(tester);
    });

    testWidgets('a payment the server refuses puts the badge back to Pendiente', (tester) async {
      final repo = monthWithBudgets();
      await pumpHome(tester, repo, size: tallPhone);
      repo.failures['markPaid'] = const HomeFailure(0);
      await tester.tap(find.text('PENDIENTE'));
      await tester.pumpAndSettle();
      expect(find.text('PENDIENTE'), findsOneWidget);
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
    });

    testWidgets('swipe right on a paid row edits it, when there is an editor', (tester) async {
      final harness = await pumpHome(tester, monthWithBudgets(), withEdit: true);
      await swipe(tester, find.text('Café'), 250);
      expect(harness.edited.map((t) => t.id), ['coffee']);
      expect(find.text('Café'), findsOneWidget);
    });

    testWidgets('a tap on a row opens it for editing', (tester) async {
      final harness = await pumpHome(tester, monthWithBudgets(), withEdit: true);
      await tester.tap(find.text('Almuerzo'));
      await tester.pumpAndSettle();
      expect(harness.edited.map((t) => t.id), ['lunch']);
    });

    testWidgets('a vertical drag scrolls and never swipes a row (axis lock)', (tester) async {
      final repo = monthWithBudgets();
      await pumpHome(tester, repo);
      // Far enough left to delete a row, but more up than left: the list's.
      await tester.drag(find.text('Café'), const Offset(-150, -160));
      await tester.pumpAndSettle();
      // A perfect diagonal also scrolls.
      await tester.drag(find.text('Almuerzo'), const Offset(-150, -150));
      await tester.pumpAndSettle();
      expect(repo.calls.where((c) => c.startsWith('delete')), isEmpty);
      expect(find.text('BORRAR'), findsNothing);
    });

    testWidgets('a short swipe leaves the action open; only one row is open at a time', (
      tester,
    ) async {
      final repo = monthWithBudgets();
      await pumpHome(tester, repo);

      await swipe(tester, find.text('Café'), -100);
      expect(find.text('BORRAR'), findsOneWidget);
      expect(repo.calls.where((c) => c.startsWith('delete')), isEmpty);
      final open = tester.getTopLeft(find.text('Café')).dx;

      // Another row opens: the first closes.
      await swipe(tester, find.text('Almuerzo'), -100);
      expect(find.text('BORRAR'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Café')).dx, greaterThan(open));

      // A tap anywhere else closes it.
      await tester.tap(find.text('Octubre'));
      await tester.pumpAndSettle();
      expect(find.text('BORRAR'), findsNothing);
    });

    testWidgets('a tap on an open row closes it instead of opening it', (tester) async {
      final harness = await pumpHome(tester, monthWithBudgets(), withEdit: true);
      await swipe(tester, find.text('Café'), -100);
      expect(find.text('BORRAR'), findsOneWidget);
      await tester.tap(find.text('Café'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('BORRAR'), findsNothing);
      expect(harness.edited, isEmpty);
    });

    testWidgets('tapping the opened action runs it', (tester) async {
      final repo = monthWithBudgets();
      await pumpHome(tester, repo);
      await swipe(tester, find.text('Café'), -100);
      await tester.tap(find.text('BORRAR'));
      await tester.pumpAndSettle();
      expect(repo.deleted.map((t) => t.id), ['coffee']);
      expect(find.text('Café'), findsNothing);
    });

    testWidgets('a flick deletes even after a short distance', (tester) async {
      final repo = monthWithBudgets();
      await pumpHome(tester, repo);
      await swipe(tester, find.text('Café'), -60, ms: 40);
      expect(repo.deleted.map((t) => t.id), ['coffee']);
    });

    testWidgets('a swipe that is too small closes again', (tester) async {
      final repo = monthWithBudgets();
      await pumpHome(tester, repo);
      final at = tester.getTopLeft(find.text('Café')).dx;
      await swipe(tester, find.text('Café'), -20);
      expect(tester.getTopLeft(find.text('Café')).dx, at);
      expect(find.text('BORRAR'), findsNothing);
    });

    testWidgets('with "remove animations" a deleted row just fades away', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final repo = monthWithBudgets();
      await pumpHome(tester, repo);
      await swipe(tester, find.text('Café'), -250);
      expect(find.text('Café'), findsNothing);
      expect(repo.deleted.map((t) => t.id), ['coffee']);
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(find.text('Café'), findsOneWidget);
    });
  });

  group('Wambi', () {
    testWidgets('says the month\'s line: what is left and the days to go', (tester) async {
      await pumpHome(tester, monthWithBudgets());
      expect(find.textContaining('Vas muy bien: te quedan'), findsOneWidget);
      expect(find.textContaining('10 días'), findsOneWidget);
    });

    testWidgets('without budgets he talks about what was spent', (tester) async {
      await pumpHome(tester, monthWithBudgets()..budgetTotal = 0);
      expect(find.textContaining('Este mes llevas'), findsOneWidget);
    });

    testWidgets('the event line names the movement and returns to the month\'s line after 10 s', (
      tester,
    ) async {
      await pumpHome(tester, monthWithBudgets(), size: tallPhone);
      expect(find.textContaining('Vas muy bien'), findsOneWidget);

      await swipe(tester, find.text('Arriendo'), 250);
      expect(find.textContaining('«Arriendo»'), findsOneWidget);
      expect(find.textContaining('Pagaste «Arriendo»: \$500.000'), findsOneWidget);
      expect(find.textContaining('Vas muy bien'), findsNothing);

      await tester.pump(const Duration(seconds: 9));
      expect(find.textContaining('Pagaste «Arriendo»'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pagaste «Arriendo»'), findsNothing);
      expect(find.textContaining('Vas muy bien'), findsOneWidget);
    });

    testWidgets('in English the event line is English too', (tester) async {
      await pumpHome(tester, monthWithBudgets(), locale: const Locale('en'), size: tallPhone);
      await swipe(tester, find.text('Arriendo'), 250);
      expect(find.textContaining('You paid “Arriendo”: COP\u00a0500,000'), findsOneWidget);
      await endEvent(tester);
    });
  });

  group('the header and the months', () {
    FakeHomeRepository threeMonths() => FakeHomeRepository(
      budgetTotal: 200000000,
      categoryList: [category('cat-groceries', 'Supermercado', icon: '🛒')],
      items: [
        tx('coffee', '2026-10-22', -450000, name: 'Café'),
        tx('sept', '2026-09-14', -3000000, name: 'Zapatos'),
        tx('sept2', '2026-09-03', -1000000, name: 'Libro'),
        tx('july', '2026-07-09', -7000000, name: 'Vuelo'),
      ],
    );

    testWidgets('the header shows the Wambito wordmark and the face button', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHome(tester, monthWithBudgets());
      expect(find.text('Wambito'), findsOneWidget, reason: 'the wordmark');
      final face = find.byKey(const Key('home.account'));
      expect(face, findsOneWidget);
      expect(find.text('🙂'), findsOneWidget);
      expect(tester.getSemantics(face).label, 'Tu cuenta');
      // 44px round button, as `.lk-avatar`.
      expect(tester.getSize(face), const Size(44, 44));
      // Under 400px the wordmark and the face share the first row, and the month has its own.
      expect(tester.getCenter(find.text('Wambito')).dy, closeTo(tester.getCenter(face).dy, 1));
      expect(tester.getCenter(find.text('Octubre')).dy, greaterThan(tester.getCenter(face).dy));
      handle.dispose();
    });

    testWidgets('the face button opens the menu, and a tap anywhere else closes it', (
      tester,
    ) async {
      await pumpHome(tester, monthWithBudgets(), withMenu: true);
      expect(find.byKey(const Key('menu.entry')), findsNothing);
      await tester.tap(find.byKey(const Key('home.account')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu.entry')), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('menu.entry'))).height, greaterThanOrEqualTo(44));

      await tester.tap(find.text('Te quedan este mes'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu.entry')), findsNothing);

      // The button toggles it, and an entry closes it.
      await tester.tap(find.byKey(const Key('home.account')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home.account')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu.entry')), findsNothing);
      await tester.tap(find.byKey(const Key('home.account')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu.entry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu.entry')), findsNothing);
    });

    testWidgets('‹ moves to the previous month and loads its summary and movements', (
      tester,
    ) async {
      final repo = threeMonths();
      await pumpHome(tester, repo);
      expect(find.text('Octubre'), findsOneWidget);
      expect(find.text('Café'), findsOneWidget);

      await tester.tap(find.text('‹'));
      await tester.pumpAndSettle();
      expect(find.text('Septiembre'), findsOneWidget);
      expect(find.text('Octubre'), findsNothing);
      expect(repo.calls, containsAll(['summary 2026-09', 'transactions 2026-09']));
      // Its movements, not October's; and its own figures, said about September.
      expect(find.text('Zapatos'), findsOneWidget);
      expect(find.text('Libro'), findsOneWidget);
      expect(find.text('Café'), findsNothing);
      expect(find.text('Te quedaron en septiembre'), findsOneWidget);
      expect(find.text('Te quedan este mes'), findsNothing);
      expect(find.text(r'Gastado $40.000'), findsOneWidget);
      // No day of September is "Hoy", and none is "Ayer".
      expect(find.textContaining('HOY'), findsNothing);
      // Wambi talks about the month that closed.
      expect(find.textContaining('septiembre'), findsWidgets);

      await tester.tap(find.text('›'));
      await tester.pumpAndSettle();
      expect(find.text('Octubre'), findsOneWidget);
      expect(find.text('Café'), findsOneWidget);
      expect(find.text('Te quedan este mes'), findsOneWidget);
    });

    testWidgets('the current month has no later month: › is disabled, as on the web', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final repo = threeMonths();
      await pumpHome(tester, repo);
      final next = find.bySemanticsLabel('Mes siguiente');
      expect(next, findsOneWidget);
      expect(tester.getSemantics(next).flagsCollection.isEnabled, Tristate.isFalse);
      final before = repo.calls.length;
      await tester.tap(find.text('›'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(repo.calls.length, before, reason: 'nothing was asked');
      expect(find.text('Octubre'), findsOneWidget);
      // ‹ is there and enabled.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Mes anterior')).flagsCollection.isEnabled,
        Tristate.isTrue,
      );
      handle.dispose();
    });

    testWidgets('a month shows its year when it is not the current year', (tester) async {
      final repo = FakeHomeRepository(items: [tx('old', '2025-12-24', -100, name: 'Regalo')]);
      await pumpHome(tester, repo, initialMonth: '2025-12');
      expect(find.text('Diciembre 2025'), findsOneWidget);
      expect(find.text('Regalo'), findsOneWidget);
    });

    testWidgets('a month with no movements shows the web\'s empty state', (tester) async {
      final repo = threeMonths();
      await pumpHome(tester, repo);
      await tester.tap(find.text('‹'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('‹'));
      await tester.pumpAndSettle();
      expect(find.text('Agosto'), findsOneWidget);
      expect(
        find.text('Aún no hay movimientos en Agosto. Toca ＋ y anota el primero.'),
        findsOneWidget,
      );
      // The web's button under it ("Agregar gasto"), a secondary one.
      expect(find.text('AGREGAR GASTO'), findsOneWidget);
      expect(find.text('Te quedaron en agosto'), findsOneWidget);
    });

    testWidgets('moving months offline shows the offline note and never another month\'s figures', (
      tester,
    ) async {
      final repo = threeMonths();
      await pumpHome(tester, repo);
      expect(find.text('Café'), findsOneWidget);

      repo.failures['summary'] = const HomeFailure(0);
      await tester.tap(find.text('‹'));
      await tester.pumpAndSettle();

      expect(find.text('Septiembre'), findsOneWidget, reason: 'the month asked for');
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      // None of October's figures under September's name.
      expect(find.text('Café'), findsNothing);
      expect(find.textContaining('Te quedan'), findsNothing);
      expect(find.textContaining('Te quedaron'), findsNothing);
      expect(find.textContaining('Gastado'), findsNothing);
      expect(find.text(r'$1.787.500'), findsNothing);
      expect(
        find.textContaining('Vas muy bien'),
        findsNothing,
        reason: 'nor Wambi\' line about it',
      );

      // Back online, a retry brings the month.
      await tester.tap(find.text('REINTENTAR'));
      await tester.pumpAndSettle();
      expect(find.text('Zapatos'), findsOneWidget);
      expect(find.text('Te quedaron en septiembre'), findsOneWidget);
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsNothing);
    });

    testWidgets('while another month loads, no figures of the month before show', (tester) async {
      final repo = threeMonths();
      await pumpHome(tester, repo);
      final gate = Completer<void>();
      repo.holdSummary = gate;
      await tester.tap(find.text('‹'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Septiembre'), findsOneWidget);
      expect(find.text('Café'), findsNothing);
      expect(find.textContaining('Te quedan'), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Zapatos'), findsOneWidget);
    });

    testWidgets(
      'Deshacer after moving to another month brings the row back to its own month only',
      (tester) async {
        final repo = threeMonths();
        await pumpHome(tester, repo);
        await tester.tap(find.text('‹'));
        await tester.pumpAndSettle();
        expect(find.text('Septiembre'), findsOneWidget);
        await swipe(tester, find.text('Zapatos'), -250);
        expect(find.text('Eliminado: Zapatos'), findsOneWidget);

        // The toast outlives the month: go on to August, and press Deshacer there.
        await tester.tap(find.text('‹'));
        await tester.pumpAndSettle();
        expect(find.text('Agosto'), findsOneWidget);
        await tester.tap(find.text('Deshacer'));
        await tester.pumpAndSettle();
        expect(repo.calls, contains('restore sept'));
        expect(find.text('Zapatos'), findsNothing, reason: 'not a September row in August');
        expect(find.textContaining('Aún no hay movimientos en Agosto'), findsOneWidget);

        await tester.tap(find.text('›'));
        await tester.pumpAndSettle();
        expect(find.text('Septiembre'), findsOneWidget);
        expect(find.text('Zapatos'), findsOneWidget);
      },
    );

    testWidgets('?month= opens home on that month', (tester) async {
      final repo = threeMonths();
      await pumpHome(tester, repo, initialMonth: '2026-09');
      expect(find.text('Septiembre'), findsOneWidget);
      expect(find.text('Zapatos'), findsOneWidget);
      expect(find.text('Café'), findsNothing);
    });

    testWidgets('a ?month= that is not a month, or is in the future, opens the current one', (
      tester,
    ) async {
      await pumpHome(tester, threeMonths(), initialMonth: 'soon');
      expect(find.text('Octubre'), findsOneWidget);
      expect(find.text('Café'), findsOneWidget);
      await leave(tester);
      await pumpHome(tester, threeMonths(), initialMonth: '2027-02');
      expect(find.text('Octubre'), findsOneWidget);
      expect(find.text('Café'), findsOneWidget);
    });

    testWidgets('a payment made in October is not talked about on September\'s screen', (
      tester,
    ) async {
      final repo = monthWithBudgets();
      await pumpHome(tester, repo, size: tallPhone);
      await swipe(tester, find.text('Arriendo'), 250);
      expect(find.textContaining('Pagaste «Arriendo»'), findsOneWidget);
      await tester.tap(find.text('‹'));
      await tester.pumpAndSettle();
      expect(find.text('Septiembre'), findsOneWidget);
      expect(find.textContaining('Pagaste «Arriendo»'), findsNothing);
      await endEvent(tester);
    });
  });

  group('the tabs, the cards and the bottom bar', () {
    testWidgets('Movimientos | Categorías are the web\'s tabs, Movimientos first', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHome(tester, monthWithBudgets());
      expect(find.text('Movimientos'), findsOneWidget);
      expect(find.text('Categorías'), findsOneWidget);
      expect(find.bySemanticsLabel('Vista'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Movimientos')).dx,
        lessThan(tester.getTopLeft(find.text('Categorías')).dx),
      );
      expect(find.text('Café'), findsOneWidget);

      // Categorías shows the categories, not the movements.
      await tester.tap(find.text('Categorías'));
      await tester.pumpAndSettle();
      expect(find.text('Café'), findsNothing);
      await tester.tap(find.text('Movimientos'));
      await tester.pumpAndSettle();
      expect(find.text('Café'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the tabs sit on the page\'s own background: no darker band around them', (
      tester,
    ) async {
      await pumpHome(tester, monthWithBudgets());
      final strip = find.byType(HomeTabsStrip);
      expect(strip, findsOneWidget);
      // Nothing between the strip and the control paints a fill of its own (the page's gradient,
      // painted by the shell behind the whole screen, is what shows around the tabs).
      final fills = find.descendant(
        of: strip,
        matching: find.ancestor(
          of: find.byType(SegmentedControl<HomeView>),
          matching: find.byWidgetPredicate(
            (w) => w is ColoredBox || (w is DecoratedBox && w.decoration is BoxDecoration),
          ),
        ),
      );
      expect(fills, findsNothing);
    });

    testWidgets('an account without budgets gets the web\'s card, which can be put away', (
      tester,
    ) async {
      final repo = monthWithBudgets()..budgetTotal = 0;
      await pumpHome(tester, repo);
      expect(find.text('Ponle presupuesto a tus categorías'), findsOneWidget);
      expect(find.text('IR A CATEGORÍAS'), findsOneWidget);

      await tester.tap(find.text('AHORA NO'));
      await tester.pumpAndSettle();
      expect(find.text('Ponle presupuesto a tus categorías'), findsNothing);
      await leave(tester);
    });

    testWidgets('no card once a category has a budget', (tester) async {
      final repo = FakeHomeRepository(
        categoryList: [category('cat-groceries', 'Supermercado', budget: 100000)],
        budgetTotal: 100000,
        items: [tx('a', '2026-10-22', -100)],
      );
      await pumpHome(tester, repo);
      expect(find.text('Ponle presupuesto a tus categorías'), findsNothing);
    });

    testWidgets('the card\'s button goes to Categorías', (tester) async {
      await pumpHome(tester, monthWithBudgets()..budgetTotal = 0);
      await tester.tap(find.text('IR A CATEGORÍAS'));
      await tester.pumpAndSettle();
      expect(find.text('Café'), findsNothing, reason: 'the list of movements is not showing');
    });

    testWidgets('the bottom bar has Inicio, ＋, the 🎤 and Análisis', (tester) async {
      await pumpHome(tester, monthWithBudgets());
      expect(find.text('Inicio'), findsOneWidget);
      expect(find.text('Análisis'), findsOneWidget);
      expect(find.byKey(const Key('home.add')), findsOneWidget);
      expect(find.byKey(const Key('home.capture')), findsOneWidget);
      // This test has no router: the tap does nothing (and does not fail). That it opens Análisis
      // is test/insights/insights_test.dart's.
      await tester.tap(find.text('Análisis'));
      await tester.pumpAndSettle();
      expect(find.text('Te quedan este mes'), findsOneWidget);
    });

    testWidgets('the list ends above the bar: the last row can be scrolled clear of it', (
      tester,
    ) async {
      final repo = FakeHomeRepository(
        items: [
          for (var i = 20; i >= 1; i--)
            tx('t$i', '2026-10-${i.toString().padLeft(2, '0')}', -100, name: 'Gasto $i'),
        ],
      );
      await pumpHome(tester, repo);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -5000));
      await tester.pumpAndSettle();
      final last = tester.getBottomLeft(find.text('Gasto 1')).dy;
      final bar = tester.getTopLeft(find.text('Inicio')).dy;
      expect(last, lessThan(bar), reason: 'the last row is above the bar');
    });
  });

  group('a big font and long text', () {
    testWidgets('at text scale 1.3 home has no overflow', (tester) async {
      final repo = FakeHomeRepository(
        budgetTotal: 200000000,
        categoryList: [
          category('cat-groceries', 'Supermercado y todo lo que se compra en el mercado'),
        ],
        items: [
          tx(
            'rent',
            '2026-10-25',
            -50000000,
            name: 'Arriendo de la casa grande del mes',
            status: 'pending',
          ),
          tx('coffee', '2026-10-22', -450000, name: 'Café'),
          tx(
            'big',
            '2026-10-21',
            -150000000000,
            name: 'Una compra con un nombre muy largo que no cabe en una línea',
          ),
        ],
      );
      await pumpHome(tester, repo, size: const Size(360, 640), textScale: 1.3);
      expect(tester.takeException(), isNull);
      // The header, the hero and the first row are all there.
      expect(find.text('Wambito'), findsOneWidget);
      expect(find.textContaining('Te pasaste'), findsOneWidget);
      expect(find.text('Café'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The ＋ and the 🎤 are on screen and not covered by anything but the bar.
      expect(tester.getRect(find.byKey(const Key('home.add'))).bottom, lessThanOrEqualTo(640));
      expect(tester.getRect(find.byKey(const Key('home.capture'))).bottom, lessThanOrEqualTo(640));
    });

    testWidgets('a budget of \$1.500.000.000 fits at 360 px and 130%', (tester) async {
      final repo = FakeHomeRepository(
        budgetTotal: 150000000000,
        items: [tx('a', '2026-10-22', -150000000000, name: 'Todo')],
      );
      await pumpHome(tester, repo, size: const Size(360, 640), textScale: 1.3);
      expect(tester.takeException(), isNull);
      expect(find.textContaining(r'$1.500.000.000'), findsWidgets);
    });

    testWidgets('a narrow phone (under 400px) puts the month on a row of its own', (tester) async {
      await pumpHome(tester, monthWithBudgets(), size: const Size(360, 740));
      expect(tester.takeException(), isNull);
      final month = tester.getCenter(find.text('Octubre'));
      final face = tester.getCenter(find.byKey(const Key('home.account')));
      expect(month.dy, greaterThan(face.dy), reason: 'under the wordmark and the face');
      expect(month.dx, closeTo(360 / 2, 1), reason: 'centred');
    });

    // 412px (Samsung, Pixel) and up to 480px: the wordmark, the month and the two buttons do not fit
    // on one row, and the buttons must never wrap to a row of their own under the wordmark; the
    // month takes the second row instead.
    for (final width in [412.0, 430.0, 470.0]) {
      testWidgets(
        'a ${width.toInt()}px phone keeps the face beside the wordmark, the month under them',
        (tester) async {
          await pumpHome(tester, monthWithBudgets(), size: Size(width, 900));
          expect(tester.takeException(), isNull);
          final wordmark = tester.getCenter(find.text('Wambito'));
          final face = tester.getCenter(find.byKey(const Key('home.account')));
          final month = tester.getCenter(find.text('Octubre'));
          expect(face.dy, closeTo(wordmark.dy, 1), reason: 'the face on the wordmark row');
          expect(month.dy, greaterThan(face.dy), reason: 'the month on the next row');
          expect(month.dx, closeTo(width / 2, 1), reason: 'centred');
        },
      );
    }

    testWidgets('a wide screen (480px and up) has the three on one row', (tester) async {
      await pumpHome(tester, monthWithBudgets(), size: const Size(480, 900));
      expect(tester.takeException(), isNull);
      final wordmark = tester.getCenter(find.text('Wambito'));
      final face = tester.getCenter(find.byKey(const Key('home.account')));
      final month = tester.getCenter(find.text('Octubre'));
      expect(face.dy, closeTo(wordmark.dy, 1));
      expect(month.dy, closeTo(wordmark.dy, 1));
    });

    testWidgets('large text moves the month to its own row before the face would wrap', (
      tester,
    ) async {
      await pumpHome(tester, monthWithBudgets(), size: const Size(560, 900), textScale: 1.3);
      expect(tester.takeException(), isNull);
      final wordmark = tester.getCenter(find.text('Wambito'));
      final face = tester.getCenter(find.byKey(const Key('home.account')));
      final month = tester.getCenter(find.text('Octubre'));
      expect(face.dy, closeTo(wordmark.dy, 1), reason: 'the face on the wordmark row');
      expect(month.dy, greaterThan(face.dy), reason: 'the month on the next row');
    });
  });

  group('offline and errors', () {
    testWidgets('a cold start with no network shows the last good month, with the offline note', (
      tester,
    ) async {
      final store = FakeCacheStore();
      await pumpHome(tester, monthWithBudgets(), cacheStore: store);

      // The app starts again, with no network.
      final offline = monthWithBudgets()..failures['profile'] = const HomeFailure(0);
      await pumpHome(tester, offline, cacheStore: store);
      expect(find.text('Te quedan este mes'), findsOneWidget);
      expect(find.text('Café'), findsOneWidget);
      expect(find.text('Sin conexión. Te mostramos lo último que cargó.'), findsOneWidget);
      expect(find.text('REINTENTAR'), findsNothing);
      await leave(tester);
    });

    testWidgets('in English the note is English', (tester) async {
      final store = FakeCacheStore();
      await pumpHome(tester, monthWithBudgets(), cacheStore: store, locale: const Locale('en'));
      final offline = monthWithBudgets()..failures['profile'] = const HomeFailure(0);
      await pumpHome(tester, offline, cacheStore: store, locale: const Locale('en'));
      expect(find.text('No connection. Showing what loaded last.'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('an October cache opened on 3 November never says this month', (tester) async {
      final store = FakeCacheStore();
      await pumpHome(tester, monthWithBudgets(), cacheStore: store);

      final offline = monthWithBudgets()..failures['profile'] = const HomeFailure(0);
      await pumpHome(tester, offline, cacheStore: store, now: DateTime.utc(2026, 11, 3, 15));
      expect(find.text('Octubre'), findsOneWidget);
      expect(find.text('Sin conexión · mostrando octubre'), findsOneWidget);
      expect(find.text('Te quedaron en octubre'), findsOneWidget);
      expect(find.textContaining('este mes'), findsNothing);
      expect(find.textContaining('Mes cerrado'), findsNothing);
      expect(find.textContaining('octubre'), findsWidgets);
      expect(find.textContaining('Estos son tus números de octubre'), findsOneWidget);
      // Its days are not today: no "Hoy" heading for last month's rows.
      expect(find.textContaining('HOY'), findsNothing);
      await leave(tester);
    });

    testWidgets('the same in English, and without budgets it says Spent in October', (
      tester,
    ) async {
      final store = FakeCacheStore();
      final repo = monthWithBudgets()..budgetTotal = 0;
      await pumpHome(tester, repo, cacheStore: store, locale: const Locale('en'));

      final offline = (monthWithBudgets()..budgetTotal = 0)
        ..failures['profile'] = const HomeFailure(0);
      await pumpHome(
        tester,
        offline,
        cacheStore: store,
        locale: const Locale('en'),
        now: DateTime.utc(2026, 11, 3, 15),
      );
      expect(find.text('No connection · showing October'), findsOneWidget);
      expect(find.text('Spent in October'), findsOneWidget);
      expect(find.textContaining('this month'), findsNothing);
      await leave(tester);
    });

    testWidgets('the month changing while the app is open: a failed refresh names October', (
      tester,
    ) async {
      var clock = DateTime.utc(2026, 10, 31, 20); // 15:00 in Bogota
      final repo = monthWithBudgets();
      await pumpHome(tester, repo, clock: () => clock);
      expect(find.text('Te quedan este mes'), findsOneWidget);

      // The app waits in the background past midnight (Bogota: 1 November) and comes back with no
      // signal.
      clock = DateTime.utc(2026, 11, 1, 12);
      repo.failures['summary'] = const HomeFailure(0);
      await tester.fling(find.byType(CustomScrollView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(find.text('Sin conexión · mostrando octubre'), findsOneWidget);
      expect(find.text('Te quedaron en octubre'), findsOneWidget);
      expect(find.textContaining('este mes'), findsNothing);
      expect(find.textContaining('Estos son tus números de octubre'), findsOneWidget);
      expect(find.textContaining('HOY'), findsNothing);
    });

    testWidgets('a server error with the network up does not say there is no connection', (
      tester,
    ) async {
      final store = FakeCacheStore();
      await pumpHome(tester, monthWithBudgets(), cacheStore: store);

      final broken = monthWithBudgets()..failures['profile'] = const HomeFailure(503);
      await pumpHome(tester, broken, cacheStore: store);
      expect(find.text('No pudimos actualizar. Te mostramos lo último que cargó.'), findsOneWidget);
      expect(find.textContaining('Sin conexión'), findsNothing);
      expect(find.text('Café'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('a refresh that fails with a server error says so too', (tester) async {
      final repo = monthWithBudgets();
      await pumpHome(tester, repo);
      repo.failures['summary'] = const HomeFailure(500);
      await tester.fling(find.byType(CustomScrollView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('No pudimos actualizar. Te mostramos lo último que cargó.'), findsOneWidget);
      expect(find.textContaining('Sin conexión'), findsNothing);
    });

    testWidgets('another person never sees the last person\'s month', (tester) async {
      final store = FakeCacheStore();
      await pumpHome(tester, monthWithBudgets(), cacheStore: store, token: 't1');

      final offline = monthWithBudgets()..failures['profile'] = const HomeFailure(0);
      await pumpHome(tester, offline, cacheStore: store, token: 't2');
      expect(find.text('Café'), findsNothing);
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      expect(find.text('REINTENTAR'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('a first load that fails offers Reintentar, and works once back online', (
      tester,
    ) async {
      final repo = monthWithBudgets()..failures['profile'] = const HomeFailure(0);
      await pumpHome(tester, repo);
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      await tester.tap(find.text('REINTENTAR'));
      await tester.pumpAndSettle();
      expect(find.text('Te quedan este mes'), findsOneWidget);
      expect(find.text('REINTENTAR'), findsNothing);
    });

    testWidgets('pulling down refreshes; offline, the last figures stay with a note', (
      tester,
    ) async {
      final repo = monthWithBudgets();
      await pumpHome(tester, repo);
      repo.failures['summary'] = const HomeFailure(0);
      await tester.fling(find.byType(CustomScrollView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Te quedan este mes'), findsOneWidget);
      expect(find.text('Café'), findsOneWidget);
      expect(find.text('Sin conexión. Te mostramos lo último que cargó.'), findsOneWidget);

      await tester.fling(find.byType(CustomScrollView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Sin conexión. Te mostramos lo último que cargó.'), findsNothing);
    });
  });

  group('the page background', () {
    /// Scrolls home's page by [offset] px.
    void scrollBy(WidgetTester tester, double offset) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(offset);

    FakeHomeRepository longMonth() => FakeHomeRepository(
      items: [
        for (var i = 20; i >= 1; i--)
          tx('t$i', '2026-10-${i.toString().padLeft(2, '0')}', -100, name: 'Gasto $i'),
      ],
    );

    testWidgets('Movimientos: the glow scrolls away with the list, as the web\'s page does', (
      tester,
    ) async {
      await pumpHome(tester, longMonth());
      final screen = screenOf(tester);
      final start = pageGradient(tester);
      expect(start.top, 0);
      expect(start.height, greaterThan(screen.height * 1.5), reason: 'as tall as the page');

      scrollBy(tester, 600);
      await tester.pumpAndSettle();
      final scrolled = pageGradient(tester);
      expect(scrolled.top, -600);
      // The list builds its rows as they come near, and its length is an estimate until it has:
      // the page is as tall as it was, to a few pixels.
      expect(scrolled.height, closeTo(start.height, start.height * 0.02));
    });

    testWidgets('Categorías: the same, over its own list', (tester) async {
      final repo = monthWithBudgets();
      await pumpHome(tester, repo);
      await tester.tap(find.text('Categorías'));
      await tester.pumpAndSettle();
      // A short screen, so the list has somewhere to go.
      tester.view.physicalSize = const Size(390, 300);
      await tester.pumpAndSettle();
      expect(pageGradient(tester).top, 0);
      scrollBy(tester, 100);
      await tester.pumpAndSettle();
      expect(pageGradient(tester).top, -100);
    });

    testWidgets('a month with nothing in it is a screen tall, as min-h-dvh makes it', (
      tester,
    ) async {
      await pumpHome(tester, FakeHomeRepository(), size: const Size(390, 2400));
      expect(pageGradient(tester), Offset.zero & const Size(390, 2400));
    });
  });
}
