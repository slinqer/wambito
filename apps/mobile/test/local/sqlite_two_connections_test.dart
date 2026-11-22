// A background engine opens its own connection (`singleInstance: false`): closing it must not close
// the app's, and both write the same file without `database is locked`.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/crypto/records.dart' show RecordType;
import 'package:wambito/local/db.dart' show openVault;
import 'package:wambito/local/sqlite_store.dart';

const _id1 = '01930000-0000-7000-8000-000000000001';

Map<String, Object?> _cat(String name) => {
  's': 1,
  'name': name,
  'kind': 'expense',
  'icon': 'x',
  'color': '#fff',
  'sortOrder': 0,
  'archivedAt': null,
  'systemKey': null,
};

// Writes per connection. SQLite's lock has no queue: under heavy contention on a slow CI runner one
// waiter can lose every retry for longer than the store's wait (5 s). A few writes each still make
// the connections wait on one another, which is what this test is about.
const _perConnection = 5;

Future<void> _writes(SqliteStore s, String tag) async {
  for (var i = 0; i < _perConnection; i++) {
    await s.transaction((tx) async {
      final hex = tag.codeUnitAt(0).toRadixString(16).padLeft(2, '0');
      final id = '01930000-0000-7000-8000-${hex}00000000${i.toString().padLeft(2, '0')}';
      await tx.put(RecordType.category, id, _cat('$tag$i'));
    });
  }
}

void main() {
  sqfliteFfiInit();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('wambito-two'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<SqliteStore> open({bool background = false}) => SqliteStore.open(
    'ana',
    directory: dir.path,
    factory: databaseFactoryFfi,
    background: background,
  );

  test('concurrent writes on two background connections and the app one do not lock', () async {
    final path = dir.path;
    final app = await open();
    // The background engines are isolates with their own sqflite worker. On Android every
    // connection of the process shares sqflite's threads, so a waiter must not hold one for long:
    // `busy_timeout` is short and the store waits in Dart (`openVault`).
    final others = [
      for (final tag in ['b', 'c'])
        Isolate.run(() async {
          sqfliteFfiInit();
          final store = await SqliteStore.open(
            'ana',
            directory: path,
            factory: databaseFactoryFfi,
            background: true,
          );
          await _writes(store, tag);
          await store.close();
        }),
    ];
    await Future.wait([_writes(app, 'a'), ...others]);
    expect((await app.list(RecordType.category)).length, 3 * _perConnection);
    await app.close();
  });

  test('closing the background connection leaves the other usable', () async {
    final app = await open();
    final background = await open(background: true);
    await background.transaction((tx) async {
      await tx.put(RecordType.category, _id1, _cat('Food'));
    });
    await background.close();
    expect(app.isClosed, isFalse);
    expect((await app.list(RecordType.category)).length, 1);
    await app.transaction((tx) async {
      await tx.put(RecordType.category, _id1, _cat('Food 2'));
    });
    await app.close();
  });

  test('a write waits for another engine that holds the file for a second and a half', () async {
    // SQLite itself waits only `vaultBusyTimeout` (and under the Dart VM on Linux, the host tests on
    // CI, the signals the VM sends its threads cut even that short): the store waits in Dart.
    final path = dir.path;
    final app = await open();
    await app.put(RecordType.category, _id1, _cat('Food'));
    final held = ReceivePort();
    final heldPort = held.sendPort;
    final holder = Isolate.run(() async {
      sqfliteFfiInit();
      final db = await openVault(
        'ana',
        directory: path,
        factory: databaseFactoryFfi,
        singleInstance: false,
      );
      await db.execute('BEGIN IMMEDIATE');
      heldPort.send(true);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await db.execute('COMMIT');
      await db.close();
    });
    await held.first;
    final waited = Stopwatch()..start();
    await app.put(RecordType.category, _id1, _cat('Food 2'));
    expect(waited.elapsedMilliseconds, greaterThan(1000));
    expect((await app.get(RecordType.category, _id1))?.body['name'], 'Food 2');
    await holder;
    await app.close();
  });

  test('a connection left inside a transaction is recovered, then the app reads again', () async {
    // A headless engine destroyed mid-transaction: sqflite keeps its connection open, and its
    // write lock, for the life of the process. The app's store asks [recoverLock] once it gave up.
    final orphan = await openVault(
      'ana',
      directory: dir.path,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    var recovered = 0;
    final app = await SqliteStore.open(
      'ana',
      directory: dir.path,
      factory: databaseFactoryFfi,
      recoverLock: () async {
        recovered++;
        await orphan.close();
        return true;
      },
    );
    await orphan.execute('BEGIN IMMEDIATE');
    expect(await app.list(RecordType.category), isEmpty);
    expect(recovered, 1);
    await app.close();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('without a recovery the read still fails as before', () async {
    final orphan = await openVault(
      'ana',
      directory: dir.path,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    var asked = 0;
    final app = await SqliteStore.open(
      'ana',
      directory: dir.path,
      factory: databaseFactoryFfi,
      recoverLock: () async {
        asked++;
        return false;
      },
    );
    await orphan.execute('BEGIN IMMEDIATE');
    await expectLater(app.list(RecordType.category), throwsA(isA<DatabaseException>()));
    expect(asked, 1);
    await orphan.execute('ROLLBACK');
    await orphan.close();
    await app.close();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('notifyExternalChange tells the subscribers', () async {
    final app = await open();
    var heard = 0;
    app.subscribe(() => heard++);
    app.notifyExternalChange();
    expect(heard, 1);
    await app.close();
  });
}
