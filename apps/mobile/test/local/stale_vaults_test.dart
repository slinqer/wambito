// The Dart twin of apps/web/app/local/stale-vaults.test.ts: the vaults of sessions that ended
// outside a sign-out are swept at sign-in and on a signed-out start.
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wambito/local/db.dart' show vaultFileName;
import 'package:wambito/local/key_storage.dart';
import 'package:wambito/local/stale_vaults.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late KeyStorage keys;
  final forgotten = <String>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wambito-stale');
    forgotten.clear();
    FlutterSecureStorage.setMockInitialValues({
      'session.token': 't',
      'wambito.vault.ana.dk.1': 'AAAA',
      'wambito.vault.ana.current': '1',
      'wambito.encryption.ana': 'preview',
      'wambito.vault.bea.current': '1',
      'wambito.vault.bea.device': 'BBBB',
      'wambito.encryption.bea': 'preview',
      'wambito.encryption.cid': 'plain',
      'wambito.account': '{"owner":"x","id":"ana","email":"ana@wambito.test"}',
    });
    keys = KeyStorage(const FlutterSecureStorage());
    for (final id in ['ana', 'bea', 'dan']) {
      File(p.join(dir.path, vaultFileName(id))).writeAsStringSync('x');
    }
    File(p.join(dir.path, 'something-else.db')).writeAsStringSync('x');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Deletes the file and the keys, as forgetVault does.
  Future<void> forget(String id) async {
    forgotten.add(id);
    final file = File(p.join(dir.path, vaultFileName(id)));
    if (file.existsSync()) file.deleteSync();
    await keys.deleteAll(id);
  }

  Future<void> sweep(String? keep) =>
      deleteStaleVaults(keep, forget: forget, directory: () async => dir.path);

  List<String> files() => (dir.listSync().map((f) => p.basename(f.path)).toList())..sort();
  Future<List<String>> names() async =>
      (await const FlutterSecureStorage().readAll()).keys.toList()..sort();

  test('signed out: deletes every vault, its keys and what was kept, and only those', () async {
    await sweep(null);
    expect(files(), ['something-else.db']);
    expect(forgotten..sort(), ['ana', 'bea', 'cid', 'dan']);
    expect(await names(), ['session.token']);
  });

  test("signed in: keeps the signed-in person's vault, deletes the others", () async {
    await sweep('bea');
    expect(files(), ['something-else.db', vaultFileName('bea')]..sort());
    expect(await names(), [
      'session.token',
      'wambito.encryption.bea',
      'wambito.vault.bea.current',
      'wambito.vault.bea.device',
    ]);
  });

  test('keeps the kept account when it is the one kept', () async {
    await sweep('ana');
    expect(files(), ['something-else.db', vaultFileName('ana')]..sort());
    expect(await names(), [
      'session.token',
      'wambito.account',
      'wambito.encryption.ana',
      'wambito.vault.ana.current',
      'wambito.vault.ana.dk.1',
    ]);
  });

  test('a folder that cannot be listed still sweeps the keys', () async {
    await deleteStaleVaults(
      'bea',
      forget: forget,
      directory: () async => throw const FileSystemException('denied'),
    );
    expect(forgotten..sort(), ['ana', 'cid']);
    expect((await names()).where((n) => n.contains('ana')), isEmpty);
  });

  test('never throws: a failed delete is left for the next time', () async {
    await expectLater(
      deleteStaleVaults(
        null,
        forget: (id) async => throw StateError('locked'),
        directory: () async => dir.path,
      ),
      completes,
    );
    // What the forget could not delete stays; the kept mode and account still go.
    expect(await names(), contains('wambito.vault.ana.current'));
    expect(await names(), isNot(contains('wambito.account')));
  });
}
