// A background engine opens its own connection (`singleInstance: false`): closing it must not close
// the app's, and both write the same file without `database is locked`.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/crypto/records.dart' show RecordType;
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

Future<void> _writes(SqliteStore s, String tag) async {
  for (var i = 0; i < 15; i++) {
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
    // The background engines are isolates with their own sqflite worker, as Android gives each
    // database its own thread: a connection waiting for the file's lock must not stop the one that
    // holds it from committing (the ffi worker of one isolate serves every connection of it).
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
    expect((await app.list(RecordType.category)).length, 45);
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

  test('notifyExternalChange tells the subscribers', () async {
    final app = await open();
    var heard = 0;
    app.subscribe(() => heard++);
    app.notifyExternalChange();
    expect(heard, 1);
    await app.close();
  });
}
