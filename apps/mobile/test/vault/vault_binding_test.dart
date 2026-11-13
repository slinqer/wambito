// The vault is the signed-in session's: a token switched straight from one account to another
// (a sign-in replacing a guest) drops the old gate, its session and its interceptor.
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wambito/api/session.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/key_storage.dart';
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/vault_session.dart';
import 'package:wambito/vault/encryption_mode.dart';
import 'package:wambito/vault/vault_providers.dart';

import 'vault_fakes.dart';

const FakeAccount _a = (id: 'user_a', mode: 'preview');
const FakeAccount _b = (id: 'user_b', mode: 'plain');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setUpVaultFiles);
  tearDownAll(() => vaultDir.deleteSync(recursive: true));

  late KeyStorage storage;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    storage = KeyStorage(const FlutterSecureStorage());
  });
  tearDown(() => forgetVault('user_a', storage, deleteStore: deleteTestStore));

  ProviderContainer containerFor(FakeServer server) {
    final container = appContainer(server, signedIn('tokA'), storage: storage);
    addTearDown(container.dispose);
    container.listen(apiClientProvider, (_, _) {});
    return container;
  }

  FixedSession sessionOf(ProviderContainer c) => c.read(sessionProvider.notifier) as FixedSession;

  /// Account A (preview) with its keys on this phone, its vault open.
  Future<ProviderContainer> readyA(FakeServer server) async {
    await storage.writeDataKey('user_a', 1, generateDataKey());
    await storage.setCurrent('user_a', 1);
    final container = containerFor(server);
    await until(() => container.read(vaultSessionProvider) != null);
    return container;
  }

  Future<int?> financeStatus(ProviderContainer c) async {
    final net = Recorder();
    final client = c.read(apiClientProvider)..dio.httpClientAdapter = net;
    try {
      return (await client.dio.get<Object?>('/v1/transactions')).statusCode;
    } on DioException catch (e) {
      expect(net.calls, isEmpty);
      return e.response?.statusCode;
    }
  }

  for (final online in [true, false]) {
    test('preview A ready, then the token switched to B (${online ? 'online' : 'offline'}): '
        "A's gate, session and interceptor go; A's vault stays", () async {
      final server = FakeServer({'tokA': _a, 'tokB': _b});
      final c = await readyA(server);
      final vaultA = c.read(vaultSessionProvider)!;
      final gateA = c.read(vaultGateProvider)!;
      expect(c.read(apiClientProvider).dio.interceptors, contains(vaultA.interceptor));

      if (!online) server.offline.add('tokB');
      sessionOf(c).switchTo(signedIn('tokB'));

      // At once, before B's account is known.
      expect(c.read(apiClientProvider).dio.interceptors, isNot(contains(vaultA.interceptor)));
      expect(c.read(vaultSessionProvider), isNull);
      expect(c.read(vaultGateProvider), isNull);
      expect(gateA.disposed, isTrue);
      // A finance call waits for B's mode, never for A's vault: plain B goes, an unknown mode
      // fails as offline (no response).
      expect(await financeStatus(c), online ? 200 : null);

      if (online) {
        await until(() => c.read(knownPlainProvider));
        expect(await financeStatus(c), 200);
      } else {
        await until(() => c.read(vaultAccountProvider).hasError);
        expect(await financeStatus(c), isNull);
      }
      expect(c.read(vaultGateProvider), isNull);
      expect(c.read(apiClientProvider).dio.interceptors, isNot(contains(vaultA.interceptor)));
      // closed, not wiped
      expect(await storage.current('user_a'), 1);
      expect(File(p.join(vaultDir.path, vaultFileName('user_a'))).existsSync(), isTrue);
    });
  }

  group("a late 401 of A's keys call", () {
    FakeServer heldKeys() => FakeServer({'tokA': _a, 'tokB': _b})
      ..holdKeys = Completer()
      ..keysStatus = 401;

    test('signs A out while A is still signed in', () async {
      final server = heldKeys();
      final c = containerFor(server);
      await until(() => server.calls.any((call) => call.startsWith('GET /api/v2/keys')));
      server.holdKeys!.complete();
      await until(() => sessionOf(c).signOuts.isNotEmpty);
      expect(sessionOf(c).signOuts, ['tokA']);
    });

    test('never signs B out once the token switched to B', () async {
      final server = heldKeys();
      final c = containerFor(server);
      await until(() => server.calls.any((call) => call.startsWith('GET /api/v2/keys')));
      final gateA = c.read(vaultGateProvider)!;
      sessionOf(c).switchTo(signedIn('tokB'));
      await until(() => c.read(knownPlainProvider));
      server.holdKeys!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sessionOf(c).signOuts, isEmpty);
      expect(c.read(sessionProvider).stored?.token, 'tokB');
      expect(gateA.disposed, isTrue);
      expect(await storage.current('user_a'), isNull);
    });
  });
}
