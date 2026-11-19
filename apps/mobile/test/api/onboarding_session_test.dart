import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_cache.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/router.dart';

import '../entry/fakes.dart';
import '../home/fakes.dart';

/// Who goes to the welcome: the web decides it with `onboardingCompletedAt`
/// (apps/web/app/auth/session.ts `requireOnboarded`, `redirectIfSignedIn`; features/sign-in/auth.ts
/// `destinationAfterSignIn`). A new email account has none, so it is sent to /welcome after signing
/// in, and from every other screen until it finishes. An account that has it never sees the
/// welcome. A guest keeps its guest start: the web has no guests, and the app's has no welcome.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionStore', () {
    setUp(mockStorage);

    test('keeps whether the welcome is still to do, next to the token', () async {
      final store = SessionStore();
      await store.write('abc', guest: false, onboardingPending: true);
      expect((await store.read())?.onboardingPending, isTrue);
      await store.write('abc', guest: false);
      expect((await store.read())?.onboardingPending, isFalse);
    });

    test('a token stored without it is an account that has finished', () async {
      FlutterSecureStorage.setMockInitialValues({
        SessionStore.tokenKey: 'abc',
        SessionStore.guestKey: 'false',
      });
      expect((await SessionStore().read())?.onboardingPending, isFalse);
    });

    test('knows when the welcome is done, and when it does not know', () async {
      final store = SessionStore();
      await store.write('abc', guest: false);
      expect((await store.read())?.onboardingKnown, isTrue);
      await store.write('abc', guest: false, onboardingPending: true);
      expect((await store.read())?.onboardingKnown, isTrue);
      await store.write('abc', guest: false, onboardingKnown: false);
      final unknown = await store.read();
      expect(unknown?.onboardingKnown, isFalse);
      expect(unknown?.onboardingPending, isFalse);
      // A session stored before the app knew of the welcome says nothing either.
      FlutterSecureStorage.setMockInitialValues({
        SessionStore.tokenKey: 'abc',
        SessionStore.guestKey: 'false',
      });
      expect((await SessionStore().read())?.onboardingKnown, isFalse);
    });

    test('a guest has nothing to know: it is never pending', () async {
      FlutterSecureStorage.setMockInitialValues({
        SessionStore.tokenKey: 'abc',
        SessionStore.guestKey: 'true',
      });
      expect((await SessionStore().read())?.onboardingKnown, isTrue);
    });

    test('a guest never has a welcome to do', () async {
      final store = SessionStore();
      await store.write('abc', guest: true, onboardingPending: true);
      expect((await store.read())?.onboardingPending, isFalse);
    });
  });

  group('SessionController', () {
    late FakeAuthApi auth;

    ProviderContainer containerWith() {
      final container = ProviderContainer(
        overrides: [
          authApiProvider.overrideWithValue(auth),
          passkeysProvider.overrideWithValue(FakePasskeys()),
          widgetStoreProvider.overrideWithValue(FakeWidgetStore()),
          homeCacheStoreProvider.overrideWithValue(FakeCacheStore()),
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
      mockStorage();
    });

    test('a new email account has the welcome to do, and it is kept', () async {
      auth.newAccounts = true;
      final container = containerWith();
      final controller = await ready(container);
      await controller.verifyCode('ana@example.com', '123456');

      expect(container.read(sessionProvider).onboardingPending, isTrue);
      expect((await SessionStore().read())?.onboardingPending, isTrue);
    });

    test('an account that finished it does not', () async {
      final container = containerWith();
      final controller = await ready(container);
      await controller.verifyCode('ana@example.com', '123456');

      expect(container.read(sessionProvider).onboardingPending, isFalse);
    });

    test('a new account that signs in with a passkey has it to do too', () async {
      auth.newAccounts = true;
      final container = containerWith();
      final controller = await ready(container);
      await controller.signInWithPasskey();

      expect(container.read(sessionProvider).onboardingPending, isTrue);
    });

    test('a guest never has it, and keeps its guest start', () async {
      auth.newAccounts = true;
      final container = containerWith();
      final controller = await ready(container);
      await controller.startGuest();

      final state = container.read(sessionProvider);
      expect(state.isGuest, isTrue);
      expect(state.onboardingPending, isFalse);
      expect(sessionRedirect(state, Uri.parse('/')), isNull);
    });

    test('when the profile cannot be read the person is let in, and the next start asks', () async {
      auth.newAccounts = true;
      auth.failures['isGuest'] = const AuthFailure(status: 0);
      final container = containerWith();
      final controller = await ready(container);
      await controller.verifyCode('ana@example.com', '123456');
      expect(container.read(sessionProvider).onboardingPending, isFalse);

      final next = containerWith();
      await next.read(sessionProvider.notifier).refreshed;
      expect(next.read(sessionProvider).onboardingPending, isTrue);
    });

    test('an account the server could not be asked about is not known to be onboarded', () async {
      auth.failures['isGuest'] = const AuthFailure(status: 0);
      final container = containerWith();
      final controller = await ready(container);
      await controller.verifyCode('ana@example.com', '123456');
      expect(container.read(sessionProvider).stored?.onboardingKnown, isFalse);
      // The start asks, and then it is known.
      final next = containerWith();
      await next.read(sessionProvider.notifier).refreshed;
      expect(next.read(sessionProvider).stored?.onboardingKnown, isTrue);
      expect((await SessionStore().read())?.onboardingKnown, isTrue);
    });

    test('finishing the welcome is remembered as done', () async {
      auth.newAccounts = true;
      final container = containerWith();
      final controller = await ready(container);
      await controller.verifyCode('ana@example.com', '123456');
      await controller.onboardingDone();
      expect(container.read(sessionProvider).stored?.onboardingKnown, isTrue);
      expect((await SessionStore().read())?.onboardingKnown, isTrue);
    });

    test('the start asks the server, which can send an account to the welcome', () async {
      auth.pendingOnboarding['tok'] = true;
      mockStorage(token: 'tok');
      final container = containerWith();
      await container.read(sessionProvider.notifier).refreshed;

      expect(container.read(sessionProvider).onboardingPending, isTrue);
      expect((await SessionStore().read())?.onboardingPending, isTrue);
    });

    test('the start also lets one go that finished it somewhere else', () async {
      // A plain account: the server's flag is the account's.
      auth.plainTokens.add('tok');
      mockStorage(token: 'tok', onboarding: true);
      final container = containerWith();
      final controller = container.read(sessionProvider.notifier);
      await controller.ready;
      expect(container.read(sessionProvider).onboardingPending, isTrue);
      await controller.refreshed;

      expect(container.read(sessionProvider).onboardingPending, isFalse);
    });

    test("an encrypted account keeps what its vault said: the server's empty flag never brings "
        'the welcome back', () async {
      // The server's copy stays empty for a preview account: it always says "to do".
      auth.pendingOnboarding['tok'] = true;
      mockStorage(token: 'tok');
      await SessionStore().write('tok', guest: false);
      final container = containerWith();
      final controller = await ready(container);
      await controller.refreshed;
      expect(container.read(sessionProvider).onboardingPending, isFalse);
      expect((await SessionStore().read())?.onboardingPending, isFalse);
      // The vault says it is still to do (a new account): the welcome.
      await controller.onboardingFromVault(pending: true);
      expect(container.read(sessionProvider).onboardingPending, isTrue);
      expect((await SessionStore().read())?.onboardingPending, isTrue);
    });

    test('an encrypted account whose welcome the phone does not know yet takes the server\'s '
        'until its vault says', () async {
      auth.pendingOnboarding['tok'] = true;
      mockStorage(token: 'tok');
      final container = containerWith();
      final controller = await ready(container);
      await controller.refreshed;
      expect(container.read(sessionProvider).onboardingPending, isTrue);
      await controller.onboardingFromVault(pending: false);
      expect(container.read(sessionProvider).onboardingPending, isFalse);
      expect(container.read(sessionProvider).onboardingKnown, isTrue);
    });

    test('a guest has no welcome, whatever its vault says', () async {
      auth.guests['tok'] = true;
      mockStorage(token: 'tok', guest: true);
      final container = containerWith();
      final controller = await ready(container);
      await controller.refreshed;
      await controller.onboardingFromVault(pending: true);
      expect(container.read(sessionProvider).onboardingPending, isFalse);
    });

    test('offline, what is kept stands', () async {
      auth.failures['isGuest'] = const AuthFailure(status: 0);
      mockStorage(token: 'tok', onboarding: true);
      final container = containerWith();
      await container.read(sessionProvider.notifier).refreshed;

      expect(container.read(sessionProvider).onboardingPending, isTrue);
    });

    test('finishing the welcome clears it, and keeps the session', () async {
      auth.newAccounts = true;
      final container = containerWith();
      final controller = await ready(container);
      await controller.verifyCode('ana@example.com', '123456');
      await controller.onboardingDone();

      final state = container.read(sessionProvider);
      expect(state.onboardingPending, isFalse);
      expect(state.stored?.token, 'email-token-1');
      expect((await SessionStore().read())?.onboardingPending, isFalse);
    });

    test('a guest that saves its progress with an email has started: no welcome', () async {
      final container = containerWith();
      final controller = await ready(container);
      await controller.startGuest();
      await controller.claimEmail('ana@example.com');
      await controller.confirmClaim('ana@example.com', '123456');

      expect(container.read(sessionProvider).onboardingPending, isFalse);
      expect(auth.calls, contains('completeOnboarding guest-token-1'));
      expect(auth.pendingOnboarding['guest-token-1'], isFalse);
    });
  });

  group('where the session sends a person', () {
    const pending = SessionState.signedIn(
      StoredSession(token: 't', guest: false, onboardingPending: true),
    );
    const done = SessionState.signedIn(StoredSession(token: 't', guest: false));
    const guest = SessionState.signedIn(StoredSession(token: 't', guest: true));

    test('with the welcome to do: to it, from home and every other screen', () {
      for (final path in [
        '/',
        '/settings',
        '/insights',
        '/recurring',
        '/import',
        '/categories/c1',
        '/entry',
        '/entry/email',
        '/loading',
      ]) {
        expect(sessionRedirect(pending, Uri.parse(path)), '/welcome', reason: path);
      }
    });

    test('with the welcome to do: its steps and the magic link stay', () {
      for (final path in [
        '/welcome',
        '/welcome/currency',
        '/welcome/import',
        '/welcome/categories',
        '/welcome/budgets',
        '/auth/verify',
      ]) {
        expect(sessionRedirect(pending, Uri.parse(path)), isNull, reason: path);
      }
    });

    test('with the welcome to do and the passkey offer due, the offer comes first', () {
      const offered = SessionState.signedIn(
        StoredSession(token: 't', guest: false, onboardingPending: true),
        offerPasskeyFor: 'user-1',
      );
      for (final path in ['/', '/entry', '/entry/email', '/loading']) {
        expect(sessionRedirect(offered, Uri.parse(path)), '/entry/passkey-offer', reason: path);
      }
      expect(sessionRedirect(offered, Uri.parse('/entry/passkey-offer')), isNull);
      expect(sessionRedirect(offered, Uri.parse('/welcome')), isNull);
    });

    test('once the offer is answered, the way on is the welcome', () {
      expect(sessionRedirect(pending, Uri.parse('/entry/passkey-offer')), '/welcome');
    });

    test('an account that finished it never sees the welcome', () {
      for (final path in ['/welcome', '/welcome/currency', '/welcome/budgets']) {
        expect(sessionRedirect(done, Uri.parse(path)), '/', reason: path);
      }
      expect(sessionRedirect(done, Uri.parse('/')), isNull);
      expect(sessionRedirect(done, Uri.parse('/settings')), isNull);
    });

    test('a guest never does, and nothing sends it there', () {
      for (final path in ['/welcome', '/welcome/import']) {
        expect(sessionRedirect(guest, Uri.parse(path)), '/', reason: path);
      }
      expect(sessionRedirect(guest, Uri.parse('/')), isNull);
    });

    test('signed out, only the entry screens', () {
      expect(sessionRedirect(SessionState.signedOut, Uri.parse('/welcome')), '/entry');
    });
  });
}
