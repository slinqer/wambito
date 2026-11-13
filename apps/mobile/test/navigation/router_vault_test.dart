import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/client.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/local/key_storage.dart';
import 'package:wambito/router.dart';
import 'package:wambito/vault/vault_providers.dart';

import '../entry/fakes.dart';
import '../vault/vault_fakes.dart' show FakeServer, setUpVaultFiles, openTestStore, deleteTestStore;

import 'package:wambito/local/vault_session.dart';

const _in = SessionState.signedIn(StoredSession(token: 'tok', guest: false));

String? go(String path, {VaultRoute vault = VaultRoute.open, SessionState session = _in}) =>
    sessionRedirect(session, Uri.parse(path), vault: vault);

void main() {
  group('sessionRedirect and the vault', () {
    test('a preview account whose vault is not open goes to /unlock from every screen', () {
      for (final path in ['/', '/settings', '/review/abc', '/welcome', '/progress', '/loading']) {
        expect(go(path, vault: VaultRoute.locked), '/unlock', reason: path);
      }
      expect(go('/unlock', vault: VaultRoute.locked), isNull);
    });

    test('the magic link, the entry screens and the debug screens are never moved', () {
      for (final path in ['/auth/verify', '/entry', '/entry/email', '/entry/passkey-offer']) {
        expect(go(path, vault: VaultRoute.locked), isNot('/unlock'), reason: path);
      }
      expect(go('/auth/verify', vault: VaultRoute.locked), isNull);
      expect(go('/debug/prf', vault: VaultRoute.locked), isNull);
    });

    test('once the vault is open, /unlock leaves for home', () {
      expect(go('/unlock'), '/');
      expect(go('/'), isNull);
    });

    test('while the mode is being learned, a signed-in account waits on the loading route', () {
      expect(go('/', vault: VaultRoute.loading), '/loading');
      expect(go('/settings', vault: VaultRoute.loading), '/loading');
      expect(go('/loading', vault: VaultRoute.loading), isNull);
      expect(go('/unlock', vault: VaultRoute.loading), '/loading');
    });

    test('signed out, the entry screens only, whatever the vault says', () {
      expect(go('/', session: SessionState.signedOut, vault: VaultRoute.locked), '/entry');
      expect(go('/unlock', session: SessionState.signedOut), '/entry');
    });
  });

  group('the router with the vault gate', () {
    late FakeServer server;

    setUp(() {
      mockStorage(token: 'tok');
      setUpVaultFiles();
      server = FakeServer({'tok': (id: 'user_p', mode: 'preview')});
    });

    Future<ProviderContainer> pump(WidgetTester tester) => pumpApp(
      tester,
      auth: FakeAuthApi(),
      // The account's mode is the fake server's to say here.
      plain: false,
      overrides: [
        networkClientProvider.overrideWith(
          (ref) => ApiClient.forServer(
            Uri.parse('http://x'),
            token: ref.watch(sessionProvider.select((s) => s.stored?.token)),
          )..dio.httpClientAdapter = server,
        ),
        keyStorageProvider.overrideWithValue(KeyStorage()),
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

    String where(ProviderContainer c) =>
        c.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

    testWidgets('a new preview account is sent to /unlock and shows the recovery key', (
      tester,
    ) async {
      final c = await pump(tester);
      expect(where(c), '/unlock');
      expect(find.text('Guarda tu clave de recuperación'), findsOneWidget);
    });

    testWidgets('an account with keys elsewhere shows Unlock', (tester) async {
      server.wraps['user_p'] = [
        {'id': 'w1', 'kind': 'recovery', 'keyV': 1, 'wrapped': 'AAAA'},
      ];
      final c = await pump(tester);
      expect(where(c), '/unlock');
      expect(find.text('Abre tus datos aquí'), findsOneWidget);
    });

    testWidgets('the gate still opening keeps the person on /unlock, loading', (tester) async {
      server.holdKeys = Completer<void>();
      final c = await pump(tester);
      expect(where(c), '/unlock');
      expect(find.text('Abriendo tus datos…'), findsOneWidget);
      server.holdKeys!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a mode nobody could tell shows the offline view, with a retry', (tester) async {
      server.offline.add('tok');
      final c = await pump(tester);
      expect(where(c), '/unlock');
      expect(find.text('Sin conexión'), findsOneWidget);
      server.offline.clear();
      await tester.tap(find.byKey(const Key('vault.retry')));
      await tester.pumpAndSettle();
      expect(find.text('Sin conexión'), findsNothing);
      expect(find.text('Guarda tu clave de recuperación'), findsOneWidget);
    });

    testWidgets('a plain account goes on to home', (tester) async {
      server = FakeServer({'tok': (id: 'user_p', mode: 'plain')});
      final c = await pump(tester);
      expect(where(c), '/');
    });
  });
}
