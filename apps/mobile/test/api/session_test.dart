import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/passkeys.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/capture_auto/capture_platform.dart';
import 'package:wambito/home/home_cache.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/keys.dart';
import 'package:wambito/vault/vault_gate.dart';

import '../capture_auto/fakes.dart';
import '../entry/fakes.dart';
import '../home/fakes.dart';
import '../local/fake_keys.dart';

/// What happened, in order, across the widget's store and the session's.
final _log = <String>[];

class _LoggedWidgetStore extends FakeWidgetStore {
  @override
  Future<void> save(String key, String value) async {
    await super.save(key, value);
    _log.add(value.contains('"signedIn":false') ? 'widget signed out' : 'widget figures');
  }

  @override
  Future<void> updateWidgets() async {
    await super.updateWidgets();
    _log.add('widgets redrawn');
  }
}

class _LoggedSessionStore extends SessionStore {
  @override
  Future<void> clear() async {
    _log.add('session cleared');
    await super.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionStore', () {
    setUp(mockStorage);

    test('is empty at first, keeps what is written, and forgets it on clear', () async {
      final store = SessionStore();
      expect(await store.read(), isNull);

      await store.write('abc', guest: true);
      final stored = await store.read();
      expect(stored?.token, 'abc');
      expect(stored?.guest, isTrue);

      await store.write('def', guest: false);
      expect((await store.read())?.guest, isFalse);

      await store.clear();
      expect(await store.read(), isNull);
    });

    test('a token stored without the guest flag reads as a guest (the safe side)', () async {
      FlutterSecureStorage.setMockInitialValues({SessionStore.tokenKey: 'abc'});
      expect((await SessionStore().read())?.guest, isTrue);
    });
  });

  group('SessionController', () {
    late FakeAuthApi auth;
    late FakePasskeys passkeys;
    late FakeWidgetStore widget;
    late FakeCacheStore homeCache;

    ProviderContainer containerWith() {
      final container = ProviderContainer(
        overrides: [
          authApiProvider.overrideWithValue(auth),
          passkeysProvider.overrideWithValue(passkeys),
          widgetStoreProvider.overrideWithValue(widget),
          homeCacheStoreProvider.overrideWithValue(homeCache),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<SessionController> ready(ProviderContainer container) async {
      final controller = container.read(sessionProvider.notifier);
      await controller.ready;
      return controller;
    }

    setUp(() {
      auth = FakeAuthApi();
      passkeys = FakePasskeys();
      widget = FakeWidgetStore();
      homeCache = FakeCacheStore();
      mockStorage();
    });

    test('starts signed out with nothing stored', () async {
      final container = containerWith();
      await ready(container);
      expect(container.read(sessionProvider).status, SessionStatus.signedOut);
    });

    test('startGuest stores a guest session', () async {
      final container = containerWith();
      final controller = await ready(container);
      await controller.startGuest();

      final state = container.read(sessionProvider);
      expect(state.status, SessionStatus.signedIn);
      expect(state.stored?.token, 'guest-token-1');
      expect(state.stored?.guest, isTrue);
      expect((await SessionStore().read())?.guest, isTrue);
    });

    test('sendCode and verifyCode sign in with an email', () async {
      final container = containerWith();
      final controller = await ready(container);
      await controller.sendCode('ana@correo.com');
      await controller.verifyCode('ana@correo.com', '123456');

      // Then, as the phone has passkeys, whether to offer one (test/entry/passkey_offer_flow_test.dart),
      // with the new session's token.
      expect(auth.calls, [
        'sendCode ana@correo.com',
        'verifyCode ana@correo.com 123456',
        'accountId email-token-1',
        'passkeyCount email-token-1',
        // And whether the account still has the welcome to do (test/api/onboarding_session_test.dart).
        'isGuest email-token-1',
      ]);
      expect(container.read(sessionProvider).stored?.token, 'email-token-1');
      expect(container.read(sessionProvider).stored?.guest, isFalse);
    });

    group('never discards a guest token on an email sign-in', () {
      setUp(() => mockStorage(token: 'guest-token-0', guest: true));

      test('sendCode, verifyCode and the passkey stop with GuestInTheWay', () async {
        auth.guests['guest-token-0'] = true;
        final container = containerWith();
        final controller = await ready(container);

        await expectLater(controller.sendCode('ana@correo.com'), throwsA(isA<GuestInTheWay>()));
        await expectLater(
          controller.verifyCode('ana@correo.com', '123456'),
          throwsA(isA<GuestInTheWay>()),
        );
        await expectLater(controller.signInWithPasskey(), throwsA(isA<GuestInTheWay>()));

        expect(auth.calls.where((c) => !c.startsWith('isGuest')), isEmpty);
        expect(passkeys.calls, isEmpty);
        expect(container.read(sessionProvider).stored?.token, 'guest-token-0');
        expect((await SessionStore().read())?.token, 'guest-token-0');
      });

      test('claiming the email keeps the same token and user, no longer a guest', () async {
        auth.guests['guest-token-0'] = true;
        final container = containerWith();
        final controller = await ready(container);

        await controller.claimEmail('ana@correo.com');
        await controller.confirmClaim('ana@correo.com', '111222');

        expect(auth.calls.where((c) => !c.startsWith('isGuest')), [
          'claimSend guest-token-0 ana@correo.com',
          'claimVerify guest-token-0 ana@correo.com 111222',
          // The guest's start was its welcome.
          'completeOnboarding guest-token-0',
        ]);
        final stored = await SessionStore().read();
        expect(stored?.token, 'guest-token-0');
        expect(stored?.guest, isFalse);
      });

      test('replaceGuest: true, once the person was warned, signs in as the email', () async {
        auth.guests['guest-token-0'] = true;
        final container = containerWith();
        final controller = await ready(container);

        await controller.sendCode('ana@correo.com', replaceGuest: true);
        await controller.verifyCode('ana@correo.com', '123456', replaceGuest: true);

        expect(container.read(sessionProvider).stored?.token, 'email-token-1');
      });

      test("a replaced guest's home cache and widget figures are cleared", () async {
        auth.guests['guest-token-0'] = true;
        homeCache.value = '{"v":1}';
        widget.saved[widgetSnapshotKey] = '{"v":1}';
        final container = containerWith();
        final controller = await ready(container);

        await controller.verifyCode('ana@correo.com', '123456', replaceGuest: true);

        expect(container.read(sessionProvider).stored?.token, 'email-token-1');
        expect(homeCache.value, isNull);
        expect(widgetSignedOut(widget), isTrue);
      });

      test('claiming an email keeps the same token, so the cache stays', () async {
        homeCache.value = '{"v":1}';
        final container = containerWith();
        final controller = await ready(container);

        await controller.claimEmail('ana@correo.com');
        await controller.confirmClaim('ana@correo.com', '123456');

        expect(homeCache.value, '{"v":1}');
      });

      test('a guest whose stored flag is stale is still caught by /v1/me', () async {
        mockStorage(token: 'guest-token-0', guest: false);
        auth.guests['guest-token-0'] = true;
        final container = containerWith();
        final controller = await ready(container);
        await controller.refreshed;

        await expectLater(controller.sendCode('ana@correo.com'), throwsA(isA<GuestInTheWay>()));
      });
    });

    test('a claim needs a guest session', () async {
      mockStorage(token: 'email-token-0');
      final container = containerWith();
      final controller = await ready(container);
      await expectLater(controller.claimEmail('ana@correo.com'), throwsA(isA<StateError>()));
    });

    test('signInWithPasskey asks the phone with the server options and keeps the token', () async {
      final container = containerWith();
      final controller = await ready(container);
      await controller.signInWithPasskey();

      expect(passkeys.calls, ['get {"challenge":"sign-in"}']);
      expect(auth.calls, [
        'passkeySignInOptions',
        'passkeySignIn {"assertion":true}',
        'isGuest passkey-token-1',
      ]);
      expect(container.read(sessionProvider).stored?.token, 'passkey-token-1');
      expect(container.read(sessionProvider).isGuest, isFalse);
    });

    test("a guest's passkey signs them back in as a guest", () async {
      auth.passkeyBelongsToGuest = true;
      final container = containerWith();
      final controller = await ready(container);
      await controller.signInWithPasskey();

      expect(container.read(sessionProvider).isGuest, isTrue);
      expect((await SessionStore().read())?.guest, isTrue);
      // So signing out warns first, as for any guest.
      await expectLater(controller.signOut(), throwsA(isA<GuestInTheWay>()));
    });

    test('a passkey sign-in whose guest check fails is kept as a guest (the safe side)', () async {
      final container = containerWith();
      final controller = await ready(container);
      auth.failures['isGuest'] = const AuthFailure(code: 'NETWORK', status: 0);
      await controller.signInWithPasskey();

      expect(container.read(sessionProvider).stored?.token, 'passkey-token-1');
      expect(container.read(sessionProvider).isGuest, isTrue);
    });

    group('signInWithAvailablePasskey (the email screen, on opening)', () {
      test('asks only for what the phone has at once, and signs in with it', () async {
        passkeys.hasPasskey = true;
        final container = containerWith();
        final controller = await ready(container);

        expect(await controller.signInWithAvailablePasskey(), isTrue);
        expect(passkeys.calls, ['getAvailable {"challenge":"sign-in"}']);
        expect(container.read(sessionProvider).stored?.token, 'passkey-token-1');
        expect(container.read(sessionProvider).isGuest, isFalse);
      });

      test('with none to offer, or the sheet closed, it is false and nothing changes', () async {
        final container = containerWith();
        final controller = await ready(container);

        expect(await controller.signInWithAvailablePasskey(), isFalse);
        passkeys.hasPasskey = true;
        passkeys.failure = const AuthFailure(code: 'AUTH_CANCELLED', status: 400);
        expect(await controller.signInWithAvailablePasskey(), isFalse);
        expect(container.read(sessionProvider).status, SessionStatus.signedOut);
        expect(auth.calls.where((c) => c.startsWith('passkeySignIn ')), isEmpty);
      });

      test('no connection for the challenge is as silent: the email is there', () async {
        passkeys.hasPasskey = true;
        final container = containerWith();
        final controller = await ready(container);
        auth.failures['passkeySignInOptions'] = const AuthFailure(code: 'NETWORK', status: 0);

        expect(await controller.signInWithAvailablePasskey(), isFalse);
        expect(passkeys.calls, isEmpty);
      });

      test('a passkey the person chose and the server refuses is an AuthFailure', () async {
        passkeys.hasPasskey = true;
        final container = containerWith();
        final controller = await ready(container);
        auth.failures['passkeySignIn'] = const AuthFailure(code: 'PASSKEY_NOT_FOUND', status: 401);

        await expectLater(controller.signInWithAvailablePasskey(), throwsA(isA<AuthFailure>()));
        expect(container.read(sessionProvider).status, SessionStatus.signedOut);
      });

      test('never discards a guest token: GuestInTheWay, and the phone is not asked', () async {
        mockStorage(token: 'guest-token-0', guest: true);
        auth.guests['guest-token-0'] = true;
        passkeys.hasPasskey = true;
        final container = containerWith();
        final controller = await ready(container);

        await expectLater(controller.signInWithAvailablePasskey(), throwsA(isA<GuestInTheWay>()));
        expect(passkeys.calls, isEmpty);
        expect(container.read(sessionProvider).stored?.token, 'guest-token-0');
      });
    });

    test('registerPasskey adds a passkey to the signed-in user, guest or not', () async {
      final container = containerWith();
      final controller = await ready(container);
      await controller.startGuest();
      await controller.registerPasskey();

      expect(passkeys.calls, ['create {"challenge":"register"}']);
      expect(auth.calls.skip(1), [
        'passkeyRegisterOptions guest-token-1',
        'passkeyRegister guest-token-1 {"attestation":true}',
      ]);
      // Still the same guest session.
      expect(container.read(sessionProvider).stored?.token, 'guest-token-1');
    });

    test('a cancelled passkey prompt changes nothing', () async {
      final container = containerWith();
      final controller = await ready(container);
      passkeys.failure = const AuthFailure(code: 'AUTH_CANCELLED', status: 400);

      await expectLater(controller.signInWithPasskey(), throwsA(isA<AuthFailure>()));
      expect(container.read(sessionProvider).status, SessionStatus.signedOut);
    });

    test('signOut forgets the session', () async {
      mockStorage(token: 'email-token-0');
      final container = containerWith();
      final controller = await ready(container);
      await controller.signOut();

      expect(container.read(sessionProvider).status, SessionStatus.signedOut);
      expect(await SessionStore().read(), isNull);
      expect(auth.calls.last, 'signOut email-token-0');
    });

    test('signOut clears the queue of captures waiting to be sent', () async {
      mockStorage(token: 'email-token-0');
      final capture = FakeAutoCapturePlatform();
      final container = ProviderContainer(
        overrides: [
          authApiProvider.overrideWithValue(auth),
          passkeysProvider.overrideWithValue(passkeys),
          widgetStoreProvider.overrideWithValue(widget),
          homeCacheStoreProvider.overrideWithValue(homeCache),
          autoCapturePlatformProvider.overrideWithValue(capture),
        ],
      );
      addTearDown(container.dispose);
      final controller = await ready(container);
      await controller.signOut();

      expect(capture.callsNamed('clearQueue'), hasLength(1));
      expect(container.read(sessionProvider).status, SessionStatus.signedOut);
    });

    group('sends the captures queued for the account that signs in', () {
      late FakeAutoCapturePlatform capture;

      ProviderContainer withCapture() {
        final container = ProviderContainer(
          overrides: [
            authApiProvider.overrideWithValue(auth),
            passkeysProvider.overrideWithValue(passkeys),
            widgetStoreProvider.overrideWithValue(widget),
            homeCacheStoreProvider.overrideWithValue(homeCache),
            autoCapturePlatformProvider.overrideWithValue(capture),
          ],
        );
        addTearDown(container.dispose);
        return container;
      }

      setUp(() => capture = FakeAutoCapturePlatform());

      test('after an email sign-in, with the account id', () async {
        auth.account = 'user-7';
        final controller = await ready(withCapture());
        await controller.verifyCode('ana@correo.com', '123456');
        await pumpEventQueue();
        expect(capture.callsNamed('sendQueued'), ['sendQueued user-7']);
      });

      test('after a guest starts', () async {
        auth.account = 'guest-user';
        final controller = await ready(withCapture());
        await controller.startGuest();
        await pumpEventQueue();
        expect(capture.callsNamed('sendQueued'), ['sendQueued guest-user']);
      });

      test('at a start whose stored session the server still knows', () async {
        mockStorage(token: 'email-token-0');
        auth.account = 'user-3';
        final controller = await ready(withCapture());
        await controller.refreshed;
        await pumpEventQueue();
        expect(capture.callsNamed('sendQueued'), ['sendQueued user-3']);
      });

      test('never at a start whose session the server dropped, and the queue is kept', () async {
        mockStorage(token: 'email-token-0');
        auth.failures['isGuest'] = const AuthFailure(status: 401);
        final controller = await ready(withCapture());
        await controller.refreshed;
        await pumpEventQueue();
        expect(capture.callsNamed('sendQueued'), isEmpty);
        expect(capture.callsNamed('clearQueue'), isEmpty);
      });

      test('not when the account cannot be told (offline)', () async {
        auth.failures['accountId'] = const AuthFailure(status: 0);
        final controller = await ready(withCapture());
        await controller.startGuest();
        await pumpEventQueue();
        expect(capture.callsNamed('sendQueued'), isEmpty);
      });

      test('without an Android side the account is not even asked', () async {
        capture.available = false;
        final controller = await ready(withCapture());
        await controller.startGuest();
        await pumpEventQueue();
        expect(capture.callsNamed('sendQueued'), isEmpty);
        expect(auth.calls.where((c) => c.startsWith('accountId')), isEmpty);
      });
    });

    test(
      'signOut of a guest throws GuestInTheWay and keeps the session, the widget and the cache',
      () async {
        mockStorage(token: 'guest-token-0', guest: true);
        auth.guests['guest-token-0'] = true;
        widget.saved[widgetSnapshotKey] = '{"v":1}';
        homeCache.value = '{"v":1}';
        final container = containerWith();
        final controller = await ready(container);

        await expectLater(controller.signOut(), throwsA(isA<GuestInTheWay>()));

        expect(container.read(sessionProvider).status, SessionStatus.signedIn);
        expect((await SessionStore().read())?.token, 'guest-token-0');
        expect(
          auth.calls,
          isNot(contains('signOut guest-token-0')),
          reason: 'the server is not told',
        );
        expect(widget.saved, isNotEmpty);
        expect(homeCache.value, isNotNull);
      },
    );

    test('a guest who was warned signs out with discardGuest, and everything goes', () async {
      mockStorage(token: 'guest-token-0', guest: true);
      auth.guests['guest-token-0'] = true;
      widget.saved[widgetSnapshotKey] = '{"v":1}';
      homeCache.value = '{"v":1}';
      final container = containerWith();
      final controller = await ready(container);

      await controller.signOut(discardGuest: true);

      expect(container.read(sessionProvider).status, SessionStatus.signedOut);
      expect(await SessionStore().read(), isNull);
      expect(auth.calls.last, 'signOut guest-token-0');
      expect(widgetSignedOut(widget), isTrue);
      expect(homeCache.value, isNull);
    });

    test(
      'the old server being down does not stop the sign-out: everything local still goes',
      () async {
        mockStorage(token: 'email-token-0');
        widget.saved[widgetSnapshotKey] = '{"v":1}';
        homeCache.value = '{"v":1}';
        auth.failures['signOut'] = const AuthFailure(status: 0);
        final container = containerWith();
        final controller = await ready(container);

        await controller.signOut();

        expect(auth.calls, contains('signOut email-token-0'));
        expect(container.read(sessionProvider).status, SessionStatus.signedOut);
        expect(await SessionStore().read(), isNull);
        expect(widgetSignedOut(widget), isTrue);
        expect(homeCache.value, isNull);
      },
    );

    test('any error from the server call still signs out locally, whatever it is', () async {
      final errors = <String, Object>{
        'socket': const SocketException('Connection refused'),
        'tls': const HandshakeException('bad certificate'),
        'http': const HttpException('closed'),
        'bug': StateError('unexpected'),
      };
      for (final entry in errors.entries) {
        mockStorage(token: 'email-token-0');
        widget.saved[widgetSnapshotKey] = '{"v":1}';
        homeCache.value = '{"v":1}';
        auth.failures['signOut'] = entry.value;
        final container = containerWith();
        final controller = await ready(container);

        await controller.signOut();

        expect(container.read(sessionProvider).status, SessionStatus.signedOut, reason: entry.key);
        expect(await SessionStore().read(), isNull, reason: entry.key);
        expect(widgetSignedOut(widget), isTrue, reason: entry.key);
        expect(homeCache.value, isNull, reason: entry.key);
      }
    });

    test('a 5xx from the server still signs out locally', () async {
      mockStorage(token: 'email-token-0');
      widget.saved[widgetSnapshotKey] = '{"v":1}';
      homeCache.value = '{"v":1}';
      auth.failures['signOut'] = const AuthFailure(status: 503);
      final container = containerWith();
      final controller = await ready(container);
      await controller.signOut();
      expect(container.read(sessionProvider).status, SessionStatus.signedOut);
      expect(widgetSignedOut(widget), isTrue);
      expect(homeCache.value, isNull);
    });

    testWidgets('a server that never answers is waited for 10 seconds at most', (tester) async {
      mockStorage(token: 'email-token-0');
      widget.saved[widgetSnapshotKey] = '{"v":1}';
      homeCache.value = '{"v":1}';
      auth.holdSignOut = Completer<void>();
      final container = containerWith();
      final controller = await ready(container);

      var done = false;
      unawaited(controller.signOut().then((_) => done = true));
      await tester.pump(const Duration(seconds: 9));
      expect(done, isFalse, reason: 'still waiting for the server');
      expect(container.read(sessionProvider).status, SessionStatus.signedIn);

      await tester.pump(const Duration(seconds: 2));
      expect(done, isTrue);
      expect(container.read(sessionProvider).status, SessionStatus.signedOut);
      expect(widgetSignedOut(widget), isTrue);
      expect(homeCache.value, isNull);
    });

    group('the widget is signed out before the session is forgotten', () {
      // If the process dies in between, the widget must not keep the figure: with the session
      // still there, the next start (or refresh) finds it and puts things right.
      ProviderContainer ordered() {
        _log.clear();
        final container = ProviderContainer(
          overrides: [
            authApiProvider.overrideWithValue(auth),
            passkeysProvider.overrideWithValue(passkeys),
            widgetStoreProvider.overrideWithValue(_LoggedWidgetStore()),
            sessionStoreProvider.overrideWithValue(_LoggedSessionStore()),
            homeCacheStoreProvider.overrideWithValue(homeCache),
          ],
        );
        addTearDown(container.dispose);
        return container;
      }

      test('on sign-out', () async {
        mockStorage(token: 'email-token-0');
        final container = ordered();
        await ready(container).then((c) => c.signOut());
        expect(_log, ['widget signed out', 'widgets redrawn', 'session cleared']);
      });

      test('when the server no longer knows the session', () async {
        mockStorage(token: 'stale-token');
        auth.failures['isGuest'] = const AuthFailure(status: 401);
        final container = ordered();
        await (await ready(container)).refreshed;
        expect(_log, ['widget signed out', 'widgets redrawn', 'session cleared']);
      });
    });

    test("signOut also wipes the widget's figures: they are the person's", () async {
      mockStorage(token: 'email-token-0');
      widget.saved[widgetSnapshotKey] = '{"v":1}';
      final container = containerWith();
      final controller = await ready(container);
      await controller.signOut();

      expect(widgetSignedOut(widget), isTrue);
      // And the widgets on the home screen are redrawn with it.
      await Future<void>.delayed(Duration.zero);
      expect(widget.updates, greaterThan(0));
    });

    test('signOut also wipes the home cache: the next person must never see it', () async {
      mockStorage(token: 'email-token-0');
      homeCache.value = '{"v":1}';
      final container = containerWith();
      final controller = await ready(container);
      await controller.signOut();

      expect(homeCache.value, isNull);
    });

    test('a session the server no longer knows wipes the home cache too', () async {
      mockStorage(token: 'stale-token');
      homeCache.value = '{"v":1}';
      auth.failures['isGuest'] = const AuthFailure(status: 401);
      final container = containerWith();
      final controller = await ready(container);
      await controller.refreshed;

      expect(homeCache.value, isNull);
    });

    test("a session the server no longer knows wipes the widget's figures too", () async {
      mockStorage(token: 'stale-token');
      widget.saved[widgetSnapshotKey] = '{"v":1}';
      auth.failures['isGuest'] = const AuthFailure(status: 401);
      final container = containerWith();
      final controller = await ready(container);
      await controller.refreshed;

      expect(container.read(sessionProvider).status, SessionStatus.signedOut);
      expect(widgetSignedOut(widget), isTrue);
    });

    group('signInWithRecoveryKey (Review Focus 3)', () {
      /// Every secret the session parsed, to check that it is zeroed.
      final parsed = <Uint8List>[];

      setUp(() {
        parsed.clear();
        keysParseRecoveryKey = (text) {
          final secret = parseRecoveryKey(text);
          parsed.add(secret);
          return secret;
        };
      });
      tearDown(() => keysParseRecoveryKey = parseRecoveryKey);

      /// An account set up on another phone (its recovery wrap and verifier on the fake
      /// `/v2/keys`), this phone holding nothing of it: its recovery key.
      Future<({FakeKeys api, KeysOptions options, String key})> accountElsewhere() async {
        final api = FakeKeys();
        final userId = newUser();
        auth.account = userId;
        final options = KeysOptions(userId: userId, dio: api.dio(), storage: memoryKeyStorage());
        final prepared = await prepareAccount(options, guest: false);
        await prepared.commit();
        await forgetDevice(userId, options.storage);
        return (api: api, options: options, key: prepared.recoveryKey!);
      }

      /// The app's gate for that account, which must never ask for the key.
      VaultGate<LocalKeys, String> gateFor(ProviderContainer container, KeysOptions options) =>
          VaultGate(
            VaultGateDeps(
              loadLocalKeys: () => loadLocalKeys(options.userId, options.storage),
              prepareAccount: () async => throw const KeysError('already_set_up'),
              unlockWithRecovery: (_) async => throw StateError('the gate asked for the key'),
              takeSignInRecoverySecret: () =>
                  container.read(signInRecoveryKeyProvider).take(options.userId),
              unlockWithRecoverySecret: (secret) => unlockWithRecoverySecret(options, secret),
              open: (keys, fresh) async => 'open',
            ),
          );

      Future<void> settled(VaultGate<LocalKeys, String> gate) async {
        for (var i = 0; i < 500 && (gate.state is Checking || gate.state is Opening); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }

      test(
        'a key typed in lower case with spaces and dashes signs in, and the gate unlocks with it '
        'without asking',
        () async {
          final a = await accountElsewhere();
          final typed = '  ${a.key.toLowerCase().replaceAll('-', ' - ')}\n';
          final container = containerWith();
          final controller = await ready(container);

          await controller.signInWithRecoveryKey(typed);

          // What was sent is what the server keeps the hashes of.
          final sent = auth.recoverySignIns.single;
          expect(sent.lookup, hasLength(16));
          expect(sent.auth, hasLength(32));
          expect(toBase64Url(await verifierHash(sent.lookup)), a.api.verifier!.lookupHash);
          expect(toBase64Url(await verifierHash(sent.auth)), a.api.verifier!.authHash);
          final state = container.read(sessionProvider);
          expect(state.status, SessionStatus.signedIn);
          expect(state.stored?.token, 'recovery-token-1');
          expect(state.stored?.guest, isFalse);

          final gate = gateFor(container, a.options)..start();
          await settled(gate);
          expect(gate.state, const Ready('open'));
          expect(await loadLocalKeys(a.options.userId, a.options.storage), isNotNull);
        },
      );

      test('a key that does not parse sends nothing', () async {
        final container = containerWith();
        final controller = await ready(container);
        for (final text in ['', 'hello', 'ABCD-EFGH-JKMN-PQRS-TVWX-YZ01-23']) {
          await expectLater(
            controller.signInWithRecoveryKey(text),
            throwsA(
              isA<AuthFailure>()
                  .having((f) => f.code, 'code', 'bad_recovery_key')
                  .having((f) => f.status, 'status', 400),
            ),
          );
        }
        expect(auth.calls, isNot(contains('recoverySignIn')));
        expect(container.read(sessionProvider).status, SessionStatus.signedOut);
      });

      test(
        'the held secret is taken once and is all zeros after the unlock, and after a failed one',
        () async {
          final a = await accountElsewhere();
          final container = containerWith();
          final controller = await ready(container);
          final held = container.read(signInRecoveryKeyProvider);

          // Taken once: a second take has nothing.
          await controller.signInWithRecoveryKey(a.key);
          final secret = held.take(a.options.userId);
          expect(secret, isNotNull);
          expect(zeroed(secret!), isFalse);
          expect(held.take(a.options.userId), isNull);
          held.hold(a.options.userId, secret);

          // All zeros after the unlock.
          final gate = gateFor(container, a.options)..start();
          await settled(gate);
          expect(gate.state, const Ready('open'));
          expect(zeroed(secret), isTrue);
          expect(parsed.every(zeroed), isTrue);

          // And after a failed one: a key that signs in but opens nothing here.
          await forgetDevice(a.options.userId, a.options.storage);
          await controller.signInWithRecoveryKey(formatRecoveryKey(newRecoverySecret()));
          final other = parsed.last;
          expect(zeroed(other), isFalse);
          final failing = gateFor(container, a.options)..start();
          await settled(failing);
          expect(failing.state, const Unlock(error: 'wrong_recovery_key'));
          expect(zeroed(other), isTrue);

          // And at once after a failed sign-in, with nothing held.
          auth.failures['recoverySignIn'] = const AuthFailure(
            code: 'recovery_key_invalid',
            status: 401,
          );
          await expectLater(
            controller.signInWithRecoveryKey(a.key),
            throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'recovery_key_invalid')),
          );
          expect(zeroed(parsed.last), isTrue);
          expect(held.take(a.options.userId), isNull);
        },
      );
    });
  });

  test('passkeysSupported is false where the platform cannot answer', () async {
    expect(await const PlatformPasskeys().supported(), isFalse);
  });
}
