// The offline first run (phone-first spec 4, ruling 8): "Start" without network, on a server known
// to make encrypted users, lands on a provisional vault; once the network answers, the shared
// adoption (Task 10) promotes it into one anonymous user. Real SQLite vaults in a temp dir, a fake
// auth server, a fake `/v2/keys` and a fake `/v2/sync`.
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/api/auth_api.dart' show AuthFailure;
import 'package:wambito/api/device.dart';
import 'package:wambito/api/server_url.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/capture/models_download.dart' show preciseEligibleProvider;
import 'package:wambito/capture_auto/capture_platform.dart' show autoCapturePlatformProvider;
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/home/home_cache.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/local/adopt.dart';
import 'package:wambito/local/db.dart' show VaultHoldKind, vaultFileName, vaultHoldOf;
import 'package:wambito/local/keys.dart';
import 'package:wambito/local/memory_store.dart' show createMemoryStore;
import 'package:wambito/local/provisional.dart';
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/sync.dart';
import 'package:wambito/local/vault_lock.dart' show VaultLease;
import 'package:wambito/router.dart';
import 'package:wambito/vault/vault_providers.dart';

import '../capture_auto/fakes.dart';
import '../entry/fakes.dart';
import '../home/fakes.dart';
import '../local/fake_keys.dart' show FakeKeys;
import '../local/fake_sync.dart';
import '../local/merge_test.dart' show category, transaction;

const food = '01930000-0000-7000-8000-00000000d001';
const tx = '01930000-0000-7000-8000-00000000d003';

/// An auth server that can be offline, and whose every anonymous sign-up is a new user (`new_1`, …),
/// `plain` when [plain].
class _Auth extends FakeAuthApi {
  bool offline = false;
  bool plain = false;
  var made = 0;

  @override
  Future<String> signInAsGuest() async {
    if (offline) {
      calls.add('signInAsGuest');
      throw const AuthFailure(status: 0);
    }
    final token = await super.signInAsGuest();
    accounts[token] = 'new_${++made}';
    if (plain) plainTokens.add(token);
    return token;
  }

  @override
  Future<String> accountId(String token) async {
    calls.add('accountId $token');
    if (offline) throw const AuthFailure(status: 0);
    return accounts[token] ?? account;
  }
}

class _NoLease implements VaultLease {
  @override
  Future<bool> renew() async => true;

  @override
  Future<void> release() async {}
}

/// The app's own client must never reach a server while provisional: every request it sends
/// past the vault is recorded and fails as offline.
class _NoNetwork implements HttpClientAdapter {
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add('${options.method} ${options.uri.path}');
    throw DioException.connectionError(requestOptions: options, reason: 'offline');
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory dir;
  late _Auth auth;
  late FakeKeys keysServer;
  late FakeAutoCapturePlatform capture;

  Future<SqliteStore> open(String id) =>
      SqliteStore.open(id, directory: dir.path, factory: databaseFactoryFfi, background: true);
  bool fileOf(String id) => File(p.join(dir.path, vaultFileName(id))).existsSync();
  KeyStorage keyStorage() => KeyStorage(const FlutterSecureStorage());
  Future<Map<String, String>> kept() => const FlutterSecureStorage().readAll();
  List<String> vaultFiles() => [
    for (final e in dir.listSync())
      if (e.path.endsWith('.db')) p.basename(e.path),
  ];

  Future<void> forget(String id) async {
    await databaseFactoryFfi.deleteDatabase(p.join(dir.path, vaultFileName(id)));
    await keyStorage().deleteAll(id);
  }

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
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wambito-provisional-session');
    auth = _Auth();
    keysServer = FakeKeys();
    capture = FakeAutoCapturePlatform();
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// The app's session, as one start of the process: a new container on the same disk.
  ProviderContainer start({bool encryptedServer = true}) {
    final container = ProviderContainer(
      overrides: [
        authApiProvider.overrideWithValue(auth),
        passkeysProvider.overrideWithValue(FakePasskeys()),
        widgetStoreProvider.overrideWithValue(FakeWidgetStore()),
        homeCacheStoreProvider.overrideWithValue(FakeCacheStore()),
        autoCapturePlatformProvider.overrideWithValue(capture),
        forgetVaultProvider.overrideWithValue((id, storage) => forget(id)),
        adoptDepsProvider.overrideWith((ref) => deps()),
        newUsersEncryptedByBuildProvider.overrideWithValue(encryptedServer),
        provisionalOpenerProvider.overrideWithValue(
          (id) => openProvisionalVault(
            id,
            const DeviceHints(timezone: 'America/Bogota', locale: 'es-CO'),
            directory: dir.path,
            factory: databaseFactoryFfi,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ProviderContainer> startedOffline() async {
    auth.offline = true;
    final container = start();
    await container.read(sessionProvider.notifier).startGuest();
    return container;
  }

  String location(ProviderContainer c, String path) =>
      sessionRedirect(c.read(sessionProvider), Uri.parse(path)) ?? path;

  test('Start without network, on a server known to make encrypted users, lands home on a provisional vault', () async {
    final container = await startedOffline();
    final session = container.read(sessionProvider);
    expect(session.status, SessionStatus.provisional);
    final localId = session.localId!;
    expect(localId, startsWith('local-'));
    expect(session.stored, isNull);
    expect((await kept())[SessionStore.provisionalKey], localId);
    // Home is open; the entry, Unlock and "Guarda tu progreso" go home.
    expect(location(container, '/'), '/');
    expect(location(container, '/settings'), '/settings');
    expect(location(container, '/entry'), '/');
    expect(location(container, '/unlock'), '/');
    expect(location(container, '/progress'), '/');
    expect(location(container, '/auth/verify'), '/');
    // The screens' `/v1` is answered by the vault: its seeded categories.
    final client = container.read(apiClientProvider);
    final network = _NoNetwork();
    client.dio.httpClientAdapter = network;
    final categories = await client.dio.get<Object?>('/v1/categories');
    expect(categories.statusCode, 200);
    expect(categories.data, isA<List<Object?>>().having((l) => l.length, 'length', isNonZero));
    expect(network.paths, isEmpty);
    // The vault is held, and the captures queued from now on are its.
    expect(
      (await vaultHoldOf(localId, directory: dir.path, factory: databaseFactoryFfi))?.kind,
      VaultHoldKind.provisional,
    );
    await Future<void>.delayed(Duration.zero);
    expect(capture.callsNamed('sendQueued'), ['sendQueued $localId']);
    // No sign-in while provisional.
    await expectLater(
      container.read(sessionProvider.notifier).sendCode('ana@wambito.test'),
      throwsStateError,
    );
  });

  test('nothing is pushed or sealed while the user id is unknown', () async {
    final container = await startedOffline();
    final client = container.read(apiClientProvider);
    final network = _NoNetwork();
    client.dio.httpClientAdapter = network;
    final categories = (await client.dio.get<List<Object?>>('/v1/categories')).data!;
    final categoryId = (categories.first! as Map)['id']! as String;
    final made = await client.dio.post<Object?>(
      '/v1/transactions',
      data: {'name': 'Pan', 'amount': -1250, 'categoryId': categoryId, 'date': '2026-11-18'},
    );
    expect(made.statusCode, 201);
    // A finance route the vault does not answer stops at the guard; none reached a server.
    await expectLater(client.dio.get<Object?>('/v1/imports'), throwsA(isA<DioException>()));
    expect(network.paths.where((path) => path.contains('/v1/')), isEmpty);
    // No user, no keys, no sync: nothing was asked of the server.
    expect(keysServer.calls, isEmpty);
    expect(auth.made, 0);
    expect((await kept()).keys.where((k) => k.startsWith('wambito.vault.')), isEmpty);
  });

  test('killed and reopened offline three times: one provisional id, one vault; online, one anonymous sign-in', () async {
    final first = await startedOffline();
    final localId = first.read(sessionProvider).localId!;
    await first
        .read(provisionalVaultProvider)!
        .store
        .put(RecordType.category, food, category('Comida'));
    // Killed: the file is left as it is (closed here only so the next start can open it).
    await first.read(provisionalVaultProvider.notifier).close();
    first.dispose();

    for (var i = 0; i < 3; i++) {
      final again = start();
      final session = again.read(sessionProvider.notifier);
      await session.ready;
      expect(again.read(sessionProvider).localId, localId);
      // The start's promotion finds no network: nothing made, nothing lost.
      expect(await session.promoteProvisional(), isFalse);
      // A second Start (a person tapping again) reuses the same vault.
      await session.startGuest();
      expect(again.read(sessionProvider).localId, localId);
      await again.read(provisionalVaultProvider.notifier).close();
      again.dispose();
    }
    expect(vaultFiles(), [vaultFileName(localId)]);
    expect(auth.made, 0);

    auth.offline = false;
    final online = start();
    final session = online.read(sessionProvider.notifier);
    await session.ready;
    expect(await session.promoteProvisional(), isTrue);
    // Asked again (a resume, the minute's tick): nothing more is made.
    expect(await session.promoteProvisional(), isFalse);
    expect(auth.made, 1);
    expect(online.read(sessionProvider).status, SessionStatus.signedIn);
    expect(online.read(sessionProvider).isGuest, isTrue);
    expect(vaultFiles(), [vaultFileName('new_1')]);
    final store = await open('new_1');
    expect((await store.list(RecordType.category)).map((r) => r.id), contains(food));
    await store.close();
    final storage = await kept();
    expect(storage.containsKey(SessionStore.provisionalKey), isFalse);
    expect(storage.containsKey(SessionStore.provisionalTokenKey), isFalse);
  });

  test(
    'online on a preview server: the records reach the user\'s vault and sync sealed under its id',
    () async {
      final container = await startedOffline();
      final localId = container.read(sessionProvider).localId!;
      final vault = container.read(provisionalVaultProvider)!;
      await vault.store.put(RecordType.category, food, category('Comida'));
      await vault.store.put(RecordType.transaction, tx, transaction(food));

      auth.offline = false;
      expect(await container.read(sessionProvider.notifier).promoteProvisional(), isTrue);
      const newId = 'new_1';
      expect(container.read(sessionProvider).stored?.token, 'guest-token-1');
      expect(fileOf(localId), isFalse);
      // The token was kept before anything was carried, then dropped once the session was its.
      expect((await kept()).containsKey(SessionStore.provisionalTokenKey), isFalse);
      // The captures queued while provisional are the new user's.
      expect(capture.callsNamed('sendQueued'), contains('sendQueued $newId from $localId'));

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
      final keys = currentRecordKeys(local);
      final pushed = <String, Object?>{};
      for (final row in server.rows.values) {
        pushed[row['id']! as String] = await openRecord(
          keys,
          RecordContext(
            userId: newId,
            type: RecordType.values.byName(row['type']! as String),
            id: row['id']! as String,
            keyV: row['keyV']! as int,
          ),
          fromBase64Url(row['body']! as String),
        );
      }
      expect(pushed.keys, containsAll([food, tx]));
      expect((pushed[tx]! as Map)['categoryId'], food);
      // Under the local id nothing opens: the AAD is the new user's.
      final row = server.rows[tx]!;
      await expectLater(
        openRecord(
          keys,
          RecordContext(
            userId: localId,
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

  test('a promotion that finds a plain user sends nothing to /v1, signs that session out, keeps the vault and sets provisionalBlock plainServer', () async {
    final container = await startedOffline();
    final localId = container.read(sessionProvider).localId!;
    await container
        .read(provisionalVaultProvider)!
        .store
        .put(RecordType.transaction, tx, transaction(food));
    final server = container.read(serverUrlProvider);
    await rememberNewUsersEncrypted(server);

    auth
      ..offline = false
      ..plain = true;
    expect(await container.read(sessionProvider.notifier).promoteProvisional(), isFalse);
    final session = container.read(sessionProvider);
    expect(session.status, SessionStatus.provisional);
    expect(session.localId, localId);
    expect(session.provisionalBlock, ProvisionalBlock.plainServer);
    // That anonymous session is signed out on the server; its token is not kept.
    expect(auth.calls, contains('signOut guest-token-1'));
    expect((await kept()).containsKey(SessionStore.provisionalTokenKey), isFalse);
    // The server makes plain users after all: an offline Start needs the network again.
    expect((await kept()).containsKey(newUsersKeyOf(server)), isFalse);
    // Nothing went to `/v1` (nor any key was made), and the vault is kept, held, with its data.
    expect(keysServer.calls.where((c) => c.path.contains('/v1/')), isEmpty);
    expect(keysServer.calls, isEmpty);
    expect(
      (await vaultHoldOf(localId, directory: dir.path, factory: databaseFactoryFfi))?.kind,
      VaultHoldKind.provisional,
    );
    expect(fileOf('new_1'), isFalse);
    // The app's vault opens again for the person.
    await until(() => container.read(provisionalVaultProvider) != null);
    expect(
      (await container.read(provisionalVaultProvider)!.store.list(RecordType.transaction))
          .single
          .id,
      tx,
    );
    final client = container.read(apiClientProvider);
    final network = _NoNetwork();
    client.dio.httpClientAdapter = network;
    await client.dio.get<Object?>('/v1/transactions');
    expect(network.paths.where((path) => path.contains('/v1/transactions')), isEmpty);
    expect(network.paths.where((path) => path.contains('/v1/categories')), isEmpty);
  });

  testWidgets(
    'GUEST_SIGNUP closed: stays provisional with provisionalBlock noGuests and Settings says why',
    (tester) async {
      final fake = FakeAuthApi()..failures['signInAsGuest'] = const AuthFailure(status: 0);
      final opened = <String>[];
      final container = await pumpApp(
        tester,
        auth: fake,
        overrides: [
          newUsersEncryptedByBuildProvider.overrideWithValue(true),
          provisionalPromotionEveryProvider.overrideWithValue(null),
          // Settings asks the phone what voice model fits it; not this test's business.
          preciseEligibleProvider.overrideWith((ref, locale) async => false),
          provisionalOpenerProvider.overrideWithValue((id) async {
            opened.add(id);
            return LocalOnlyVault(id, createMemoryStore());
          }),
          // The promotion's adoption, on a folder of its own (the vault is in memory here).
          adoptDepsProvider.overrideWith(
            (ref) => AdoptDeps(
              auth: fake,
              keys: keyStorage(),
              network: (token) => keysServer.dio(),
              openStore: open,
              lease: (id) async => _NoLease(),
              forgetVault: forget,
              now: DateTime.now,
              keptToken: () async => null,
              keepToken: (t) async {},
              forgetToken: () async {},
              directory: dir.path,
            ),
          ),
        ],
      );
      await tester.tap(find.byKey(const Key('entry.start')));
      await tester.pumpAndSettle();
      expect(container.read(sessionProvider).status, SessionStatus.provisional);
      expect(opened, hasLength(1));

      // Online now, but the server takes no new accounts without email.
      fake.failures['signInAsGuest'] = const AuthFailure(
        code: 'guest_signup_disabled',
        status: 403,
      );
      expect(await container.read(sessionProvider.notifier).promoteProvisional(), isFalse);
      await tester.pumpAndSettle();
      expect(container.read(sessionProvider).status, SessionStatus.provisional);
      expect(container.read(sessionProvider).provisionalBlock, ProvisionalBlock.noGuests);

      container.read(routerProvider).go('/settings');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings.provisional')), findsOneWidget);
      expect(
        find.text(
          'Tus datos siguen en este teléfono. Este servidor no acepta cuentas nuevas sin correo por ahora.',
        ),
        findsOneWidget,
      );
      // No sign-in, no server change, no account card while provisional.
      expect(find.byKey(const Key('settings.signOut')), findsNothing);
      expect(find.byKey(const Key('settings.server')), findsNothing);
    },
  );
}

/// Waits (real time) until [ready] holds.
Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ready(), isTrue);
}
