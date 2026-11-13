// No finance call of an account not known to be plain reaches the network before its vault opens.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/key_storage.dart';
import 'package:wambito/local/vault_session.dart';
import 'package:wambito/vault/encryption_mode.dart';
import 'package:wambito/vault/vault_providers.dart';

import 'vault_fakes.dart';

const FakeAccount _preview = (id: 'user_p', mode: 'preview');
const FakeAccount _plain = (id: 'user_q', mode: 'plain');

/// The API's FINANCE_PATHS (apps/api/src/http/preview.ts), one request each.
const _finance = [
  ('GET', '/v1/transactions'),
  ('POST', '/v1/transactions'),
  ('PATCH', '/v1/transactions/t1'),
  ('GET', '/v1/categories'),
  ('DELETE', '/v1/categories/c1'),
  ('GET', '/v1/recurrences'),
  ('GET', '/v1/summary'),
  ('GET', '/v1/reports/trend'),
  ('POST', '/v1/captures'),
  ('POST', '/v1/imports'),
  ('GET', '/v1/me/export'),
];

/// Not finance: they go on.
const _other = [
  ('GET', '/v1/me'),
  ('GET', '/v2/keys'),
  ('GET', '/auth/passkey/list-user-passkeys'),
];

/// [method] [path] through the screens' client, its network recorded in [net]: the status, and the
/// problem's code when refused.
Future<(int?, String?)> send(ProviderContainer c, Recorder net, String method, String path) async {
  final client = c.read(apiClientProvider)..dio.httpClientAdapter = net;
  try {
    final r = await client.dio.request<Object?>(path, options: Options(method: method));
    return (r.statusCode, null);
  } on DioException catch (e) {
    final data = e.response?.data;
    return (e.response?.statusCode, data is Map ? data['code'] as String? : null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setUpVaultFiles);
  tearDownAll(() => vaultDir.deleteSync(recursive: true));

  late KeyStorage storage;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    storage = KeyStorage(const FlutterSecureStorage());
  });
  tearDown(() => forgetVault('user_p', storage, deleteStore: deleteTestStore));

  ProviderContainer containerFor(FakeServer server, [SessionState? session]) {
    final container = appContainer(server, session ?? signedIn('tok'), storage: storage);
    addTearDown(container.dispose);
    container.listen(apiClientProvider, (_, _) {});
    return container;
  }

  Future<void> expectHeld(ProviderContainer c) async {
    final net = Recorder();
    for (final (method, path) in _finance) {
      expect(await send(c, net, method, path), (423, 'vault_locked'), reason: '$method $path');
    }
    expect(net.calls, isEmpty);
    for (final (method, path) in _other) {
      await send(c, net, method, path);
    }
    expect(net.calls, [for (final (m, path) in _other) '$m /api$path']);
  }

  test(
    'while the mode loads, a finance call waits and nothing is sent; preview refuses it',
    () async {
      final server = FakeServer({'tok': _preview})..holdMe = Completer();
      final c = containerFor(server);
      final net = Recorder();
      var done = false;
      final call = send(c, net, 'GET', '/v1/transactions').whenComplete(() => done = true);
      await pumpEventQueue();
      expect(done, isFalse);
      expect(net.calls, isEmpty);
      server.holdMe!.complete();
      expect(await call, (423, 'vault_locked'));
      expect(net.calls, isEmpty);
    },
  );

  test(
    'while the mode loads, a plain account’s finance call goes once the mode is known',
    () async {
      final server = FakeServer({'tok': _plain})..holdMe = Completer();
      final c = containerFor(server);
      final net = Recorder();
      final call = send(c, net, 'GET', '/v1/transactions');
      await pumpEventQueue();
      expect(net.calls, isEmpty);
      server.holdMe!.complete();
      expect(await call, (200, null));
      expect(net.calls, ['GET /api/v1/transactions']);
    },
  );

  test('when the mode failed (and nothing was kept), finance calls are refused', () async {
    final server = FakeServer({'tok': _preview})..meStatus = 500;
    final c = containerFor(server);
    await until(() => c.read(vaultAccountProvider).hasError);
    await expectHeld(c);
  });

  test('a preview account on Unlock: finance calls are refused, the rest goes on', () async {
    final server = FakeServer({'tok': _preview})
      ..wraps['user_p'] = [
        {'id': 'w1', 'kind': 'recovery', 'keyV': 1, 'wrapped': 'AAAA'},
      ];
    final c = containerFor(server);
    await until(() => c.read(vaultGateStateProvider)?.status == 'unlock');
    await expectHeld(c);
  });

  test('a preview account on Setup: finance calls are refused', () async {
    final c = containerFor(FakeServer({'tok': _preview}));
    await until(() => c.read(vaultGateStateProvider)?.status == 'setup');
    await expectHeld(c);
  });

  test('a preview account on Locked: finance calls are refused', () async {
    final c = containerFor(FakeServer({'tok': _preview})..keysStatus = 500);
    await until(() => c.read(vaultGateStateProvider)?.status == 'locked');
    await expectHeld(c);
  });

  test('a preview account on Checking: finance calls are refused', () async {
    final server = FakeServer({'tok': _preview})..holdKeys = Completer();
    final c = containerFor(server);
    await until(() => server.calls.any((call) => call.startsWith('GET /api/v2/keys')));
    expect(c.read(vaultGateStateProvider)?.status, 'checking');
    final net = Recorder();
    for (final (method, path) in _finance) {
      expect(await send(c, net, method, path), (423, 'vault_locked'));
    }
    expect(net.calls, isEmpty);
    server.holdKeys!.complete();
  });

  test('ready: the vault answers on the phone, and nothing goes to the network', () async {
    await storage.writeDataKey('user_p', 1, generateDataKey());
    await storage.setCurrent('user_p', 1);
    final c = containerFor(FakeServer({'tok': _preview}));
    await until(() => c.read(vaultSessionProvider) != null);
    final net = Recorder();
    expect((await send(c, net, 'GET', '/v1/categories')).$1, 200);
    expect((await send(c, net, 'GET', '/v1/me/export')).$1, 403);
    expect(net.calls, isEmpty);
  });

  test('a plain account passes through untouched', () async {
    final c = containerFor(FakeServer({'tok': _plain}));
    await until(() => c.read(knownPlainProvider));
    final net = Recorder();
    for (final (method, path) in [..._finance, ..._other]) {
      expect((await send(c, net, method, path)).$1, 200);
    }
    expect(net.calls, [
      for (final (m, path) in [..._finance, ..._other]) '$m /api$path',
    ]);
    expect(
      c.read(apiClientProvider).dio.interceptors.whereType<Interceptor>(),
      hasLength(c.read(networkClientProvider).dio.interceptors.length),
    );
  });

  test('signed out: no guard', () async {
    final c = containerFor(FakeServer({}), SessionState.signedOut);
    final net = Recorder();
    expect((await send(c, net, 'GET', '/v1/transactions')).$1, 200);
    expect(net.calls, ['GET /api/v1/transactions']);
  });
}
