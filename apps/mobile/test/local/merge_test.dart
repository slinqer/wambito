import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/core/records.dart' show Json;
import 'package:wambito/crypto/records.dart' show RecordType;
import 'package:wambito/local/captures.dart' show merchantRecordId;
import 'package:wambito/local/ids.dart';
import 'package:wambito/local/memory_store.dart';
import 'package:wambito/local/merge.dart';
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/store.dart';

// Invented fixtures: two users, the phone's anonymous one and the account it is carried into.
const phoneUser = 'a1a1a1a1-0000-4000-8000-000000000001';
const accountUser = 'b2b2b2b2-0000-4000-8000-000000000002';

String settingsIdOf(String userId) => uuidv5(uuidv5(seedNamespace, userId), 'settings');

Json category(String name, {String kind = 'expense', String? archivedAt}) => {
  's': 1,
  'name': name,
  'kind': kind,
  'icon': 'x',
  'color': '#fff',
  'sortOrder': 0,
  'archivedAt': archivedAt,
  'systemKey': null,
};

Json settings({String currency = 'COP', String? savedAt, List<String> revoked = const []}) => {
  's': 1,
  'name': null,
  'currency': currency,
  'locale': 'es',
  'timezone': 'America/Bogota',
  'onboardingCompletedAt': null,
  'revokedDevices': revoked,
  'recoveryKeySavedAt': savedAt,
};

Json transaction(
  String categoryId, {
  int amount = -1500000,
  String? accountId,
  String? recurrenceId,
  String? occurrenceMonth,
}) => {
  's': 1,
  'name': 'Mercado',
  'amount': amount,
  'currency': 'COP',
  'date': '2026-11-03',
  'status': recurrenceId != null ? 'pending' : 'paid',
  'note': null,
  'categoryId': categoryId,
  'accountId': accountId,
  'recurrenceId': recurrenceId,
  'occurrenceMonth': occurrenceMonth,
  'source': recurrenceId != null ? 'recurrence' : 'app',
  'needsReview': false,
  'captureSource': null,
  'capturedAt': null,
  'captureMerchantKey': null,
};

Json recurrence(String categoryId) => {
  's': 1,
  'name': 'Arriendo',
  'amount': -120000000,
  'categoryId': categoryId,
  'frequency': 'monthly',
  'dayOfMonth': 5,
  'monthOfYear': null,
  'startDate': '2026-01-05',
  'endDate': null,
  'rev': 0,
};

Json budget(String categoryId, {int amount = 50000000, String from = '2026-11'}) => {
  's': 1,
  'categoryId': categoryId,
  'amount': amount,
  'effectiveFrom': from,
};

Json merchant(String key, String categoryId) => {
  's': 1,
  'merchantKey': key,
  'categoryId': categoryId,
};

Json account(String name) => {'s': 1, 'name': name, 'currency': 'COP', 'isDefault': false};

/// Every record of [store] (tombstones too) as `type/id → [deleted, body]`.
Future<Map<String, List<Object>>> dump(FinanceStore store) async => {
  for (final type in RecordType.values)
    for (final r in await store.list(type, const ReadOptions(includeDeleted: true)))
      '${type.name}/${r.id}': [r.deleted, r.body],
};

Future<Json?> body(FinanceStore store, RecordType type, String id) async =>
    (await store.get(type, id))?.body;

// Phone ids (v7-looking) and account ids, invented.
const pFood = '01930000-0000-7000-8000-00000000a001';
const pSalary = '01930000-0000-7000-8000-00000000a002';
const pTx = '01930000-0000-7000-8000-00000000a003';
const pRule = '01930000-0000-7000-8000-00000000a004';
const pBudget = '01930000-0000-7000-8000-00000000a005';
const pGone = '01930000-0000-7000-8000-00000000a006';
const pAccount = '01930000-0000-7000-8000-00000000a007';
const aFood = '01930000-0000-7000-8000-00000000b001';
const aSalary = '01930000-0000-7000-8000-00000000b002';
const aBudget = '01930000-0000-7000-8000-00000000b005';
const aAccount = '01930000-0000-7000-8000-00000000b007';
const aRule = '01930000-0000-7000-8000-00000000b004';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  var counter = 0;
  setUpAll(() => dir = Directory.systemTemp.createTempSync('wambito-merge-test'));
  tearDownAll(() => dir.deleteSync(recursive: true));
  Future<SqliteStore> sqlite() =>
      SqliteStore.open('merge-${++counter}', directory: dir.path, factory: databaseFactoryFfi);

  test('currencyOf reads the settings record, null without one', () async {
    final store = createMemoryStore();
    expect(await currencyOf(store), isNull);
    await store.put(RecordType.settings, settingsIdOf(phoneUser), settings(currency: 'USD'));
    expect(await currencyOf(store), 'USD');
  });

  test('foldedName is the trimmed lower-case name', () {
    expect(foldedName('  Comida '), 'comida');
    expect(foldedName('MERCADO'), 'mercado');
  });

  test('adopt copies every live record, re-keys settings and merchants, clears recoveryKeySavedAt, '
      'skips tombstones', () async {
    final from = createMemoryStore();
    final into = createMemoryStore();
    final oldSettings = settingsIdOf(phoneUser);
    final oldMerchant = merchantRecordId(phoneUser, 'exito');
    await from.put(
      RecordType.settings,
      oldSettings,
      settings(savedAt: '2026-11-01T10:00:00.000Z', revoked: [pGone]),
    );
    await from.put(RecordType.category, pFood, category('Comida'));
    await from.put(RecordType.account, pAccount, account('Bancolombia'));
    await from.put(RecordType.transaction, pTx, transaction(pFood, accountId: pAccount));
    await from.put(RecordType.recurrence, pRule, recurrence(pFood));
    await from.put(RecordType.budget, pBudget, budget(pFood));
    await from.put(RecordType.merchant, oldMerchant, merchant('exito', pFood));
    await from.put(RecordType.transaction, pGone, transaction(pFood));
    await from.delete(RecordType.transaction, pGone);
    await from.put(RecordType.category, pSalary, category('Viejo'));
    await from.delete(RecordType.category, pSalary);

    final report = await carryRecords(from, into, mode: CarryMode.adopt, intoUserId: accountUser);

    final newSettings = settingsIdOf(accountUser);
    final newMerchant = merchantRecordId(accountUser, 'exito');
    expect((await dump(into)).keys.toSet(), {
      'settings/$newSettings',
      'category/$pFood',
      'account/$pAccount',
      'transaction/$pTx',
      'recurrence/$pRule',
      'budget/$pBudget',
      'merchant/$newMerchant',
    });
    expect(await body(into, RecordType.settings, newSettings), {
      ...settings(),
      'recoveryKeySavedAt': null,
      'revokedDevices': <Object?>[],
    });
    expect(await body(into, RecordType.merchant, newMerchant), merchant('exito', pFood));
    expect(await body(into, RecordType.transaction, pTx), transaction(pFood, accountId: pAccount));
    expect(await body(into, RecordType.category, pFood), category('Comida'));
    expect(report.written, 7);
    expect(report.dropped, 0);
    expect(report.remapped, {oldSettings: newSettings, oldMerchant: newMerchant});
  });

  test('a deleted occurrence of a carried recurrence is carried as a tombstone, so the rule '
      'does not make it again', () async {
    final from = createMemoryStore();
    final into = createMemoryStore();
    final occurrence = uuidv5(pRule, '2026-11:0');
    await from.put(RecordType.category, pFood, category('Comida'));
    await from.put(RecordType.recurrence, pRule, recurrence(pFood));
    await from.put(
      RecordType.transaction,
      occurrence,
      transaction(pFood, recurrenceId: pRule, occurrenceMonth: '2026-11'),
    );
    await from.delete(RecordType.transaction, occurrence);

    await carryRecords(from, into, mode: CarryMode.adopt, intoUserId: accountUser);

    final carried = await into.get(
      RecordType.transaction,
      occurrence,
      const ReadOptions(includeDeleted: true),
    );
    expect(carried?.deleted, isTrue);
    expect(carried?.body['recurrenceId'], pRule);
    expect(await into.get(RecordType.transaction, occurrence), isNull);
  });

  group('merge', () {
    /// The account's vault, as downloaded: its settings, categories, an account and a budget.
    Future<FinanceStore> theAccount([FinanceStore? store]) async {
      final into = store ?? createMemoryStore();
      await into.put(RecordType.settings, settingsIdOf(accountUser), settings(currency: 'COP'));
      await into.put(RecordType.category, aFood, category('comida'));
      await into.put(RecordType.category, aSalary, category('Salario', kind: 'income'));
      await into.put(RecordType.account, aAccount, account('bancolombia '));
      await into.put(RecordType.budget, aBudget, budget(aFood, amount: 70000000));
      return into;
    }

    test("merge: a phone category with the account's folded name and kind is dropped and its "
        "transactions, recurrences, budgets and merchants point to the account's", () async {
      final from = createMemoryStore();
      final into = await theAccount();
      final pSalaryBudget = '${pBudget.substring(0, 33)}999';
      await from.put(RecordType.category, pFood, category('  Comida '));
      await from.put(RecordType.category, pSalary, category('SALARIO', kind: 'income'));
      await from.put(RecordType.account, pAccount, account('Bancolombia'));
      await from.put(RecordType.transaction, pTx, transaction(pFood, accountId: pAccount));
      await from.put(RecordType.recurrence, pRule, recurrence(pSalary));
      // the account has no budget for Salario: the phone's comes along, re-pointed
      await from.put(RecordType.budget, pSalaryBudget, budget(pSalary));
      await from.put(
        RecordType.merchant,
        merchantRecordId(phoneUser, 'exito'),
        merchant('exito', pFood),
      );

      final report = await carryRecords(from, into, mode: CarryMode.merge, intoUserId: accountUser);

      expect(await body(into, RecordType.category, pFood), isNull);
      expect(await body(into, RecordType.category, pSalary), isNull);
      expect(await body(into, RecordType.account, pAccount), isNull);
      expect(
        await body(into, RecordType.transaction, pTx),
        transaction(aFood, accountId: aAccount),
      );
      expect(await body(into, RecordType.recurrence, pRule), recurrence(aSalary));
      expect(await body(into, RecordType.budget, pSalaryBudget), budget(aSalary));
      expect(
        await body(into, RecordType.merchant, merchantRecordId(accountUser, 'exito')),
        merchant('exito', aFood),
      );
      expect(report.remapped, {
        pFood: aFood,
        pSalary: aSalary,
        pAccount: aAccount,
        merchantRecordId(phoneUser, 'exito'): merchantRecordId(accountUser, 'exito'),
      });
      expect(report.dropped, 3);
      expect(report.written, 4);
    });

    test('merge: same name, other kind is kept as "<name> 2"', () async {
      final from = createMemoryStore();
      final into = await theAccount();
      await from.put(RecordType.category, pFood, category(' Comida', kind: 'income'));
      await from.put(RecordType.transaction, pTx, transaction(pFood, amount: 900000));

      await carryRecords(from, into, mode: CarryMode.merge, intoUserId: accountUser);

      expect(await body(into, RecordType.category, pFood), category('Comida 2', kind: 'income'));
      expect((await body(into, RecordType.transaction, pTx))?['categoryId'], pFood);
      expect(await body(into, RecordType.category, aFood), category('comida'));
    });

    test('merge: an archived account category does not match', () async {
      final from = createMemoryStore();
      final into = createMemoryStore();
      await into.put(
        RecordType.category,
        aFood,
        category('Comida', archivedAt: '2026-10-01T00:00:00.000Z'),
      );
      await from.put(RecordType.category, pFood, category('Comida'));
      await from.put(RecordType.transaction, pTx, transaction(pFood));

      final report = await carryRecords(from, into, mode: CarryMode.merge, intoUserId: accountUser);

      expect(await body(into, RecordType.category, pFood), category('Comida'));
      expect((await body(into, RecordType.transaction, pTx))?['categoryId'], pFood);
      expect(report.remapped, isEmpty);
    });

    test("merge: the account's settings win", () async {
      final from = createMemoryStore();
      final into = await theAccount();
      await from.put(
        RecordType.settings,
        settingsIdOf(phoneUser),
        settings(currency: 'COP', savedAt: '2026-11-02T00:00:00.000Z'),
      );

      final report = await carryRecords(from, into, mode: CarryMode.merge, intoUserId: accountUser);

      final all = await into.list(RecordType.settings);
      expect(all.map((r) => r.id), [settingsIdOf(accountUser)]);
      expect(all.single.body, settings(currency: 'COP'));
      expect(report.dropped, 1);
      expect(report.written, 0);
    });

    test(
      'merge: a phone budget is added only where the account has none for that category',
      () async {
        final from = createMemoryStore();
        final into = await theAccount();
        const pOther = '01930000-0000-7000-8000-00000000a008';
        const pOtherBudget = '01930000-0000-7000-8000-00000000a009';
        await from.put(RecordType.category, pFood, category('Comida'));
        await from.put(RecordType.category, pOther, category('Transporte'));
        await from.put(RecordType.budget, pBudget, budget(pFood, amount: 10000000));
        await from.put(RecordType.budget, pOtherBudget, budget(pOther, amount: 20000000));

        await carryRecords(from, into, mode: CarryMode.merge, intoUserId: accountUser);

        final budgets = {for (final r in await into.list(RecordType.budget)) r.id: r.body};
        expect(budgets, {
          aBudget: budget(aFood, amount: 70000000),
          pOtherBudget: budget(pOther, amount: 20000000),
        });
      },
    );

    test("merge: a merchant whose re-keyed id exists keeps the account's", () async {
      final from = createMemoryStore();
      final into = await theAccount();
      final theirs = merchantRecordId(accountUser, 'exito');
      await into.put(RecordType.merchant, theirs, merchant('exito', aSalary));
      await from.put(RecordType.category, pFood, category('Comida'));
      await from.put(
        RecordType.merchant,
        merchantRecordId(phoneUser, 'exito'),
        merchant('exito', pFood),
      );

      await carryRecords(from, into, mode: CarryMode.merge, intoUserId: accountUser);

      expect(await body(into, RecordType.merchant, theirs), merchant('exito', aSalary));
      expect((await into.list(RecordType.merchant)).map((r) => r.id), [theirs]);
    });

    test('merge: occurrence ids are kept and do not collide', () async {
      final from = createMemoryStore();
      final into = await theAccount();
      final theirOccurrence = uuidv5(aRule, '2026-11:0');
      final ourOccurrence = uuidv5(pRule, '2026-11:0');
      await into.put(RecordType.recurrence, aRule, recurrence(aFood));
      await into.put(
        RecordType.transaction,
        theirOccurrence,
        transaction(aFood, recurrenceId: aRule, occurrenceMonth: '2026-11'),
      );
      await from.put(RecordType.category, pFood, category('Comida'));
      await from.put(RecordType.recurrence, pRule, recurrence(pFood));
      await from.put(
        RecordType.transaction,
        ourOccurrence,
        transaction(pFood, recurrenceId: pRule, occurrenceMonth: '2026-11'),
      );

      await carryRecords(from, into, mode: CarryMode.merge, intoUserId: accountUser);

      expect(ourOccurrence, isNot(theirOccurrence));
      expect(
        await body(into, RecordType.transaction, ourOccurrence),
        transaction(aFood, recurrenceId: pRule, occurrenceMonth: '2026-11'),
      );
      expect(
        await body(into, RecordType.transaction, theirOccurrence),
        transaction(aFood, recurrenceId: aRule, occurrenceMonth: '2026-11'),
      );
      expect(await body(into, RecordType.recurrence, pRule), recurrence(aFood));
    });
  });

  test('running the carry twice gives the same target', () async {
    for (final mode in CarryMode.values) {
      final from = createMemoryStore();
      final into = await sqlite();
      await into.put(RecordType.settings, settingsIdOf(accountUser), settings());
      await into.put(RecordType.category, aFood, category('Comida'));
      await into.put(RecordType.budget, aBudget, budget(aFood));
      await from.put(RecordType.settings, settingsIdOf(phoneUser), settings());
      await from.put(RecordType.category, pFood, category('comida'));
      await from.put(RecordType.category, pSalary, category('Comida', kind: 'income'));
      await from.put(RecordType.budget, pBudget, budget(pFood));
      await from.put(RecordType.transaction, pTx, transaction(pFood));
      await from.put(RecordType.recurrence, pRule, recurrence(pSalary));
      await from.put(
        RecordType.merchant,
        merchantRecordId(phoneUser, 'exito'),
        merchant('exito', pFood),
      );
      final occurrence = uuidv5(pRule, '2026-11:0');
      await from.put(
        RecordType.transaction,
        occurrence,
        transaction(pSalary, recurrenceId: pRule, occurrenceMonth: '2026-11'),
      );
      await from.delete(RecordType.transaction, occurrence);

      await carryRecords(from, into, mode: mode, intoUserId: accountUser);
      final first = await dump(into);
      final firstOutbox = {for (final e in await into.readOutbox(1000)) e.id};
      await carryRecords(from, into, mode: mode, intoUserId: accountUser);

      expect(await dump(into), first, reason: mode.name);
      expect({for (final e in await into.readOutbox(1000)) e.id}, firstOutbox, reason: mode.name);
      await into.close();
    }
  });

  test('every written record is an outbox entry with no base version', () async {
    final from = createMemoryStore();
    final into = await sqlite();
    await from.put(RecordType.settings, settingsIdOf(phoneUser), settings());
    await from.put(RecordType.category, pFood, category('Comida'));
    await from.put(RecordType.transaction, pTx, transaction(pFood));
    await from.put(RecordType.recurrence, pRule, recurrence(pFood));
    await from.put(RecordType.budget, pBudget, budget(pFood));
    await from.put(
      RecordType.merchant,
      merchantRecordId(phoneUser, 'exito'),
      merchant('exito', pFood),
    );
    final occurrence = uuidv5(pRule, '2026-11:0');
    await from.put(
      RecordType.transaction,
      occurrence,
      transaction(pFood, recurrenceId: pRule, occurrenceMonth: '2026-11'),
    );
    await from.delete(RecordType.transaction, occurrence);

    final report = await carryRecords(from, into, mode: CarryMode.adopt, intoUserId: accountUser);

    final outbox = await into.readOutbox(1000);
    final written = {for (final key in (await dump(into)).keys) key.split('/').last};
    expect({for (final e in outbox) e.id}, written);
    expect(outbox.length, report.written);
    expect(outbox.every((e) => e.baseVersion == null), isTrue);
    expect(outbox.where((e) => e.deleted).map((e) => e.id), [occurrence]);
    await into.close();
  });
}
