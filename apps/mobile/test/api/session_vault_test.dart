import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart' show AuthFailure;
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_cache.dart';
import 'package:wambito/home/widget_snapshot.dart';
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

    ProviderContainer containerWith() {
      final container = ProviderContainer(
        overrides: [
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

    test('a 401 at start wipes the vault and the kept account too', () async {
      auth.failures['isGuest'] = const AuthFailure(status: 401);
      final container = containerWith();
      final controller = container.read(sessionProvider.notifier);
      await controller.ready;
      await controller.refreshed;

      expect(container.read(sessionProvider).status, SessionStatus.signedOut);
      expect(deleted, ['user_p']);
      final left = await kept();
      expect(left.keys.where((k) => k.startsWith('wambito.vault.user_p.')), isEmpty);
      expect(left.containsKey(EncryptionStore.accountKey), isFalse);
      expect(left.containsKey('wambito.encryption.user_p'), isFalse);
      expect(_log.indexOf('vault wiped'), lessThan(_log.indexOf('token gone')));
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
      await clearKeysAfterReinstall(storage, marker);
      expect(await const FlutterSecureStorage().readAll(), {'session.token': 't'});
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
