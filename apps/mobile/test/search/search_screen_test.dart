
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/home/home_widgets.dart' show DayHeading;
import 'package:wambito/money/format.dart';
import 'package:wambito/search/search_repository.dart';
import 'package:wambito/search/search_screen.dart';

import '../home/fakes.dart';
import '../home/fixtures.dart';
import '../settings/harness.dart';

/// The server's search over a list of transactions: filters like the API, pages of [pageSize],
/// totals over every match. Records every call.
class _FakeSearch implements SearchRepository {
  _FakeSearch(this.all, {this.pageSize = 50, this.sendTotals = true});

  final List<Transaction> all;
  final int pageSize;
  final bool sendTotals;
  final calls = <(SearchFilters, String?)>[];
  Object? failure;

  @override
  Future<SearchPage> search(SearchFilters f, {String? cursor}) async {
    calls.add((f, cursor));
    final error = failure;
    if (error != null) {
      failure = null;
      throw error;
    }
    final text = f.text.trim().toLowerCase();
    final matches = [
      for (final t in all)
        if ((text.isEmpty || t.name.toLowerCase().contains(text)) &&
            (f.kind == SearchKind.all ||
                (f.kind == SearchKind.expense ? t.amount < 0 : t.amount > 0)) &&
            (f.categoryIds.isEmpty || f.categoryIds.contains(t.categoryId)) &&
            (f.status == SearchStatus.all || t.status.name == f.status.name))
          t,
    ];
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + pageSize).clamp(0, matches.length);
    return SearchPage(
      items: matches.sublist(start, end),
      nextCursor: end < matches.length ? '$end' : null,
      totals: !sendTotals
          ? null
          : SearchTotals(
              count: matches.length,
              expense: matches.where((t) => t.amount < 0).fold(0, (s, t) => s - t.amount),
              income: matches.where((t) => t.amount > 0).fold(0, (s, t) => s + t.amount),
            ),
    );
  }
}

final _field = find.byKey(const Key('search.field'));

Future<(_FakeSearch, SettingsEnv)> _pump(
  WidgetTester tester, {
  List<Transaction>? items,
  int pageSize = 50,
  bool sendTotals = true,
  Future<void> Function(BuildContext, Transaction)? edit,
  String location = '/search',
  Locale locale = const Locale('es'),
}) async {
  final search = _FakeSearch(
    items ??
        [
          tx('a', '2026-10-21', -1250000, name: 'Cafe Juan'),
          tx('b', '2026-10-21', -3000000, name: 'Cafe Taxi', categoryId: 'cat-eat'),
          tx('c', '2026-10-20', 80000000, name: 'Cafe nomina', categoryId: 'cat-pay'),
          tx('d', '2026-10-19', -500000, name: 'Pan', categoryId: 'cat-old'),
        ],
    pageSize: pageSize,
    sendTotals: sendTotals,
  );
  final home = FakeHomeRepository(
    categoryList: [
      category('cat-groceries', 'Supermercado'),
      category('cat-eat', 'Restaurante'),
      category('cat-pay', 'Nomina', kind: 'income'),
      category('cat-old', 'Vieja', archived: true),
    ],
  );
  final env = await pumpSettingsApp(
    tester,
    homeRepo: home,
    location: location,
    locale: locale,
    overrides: [
      searchRepositoryProvider.overrideWithValue(search),
      if (edit != null) searchOpenEditProvider.overrideWithValue(edit),
    ],
  );
  return (search, env);
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_field, text);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens with the hint and the field focused, nothing searched', (tester) async {
    final (search, _) = await _pump(tester);
    expect(find.text('Busca por nombre, nota, categoría…'), findsOneWidget);
    final editable = tester.widget<EditableText>(_field);
    expect(editable.focusNode.hasFocus, isTrue);
    expect(search.calls, isEmpty);
    expect(find.byType(DayHeading), findsNothing);
  });

  testWidgets('typing shows the rows by day and the totals', (tester) async {
    final (search, _) = await _pump(tester);
    await _type(tester, 'cafe');
    expect(search.calls.single.$1.text, 'cafe');
    expect(find.text('Cafe Juan'), findsOneWidget);
    expect(find.text('Cafe Taxi'), findsOneWidget);
    expect(find.text('Cafe nomina'), findsOneWidget);
    expect(find.text('Pan'), findsNothing);
    expect(find.byType(DayHeading), findsNWidgets(2));
    final expense = formatMoney(4250000, 'COP', 'es');
    final income = formatMoney(80000000, 'COP', 'es');
    expect(find.text('3 movimientos · gastos $expense · ingresos $income'), findsOneWidget);
  });

  testWidgets('the totals line is hidden when the server sends none', (tester) async {
    await _pump(tester, sendTotals: false);
    await _type(tester, 'cafe');
    expect(find.text('Cafe Juan'), findsOneWidget);
    expect(find.byKey(const Key('search.totals')), findsNothing);
  });

  testWidgets('Ingresos hides the expenses', (tester) async {
    final (search, _) = await _pump(tester);
    await _type(tester, 'cafe');
    await tester.tap(find.byKey(const Key('search.kind.income')));
    await tester.pumpAndSettle();
    expect(search.calls.last.$1.kind, SearchKind.income);
    expect(find.text('Cafe nomina'), findsOneWidget);
    expect(find.text('Cafe Juan'), findsNothing);
    expect(find.text('Cafe Taxi'), findsNothing);
  });

  testWidgets('the category sheet selects two categories and both are sent', (tester) async {
    final (search, _) = await _pump(tester);
    await tester.tap(find.byKey(const Key('search.categories')));
    await tester.pumpAndSettle();
    expect(find.text('Vieja'), findsOneWidget);
    await tester.tap(find.byKey(const Key('category.cat-groceries')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('category.cat-eat')));
    await tester.pumpAndSettle();
    expect(search.calls.last.$1.categoryIds, {'cat-groceries', 'cat-eat'});
    await tester.tap(find.text('LISTO'));
    await tester.pumpAndSettle();
    expect(find.text('CATEGORÍA · 2'), findsOneWidget);
    expect(find.text('Cafe Juan'), findsOneWidget);
    expect(find.text('Cafe Taxi'), findsOneWidget);
    expect(find.text('Cafe nomina'), findsNothing);
  });

  testWidgets('no results says so with the text', (tester) async {
    await _pump(tester);
    await _type(tester, 'zzz');
    expect(find.text('No encontré nada con «zzz»'), findsOneWidget);
    expect(find.byKey(const Key('search.totals')), findsNothing);
  });

  testWidgets('no results with only filters says so without the text', (tester) async {
    await _pump(tester, items: [tx('a', '2026-10-21', -100, name: 'Solo gasto')]);
    await tester.tap(find.byKey(const Key('search.kind.income')));
    await tester.pumpAndSettle();
    expect(find.text('No encontré nada con esos filtros'), findsOneWidget);
  });

  testWidgets('a failure shows the failure row and Reintentar searches again', (tester) async {
    final (search, _) = await _pump(tester);
    search.failure = const HomeFailure(500);
    await _type(tester, 'cafe');
    expect(find.byKey(const Key('search.failure')), findsOneWidget);
    expect(find.text('Cafe Juan'), findsNothing);
    await tester.tap(find.byKey(const Key('search.retry')));
    await tester.pumpAndSettle();
    expect(search.calls, hasLength(2));
    expect(find.byKey(const Key('search.failure')), findsNothing);
    expect(find.text('Cafe Juan'), findsOneWidget);
  });

  testWidgets('scrolling to the end loads the next page', (tester) async {
    final items = [
      for (var i = 0; i < 12; i++)
        tx('t$i', '2026-10-${(20 - i ~/ 2).toString().padLeft(2, '0')}', -100000, name: 'Item $i'),
    ];
    final (search, _) = await _pump(tester, items: items, pageSize: 4);
    await _type(tester, 'item');
    expect(find.text('Item 11'), findsNothing);
    await tester.dragUntilVisible(
      find.text('Item 11'),
      find.byType(SingleChildScrollView).first,
      const Offset(0, -300),
      maxIteration: 80,
    );
    await tester.pumpAndSettle();
    expect(find.text('Item 11'), findsOneWidget);
    expect(search.calls.where((c) => c.$2 != null), isNotEmpty);
    expect(search.calls.map((c) => c.$2).toSet().length, greaterThan(2));
  });

  testWidgets('after the editor closes the list and the totals reload', (tester) async {
    late _FakeSearch search;
    Future<void> deleteFirst(BuildContext context, Transaction t) async {
      search.all.removeWhere((x) => x.id == t.id);
    }

    final pumped = await _pump(tester, edit: deleteFirst);
    search = pumped.$1;
    await _type(tester, 'cafe');
    expect(find.text('Cafe Juan'), findsOneWidget);
    await tester.tap(find.text('Cafe Juan'));
    await tester.pumpAndSettle();
    expect(search.calls, hasLength(2), reason: 'the first page was asked again');
    expect(find.text('Cafe Juan'), findsNothing);
    final expense = formatMoney(3000000, 'COP', 'es');
    final income = formatMoney(80000000, 'COP', 'es');
    expect(find.text('2 movimientos · gastos $expense · ingresos $income'), findsOneWidget);
  });

  testWidgets("the home header's magnifier opens /search", (tester) async {
    final (_, env) = await _pump(tester, location: '/');
    expect(find.bySemanticsLabel('Buscar'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home.search')));
    await tester.pumpAndSettle();
    expect(env.router.routerDelegate.currentConfiguration.last.matchedLocation, '/search');
    expect(find.byKey(const Key('search.field')), findsOneWidget);
  });
}
