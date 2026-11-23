import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/categories/categories_repository.dart';
import 'package:wambito/home/home_controller.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/notices/notice_backend.dart';
import 'package:wambito/notices/notice_platform.dart';
import 'package:wambito/notices/notice_sync.dart';
import 'package:wambito/ui/budget_bar.dart';
import 'package:wambito/ui/category_row.dart';

import '../budgets/budgets_test.dart'
    show Env, openBudgetsTab, openDetail, pumpBudgets, testBudgets;
import '../budgets/fakes.dart';
import '../home/fakes.dart';
import '../home/fixtures.dart';
import '../notices/fakes.dart';
import 'fakes.dart';

/// Managing categories from home's Categorías tab and a category's detail (the web has no page of
/// its own for it): the tab's switch, "Nueva categoría" and the folded "Archivadas"; the detail's
/// rename, emoji and colour, and archiving. How they look is the parity pairs' business
/// (test/parity/categories_parity_test.dart); here is what they do.

class CatEnv {
  CatEnv(this.app, this.home, this.categories);

  final Env app;
  final FakeHomeRepository home;
  final FakeCategoriesRepository categories;
}

Future<CatEnv> pumpCategories(
  WidgetTester tester, {
  FakeHomeRepository? home,
  Map<String, int>? budgetMap,
  List<Recurrence> rules = const [],
  Locale locale = const Locale('es'),
  String? location,
  List<Override> overrides = const [],
}) async {
  final server = home ?? budgetsMonth();
  final budgets = FakeBudgetsRepository(
    server,
    budgets: budgetMap ?? {'cat-groceries': 25000000, 'cat-home': 60000000},
  );
  final categories = FakeCategoriesRepository(server, budgets, rules: rules);
  final app = await pumpBudgets(
    tester,
    home: server,
    budgets: budgets,
    locale: locale,
    location: location,
    overrides: [categoriesRepositoryProvider.overrideWithValue(categories), ...overrides],
  );
  return CatEnv(app, server, categories);
}

/// A row of a list, by what a screen reader hears: its name and its status.
Finder row(String label) => find.bySemanticsLabel(RegExp('^$label\$'));

FakeHomeRepository monthWithArchived({bool spending = false}) {
  final home = budgetsMonth();
  home.categoryList.add(category('cat-old', 'Gimnasio', icon: '🏋️', archived: true));
  if (spending) {
    home.items.add(tx('gym', '2026-10-03', -4000000, name: 'Mensualidad', categoryId: 'cat-old'));
  }
  return home;
}

Future<void> openFold(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('categories.fold')));
  await tester.pumpAndSettle();
}

Future<void> openNewCategory(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('categories.add')));
  await tester.pumpAndSettle();
}

Future<void> typeName(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const Key('category.name')), name);
  await tester.pump();
}

Future<void> saveCategory(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('category.save')));
  await tester.tap(find.byKey(const Key('category.save')));
  await tester.pumpAndSettle();
}

Future<void> pick(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

Future<void> openEdit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('detail.edit')));
  await tester.pumpAndSettle();
}

Future<void> askToArchive(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('category.archive')));
  await tester.tap(find.byKey(const Key('category.archive')));
  await tester.pumpAndSettle();
}

String _title(WidgetTester tester) {
  final text = tester.widget<Text>(find.byKey(const Key('detail.title')));
  return text.data ?? '';
}

void main() {
  group('the Categorías tab', () {
    testBudgets('has a Gastos | Ingresos switch and Nueva categoría above the list', (
      tester,
    ) async {
      await pumpCategories(tester);
      await openBudgetsTab(tester);

      expect(find.byKey(const Key('categories.kind.expense')), findsOneWidget);
      expect(find.byKey(const Key('categories.kind.income')), findsOneWidget);
      expect(find.text('Gastos'), findsOneWidget);
      expect(find.text('Ingresos'), findsOneWidget);
      expect(find.byKey(const Key('categories.add')), findsOneWidget);
      expect(
        [for (final r in tester.widgetList<CategoryRow>(find.byType(CategoryRow))) r.name],
        ['Hogar', 'Supermercado'],
      );
    });

    testBudgets('Nueva categoría is a row after the categories, and the switch has the whole row', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpCategories(tester);
      await openBudgetsTab(tester);

      final add = find.byKey(const Key('categories.add'));
      expect(find.descendant(of: add, matching: find.text('Nueva categoría')), findsOneWidget);
      expect(tester.getSemantics(add).label, 'Nueva categoría');
      final addBox = tester.getRect(add);
      expect(addBox.height, greaterThanOrEqualTo(48));
      final last = tester.getRect(find.byType(CategoryRow).last);
      expect(addBox.top, greaterThan(last.bottom), reason: 'after the categories');
      expect(addBox.width, closeTo(last.width, 1), reason: 'as wide as a row');
      final expense = tester.getRect(find.byKey(const Key('categories.kind.expense')));
      final income = tester.getRect(find.byKey(const Key('categories.kind.income')));
      expect(income.right - expense.left, closeTo(last.width, 12), reason: 'the switch fills it');
    });

    testBudgets('Nueva categoría comes before Archivadas', (tester) async {
      await pumpCategories(tester, home: monthWithArchived());
      await openBudgetsTab(tester);
      expect(
        tester.getRect(find.byKey(const Key('categories.add'))).bottom,
        lessThan(tester.getRect(find.byKey(const Key('categories.fold'))).top),
      );
    });

    testBudgets('Ingresos lists the income categories with "Ingreso" and no bar', (tester) async {
      await pumpCategories(tester);
      await openBudgetsTab(tester);
      await tester.tap(find.byKey(const Key('categories.kind.income')));
      await tester.pumpAndSettle();

      expect(row('Nómina Ingreso'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(CategoryRow), matching: find.byType(BudgetBar)),
        findsNothing,
      );
      expect(find.text('Hogar'), findsNothing);
      expect(find.text('Supermercado'), findsNothing);
      expect(find.byKey(const Key('categories.add')), findsOneWidget);

      await tester.tap(find.byKey(const Key('categories.kind.expense')));
      await tester.pumpAndSettle();
      expect(find.text('Hogar'), findsOneWidget);
      expect(find.text('Nómina'), findsNothing);
    });

    testBudgets('an income category opens its detail from the list', (tester) async {
      await pumpCategories(tester);
      await openBudgetsTab(tester);
      await tester.tap(find.byKey(const Key('categories.kind.income')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nómina'));
      await tester.pumpAndSettle();
      expect(_title(tester), 'Nómina');
    });

    testBudgets('a kind with no category says so', (tester) async {
      final home = budgetsMonth()
        ..categoryList.removeWhere((c) => c.kind == CategoryKindEnum.income);
      await pumpCategories(tester, home: home);
      await openBudgetsTab(tester);
      await tester.tap(find.byKey(const Key('categories.kind.income')));
      await tester.pumpAndSettle();
      expect(find.text('Aún no tienes categorías de este tipo.'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const Key('categories.add'))).top,
        greaterThan(tester.getRect(find.text('Aún no tienes categorías de este tipo.')).bottom),
        reason: 'the way to make the first one, under the line',
      );
    });

    testBudgets('there is no Archivadas while nothing is archived', (tester) async {
      await pumpCategories(tester);
      await openBudgetsTab(tester);
      expect(find.byKey(const Key('categories.fold')), findsNothing);
    });

    testBudgets('an archived category with no spending this month waits in Archivadas, folded', (
      tester,
    ) async {
      await pumpCategories(tester, home: monthWithArchived());
      await openBudgetsTab(tester);

      expect(find.text('Gimnasio'), findsNothing, reason: 'not among the rows');
      expect(find.text('ARCHIVADAS (1)'), findsOneWidget);
      expect(row('Archivadas'), findsNothing, reason: 'folded');

      await openFold(tester);
      expect(row('Gimnasio Archivada'), findsOneWidget);
      expect(find.byKey(const Key('categories.restore.cat-old')), findsOneWidget);
      expect(find.text('RESTAURAR'), findsOneWidget);

      await tester.tap(find.byKey(const Key('categories.fold')));
      await tester.pumpAndSettle();
      expect(find.text('Gimnasio'), findsNothing, reason: 'folded again');
    });

    testBudgets('one with spending this month is among the rows, noted, and not in Archivadas', (
      tester,
    ) async {
      await pumpCategories(tester, home: monthWithArchived(spending: true));
      await openBudgetsTab(tester);

      expect(row('Gimnasio archivada Sin presupuesto'), findsOneWidget);
      expect(find.byKey(const Key('categories.fold')), findsNothing);
      // It opens its detail, which offers Restaurar.
      await tester.tap(find.byKey(const ValueKey('cat-old')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail.restore')), findsOneWidget);
    });

    testBudgets('the fold counts the archived ones of the kind on screen', (tester) async {
      final home = monthWithArchived();
      home.categoryList.add(category('cat-old-income', 'Beca', kind: 'income', archived: true));
      home.categoryList.add(category('cat-old-2', 'Cine', archived: true));
      await pumpCategories(tester, home: home);
      await openBudgetsTab(tester);
      expect(find.text('ARCHIVADAS (2)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('categories.kind.income')));
      await tester.pumpAndSettle();
      expect(find.text('ARCHIVADAS (1)'), findsOneWidget);
    });

    testBudgets('Restaurar brings an archived category back among the others', (tester) async {
      final env = await pumpCategories(tester, home: monthWithArchived());
      await openBudgetsTab(tester);
      await openFold(tester);

      await tester.tap(find.byKey(const Key('categories.restore.cat-old')));
      await tester.pumpAndSettle();

      expect(env.categories.calls, contains('update cat-old archived=false'));
      expect(find.text('Gimnasio está de vuelta.'), findsOneWidget);
      expect(row('Gimnasio Sin presupuesto'), findsOneWidget);
      expect(
        find.byKey(const Key('categories.fold')),
        findsNothing,
        reason: 'nothing archived now',
      );
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('a restore that fails says why and changes nothing', (tester) async {
      final env = await pumpCategories(tester, home: monthWithArchived());
      env.categories.failures['update'] = const HomeFailure(0);
      await openBudgetsTab(tester);
      await openFold(tester);

      await tester.tap(find.byKey(const Key('categories.restore.cat-old')));
      await tester.pumpAndSettle();

      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      expect(row('Gimnasio Archivada'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('an archived row opens its detail, which offers Restaurar', (tester) async {
      await pumpCategories(tester, home: monthWithArchived());
      await openBudgetsTab(tester);
      await openFold(tester);
      await tester.tap(find.text('Gimnasio'));
      await tester.pumpAndSettle();
      expect(_title(tester), 'Gimnasio');
      expect(find.byKey(const Key('detail.restore')), findsOneWidget);
    });

    testBudgets('in English the copy is English', (tester) async {
      await pumpCategories(tester, home: monthWithArchived(), locale: const Locale('en'));
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      expect(find.text('Spending'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const Key('categories.add'))).label, 'New category');
      expect(find.text('ARCHIVED (1)'), findsOneWidget);
      await openFold(tester);
      expect(row('Gimnasio Archived'), findsOneWidget);
      expect(find.text('RESTORE'), findsOneWidget);
    });
  });

  group('Nueva categoría', () {
    testBudgets('opens a sheet with the name, the kind, the emoji and the colour', (tester) async {
      await pumpCategories(tester);
      await openBudgetsTab(tester);
      await openNewCategory(tester);

      expect(
        find.text('Nueva categoría'),
        findsNWidgets(2),
        reason: 'the row and the sheet\'s title',
      );
      expect(find.text('Nombre'), findsOneWidget);
      expect(find.text('Tipo'), findsOneWidget);
      expect(find.text('Ícono'), findsOneWidget);
      expect(find.text('Color'), findsOneWidget);
      expect(find.byKey(const Key('category.kind.expense')), findsOneWidget);
      expect(find.byKey(const Key('category.kind.income')), findsOneWidget);
      expect(find.byKey(const Key('category.glyph.🏷️')), findsOneWidget);
      expect(find.byKey(const Key('category.tint.orange')), findsOneWidget);
      expect(
        find.byKey(const Key('category.archive')),
        findsNothing,
        reason: 'nothing to archive yet',
      );
      expect(find.text('GUARDAR CATEGORÍA'), findsOneWidget);
    });

    testBudgets('a name is asked for, and nothing is sent without one', (tester) async {
      final env = await pumpCategories(tester);
      await openBudgetsTab(tester);
      await openNewCategory(tester);

      await saveCategory(tester);
      expect(find.byKey(const Key('category.error')), findsOneWidget);
      expect(find.text('Escribe un nombre para la categoría.'), findsOneWidget);
      await typeName(tester, '   ');
      await saveCategory(tester);
      expect(find.text('Escribe un nombre para la categoría.'), findsOneWidget);
      expect(env.categories.calls.where((c) => c.startsWith('create')), isEmpty);
    });

    testBudgets('saves what was chosen and the new category joins the list', (tester) async {
      final env = await pumpCategories(tester);
      await openBudgetsTab(tester);
      await openNewCategory(tester);

      await typeName(tester, '  Mascotas ');
      await pick(tester, 'category.glyph.🐶');
      await pick(tester, 'category.tint.blue');
      await saveCategory(tester);

      expect(
        env.categories.calls.where((c) => c.startsWith('create')).single,
        'create Mascotas expense 🐶 #3fa7ff',
      );
      expect(find.byKey(const Key('category.save')), findsNothing, reason: 'the sheet closed');
      expect(find.text('Listo: creaste Mascotas.'), findsOneWidget);
      expect(row('Mascotas Sin presupuesto'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('an income category is made in Ingresos', (tester) async {
      final env = await pumpCategories(tester);
      await openBudgetsTab(tester);
      await openNewCategory(tester);

      await typeName(tester, 'Beca');
      await pick(tester, 'category.kind.income');
      await saveCategory(tester);

      expect(
        env.categories.calls.where((c) => c.startsWith('create')).single,
        'create Beca income 🏷️ #ff9f1c',
      );
      expect(find.text('Beca'), findsNothing, reason: 'Gastos is on screen');
      await tester.tap(find.byKey(const Key('categories.kind.income')));
      await tester.pumpAndSettle();
      expect(row('Beca Ingreso'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('a name another category has is refused in the sheet, which stays', (tester) async {
      final env = await pumpCategories(tester);
      await openBudgetsTab(tester);
      await openNewCategory(tester);

      await typeName(tester, 'hogar');
      await saveCategory(tester);
      expect(find.text('Ya tienes una categoría con ese nombre.'), findsOneWidget);
      expect(find.byKey(const Key('category.save')), findsOneWidget, reason: 'still open');
      expect(
        tester.widget<EditableText>(find.byKey(const Key('category.name'))).controller.text,
        'hogar',
      );

      await typeName(tester, 'Hogar 2');
      await saveCategory(tester);
      expect(find.byKey(const Key('category.save')), findsNothing);
      expect(env.categories.calls.where((c) => c.startsWith('create')), hasLength(2));
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('with no connection it says so, and a retry saves', (tester) async {
      final env = await pumpCategories(tester);
      env.categories.failures['create'] = const HomeFailure(0);
      await openBudgetsTab(tester);
      await openNewCategory(tester);

      await typeName(tester, 'Mascotas');
      await saveCategory(tester);
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      await saveCategory(tester);
      expect(find.byKey(const Key('category.save')), findsNothing);
      expect(row('Mascotas Sin presupuesto'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('a create whose answer is lost shows the category the server made', (tester) async {
      final env = await pumpCategories(tester);
      env.categories.lostAnswers.add('create');
      await openBudgetsTab(tester);
      await openNewCategory(tester);

      await typeName(tester, 'Mascotas');
      await saveCategory(tester);
      await tester.pumpAndSettle();
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      // The categories were read again behind the sheet: the one the server made is on the tab, so
      // another Guardar is not a second one.
      expect(
        env.app.settings.container
            .read(homeProvider)
            .data!
            .categories
            .values
            .any((c) => c.name == 'Mascotas'),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('Guardar categoría while it saves sends it once', (tester) async {
      final env = await pumpCategories(tester);
      env.categories.hold = Completer<void>();
      await openBudgetsTab(tester);
      await openNewCategory(tester);
      await typeName(tester, 'Mascotas');

      await tester.ensureVisible(find.byKey(const Key('category.save')));
      await tester.tap(find.byKey(const Key('category.save')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('category.save')), warnIfMissed: false);
      await tester.pump();
      env.categories.hold!.complete();
      await tester.pumpAndSettle();

      expect(env.categories.calls.where((c) => c.startsWith('create')), hasLength(1));
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('the name takes 40 characters at most', (tester) async {
      await pumpCategories(tester);
      await openBudgetsTab(tester);
      await openNewCategory(tester);
      await typeName(tester, 'x' * 60);
      expect(
        tester.widget<EditableText>(find.byKey(const Key('category.name'))).controller.text,
        'x' * 40,
      );
    });

    testBudgets('in English the sheet is English', (tester) async {
      await pumpCategories(tester, locale: const Locale('en'));
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      await openNewCategory(tester);
      expect(find.text('New category'), findsNWidgets(2), reason: 'the row and the sheet\'s title');
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Icon'), findsOneWidget);
      expect(find.text('SAVE CATEGORY'), findsOneWidget);
    });
  });

  group('a category\'s detail', () {
    testBudgets('has Editar, where Stage 3b had a link to the web', (tester) async {
      await pumpCategories(tester);
      await openDetail(tester, 'Supermercado');
      expect(find.text('EDITAR'), findsOneWidget);
      expect(find.text('MÁS EN LA WEB'), findsNothing);
    });

    testBudgets('Editar opens the sheet with its name, emoji and colour', (tester) async {
      await pumpCategories(tester);
      await openDetail(tester, 'Supermercado');
      await openEdit(tester);

      expect(find.text('Editar categoría'), findsOneWidget, reason: 'the sheet\'s title');
      expect(
        tester.widget<EditableText>(find.byKey(const Key('category.name'))).controller.text,
        'Supermercado',
      );
      expect(find.byKey(const Key('category.archive')), findsOneWidget);
      // Its own emoji first.
      final glyphs = [
        for (final element
            in find
                .byWidgetPredicate(
                  (w) =>
                      w.key is ValueKey<String> &&
                      (w.key! as ValueKey<String>).value.startsWith('category.glyph.'),
                )
                .evaluate())
          (element.widget.key! as ValueKey<String>).value,
      ];
      expect(glyphs.first, 'category.glyph.🛒');
      expect(glyphs.toSet().length, glyphs.length, reason: 'each once');
    });

    testBudgets('rename, emoji and colour go in one change; the title and the list follow', (
      tester,
    ) async {
      final env = await pumpCategories(tester);
      await openDetail(tester, 'Supermercado');
      await openEdit(tester);

      await typeName(tester, 'Súper');
      await pick(tester, 'category.glyph.🎁');
      await pick(tester, 'category.tint.blue');
      await saveCategory(tester);

      expect(
        env.categories.calls.where((c) => c.startsWith('update')).single,
        'update cat-groceries name=Súper icon=🎁 color=#3fa7ff',
        reason: 'the kind did not change, so it is not sent',
      );
      expect(_title(tester), 'Súper');
      expect(find.text('Guardaste los cambios de Súper.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.tap(find.bySemanticsLabel('Volver a Categorías').first);
      await tester.pumpAndSettle();
      expect(find.text('Súper'), findsOneWidget);
      expect(find.text('Supermercado'), findsNothing);
    });

    testBudgets('a name another category has is refused in the sheet', (tester) async {
      final env = await pumpCategories(tester);
      await openDetail(tester, 'Supermercado');
      await openEdit(tester);
      await typeName(tester, 'Hogar');
      await saveCategory(tester);

      expect(find.text('Ya tienes una categoría con ese nombre.'), findsOneWidget);
      expect(find.byKey(const Key('category.save')), findsOneWidget);
      expect(_title(tester), 'Supermercado');
      expect(env.categories.calls.where((c) => c.startsWith('update')), hasLength(1));
    });

    testBudgets('with movements its kind is fixed, and the sheet says why', (tester) async {
      final env = await pumpCategories(tester);
      await openDetail(tester, 'Supermercado');
      await openEdit(tester);
      await tester.pumpAndSettle();

      expect(find.text('Con movimientos, su tipo no se puede cambiar aquí.'), findsOneWidget);
      // The disabled choice does nothing: only the rest of the changes are sent.
      await tester.ensureVisible(find.byKey(const Key('category.kind.income')));
      await tester.tap(find.byKey(const Key('category.kind.income')), warnIfMissed: false);
      await tester.pump();
      await typeName(tester, 'Súper');
      await saveCategory(tester);
      expect(
        env.categories.calls.where((c) => c.startsWith('update')).single,
        'update cat-groceries name=Súper icon=🛒 color=#2fd388',
      );
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('without movements its kind can change', (tester) async {
      final home = budgetsMonth();
      home.categoryList.add(category('cat-new', 'Mascotas', icon: '🐶'));
      final env = await pumpCategories(tester, home: home);
      await openDetail(tester, 'Mascotas');
      await openEdit(tester);

      expect(find.text('Con movimientos, su tipo no se puede cambiar aquí.'), findsNothing);
      await pick(tester, 'category.kind.income');
      await saveCategory(tester);

      expect(
        env.categories.calls.where((c) => c.startsWith('update')).single,
        'update cat-new name=Mascotas icon=🐶 color=#2fd388 kind=income',
      );
      expect(find.text('Categoría de ingreso'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('a kind change the server refuses is said in the sheet', (tester) async {
      final home = budgetsMonth();
      home.categoryList.add(category('cat-new', 'Mascotas', icon: '🐶'));
      final env = await pumpCategories(tester, home: home);
      env.categories.failures['update'] = const HomeFailure(409, code: 'category_has_transactions');
      await openDetail(tester, 'Mascotas');
      await openEdit(tester);
      await pick(tester, 'category.kind.income');
      await saveCategory(tester);
      expect(
        find.text('Esta categoría ya tiene movimientos, así que su tipo no puede cambiar.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('category.save')), findsOneWidget);
    });

    testBudgets('archiving asks first, and Cancelar changes nothing', (tester) async {
      final env = await pumpCategories(tester);
      await openDetail(tester, 'Supermercado');
      await openEdit(tester);
      await askToArchive(tester);

      expect(find.text('¿Archivar Supermercado?'), findsOneWidget);
      expect(find.textContaining('Sus movimientos se quedan'), findsOneWidget);
      expect(
        find.textContaining('También se detendr'),
        findsNothing,
        reason: 'no recurring payment',
      );
      expect(find.byKey(const Key('category.save')), findsNothing, reason: 'the edit sheet went');

      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();
      expect(env.categories.calls.where((c) => c.startsWith('update')), isEmpty);
      expect(find.text('¿Archivar Supermercado?'), findsNothing);
    });

    testBudgets('the question counts the recurring payments it stops', (tester) async {
      final rules = [
        recurrence('r1', 'cat-groceries', name: 'Suscripción'),
        recurrence('r2', 'cat-groceries', name: 'Otra', endDate: '2026-10-31'),
        recurrence('r3', 'cat-groceries', name: 'Vieja', endDate: '2026-10-01'),
        recurrence('r4', 'cat-home', name: 'Arriendo'),
      ];
      await pumpCategories(tester, rules: rules);
      await openDetail(tester, 'Supermercado');
      await openEdit(tester);
      await askToArchive(tester);
      expect(
        find.text('También se detendrán 2 pagos recurrentes de esta categoría.'),
        findsOneWidget,
      );
      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();

      // One, in the singular.
      await tester.tap(find.bySemanticsLabel('Volver a Categorías').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hogar'));
      await tester.pumpAndSettle();
      await openEdit(tester);
      await askToArchive(tester);
      expect(find.text('También se detendrá 1 pago recurrente de esta categoría.'), findsOneWidget);
    });

    testBudgets('Sí, archivar archives it: the detail says so and offers Restaurar', (
      tester,
    ) async {
      final env = await pumpCategories(tester);
      await openDetail(tester, 'Supermercado');
      await openEdit(tester);
      await askToArchive(tester);
      await tester.tap(find.byKey(const Key('category.archive.confirm')));
      await tester.pumpAndSettle();

      expect(env.categories.calls, contains('update cat-groceries archived=true'));
      expect(find.text('Archivaste Supermercado. Sus movimientos se quedan.'), findsOneWidget);
      expect(find.text('Categoría de gasto · Archivada'), findsOneWidget);
      expect(find.byKey(const Key('detail.restore')), findsOneWidget);
      expect(find.byKey(const Key('detail.changeBudget')), findsNothing);
      await tester.pump(const Duration(seconds: 10));

      await tester.tap(find.byKey(const Key('detail.restore')));
      await tester.pumpAndSettle();
      expect(env.categories.calls, contains('update cat-groceries archived=false'));
      expect(find.text('Supermercado está de vuelta.'), findsOneWidget);
      expect(find.text('Categoría de gasto'), findsOneWidget);
      expect(find.byKey(const Key('detail.restore')), findsNothing);
      expect(find.byKey(const Key('detail.changeBudget')), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('an archive that fails says why and the question stays for another try', (
      tester,
    ) async {
      final env = await pumpCategories(tester);
      env.categories.failures['update'] = const HomeFailure(503);
      await openDetail(tester, 'Supermercado');
      await openEdit(tester);
      await askToArchive(tester);
      await tester.tap(find.byKey(const Key('category.archive.confirm')));
      await tester.pumpAndSettle();

      expect(
        find.text('Tuvimos un problema de nuestro lado. Inténtalo de nuevo en un momento.'),
        findsOneWidget,
      );
      expect(find.text('¿Archivar Supermercado?'), findsOneWidget, reason: 'still asking');
      expect(find.text('Categoría de gasto'), findsOneWidget, reason: 'not archived');

      await tester.pump(const Duration(seconds: 10));
      await tester.tap(find.byKey(const Key('category.archive.confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Categoría de gasto · Archivada'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('opened from the tab, back says so and leads to the tab', (tester) async {
      await pumpCategories(tester);
      await openDetail(tester, 'Supermercado');
      expect(find.bySemanticsLabel('Volver a Categorías'), findsWidgets);

      await tester.tap(find.bySemanticsLabel('Volver a Categorías').first);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(const Key('categories.add')), findsOneWidget, reason: 'the Categorías tab');
    });

    testBudgets('a category that is not there leads back to the tab', (tester) async {
      await pumpCategories(tester, location: '/categories/nope');
      expect(find.text('No encontramos esta categoría'), findsOneWidget);
      await tester.tap(find.text('VER MIS CATEGORÍAS'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(const Key('categories.add')), findsOneWidget);
    });

    testBudgets('in English the detail\'s words are English', (tester) async {
      await pumpCategories(tester, locale: const Locale('en'));
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supermercado'));
      await tester.pumpAndSettle();
      expect(find.text('EDIT'), findsOneWidget);
      expect(find.bySemanticsLabel('Back to Categories'), findsWidgets);
      await openEdit(tester);
      expect(find.text('Edit category'), findsOneWidget);
      await askToArchive(tester);
      expect(find.text('Archive Supermercado?'), findsOneWidget);
    });
  });

  group('archiving a category that has a budget or a recurring payment', () {
    testBudgets('home\'s figures, the tab and the widget follow', (tester) async {
      // Mascotas has a budget and no movement: archived, it leaves the month's budgets.
      final home = budgetsMonth();
      home.categoryList.add(category('cat-pets', 'Mascotas', icon: '🐶'));
      final env = await pumpCategories(
        tester,
        home: home,
        budgetMap: {'cat-groceries': 25000000, 'cat-home': 60000000, 'cat-pets': 10000000},
      );
      // 950.000 of budgets and 183.000 spent: 767.000 left.
      expect(find.text(r'$767.000'), findsOneWidget);
      final before = env.app.snapshots.length;

      await openDetail(tester, 'Mascotas');
      await openEdit(tester);
      await askToArchive(tester);
      await tester.tap(find.byKey(const Key('category.archive.confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Volver a Categorías').first);
      await tester.pumpAndSettle();

      // Its budget is no longer part of the month: Te quedan has 100.000 less.
      final summary = env.app.settings.container.read(homeProvider).data!.summary;
      expect(summary.budgetTotal, 85000000);
      expect(find.text(r'$767.000'), findsNothing);
      expect(find.text(r'$667.000'), findsOneWidget, reason: 'the hero');
      expect(find.text('Mascotas'), findsNothing, reason: 'not among the budgets');
      expect(find.text('ARCHIVADAS (1)'), findsOneWidget);
      // The widget was told the month\'s new figures.
      expect(env.app.snapshots.length, greaterThan(before));
      expect(env.app.snapshots.last.budgetTotal, 85000000);
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('its recurring payment ends, its pending row goes, and the notices look again', (
      tester,
    ) async {
      final platform = FakeNoticePlatform(permissionState: NoticePermission.granted);
      late FakeCategoriesRepository cats;
      final home = budgetsMonth();
      final budgets = FakeBudgetsRepository(
        home,
        budgets: {'cat-groceries': 25000000, 'cat-home': 60000000},
      );
      cats = FakeCategoriesRepository(
        home,
        budgets,
        rules: [recurrence('rent', 'cat-home', name: 'Arriendo', amount: -50000000)],
      );
      final backend = RecurringNoticeBackend(cats);
      final env = await pumpBudgets(
        tester,
        home: home,
        budgets: budgets,
        overrides: [
          categoriesRepositoryProvider.overrideWithValue(cats),
          noticePlatformProvider.overrideWithValue(platform),
          noticeBackendProvider.overrideWithValue(backend),
        ],
      );
      final container = env.settings.container;
      await container.read(noticeSyncProvider).idle;
      expect(
        platform.callsNamed('scheduleDue'),
        isNotEmpty,
        reason: 'a recurring payment is running',
      );
      platform.clear();
      final asked = backend.calls;

      // Home lists the rent among Movimientos, pending.
      expect(find.text('Arriendo'), findsOneWidget);

      await openDetail(tester, 'Hogar');
      await openEdit(tester);
      await askToArchive(tester);
      expect(find.text('También se detendrá 1 pago recurrente de esta categoría.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('category.archive.confirm')));
      await tester.pumpAndSettle();
      await container.read(noticeSyncProvider).idle;
      await tester.pumpAndSettle();

      expect(
        cats.rules.single.endDate,
        FakeCategoriesRepository.today,
        reason: 'the server ended it',
      );
      // The notices looked again at what the server says. The rule ended today, so it still counts
      // as running until tonight, but its pending row is gone: "Hoy vence…" has nothing to say.
      expect(backend.calls, greaterThan(asked), reason: 'the notices were asked to look again');
      await tester.pump(const Duration(seconds: 10));
      await tester.tap(find.bySemanticsLabel('Volver a Categorías').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Movimientos'));
      await tester.pumpAndSettle();
      expect(find.text('Arriendo'), findsNothing, reason: 'its pending row went from home');
      expect(find.text('Mercado'), findsOneWidget, reason: 'the others stay');
    });
  });
}
