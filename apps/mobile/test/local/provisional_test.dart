// The offline first run's vault (phone-first spec 4, ruling 8): a local id, held `provisional`,
// seeded from the phone's hints, and kept by the stale-vault sweep. Real SQLite in a temp dir.
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/api/device.dart';
import 'package:wambito/crypto/records.dart' show RecordType;
import 'package:wambito/local/db.dart' show VaultHoldKind, vaultFileName, vaultHoldOf;
import 'package:wambito/local/provisional.dart';
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/stale_vaults.dart';

const _hints = DeviceHints(timezone: 'America/Bogota', locale: 'en-GB');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('wambito-provisional');
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<LocalOnlyVault> open(String id) => openProvisionalVault(
    id,
    _hints,
    directory: dir.path,
    factory: databaseFactoryFfi,
    now: () => DateTime.utc(2026, 11, 18, 9),
  );

  bool fileOf(String id) => File(p.join(dir.path, vaultFileName(id))).existsSync();

  test('newProvisionalId matches the vault file pattern', () {
    final id = newProvisionalId();
    expect(id, startsWith('local-'));
    expect(RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id), isTrue);
    expect(
      RegExp(r'^wambito-vault-([A-Za-z0-9_-]{1,128})\.db$').hasMatch(vaultFileName(id)),
      isTrue,
    );
    expect(newProvisionalId(), isNot(id));
  });

  test('openProvisionalVault holds the vault provisional and seeds it from the hints', () async {
    final id = newProvisionalId();
    final vault = await open(id);
    expect(vault.localId, id);
    final settings = await vault.store.list(RecordType.settings);
    expect(settings, hasLength(1));
    expect(settings.single.body['locale'], 'en');
    expect(settings.single.body['timezone'], 'America/Bogota');
    expect(await vault.store.list(RecordType.category), isNotEmpty);
    await vault.close();

    final hold = await vaultHoldOf(id, directory: dir.path, factory: databaseFactoryFfi);
    expect(hold?.kind, VaultHoldKind.provisional);
    expect(hold?.since, '2026-11-18T09:00:00.000Z');
    // Nothing waits to be pushed: the vault has no user, no keys, no sync.
    final store = await SqliteStore.open(id, directory: dir.path, factory: databaseFactoryFfi);
    expect(await store.list(RecordType.transaction), isEmpty);
    await store.close();
  });

  test('reopening the same id opens the same vault and seeds nothing twice', () async {
    final id = newProvisionalId();
    final first = await open(id);
    final categories = (await first.store.list(RecordType.category)).length;
    final settingsId = (await first.store.list(RecordType.settings)).single.id;
    await first.store.put(RecordType.transaction, '01930000-0000-7000-8000-0000000000a1', {
      's': 1,
      'amountCents': -1250,
    });
    await first.close();

    final again = await open(id);
    expect((await again.store.list(RecordType.settings)).map((r) => r.id), [settingsId]);
    expect(await again.store.list(RecordType.category), hasLength(categories));
    expect(await again.store.list(RecordType.transaction), hasLength(1));
    await again.close();
    final hold = await vaultHoldOf(id, directory: dir.path, factory: databaseFactoryFfi);
    expect(hold?.since, '2026-11-18T09:00:00.000Z');
    expect(dir.listSync().where((e) => e.path.endsWith('.db')), hasLength(1));
  });

  test('the provisional vault survives deleteStaleVaults', () async {
    final id = newProvisionalId();
    await (await open(id)).close();
    final forgotten = <String>[];
    await deleteStaleVaults(
      null,
      forget: (userId) async => forgotten.add(userId),
      directory: () async => dir.path,
      holdOf: (userId) => vaultHoldOf(userId, directory: dir.path, factory: databaseFactoryFfi),
    );
    expect(forgotten, isEmpty);
    expect(fileOf(id), isTrue);
  });
}
