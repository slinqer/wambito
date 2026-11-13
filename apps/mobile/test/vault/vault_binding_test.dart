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
      if (online) {
        // Another account signed in: A's vault is swept (the web's deleteStaleVaults).
        await until(() => !File(p.join(vaultDir.path, vaultFileName('user_a'))).existsSync());
        expect(await storage.current('user_a'), isNull);
      } else {
        // closed, not wiped: nobody has said who B is yet
        expect(await storage.current('user_a'), 1);
        expect(File(p.join(vaultDir.path, vaultFileName('user_a'))).existsSync(), isTrue);
      }
    });
  }

  group('a 401 (the session expired, or was signed out everywhere)', () {
    const FakeAccount aAgain = (id: 'user_a', mode: 'preview');

    /// A ready, with one change of the person in its outbox that the server refused with a 401.
    Future<(ProviderContainer, FakeServer)> expiredWithAChange() async {
      final server = FakeServer({'tokA': _a, 'tokA2': aAgain, 'tokB': _b});
      final c = await readyA(server);
      final vault = c.read(vaultSessionProvider)!;
      // The first records (settings, categories) are sent first.
      await until(() => server.pushes.isNotEmpty);
      await vault.sync();
      expect(await vault.pendingChanges(), 0);
      server.expired.add('tokA');
      await c
          .read(apiClientProvider)
          .dio
          .post<Object?>(
            '/v1/categories',
            data: {'name': 'Pets', 'kind': 'expense', 'icon': 'paw', 'color': '#f0f'},
          );
      await until(() => sessionOf(c).expiries.isNotEmpty);
      return (c, server);
    }

    test('ends the session, never signs out: the vault, its keys and its outbox stay', () async {
      final (c, _) = await expiredWithAChange();
      expect(sessionOf(c).expiries, ['tokA']);
      expect(sessionOf(c).signOuts, isEmpty);
      expect(c.read(sessionProvider).status, SessionStatus.signedOut);
      await pumpEventQueue();
      expect(await storage.current('user_a'), 1);
      expect(File(p.join(vaultDir.path, vaultFileName('user_a'))).existsSync(), isTrue);
      final store = await openTestStore('user_a');
      try {
        final pending = (await store.readOutbox(1000)).where((e) => !e.reseal && !e.abandoned);
        expect(pending, hasLength(1));
      } finally {
        await store.close();
      }
    });

    test('the same account signing in again finds them and sends the change', () async {
      final (c, server) = await expiredWithAChange();
      sessionOf(c).switchTo(signedIn('tokA2'));
      await until(() => c.read(vaultSessionProvider) != null);
      await until(() => server.pushes.any((push) => push.$1 == 'tokA2' && push.$2 == 1));
      expect(await storage.current('user_a'), 1);
    });

    test('another account signing in sweeps them', () async {
      final (c, _) = await expiredWithAChange();
      sessionOf(c).switchTo(signedIn('tokB'));
      await until(() => c.read(knownPlainProvider));
      await until(() => !File(p.join(vaultDir.path, vaultFileName('user_a'))).existsSync());
      final left = await const FlutterSecureStorage().readAll();
      expect(left.keys.where((k) => k.contains('user_a')), isEmpty);
    });
  });

  group("a late 401 of A's keys call", () {
    FakeServer heldKeys() => FakeServer({'tokA': _a, 'tokB': _b})
      ..holdKeys = Completer()
      ..keysStatus = 401;

    test("ends A's session while A is still signed in (never a sign-out)", () async {
      final server = heldKeys();
      final c = containerFor(server);
      await until(() => server.calls.any((call) => call.startsWith('GET /api/v2/keys')));
      server.holdKeys!.complete();
      await until(() => sessionOf(c).expiries.isNotEmpty);
      expect(sessionOf(c).expiries, ['tokA']);
      expect(sessionOf(c).signOuts, isEmpty);
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
      expect(sessionOf(c).expiries, isEmpty);
      expect(c.read(sessionProvider).stored?.token, 'tokB');
      expect(gateA.disposed, isTrue);
      expect(await storage.current('user_a'), isNull);
    });
  });
}
