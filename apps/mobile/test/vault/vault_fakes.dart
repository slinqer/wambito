import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/api/client.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/local/key_storage.dart';
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/stale_vaults.dart';
import 'package:wambito/local/vault_session.dart';
import 'package:wambito/vault/vault_providers.dart';

/// The signed-in session, set by the test: nothing is read from storage or asked of the server.
/// [signOut] only records whose session it ended.
class FixedSession extends SessionController {
  FixedSession(this._initial);

  final SessionState _initial;

  /// The token of each session [signOut] ended.
  final signOuts = <String?>[];

  /// The token of each session [sessionExpired] ended (the server said 401).
  final expiries = <String?>[];

  @override
  SessionState build() {
    ready = Future.value();
    refreshed = Future.value();
    return _initial;
  }

  /// Another session in place of this one, without a sign-out (a sign-in replacing a guest).
  void switchTo(SessionState next) => state = next;

  @override
  Future<void> signOut({bool discardGuest = false}) async {
    signOuts.add(state.stored?.token);
    state = SessionState.signedOut;
  }

  @override
  Future<void> sessionExpired({String? token}) async {
    expiries.add(state.stored?.token);
    state = SessionState.signedOut;
  }
}

SessionState signedIn(String token) =>
    SessionState.signedIn(StoredSession(token: token, guest: false));

ResponseBody json(Object? body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// One account of the [FakeServer].
typedef FakeAccount = ({String id, String mode});

/// The server, by bearer token: `GET /v1/me` of the token's account (401 for an unknown token),
/// `GET /v2/keys` with that account's [wraps], an empty `GET /v2/sync`; anything else answers `{}`.
class FakeServer implements HttpClientAdapter {
  FakeServer(this.accounts);

  final Map<String, FakeAccount> accounts;

  /// Tokens whose calls fail as without network.
  final offline = <String>{};

  /// Tokens the server no longer knows: every call answers 401.
  final expired = <String>{};

  /// The number of changes of each `POST /v2/sync`, with its token.
  final pushes = <(String?, int)>[];
  var _version = 0;

  /// `GET /v1/me` waits for this while set.
  Completer<void>? holdMe;

  /// `GET /v2/keys` waits for this while set, then answers [keysStatus] when set.
  Completer<void>? holdKeys;
  int? keysStatus;

  /// `GET /v1/me` answers this status (a problem) when set.
  int? meStatus;

  /// `GET /v2/sync` waits for this while set (the vault stays Opening).
  Completer<void>? holdSync;

  /// Every `PUT` waits for this while set (a setup stays Committing).
  Completer<void>? holdPut;

  /// The wraps by account id.
  final wraps = <String, List<Object?>>{};

  /// `<method> <path> <token>` of every call.
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final auth = options.headers['Authorization'] as String?;
    final token = auth?.replaceFirst('Bearer ', '');
    final call = '${options.method.toUpperCase()} ${options.uri.path}';
    calls.add('$call $token');
    if (offline.contains(token)) {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    if (expired.contains(token)) return json({'code': 'unauthenticated'}, 401);
    final account = accounts[token];
    switch (call) {
      case 'POST /api/v2/sync':
        final data = options.data;
        final changes = data is Map ? data['changes'] : null;
        final list = changes is List ? changes : const <Object?>[];
        pushes.add((token, list.length));
        // Every change is taken, at a new version.
        return json({
          'results': [
            for (final change in list)
              if (change is Map) {'id': change['id'], 'version': ++_version},
          ],
        });
      case 'GET /api/v1/me':
        await holdMe?.future;
        if (meStatus != null) return json({'code': 'bad'}, meStatus!);
        if (account == null) return json({'code': 'unauthenticated'}, 401);
        return json({
          'id': account.id,
          'email': 'ana@wambito.test',
          'timezone': 'America/Bogota',
          'locale': 'es',
          'onboardingCompletedAt': null,
          'currency': 'EUR',
          'isAnonymous': false,
          'encryption': account.mode,
        });
      case 'GET /api/v2/keys':
        await holdKeys?.future;
        if (keysStatus != null) return json({'code': 'nope'}, keysStatus!);
        return json({'wraps': wraps[account?.id] ?? <Object?>[], 'links': <Object?>[]});
      case 'GET /api/v2/sync':
        await holdSync?.future;
        return json({'records': <Object?>[], 'next': null, 'latest': 0});
      default:
        if (options.method.toUpperCase() == 'PUT') await holdPut?.future;
        return json(<String, Object?>{});
    }
  }

  @override
  void close({bool force = false}) {}
}

/// Records every request that reaches the network, answering `{}`.
class Recorder implements HttpClientAdapter {
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method.toUpperCase()} ${options.uri.path}');
    return json(<String, Object?>{});
  }

  @override
  void close({bool force = false}) {}
}

/// The vault files of the tests.
late Directory vaultDir;

void setUpVaultFiles() {
  sqfliteFfiInit();
  vaultDir = Directory.systemTemp.createTempSync('wambito-vault-providers');
}

Future<SqliteStore> openTestStore(String userId) =>
    SqliteStore.open(userId, directory: vaultDir.path, factory: databaseFactoryFfi);

Future<void> deleteTestStore(String userId) =>
    deleteVault(userId, directory: vaultDir.path, factory: databaseFactoryFfi);

/// The app's providers over [server], signed in as [session], with the vault in [vaultDir].
ProviderContainer appContainer(
  FakeServer server,
  SessionState session, {
  required KeyStorage storage,
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      ...overrides,
      sessionProvider.overrideWith(() => FixedSession(session)),
      keyStorageProvider.overrideWithValue(storage),
      staleVaultsProvider.overrideWithValue(
        (keep) => deleteStaleVaults(
          keep,
          forget: (id) => forgetVault(id, storage, deleteStore: deleteTestStore),
          directory: () async => vaultDir.path,
        ),
      ),
      networkClientProvider.overrideWith(
        (ref) => ApiClient.forServer(
          Uri.parse('http://x'),
          token: ref.watch(sessionProvider.select((s) => s.stored?.token)),
        )..dio.httpClientAdapter = server,
      ),
      openVaultSessionProvider.overrideWithValue(
        (o) => openVaultSession(
          OpenVaultOptions(
            profile: o.profile,
            keys: o.keys,
            fresh: o.fresh,
            network: o.network,
            storage: o.storage,
            onUnauthorized: o.onUnauthorized,
            onSessionChanged: o.onSessionChanged,
            openStore: openTestStore,
            deleteStore: deleteTestStore,
          ),
        ),
      ),
    ],
  );
  return container;
}

/// Waits (a bounded number of turns) until [condition] holds.
Future<void> until(bool Function() condition) async {
  final stop = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(stop)) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
