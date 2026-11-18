// The Dart twin of apps/web/app/local/stale-vaults.test.ts: the vaults of sessions that ended
// outside a sign-out are swept at sign-in and on a signed-out start.
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/local/db.dart'
    show VaultHold, VaultHoldKind, listVaultHolds, vaultFileName, vaultHoldOf;
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/key_storage.dart';
import 'package:wambito/local/stale_vaults.dart';
import 'package:wambito/local/vault_lock.dart' show vaultLockFileName;

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

  test('a vault that comes into use during the sweep is left alone', () async {
    // Another account signs in while the sweep runs and opens its leftover vault: it is asked
    // again right before each delete.
    await deleteStaleVaults(
      'ana',
      forget: forget,
      directory: () async => dir.path,
      inUse: (id) => id == 'bea',
    );
    expect(forgotten..sort(), ['cid', 'dan']);
    expect(files(), containsAll([vaultFileName('ana'), vaultFileName('bea')]));
    final left = await names();
    expect(left, containsAll(['wambito.vault.bea.current', 'wambito.encryption.bea']));
  });

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

  test('a vault whose only file left is its lock is swept too', () async {
    File(p.join(dir.path, vaultLockFileName('eve'))).writeAsStringSync('x');
    File(p.join(dir.path, '${vaultLockFileName('fay')}.claim-ab12')).writeAsStringSync('x');
    await sweep('bea');
    expect(forgotten, containsAll(['eve', 'fay']));
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

  group('holds', () {
    Future<void> hold(String id, VaultHold h) async {
      final store = await SqliteStore.open(id, directory: dir.path, factory: databaseFactoryFfi);
      await store.setHold(h);
      await store.close();
    }

    setUp(() {
      sqfliteFfiInit();
      // Real vault files for these (the setUp above wrote placeholders).
      for (final id in ['ana', 'bea', 'dan']) {
        File(p.join(dir.path, vaultFileName(id))).deleteSync();
      }
    });

    Future<VaultHold?> holdOf(String id) async {
      final all = await listVaultHolds(directory: dir.path, factory: databaseFactoryFfi);
      for (final h in all.holds) {
        if (h.userId == id) return h.hold;
      }
      return null;
    }

    test('a held vault and its wambito.vault.<id>.* keys survive the sweep', () async {
      await hold('bea', const VaultHold(VaultHoldKind.merging, target: 'e@x.test', since: 's'));
      await deleteStaleVaults(
        'ana',
        forget: forget,
        directory: () async => dir.path,
        holdOf: holdOf,
      );
      expect(forgotten, isNot(contains('bea')));
      expect(files(), contains(vaultFileName('bea')));
      expect(await names(), containsAll(['wambito.vault.bea.current', 'wambito.encryption.bea']));
    });

    test('an unheld one goes', () async {
      final store = await SqliteStore.open('bea', directory: dir.path, factory: databaseFactoryFfi);
      await store.close();
      await deleteStaleVaults(
        'ana',
        forget: forget,
        directory: () async => dir.path,
        holdOf: holdOf,
      );
      expect(forgotten, contains('bea'));
    });

    test('a vault whose hold cannot be read is left for the next time', () async {
      await deleteStaleVaults(
        'ana',
        forget: forget,
        directory: () async => dir.path,
        holdOf: (id) async => id == 'bea' ? throw StateError('unreadable') : null,
      );
      expect(forgotten, isNot(contains('bea')));
      expect(await names(), contains('wambito.vault.bea.current'));
      expect(forgotten, contains('cid'));
    });

    test(
      'listVaultHolds finds each held vault with its id and kind and skips unheld ones',
      () async {
        await hold('bea', const VaultHold(VaultHoldKind.orphaned, target: 'new', since: 's'));
        await hold('dan', const VaultHold(VaultHoldKind.provisional, since: 't'));
        final unheld = await SqliteStore.open(
          'ana',
          directory: dir.path,
          factory: databaseFactoryFfi,
        );
        await unheld.close();
        final all = await listVaultHolds(directory: dir.path, factory: databaseFactoryFfi);
        final byId = {for (final h in all.holds) h.userId: h.hold};
        expect(all.unreadable, isEmpty);
        expect(byId.keys.toSet(), {'bea', 'dan'});
        expect([byId['bea']?.kind, byId['bea']?.target], [VaultHoldKind.orphaned, 'new']);
        expect(byId['dan']?.kind, VaultHoldKind.provisional);
      },
    );

    test('the real vaultHoldOf throws on a corrupt file, so the sweep keeps it', () async {
      File(p.join(dir.path, vaultFileName('bea'))).writeAsStringSync('not a database');
      await hold('dan', const VaultHold(VaultHoldKind.provisional, since: 't'));
      // A malformed hold in a real vault.
      final bad = await SqliteStore.open('ana', directory: dir.path, factory: databaseFactoryFfi);
      await bad.setMeta('hold', {'kind': 'nope'});
      await bad.close();
      await deleteStaleVaults(
        'zed',
        forget: forget,
        directory: () async => dir.path,
        holdOf: (id) => vaultHoldOf(id, directory: dir.path, factory: databaseFactoryFfi),
      );
      expect(forgotten, isNot(containsAll(['bea'])));
      expect(forgotten, isNot(contains('ana')));
      expect(forgotten, isNot(contains('dan')));
      final listed = await listVaultHolds(directory: dir.path, factory: databaseFactoryFfi);
      expect(listed.unreadable..sort(), ['ana', 'bea']);
      expect(listed.holds.map((h) => h.userId), ['dan']);
    });
  });
}
