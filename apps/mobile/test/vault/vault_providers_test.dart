// The vault gate's wiring (no TS twin: VaultGate.tsx's deps as Riverpod providers).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/api/client.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/keys.dart';
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/vault_session.dart';
import 'package:wambito/vault/encryption_mode.dart';
import 'package:wambito/vault/vault_gate.dart';
import 'package:wambito/vault/vault_providers.dart';

/// The signed-in session, fixed: nothing is read from storage or asked of the server.
class _Session extends SessionController {
  _Session(this._state);

  final SessionState _state;

  @override
  SessionState build() {
    ready = Future.value();
    refreshed = Future.value();
    return _state;
  }
}

ResponseBody _json(Object? body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// The server: `GET /v1/me` of one account in [mode]; `GET /v2/keys` lists [wraps].
class FakeServer implements HttpClientAdapter {
  FakeServer({this.mode = 'preview'});

  String mode;
  bool offline = false;

  /// `GET /v1/me` answers this status (a problem) when set.
  int? status;
  List<Object?> wraps = [];
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final call = '${options.method.toUpperCase()} ${options.uri.path}';
    calls.add(call);
    if (offline) throw DioException.connectionError(requestOptions: options, reason: 'offline');
    if (status != null && call == 'GET /api/v1/me') return _json({'code': 'nope'}, status!);
    return switch (call) {
      'GET /api/v1/me' => _json({
        'id': 'vault_user',
        'email': 'ana@wambito.test',
        'timezone': 'America/Bogota',
        'locale': 'es',
        'onboardingCompletedAt': null,
        'currency': 'EUR',
        'isAnonymous': false,
        'encryption': mode,
      }),
      'GET /api/v2/keys' => _json({'wraps': wraps, 'links': <Object?>[]}),
      _ => _json({'code': 'not_found'}, 404),
    };
  }

  @override
  void close({bool force = false}) {}
}

const _signedIn = SessionState.signedIn(StoredSession(token: 'tok', guest: false));

ProviderContainer containerWith(FakeServer server, {SessionState session = _signedIn}) {
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(() => _Session(session)),
      networkClientProvider.overrideWith(
        (ref) =>
            ApiClient.forServer(Uri.parse('http://x'), token: 'tok')
              ..dio.httpClientAdapter = server,
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('encryptionModeProvider', () {
    test('is null when signed out, and asks nothing', () async {
      final server = FakeServer();
      final container = containerWith(server, session: SessionState.signedOut);
      expect(await container.read(encryptionModeProvider.future), isNull);
      expect(server.calls, isEmpty);
    });

    test("reads the account's mode from GET /v1/me and keeps it under "
        'wambito.encryption.<userId>', () async {
      final container = containerWith(FakeServer());
      expect(await container.read(encryptionModeProvider.future), EncryptionMode.preview);
      final stored = await const FlutterSecureStorage().readAll();
      expect(stored['wambito.encryption.vault_user'], 'preview');
    });

    test('an offline start of the same session knows the mode and the profile', () async {
      await containerWith(FakeServer(mode: 'plain')).read(encryptionModeProvider.future);
      final offline = containerWith(FakeServer()..offline = true);
      expect(await offline.read(encryptionModeProvider.future), EncryptionMode.plain);
      expect((await offline.read(vaultAccountProvider.future))?.profile.email, 'ana@wambito.test');
    });

    test('another session never reads what this one kept; offline it does not know', () async {
      await containerWith(FakeServer()).read(encryptionModeProvider.future);
      final other = containerWith(
        FakeServer()..offline = true,
        session: const SessionState.signedIn(StoredSession(token: 'other', guest: false)),
      );
      await expectLater(other.read(encryptionModeProvider.future), throwsA(isA<DioException>()));
    });
  });

  test('a 401 or another 4xx is the answer: nothing kept stands in for it', () async {
    await containerWith(FakeServer()).read(encryptionModeProvider.future);
    final server = FakeServer()..status = 401;
    final refused = containerWith(server);
    await expectLater(refused.read(encryptionModeProvider.future), throwsA(isA<DioException>()));
    final bad = containerWith(FakeServer()..status = 400);
    await expectLater(bad.read(encryptionModeProvider.future), throwsA(isA<DioException>()));
    final down = containerWith(FakeServer()..status = 503);
    expect(await down.read(encryptionModeProvider.future), EncryptionMode.preview);
  });

  group('vaultGateProvider', () {
    test('is null for a plain account, and the API client has no vault interceptor', () async {
      final container = containerWith(FakeServer(mode: 'plain'));
      await container.read(vaultAccountProvider.future);
      expect(container.read(vaultGateProvider), isNull);
      expect(container.read(vaultSessionProvider), isNull);
      final client = container.read(apiClientProvider);
      expect(
        client.dio.interceptors.whereType<Interceptor>().map((i) => i.runtimeType),
        isNot(contains(predicate((Type t) => t.toString() == 'LocalBackendInterceptor'))),
      );
    });

    test('a preview account with keys elsewhere gets a started gate that asks to unlock', () async {
      final server = FakeServer()
        ..wraps = [
          {'id': 'w1', 'kind': 'recovery', 'keyV': 1, 'wrapped': 'AAAA'},
        ];
      final container = containerWith(server);
      final seen = <String?>[];
      container.listen(
        vaultGateStateProvider,
        (_, next) => seen.add(next?.status),
        fireImmediately: true,
      );
      await container.read(vaultAccountProvider.future);
      final gate = container.read(vaultGateProvider);
      expect(gate, isNotNull);
      await pumpEventQueue();
      expect(gate!.state, const Unlock());
      expect(container.read(vaultGateStateProvider), const Unlock());
      expect(container.read(vaultSessionProvider), isNull);
      expect(seen.last, 'unlock');
      // The keys asked the network directly, naming the account.
      expect(server.calls, contains('GET /api/v2/keys'));
    });
  });

  group('apiClientProvider', () {
    late Directory dir;
    setUpAll(() {
      sqfliteFfiInit();
      dir = Directory.systemTemp.createTempSync('wambito-vault-providers');
    });
    tearDownAll(() => dir.deleteSync(recursive: true));

    test("puts the open vault's interceptor in front; the network client never gets it", () async {
      final server = FakeServer();
      final storage = KeyStorage(const FlutterSecureStorage());
      final dk = generateDataKey();
      final session = await openVaultSession(
        OpenVaultOptions(
          profile: const VaultProfile(
            id: 'vault_user',
            email: 'ana@wambito.test',
            isAnonymous: false,
            locale: 'es',
            timezone: 'America/Bogota',
          ),
          keys: LocalKeys(keyring: Keyring(current: 1, byVersion: {1: await deriveRecordKeys(dk)})),
          fresh: false,
          network: Dio(BaseOptions(baseUrl: 'http://x/api'))..httpClientAdapter = server,
          storage: storage,
          openStore: (id) => SqliteStore.open(id, directory: dir.path, factory: databaseFactoryFfi),
          deleteStore: (id) => deleteVault(id, directory: dir.path, factory: databaseFactoryFfi),
        ),
      );
      addTearDown(
        () => forgetVault(
          'vault_user',
          storage,
          deleteStore: (id) => deleteVault(id, directory: dir.path, factory: databaseFactoryFfi),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(() => _Session(_signedIn)),
          vaultSessionProvider.overrideWithValue(session),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(apiClientProvider).dio.interceptors, contains(session.interceptor));
      expect(
        container.read(networkClientProvider).dio.interceptors,
        isNot(contains(session.interceptor)),
      );
      expect(
        identical(container.read(apiClientProvider).dio, container.read(networkClientProvider).dio),
        isFalse,
      );
    });
  });
}
