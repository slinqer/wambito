// Port of apps/web/app/local/vault-session.test.ts, plus signOutDuringSyncLeavesNothing and
// reinstallClearsOldKeys (Review Focus 4 and 1).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/core/suggested_categories.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/ids.dart';
import 'package:wambito/local/install_marker.dart';
import 'package:wambito/local/keys.dart';
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/sync.dart';
import 'package:wambito/local/vault_session.dart';

import 'fake_keys.dart';

late Directory _dir;
var _counter = 0;

VaultProfile profileOf() => VaultProfile(
  id: 'vault_user_${++_counter}',
  email: 'ana@wambito.test',
  isAnonymous: false,
  locale: 'es',
  timezone: 'America/Bogota',
);

Future<SqliteStore> openStore(String userId) =>
    SqliteStore.open(userId, directory: _dir.path, factory: databaseFactoryFfi);

Future<void> deleteStore(String userId) =>
    deleteVault(userId, directory: _dir.path, factory: databaseFactoryFfi);

bool vaultExists(String userId) => File(p.join(_dir.path, vaultFileName(userId))).existsSync();

Future<LocalKeys> keys() async => LocalKeys(
  keyring: Keyring(current: 1, byVersion: {1: await deriveRecordKeys(generateDataKey())}),
);

ResponseBody _json(Object? body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, Object?>? _body(Object? data) => data is Map
    ? (jsonDecode(jsonEncode(data)) as Map).cast<String, Object?>()
    : data is String && data.isNotEmpty
    ? (jsonDecode(data) as Map).cast<String, Object?>()
    : null;

enum Mode { ok, offline, unauthorized, sessionChanged }

/// An empty `/v2/sync` that takes every push; [mode] makes it fail.
class FakeNetwork implements HttpClientAdapter {
  Mode mode = Mode.ok;
  int pushed = 0;

  /// The `keyV` of every pushed change, in order.
  final List<int> pushedKeyV = [];

  /// Records the pull hands out (e.g. one under a key version this phone never got).
  List<Object?> records = [];
  final List<String> live = [];

  /// The `x-wambito-user` of every `/v2` call.
  final List<String?> users = [];

  /// When set, a pull waits for it; [pullHeld] completes once one does.
  Completer<void>? holdPull;
  final Completer<void> pullHeld = Completer();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    final method = options.method.toUpperCase();
    if (mode == Mode.offline) {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    if (path.startsWith('/api/v2/')) users.add(options.headers['x-wambito-user'] as String?);
    if (mode == Mode.unauthorized) return _json({'code': 'unauthenticated'}, 401);
    if (mode == Mode.sessionChanged && path.startsWith('/api/v2/')) {
      return _json({'code': 'session_changed'}, 409);
    }
    if (path == '/api/v2/sync' && method == 'GET') {
      final hold = holdPull;
      if (hold != null) {
        if (!pullHeld.isCompleted) pullHeld.complete();
        await hold.future;
      }
      return _json({'records': records, 'next': null, 'latest': pushed + records.length});
    }
    if (path == '/api/v2/sync' && method == 'POST') {
      final changes = (_body(options.data)!['changes']! as List).cast<Map<Object?, Object?>>();
      pushedKeyV.addAll(changes.map((c) => c['keyV']! as int));
      return _json({
        'results': [
          for (final c in changes) {'id': c['id'], 'version': ++pushed},
        ],
      });
    }
    live.add('$method $path');
    return ResponseBody.fromString('', 204);
  }

  @override
  void close({bool force = false}) {}
}

/// An account's server for the real `keys.dart` (`/v2/keys` from [FakeKeys]) and a `/v2/sync`
/// that takes a change only at the account's [current] key version.
class FakeAccount implements HttpClientAdapter {
  final FakeKeys keys = FakeKeys();
  int current = 1;
  final List<({String id, int keyV})> pushed = [];
  final Map<String, ({int version, int keyV})> rows = {};
  int counter = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    final method = options.method.toUpperCase();
    if (path == '/api/v2/sync' && method == 'GET') {
      return _json({'records': <Object?>[], 'next': null, 'latest': counter});
    }
    if (path == '/api/v2/sync' && method == 'POST') {
      final changes = (_body(options.data)!['changes']! as List).cast<Map<Object?, Object?>>();
      final results = [
        for (final c in changes)
          if (c['keyV'] != current)
            {'id': c['id'], 'error': 'key_version_mismatch', 'keyV': current}
          else
            () {
              final id = c['id']! as String;
              pushed.add((id: id, keyV: c['keyV']! as int));
              final version = ++counter;
              rows[id] = (version: version, keyV: c['keyV']! as int);
              return {'id': id, 'version': version};
            }(),
      ];
      return _json({'results': results});
    }
    return keys.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

Dio network(HttpClientAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'http://x/api'))..httpClientAdapter = adapter;

/// The app's client: the session's interceptor in front of the network.
Dio appDio(VaultSession session, HttpClientAdapter adapter) =>
    network(adapter)..interceptors.add(session.interceptor);

Future<Response<Object?>> send(Dio dio, String method, String path, [Object? data]) async {
  try {
    return await dio.request<Object?>(
      path,
      data: data,
      options: Options(method: method),
    );
  } on DioException catch (e) {
    final response = e.response;
    if (response == null) rethrow;
    return response;
  }
}

Future<void> until(bool Function() done, {int timeoutMs = 4000}) async {
  final stop = DateTime.now().add(Duration(milliseconds: timeoutMs));
  while (!done()) {
    if (DateTime.now().isAfter(stop)) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

late KeyStorage storage;

/// Every account a test opened: forgotten after it.
final _opened = <String>{};

Future<VaultSession> open(
  VaultProfile profile, {
  required HttpClientAdapter net,
  required LocalKeys keys,
  bool fresh = true,
  void Function()? onUnauthorized,
  void Function()? onSessionChanged,
  Future<SqliteStore> Function(String userId)? store,
  Future<LocalKeys> Function(KeysOptions options)? refresh,
}) {
  _opened.add(profile.id);
  return openVaultSession(
    OpenVaultOptions(
      profile: profile,
      keys: keys,
      fresh: fresh,
      network: network(net),
      storage: storage,
      onUnauthorized: onUnauthorized,
      onSessionChanged: onSessionChanged,
      openStore: store ?? openStore,
      deleteStore: deleteStore,
      syncDebounce: const Duration(milliseconds: 20),
      refreshKeys: refresh,
    ),
  );
}

Future<Object?> failure(Future<Object?> future) async {
  try {
    await future;
    return null;
  } on Object catch (e) {
    return e;
  }
}

Matcher isOpenError(SyncProblemCode code) =>
    isA<VaultOpenError>().having((e) => e.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  setUpAll(() => _dir = Directory.systemTemp.createTempSync('wambito-session-test'));
  tearDownAll(() => _dir.deleteSync(recursive: true));
  setUp(() => storage = memoryKeyStorage());
  tearDown(() async {
    for (final id in _opened) {
      await forgetVault(id, storage, deleteStore: deleteStore);
    }
    _opened.clear();
  });

  group('openVaultSession', () {
    test(
      'seeds a new account with its settings and the suggested categories, as records',
      () async {
        final net = FakeNetwork();
        final profile = profileOf();
        final session = await open(profile, net: net, keys: await keys());
        final dio = appDio(session, net);
        final me = (await send(dio, 'GET', '/v1/me')).data! as Map;
        expect(me['id'], profile.id);
        expect(me['email'], 'ana@wambito.test');
        expect(me['locale'], 'es');
        expect(me['timezone'], 'America/Bogota');
        expect(me['currency'], 'EUR');
        expect(me['onboardingCompletedAt'], isNull);
        expect(me['encryption'], 'preview');
        final categories = (await send(dio, 'GET', '/v1/categories')).data! as List;
        expect(categories.length, greaterThan(3));
        expect(categories.map((c) => (c as Map)['name']), contains('Supermercado'));

        // a second open reuses it, without seeding again
        final again = await open(profile, net: net, keys: await keys(), fresh: false);
        expect(identical(again, session), isTrue);
      },
    );

    test('gives the seeded records ids made from the account, so two devices seed the same '
        'ones', () async {
      final profile = profileOf();
      SqliteStore? opened;
      await open(
        profile,
        net: FakeNetwork(),
        keys: await keys(),
        store: (userId) async => opened = await openStore(userId),
      );
      final store = opened!;
      final [settings] = await store.list(RecordType.settings);
      final categories = await store.list(RecordType.category);
      expect(settings.body['timezone'], 'America/Bogota');
      expect(settings.body['locale'], 'es');
      expect(settings.body['currency'], 'EUR');
      // The ids are the same on every device for this account, and differ between accounts.
      final namespace = uuidv5('6f1f7a4e-0c5b-5e0a-9a3e-2b1d6c8f4a10', profile.id);
      expect(settings.id, uuidv5(namespace, 'settings'));
      expect(categories.length, greaterThan(3));
      expect(categories.map((c) => c.id).toSet(), hasLength(categories.length));
      for (final category in categories) {
        expect(category.body.containsKey('createdAt'), isFalse);
        final key = suggestedCategories
            .firstWhere((s) => s.names[SuggestionLocale.es] == category.body['name'])
            .key;
        expect(category.id, uuidv5(namespace, 'category:$key'));
      }
    });

    test('refuses what a preview account cannot do yet, and sends deleting the account to the '
        'API', () async {
      final net = FakeNetwork();
      final session = await open(profileOf(), net: net, keys: await keys());
      final dio = appDio(session, net);
      expect((await send(dio, 'GET', '/v1/me/export?format=json')).statusCode, 403);
      expect((await send(dio, 'POST', '/v1/imports')).statusCode, 403);
      expect((await send(dio, 'GET', '/v1/me/assistants')).statusCode, 403);
      expect((await send(dio, 'DELETE', '/v1/me')).statusCode, 204);
      expect(net.live, ['DELETE /api/v1/me']);
    });

    test(
      'a fresh vault needs its first sync; a known one opens offline on its local data',
      () async {
        final net = FakeNetwork()..mode = Mode.offline;
        final profile = profileOf();
        expect(
          await failure(open(profile, net: net, keys: await keys())),
          isOpenError(SyncProblemCode.offline),
        );
        final session = await open(profile, net: net, keys: await keys(), fresh: false);
        expect((await send(appDio(session, net), 'GET', '/v1/me')).statusCode, 200);
      },
    );

    test('a 401 from the sync stops the opening and reports it', () async {
      final net = FakeNetwork()..mode = Mode.unauthorized;
      var unauthorized = 0;
      expect(
        await failure(
          open(
            profileOf(),
            net: net,
            keys: await keys(),
            fresh: false,
            onUnauthorized: () => unauthorized += 1,
          ),
        ),
        isOpenError(SyncProblemCode.unauthorized),
      );
      expect(unauthorized, greaterThan(0));
    });
  });

  group('seeding', () {
    test('does not seed when the first sync failed (a known phone offline)', () async {
      final net = FakeNetwork()..mode = Mode.offline;
      SqliteStore? store;
      final session = await open(
        profileOf(),
        net: net,
        keys: await keys(),
        fresh: false,
        store: (userId) async => store = await openStore(userId),
      );
      expect(await store!.list(RecordType.settings), isEmpty);
      expect(await store!.list(RecordType.category), isEmpty);
      await session.close();
    });

    test('does not seed over changes a failed resync set aside', () async {
      final net = FakeNetwork()..mode = Mode.offline;
      final profile = profileOf();
      final store = await openStore(profile.id);
      await store.put(RecordType.category, '01930000-0000-7000-8000-0000000000aa', {
        's': 1,
        'name': 'Mine',
        'kind': 'expense',
        'icon': 'x',
        'color': '#fff',
        'sortOrder': 0,
        'archivedAt': null,
        'systemKey': null,
      });
      await store.wipeRecords();
      final session = await open(
        profile,
        net: net,
        keys: await keys(),
        fresh: false,
        store: (_) async => store,
      );
      expect(await store.list(RecordType.settings), isEmpty);
      expect((await store.readOutbox(10)).map((e) => e.setAside != null), [true]);
      await session.close();
    });
  });

  group('another account signed in', () {
    test("names the vault's account on every sync call", () async {
      final net = FakeNetwork();
      final profile = profileOf();
      final session = await open(profile, net: net, keys: await keys());
      expect(net.users, isNotEmpty);
      expect(net.users.every((u) => u == profile.id), isTrue);
      await session.close();
    });

    test('a 409 session_changed on opening fails it, even for a known phone', () async {
      final net = FakeNetwork()..mode = Mode.sessionChanged;
      expect(
        await failure(open(profileOf(), net: net, keys: await keys(), fresh: false)),
        isOpenError(SyncProblemCode.sessionChanged),
      );
    });

    test('a 409 session_changed later closes the session and tells onSessionChanged', () async {
      final net = FakeNetwork();
      var sessionChanged = 0;
      SqliteStore? store;
      final session = await open(
        profileOf(),
        net: net,
        keys: await keys(),
        onSessionChanged: () => sessionChanged += 1,
        store: (userId) async => store = await openStore(userId),
      );
      var closed = 0;
      session.onClosed(() => closed += 1);
      await wait(100); // the start's own run
      net.mode = Mode.sessionChanged;
      // A local write (through the interceptor) triggers the next sync.
      final dio = appDio(session, net);
      final first = ((await send(dio, 'GET', '/v1/categories')).data! as List).first as Map;
      await send(dio, 'PATCH', '/v1/categories/${first['id']}', {'name': 'Edited'});
      await until(() => sessionChanged == 1);
      expect(store!.isClosed, isTrue);
      expect(closed, 0);
      // the session is gone: the next open makes a new one
      net.mode = Mode.ok;
      final again = await open(profileOf(), net: net, keys: await keys());
      expect(identical(again, session), isFalse);
      await again.close();
    });
  });

  group('a vault closed under the session', () {
    test('drops the session and tells onClosed', () async {
      final net = FakeNetwork();
      final profile = profileOf();
      SqliteStore? store;
      final session = await open(
        profile,
        net: net,
        keys: await keys(),
        store: (userId) async => store = await openStore(userId),
      );
      var closed = 0;
      session.onClosed(() => closed += 1);
      await store!.close();
      expect(closed, 1);
      // the next open makes a new session instead of handing back the dead one
      final again = await open(profile, net: net, keys: await keys(), fresh: false);
      expect(identical(again, session), isFalse);
      await again.close();
    });

    test('closing the session itself does not report a close', () async {
      final session = await open(profileOf(), net: FakeNetwork(), keys: await keys());
      var closed = 0;
      session.onClosed(() => closed += 1);
      await session.close();
      expect(closed, 0);
    });
  });

  group('forgetVault', () {
    test("closes the session and deletes this phone's vault", () async {
      final profile = profileOf();
      await open(profile, net: FakeNetwork(), keys: await keys());
      expect(vaultExists(profile.id), isTrue);
      await forgetVault(profile.id, storage, deleteStore: deleteStore);
      expect(vaultExists(profile.id), isFalse);
      // nothing left to read
      final store = await openStore(profile.id);
      expect(await store.list(RecordType.settings), isEmpty);
      await store.close();
    });

    test('does nothing when the account never opened a vault here', () async {
      await expectLater(
        forgetVault('vault_user_never', storage, deleteStore: deleteStore),
        completes,
      );
    });

    test('signOutDuringSyncLeavesNothing: a sync in flight at sign-out ends closed and leaves '
        'neither the vault nor its keys', () async {
      final net = FakeNetwork();
      final profile = profileOf();
      final dk = generateDataKey();
      await storage.writeDataKey(profile.id, 1, dk);
      await storage.setCurrent(profile.id, 1);
      final session = await open(
        profile,
        net: net,
        keys: LocalKeys(keyring: Keyring(current: 1, byVersion: {1: await deriveRecordKeys(dk)})),
      );
      await wait(100); // the start's own run
      final hold = net.holdPull = Completer<void>();
      final syncing = session.sync();
      await net.pullHeld.future;
      await forgetVault(profile.id, storage, deleteStore: deleteStore);
      expect(vaultExists(profile.id), isFalse);
      hold.complete();
      final result = await syncing;
      expect(result.ok, isFalse);
      expect(result.error, SyncProblemCode.closed);
      await wait(50);
      expect(vaultExists(profile.id), isFalse);
      expect(await storedEntries(), isEmpty);
    });
  });

  group('a key refresh in flight at sign-out', () {
    // A pulled record under key version 2 makes the run refresh the keys; the refresh is held
    // across `forgetVault`, then ends as [outcome] says.
    const rotated = {
      'id': '01930000-0000-7000-8000-0000000000fe',
      'type': 'category',
      'version': 1,
      'deleted': false,
      'keyV': 2,
      'encV': 1,
      'body': 'AAAA',
    };

    Future<({VaultSession session, Completer<void> hold, Completer<void> started})> heldRefresh(
      VaultProfile profile,
      FakeNetwork net,
      Future<LocalKeys> Function() outcome,
    ) async {
      final dk = generateDataKey();
      await storage.writeDataKey(profile.id, 1, dk);
      await storage.setCurrent(profile.id, 1);
      final hold = Completer<void>();
      final started = Completer<void>();
      var first = true;
      final session = await open(
        profile,
        net: net,
        keys: LocalKeys(keyring: Keyring(current: 1, byVersion: {1: await deriveRecordKeys(dk)})),
        refresh: (_) async {
          if (!first) throw const KeysError('device_removed');
          first = false;
          started.complete();
          await hold.future;
          return outcome();
        },
      );
      await wait(100); // the start's own run
      return (session: session, hold: hold, started: started);
    }

    for (final (name, ends) in [
      ('success', 'ok'),
      ('device_removed', 'device_removed'),
      ('tampered', 'tampered'),
    ]) {
      test('a refresh that ends in $name after sign-out ends closed and fires nothing', () async {
        final net = FakeNetwork();
        final profile = profileOf();
        final dk2 = generateDataKey();
        final (:session, :hold, :started) = await heldRefresh(profile, net, () async {
          if (ends == 'device_removed') throw const KeysError('device_removed');
          if (ends == 'tampered') throw const KeysError('tampered');
          // a refresh that kept a newer version: it writes after the sign-out deleted the keys
          await storage.writeDataKey(profile.id, 2, dk2);
          await storage.setCurrent(profile.id, 2);
          return LocalKeys(
            keyring: Keyring(current: 2, byVersion: {2: await deriveRecordKeys(dk2)}),
          );
        });
        var removed = 0;
        var unverified = 0;
        var closed = 0;
        session
          ..onRemoved(() => removed += 1)
          ..onUnverified(() => unverified += 1)
          ..onClosed(() => closed += 1);
        net.records = [rotated];
        final syncing = session.sync();
        await started.future;
        await forgetVault(profile.id, storage, deleteStore: deleteStore);
        hold.complete();
        final result = await syncing;
        await wait(100);
        expect(result.error, SyncProblemCode.closed);
        expect(removed, 0);
        expect(unverified, 0);
        expect(closed, 0);
        expect(vaultExists(profile.id), isFalse);
        expect(await storedEntries(), isEmpty);
      });
    }

    for (final ends in ['ok', 'device_removed']) {
      test('the same account opened again before a stale refresh ($ends) returns keeps its vault '
          'and keys', () async {
        final net = FakeNetwork();
        final profile = profileOf();
        final stale = generateDataKey();
        final (:session, :hold, :started) = await heldRefresh(profile, net, () async {
          if (ends == 'device_removed') throw const KeysError('device_removed');
          await storage.writeDataKey(profile.id, 2, stale);
          await storage.setCurrent(profile.id, 2);
          return LocalKeys(
            keyring: Keyring(current: 2, byVersion: {2: await deriveRecordKeys(stale)}),
          );
        });
        var removed = 0;
        session.onRemoved(() => removed += 1);
        net.records = [rotated];
        final syncing = session.sync();
        await started.future;
        await forgetVault(profile.id, storage, deleteStore: deleteStore);

        // signed in and unlocked again: a new session of the same account
        net.records = [];
        final dk = generateDataKey();
        await storage.writeDataKey(profile.id, 1, dk);
        await storage.setCurrent(profile.id, 1);
        SqliteStore? store;
        final again = await open(
          profile,
          net: net,
          keys: LocalKeys(keyring: Keyring(current: 1, byVersion: {1: await deriveRecordKeys(dk)})),
          store: (userId) async => store = await openStore(userId),
        );
        await wait(100);
        final dio = appDio(again, net..mode = Mode.offline);
        final first = ((await send(dio, 'GET', '/v1/categories')).data! as List).first as Map;
        await send(dio, 'PATCH', '/v1/categories/${first['id']}', {'name': 'Unsynced'});

        hold.complete();
        expect((await syncing).error, SyncProblemCode.closed);
        await wait(100);
        expect(removed, 0);
        expect(store!.isClosed, isFalse);
        expect(vaultExists(profile.id), isTrue);
        expect(await again.pendingChanges(), 1);
        expect(await storage.current(profile.id), isNotNull);
        expect(await storage.readDataKey(profile.id, 1), isNotNull);
        await again.close();
      });
    }
  });

  group('this phone removed from the account', () {
    // No device wrap of this phone is left: `refreshKeys` (over `keys.dart`) says `device_removed`.
    const rotated = {
      'id': '01930000-0000-7000-8000-0000000000ff',
      'type': 'category',
      'version': 1,
      'deleted': false,
      'keyV': 2,
      'encV': 1,
      'body': 'AAAA',
    };

    test('stops the sync, deletes the vault and calls onRemoved', () async {
      final net = FakeNetwork();
      final profile = profileOf();
      SqliteStore? store;
      final session = await open(
        profile,
        net: net,
        keys: await keys(),
        store: (userId) async => store = await openStore(userId),
      );
      var removed = 0;
      var closed = 0;
      session.onRemoved(() => removed += 1);
      session.onClosed(() => closed += 1);
      await wait(100);
      net.records = [rotated];
      final dio = appDio(session, net);
      final first = ((await send(dio, 'GET', '/v1/categories')).data! as List).first as Map;
      await send(dio, 'PATCH', '/v1/categories/${first['id']}', {'name': 'Edited'});
      await until(() => removed == 1);
      expect(store!.isClosed, isTrue);
      expect(vaultExists(profile.id), isFalse);
      expect(closed, 0);
      // the session is gone: the next open makes a new one
      net.records = [];
      final again = await open(profile, net: net, keys: await keys());
      expect(identical(again, session), isFalse);
      await again.close();
    });

    test('fails the opening with device_removed and deletes the vault', () async {
      final net = FakeNetwork()..records = [rotated];
      final profile = profileOf();
      expect(
        await failure(open(profile, net: net, keys: await keys(), fresh: false)),
        isOpenError(SyncProblemCode.deviceRemoved),
      );
      expect(vaultExists(profile.id), isFalse);
    });
  });

  group('reloadKeys', () {
    test('gives the running sync the keyring storage now holds (a rotation), then syncs', () async {
      final net = FakeNetwork();
      final profile = profileOf();
      final dk1 = generateDataKey();
      final dk2 = generateDataKey();
      await storage.writeDataKey(profile.id, 1, dk1);
      await storage.setCurrent(profile.id, 1);
      final session = await open(
        profile,
        net: net,
        keys: LocalKeys(keyring: Keyring(current: 1, byVersion: {1: await deriveRecordKeys(dk1)})),
      );
      await wait(100);
      // a rotation committed on this phone: version 2's key is in storage, and current
      await storage.writeDataKey(profile.id, 2, dk2);
      await storage.setCurrent(profile.id, 2);
      final pushes = net.pushedKeyV.length;

      await session.reloadKeys();
      final dio = appDio(session, net);
      final first = ((await send(dio, 'GET', '/v1/categories')).data! as List).first as Map;
      await send(dio, 'PATCH', '/v1/categories/${first['id']}', {'name': 'Edited'});
      await until(() => net.pushedKeyV.skip(pushes).contains(2));
      final after = net.pushedKeyV.sublist(net.pushedKeyV.indexOf(2));
      expect(after.every((v) => v == 2), isTrue);
      await session.close();
    });
  });

  group('pendingChanges', () {
    test("counts the person's changes not pushed yet", () async {
      final net = FakeNetwork();
      final session = await open(profileOf(), net: net, keys: await keys());
      await wait(100);
      expect(await session.pendingChanges(), 0);
      net.mode = Mode.offline;
      final dio = appDio(session, net);
      final cats = (await send(dio, 'GET', '/v1/categories')).data! as List;
      for (final (i, c) in cats.take(2).indexed) {
        final r = await send(dio, 'PATCH', '/v1/categories/${(c as Map)['id']}', {
          'name': 'Edited $i',
        });
        expect(r.statusCode, 200);
      }
      expect(await session.pendingChanges(), 2);
      await session.close();
    });
  });

  group('a new key version this phone cannot verify', () {
    /// An account set up on this phone at v1, then rotated to v2 by another device: the recovery
    /// wrap and `link(2)` are real, but this phone's device wrap holds a forged v2 (another DK,
    /// sealed to its public key), whose link cannot lead back to the key it holds.
    Future<
      ({
        FakeAccount net,
        VaultProfile profile,
        VaultSession session,
        SqliteStore store,
        String recoveryKey,
        Future<String> Function() rotate,
      })
    >
    forgedRotation({bool noLink = false}) async {
      final net = FakeAccount();
      final profile = profileOf();
      final options = KeysOptions(userId: profile.id, dio: network(net), storage: storage);
      final prepared = await prepareAccount(options, guest: false);
      final local = await prepared.commit();
      final recoveryKey = prepared.recoveryKey!;
      SqliteStore? store;
      final session = await open(
        profile,
        net: net,
        keys: local,
        store: (userId) async => store = await openStore(userId),
      );
      await wait(100);
      Future<String> rotate() async {
        final secret = parseRecoveryKey(recoveryKey);
        final recovery = net.keys.wraps.firstWhere((w) => w.kind == 'recovery');
        final dk1 = await unwrapDataKey(
          secret,
          WrapContext(kind: WrapKind.recovery, userId: profile.id, keyV: 1),
          fromBase64Url(recovery.wrapped),
        );
        final dk2 = generateDataKey();
        if (!noLink) await addLink(net.keys, profile.id, dk2, dk1, 2);
        recovery
          ..keyV = 2
          ..wrapped = toBase64Url(
            await wrapDataKey(
              secret,
              WrapContext(kind: WrapKind.recovery, userId: profile.id, keyV: 2),
              dk2,
            ),
          );
        final device = net.keys.wraps.firstWhere((w) => w.kind == 'device');
        device
          ..keyV = 2
          ..wrapped = toBase64Url(
            await sealToDevice(
              fromBase64Url(device.publicKey!),
              WrapContext(kind: WrapKind.device, userId: profile.id, keyV: 2),
              // without a link (a rotation made before links) the real v2, else a forged one
              noLink ? dk2 : generateDataKey(),
            ),
          );
        net.current = 2;
        return device.id;
      }

      return (
        net: net,
        profile: profile,
        session: session,
        store: store!,
        recoveryKey: recoveryKey,
        rotate: rotate,
      );
    }

    Future<String> editFirst(VaultSession session, HttpClientAdapter net) async {
      final dio = appDio(session, net);
      final first = ((await send(dio, 'GET', '/v1/categories')).data! as List).first as Map;
      await send(dio, 'PATCH', '/v1/categories/${first['id']}', {'name': 'Edited'});
      return first['id']! as String;
    }

    test('the session calls onUnverified once and does not delete the vault', () async {
      final (:net, :profile, :session, :store, recoveryKey: _, :rotate) = await forgedRotation();
      var unverified = 0;
      var removed = 0;
      var closed = 0;
      session
        ..onUnverified(() => unverified += 1)
        ..onRemoved(() => removed += 1)
        ..onClosed(() => closed += 1);
      await rotate();
      final id = await editFirst(session, net);
      await until(() => unverified == 1);
      await wait(100);
      expect(unverified, 1);
      expect(removed, 0);
      expect(closed, 0);
      // the session is gone, the vault and its unsent edit are kept
      expect(store.isClosed, isTrue);
      expect(vaultExists(profile.id), isTrue);
      final kept = await openStore(profile.id);
      expect((await kept.readOutbox(10)).map((e) => e.id), contains(id));
      expect((await kept.get(RecordType.category, id))!.body['name'], 'Edited');
      await kept.close();
    });

    test('fails the opening with key_unverified and keeps the vault', () async {
      final (:net, :profile, :session, store: _, recoveryKey: _, :rotate) = await forgedRotation();
      await session.close();
      await rotate();
      final kept = await openStore(profile.id);
      final [first, ...] = await kept.list(RecordType.category);
      await kept.put(RecordType.category, first.id, {...first.body, 'name': 'Edited'});
      await kept.close();
      expect(
        await failure(
          open(profile, net: net, keys: (await loadLocalKeys(profile.id, storage))!, fresh: false),
        ),
        isOpenError(SyncProblemCode.keyUnverified),
      );
      expect(vaultExists(profile.id), isTrue);
    });

    test('unlocking with the recovery key from unverified keeps the outbox, deletes the old '
        'device wrap, and the next sync pushes the edit', () async {
      final (:net, :profile, :session, store: _, :recoveryKey, :rotate) = await forgedRotation();
      var unverified = 0;
      session.onUnverified(() => unverified += 1);
      final oldWrap = await rotate();
      final id = await editFirst(session, net);
      await until(() => unverified == 1);
      await wait(100);

      // Unlock's recovery key: the vault is kept, a new device wrap replaces the old one
      final local = await unlockWithRecovery(
        KeysOptions(userId: profile.id, dio: network(net), storage: storage),
        recoveryKey,
      );
      expect(local.keyring.current, 2);
      expect(local.keyring.byVersion.keys.toList()..sort(), [1, 2]);
      expect(net.keys.deletes, [oldWrap]);
      final devices = net.keys.wraps.where((w) => w.kind == 'device').toList();
      expect(devices, hasLength(1));
      expect(devices.single.id, isNot(oldWrap));
      expect(vaultExists(profile.id), isTrue);

      // the gate opens again: a new session, whose first sync pushes the kept edit under v2
      final again = await open(profile, net: net, keys: local);
      expect(identical(again, session), isFalse);
      expect(net.rows[id]!.keyV, 2);
      await again.close();
      final reopened = await openStore(profile.id);
      expect((await reopened.readOutbox(1 << 40)).where((e) => !e.reseal), isEmpty);
      await reopened.close();
    });

    test('a vault stuck in unverified because v+1 has no link unlocks with the recovery key at '
        'v+1, keeps v and v+1, and its outbox syncs', () async {
      final (:net, :profile, :session, store: _, :recoveryKey, :rotate) = await forgedRotation(
        noLink: true,
      );
      var unverified = 0;
      session.onUnverified(() => unverified += 1);
      await rotate();
      final id = await editFirst(session, net);
      await until(() => unverified == 1);
      await wait(100);

      final local = await unlockWithRecovery(
        KeysOptions(userId: profile.id, dio: network(net), storage: storage),
        recoveryKey,
      );
      expect(local.keyring.current, 2);
      expect(local.keyring.byVersion.keys.toList()..sort(), [1, 2]);
      final again = await open(profile, net: net, keys: local);
      expect(net.rows[id]!.keyV, 2);
      await again.close();
      final reopened = await openStore(profile.id);
      expect((await reopened.get(RecordType.category, id))!.body['name'], 'Edited');
      expect((await reopened.readOutbox(1 << 40)).where((e) => !e.reseal), isEmpty);
      await reopened.close();
    });
  });

  group('reinstall', () {
    test('reinstallClearsOldKeys: keys left by an earlier install go, the marker is set', () async {
      storage = memoryKeyStorage({
        'wambito.vault.user_a.dk.1': 'AAAA',
        'wambito.vault.user_a.current': '1',
        'wambito.vault.user_b.device': 'BBBB',
        'wambito.encryption.user_a': 'preview',
      });
      final marker = FileInstallMarker(p.join(_dir.path, 'install-${++_counter}'));
      expect(await marker.exists(), isFalse);
      await clearKeysAfterReinstall(storage, marker);
      expect(await storedEntries(), isEmpty);
      expect(await marker.exists(), isTrue);
    });

    test('keeps everything else, and does nothing once the marker is set', () async {
      storage = memoryKeyStorage({
        'wambito.vault.user_a.current': '1',
        'session.token': 't',
        'setting.server': 's',
      });
      final marker = FileInstallMarker(p.join(_dir.path, 'install-${++_counter}'));
      await clearKeysAfterReinstall(storage, marker);
      expect(await storedEntries(), {'session.token': 't', 'setting.server': 's'});
      await storage.setCurrent('user_a', 2);
      await clearKeysAfterReinstall(storage, marker);
      expect(await storage.current('user_a'), 2);
    });
  });
}
