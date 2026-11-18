// A deleted user's vault adopted into a new anonymous user (phone-first spec 10, ruling 7): real
// SQLite vaults in a temp dir, a fake auth server, a fake `/v2/keys` and a fake `/v2/sync`.
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/api/auth_api.dart' show AuthFailure;
import 'package:wambito/api/session.dart';
import 'package:wambito/api/unauthorized.dart';
import 'package:wambito/background/queued_capture.dart';
import 'package:wambito/capture_auto/capture_platform.dart' show autoCapturePlatformProvider;
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/home/home_cache.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/local/adopt.dart';
import 'package:wambito/local/db.dart'
    show VaultHold, VaultHoldKind, listVaultHolds, vaultFileName, vaultHoldOf;
import 'package:wambito/local/keys.dart';
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/stale_vaults.dart';
import 'package:wambito/local/sync.dart';
import 'package:wambito/local/vault_lock.dart' show VaultLease;
import 'package:wambito/local/vault_session.dart' show VaultProfile;
import 'package:wambito/vault/encryption_mode.dart';
import 'package:wambito/vault/vault_providers.dart';

import '../capture_auto/fakes.dart';
import '../entry/fakes.dart';
import '../home/fakes.dart';
import 'fake_keys.dart' show FakeKeys;
import 'fake_sync.dart';
import 'merge_test.dart' show category, merchant, settings, settingsIdOf, transaction;

// Invented ids: the deleted user, and what its records were.
const oldId = 'c3c3c3c3-0000-4000-8000-000000000003';
const oldToken = 'tok-of-the-deleted-user';
const food = '01930000-0000-7000-8000-00000000c001';
const tx = '01930000-0000-7000-8000-00000000c003';

/// An auth server whose every anonymous sign-up is a new user (`new_1`, `new_2`, …).
class _Auth extends FakeAuthApi {
  var _users = 0;
  final deletedUsers = <String>[];

  @override
  Future<String> signInAsGuest() async {
    final token = await super.signInAsGuest();
    accounts[token] = 'new_${++_users}';
    return token;
  }

  @override
  Future<void> deleteUser(String token) async {
    deletedUsers.add(token);
  }
}

class _NoLease implements VaultLease {
  @override
  Future<bool> renew() async => true;

  @override
  Future<void> release() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory dir;
  late _Auth auth;
  late FakeKeys keysServer;
  late List<String> forgotten;
  late FakeAutoCapturePlatform capture;

  /// Fails the next open of that vault (a crash right there).
  String? crashOpening;

  Future<SqliteStore> open(String id) {
    if (crashOpening == id) {
      crashOpening = null;
      throw StateError('killed');
    }
    return SqliteStore.open(id, directory: dir.path, factory: databaseFactoryFfi, background: true);
  }

  bool fileOf(String id) => File(p.join(dir.path, vaultFileName(id))).existsSync();
  KeyStorage keyStorage() => KeyStorage(const FlutterSecureStorage());
  Future<Map<String, String>> kept() => const FlutterSecureStorage().readAll();

  Future<void> forget(String id) async {
    forgotten.add(id);
    await databaseFactoryFfi.deleteDatabase(p.join(dir.path, vaultFileName(id)));
    await keyStorage().deleteAll(id);
  }

  /// What [AdoptDeps.listHolds] does: the real listing, unless a test holds it.
  Future<({List<({String userId, VaultHold hold})> holds, List<String> unreadable})> Function()?
  listing;

  AdoptDeps deps() => AdoptDeps(
    auth: auth,
    keys: keyStorage(),
    network: (token) => keysServer.dio(),
    openStore: open,
    lease: (id) async => _NoLease(),
    forgetVault: forget,
    now: () => DateTime.utc(2026, 11, 18, 12),
    keptToken: () => const FlutterSecureStorage().read(key: adoptTokenKey),
    keepToken: (t) => const FlutterSecureStorage().write(key: adoptTokenKey, value: t),
    forgetToken: () => const FlutterSecureStorage().delete(key: adoptTokenKey),
    directory: dir.path,
    factory: databaseFactoryFfi,
    hasQueuedCaptures: capture.hasQueued,
    listHolds: listing,
  );

  /// The deleted user's vault: its settings (a recovery key once saved), a category, and, when
  /// [data], a movement and a merchant.
  Future<void> oldVault({bool data = true}) async {
    final store = await open(oldId);
    await store.put(RecordType.settings, settingsIdOf(oldId), settings(savedAt: '2026-01-02'));
    await store.put(RecordType.category, food, category('Comida'));
    if (data) {
      await store.put(RecordType.transaction, tx, transaction(food));
      await store.put(RecordType.merchant, 'merchant-1', merchant('mercadona', food));
    }
    await store.close();
  }

  /// The phone as the deleted user left it: its session, its keys, and its account kept `preview`.
  Future<void> signedInAsTheDeletedUser() async {
    FlutterSecureStorage.setMockInitialValues({
      SessionStore.tokenKey: oldToken,
      SessionStore.guestKey: 'true',
      'wambito.vault.$oldId.current': '1',
      'wambito.vault.$oldId.dk.1': 'AAAA',
    });
    await const EncryptionStore().remember(
      oldToken,
      VaultAccount(
        owner: sessionOwnerOf(oldToken),
        profile: const VaultProfile(
          id: oldId,
          email: '',
          isAnonymous: true,
          locale: 'es',
          timezone: 'America/Bogota',
        ),
        mode: EncryptionMode.preview,
      ),
    );
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('wambito-adopt');
    auth = _Auth();
    keysServer = FakeKeys();
    forgotten = [];
    crashOpening = null;
    listing = null;
    capture = FakeAutoCapturePlatform();
    await signedInAsTheDeletedUser();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ProviderContainer containerFor() {
    final container = ProviderContainer(
      overrides: [
        authApiProvider.overrideWithValue(auth),
        passkeysProvider.overrideWithValue(FakePasskeys()),
        widgetStoreProvider.overrideWithValue(FakeWidgetStore()),
        homeCacheStoreProvider.overrideWithValue(FakeCacheStore()),
        autoCapturePlatformProvider.overrideWithValue(capture),
        forgetVaultProvider.overrideWithValue((id, storage) => forget(id)),
        vaultHoldReaderProvider.overrideWithValue(
          (id) => vaultHoldOf(id, directory: dir.path, factory: databaseFactoryFfi),
        ),
        adoptDepsProvider.overrideWith((ref) => deps()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// The app's session over [deps], with the start's `GET /v1/me` of the deleted user answering
  /// [code].
  Future<ProviderContainer> startWith401(String code) async {
    auth.failures['isGuest'] = AuthFailure(code: code, status: 401);
    final container = containerFor();
    final session = container.read(sessionProvider.notifier);
    await session.ready;
    await session.refreshed;
    return container;
  }

  test(
    'user_deleted: a new anonymous user, every record re-sealed under its id on the next push',
    () async {
      await oldVault();
      final container = await startWith401('user_deleted');

      // The start named the kept account, so the server could say it was deleted.
      expect(auth.standingUsers.first, oldId);
      // One new anonymous user, and the session is now its.
      expect(auth.signInAsGuestCalls, 1);
      final newToken = container.read(sessionProvider).stored!.token;
      expect(newToken, isNot(oldToken));
      expect(container.read(sessionProvider).isGuest, isTrue);
      const newId = 'new_1';
      // Its keys were made on this phone (a hidden recovery wrap first, then this device's).
      expect(keysServer.puts.map((c) => c.user).toSet(), {newId});
      // The old vault and its keys are gone; nothing is held; the kept token went once used.
      expect(fileOf(oldId), isFalse);
      expect(forgotten, [oldId]);
      expect((await kept()).containsKey(adoptTokenKey), isFalse);
      // The deleted user's queued captures are the new user's now.
      await Future<void>.delayed(Duration.zero);
      expect(capture.callsNamed('sendQueued'), anyElement(endsWith(' from $oldId')));

      // The next push: every record opens with the new user's keys and its id in the AAD.
      final local = (await loadLocalKeys(newId, keyStorage()))!;
      final store = await open(newId);
      final server = FakeSync();
      final engine = createSyncEngine(
        SyncEngineOptions(
          store: store,
          dio: server.dio(),
          userId: newId,
          keyring: local.keyring,
          refreshKeys: () async => local.keyring,
        ),
      );
      final result = await engine.run();
      expect(result.ok, isTrue, reason: '$result');
      final newKeys = currentRecordKeys(local);
      final pushed = <String, Object?>{};
      for (final row in server.rows.values) {
        final type = RecordType.values.byName(row['type']! as String);
        pushed[row['id']! as String] = await openRecord(
          newKeys,
          RecordContext(
            userId: newId,
            type: type,
            id: row['id']! as String,
            keyV: row['keyV']! as int,
          ),
          fromBase64Url(row['body']! as String),
        );
      }
      expect(pushed.keys, containsAll([food, tx, settingsIdOf(newId)]));
      expect((pushed[tx]! as Map)['categoryId'], food);
      // Under the old user's id nothing opens: the AAD is the new user's.
      final row = server.rows[tx]!;
      await expectLater(
        openRecord(
          newKeys,
          RecordContext(
            userId: oldId,
            type: RecordType.transaction,
            id: tx,
            keyV: row['keyV']! as int,
          ),
          fromBase64Url(row['body']! as String),
        ),
        throwsA(anything),
      );
      await store.close();
    },
  );

  test('the orphaned vault survives the new user\'s sweep', () async {
    await oldVault();
    // Killed once the new user exists and its keys are kept, as its vault was opened.
    crashOpening = 'new_1';
    await expectLater(adoptOrphan(oldId, deps()), throwsA(isA<StateError>()));
    final hold = await vaultHoldOf(oldId, directory: dir.path, factory: databaseFactoryFfi);
    expect(hold?.kind, VaultHoldKind.orphaned);
    expect(hold?.target, 'new_1');

    // The new user's first `GET /v1/me` sweeps every other account's vault.
    await deleteStaleVaults(
      'new_1',
      forget: forget,
      directory: () async => dir.path,
      holdOf: (id) => vaultHoldOf(id, directory: dir.path, factory: databaseFactoryFfi),
    );
    expect(fileOf(oldId), isTrue);
    expect((await kept())['wambito.vault.$oldId.current'], '1');
    expect(forgotten, isEmpty);
  });

  test('a crash after the new user exists resumes without a second user', () async {
    await oldVault();
    crashOpening = 'new_1';
    await expectLater(adoptOrphan(oldId, deps()), throwsA(isA<StateError>()));
    expect(auth.signInAsGuestCalls, 1);
    expect((await kept())[adoptTokenKey], isNotNull);

    final adopted = <String>[];
    await resumeAdoption(
      deps().withSession(onAdopted: (token, {required fromUserId}) async => adopted.add(token)),
    );
    expect(auth.signInAsGuestCalls, 1);
    expect(adopted, hasLength(1));
    expect(fileOf(oldId), isFalse);
    final store = await open('new_1');
    expect((await store.list(RecordType.transaction)).single.id, tx);
    await store.close();
  });

  test('an empty vault is wiped and the phone signs out', () async {
    await oldVault(data: false);
    final container = await startWith401('user_deleted');
    expect(container.read(sessionProvider).status, SessionStatus.signedOut);
    expect(auth.signInAsGuestCalls, 0);
    expect(fileOf(oldId), isFalse);
    expect(forgotten, contains(oldId));
    expect((await kept()).keys.where((k) => k.startsWith('wambito.vault.$oldId.')), isEmpty);
  });

  test('the nudges start over', () async {
    await oldVault();
    expect(await adoptOrphan(oldId, deps()), AdoptOutcome.adopted);
    final store = await open('new_1');
    final all = await store.list(RecordType.settings);
    await store.close();
    // The old recovery key and passkey wrap were the deleted user's.
    expect(all.single.id, settingsIdOf('new_1'));
    expect(all.single.body['recoveryKeySavedAt'], isNull);
    expect(all.single.body['revokedDevices'], isEmpty);
  });

  test('adoptVaultIntoNewUser reuses a kept token instead of making a second user', () async {
    await oldVault();
    const keptToken = 'kept-token';
    auth.accounts[keptToken] = 'new_kept';
    await const FlutterSecureStorage().write(key: adoptTokenKey, value: keptToken);
    expect(await adoptVaultIntoNewUser(oldId, deps()), AdoptStep.adopted);
    expect(auth.signInAsGuestCalls, 0);
    expect(auth.calls, contains('isGuest $keptToken'));
    final store = await open('new_kept');
    expect((await store.list(RecordType.transaction)).single.id, tx);
    await store.close();
  });

  test('offline it waits: nothing carried, the vault held, the session as it was', () async {
    await oldVault();
    keysServer.offline = true;
    final container = await startWith401('user_deleted');
    expect(container.read(sessionProvider).stored?.token, oldToken);
    expect(fileOf(oldId), isTrue);
    expect(
      (await vaultHoldOf(oldId, directory: dir.path, factory: databaseFactoryFfi))?.kind,
      VaultHoldKind.orphaned,
    );
    // Back online, the resume goes on with the same new user.
    keysServer.offline = false;
    await container.read(sessionProvider.notifier).resumeAdoptions();
    expect(auth.signInAsGuestCalls, 1);
    expect(container.read(sessionProvider).stored?.token, isNot(oldToken));
    expect(fileOf(oldId), isFalse);
  });

  test('a plain new user carries nothing and keeps the vault held', () async {
    await oldVault();
    auth.plainTokens.add('guest-token-1');
    expect(await adoptVaultIntoNewUser(oldId, deps()), AdoptStep.plainUser);
    expect(fileOf(oldId), isTrue);
    expect(fileOf('new_1'), isFalse);
    expect(keysServer.puts, isEmpty);
  });

  test('resumeAdoption leaves a vault whose hold cannot be read alone', () async {
    const unreadable = 'd4d4d4d4-0000-4000-8000-000000000004';
    final broken = await open(unreadable);
    await broken.setMeta('hold', 'not a hold');
    await broken.close();
    await oldVault();
    final store = await open(oldId);
    await store.setHold(const VaultHold(VaultHoldKind.orphaned, since: '2026-11-18T00:00:00Z'));
    await store.close();

    final adopted = <String>[];
    await resumeAdoption(
      deps().withSession(
        onAdopted: (token, {required fromUserId}) async => adopted.add(fromUserId),
      ),
    );
    expect(adopted, [oldId]);
    expect(fileOf(unreadable), isTrue);
    expect(forgotten, [oldId]);
  });

  test('a resume never replaces another account\'s session', () async {
    await oldVault();
    final store = await open(oldId);
    await store.setHold(const VaultHold(VaultHoldKind.orphaned, since: '2026-11-18T00:00:00Z'));
    await store.close();
    await resumeAdoption(deps().withSession(mayResume: (id) async => false));
    expect(auth.signInAsGuestCalls, 0);
    expect(fileOf(oldId), isTrue);
  });

  test(
    'a start\'s resume and its 401 user_deleted at once: both run, the 401\'s adoption too',
    () async {
      await oldVault();
      // The resume lists the holds while the start's 401 comes in: the old vault is not held yet.
      listing = () async {
        await until(() => auth.standingUsers.isNotEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return listVaultHolds(directory: dir.path, factory: databaseFactoryFfi);
      };
      auth.failures['isGuest'] = const AuthFailure(code: 'user_deleted', status: 401);
      final container = ProviderContainer(
        overrides: [
          authApiProvider.overrideWithValue(auth),
          passkeysProvider.overrideWithValue(FakePasskeys()),
          widgetStoreProvider.overrideWithValue(FakeWidgetStore()),
          homeCacheStoreProvider.overrideWithValue(FakeCacheStore()),
          autoCapturePlatformProvider.overrideWithValue(capture),
          forgetVaultProvider.overrideWithValue((id, storage) => forget(id)),
          adoptDepsProvider.overrideWith((ref) => deps()),
        ],
      );
      addTearDown(container.dispose);
      container.read(adoptionResumeProvider);
      final session = container.read(sessionProvider.notifier);
      await session.refreshed;
      await until(() => !fileOf(oldId));
      expect(auth.signInAsGuestCalls, 1);
      expect(container.read(sessionProvider).stored?.token, isNot(oldToken));
      final store = await open('new_1');
      expect((await store.list(RecordType.transaction)).single.id, tx);
      await store.close();
    },
  );

  test('a vault without records but with captures still queued is adopted, not wiped', () async {
    await oldVault(data: false);
    capture.queuedCaptures = [_queued];
    final container = await startWith401('user_deleted');
    expect(auth.signInAsGuestCalls, 1);
    expect(container.read(sessionProvider).stored?.token, isNot(oldToken));
    await Future<void>.delayed(Duration.zero);
    // The queue is never cleared: it is re-tagged to the new user.
    expect(capture.calls, isNot(contains('clearQueue')));
    expect(capture.callsNamed('sendQueued'), anyElement(endsWith(' from $oldId')));
  });

  test('two asks for the same 401 user_deleted, with a capture queued: one new user, the session '
      'on it with its data', () async {
    await oldVault();
    capture.queuedCaptures = [_queued];
    auth.failures['isGuest'] = const AuthFailure(code: 'user_deleted', status: 401);
    final container = containerFor();
    final session = container.read(sessionProvider.notifier);
    await session.ready;
    // The start's 401 and the gate's, for the same dead session.
    final second = session.sessionEnded(token: oldToken, kind: Unauthorized.userDeleted);
    await session.refreshed;
    await second;
    expect(auth.signInAsGuestCalls, 1);
    expect(container.read(sessionProvider).stored?.token, 'guest-token-1');
    final store = await open('new_1');
    expect((await store.list(RecordType.transaction)).single.id, tx);
    await store.close();
    // The queue was handed to the new user before anything else could look at it.
    expect(capture.callsNamed('sendQueued'), anyElement(endsWith(' from $oldId')));
  });

  test('a queue Android cannot read counts as data: the empty vault is adopted', () async {
    await oldVault(data: false);
    capture.hasQueuedError = PlatformException(code: 'io');
    final container = await startWith401('user_deleted');
    expect(auth.signInAsGuestCalls, 1);
    expect(container.read(sessionProvider).stored?.token, isNot(oldToken));
  });

  test('killed after the old vault was forgotten and before the session changed: the next '
      'start\'s 401 finishes it with the same user', () async {
    await oldVault();
    await expectLater(
      adoptOrphan(
        oldId,
        deps().withSession(
          onAdopted: (token, {required fromUserId}) async => throw StateError('killed'),
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect(fileOf(oldId), isFalse);
    expect((await kept())[adoptTokenKey], isNotNull);

    final container = await startWith401('user_deleted');
    expect(auth.signInAsGuestCalls, 1);
    expect(container.read(sessionProvider).stored?.token, 'guest-token-1');
    expect((await kept()).containsKey(adoptTokenKey), isFalse);
    final store = await open('new_1');
    expect((await store.list(RecordType.transaction)).single.id, tx);
    await store.close();
  });

  group('regression guards, as 3a', () {
    test('device_removed wipes, unauthenticated keeps the vault', () async {
      await oldVault();
      final removed = await startWith401('device_removed');
      expect(removed.read(sessionProvider).status, SessionStatus.signedOut);
      expect(forgotten, [oldId]);
      expect(auth.signInAsGuestCalls, 0);

      await oldVault();
      await signedInAsTheDeletedUser();
      forgotten.clear();
      final expired = await startWith401('unauthenticated');
      expect(expired.read(sessionProvider).status, SessionStatus.signedOut);
      expect(forgotten, isEmpty);
      expect(fileOf(oldId), isTrue);
      expect((await kept())['wambito.vault.$oldId.current'], '1');
      expect(auth.signInAsGuestCalls, 0);
    });
  });
}

Future<void> until(bool Function() condition) async {
  final stop = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(stop)) throw StateError('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

const _queued = QueuedCapture(
  key: 'k1',
  kind: 'expense',
  amount: 1250,
  currency: 'EUR',
  merchant: 'Mercadona',
  capturedAt: '2026-11-18T10:00:00.000Z',
  source: 'revolut',
);
