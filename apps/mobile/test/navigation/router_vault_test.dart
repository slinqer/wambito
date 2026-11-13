import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/client.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_cache.dart';
import 'package:wambito/local/key_storage.dart';
import 'package:wambito/router.dart';
import 'package:wambito/vault/vault_providers.dart';

import '../entry/fakes.dart';
import '../home/fakes.dart' show FakeCacheStore, FakePendingSavesStore;
import '../vault/vault_fakes.dart' show FakeServer, setUpVaultFiles, openTestStore, deleteTestStore;

import 'package:wambito/local/vault_session.dart';
import 'package:wambito/offline/pending_saves.dart';
import 'package:wambito/vault/encryption_mode.dart';

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

    Future<ProviderContainer> pump(WidgetTester tester, {List<Override> extra = const []}) => pumpApp(
      tester,
      auth: FakeAuthApi(),
      // The account's mode is the fake server's to say here.
      plain: false,
      overrides: [
        ...extra,
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

  group('a start from what the phone kept (stale-while-revalidate)', () {
    late FakeServer server;

    setUp(() {
      setUpVaultFiles();
    });

    /// The phone kept [mode] for the session of `tok` at an earlier start.
    Future<void> kept(String mode) async {
      mockStorage(token: 'tok');
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
          mode: EncryptionMode.values.byName(mode),
        ),
      );
    }

    Future<ProviderContainer> pump(
      WidgetTester tester, {
      List<Override> extra = const [],
      FakeCacheStore? cache,
    }) => pumpApp(
          tester,
          auth: FakeAuthApi(),
          plain: false,
          homeCache: cache,
          overrides: [
            ...extra,
            networkClientProvider.overrideWith(
              (ref) => ApiClient.forServer(
                Uri.parse('http://x'),
                token: ref.watch(sessionProvider.select((s) => s.stored?.token)),
              )..dio.httpClientAdapter = server,
            ),
            keyStorageProvider.overrideWithValue(KeyStorage()),
            staleVaultsProvider.overrideWithValue((_) async {}),
            openVaultSessionProvider.overrideWithValue(
              (o) => openVaultSession(
                OpenVaultOptions(
                  profile: o.profile,
                  keys: o.keys,
                  fresh: o.fresh,
                  network: o.network,
                  storage: o.storage,
                  openStore: openTestStore,
                  deleteStore: deleteTestStore,
                ),
              ),
            ),
          ],
        );

    String where(ProviderContainer c) =>
        c.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

    testWidgets('a plain account with its mode kept shows home at once, while GET /v1/me waits', (
      tester,
    ) async {
      await kept('plain');
      server = FakeServer({'tok': (id: 'user_p', mode: 'plain')})..holdMe = Completer<void>();
      final c = await pump(tester);
      expect(where(c), '/');
      server.holdMe!.complete();
      await tester.pumpAndSettle();
      expect(where(c), '/');
    });

    testWidgets('a preview account with its mode kept goes straight to /unlock', (tester) async {
      await kept('preview');
      server = FakeServer({'tok': (id: 'user_p', mode: 'preview')})..holdMe = Completer<void>();
      final c = await pump(tester);
      expect(where(c), '/unlock');
      server.holdMe!.complete();
      await tester.pumpAndSettle();
      expect(where(c), '/unlock');
    });

    testWidgets('kept plain, then the server says preview: the route moves to /unlock', (
      tester,
    ) async {
      await kept('plain');
      server = FakeServer({'tok': (id: 'user_p', mode: 'preview')})..holdMe = Completer<void>();
      final c = await pump(tester);
      expect(where(c), '/');
      server.holdMe!.complete();
      await tester.pumpAndSettle();
      expect(where(c), '/unlock');
      expect(c.read(knownPlainProvider), isFalse);
    });

    testWidgets('kept preview, then the server says plain: the route moves home', (tester) async {
      await kept('preview');
      server = FakeServer({'tok': (id: 'user_p', mode: 'plain')})..holdMe = Completer<void>();
      final c = await pump(tester);
      expect(where(c), '/unlock');
      server.holdMe!.complete();
      await tester.pumpAndSettle();
      expect(where(c), '/');
    });

    testWidgets('the first start after the update, offline, with a home cache of this session: '
        'home from the cache, not Locked', (tester) async {
      mockStorage(token: 'tok');
      server = FakeServer({'tok': (id: 'user_p', mode: 'plain')})..offline.add('tok');
      final cache = FakeCacheStore()
        ..value = jsonEncode({'v': 1, 'owner': sessionOwnerOf('tok'), 'userId': 'user_p'});
      final c = await pump(tester, cache: cache);
      expect(where(c), '/');
      expect(find.text('Sin conexión'), findsNothing);
    });

    testWidgets("the first start after the update, offline, with this session's saves waiting: "
        'home, not Locked', (tester) async {
      mockStorage(token: 'tok');
      server = FakeServer({'tok': (id: 'user_p', mode: 'plain')})..offline.add('tok');
      final saves = FakePendingSavesStore()
        ..value = jsonEncode({'v': 1, 'owner': sessionOwnerOf('tok'), 'saves': <Object?>[]});
      final c = await pump(tester, extra: [pendingSavesStoreProvider.overrideWithValue(saves)]);
      expect(where(c), '/');
    });

    testWidgets("another session's home cache proves nothing: offline, Locked", (tester) async {
      mockStorage(token: 'tok');
      server = FakeServer({'tok': (id: 'user_p', mode: 'plain')})..offline.add('tok');
      final cache = FakeCacheStore()
        ..value = jsonEncode({'v': 1, 'owner': sessionOwnerOf('old'), 'userId': 'user_p'});
      final c = await pump(tester, cache: cache);
      expect(where(c), '/unlock');
      expect(find.text('Sin conexión'), findsOneWidget);
    });

    testWidgets('a home cache proves plain only until the server says preview', (tester) async {
      mockStorage(token: 'tok');
      server = FakeServer({'tok': (id: 'user_p', mode: 'preview')})..holdMe = Completer<void>();
      final cache = FakeCacheStore()
        ..value = jsonEncode({'v': 1, 'owner': sessionOwnerOf('tok'), 'userId': 'user_p'});
      final c = await pump(tester, cache: cache);
      expect(where(c), '/');
      // Never known plain: a finance call waits for the server, which says preview.
      expect(c.read(knownPlainProvider), isFalse);
      server.holdMe!.complete();
      await tester.pumpAndSettle();
      expect(where(c), '/unlock');
    });
  });
}
