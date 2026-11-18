// The merge of this phone's anonymous account into an existing email account (phone-first spec
// 7.2, ruling 10): two real SQLite vaults in a temp dir, a fake auth server and a fake sync.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/api/auth_api.dart' show AuthFailure;
import 'package:wambito/api/session.dart';
import 'package:wambito/capture_auto/capture_platform.dart' show autoCapturePlatformProvider;
import 'package:wambito/local/merge.dart' show CarryMode, carryRecords, mergedId;
import 'package:wambito/crypto/records.dart' show RecordType;
import 'package:wambito/home/home_cache.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/local/db.dart'
    show VaultHoldKind, listVaultHolds, vaultFileName, vaultHoldOf;
import 'package:wambito/local/key_storage.dart';
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/stale_vaults.dart';
import 'package:wambito/local/vault_lock.dart' show tryLease;
import 'package:wambito/local/vault_session.dart' show VaultProfile;
import 'package:wambito/merge/merge_controller.dart';
import 'package:wambito/vault/encryption_mode.dart';
import 'package:wambito/vault/vault_providers.dart';

import '../capture_auto/fakes.dart';
import '../entry/fakes.dart';
import '../home/fakes.dart';
import '../local/merge_test.dart' show category, dump, settings, settingsIdOf, transaction;

// Invented ids: the phone's anonymous user and the email account it merges into.
const anonId = 'a1a1a1a1-0000-4000-8000-000000000001';
const accountId = 'b2b2b2b2-0000-4000-8000-000000000002';
const email = 'ana@wambito.test';
const anonToken = 'guest-token-phone';
const pFood = '01930000-0000-7000-8000-00000000a001';
const pTx = '01930000-0000-7000-8000-00000000a003';

/// The id the merge gives the phone's movement in the account.
final mTx = mergedId(accountId, pTx);
const aFood = '01930000-0000-7000-8000-00000000b001';
const aTx = '01930000-0000-7000-8000-00000000b003';

/// The server's `/v2/sync` as far as a merge sees it: pushes ack every pending change, unless
/// offline.
class FakeSync {
  bool offline = false;
  var runs = 0;

  /// Ids the server answers `id_taken` (another user owns them, as the guest owns what it synced):
  /// the sync drops them, unversioned, as the real engine does.
  final refused = <String>{};

  /// Every id pushed, in order.
  final pushed = <String>[];

  Future<bool> run(SqliteStore store) async {
    runs += 1;
    if (offline) return false;
    var version = 100;
    for (final entry in await store.readOutbox(1000)) {
      pushed.add(entry.id);
      await store.ackOutbox(entry.id, refused.contains(entry.id) ? 0 : ++version, entry.seq);
    }
    return true;
  }
}

Future<int> pendingOf(SqliteStore store) async =>
    (await store.readOutbox(1000)).where((e) => !e.reseal && !e.abandoned).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory dir;
  late FakeAuthApi auth;
  late FakeSync sync;
  late List<String> forgotten;
  late SqliteStore accountStore;
  late FakeAutoCapturePlatform capture;
  var targetReady = false;

  Future<SqliteStore> open(String id) =>
      SqliteStore.open(id, directory: dir.path, factory: databaseFactoryFfi);

  bool fileOf(String id) => File(p.join(dir.path, vaultFileName(id))).existsSync();

  Future<void> forget(String id, KeyStorage storage) async {
    forgotten.add(id);
    await databaseFactoryFfi.deleteDatabase(p.join(dir.path, vaultFileName(id)));
    await storage.deleteAll(id);
  }

  Future<Map<String, String>> kept() => const FlutterSecureStorage().readAll();

  VaultAccount accountFor(String token) {
    final phone = token == anonToken;
    return VaultAccount(
      owner: sessionOwnerOf(token),
      profile: VaultProfile(
        id: phone ? anonId : accountId,
        email: phone ? '' : email,
        isAnonymous: phone,
        locale: 'es',
        timezone: 'America/Bogota',
      ),
      mode: EncryptionMode.preview,
    );
  }

  /// The app as it runs on this phone, as far as a merge goes: the session, the account's mode,
  /// the account's open vault once [targetReady].
  ProviderContainer app() {
    final container = ProviderContainer(
      overrides: [
        authApiProvider.overrideWithValue(auth),
        passkeysProvider.overrideWithValue(FakePasskeys(isSupported: false)),
        widgetStoreProvider.overrideWithValue(FakeWidgetStore()),
        homeCacheStoreProvider.overrideWithValue(FakeCacheStore()),
        vaultAccountProvider.overrideWith((ref) {
          final token = ref.watch(sessionProvider.select((s) => s.stored?.token));
          if (token == null) return SynchronousFuture<VaultAccount?>(null);
          final account = accountFor(token);
          ref.read(knownAccountProvider)
            ..owner = account.owner
            ..id = account.profile.id;
          return SynchronousFuture<VaultAccount?>(account);
        }),
        forgetVaultProvider.overrideWithValue(forget),
        autoCapturePlatformProvider.overrideWithValue(capture),
        mergeDepsProvider.overrideWithValue(
          MergeDeps(
            listHolds: () => listVaultHolds(directory: dir.path, factory: databaseFactoryFfi),
            openSource: (id) => SqliteStore.open(
              id,
              directory: dir.path,
              factory: databaseFactoryFfi,
              background: true,
            ),
            lease: (id) => tryLease(id, holder: 'app', directory: dir.path),
            storage: const FlutterSecureStorage(),
            now: () => DateTime.utc(2026, 11, 18, 12),
          ),
        ),
        mergeTargetProvider.overrideWith((ref) {
          final account = ref.watch(currentVaultAccountProvider);
          if (!targetReady || account == null || account.profile.id != accountId) return null;
          return MergeTarget(
            userId: accountId,
            email: email,
            store: accountStore,
            sync: () => sync.run(accountStore),
            pendingChanges: () => pendingOf(accountStore),
            serverVersion: (type, id) async => (await accountStore.rawRecord(type, id))?.version,
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// The phone's anonymous vault with a category and a movement, in [currency].
  Future<void> phoneVault({String currency = 'COP'}) async {
    final store = await open(anonId);
    await store.put(RecordType.settings, settingsIdOf(anonId), settings(currency: currency));
    await store.put(RecordType.category, pFood, category('Comida'));
    await store.put(RecordType.transaction, pTx, transaction(pFood));
    await store.close();
  }

  /// The email account's vault, downloaded and synced (nothing pending).
  Future<void> accountVault({String currency = 'COP'}) async {
    accountStore = await open(accountId);
    await accountStore.put(
      RecordType.settings,
      settingsIdOf(accountId),
      settings(currency: currency),
    );
    await accountStore.put(RecordType.category, aFood, category('Comida'));
    await accountStore.put(RecordType.transaction, aTx, transaction(aFood));
    await sync.run(accountStore);
    sync.runs = 0;
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('wambito-merge-ctl');
    auth = FakeAuthApi();
    sync = FakeSync();
    capture = FakeAutoCapturePlatform();
    forgotten = [];
    targetReady = false;
    FlutterSecureStorage.setMockInitialValues({
      SessionStore.tokenKey: anonToken,
      SessionStore.guestKey: 'true',
      'wambito.vault.$anonId.dk.1': 'AAAA',
      'wambito.vault.$anonId.current': '1',
      'wambito.vault.$anonId.device': 'BBBB',
    });
    await phoneVault();
    await accountVault();
  });

  tearDown(() async {
    if (!accountStore.isClosed) await accountStore.close();
    dir.deleteSync(recursive: true);
  });

  /// Up to the email sign-in: the offer said yes (begin), the code went in.
  Future<ProviderContainer> signedInToTheAccount() async {
    final container = app();
    final session = container.read(sessionProvider.notifier);
    await session.ready;
    final merge = container.read(mergeControllerProvider.notifier);
    await merge.begin(email);
    expect(container.read(mergeControllerProvider), isA<MergeSigningIn>());
    await session.verifyCode(email, '123456', replaceGuest: true);
    await merge.resume();
    return container;
  }

  int deletes() => auth.calls.where((c) => c.startsWith('deleteUser')).length;

  test(
    'the phone\'s records reach the account\'s vault and the anonymous user is deleted only after '
    'the outbox is empty',
    () async {
      final container = await signedInToTheAccount();
      final merge = container.read(mergeControllerProvider.notifier);
      expect(container.read(mergeControllerProvider), isA<MergeWaitingUnlock>());
      // Before the account's vault is open nothing happens.
      await merge.run();
      expect(deletes(), 0);

      targetReady = true;
      container.invalidate(mergeTargetProvider);
      // The DELETE is asked only once the outbox is empty: check at the call.
      int? pendingAtDelete;
      auth.onDeleteUser = () async => pendingAtDelete = await pendingOf(accountStore);
      await merge.run();

      expect(container.read(mergeControllerProvider), isA<MergeDone>());
      // The phone's movement is in the account; its "Comida" became the account's.
      final movement = await accountStore.get(RecordType.transaction, mTx);
      expect(movement?.body['categoryId'], aFood);
      expect(await accountStore.get(RecordType.category, pFood), isNull);
      expect(auth.calls.where((c) => c.startsWith('deleteUser')), ['deleteUser $anonToken']);
      expect(pendingAtDelete, 0);
      expect(sync.runs, greaterThan(0));
      // The old vault, its keys and the kept token are gone.
      expect(forgotten, [anonId]);
      expect(fileOf(anonId), isFalse);
      final left = await kept();
      expect(left.keys.where((k) => k.startsWith('wambito.vault.$anonId.')), isEmpty);
      expect(left.containsKey(mergeTokenKey(anonId)), isFalse);
    },
  );

  test('killed after the email sign-in: the sweep keeps the anonymous vault and a new controller '
      'resumes', () async {
    final first = await signedInToTheAccount();
    // Killed here: the app is gone.
    first.dispose();

    // The next start: the account's `/v1/me` answer sweeps every other vault.
    await deleteStaleVaults(
      accountId,
      forget: (id) => forget(id, KeyStorage(const FlutterSecureStorage())),
      directory: () async => dir.path,
      holdOf: (id) => vaultHoldOf(id, directory: dir.path, factory: databaseFactoryFfi),
    );
    expect(forgotten, isEmpty);
    expect(fileOf(anonId), isTrue);
    expect((await kept())[mergeTokenKey(anonId)], anonToken);

    final container = app();
    await container.read(sessionProvider.notifier).ready;
    final merge = container.read(mergeControllerProvider.notifier);
    await merge.resume();
    expect(container.read(mergeControllerProvider), isA<MergeWaitingUnlock>());
    targetReady = true;
    container.invalidate(mergeTargetProvider);
    await merge.run();

    expect(container.read(mergeControllerProvider), isA<MergeDone>());
    expect((await accountStore.get(RecordType.transaction, mTx))?.body['categoryId'], aFood);
    expect(deletes(), 1);
    expect(fileOf(anonId), isFalse);
  });

  test('killed during the upload: no DELETE until a later run empties the outbox', () async {
    final first = await signedInToTheAccount();
    targetReady = true;
    first.invalidate(mergeTargetProvider);
    sync.offline = true;
    await first.read(mergeControllerProvider.notifier).run();
    expect(first.read(mergeControllerProvider), isA<MergeUploading>());
    expect(deletes(), 0);
    first.dispose();

    // The person edits the carried movement before the next start: a later run never carries
    // the phone's copy over it again.
    final edited = Map<String, Object?>.of(
      (await accountStore.get(RecordType.transaction, mTx))!.body,
    )..['name'] = 'Mercado del barrio';
    await accountStore.put(RecordType.transaction, mTx, edited);

    // Still offline at the next start.
    final second = app();
    await second.read(sessionProvider.notifier).ready;
    var merge = second.read(mergeControllerProvider.notifier);
    await merge.resume();
    await merge.run();
    expect(second.read(mergeControllerProvider), isA<MergeUploading>());
    expect(deletes(), 0);
    expect(fileOf(anonId), isTrue);
    second.dispose();

    // Online again.
    sync.offline = false;
    final third = app();
    await third.read(sessionProvider.notifier).ready;
    merge = third.read(mergeControllerProvider.notifier);
    await merge.resume();
    await merge.run();
    expect(third.read(mergeControllerProvider), isA<MergeDone>());
    expect(deletes(), 1);
    expect(
      (await accountStore.get(RecordType.transaction, mTx))?.body['name'],
      'Mercado del barrio',
    );
    expect(await pendingOf(accountStore), 0);
  });

  test('offline during the upload stays MergeUploading and deletes nothing', () async {
    final container = await signedInToTheAccount();
    targetReady = true;
    container.invalidate(mergeTargetProvider);
    sync.offline = true;
    await container.read(mergeControllerProvider.notifier).run();

    final state = container.read(mergeControllerProvider);
    expect(state, isA<MergeUploading>());
    expect((state as MergeUploading).pending, greaterThan(0));
    expect(deletes(), 0);
    expect(forgotten, isEmpty);
    expect(fileOf(anonId), isTrue);
    expect(
      (await vaultHoldOf(anonId, directory: dir.path, factory: databaseFactoryFfi))?.kind,
      VaultHoldKind.merging,
    );
    expect((await kept())[mergeTokenKey(anonId)], anonToken);
  });

  test(
    'different currencies stop before anything is written; cancel puts the guest session back',
    () async {
      await accountStore.close();
      await databaseFactoryFfi.deleteDatabase(p.join(dir.path, vaultFileName(accountId)));
      await accountVault(currency: 'USD');
      final container = await signedInToTheAccount();
      targetReady = true;
      container.invalidate(mergeTargetProvider);
      final before = await dump(accountStore);
      final merge = container.read(mergeControllerProvider.notifier);
      await merge.run();

      final state = container.read(mergeControllerProvider);
      expect(state, isA<MergeCurrencyStop>());
      expect((state as MergeCurrencyStop).phone, 'COP');
      expect(state.account, 'USD');
      expect(await dump(accountStore), before);
      expect(await pendingOf(accountStore), 0);
      expect(deletes(), 0);

      final emailToken = container.read(sessionProvider).stored!.token;
      await merge.cancel();
      final session = container.read(sessionProvider);
      expect(session.stored?.token, anonToken);
      expect(session.isGuest, isTrue);
      expect(auth.calls, contains('signOut $emailToken'));
      expect(forgotten, [accountId]);
      expect(container.read(mergeControllerProvider), isA<MergeIdle>());
      expect(await vaultHoldOf(anonId, directory: dir.path, factory: databaseFactoryFfi), isNull);
      expect(deletes(), 0);
    },
  );

  test(
    'keep only the account\'s data deletes the anonymous user and its vault and carries nothing',
    () async {
      await accountStore.close();
      await databaseFactoryFfi.deleteDatabase(p.join(dir.path, vaultFileName(accountId)));
      await accountVault(currency: 'USD');
      final container = await signedInToTheAccount();
      targetReady = true;
      container.invalidate(mergeTargetProvider);
      final merge = container.read(mergeControllerProvider.notifier);
      await merge.run();
      expect(container.read(mergeControllerProvider), isA<MergeCurrencyStop>());
      final before = await dump(accountStore);

      await merge.keepAccountOnly();

      expect(container.read(mergeControllerProvider), isA<MergeDone>());
      expect(auth.calls.where((c) => c.startsWith('deleteUser')), ['deleteUser $anonToken']);
      expect(forgotten, [anonId]);
      expect(fileOf(anonId), isFalse);
      expect(await dump(accountStore), before);
      expect(await accountStore.get(RecordType.transaction, mTx), isNull);
      expect((await kept()).containsKey(mergeTokenKey(anonId)), isFalse);
      // Still signed in to the account.
      expect(container.read(sessionProvider).stored?.token, isNot(anonToken));
    },
  );

  test('a DELETE answered 401 counts as done', () async {
    final container = await signedInToTheAccount();
    targetReady = true;
    container.invalidate(mergeTargetProvider);
    auth.failures['deleteUser'] = const AuthFailure(code: 'unauthenticated', status: 401);
    await container.read(mergeControllerProvider.notifier).run();

    expect(container.read(mergeControllerProvider), isA<MergeDone>());
    expect(forgotten, [anonId]);
    expect((await kept()).containsKey(mergeTokenKey(anonId)), isFalse);
  });

  test('a DELETE that cannot reach the server keeps the old vault for the next run', () async {
    final container = await signedInToTheAccount();
    targetReady = true;
    container.invalidate(mergeTargetProvider);
    auth.failures['deleteUser'] = const AuthFailure(status: 0);
    final merge = container.read(mergeControllerProvider.notifier);
    await merge.run();
    expect(container.read(mergeControllerProvider), isA<MergeFailed>());
    expect((container.read(mergeControllerProvider) as MergeFailed).carried, isTrue);
    expect(fileOf(anonId), isTrue);

    await merge.run();
    expect(container.read(mergeControllerProvider), isA<MergeDone>());
    expect(deletes(), 2);
    expect(forgotten, [anonId]);
  });

  test('cancel after the sign-in leaves the guest session with its data and no hold', () async {
    final container = await signedInToTheAccount();
    await container.read(mergeControllerProvider.notifier).cancel();

    final session = container.read(sessionProvider);
    expect(session.stored?.token, anonToken);
    expect(session.isGuest, isTrue);
    expect(await vaultHoldOf(anonId, directory: dir.path, factory: databaseFactoryFfi), isNull);
    final store = await open(anonId);
    expect((await store.get(RecordType.transaction, pTx))?.body['categoryId'], pFood);
    await store.close();
    final left = await kept();
    expect(left['wambito.vault.$anonId.device'], 'BBBB');
    expect(left.containsKey(mergeTokenKey(anonId)), isFalse);
    expect(container.read(mergeControllerProvider), isA<MergeIdle>());
    expect(deletes(), 0);
  });

  test('cancel before the sign-in only clears the hold', () async {
    final container = app();
    await container.read(sessionProvider.notifier).ready;
    final merge = container.read(mergeControllerProvider.notifier);
    await merge.begin(email);
    expect(
      (await vaultHoldOf(anonId, directory: dir.path, factory: databaseFactoryFfi))?.target,
      email,
    );
    await merge.cancel();

    expect(container.read(sessionProvider).stored?.token, anonToken);
    expect(auth.calls.where((c) => c.startsWith('signOut')), isEmpty);
    expect(await vaultHoldOf(anonId, directory: dir.path, factory: databaseFactoryFfi), isNull);
    expect((await kept()).containsKey(mergeTokenKey(anonId)), isFalse);
    expect(forgotten, isEmpty);
  });

  test(
    'returnToGuest\'s sign-out of the email account never takes the device_removed wipe path',
    () async {
      // The account kept last is the phone's own (no answer for the email account yet), which is
      // what a sign-out would fall back to wiping: the guest's vault, file and keys, must stay.
      final container = app();
      final session = container.read(sessionProvider.notifier);
      await session.ready;
      await const EncryptionStore().remember(anonToken, accountFor(anonToken));
      await container.read(mergeControllerProvider.notifier).begin(email);
      await session.verifyCode(email, '123456', replaceGuest: true);
      container.read(knownAccountProvider)
        ..owner = null
        ..id = null;
      final emailToken = container.read(sessionProvider).stored!.token;
      auth.calls.clear();

      await session.returnToGuest(anonToken, guestUserId: anonId);

      expect(forgotten, isNot(contains(anonId)));
      expect(fileOf(anonId), isTrue);
      final left = await kept();
      expect(left['wambito.vault.$anonId.dk.1'], 'AAAA');
      expect(left['wambito.vault.$anonId.device'], 'BBBB');
      expect(auth.calls.where((c) => c.startsWith('signOut')), ['signOut $emailToken']);
      expect(auth.calls.where((c) => c.startsWith('deleteUser')), isEmpty);
      expect(container.read(sessionProvider).stored?.token, anonToken);
      expect(container.read(sessionProvider).isGuest, isTrue);
    },
  );

  test('a resume leaves a vault whose hold cannot be read alone', () async {
    // A merge was under way, but the hold of the phone's vault is unreadable now.
    final store = await open(anonId);
    await store.setMeta('hold', {'kind': 'merging?'});
    await store.close();
    await const FlutterSecureStorage().write(key: mergeTokenKey(anonId), value: anonToken);
    FlutterSecureStorage.setMockInitialValues({
      ...await kept(),
      SessionStore.tokenKey: 'email-token-9',
      SessionStore.guestKey: 'false',
    });
    final container = app();
    await container.read(sessionProvider.notifier).ready;
    targetReady = true;
    final merge = container.read(mergeControllerProvider.notifier);
    await merge.resume();
    await merge.run();

    expect(container.read(mergeControllerProvider), isA<MergeIdle>());
    expect(fileOf(anonId), isTrue);
    expect(forgotten, isEmpty);
    expect(deletes(), 0);
    expect((await kept())[mergeTokenKey(anonId)], anonToken);
    expect(await accountStore.get(RecordType.transaction, mTx), isNull);
  });

  test(
    'a start still in the phone\'s own session keeps the merge for its sign-in (the email\'s link '
    'may still come)',
    () async {
      final first = app();
      await first.read(sessionProvider.notifier).ready;
      await first.read(mergeControllerProvider.notifier).begin(email);
      first.dispose();

      final container = app();
      final session = container.read(sessionProvider.notifier);
      await session.ready;
      final merge = container.read(mergeControllerProvider.notifier);
      await merge.resume();
      expect(container.read(mergeControllerProvider), isA<MergeSigningIn>());
      expect(
        (await vaultHoldOf(anonId, directory: dir.path, factory: databaseFactoryFfi))?.target,
        email,
      );

      await session.verifyCode(email, '123456', replaceGuest: true);
      await merge.resume();
      targetReady = true;
      container.invalidate(mergeTargetProvider);
      await merge.run();
      expect(container.read(mergeControllerProvider), isA<MergeDone>());
      expect(deletes(), 1);
    },
  );

  test('begin holds the anonymous vault and keeps its token before any code is sent', () async {
    final container = app();
    await container.read(sessionProvider.notifier).ready;
    await container.read(mergeControllerProvider.notifier).begin(email);

    final hold = await vaultHoldOf(anonId, directory: dir.path, factory: databaseFactoryFfi);
    expect(hold?.kind, VaultHoldKind.merging);
    expect(hold?.target, email);
    expect((await kept())[mergeTokenKey(anonId)], anonToken);
    expect(auth.calls.where((c) => c.startsWith('sendCode')), isEmpty);
  });

  test(
    'the merge\'s sign-in takes the captures queued for the guest, and a cancel gives them back',
    () async {
      auth
        ..account = accountId
        ..accounts[anonToken] = anonId;
      final container = await signedInToTheAccount();
      await pumpEventQueue();
      expect(capture.callsNamed('sendQueued').last, 'sendQueued $accountId from $anonId');
      expect(capture.callsNamed('sendQueued'), isNot(contains('sendQueued $accountId')));

      capture.calls.clear();
      await container.read(mergeControllerProvider.notifier).cancel();
      await pumpEventQueue();
      expect(capture.callsNamed('sendQueued'), ['sendQueued $anonId from $accountId']);
    },
  );

  test('killed while the cancel signs the email account out: the restart is the guest with its '
      'data', () async {
    final container = await signedInToTheAccount();
    auth.holdSignOut = Completer<void>();
    await container.read(mergeControllerProvider.notifier).cancel();
    // The sign-out on the server is still waiting: the app is killed.
    container.dispose();

    final again = app();
    await again.read(sessionProvider.notifier).ready;
    expect(again.read(sessionProvider).stored?.token, anonToken);
    expect(again.read(sessionProvider).isGuest, isTrue);
    expect(fileOf(anonId), isTrue);
    expect((await kept())['wambito.vault.$anonId.device'], 'BBBB');
    final store = await open(anonId);
    expect((await store.get(RecordType.transaction, pTx))?.body['categoryId'], pFood);
    await store.close();
    auth.holdSignOut!.complete();
  });

  test(
    'killed after the carry committed but before its mark: the next run never carries again',
    () async {
      final first = await signedInToTheAccount();
      first.dispose();
      // The carry committed in the account's vault; the process died before the old vault said so.
      final source = await open(anonId);
      await carryRecords(source, accountStore, mode: CarryMode.merge, intoUserId: accountId);
      await source.close();
      final edited = Map<String, Object?>.of(
        (await accountStore.get(RecordType.transaction, mTx))!.body,
      )..['name'] = 'Mercado del barrio';
      await accountStore.put(RecordType.transaction, mTx, edited);

      final container = app();
      await container.read(sessionProvider.notifier).ready;
      final merge = container.read(mergeControllerProvider.notifier);
      await merge.resume();
      targetReady = true;
      container.invalidate(mergeTargetProvider);
      await merge.run();

      expect(container.read(mergeControllerProvider), isA<MergeDone>());
      expect(
        (await accountStore.get(RecordType.transaction, mTx))?.body['name'],
        'Mercado del barrio',
      );
    },
  );

  test('keep only the account\'s data, then a failure: the next start finishes it and never stops '
      'at the currency again', () async {
    await accountStore.close();
    await databaseFactoryFfi.deleteDatabase(p.join(dir.path, vaultFileName(accountId)));
    await accountVault(currency: 'USD');
    final first = await signedInToTheAccount();
    targetReady = true;
    first.invalidate(mergeTargetProvider);
    await first.read(mergeControllerProvider.notifier).run();
    expect(first.read(mergeControllerProvider), isA<MergeCurrencyStop>());
    auth.failures['deleteUser'] = const AuthFailure(status: 0);
    await first.read(mergeControllerProvider.notifier).keepAccountOnly();
    expect(first.read(mergeControllerProvider), isA<MergeFailed>());
    first.dispose();

    final container = app();
    await container.read(sessionProvider.notifier).ready;
    final merge = container.read(mergeControllerProvider.notifier);
    await merge.resume();
    container.invalidate(mergeTargetProvider);
    await merge.run();

    expect(container.read(mergeControllerProvider), isA<MergeDone>());
    expect(fileOf(anonId), isFalse);
    expect(await accountStore.get(RecordType.transaction, mTx), isNull);
  });

  test('a carried record the server refuses for good keeps the anonymous user', () async {
    final container = await signedInToTheAccount();
    targetReady = true;
    container.invalidate(mergeTargetProvider);
    sync.refused.add(mTx);
    await container.read(mergeControllerProvider.notifier).run();

    final state = container.read(mergeControllerProvider);
    expect(state, isA<MergeFailed>());
    expect((state as MergeFailed).code, 'refused');
    expect(state.carried, isTrue);
    expect(await pendingOf(accountStore), 0);
    expect(deletes(), 0);
    expect(fileOf(anonId), isTrue);
    expect((await kept())[mergeTokenKey(anonId)], anonToken);
  });

  test('a synced guest\'s merge pushes no id the guest already owns, and finishes', () async {
    // The guest synced its records before: on the server those ids are the anonymous user's.
    final owned = <String>{settingsIdOf(anonId), pFood, pTx};
    sync.refused.addAll(owned);
    final container = await signedInToTheAccount();
    targetReady = true;
    container.invalidate(mergeTargetProvider);
    await container.read(mergeControllerProvider.notifier).run();

    expect(sync.pushed.where(owned.contains), isEmpty);
    expect(container.read(mergeControllerProvider), isA<MergeDone>());
    expect((await accountStore.rawRecord(RecordType.transaction, mTx))?.version, greaterThan(0));
    expect(await accountStore.get(RecordType.transaction, pTx), isNull);
    expect(deletes(), 1);
  });

  test('killed right after the merge\'s sign-in: the next start still hands the guest\'s captures '
      'over', () async {
    auth
      ..account = accountId
      ..accounts[anonToken] = anonId;
    // Nothing reaches Android before the kill.
    capture.available = false;
    final first = await signedInToTheAccount();
    first.dispose();

    capture
      ..available = true
      ..calls.clear();
    final again = app();
    await again.read(sessionProvider.notifier).refreshed;
    await pumpEventQueue();
    expect(capture.callsNamed('sendQueued').first, 'sendQueued $accountId from $anonId');
  });
}
