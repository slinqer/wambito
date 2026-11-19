import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart' show AuthFailure;
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_cache.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/api/server_url.dart';
import 'package:wambito/local/db.dart' show VaultHold, VaultHoldKind;
import 'package:wambito/local/install_marker.dart';
import 'package:wambito/local/key_storage.dart';
import 'package:wambito/local/sync.dart' show SyncResult;
import 'package:wambito/local/vault_session.dart';
import 'package:wambito/ui/press_button.dart';
import 'package:wambito/vault/encryption_mode.dart';
import 'package:wambito/vault/unsynced_sheet.dart';
import 'package:wambito/vault/vault_providers.dart';

import '../entry/fakes.dart';
import '../home/fakes.dart';
import '../support/ui_app.dart';

/// Signing out of a `preview` account takes the vault with it: its file, its keys and what the
/// phone kept of the account; and before it, a sheet when changes were not sent yet.
final _log = <String>[];

class _LoggedSessionStore extends SessionStore {
  @override
  Future<void> clear() async {
    _log.add('token gone');
    await super.clear();
  }
}

class _FakeSession extends Fake implements VaultSession {
  _FakeSession(this.pending);

  /// What `pendingChanges` answers, in turn; the last one again.
  final List<int> pending;
  var syncs = 0;
  var _asked = 0;

  @override
  Future<int> pendingChanges() async => pending[_asked < pending.length - 1 ? _asked++ : _asked];

  @override
  Future<SyncResult> sync() async {
    syncs += 1;
    return SyncResult();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('signing out of a preview account', () {
    late FakeAuthApi auth;
    final deleted = <String>[];

    ProviderContainer containerWith({Map<String, VaultHold> holds = const {}}) {
      final container = ProviderContainer(
        overrides: [
          vaultHoldReaderProvider.overrideWithValue((userId) async => holds[userId]),
          authApiProvider.overrideWithValue(auth),
          passkeysProvider.overrideWithValue(FakePasskeys()),
          widgetStoreProvider.overrideWithValue(FakeWidgetStore()),
          homeCacheStoreProvider.overrideWithValue(FakeCacheStore()),
          sessionStoreProvider.overrideWithValue(_LoggedSessionStore()),
          // The file of the vault is deleted under the test's own folder; the keys are the real
          // storage's, in the plugin's in-memory mock.
          forgetVaultProvider.overrideWithValue((userId, storage) {
            _log.add('vault wiped');
            return forgetVault(userId, storage, deleteStore: (id) async => deleted.add(id));
          }),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    setUp(() async {
      _log.clear();
      deleted.clear();
      auth = FakeAuthApi();
      FlutterSecureStorage.setMockInitialValues({
        SessionStore.tokenKey: 'tok',
        SessionStore.guestKey: 'false',
        SessionStore.onboardingKey: 'done',
        'wambito.vault.user_p.dk.1': 'AAAA',
        'wambito.vault.user_p.current': '1',
        'wambito.vault.user_p.device': 'BBBB',
        'wambito.vault.user_q.current': '1',
        'wambito.encryption.user_q': 'preview',
      });
      await const EncryptionStore().remember(
        'tok',
        VaultAccount(
          owner: sessionOwnerOf('tok'),
          profile: const VaultProfile(
            id: 'user_p',
            email: 'ana@wambito.test',
            isAnonymous: false,
            locale: 'es',
            timezone: 'America/Bogota',
          ),
          mode: EncryptionMode.preview,
        ),
      );
      _log.clear();
    });

    Future<Map<String, String>> kept() => const FlutterSecureStorage().readAll();

    test('signOut deletes the vault file and every key of the account, before the token', () async {
      final container = containerWith();
      final controller = container.read(sessionProvider.notifier);
      await controller.ready;
      await controller.signOut();

      expect(deleted, ['user_p']);
      final left = await kept();
      expect(left.keys.where((k) => k.startsWith('wambito.vault.user_p.')), isEmpty);
      expect(left.containsKey('wambito.encryption.user_p'), isFalse);
      expect(left.containsKey(EncryptionStore.accountKey), isFalse);
      // Another account's keys on this phone are not touched.
      expect(left['wambito.vault.user_q.current'], '1');
      expect(left['wambito.encryption.user_q'], 'preview');
      expect(_log.indexOf('vault wiped'), lessThan(_log.indexOf('token gone')));
      expect(_log, contains('token gone'));
      expect(container.read(sessionProvider).status, SessionStatus.signedOut);
    });

    // Final review finding 1: a held vault (an adoption waiting, a merge, a provisional vault) is
    // the only copy of its data; only its own flow forgets it, never a sign-out.
    for (final kind in VaultHoldKind.values) {
      test('signOut keeps a vault held ${kind.name}: its file, its keys and the kept account, for '
          'its own flow to resume', () async {
        final container = containerWith(
          holds: {'user_p': VaultHold(kind, since: '2026-11-18T00:00:00Z')},
        );
        final controller = container.read(sessionProvider.notifier);
        await controller.ready;
        await controller.signOut();

        expect(deleted, isEmpty);
        expect(_log, isNot(contains('vault wiped')));
        final left = await kept();
        expect(left['wambito.vault.user_p.dk.1'], 'AAAA');
        expect(left['wambito.vault.user_p.device'], 'BBBB');
        expect(container.read(sessionProvider).status, SessionStatus.signedOut);
        expect(left.containsKey(SessionStore.tokenKey), isFalse);
      });
    }

    test(
      'a hold that cannot be read keeps the vault too (nothing is deleted on a guess)',
      () async {
        final container = ProviderContainer(
          overrides: [
            authApiProvider.overrideWithValue(auth),
            passkeysProvider.overrideWithValue(FakePasskeys()),
            widgetStoreProvider.overrideWithValue(FakeWidgetStore()),
            homeCacheStoreProvider.overrideWithValue(FakeCacheStore()),
            vaultHoldReaderProvider.overrideWithValue(
              (userId) async => throw const FormatException('unreadable vault hold'),
            ),
            forgetVaultProvider.overrideWithValue((userId, storage) async => deleted.add(userId)),
          ],
        );
        addTearDown(container.dispose);
        final controller = container.read(sessionProvider.notifier);
        await controller.ready;
        await controller.signOut();
        expect(deleted, isEmpty);
        expect((await kept())['wambito.vault.user_p.dk.1'], 'AAAA');
        expect(container.read(sessionProvider).status, SessionStatus.signedOut);
      },
    );

    test('a server change while an adoption waits keeps the held vault and its keys', () async {
      final container = containerWith(
        holds: {'user_p': const VaultHold(VaultHoldKind.orphaned, since: '2026-11-18T00:00:00Z')},
      );
      await container.read(sessionProvider.notifier).ready;
      expect(
        await container.read(serverUrlProvider.notifier).change('https://my.server.org'),
        isTrue,
      );

      expect(deleted, isEmpty);
      final left = await kept();
      expect(left['wambito.vault.user_p.dk.1'], 'AAAA');
      expect(container.read(sessionProvider).status, SessionStatus.signedOut);
    });

    test('the adoption\'s "needs an encrypted server" goes with a sign-out and with another '
        'account', () async {
      final container = containerWith();
      final controller = container.read(sessionProvider.notifier);
      await controller.ready;
      final waiting = container.read(adoptionNeedsEncryptedServerProvider);
      waiting.value = true;
      await controller.signOut();
      expect(waiting.value, isFalse);

      waiting.value = true;
      await controller.verifyCode('otra@wambito.test', '123456');
      expect(container.read(sessionProvider).stored?.token, isNot('tok'));
      expect(waiting.value, isFalse);
    });

    test('accountDeleted does the same, before the token', () async {
      final container = containerWith();
      final controller = container.read(sessionProvider.notifier);
      await controller.ready;
      await controller.accountDeleted();

      expect(deleted, ['user_p']);
      final left = await kept();
      expect(left.keys.where((k) => k.startsWith('wambito.vault.user_p.')), isEmpty);
      expect(left.containsKey(EncryptionStore.accountKey), isFalse);
      expect(_log.indexOf('vault wiped'), lessThan(_log.indexOf('token gone')));
    });

    test('a wipe that fails does not keep the person signed in, and the keys still go', () async {
      final container = ProviderContainer(
        overrides: [
          authApiProvider.overrideWithValue(auth),
          passkeysProvider.overrideWithValue(FakePasskeys()),
          widgetStoreProvider.overrideWithValue(FakeWidgetStore()),
          homeCacheStoreProvider.overrideWithValue(FakeCacheStore()),
          vaultHoldReaderProvider.overrideWithValue((userId) async => null),
          forgetVaultProvider.overrideWithValue((userId, storage) async {
            throw StateError('the file is locked');
          }),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionProvider.notifier);
      await controller.ready;
      await controller.signOut();

      expect(container.read(sessionProvider).status, SessionStatus.signedOut);
      final left = await kept();
      expect(left.keys.where((k) => k.startsWith('wambito.vault.user_p.')), isEmpty);
    });

    test('a 401 at start ends the session but keeps the vault, its keys and the kept account, for '
        'the same account to find at its next sign-in', () async {
      auth.failures['isGuest'] = const AuthFailure(status: 401);
      final container = containerWith();
      final controller = container.read(sessionProvider.notifier);
      await controller.ready;
      await controller.refreshed;

      expect(container.read(sessionProvider).status, SessionStatus.signedOut);
      expect(deleted, isEmpty);
      expect(_log, isNot(contains('vault wiped')));
      expect(_log, contains('token gone'));
      final left = await kept();
      expect(left['wambito.vault.user_p.current'], '1');
      expect(left['wambito.vault.user_p.dk.1'], 'AAAA');
      expect(left.containsKey(EncryptionStore.accountKey), isTrue);
      expect(left['wambito.encryption.user_p'], 'preview');
      expect(left.containsKey(SessionStore.tokenKey), isFalse);
    });

    test('a signed-out start sweeps every vault but the one of the account kept last', () async {
      final swept = <String?>[];
      FlutterSecureStorage.setMockInitialValues({
        'wambito.vault.user_p.current': '1',
        'wambito.account': '{"owner":"x","id":"user_p"}',
      });
      final container = ProviderContainer(
        overrides: [
          authApiProvider.overrideWithValue(auth),
          passkeysProvider.overrideWithValue(FakePasskeys()),
          staleVaultsProvider.overrideWithValue((keep) async => swept.add(keep)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.notifier).ready;
      await pumpEventQueue();
      expect(swept, ['user_p']);
    });

    test('a signed-out start with nothing kept sweeps every vault', () async {
      final swept = <String?>[];
      FlutterSecureStorage.setMockInitialValues({'wambito.vault.user_z.current': '1'});
      final container = ProviderContainer(
        overrides: [
          authApiProvider.overrideWithValue(auth),
          passkeysProvider.overrideWithValue(FakePasskeys()),
          staleVaultsProvider.overrideWithValue((keep) async => swept.add(keep)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.notifier).ready;
      await pumpEventQueue();
      expect(swept, [null]);
    });

    test('a signed-in start sweeps nothing before the server says who it is', () async {
      final swept = <String?>[];
      final container = ProviderContainer(
        overrides: [
          authApiProvider.overrideWithValue(auth),
          passkeysProvider.overrideWithValue(FakePasskeys()),
          widgetStoreProvider.overrideWithValue(FakeWidgetStore()),
          staleVaultsProvider.overrideWithValue((keep) async => swept.add(keep)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.notifier).ready;
      await pumpEventQueue();
      expect(swept, isEmpty);
    });

    test('with wambito.account missing, the account the app knows is wiped', () async {
      FlutterSecureStorage.setMockInitialValues({
        SessionStore.tokenKey: 'tok',
        SessionStore.guestKey: 'false',
        'wambito.vault.user_p.current': '1',
        'wambito.encryption.user_p': 'preview',
      });
      final container = ProviderContainer(
        overrides: [
          authApiProvider.overrideWithValue(auth),
          passkeysProvider.overrideWithValue(FakePasskeys()),
          widgetStoreProvider.overrideWithValue(FakeWidgetStore()),
          homeCacheStoreProvider.overrideWithValue(FakeCacheStore()),
          knownAccountProvider.overrideWithValue(
            KnownAccount()
              ..owner = sessionOwnerOf('tok')
              ..id = 'user_p',
          ),
          vaultHoldReaderProvider.overrideWithValue((userId) async => null),
          forgetVaultProvider.overrideWithValue(
            (userId, storage) =>
                forgetVault(userId, storage, deleteStore: (id) async => deleted.add(id)),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionProvider.notifier);
      await controller.ready;
      await controller.signOut();
      expect(deleted, ['user_p']);
      final left = await kept();
      expect(left.keys.where((k) => k.startsWith('wambito.vault.user_p.')), isEmpty);
    });

    test(
      'a sign-out before the server said who a new session is still wipes the kept vault',
      () async {
        // The session expired (vault kept, wambito.account bound to the old token), the same person
        // signed in again and GET /v1/me failed: nothing names the account but what was kept last.
        await const FlutterSecureStorage().write(key: SessionStore.tokenKey, value: 'tok2');
        final container = containerWith();
        final controller = container.read(sessionProvider.notifier);
        await controller.ready;
        await controller.signOut();

        expect(deleted, ['user_p']);
        final left = await kept();
        expect(left.keys.where((k) => k.startsWith('wambito.vault.user_p.')), isEmpty);
        expect(left.containsKey(EncryptionStore.accountKey), isFalse);
        expect(left['wambito.vault.user_q.current'], '1');
      },
    );

    test('a plain account with nothing kept signs out as before', () async {
      FlutterSecureStorage.setMockInitialValues({
        SessionStore.tokenKey: 'tok',
        SessionStore.guestKey: 'false',
      });
      final container = containerWith();
      final controller = container.read(sessionProvider.notifier);
      await controller.ready;
      await controller.signOut();
      expect(deleted, isEmpty);
      expect(container.read(sessionProvider).status, SessionStatus.signedOut);
    });

    // Phone-first spec 10 changes nothing for a `plain` account: whatever the 401's code, today's
    // handling (the session ends, nothing wiped, nothing adopted, no new user).
    Future<void> rememberPlain() => const EncryptionStore().remember(
      'tok',
      VaultAccount(
        owner: sessionOwnerOf('tok'),
        profile: const VaultProfile(
          id: 'user_p',
          email: 'ana@wambito.test',
          isAnonymous: false,
          locale: 'es',
          timezone: 'America/Bogota',
        ),
        mode: EncryptionMode.plain,
      ),
    );

    test(
      "a plain account's 401 unauthenticated signs out as today, nothing wiped or adopted",
      () async {
        for (final code in ['unauthenticated', 'user_deleted', 'device_removed']) {
          FlutterSecureStorage.setMockInitialValues({
            SessionStore.tokenKey: 'tok',
            SessionStore.guestKey: 'false',
            SessionStore.onboardingKey: 'done',
            'wambito.vault.user_q.current': '1',
          });
          await rememberPlain();
          _log.clear();
          auth = FakeAuthApi()..failures['isGuest'] = AuthFailure(code: code, status: 401);
          final container = containerWith();
          final controller = container.read(sessionProvider.notifier);
          await controller.ready;
          await controller.refreshed;

          expect(container.read(sessionProvider).status, SessionStatus.signedOut, reason: code);
          expect(deleted, isEmpty, reason: code);
          expect(_log, isNot(contains('vault wiped')), reason: code);
          expect(auth.signInAsGuestCalls, 0, reason: code);
          final left = await kept();
          expect(left.containsKey(EncryptionStore.accountKey), isTrue, reason: code);
          expect(left['wambito.vault.user_q.current'], '1', reason: code);
          expect(left.containsKey(adoptTokenKey), isFalse, reason: code);
        }
      },
    );

    // Quick device removal: signing out leaves no row behind in Settings → Devices.
    group("this phone's device wrap", () {
      Future<void> keepWrapId() => const FlutterSecureStorage().write(
        key: 'wambito.vault.user_p.deviceWrapId',
        value: 'wrap_p',
      );

      test(
        "a preview account's sign-out deletes its own device wrap before ending the session",
        () async {
          await keepWrapId();
          final container = containerWith();
          final controller = container.read(sessionProvider.notifier);
          await controller.ready;
          await controller.signOut();

          expect(
            auth.calls,
            containsAllInOrder(['deleteDeviceWrap tok user_p wrap_p', 'signOut tok']),
          );
          expect(container.read(sessionProvider).status, SessionStatus.signedOut);
          expect((await kept()).keys.where((k) => k.startsWith('wambito.vault.user_p.')), isEmpty);
        },
      );

      test('no DELETE for a plain account', () async {
        await rememberPlain();
        await keepWrapId();
        final container = containerWith();
        final controller = container.read(sessionProvider.notifier);
        await controller.ready;
        await controller.signOut();

        expect(auth.calls.where((c) => c.startsWith('deleteDeviceWrap')), isEmpty);
        expect(auth.calls, contains('signOut tok'));
        expect(container.read(sessionProvider).status, SessionStatus.signedOut);
      });

      test('no DELETE without a wrap id', () async {
        final container = containerWith();
        final controller = container.read(sessionProvider.notifier);
        await controller.ready;
        await controller.signOut();

        expect(auth.calls.where((c) => c.startsWith('deleteDeviceWrap')), isEmpty);
        expect(auth.calls, contains('signOut tok'));
      });

      for (final kind in VaultHoldKind.values) {
        test('no DELETE while the vault is held ${kind.name}: it keeps its wrap', () async {
          await keepWrapId();
          final container = containerWith(
            holds: {'user_p': VaultHold(kind, since: '2026-11-18T00:00:00Z')},
          );
          final controller = container.read(sessionProvider.notifier);
          await controller.ready;
          await controller.signOut();

          expect(auth.calls.where((c) => c.startsWith('deleteDeviceWrap')), isEmpty);
          expect(auth.calls, contains('signOut tok'));
          expect((await kept())['wambito.vault.user_p.deviceWrapId'], 'wrap_p');
          expect(container.read(sessionProvider).status, SessionStatus.signedOut);
        });
      }

      test('a 401 at start keeps the wrap: no DELETE, its id stays', () async {
        await keepWrapId();
        auth.failures['isGuest'] = const AuthFailure(status: 401);
        final container = containerWith();
        final controller = container.read(sessionProvider.notifier);
        await controller.ready;
        await controller.refreshed;

        expect(container.read(sessionProvider).status, SessionStatus.signedOut);
        expect(auth.calls.where((c) => c.startsWith('deleteDeviceWrap')), isEmpty);
        expect((await kept())['wambito.vault.user_p.deviceWrapId'], 'wrap_p');
      });

      test('a DELETE that fails changes nothing else: the sign-out goes on', () async {
        for (final failure in <Object>[
          const AuthFailure(status: 0),
          const AuthFailure(status: 500),
          const SocketException('no route'),
          StateError('a bug in the call'),
        ]) {
          FlutterSecureStorage.setMockInitialValues({
            SessionStore.tokenKey: 'tok',
            SessionStore.guestKey: 'false',
            SessionStore.onboardingKey: 'done',
            'wambito.vault.user_p.deviceWrapId': 'wrap_p',
          });
          await const EncryptionStore().remember(
            'tok',
            VaultAccount(
              owner: sessionOwnerOf('tok'),
              profile: const VaultProfile(
                id: 'user_p',
                email: 'ana@wambito.test',
                isAnonymous: false,
                locale: 'es',
                timezone: 'America/Bogota',
              ),
              mode: EncryptionMode.preview,
            ),
          );
          auth = FakeAuthApi()..failures['deleteDeviceWrap'] = failure;
          final container = containerWith();
          final controller = container.read(sessionProvider.notifier);
          await controller.ready;
          await controller.signOut();

          expect(
            auth.calls,
            containsAllInOrder(['deleteDeviceWrap tok user_p wrap_p', 'signOut tok']),
          );
          expect(
            container.read(sessionProvider).status,
            SessionStatus.signedOut,
            reason: '$failure',
          );
        }
      });

      testWidgets('an offline DELETE does not delay the sign-out past signOutWait', (tester) async {
        await keepWrapId();
        auth.holdDeleteDeviceWrap = Completer<void>();
        auth.holdSignOut = Completer<void>();
        final container = containerWith();
        final controller = container.read(sessionProvider.notifier);
        await controller.ready;

        var done = false;
        unawaited(controller.signOut().then((_) => done = true));
        await tester.pump(const Duration(seconds: 9));
        expect(done, isFalse, reason: 'still waiting for the server');
        expect(container.read(sessionProvider).status, SessionStatus.signedIn);

        await tester.pump(const Duration(seconds: 2));
        expect(done, isTrue);
        expect(container.read(sessionProvider).status, SessionStatus.signedOut);
        // The server is still told the session ends, even after a DELETE that never answered.
        expect(
          auth.calls,
          containsAllInOrder(['deleteDeviceWrap tok user_p wrap_p', 'signOut tok']),
        );
      });
    });
  });

  group('reinstall', () {
    test('clearKeysAfterReinstall also deletes the kept account', () async {
      // Personal data (the email, the id) must not survive an iOS reinstall in the Keychain.
      final storage = KeyStorage(const FlutterSecureStorage());
      FlutterSecureStorage.setMockInitialValues({
        'wambito.account': '{"id":"user_p","email":"ana@wambito.test"}',
        'wambito.encryption.user_p': 'preview',
        'wambito.vault.user_p.current': '1',
        'session.token': 't',
      });
      final marker = FileInstallMarker(Directory.systemTemp.createTempSync('wambito-marker').path);
      await clearKeysAfterReinstall(
        storage,
        marker,
        markSession: const EncryptionStore().markReinstalled,
      );
      expect(await const FlutterSecureStorage().readAll(), {
        'session.token': 't',
        EncryptionStore.reinstalledKey: sessionOwnerOf('t'),
      });
    });

    test('the session that survived a reinstall is marked, and only on the first start', () async {
      final storage = KeyStorage(const FlutterSecureStorage());
      FlutterSecureStorage.setMockInitialValues({'session.token': 't'});
      final marker = FileInstallMarker(Directory.systemTemp.createTempSync('wambito-marker').path);
      await clearKeysAfterReinstall(
        storage,
        marker,
        markSession: const EncryptionStore().markReinstalled,
      );
      expect(await const EncryptionStore().reinstalledSession('t'), isTrue);
      expect(await const EncryptionStore().reinstalledSession('other'), isFalse);

      await const FlutterSecureStorage().delete(key: EncryptionStore.reinstalledKey);
      await clearKeysAfterReinstall(
        storage,
        marker,
        markSession: const EncryptionStore().markReinstalled,
      );
      expect(await const EncryptionStore().reinstalledSession('t'), isFalse);
    });

    test('with no session, a reinstall marks nothing', () async {
      final storage = KeyStorage(const FlutterSecureStorage());
      FlutterSecureStorage.setMockInitialValues({});
      final marker = FileInstallMarker(Directory.systemTemp.createTempSync('wambito-marker').path);
      await clearKeysAfterReinstall(
        storage,
        marker,
        markSession: const EncryptionStore().markReinstalled,
      );
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
    });
  });

  group('the sheet before signing out', () {
    Future<bool?> ask(WidgetTester tester, VaultSession? session) async {
      bool? answer;
      await tester.pumpWidget(
        uiApp(
          Builder(
            builder: (context) => PressButton.text(
              'go',
              key: const Key('go'),
              onPressed: () async => answer = await confirmUnsyncedSignOut(context, session),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('says "You have 2 changes not synced yet" and offers both ways', (tester) async {
      final session = _FakeSession([2]);
      await ask(tester, session);
      expect(find.text('Tienes 2 cambios sin sincronizar'), findsOneWidget);
      expect(find.byKey(const Key('vault.syncAndSignOut')), findsOneWidget);
      expect(find.byKey(const Key('vault.signOutAnyway')), findsOneWidget);
    });

    testWidgets('"Sync and sign out" syncs, then goes on', (tester) async {
      final session = _FakeSession([2, 0]);
      bool? answer;
      await tester.pumpWidget(
        uiApp(
          Builder(
            builder: (context) => PressButton.text(
              'go',
              key: const Key('go'),
              onPressed: () async => answer = await confirmUnsyncedSignOut(context, session),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vault.syncAndSignOut')));
      await tester.pumpAndSettle();
      expect(session.syncs, 1);
      expect(answer, isTrue);
    });

    testWidgets('a sync that left changes behind asks again, and signs out only when told', (
      tester,
    ) async {
      final session = _FakeSession([2, 2]);
      bool? answer;
      await tester.pumpWidget(
        uiApp(
          Builder(
            builder: (context) => PressButton.text(
              'go',
              key: const Key('go'),
              onPressed: () async => answer = await confirmUnsyncedSignOut(context, session),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vault.syncAndSignOut')));
      await tester.pumpAndSettle();
      expect(answer, isNull);
      expect(find.text('Tienes 2 cambios sin sincronizar'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vault.signOutAnyway')));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
      expect(session.syncs, 1);
    });

    testWidgets('"Sign out anyway" goes on without syncing', (tester) async {
      final session = _FakeSession([2]);
      bool? answer;
      await tester.pumpWidget(
        uiApp(
          Builder(
            builder: (context) => PressButton.text(
              'go',
              key: const Key('go'),
              onPressed: () async => answer = await confirmUnsyncedSignOut(context, session),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vault.signOutAnyway')));
      await tester.pumpAndSettle();
      expect(session.syncs, 0);
      expect(answer, isTrue);
    });

    testWidgets('Cancel backs out', (tester) async {
      final session = _FakeSession([2]);
      bool? answer;
      await tester.pumpWidget(
        uiApp(
          Builder(
            builder: (context) => PressButton.text(
              'go',
              key: const Key('go'),
              onPressed: () async => answer = await confirmUnsyncedSignOut(context, session),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();
      expect(answer, isFalse);
    });

    testWidgets('nothing to send, or no open vault: no sheet, straight on', (tester) async {
      expect(await ask(tester, _FakeSession([0])), isTrue);
      expect(find.byKey(const Key('vault.signOutAnyway')), findsNothing);
      expect(await ask(tester, null), isTrue);
    });
  });
}
