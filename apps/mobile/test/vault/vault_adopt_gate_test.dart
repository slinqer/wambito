// A vault held `orphaned` is being adopted into a new user (lib/local/adopt.dart): the gate never
// opens it, since what it would write there is lost when the adoption forgets that vault.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/adopt.dart' show AdoptStep;
import 'package:wambito/local/db.dart' show VaultHold, VaultHoldKind, vaultHoldOf;
import 'package:wambito/local/key_storage.dart';
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/vault_session.dart';
import 'package:wambito/vault/vault_gate.dart';
import 'package:wambito/vault/vault_providers.dart';

import 'vault_fakes.dart';

const FakeAccount _a = (id: 'user_a', mode: 'preview');

/// The session, counting the adoption resumes the gate asks for.
class _Session extends FixedSession {
  _Session(super.initial);

  var resumes = 0;

  @override
  Future<void> resumeAdoptions() async => resumes += 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setUpVaultFiles);
  tearDownAll(() => vaultDir.deleteSync(recursive: true));

  late KeyStorage storage;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    storage = KeyStorage(const FlutterSecureStorage());
    await storage.writeDataKey('user_a', 1, generateDataKey());
    await storage.setCurrent('user_a', 1);
  });
  tearDown(() => forgetVault('user_a', storage, deleteStore: deleteTestStore));

  Future<void> hold(VaultHold? hold) async {
    // On a connection of its own, as the adoption's: closing it never closes the gate's.
    final store = await SqliteStore.open(
      'user_a',
      directory: vaultDir.path,
      factory: databaseFactoryFfi,
      background: true,
    );
    await store.setHold(hold);
    await store.close();
  }

  const orphaned = VaultHold(VaultHoldKind.orphaned, since: '2026-11-18T00:00:00Z');

  ProviderContainer containerFor(FakeServer server, _Session session) {
    final container = appContainer(
      server,
      signedIn('tokA'),
      storage: storage,
      sessionController: () => session,
      overrides: [
        vaultHoldReaderProvider.overrideWithValue(
          (id) => vaultHoldOf(id, directory: vaultDir.path, factory: databaseFactoryFfi),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(apiClientProvider, (_, _) {});
    return container;
  }

  VaultGateState<VaultSession>? stateOf(ProviderContainer c) => c.read(vaultGateStateProvider);

  test(
    'an orphaned vault never opens: Locked, the adoption asked to go on; once it ends, it opens',
    () async {
      await hold(orphaned);
      final session = _Session(signedIn('tokA'));
      final c = containerFor(FakeServer({'tokA': _a}), session);
      await until(() => stateOf(c) is Locked);
      expect(stateOf(c), const Locked<VaultSession>(LockedKind.offline, false));
      expect(c.read(vaultSessionProvider), isNull);
      expect(session.resumes, greaterThan(0));

      // The adoption stopped at a new user that keeps data in clear: the gate says so at once,
      // without a tap on retry.
      session.adoptionStepped(AdoptStep.plainUser);
      await until(() => stateOf(c) == const Locked<VaultSession>(LockedKind.plainServer, false));
      // The same stop again changes nothing (no loop of rechecks).
      final resumes = session.resumes;
      session.adoptionStepped(AdoptStep.plainUser);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.resumes, resumes);

      // No hold any more (another way out): the vault opens as before.
      await hold(null);
      c.read(vaultGateProvider)!.retry();
      await until(() => c.read(vaultSessionProvider) != null);
    },
  );

  test('held while it was opening: closed again before it is handed out', () async {
    final server = FakeServer({'tokA': _a})..holdSync = Completer<void>();
    final session = _Session(signedIn('tokA'));
    final c = containerFor(server, session);
    await until(() => stateOf(c) is Opening);
    // The adoption holds the vault while its first sync is still out.
    await hold(orphaned);
    server.holdSync!.complete();
    await until(() => stateOf(c) is Locked);
    expect(c.read(vaultSessionProvider), isNull);
    expect(session.resumes, greaterThan(0));
  });
}
