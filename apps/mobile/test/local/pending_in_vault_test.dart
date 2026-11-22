// Counting a kept vault's unsent changes from its file, without opening the vault (Unlock, Locked).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/crypto/records.dart' show RecordType;
import 'package:wambito/local/db.dart';
import 'package:wambito/local/sqlite_store.dart';

void main() {
  late Directory dir;
  setUpAll(sqfliteFfiInit);
  setUp(() => dir = Directory.systemTemp.createTempSync('wambito-pending'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<int> count(String userId) =>
      pendingChangesInVault(userId, directory: dir.path, factory: databaseFactoryFfi);

  test('no file: nothing', () async {
    expect(await count('ana'), 0);
    expect(dir.listSync(), isEmpty, reason: 'counting creates no file');
  });

  test("counts the person's changes in the file, the store closed or still open", () async {
    final store = await SqliteStore.open('ana', directory: dir.path, factory: databaseFactoryFfi);
    await store.put(RecordType.category, 'c1', {'s': 1, 'name': 'Pets'});
    await store.put(RecordType.category, 'c2', {'s': 1, 'name': 'Food'});
    expect(await count('ana'), 2);
    await store.close();
    expect(await count('ana'), 2);
    expect(await count('bea'), 0);
  });
}
