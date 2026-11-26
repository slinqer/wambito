import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/home/home_controller.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/notices/notice_backend.dart';
import 'package:wambito/notices/notice_platform.dart';
import 'package:wambito/notices/notice_sync.dart';
import 'package:wambito/recurring/recurring_actions.dart';
import 'package:wambito/recurring/recurring_repository.dart';
import 'package:wambito/recurring/recurring_row.dart';

import '../budgets/budgets_test.dart' show Env, pumpBudgets, testBudgets;
import '../budgets/fakes.dart';
import '../home/fakes.dart';
import '../home/fixtures.dart';
import '../notices/fakes.dart';
import 'fakes.dart';
import '../support/amounts.dart';

/// The recurring payments page and its sheets, in the whole app (the real router) against fakes of
/// the server. How they look is the parity pairs' business (test/parity/recurring_parity_test.dart);
/// here is what they do. "Today" is 22 October 2026, in Bogota.

class RecEnv {
  RecEnv(this.app, this.home, this.server, this.platform);

  final Env app;
  final FakeHomeRepository home;
  final FakeRecurringRepository server;
  final FakeNoticePlatform platform;

  ProviderContainer get container => app.settings.container;
}

Future<RecEnv> pumpRecurring(
  WidgetTester tester, {
  List<Recurrence> rules = const [],
  FakeHomeRepository? home,
  Locale locale = const Locale('es'),
  List<Override> overrides = const [],
}) async {
  final month = home ?? budgetsMonth();
  final budgets = budgetsFor(month);
  final server = FakeRecurringRepository(month, rules: rules, budgets: budgets);
  final platform = FakeNoticePlatform(permissionState: NoticePermission.granted);
  final app = await pumpBudgets(
    tester,
    home: month,
    budgets: budgets,
    locale: locale,
    location: '/recurring',
    overrides: [
      recurringRepositoryProvider.overrideWithValue(server),
      noticePlatformProvider.overrideWithValue(platform),
      noticeBackendProvider.overrideWithValue(RulesNoticeBackend(server)),
      ...overrides,
    ],
  );
  return RecEnv(app, month, server, platform);
}

Finder rowOf(String name) =>
    find.byWidgetPredicate((w) => w is RecurringRow && w.rule.name == name);

Future<void> reveal(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await reveal(tester, key);
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> openNew(WidgetTester tester) => tapKey(tester, 'recurring.add');

Future<void> typeDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.byKey(Key('keypad.$digit')));
    await tester.pump();
  }
}

Future<void> typeName(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const Key('recurring.name')), name);
  await tester.pump();
}

Future<void> save(WidgetTester tester) => tapKey(tester, 'recurring.save');

Future<void> openEdit(WidgetTester tester, String name) async {
  await tester.tap(rowOf(name));
  await tester.pumpAndSettle();
}

Future<void> deleteIt(WidgetTester tester, {bool confirm = true}) async {
  await tapKey(tester, 'recurring.delete');
  if (confirm) {
    await tester.tap(find.byKey(const Key('recurring.delete.confirm')));
    await tester.pumpAndSettle();
  }
}

String _error(WidgetTester tester, String text) {
  expect(find.text(text), findsOneWidget);
  return text;
}

void main() {
  group('the list', () {
    testBudgets('says each payment\'s rule in words and its next date, as the web does', (
      tester,
    ) async {
      await pumpRecurring(
        tester,
        rules: [
          rule('spotify', 'cat-groceries', name: 'Spotify', amount: -353, day: 25),
          rule(
            'insurance',
            'cat-home',
            name: 'Seguro del carro',
            amount: -42000,
            frequency: RecurrenceFrequencyEnum.yearly,
            day: 15,
            month: 3,
            start: '2025-03-01',
          ),
          rule('salary', 'cat-salary', name: 'Salario', amount: 250000, day: 1),
          rule('old', 'cat-home', name: 'Gimnasio', end: '2026-06-30'),
        ],
      );

      expect(find.text('Recurrentes'), findsOneWidget);
      expect(find.textContaining('Lo que se repite cada mes o cada año'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Spotify .*Cada mes, el día 25 · Supermercado Próximo: 25 oct 2026'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Cada año, el 15 de marzo · Hogar Próximo: 15 mar 2027')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'^Salario \+.*Próximo: 1 nov 2026')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Gimnasio .*Ya terminó')), findsOneWidget);
      final names = [
        for (final r in tester.widgetList<RecurringRow>(find.byType(RecurringRow))) r.rule.name,
      ];
      expect(names, ['Spotify', 'Seguro del carro', 'Salario', 'Gimnasio'], reason: 'oldest first');
    });

    testBudgets('in English: the rule, the date and the empty page', (tester) async {
      await pumpRecurring(
        tester,
        locale: const Locale('en'),
        rules: [rule('spotify', 'cat-groceries', name: 'Spotify', day: 25)],
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Every month, on day 25 · Groceries|Every month, on day 25')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'Next: Oct 25, 2026')), findsOneWidget);
    });

    testBudgets('with none, Wambi says what goes here and the add button is there', (tester) async {
      await pumpRecurring(tester);
      expect(find.textContaining('Aquí van tus pagos fijos'), findsOneWidget);
      expect(find.byKey(const Key('recurring.add')), findsOneWidget);
      expect(find.byType(RecurringRow), findsNothing);
    });

    testBudgets('a list that cannot be read says so, and Reintentar reads it again', (
      tester,
    ) async {
      final home = budgetsMonth();
      final server = FakeRecurringRepository(home)..failures['list'] = const HomeFailure(0);
      await pumpBudgets(
        tester,
        home: home,
        location: '/recurring',
        overrides: [recurringRepositoryProvider.overrideWithValue(server)],
      );
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      server.rules.add(rule('spotify', 'cat-home', name: 'Spotify'));
      await tester.tap(find.text('REINTENTAR'));
      await tester.pumpAndSettle();
      expect(rowOf('Spotify'), findsOneWidget);
    });
  });

  group('a new payment', () {
    testBudgets('an expense: the amount, a name and a category, saved for today', (tester) async {
      final env = await pumpRecurring(tester);
      await openNew(tester);
      expect(find.text('Nuevo recurrente'), findsWidgets);

      await typeDigits(tester, '420');
      await typeName(tester, '  Arriendo ');
      await tapKey(tester, 'recurring.category.cat-home');
      await save(tester);

      final sent = env.server.created.single;
      expect(
        (
          sent.name,
          sent.amount,
          sent.categoryId,
          sent.frequency,
          sent.dayOfMonth,
          sent.monthOfYear,
          sent.startDate,
          sent.endDate,
        ),
        (
          'Arriendo',
          -42000,
          'cat-home',
          RecurrenceFrequencyEnum.monthly,
          22,
          null,
          '2026-10-22',
          null,
        ),
        reason: 'it starts today, on today\'s day, an expense is negative, the name is trimmed',
      );
      expect(find.byKey(const Key('recurring.save')), findsNothing, reason: 'the sheet closed');
      expect(find.text('Guardaste Arriendo.'), findsOneWidget);
      expect(rowOf('Arriendo'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('an income on the 23rd, with an end date, in Ingresos', (tester) async {
      final env = await pumpRecurring(tester);
      await openNew(tester);
      await tapKey(tester, 'recurring.kind.income');
      await typeDigits(tester, '150');
      await typeName(tester, 'Clases');
      expect(find.byKey(const Key('recurring.category.cat-groceries')), findsNothing);
      await tapKey(tester, 'recurring.category.cat-salary');
      await tapKey(tester, 'recurring.day');
      await tapKey(tester, 'recurring.choice.23');
      expect(find.text('23'), findsOneWidget);
      await save(tester);

      final sent = env.server.created.single;
      expect((sent.amount, sent.dayOfMonth, sent.categoryId), (15000, 23, 'cat-salary'));
      expect(find.text('Guardaste Clases.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('a yearly one needs its month: without it nothing is sent', (tester) async {
      final env = await pumpRecurring(tester);
      await openNew(tester);
      await typeDigits(tester, '420');
      await typeName(tester, 'Seguro de la moto');
      await tapKey(tester, 'recurring.category.cat-home');
      await tapKey(tester, 'recurring.frequency.yearly');
      expect(find.byKey(const Key('recurring.month')), findsOneWidget);
      expect(find.text('Elige un mes'), findsOneWidget);

      await save(tester);
      _error(tester, 'Elige el mes en que se repite.');
      expect(env.server.created, isEmpty);
      expect(find.byKey(const Key('recurring.save')), findsOneWidget, reason: 'the sheet stays');

      await tapKey(tester, 'recurring.month');
      await tapKey(tester, 'recurring.choice.3');
      expect(
        find.text('Elige el mes en que se repite.'),
        findsNothing,
        reason: 'choosing clears it',
      );
      await tapKey(tester, 'recurring.day');
      await tapKey(tester, 'recurring.choice.15');
      await save(tester);

      final sent = env.server.created.single;
      expect(
        (sent.frequency, sent.monthOfYear, sent.dayOfMonth, sent.amount),
        (RecurrenceFrequencyEnum.yearly, 3, 15, -42000),
      );
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('every missing field says so, first the amount, and nothing is sent', (
      tester,
    ) async {
      final env = await pumpRecurring(tester);
      await openNew(tester);
      await save(tester);
      _error(tester, 'Escribe el monto.');
      await typeDigits(tester, '5');
      await save(tester);
      _error(tester, 'Ponle un nombre.');
      await typeName(tester, '   ');
      await save(tester);
      _error(tester, 'Ponle un nombre.');
      await typeName(tester, 'Gimnasio');
      await save(tester);
      _error(tester, 'Elige una categoría.');
      expect(env.server.created, isEmpty);
      await tapKey(tester, 'recurring.category.cat-home');
      expect(find.text('Elige una categoría.'), findsNothing);
    });

    testBudgets('changing the kind drops a category of the other one', (tester) async {
      final env = await pumpRecurring(tester);
      await openNew(tester);
      await typeDigits(tester, '5');
      await typeName(tester, 'Algo');
      await tapKey(tester, 'recurring.category.cat-home');
      await tapKey(tester, 'recurring.kind.income');
      await save(tester);
      _error(tester, 'Elige una categoría.');
      expect(env.server.created, isEmpty);
    });

    testBudgets('a day past the 28th explains the shorter months', (tester) async {
      await pumpRecurring(tester);
      await openNew(tester);
      expect(find.textContaining('En los meses que no llegan a ese día'), findsNothing);
      await tapKey(tester, 'recurring.day');
      await tapKey(tester, 'recurring.choice.31');
      expect(find.textContaining('cae el último día del mes'), findsOneWidget);
    });

    testBudgets('a refusal is said in the sheet, which keeps what was typed', (tester) async {
      final env = await pumpRecurring(tester);
      env.server.failures['create'] = const HomeFailure(422, code: 'category_not_found');
      await openNew(tester);
      await typeDigits(tester, '9');
      await typeName(tester, 'Nube');
      await tapKey(tester, 'recurring.category.cat-home');
      await save(tester);

      expect(find.text('Elige una de tus categorías activas.'), findsOneWidget);
      expect(find.byKey(const Key('recurring.save')), findsOneWidget);
      expect(find.text('Nube'), findsOneWidget);
      // Again, and it goes through.
      await save(tester);
      expect(find.byKey(const Key('recurring.save')), findsNothing);
      expect(env.server.created, hasLength(1), reason: 'the refused one was never made');
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets(
      'a create whose answer is lost shows the rule the server made, so a retry is not a copy',
      (tester) async {
        final env = await pumpRecurring(tester);
        env.server.lostAnswers.add('create');
        await openNew(tester);
        await typeDigits(tester, '9');
        await typeName(tester, 'Nube');
        await tapKey(tester, 'recurring.category.cat-home');
        await save(tester);
        await tester.pumpAndSettle();

        expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
        expect(env.server.rules.map((r) => r.name), ['Nube'], reason: 'the server made it');
        expect(rowOf('Nube'), findsOneWidget, reason: 'the list was read again behind the sheet');
        expect(
          env.container.read(homeProvider).data!.items.where((t) => t.name == 'Nube'),
          hasLength(1),
          reason: 'home was loaded again too',
        );
        await tester.pump(const Duration(seconds: 10));
      },
    );

    testBudgets('a refusal that changed nothing does not reload anything', (tester) async {
      final env = await pumpRecurring(tester);
      env.server.failures['create'] = const HomeFailure(422, code: 'category_not_found');
      await openNew(tester);
      await typeDigits(tester, '9');
      await typeName(tester, 'Nube');
      await tapKey(tester, 'recurring.category.cat-home');
      final listed = env.server.calls.where((c) => c == 'list').length;
      await save(tester);
      await tester.pumpAndSettle();
      expect(env.server.calls.where((c) => c == 'list'), hasLength(listed));
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('offline says so; a server error says it is ours', (tester) async {
      final env = await pumpRecurring(tester);
      env.server.failures['create'] = const HomeFailure(0);
      await openNew(tester);
      await typeDigits(tester, '9');
      await typeName(tester, 'Nube');
      await tapKey(tester, 'recurring.category.cat-home');
      await save(tester);
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      env.server.failures['create'] = const HomeFailure(500);
      await save(tester);
      expect(
        find.text('Tuvimos un problema de nuestro lado. Inténtalo de nuevo en un momento.'),
        findsOneWidget,
      );
    });

    testBudgets('while one is being saved, Guardar sends nothing more', (tester) async {
      final env = await pumpRecurring(tester);
      env.server.hold = Completer<void>();
      await openNew(tester);
      await typeDigits(tester, '9');
      await typeName(tester, 'Nube');
      await tapKey(tester, 'recurring.category.cat-home');
      await tester.tap(find.byKey(const Key('recurring.save')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('recurring.save')), warnIfMissed: false);
      await tester.tap(find.byKey(const Key('recurring.save')), warnIfMissed: false);
      await tester.pump();
      env.server.hold!.complete();
      await tester.pumpAndSettle();
      expect(env.server.created, hasLength(1));
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('pesos have no decimal key, and the amount is stored in hundredths', (
      tester,
    ) async {
      final env = await pumpRecurring(tester);
      await openNew(tester);
      expect(find.byKey(const Key('keypad.comma')), findsNothing);
      await typeDigits(tester, '50000');
      await typeName(tester, 'Arriendo');
      await tapKey(tester, 'recurring.category.cat-home');
      await save(tester);
      expect(env.server.created.single.amount, -5000000);
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('the new payment\'s pending row reaches home, and the notices look again', (
      tester,
    ) async {
      final env = await pumpRecurring(tester);
      await env.container.read(noticeSyncProvider).idle;
      expect(env.platform.callsNamed('scheduleDue'), isEmpty, reason: 'nothing to announce yet');
      final asked = (env.container.read(noticeBackendProvider) as FakeNoticeBackend).calls;

      await openNew(tester);
      await typeDigits(tester, '35');
      await typeName(tester, 'Spotify');
      await tapKey(tester, 'recurring.category.cat-groceries');
      await save(tester);
      await env.container.read(noticeSyncProvider).idle;

      final items = env.container.read(homeProvider).data!.items;
      expect(
        items.where((t) => t.name == 'Spotify' && t.status == TransactionStatusEnum.pending),
        hasLength(1),
        reason: 'home\'s month was loaded again: the rule\'s pending row is there',
      );
      expect(
        (env.container.read(noticeBackendProvider) as FakeNoticeBackend).calls,
        greaterThan(asked),
      );
      expect(env.platform.callsNamed('scheduleDue'), isNotEmpty, reason: 'now there is one');
      await tester.pump(const Duration(seconds: 10));
    });
  });

  group('the sheet', () {
    testWidgets('scrolled down, a drag back past its top goes on to pull it closed', (
      tester,
    ) async {
      await pumpRecurring(tester);
      await openNew(tester);
      expect(find.text('Nuevo recurrente'), findsOneWidget);
      final caption = find.text('Categoría');
      await tester.drag(caption, const Offset(0, -300));
      await tester.pumpAndSettle();
      final scrolled = Scrollable.of(tester.element(caption)).position.pixels;
      expect(scrolled, greaterThan(0));

      // One finger: back up the content, and on past its top, down the screen.
      final gesture = await tester.startGesture(tester.getCenter(caption));
      for (var i = 0; i < 40; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Nuevo recurrente'), findsNothing);
    });
  });

  group('editing one', () {
    testBudgets('opens with what it has, and saves without the category it did not change', (
      tester,
    ) async {
      final env = await pumpRecurring(
        tester,
        rules: [rule('spotify', 'cat-groceries', name: 'Spotify', amount: -350000, day: 25)],
      );
      await openEdit(tester, 'Spotify');
      expect(find.text('Editar recurrente'), findsWidgets);
      expect(
        find.textContaining('−\$3.500', findRichText: true),
        findsNWidgets(2),
        reason: 'the row, and the sheet\'s figure',
      );
      expect(find.text('Spotify'), findsWidgets);
      expect(find.text('ELIMINAR RECURRENTE'), findsOneWidget);

      await typeName(tester, 'Spotify Duo');
      await save(tester);

      final (id, values, categoryChanged) = env.server.updated.single;
      expect(
        (id, values.name, values.amount, values.dayOfMonth),
        ('spotify', 'Spotify Duo', -350000, 25),
      );
      expect(categoryChanged, isFalse);
      expect(find.text('Guardaste Spotify Duo.'), findsOneWidget);
      expect(rowOf('Spotify Duo'), findsOneWidget);
      expect(rowOf('Spotify'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('a category chosen anew is sent', (tester) async {
      final env = await pumpRecurring(
        tester,
        rules: [rule('spotify', 'cat-groceries', name: 'Spotify', amount: -353)],
      );
      await openEdit(tester, 'Spotify');
      await tapKey(tester, 'recurring.category.cat-home');
      await save(tester);
      final (_, values, categoryChanged) = env.server.updated.single;
      expect((values.categoryId, categoryChanged), ('cat-home', true));
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('one whose category was archived since still offers it, and saves without a 422', (
      tester,
    ) async {
      final home = budgetsMonth();
      home.categoryList.add(category('cat-old', 'Gimnasio', icon: '🏋️', archived: true));
      final env = await pumpRecurring(
        tester,
        home: home,
        rules: [rule('gym', 'cat-old', name: 'Mensualidad', amount: -4000000)],
      );
      await openEdit(tester, 'Mensualidad');
      expect(find.byKey(const Key('recurring.category.cat-old')), findsOneWidget);
      await typeName(tester, 'Mensualidad gym');
      await save(tester);
      expect(env.server.updated.single.$3, isFalse, reason: 'its category is not sent');
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('an end date can be taken out again', (tester) async {
      final env = await pumpRecurring(
        tester,
        rules: [rule('spotify', 'cat-groceries', name: 'Spotify', amount: -353, end: '2027-06-30')],
      );
      await openEdit(tester, 'Spotify');
      expect(find.text('30/06/2027'), findsOneWidget);
      await tapKey(tester, 'recurring.end.clear');
      expect(find.text('30/06/2027'), findsNothing);
      await save(tester);
      expect(env.server.updated.single.$2.endDate, isNull);
      expect(env.server.rules.single.endDate, isNull);
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('the sheet of an income starts on Ingreso', (tester) async {
      await pumpRecurring(
        tester,
        rules: [rule('salary', 'cat-salary', name: 'Salario', amount: 250000, day: 1)],
      );
      await openEdit(tester, 'Salario');
      expect(find.byKey(const Key('recurring.category.cat-salary')), findsOneWidget);
      expect(find.byKey(const Key('recurring.category.cat-groceries')), findsNothing);
    });
  });

  group('deleting one', () {
    testBudgets('asks first, and Cancelar leaves it', (tester) async {
      final env = await pumpRecurring(
        tester,
        rules: [rule('spotify', 'cat-groceries', name: 'Spotify')],
      );
      await openEdit(tester, 'Spotify');
      await deleteIt(tester, confirm: false);
      expect(find.text('¿Eliminar Spotify?'), findsWidgets);
      expect(
        find.textContaining('sus pendientes de este mes en adelante se borran'),
        findsOneWidget,
      );
      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();
      expect(env.server.calls.where((c) => c.startsWith('delete')), isEmpty);
      expect(rowOf('Spotify'), findsOneWidget);
    });

    testBudgets('Sí, eliminar deletes it and says what stays', (tester) async {
      final env = await pumpRecurring(
        tester,
        rules: [
          rule('spotify', 'cat-groceries', name: 'Spotify'),
          rule('rent', 'cat-home', name: 'Arriendo', amount: -50000000),
        ],
      );
      await openEdit(tester, 'Spotify');
      await deleteIt(tester);
      expect(env.server.calls, contains('delete spotify'));
      expect(rowOf('Spotify'), findsNothing);
      expect(rowOf('Arriendo'), findsOneWidget);
      expect(find.text('Eliminaste Spotify. Lo que ya pagaste se queda.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('a failure is said in a toast and the question stays for another try', (
      tester,
    ) async {
      final env = await pumpRecurring(
        tester,
        rules: [rule('spotify', 'cat-groceries', name: 'Spotify')],
      );
      env.server.failures['delete'] = const HomeFailure(0);
      await openEdit(tester, 'Spotify');
      await deleteIt(tester);
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      expect(find.byKey(const Key('recurring.delete.confirm')), findsOneWidget);
      expect(rowOf('Spotify'), findsOneWidget);
      await tester.tap(find.byKey(const Key('recurring.delete.confirm')));
      await tester.pumpAndSettle();
      expect(rowOf('Spotify'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('a delete whose answer is lost: the row is gone, and the notices look again', (
      tester,
    ) async {
      final env = await pumpRecurring(
        tester,
        rules: [rule('spotify', 'cat-groceries', name: 'Spotify', day: 22)],
      );
      await env.container.read(noticeSyncProvider).idle;
      expect(env.platform.callsNamed('scheduleDue'), isNotEmpty);
      env.platform.clear();
      env.server.lostAnswers.add('delete');
      await openEdit(tester, 'Spotify');
      await deleteIt(tester);
      await env.container.read(noticeSyncProvider).idle;
      await tester.pumpAndSettle();

      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      expect(env.server.rules, isEmpty, reason: 'the server deleted it');
      expect(rowOf('Spotify'), findsNothing, reason: 'the list was read again');
      expect(
        env.container.read(homeProvider).data!.items.where((t) => t.name == 'Spotify'),
        isEmpty,
      );
      expect(env.platform.callsNamed('cancelDue'), isNotEmpty);
      await tester.pump(const Duration(seconds: 10));
    });

    testBudgets('the last one gone brings the empty page back', (tester) async {
      await pumpRecurring(tester, rules: [rule('spotify', 'cat-groceries', name: 'Spotify')]);
      await openEdit(tester, 'Spotify');
      await deleteIt(tester);
      expect(find.textContaining('Aquí van tus pagos fijos'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });
  });

  group('Review Focus 2: ending a payment due today, after the 9:00 notice is scheduled', () {
    /// A payment due today (the 22nd), as the server holds it: its pending row is dated today.
    List<Recurrence> dueToday() => [
      rule('internet', 'cat-home', name: 'Internet', amount: -5000000, day: 22),
    ];

    testBudgets(
      'deleting it: no notice is posted for it, home and the widget follow, DueWorker is cancelled',
      (tester) async {
        final env = await pumpRecurring(tester, rules: dueToday());
        await env.container.read(noticeSyncProvider).idle;
        expect(env.platform.callsNamed('scheduleDue'), isNotEmpty, reason: 'scheduled for 9:00');
        expect(env.server.dueOn('2026-10-22'), ['Internet'], reason: 'the notice would name it');
        expect(
          env.container.read(homeProvider).data!.items.where((t) => t.name == 'Internet'),
          isNotEmpty,
          reason: 'home lists its pending row',
        );
        final snapshots = env.app.snapshots.length;
        env.platform.clear();

        await openEdit(tester, 'Internet');
        await deleteIt(tester);
        await env.container.read(noticeSyncProvider).idle;
        await tester.pumpAndSettle();

        expect(env.server.dueOn('2026-10-22'), isEmpty, reason: 'no notice is posted for it');
        expect(
          env.container.read(homeProvider).data!.items.where((t) => t.name == 'Internet'),
          isEmpty,
          reason: 'its pending row left home',
        );
        expect(env.app.snapshots.length, greaterThan(snapshots), reason: 'the widget was told');
        expect(env.platform.callsNamed('cancelDue'), isNotEmpty, reason: 'no active rule is left');
        expect(env.platform.callsNamed('scheduleDue'), isEmpty);
        await tester.pump(const Duration(seconds: 10));
      },
    );

    testBudgets(
      'with another one still running, its notice stays and only the ended one drops out',
      (tester) async {
        final env = await pumpRecurring(
          tester,
          rules: [
            ...dueToday(),
            rule('spotify', 'cat-groceries', name: 'Spotify', day: 22),
            rule('gym', 'cat-home', name: 'Gimnasio', day: 28),
          ],
        );
        await env.container.read(noticeSyncProvider).idle;
        expect(env.server.dueOn('2026-10-22'), unorderedEquals(['Internet', 'Spotify']));
        env.platform.clear();

        await openEdit(tester, 'Internet');
        await deleteIt(tester);
        await env.container.read(noticeSyncProvider).idle;
        await tester.pumpAndSettle();

        expect(env.server.dueOn('2026-10-22'), ['Spotify']);
        expect(env.platform.callsNamed('cancelDue'), isEmpty, reason: 'others are running');
        expect(env.platform.callsNamed('scheduleDue'), isNotEmpty);
        await tester.pump(const Duration(seconds: 10));
      },
    );

    testBudgets('ending it with an end date before today does the same', (tester) async {
      final env = await pumpRecurring(tester, rules: dueToday());
      await env.container.read(noticeSyncProvider).idle;
      env.platform.clear();
      final before = env.server.rules.single;

      await env.container
          .read(recurringActionsProvider)
          .save(
            before,
            NewRecurrence(
              name: before.name,
              amount: before.amount,
              categoryId: before.categoryId,
              frequency: before.frequency,
              dayOfMonth: before.dayOfMonth,
              monthOfYear: null,
              startDate: before.startDate,
              endDate: '2026-10-21',
            ),
          );
      await env.container.read(noticeSyncProvider).idle;
      await tester.pumpAndSettle();

      expect(env.server.dueOn('2026-10-22'), isEmpty);
      expect(
        env.container.read(homeProvider).data!.items.where((t) => t.name == 'Internet'),
        isEmpty,
      );
      expect(
        env.platform.callsNamed('cancelDue'),
        isNotEmpty,
        reason: 'it has ended: nothing runs',
      );
      await tester.pump(const Duration(seconds: 10));
    });
  });

  testWidgets('with home\'s eye closed, recurring payments show no amount', (tester) async {
    final semantics = tester.ensureSemantics();
    final env = await pumpRecurring(
      tester,
      rules: [rule('spotify', 'cat-groceries', name: 'Spotify', day: 25)],
    );
    await closeEye(tester, env.app.settings.container);
    expect(find.text('Spotify'), findsOneWidget);
    expectNoAmounts(tester);
    semantics.dispose();
  });
}
