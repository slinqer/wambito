import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/core/records.dart';
import 'package:wambito/crypto/records.dart';
import 'package:wambito/local/db.dart' show pendingChangesInVault;
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/store.dart';

import 'store_contract.dart';

Json _category(String name, [String color = '#fff']) => {
  's': 1,
  'name': name,
  'kind': 'expense',
  'icon': 'x',
  'color': color,
  'sortOrder': 0,
  'archivedAt': null,
  'systemKey': null,
};

const _remote = WriteOptions(origin: 'remote', version: 3, keyV: 2);

WriteOptions _remoteAt(int version, int keyV) =>
    WriteOptions(origin: 'remote', version: version, keyV: keyV);

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory dir;
  var counter = 0;

  setUpAll(() => dir = Directory.systemTemp.createTempSync('wambito-vault-test'));
  tearDownAll(() => dir.deleteSync(recursive: true));

  String freshUser() => 'user-${++counter}';
  Future<SqliteStore> openFor(String userId) =>
      SqliteStore.open(userId, directory: dir.path, factory: factory);
  Future<SqliteStore> fresh() => openFor(freshUser());

  runStoreContract('sqlite', fresh);

  group('the outbox', () {
    test('readOutbox with a limit of zero or less reads nothing', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('A'));
      expect(await store.readOutbox(0), isEmpty);
      expect(await store.readOutbox(-1), isEmpty);
      expect(await store.readOutbox(1), hasLength(1));
    });

    test('calling the store from inside a transaction throws instead of deadlocking', () async {
      final store = await fresh();
      await expectLater(
        store.transaction((tx) async {
          await store.list(RecordType.category);
        }),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('transaction'))),
      );
      // The store still works afterwards.
      await store.put(RecordType.category, 'a', _category('A'));
      expect(await store.list(RecordType.category), hasLength(1));
    });

    test('adds an entry with every key on create, in the same commit as the record', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('A'));
      final entry = (await store.readOutbox(10)).single;
      expect(entry.id, 'a');
      expect(entry.type, RecordType.category);
      expect(entry.baseVersion, isNull);
      expect(entry.deleted, isFalse);
      expect([...entry.touched]..sort(), [..._category('A').keys]..sort());
    });

    test('merges later writes: union of touched fields, one entry per id, base kept', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('A'));
      await store.ackOutbox('a', 3, (await store.readOutbox(1)).first.seq);
      expect(await store.readOutbox(10), isEmpty);
      await store.put(RecordType.category, 'a', _category('A2'));
      await store.put(RecordType.category, 'a', _category('A2', '#000'));
      final entries = await store.readOutbox(10);
      expect(entries, hasLength(1));
      expect(entries.single.baseVersion, 3);
      expect(entries.single.deleted, isFalse);
      expect([...entries.single.touched]..sort(), ['color', 'name']);
    });

    test('a delete marks the entry deleted; a restore before the push clears it again', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('A'));
      await store.delete(RecordType.category, 'a');
      expect((await store.readOutbox(10)).first.deleted, isTrue);
      final dead = await store.get(
        RecordType.category,
        'a',
        const ReadOptions(includeDeleted: true),
      );
      if (dead != null) await store.put(RecordType.category, 'a', dead.body);
      expect((await store.readOutbox(10)).first.deleted, isFalse);
    });

    test('rolls the outbox back with a failed transaction', () async {
      final store = await fresh();
      await expectLater(
        store.transaction((tx) async {
          await tx.put(RecordType.category, 'a', _category('A'));
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );
      expect(await store.readOutbox(10), isEmpty);
      expect(await store.list(RecordType.category), isEmpty);
    });

    test(
      'writeAndOutboxAreAtomic: a put then a throw leaves both empty, also after reopening',
      () async {
        final userId = freshUser();
        final store = await openFor(userId);
        await expectLater(
          store.transaction((tx) async {
            await tx.put(RecordType.category, 'a', _category('A'));
            throw StateError('boom');
          }),
          throwsA(isA<StateError>()),
        );
        expect(await store.get(RecordType.category, 'a'), isNull);
        expect(await store.readOutbox(10), isEmpty);
        await store.close();
        final again = await openFor(userId);
        expect(
          await again.get(RecordType.category, 'a', const ReadOptions(includeDeleted: true)),
          isNull,
        );
        expect(await again.readOutbox(10), isEmpty);
        expect(await again.getMeta('seq'), isNull);
      },
    );

    test('keeps what was committed across a reopen', () async {
      final userId = freshUser();
      final store = await openFor(userId);
      await store.put(RecordType.category, 'a', _category('A'));
      await store.setMeta('latest', 42);
      await store.close();
      final again = await openFor(userId);
      expect((await again.get(RecordType.category, 'a'))?.body['name'], 'A');
      expect((await again.readOutbox(10)).single.id, 'a');
      expect(await again.getMeta('latest'), 42);
      // The write order survives too: the next first write comes after it.
      await again.put(RecordType.category, 'b', _category('B'));
      expect((await again.list(RecordType.category)).map((r) => r.id), ['a', 'b']);
    });

    test('limits and orders readOutbox by write order', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'b', _category('B'));
      await store.put(RecordType.category, 'a', _category('A'));
      await store.put(RecordType.category, 'b', _category('B2'));
      expect((await store.readOutbox(10)).map((e) => e.id), ['a', 'b']);
      expect((await store.readOutbox(1)).map((e) => e.id), ['a']);
    });

    test(
      'acks only the write that was read: a newer write keeps its entry, based on the version',
      () async {
        final store = await fresh();
        await store.put(RecordType.category, 'a', _category('A'));
        final read = (await store.readOutbox(10)).first;
        await store.put(RecordType.category, 'a', _category('A2'));
        await store.ackOutbox('a', 1, read.seq);
        expect((await store.rawRecord(RecordType.category, 'a'))?.version, 1);
        final left = (await store.readOutbox(10)).first;
        expect(left.id, 'a');
        expect(left.baseVersion, 1);
        await store.ackOutbox('a', 2, left.seq);
        expect(await store.readOutbox(10), isEmpty);
        expect((await store.rawRecord(RecordType.category, 'a'))?.version, 2);
      },
    );
  });

  group('remote writes', () {
    test('store the version and key version, add no outbox entry, and notify', () async {
      final store = await fresh();
      var calls = 0;
      store.subscribe(() => calls++);
      await store.put(
        RecordType.category,
        'a',
        _category('A'),
        const WriteOptions(origin: 'remote', version: 7, keyV: 2),
      );
      expect(await store.readOutbox(10), isEmpty);
      final raw = await store.rawRecord(RecordType.category, 'a');
      expect([raw?.version, raw?.keyV, raw?.deleted], [7, 2, false]);
      await store.delete(RecordType.category, 'a', _remoteAt(8, 2));
      expect(await store.readOutbox(10), isEmpty);
      final dead = await store.rawRecord(RecordType.category, 'a');
      expect([dead?.version, dead?.deleted], [8, true]);
      expect(calls, 2);
    });

    test('a local edit of a synced record is based on its server version', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('A'), _remoteAt(7, 1));
      await store.put(RecordType.category, 'a', _category('A2'));
      final entry = (await store.readOutbox(10)).single;
      expect(
        [entry.baseVersion, entry.touched, entry.deleted],
        [
          7,
          ['name'],
          false,
        ],
      );
    });
  });

  group('meta, quarantine, wipe', () {
    test('keeps meta values', () async {
      final store = await fresh();
      expect(await store.getMeta('latest'), isNull);
      await store.setMeta('latest', 42);
      expect(await store.getMeta('latest'), 42);
      await store.setMeta('shape', {
        'a': [1, 'b'],
      });
      expect(await store.getMeta('shape'), {
        'a': [1, 'b'],
      });
    });

    test('counts quarantined records, one per version, and never overwrites', () async {
      final store = await fresh();
      const q = QuarantineEntry(id: 'a', type: RecordType.category, version: 1, reason: 'bad');
      await store.quarantine(q);
      await store.quarantine(
        const QuarantineEntry(id: 'a', type: RecordType.category, version: 2, reason: 'bad again'),
      );
      await store.quarantine(
        const QuarantineEntry(id: 'a', type: RecordType.category, version: 2, reason: 'bad again'),
      );
      expect(await store.quarantineCount(), 2);
    });

    test(
      'a remote put or delete of a record clears its quarantine rows; a local write does not',
      () async {
        final store = await fresh();
        QuarantineEntry q(String id, RecordType type, int version) =>
            QuarantineEntry(id: id, type: type, version: version, reason: 'x', keyV: 2);
        await store.quarantine(q('a', RecordType.category, 1));
        await store.quarantine(q('a', RecordType.category, 2));
        await store.quarantine(q('b', RecordType.category, 1));
        await store.quarantine(q('c', RecordType.category, 1));
        await store.quarantine(q('a', RecordType.merchant, 1));
        await store.put(RecordType.category, 'c', _category('C'));
        expect(await store.quarantineCount(), 5);
        await store.put(RecordType.category, 'a', _category('A'), _remote);
        expect(await store.quarantineCount(), 3);
        // a tombstone of a record this phone never had
        await store.delete(RecordType.category, 'b', _remote);
        expect(await store.quarantineCount(), 2);
        expect((await store.quarantined()).map((e) => '${e.type.name}:${e.id}').toList()..sort(), [
          'category:c',
          'merchant:a',
        ]);
      },
    );

    test('wipes records, quarantine and the cursors, but not keyV, userId or outbox', () async {
      final store = await fresh();
      var calls = 0;
      await store.put(RecordType.category, 'a', _category('A'));
      await store.quarantine(
        const QuarantineEntry(id: 'q', type: RecordType.merchant, version: 1, reason: 'x'),
      );
      await store.setMeta('latest', 5);
      await store.setMeta('base', 4);
      await store.setMeta('keyV', 1);
      await store.setMeta('userId', 'u');
      store.subscribe(() => calls++);
      await store.wipeRecords();
      expect(
        await store.list(RecordType.category, const ReadOptions(includeDeleted: true)),
        isEmpty,
      );
      expect(await store.quarantineCount(), 0);
      expect(await store.getMeta('latest'), isNull);
      expect(await store.getMeta('base'), isNull);
      expect(await store.getMeta('keyV'), 1);
      expect(await store.getMeta('userId'), 'u');
      expect(calls, 1);
      // The pending change is set aside with its body, in the same commit as the wipe.
      final entry = (await store.readOutbox(10)).single;
      expect(entry.id, 'a');
      expect(entry.setAside?.body, _category('A'));
    });

    test('keeps a set-aside body up to date with writes made before it is restored', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('A'), _remoteAt(3, 1));
      await store.put(RecordType.category, 'a', _category('A', '#111'));
      await store.wipeRecords();
      await store.put(RecordType.category, 'a', _category('A2', '#111'));
      final entry = (await store.readOutbox(10)).first;
      expect(entry.setAside?.body, containsPair('name', 'A2'));
      expect(entry.setAside?.body, containsPair('color', '#111'));
      expect(entry.touched, containsAll(['color', 'name']));
    });

    test('restores set-aside changes in one commit, as the resolver decides', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('A', '#111'));
      await store.put(RecordType.category, 'b', _category('B'));
      await store.put(RecordType.category, 'c', _category('C'));
      await store.wipeRecords();
      await store.put(RecordType.category, 'a', _category('Server A'), _remoteAt(9, 1));
      await store.put(RecordType.category, 'b', _category('Server B'), _remoteAt(10, 1));
      var calls = 0;
      store.subscribe(() => calls++);
      final seen = <String>[];
      await store.restoreSetAside((entry, fresh) {
        seen.add('${entry.id}:${fresh?.version}');
        if (entry.id == 'a') return SetAsidePut({..._category('Server A'), 'color': '#111'});
        if (entry.id == 'b') return const SetAsideDelete();
        return const SetAsideDrop();
      });
      expect(seen..sort(), ['a:9', 'b:10', 'c:null']);
      expect(calls, 1);
      final outbox = await store.readOutbox(10);
      expect(outbox.map((e) => [e.id, e.baseVersion, e.deleted, e.setAside]), [
        ['a', 9, false, null],
        ['b', 10, true, null],
      ]);
      expect((await store.get(RecordType.category, 'a'))?.body['name'], 'Server A');
      expect((await store.get(RecordType.category, 'a'))?.body['color'], '#111');
      expect(await store.get(RecordType.category, 'b'), isNull);
      expect(await store.get(RecordType.category, 'c'), isNull);
    });
  });

  group('pending ids and parked changes', () {
    test('a remote write with skipIfPending leaves a record with a pending change alone', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('Local'));
      const remote = WriteOptions(origin: 'remote', version: 4, keyV: 1, skipIfPending: true);
      await store.transaction((tx) async {
        await tx.put(RecordType.category, 'a', _category('Server'), remote);
        await tx.put(RecordType.category, 'b', _category('Server B'), remote);
        await tx.delete(RecordType.category, 'a', remote);
      });
      final a = await store.rawRecord(RecordType.category, 'a');
      expect([a?.version, a?.deleted, a?.body['name']], [0, false, 'Local']);
      expect((await store.rawRecord(RecordType.category, 'b'))?.version, 4);
    });

    test('a remote write with ifSeq applies only while the outbox entry is that write', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('Local'));
      final seq = (await store.readOutbox(1)).first.seq;
      await store.put(
        RecordType.category,
        'a',
        _category('Merged'),
        WriteOptions(origin: 'remote', version: 2, ifSeq: seq),
      );
      var a = await store.rawRecord(RecordType.category, 'a');
      expect([a?.version, a?.body['name']], [2, 'Merged']);
      await store.put(RecordType.category, 'a', _category('Newer'));
      await store.put(
        RecordType.category,
        'a',
        _category('Stale'),
        WriteOptions(origin: 'remote', version: 3, ifSeq: seq),
      );
      a = await store.rawRecord(RecordType.category, 'a');
      expect([a?.version, a?.body['name']], [2, 'Newer']);
    });

    test('parks only the write that was read, and a later local write clears the park', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('A'));
      final seq = (await store.readOutbox(1)).first.seq;
      const park = OutboxPark(attempts: 1, lastError: 'rejected_422', until: 1000);
      await store.parkOutbox('a', seq, park);
      final parked = (await store.readOutbox(1)).first.park;
      expect([parked?.attempts, parked?.lastError, parked?.until], [1, 'rejected_422', 1000]);
      await store.put(RecordType.category, 'a', _category('A2'));
      expect((await store.readOutbox(1)).first.park, isNull);
      await store.parkOutbox('a', seq, park);
      expect((await store.readOutbox(1)).first.park, isNull);
    });

    test(
      'abandons only the write that was read; a remote write then replaces it and the entry goes',
      () async {
        final store = await fresh();
        await store.put(RecordType.category, 'a', _category('A'));
        final seq = (await store.readOutbox(1)).first.seq;
        const park = OutboxPark(attempts: 5, lastError: 'rejected_422', until: 9);
        await store.abandonOutbox('a', seq + 1, park);
        expect((await store.readOutbox(1)).first.abandoned, isFalse);
        await store.abandonOutbox('a', seq, park);
        final entry = (await store.readOutbox(1)).first;
        expect([entry.abandoned, entry.park?.attempts], [true, 5]);
        // An abandoned change does not hold back a pull that skips pending ids.
        await store.put(
          RecordType.category,
          'a',
          _category('Server'),
          const WriteOptions(origin: 'remote', version: 6, keyV: 1, skipIfPending: true),
        );
        expect((await store.get(RecordType.category, 'a'))?.body['name'], 'Server');
        expect(await store.readOutbox(10), isEmpty);
      },
    );
  });

  group('adopting the server copy of a create that lost', () {
    const server = ServerCopy(version: 4, keyV: 2, body: {'s': 1, 'name': 'Server'});

    test(
      'without a newer local write the server copy replaces the record and the entry goes',
      () async {
        final store = await fresh();
        var calls = 0;
        await store.put(RecordType.category, 'a', _category('Mine'));
        final seq = (await store.readOutbox(1)).first.seq;
        store.subscribe(() => calls++);
        await store.adoptServerCopy(
          RecordType.category,
          'a',
          seq,
          server,
          (_) => throw StateError('no rebase needed'),
        );
        final raw = await store.rawRecord(RecordType.category, 'a');
        expect([raw?.version, raw?.keyV, raw?.body['name']], [4, 2, 'Server']);
        expect(await store.readOutbox(10), isEmpty);
        expect(calls, 1);
      },
    );

    test('with a newer local write the server copy becomes the base and rebase decides', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('Mine'));
      final seq = (await store.readOutbox(1)).first.seq;
      await store.put(RecordType.category, 'a', _category('Mine 2'));
      await store.adoptServerCopy(
        RecordType.category,
        'a',
        seq,
        server,
        (local) => (body: {...server.body, 'name': local!['name']}, touched: ['name']),
      );
      final raw = await store.rawRecord(RecordType.category, 'a');
      expect([raw?.version, raw?.body['name']], [4, 'Mine 2']);
      final entry = (await store.readOutbox(10)).single;
      expect(
        [entry.baseVersion, entry.touched],
        [
          4,
          ['name'],
        ],
      );
      // Nothing left to push: the entry goes.
      await store.put(RecordType.category, 'b', _category('B'));
      final bSeq = (await store.readOutbox(10)).firstWhere((e) => e.id == 'b').seq;
      await store.put(RecordType.category, 'b', _category('B2'));
      await store.adoptServerCopy(
        RecordType.category,
        'b',
        bSeq,
        server,
        (local) => (body: server.body, touched: <String>[]),
      );
      expect((await store.readOutbox(10)).map((e) => e.id), ['a']);
    });

    test('deleted since: the delete is pushed as an edit of the server copy', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('Mine'));
      final seq = (await store.readOutbox(1)).first.seq;
      await store.delete(RecordType.category, 'a');
      await store.adoptServerCopy(
        RecordType.category,
        'a',
        seq,
        server,
        (_) => throw StateError('not called for a delete'),
      );
      expect(await store.get(RecordType.category, 'a'), isNull);
      final raw = await store.rawRecord(RecordType.category, 'a');
      expect([raw?.version, raw?.deleted], [4, true]);
      final entry = (await store.readOutbox(10)).single;
      expect([entry.deleted, entry.baseVersion, entry.touched], [true, 4, <String>[]]);
    });
  });

  group('re-sealing under a new key version', () {
    test('queues the pushed records under an older keyV, up to the limit, and a local write makes one an edit', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('A'), _remoteAt(1, 1));
      await store.put(RecordType.category, 'b', _category('B'), _remoteAt(2, 1));
      await store.put(RecordType.category, 'c', _category('C'), _remoteAt(3, 2));
      await store.put(RecordType.category, 'd', _category('D')); // never pushed
      await store.put(RecordType.category, 'e', _category('E'), _remoteAt(4, 1));
      await store.delete(RecordType.category, 'e', _remoteAt(5, 1)); // a tombstone has no body
      expect(await store.keyVersionsInUse(), {1, 2});
      // a quarantined record may still be retried under its key version
      await store.quarantine(
        const QuarantineEntry(id: 'q', type: RecordType.category, version: 9, reason: 'x', keyV: 5),
      );
      expect(await store.keyVersionsInUse(), {1, 2, 5});
      expect(await store.queueReseal(2, 1), 1);
      expect(await store.queueReseal(2, 1), 0); // one pending already fills the limit
      expect(await store.queueReseal(2, 5), 1);
      final reseals = (await store.readOutbox(10)).where((e) => e.reseal).toList();
      expect(
        (reseals.map((e) => [e.id, e.baseVersion, e.touched]).toList()
          ..sort((x, y) => (x[0]! as String).compareTo(y[0]! as String))),
        [
          ['a', 1, <String>[]],
          ['b', 2, <String>[]],
        ],
      );
      // Acked under keyV 2: the record is under 2 now.
      await store.ackOutbox('a', 6, reseals.firstWhere((e) => e.id == 'a').seq, 2);
      final a = await store.rawRecord(RecordType.category, 'a');
      expect([a?.version, a?.keyV], [6, 2]);
      // The person edits b before its re-seal went: an ordinary edit, based on the same version.
      await store.put(RecordType.category, 'b', _category('B2'));
      final b = (await store.readOutbox(10)).firstWhere((e) => e.id == 'b');
      expect(
        [b.baseVersion, b.touched],
        [
          2,
          ['name'],
        ],
      );
      expect(b.reseal, isFalse);
    });
  });

  group('closing and deleting the vault', () {
    test('close fires onClosed once, then every operation rejects with VaultClosedError', () async {
      final store = await fresh();
      var closed = 0;
      store.onClosed(() => closed++);
      await store.put(RecordType.category, 'a', _category('A'));
      expect(store.isClosed, isFalse);
      await store.close();
      await store.close();
      expect(closed, 1);
      expect(store.isClosed, isTrue);
      await expectLater(
        store.list(RecordType.category),
        throwsA(isA<VaultClosedError>().having((e) => e.code, 'code', 'vault_closed')),
      );
      await expectLater(store.readOutbox(1), throwsA(isA<VaultClosedError>()));
      await expectLater(store.getMeta('x'), throwsA(isA<VaultClosedError>()));
    });

    test('deleteVault removes the file, the records and the outbox', () async {
      final userId = freshUser();
      final store = await openFor(userId);
      await store.put(RecordType.category, 'a', _category('A'));
      await store.close();
      final file = File(p.join(dir.path, vaultFileName(userId)));
      expect(file.existsSync(), isTrue);
      await deleteVault(userId, directory: dir.path, factory: factory);
      expect(file.existsSync(), isFalse);
      final again = await openFor(userId);
      expect(await again.list(RecordType.category), isEmpty);
      expect(await again.readOutbox(10), isEmpty);
    });

    test('deleteVault also removes the SQLite side files a crash can leave', () async {
      // A stale `-wal` or `-journal` next to a new file of the same name would be replayed into it.
      final userId = freshUser();
      final store = await openFor(userId);
      await store.put(RecordType.category, 'a', _category('A'));
      await store.close();
      final path = p.join(dir.path, vaultFileName(userId));
      for (final side in ['-wal', '-shm', '-journal']) {
        File('$path$side').writeAsStringSync('left by a crash');
      }
      await deleteVault(userId, directory: dir.path, factory: factory);
      for (final side in ['', '-wal', '-shm', '-journal']) {
        expect(File('$path$side').existsSync(), isFalse, reason: side);
      }
    });

    test(
      'the file is in WAL mode: a commit holds the write lock for one sync, not three',
      () async {
        final userId = freshUser();
        final store = await openFor(userId);
        await store.put(RecordType.category, 'a', _category('A'));
        final raw = await factory.openDatabase(
          p.join(dir.path, vaultFileName(userId)),
          options: OpenDatabaseOptions(singleInstance: false),
        );
        expect((await raw.rawQuery('PRAGMA journal_mode')).first.values.first, 'wal');
        await raw.close();
        await store.close();
      },
    );

    test('names the file after the account', () {
      expect(vaultFileName('u1'), 'wambito-vault-u1.db');
    });
  });

  group('indexed transaction columns', () {
    test('are filled from the body and follow an edit', () async {
      final userId = freshUser();
      final store = await openFor(userId);
      Json tx(int amount, String date, String cat) => {
        's': 1,
        'amount': amount,
        'date': date,
        'categoryId': cat,
      };
      await store.put(RecordType.transaction, 't', tx(-1250, '2026-11-01', 'c1'));
      await store.put(RecordType.transaction, 't', tx(-900, '2026-11-02', 'c2'));
      await store.close();
      final db = await factory.openDatabase(p.join(dir.path, vaultFileName(userId)));
      final rows = await db.query('"transaction"');
      await db.close();
      expect(rows.single['date'], '2026-11-02');
      expect(rows.single['category_id'], 'c2');
      expect(rows.single['amount'], -900);
    });
  });

  group('a remote tombstone with a body', () {
    WriteOptions remote(int version, int keyV, {Json? body, bool skipIfPending = false}) =>
        WriteOptions(
          origin: 'remote',
          version: version,
          keyV: keyV,
          tombstoneBody: body,
          skipIfPending: skipIfPending,
        );

    test('a remote delete with tombstoneBody creates a tombstone for an unknown id', () async {
      final store = await fresh();
      var calls = 0;
      store.subscribe(() => calls++);
      await store.delete(RecordType.category, 'z', remote(6, 3, body: _category('Gone')));
      expect(await store.get(RecordType.category, 'z'), isNull);
      final dead = await store.get(
        RecordType.category,
        'z',
        const ReadOptions(includeDeleted: true),
      );
      expect([dead?.deleted, dead?.body['name']], [true, 'Gone']);
      final raw = await store.rawRecord(RecordType.category, 'z');
      expect([raw?.deleted, raw?.version, raw?.keyV, raw?.bodiless], [true, 6, 3, false]);
      expect(await store.readOutbox(10), isEmpty);
      expect(calls, 1);
    });

    test('a remote delete without tombstoneBody still writes nothing for an unknown id', () async {
      final store = await fresh();
      await store.delete(RecordType.category, 'z', remote(6, 3));
      expect(await store.rawRecord(RecordType.category, 'z'), isNull);
    });

    test("a remote delete with tombstoneBody replaces the local tombstone's body", () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('Old'), _remoteAt(1, 1));
      await store.delete(RecordType.category, 'a', remote(2, 2, body: _category('Server')));
      final raw = await store.rawRecord(RecordType.category, 'a');
      expect(
        [raw?.deleted, raw?.version, raw?.keyV, raw?.body['name'], raw?.bodiless],
        [true, 2, 2, 'Server', false],
      );
      expect(await store.readOutbox(10), isEmpty);
    });

    test(
      'a remote delete with tombstoneBody and skipIfPending leaves a pending local change alone',
      () async {
        final store = await fresh();
        await store.put(RecordType.category, 'a', _category('Local'));
        await store.delete(
          RecordType.category,
          'a',
          remote(4, 1, body: _category('Server'), skipIfPending: true),
        );
        await store.delete(
          RecordType.category,
          'b',
          remote(4, 1, body: _category('Server B'), skipIfPending: true),
        );
        final a = await store.rawRecord(RecordType.category, 'a');
        expect([a?.version, a?.deleted, a?.body['name']], [0, false, 'Local']);
        final b = await store.rawRecord(RecordType.category, 'b');
        expect([b?.deleted, b?.version], [true, 4]);
      },
    );

    test('a local delete ignores tombstoneBody', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('Mine'));
      await store.delete(RecordType.category, 'a', WriteOptions(tombstoneBody: _category('Other')));
      expect((await store.rawRecord(RecordType.category, 'a'))?.body['name'], 'Mine');
    });

    test('keyVersionsInUse counts a pushed tombstone with a body', () async {
      final store = await fresh();
      await store.delete(RecordType.category, 'z', remote(3, 4, body: _category('Gone')));
      expect(await store.keyVersionsInUse(), {4});
    });

    test('keyVersionsInUse does not count a pushed tombstone without a body', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('A'), _remoteAt(1, 1));
      await store.delete(RecordType.category, 'a', remote(2, 7));
      expect(await store.keyVersionsInUse(), <int>{});
      expect((await store.rawRecord(RecordType.category, 'a'))?.bodiless, isTrue);
    });

    test('queueReseal queues a pushed tombstone with a body under an older key, and its entry is a delete', () async {
      final store = await fresh();
      await store.delete(RecordType.category, 'z', remote(3, 1, body: _category('Gone')));
      await store.put(RecordType.category, 'y', _category('Y'), _remoteAt(1, 1));
      await store.delete(RecordType.category, 'y', remote(2, 1)); // no body: nothing to re-seal
      expect(await store.queueReseal(2, 5), 1);
      final entries = await store.readOutbox(10);
      expect(entries.map((e) => [e.id, e.reseal, e.baseVersion, e.deleted]).toList(), [
        ['z', true, 3, true],
      ]);
      final z = await store.get(RecordType.category, 'z', const ReadOptions(includeDeleted: true));
      expect(z?.deleted, isTrue);
      // Acked under the current key: it is no longer queued.
      await store.ackOutbox('z', 4, entries.first.seq, 2);
      expect(await store.queueReseal(2, 5), 0);
    });

    test('an acked delete of a tombstone the server held without a body counts its key', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('A'), _remoteAt(1, 1));
      await store.delete(RecordType.category, 'a', remote(2, 3)); // the server's has no body
      expect(await store.keyVersionsInUse(), <int>{});
      // The person's delete wins: put, then a local delete, pushed with the body.
      await store.put(RecordType.category, 'a', _category('Mine'));
      await store.delete(RecordType.category, 'a');
      final entry = (await store.readOutbox(10)).single;
      await store.ackOutbox('a', 3, entry.seq, 4, true);
      expect(await store.keyVersionsInUse(), {4});
    });

    test('an ack keeps a tombstone bodiless unless the push carried a body', () async {
      final store = await fresh();
      for (final id in ['a', 'b']) {
        await store.put(RecordType.category, id, _category('Old'), _remoteAt(1, 1));
        // A pending edit, then the server's tombstone without a body over it.
        await store.put(RecordType.category, id, _category('Mine'));
        await store.delete(RecordType.category, id, remote(2, 1));
        expect((await store.rawRecord(RecordType.category, id))?.bodiless, isTrue);
      }
      final entries = await store.readOutbox(10);
      int seq(String id) => entries.firstWhere((e) => e.id == id).seq;
      await store.ackOutbox('a', 3, seq('a'), 2);
      await store.ackOutbox('b', 3, seq('b'), 3, false);
      for (final id in ['a', 'b']) {
        final raw = await store.rawRecord(RecordType.category, id);
        expect([raw?.version, raw?.bodiless], [3, true], reason: id);
      }
      expect(await store.keyVersionsInUse(), <int>{});
      expect(await store.queueReseal(5, 10), 0);
      expect(await store.readOutbox(10), isEmpty);

      // A push that carried the body: the server's tombstone holds it now.
      await store.put(RecordType.category, 'c', _category('Old'), _remoteAt(4, 1));
      await store.put(RecordType.category, 'c', _category('Mine'));
      await store.delete(RecordType.category, 'c', remote(5, 1));
      final c = (await store.readOutbox(10)).single;
      await store.ackOutbox('c', 6, c.seq, 4, true);
      expect((await store.rawRecord(RecordType.category, 'c'))?.bodiless, isFalse);
      expect(await store.keyVersionsInUse(), {4});
    });

    test(
      'a remote delete with tombstoneBody and ifSeq does nothing after a newer local write',
      () async {
        final store = await fresh();
        await store.put(RecordType.category, 'a', _category('Old'), _remoteAt(1, 1));
        await store.put(RecordType.category, 'a', _category('Local'));
        final read = (await store.readOutbox(1)).single;
        await store.put(RecordType.category, 'a', _category('Newer'));
        await store.delete(
          RecordType.category,
          'a',
          WriteOptions(
            origin: 'remote',
            version: 2,
            keyV: 1,
            ifSeq: read.seq,
            tombstoneBody: _category('Server'),
          ),
        );
        final raw = await store.rawRecord(RecordType.category, 'a');
        expect([raw?.deleted, raw?.version, raw?.body['name']], [false, 1, 'Newer']);
        expect((await store.readOutbox(1)).single.seq, greaterThan(read.seq));
      },
    );

    test('an ack of a push that carried the body clears a bodiless tombstone\'s flag', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('A'), _remoteAt(1, 1));
      // The person's delete meets the server's tombstone: the engine stores the server's copy
      // (a put, then a delete without a body) and the person's entry stays, to be pushed again.
      await store.delete(RecordType.category, 'a');
      await store.transaction((tx) async {
        await tx.put(RecordType.category, 'a', _category('A'), _remoteAt(3, 1));
        await tx.delete(RecordType.category, 'a', remote(3, 1));
      });
      expect((await store.rawRecord(RecordType.category, 'a'))?.bodiless, isTrue);
      final entry = (await store.readOutbox(10)).single;
      await store.ackOutbox('a', 4, entry.seq, 2, true);
      expect((await store.rawRecord(RecordType.category, 'a'))?.bodiless, isFalse);
      expect(await store.keyVersionsInUse(), {2});
    });

    test('a remote delete without a body of a tombstone that holds one keeps it', () async {
      final store = await fresh();
      await store.delete(RecordType.category, 'z', remote(3, 1, body: _category('Gone')));
      await store.delete(RecordType.category, 'z', remote(3, 1));
      final raw = await store.rawRecord(RecordType.category, 'z');
      expect([raw?.bodiless, raw?.body['name']], [false, 'Gone']);
    });

    test('a bodiless tombstone takes the server body, and a put clears the flag', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('Old'), _remoteAt(1, 1));
      await store.delete(RecordType.category, 'a', remote(2, 1));
      await store.delete(RecordType.category, 'a', remote(2, 1, body: _category('Server')));
      final raw = await store.rawRecord(RecordType.category, 'a');
      expect([raw?.bodiless, raw?.body['name']], [false, 'Server']);
      await store.put(RecordType.category, 'b', _category('B'), _remoteAt(1, 1));
      await store.delete(RecordType.category, 'b', remote(2, 1));
      await store.put(RecordType.category, 'b', _category('Back'), _remoteAt(3, 1));
      await store.delete(RecordType.category, 'b');
      expect((await store.rawRecord(RecordType.category, 'b'))?.bodiless, isFalse);
    });

    test('queueReseal shares its limit between records and tombstones', () async {
      final store = await fresh();
      await store.put(RecordType.category, 'a', _category('A'), _remoteAt(1, 1));
      await store.delete(RecordType.category, 'z', remote(3, 1, body: _category('Gone')));
      expect(await store.queueReseal(2, 1), 1);
      expect(await store.queueReseal(2, 1), 0);
    });
  });

  group('the version 2 upgrade', () {
    // The schema the version 1 app made: the records tables have no `bodiless` column.
    Future<String> version1File(String userId) async {
      final path = p.join(dir.path, vaultFileName(userId));
      final db = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            for (final type in RecordType.values) {
              final extra = type == RecordType.transaction
                  ? ', date TEXT, category_id TEXT, amount INTEGER'
                  : '';
              await db.execute(
                'CREATE TABLE "${type.name}" (id TEXT PRIMARY KEY, seq INTEGER NOT NULL, '
                'body TEXT NOT NULL, deleted INTEGER NOT NULL, version INTEGER NOT NULL, '
                'key_v INTEGER NOT NULL$extra)',
              );
            }
            await db.execute(
              'CREATE TABLE outbox (id TEXT PRIMARY KEY, type TEXT NOT NULL, base_version INTEGER, '
              'deleted INTEGER NOT NULL, touched TEXT NOT NULL, seq INTEGER NOT NULL, park TEXT, '
              'abandoned INTEGER NOT NULL, set_aside TEXT, reseal INTEGER NOT NULL)',
            );
            await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)');
            await db.execute(
              'CREATE TABLE quarantine (type TEXT NOT NULL, id TEXT NOT NULL, '
              'version INTEGER NOT NULL, reason TEXT NOT NULL, key_v INTEGER, '
              'PRIMARY KEY (type, id, version))',
            );
          },
          singleInstance: false,
        ),
      );
      Map<String, Object?> row(String id, bool deleted, int seq) => {
        'id': id,
        'seq': seq,
        'body': '{"s":1,"name":"$id"}',
        'deleted': deleted ? 1 : 0,
        'version': 2,
        'key_v': 1,
      };
      await db.insert('category', row('live', false, 1));
      await db.insert('category', row('dead', true, 2));
      await db.insert('category', row('kept', false, 5));
      await db.insert('"transaction"', {
        ...row('t', true, 3),
        'body': '{"s":1,"amount":-500,"date":"2026-11-01","categoryId":"live"}',
        'date': '2026-11-01',
        'category_id': 'live',
        'amount': -500,
      });
      await db.insert('outbox', {
        'id': 'live',
        'type': 'category',
        'base_version': 2,
        'deleted': 0,
        'touched': '["name"]',
        'seq': 4,
        'abandoned': 0,
        'reseal': 0,
      });
      await db.insert('meta', {'key': 'seq', 'value': '5'});
      await db.close();
      return path;
    }

    test('marks every tombstone of a version 1 file as without a server body', () async {
      final userId = freshUser();
      await version1File(userId);
      expect(
        await pendingChangesInVault(userId, directory: dir.path, factory: factory),
        1,
        reason: 'the read-only count works on a version 1 file',
      );
      final store = await openFor(userId);
      final live = await store.rawRecord(RecordType.category, 'live');
      expect([live?.deleted, live?.bodiless, live?.body['name']], [false, false, 'live']);
      final dead = await store.rawRecord(RecordType.category, 'dead');
      expect([dead?.deleted, dead?.bodiless, dead?.body['name']], [true, true, 'dead']);
      final t = await store.rawRecord(RecordType.transaction, 't');
      expect([t?.deleted, t?.bodiless, t?.body['amount']], [true, true, -500]);
      // Nothing else changed: the outbox, the meta and the order of the records.
      expect((await store.readOutbox(10)).map((e) => [e.id, e.seq, e.touched]).toList(), [
        [
          'live',
          4,
          ['name'],
        ],
      ]);
      expect(await store.getMeta('seq'), 5);
      // The live records only: a tombstone of a version 1 file has no body on the server.
      expect(await store.keyVersionsInUse(), {1});
      expect(await store.queueReseal(2, 10), 1);
      expect((await store.readOutbox(10)).where((e) => e.reseal).map((e) => e.id), ['kept']);
      await store.close();
      expect(await pendingChangesInVault(userId, directory: dir.path, factory: factory), 1);
      // Opened again: already version 2, the flags stay as they are.
      final again = await openFor(userId);
      expect((await again.rawRecord(RecordType.category, 'dead'))?.bodiless, isTrue);
      await again.close();
    });

    test('marks the tombstones of a version 2 file a version 1 build reopened', () async {
      final userId = freshUser();
      final path = await version1File(userId);
      await (await openFor(userId)).close();
      // A version 1 build opened it again: the file says version 1, keeps `bodiless`, and that
      // build wrote a tombstone without setting it.
      final db = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await db.setVersion(1);
      await db.update('category', {'deleted': 1}, where: 'id = ?', whereArgs: ['kept']);
      await db.close();
      final store = await openFor(userId);
      for (final id in ['dead', 'kept']) {
        expect((await store.rawRecord(RecordType.category, id))?.bodiless, isTrue, reason: id);
      }
      expect((await store.rawRecord(RecordType.category, 'live'))?.bodiless, isFalse);
      await store.close();
    });
  });
}
