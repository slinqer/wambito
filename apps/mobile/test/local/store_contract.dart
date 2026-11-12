import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/core/records.dart';
import 'package:wambito/crypto/records.dart';
import 'package:wambito/local/store.dart';

const _cat = '01930000-0000-7000-8000-00000000000a';

Json _category(String name) => {
  's': 1,
  'name': name,
  'kind': 'expense',
  'icon': 'x',
  'color': '#fff',
  'sortOrder': 0,
  'archivedAt': null,
  'systemKey': null,
};

Json _merchant(String key) => {'s': 1, 'merchantKey': key, 'categoryId': _cat};

/// What every [FinanceStore] must do; the memory and the SQLite store both run it.
void runStoreContract(String name, Future<FinanceStore> Function() open) {
  group('$name: the FinanceStore contract', () {
    test('puts, gets and lists per type, in first-written order', () async {
      final store = await open();
      await store.put(RecordType.category, 'b', _category('B'));
      await store.put(RecordType.category, 'a', _category('A'));
      await store.put(RecordType.merchant, 'm', _merchant('cafe'));
      expect((await store.get(RecordType.category, 'a'))?.body['name'], 'A');
      expect((await store.list(RecordType.category)).map((r) => r.id), ['b', 'a']);
      expect((await store.list(RecordType.merchant)).length, 1);
      expect(await store.get(RecordType.category, 'zzz'), isNull);
    });

    test('replaces on put, keeping the position', () async {
      final store = await open();
      await store.put(RecordType.category, 'a', _category('A'));
      await store.put(RecordType.category, 'b', _category('B'));
      await store.put(RecordType.category, 'a', _category('A2'));
      expect((await store.list(RecordType.category)).map((r) => r.body['name']), ['A2', 'B']);
    });

    test('does not share objects with the caller', () async {
      final store = await open();
      final body = _category('A');
      await store.put(RecordType.category, 'a', body);
      body['name'] = 'changed';
      final read = await store.get(RecordType.category, 'a');
      expect(read?.body['name'], 'A');
      read?.body['name'] = 'changed too';
      expect((await store.get(RecordType.category, 'a'))?.body['name'], 'A');
      final listed = await store.list(RecordType.category);
      listed.first.body['name'] = 'changed via list';
      expect((await store.get(RecordType.category, 'a'))?.body['name'], 'A');
    });

    test('does not share nested objects with the caller', () async {
      final store = await open();
      final body = <String, Object?>{
        's': 1,
        'tags': ['a'],
        'nested': {'k': 'v'},
      };
      await store.put(RecordType.settings, 's', body);
      (body['tags']! as List).add('b');
      (body['nested']! as Map)['k'] = 'changed';
      final read = await store.get(RecordType.settings, 's');
      expect(read?.body['tags'], ['a']);
      expect(read?.body['nested'], {'k': 'v'});
      (read!.body['tags']! as List).add('c');
      expect((await store.get(RecordType.settings, 's'))?.body['tags'], ['a']);
    });

    test('deletes to a tombstone that only includeDeleted shows, and a put revives it', () async {
      final store = await open();
      await store.put(RecordType.category, 'a', _category('A'));
      await store.delete(RecordType.category, 'a');
      expect(await store.get(RecordType.category, 'a'), isNull);
      expect(await store.list(RecordType.category), isEmpty);
      expect(
        (await store.get(
          RecordType.category,
          'a',
          const ReadOptions(includeDeleted: true),
        ))?.deleted,
        isTrue,
      );
      expect(
        (await store.list(RecordType.category, const ReadOptions(includeDeleted: true))).length,
        1,
      );
      final dead = await store.get(
        RecordType.category,
        'a',
        const ReadOptions(includeDeleted: true),
      );
      if (dead != null) await store.put(RecordType.category, 'a', dead.body);
      expect((await store.get(RecordType.category, 'a'))?.deleted, isFalse);
    });

    test('ignores deleting an unknown id', () async {
      final store = await open();
      await store.delete(RecordType.category, 'nope');
      expect(
        await store.list(RecordType.category, const ReadOptions(includeDeleted: true)),
        isEmpty,
      );
    });

    test("commits a transaction's writes together and lets it read its own writes", () async {
      final store = await open();
      await store.put(RecordType.category, 'a', _category('A'));
      final seen = await store.transaction((tx) async {
        await tx.put(RecordType.category, 'b', _category('B'));
        await tx.delete(RecordType.category, 'a');
        return (await tx.list(RecordType.category)).map((r) => r.id).toList();
      });
      expect(seen, ['b']);
      expect((await store.list(RecordType.category)).map((r) => r.id), ['b']);
    });

    test('rolls a failed transaction back', () async {
      final store = await open();
      await store.put(RecordType.category, 'a', _category('A'));
      await expectLater(
        store.transaction((tx) async {
          await tx.put(RecordType.category, 'b', _category('B'));
          await tx.delete(RecordType.category, 'a');
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );
      expect((await store.list(RecordType.category)).map((r) => r.id), ['a']);
    });

    test('runs transactions one after the other', () async {
      final store = await open();
      await store.put(RecordType.merchant, 'm', _merchant('0'));
      Future<void> bump() => store.transaction((tx) async {
        final current = int.parse(
          (await tx.get(RecordType.merchant, 'm'))!.body['merchantKey']! as String,
        );
        await Future<void>.value();
        await tx.put(RecordType.merchant, 'm', _merchant('${current + 1}'));
      });
      await Future.wait([bump(), bump(), bump()]);
      expect((await store.get(RecordType.merchant, 'm'))?.body['merchantKey'], '3');
    });

    test('notifies subscribers once per commit, not for a rollback, until unsubscribed', () async {
      final store = await open();
      var calls = 0;
      final off = store.subscribe(() => calls++);
      await store.put(RecordType.category, 'a', _category('A'));
      expect(calls, 1);
      await store.transaction((tx) async {
        await tx.put(RecordType.category, 'b', _category('B'));
        await tx.put(RecordType.category, 'c', _category('C'));
      });
      expect(calls, 2);
      await store.transaction((tx) async {
        await tx.put(RecordType.category, 'd', _category('D'));
        await tx.get(RecordType.category, 'd');
      });
      expect(calls, 3);
      await expectLater(
        store.transaction((tx) async {
          await tx.put(RecordType.category, 'e', _category('E'));
          throw StateError('no');
        }),
        throwsA(isA<StateError>()),
      );
      expect(calls, 3);
      off();
      await store.put(RecordType.category, 'f', _category('F'));
      expect(calls, 3);
    });

    test('does not notify for a transaction that only reads', () async {
      final store = await open();
      var calls = 0;
      store.subscribe(() => calls++);
      await store.transaction((tx) => tx.list(RecordType.category));
      expect(calls, 0);
    });
  });
}
