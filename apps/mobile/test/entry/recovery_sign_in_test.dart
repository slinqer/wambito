// Signing in with the recovery key (phone-first spec, recovery-key sign-in): the email screen's link
// opens the recovery screen; the key typed there signs in (`POST /v2/recovery/sign-in`) and the same
// key then opens the vault, without asking for it again.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/client.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/l10n/app_localizations.dart';
import 'package:wambito/local/keys.dart';
import 'package:wambito/local/vault_session.dart';
import 'package:wambito/router.dart';
import 'package:wambito/ui/press_button.dart';
import 'package:wambito/vault/unlock_view.dart';
import 'package:wambito/vault/vault_gate.dart';
import 'package:wambito/vault/vault_providers.dart';

import '../local/fake_keys.dart';
import '../protect/fakes.dart' show FakeVault;
import '../support/preview_account.dart';
import 'fakes.dart';

final _es = lookupAppLocalizations(const Locale('es'));

/// A recovery sign-in that answers from the verifiers the server keeps (lookup → account), as the
/// API's `findVerifiedUser`: nothing kept is 401 `recovery_key_invalid`.
class _VerifierServer extends FakeAuthApi {
  final verifiers = <String, String>{};

  @override
  Future<RecoverySignedInAs> recoverySignIn(Uint8List lookup, Uint8List auth) async {
    final owner = verifiers[toBase64Url(lookup)];
    if (owner == null) {
      calls.add('recoverySignIn');
      throw const AuthFailure(code: 'recovery_key_invalid', status: 401);
    }
    account = owner;
    return super.recoverySignIn(lookup, auth);
  }
}

/// An open vault on a memory store, as far as the gate's wiring needs one.
class _Vault extends FakeVault {
  // Set up on another phone, which also finished the welcome (the vault's flag; the server's
  // stays empty for an encrypted account).
  _Vault(String userId) : super(userId: userId, onboardingCompletedAt: '2026-11-01T12:00:00.000Z');

  @override
  Interceptor get interceptor => Interceptor();

  @override
  void Function() onClosed(void Function() listener) => () {};

  @override
  void Function() onRemoved(void Function() listener) => () {};

  @override
  void Function() onUnverified(void Function() listener) => () {};

  @override
  Future<void> close() async {}

  @override
  void externalChange() {}

  @override
  Future<int> unreadableCount() async => 0;
}

/// Lets the real crypto and the fake servers answer, then draws.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pumpAndSettle();
  }
}

void main() {
  late FakeAuthApi auth;
  setUp(() {
    auth = FakeAuthApi();
    mockStorage();
  });

  String location(ProviderContainer container) =>
      container.read(routerProvider).routerDelegate.currentConfiguration.last.matchedLocation;

  /// The email screen's link to the recovery screen.
  Future<ProviderContainer> openRecovery(
    WidgetTester t, {
    bool plain = true,
    List<Override> overrides = const [],
  }) async {
    final container = await pumpApp(t, auth: auth, plain: plain, overrides: overrides);
    await t.tap(find.byKey(const Key('entry.haveAccount')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('entry.useRecoveryKey')));
    await t.pumpAndSettle();
    expect(location(container), '/entry/recovery');
    return container;
  }

  Future<void> submit(WidgetTester t, String key) async {
    await t.enterText(find.byKey(const Key('recovery.input')), key);
    await t.pump();
    await t.tap(find.byKey(const Key('recovery.submit')));
    await t.pumpAndSettle();
  }

  String someKey() => formatRecoveryKey(newRecoverySecret());

  testWidgets('wrong key shows the invalid message', (t) async {
    final container = await openRecovery(t);
    auth.failures['recoverySignIn'] = const AuthFailure(code: 'recovery_key_invalid', status: 401);
    await submit(t, someKey());
    expect(find.text(_es.errorRecoveryKeyInvalid), findsOneWidget);
    expect(container.read(sessionProvider).status, SessionStatus.signedOut);
    expect(location(container), '/entry/recovery');
  });

  String fieldText(WidgetTester t) =>
      t.widget<EditableText>(find.byKey(const Key('recovery.input'))).controller.text;

  bool submitEnabled(WidgetTester t) =>
      t.widget<PressButton>(find.byKey(const Key('recovery.submit'))).onPressed != null;

  testWidgets('the field groups the key, and submit waits for a full key', (t) async {
    await openRecovery(t);
    expect(submitEnabled(t), isFalse);
    await t.enterText(find.byKey(const Key('recovery.input')), 'abcd efgh 2');
    await t.pump();
    expect(fieldText(t), 'ABCD-EFGH-2');
    expect(submitEnabled(t), isFalse);
    final key = someKey();
    await t.enterText(find.byKey(const Key('recovery.input')), key.toLowerCase());
    await t.pump();
    expect(fieldText(t), key);
    expect(submitEnabled(t), isTrue);
  });

  testWidgets('Paste fills and groups the field', (t) async {
    final key = someKey();
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.getData') {
        return {'text': key.toLowerCase().replaceAll('-', ' ')};
      }
      return null;
    });
    addTearDown(
      () =>
          t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await openRecovery(t);
    await t.tap(find.byKey(const Key('recovery.paste')));
    await t.pumpAndSettle();
    expect(fieldText(t), key);
    expect(submitEnabled(t), isTrue);
  });

  testWidgets('a key that does not parse says so, and nothing is sent', (t) async {
    await openRecovery(t);
    // A full key whose check character is wrong.
    final key = someKey();
    final last = key[key.length - 1];
    await submit(t, key.substring(0, key.length - 1) + (last == 'A' ? 'B' : 'A'));
    expect(find.text(_es.vaultUnlockErrorBadKey), findsOneWidget);
    expect(auth.calls, isNot(contains('recoverySignIn')));
  });

  testWidgets('429 shows the wait', (t) async {
    await openRecovery(t);
    auth.failures['recoverySignIn'] = const AuthFailure(
      code: 'too_many_requests',
      status: 429,
      retryAfter: 600,
    );
    await submit(t, someKey());
    expect(find.text(_es.recoverySignInWait(10)), findsOneWidget);
  });

  testWidgets('offline shows offline', (t) async {
    await openRecovery(t);
    auth.failures['recoverySignIn'] = const AuthFailure(status: 0);
    await submit(t, someKey());
    expect(find.text(_es.errorNetwork), findsOneWidget);
  });

  testWidgets('a plain account has no verifier: the same invalid message, no session', (t) async {
    // A server that answers from the verifiers it keeps: a `plain` account never stored one (only
    // a vault's setup or "Protect your data" does), so the key of a plain account, even one made
    // and written down, finds nothing. The session stays signed out and no key is held.
    final server = _VerifierServer();
    auth = server;
    final container = await openRecovery(t);
    final plainKey = someKey();
    await submit(t, plainKey);
    expect(server.calls, contains('recoverySignIn'));
    expect(find.text(_es.errorRecoveryKeyInvalid), findsOneWidget);
    expect(container.read(sessionProvider).status, SessionStatus.signedOut);
    expect(await SessionStore().read(), isNull);
    expect(container.read(signInRecoveryKeyProvider).take(server.account), isNull);
  });

  testWidgets('a suspended account says so', (t) async {
    await openRecovery(t);
    auth.failures['recoverySignIn'] = const AuthFailure(code: 'account_suspended', status: 403);
    await submit(t, someKey());
    expect(find.text(_es.errorAccountSuspended), findsOneWidget);
  });

  testWidgets('signed in, the recovery screen is not offered', (t) async {
    mockStorage(token: 'email-token-9');
    final container = await pumpApp(t, auth: auth);
    container.read(routerProvider).go('/entry/recovery');
    await t.pumpAndSettle();
    expect(location(container), '/');
  });

  testWidgets(
    'success lands home with the vault open and recoveryKeySavedAt set when it was null',
    (t) async {
      // An account set up on another phone: its wraps on the fake `/v2/keys`, nothing kept here.
      final keysServer = FakeKeys();
      final userId = newUser();
      auth.account = userId;
      final storage = memoryKeyStorage();
      final options = KeysOptions(userId: userId, dio: keysServer.dio(), storage: storage);
      late String recoveryKey;
      await t.runAsync(() async {
        final prepared = await prepareAccount(options, guest: false);
        await prepared.commit();
        await forgetDevice(userId, storage);
        recoveryKey = prepared.recoveryKey!;
      });
      final vault = _Vault(userId);
      await t.runAsync(() => vault.seeded);
      expect(await t.runAsync(vault.savedAt), isNull);

      final container = await openRecovery(
        t,
        plain: false,
        overrides: [
          previewAccount(id: userId),
          keyStorageProvider.overrideWithValue(storage),
          networkClientProvider.overrideWith(
            (ref) => ApiClient.forServer(
              Uri.parse('http://x'),
              token: ref.watch(sessionProvider.select((s) => s.stored?.token)),
            )..dio.httpClientAdapter = keysServer,
          ),
          openVaultSessionProvider.overrideWithValue((o) async => vault),
        ],
      );
      await t.enterText(
        find.byKey(const Key('recovery.input')),
        recoveryKey.toLowerCase().replaceAll('-', ' '),
      );
      await t.pump();
      await t.tap(find.byKey(const Key('recovery.submit')));
      await _settle(t);

      expect(container.read(vaultGateStateProvider), isA<Ready<VaultSession>>());
      expect(location(container), '/');
      expect(find.byType(HomeScreen), findsOneWidget);
      // Never asked: Unlock was not shown.
      expect(find.byType(UnlockView), findsNothing);
      // This phone holds the keys now, with its own device wrap.
      expect(await t.runAsync(() => loadLocalKeys(userId, storage)), isNotNull);
      expect(keysServer.wraps.where((w) => w.kind == 'device'), hasLength(2));
      // The key was typed, so it is saved somewhere: the step is done.
      expect(await t.runAsync(vault.savedAt), isNotNull);
      // The widget's figures follow the vault's change after a short wait: let it pass.
      await t.pump(const Duration(seconds: 3));
    },
  );
}
