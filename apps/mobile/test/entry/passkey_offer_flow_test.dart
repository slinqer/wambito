import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/passkey_offer.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/router.dart';

import 'fakes.dart';

/// When the app offers a passkey, as the web does (apps/web/app/auth/passkey.ts `shouldOfferPasskey`
/// and use-finish-sign-in.ts): right after an email sign-in (the code or the magic link), when the
/// phone can use passkeys, the account has none, and the person has not answered on this phone.
/// The answer is kept here, per account, as the web keeps it in `localStorage`. A guest has "Guarda
/// tu progreso" instead; a passkey sign-in needs no offer.
void main() {
  late FakeAuthApi auth;
  setUp(() {
    auth = FakeAuthApi();
    mockStorage();
  });

  const offerTitle = '¿Entrar con tu huella la próxima vez?';

  Future<void> signInWithCode(WidgetTester tester, ProviderContainerOf container) async {
    container.go('/entry/email');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry.email')), 'ana@correo.com');
    await tester.tap(find.byKey(const Key('entry.send')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry.code')), '123456');
    await tester.pump();
    await tester.tap(find.byKey(const Key('entry.submitCode')));
    await tester.pumpAndSettle();
  }

  /// Signs in by code while the passkey list hangs: the lookup's wait runs out.
  Future<void> signInWithCodeLate(WidgetTester tester, ProviderContainerOf app) async {
    app.go('/entry/email');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry.email')), 'ana@correo.com');
    await tester.tap(find.byKey(const Key('entry.send')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry.code')), '123456');
    await tester.pump();
    await tester.tap(find.byKey(const Key('entry.submitCode')));
    await tester.pump(PasskeyOffer.lookupWait);
    await tester.pumpAndSettle();
  }

  Future<ProviderContainerOf> open(
    WidgetTester tester, {
    bool supported = true,
    FakePasskeys? passkeys,
  }) async {
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await pumpApp(
      tester,
      auth: auth,
      passkeys: passkeys ?? FakePasskeys(isSupported: supported),
    );
    return ProviderContainerOf(container, container.read(routerProvider));
  }

  group('shown', () {
    testWidgets('after an email sign-in, when the account has no passkey', (tester) async {
      final app = await open(tester);
      await signInWithCode(tester, app);

      expect(find.text(offerTitle), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      // The account's passkeys were asked of the server, as the web does.
      expect(auth.calls.where((c) => c.startsWith('passkeyCount')), hasLength(1));
    });

    testWidgets('after a magic link too', (tester) async {
      final app = await open(tester);
      app.go('/auth/verify?email=ana%40correo.com&code=654321');
      await tester.pumpAndSettle();

      expect(find.text(offerTitle), findsOneWidget);
    });

    testWidgets('in English', (tester) async {
      final container = await pumpApp(
        tester,
        auth: auth,
        passkeys: FakePasskeys(),
        locale: const Locale('en'),
      );
      await signInWithCode(tester, ProviderContainerOf(container, container.read(routerProvider)));
      expect(find.text('Sign in with your fingerprint next time?'), findsOneWidget);
    });
  });

  group('not shown', () {
    testWidgets('when the account already has a passkey', (tester) async {
      auth.passkeysOnAccount = 1;
      final app = await open(tester);
      await signInWithCode(tester, app);

      expect(find.text(offerTitle), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('on a phone that cannot use passkeys, and nothing is asked of the server', (
      tester,
    ) async {
      final app = await open(tester, supported: false);
      await signInWithCode(tester, app);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(auth.calls.where((c) => c.startsWith('passkeyCount')), isEmpty);
    });

    testWidgets('when the list cannot be read: the offer is skipped, not waited on', (
      tester,
    ) async {
      auth.failures['passkeyCount'] = const AuthFailure(status: 500);
      final app = await open(tester);
      await signInWithCode(tester, app);

      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('after a passkey sign-in', (tester) async {
      final passkeys = FakePasskeys(hasPasskey: true);
      final app = await open(tester, passkeys: passkeys);
      app.go('/entry/email');
      await tester.pumpAndSettle();

      // The phone offered its passkey on opening and signed in with it.
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text(offerTitle), findsNothing);
      expect(auth.calls.where((c) => c.startsWith('passkeyCount')), isEmpty);
    });
  });

  group('the offer never holds the sign-in up', () {
    testWidgets('a list that never answers: the session is stored at once, and the person is '
        'in after a few seconds, without an offer', (tester) async {
      auth.holdPasskeyCount = Completer<void>();
      final app = await open(tester);
      app.go('/entry/email');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('entry.email')), 'ana@correo.com');
      await tester.tap(find.byKey(const Key('entry.send')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('entry.code')), '123456');
      await tester.pump();
      await tester.tap(find.byKey(const Key('entry.submitCode')));
      await tester.pump(const Duration(seconds: 1));

      // The code was accepted: the token is on the phone while the lookup hangs.
      expect((await SessionStore().read())?.token, 'email-token-1');
      expect(auth.calls.last, startsWith('passkeyCount'));

      await tester.pump(PasskeyOffer.lookupWait);
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text(offerTitle), findsNothing);
      expect(app.container.read(sessionProvider).stored?.token, 'email-token-1');
    });

    testWidgets('a list that answers late is not waited for, and the offer is not made after', (
      tester,
    ) async {
      final hold = Completer<void>();
      auth.holdPasskeyCount = hold;
      final app = await open(tester);
      await signInWithCodeLate(tester, app);
      expect(find.byType(HomeScreen), findsOneWidget);

      hold.complete();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text(offerTitle), findsNothing);
    });
  });

  group('never to a guest', () {
    testWidgets('a guest who starts (Start) has Guarda tu progreso, not the offer', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('entry.start')));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text(offerTitle), findsNothing);
      expect(auth.calls.where((c) => c.startsWith('passkeyCount')), isEmpty);
    });

    testWidgets('a guest who saves their progress is not offered one', (tester) async {
      mockStorage(token: 'guest-token-0', guest: true);
      auth.guests['guest-token-0'] = true;
      final app = await open(tester);
      app.go('/entry/email?email=ana%40correo.com&claim=1');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('entry.code')), '111222');
      await tester.pump();
      await tester.tap(find.byKey(const Key('entry.submitCode')));
      await tester.pumpAndSettle();

      expect(find.text(offerTitle), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('a guest who opens the offer\'s address is sent home', (tester) async {
      mockStorage(token: 'guest-token-0', guest: true);
      auth.guests['guest-token-0'] = true;
      final app = await open(tester);
      app.go('/entry/passkey-offer');
      await tester.pumpAndSettle();

      expect(find.text(offerTitle), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('someone signed in with no offer pending who opens it is sent home', (
      tester,
    ) async {
      mockStorage(token: 'email-token-0');
      final app = await open(tester);
      app.go('/entry/passkey-offer');
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('signed out, the offer\'s address is not reachable', (tester) async {
      final app = await open(tester);
      app.go('/entry/passkey-offer');
      await tester.pumpAndSettle();

      expect(find.text(offerTitle), findsNothing);
      expect(find.byKey(const Key('entry.start')), findsOneWidget);
    });
  });

  group('the answer', () {
    testWidgets('"Ahora no" goes home, and the offer never comes back on this phone', (
      tester,
    ) async {
      final app = await open(tester);
      await signInWithCode(tester, app);
      await tester.tap(find.text('AHORA NO'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(auth.calls.where((c) => c.startsWith('passkeyRegister')), isEmpty);

      // Signed out, and in again with the same account: straight home.
      await app.container.read(sessionProvider.notifier).signOut();
      await tester.pumpAndSettle();
      await signInWithCode(tester, app);
      expect(find.text(offerTitle), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('the answer is the account\'s: another account is still offered one', (
      tester,
    ) async {
      final app = await open(tester);
      await signInWithCode(tester, app);
      await tester.tap(find.text('AHORA NO'));
      await tester.pumpAndSettle();
      await app.container.read(sessionProvider.notifier).signOut();
      await tester.pumpAndSettle();

      auth.account = 'user-2';
      await signInWithCode(tester, app);
      expect(find.text(offerTitle), findsOneWidget);
    });

    testWidgets(
      '"Crear mi huella" registers the passkey with the existing registration, then goes home',
      (tester) async {
        final passkeys = FakePasskeys();
        final app = await open(tester, passkeys: passkeys);
        await signInWithCode(tester, app);
        auth.calls.clear();

        await tester.tap(find.text('CREAR MI HUELLA'));
        await tester.pumpAndSettle();

        expect(auth.calls, [startsWith('passkeyRegisterOptions'), startsWith('passkeyRegister ')]);
        expect(passkeys.calls.where((c) => c.startsWith('create')), hasLength(1));
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.text('Listo: la próxima vez entras con tu huella.'), findsOneWidget);

        // Answered: not asked again.
        await app.container.read(sessionProvider.notifier).signOut();
        await tester.pumpAndSettle();
        await signInWithCode(tester, app);
        expect(find.text(offerTitle), findsNothing);
      },
    );

    testWidgets('closing the phone\'s prompt is silent: the offer stays and is not answered', (
      tester,
    ) async {
      final passkeys = FakePasskeys();
      final app = await open(tester, passkeys: passkeys);
      await signInWithCode(tester, app);
      passkeys.failure = const AuthFailure(code: 'AUTH_CANCELLED', status: 400);

      await tester.tap(find.text('CREAR MI HUELLA'));
      await tester.pumpAndSettle();

      expect(find.text(offerTitle), findsOneWidget);
      expect(find.textContaining('No pudimos'), findsNothing);
    });

    testWidgets('a passkey that could not be saved says so, and "Ahora no" still answers', (
      tester,
    ) async {
      final app = await open(tester);
      await signInWithCode(tester, app);
      auth.failures['passkeyRegister'] = const AuthFailure(code: 'SOMETHING', status: 500);

      await tester.tap(find.text('CREAR MI HUELLA'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No pudimos guardar tu huella'), findsOneWidget);
      expect(find.text(offerTitle), findsOneWidget);

      await tester.tap(find.text('AHORA NO'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('a passkey this phone already had counts as made', (tester) async {
      final app = await open(tester);
      await signInWithCode(tester, app);
      auth.failures['passkeyRegister'] = const AuthFailure(
        code: 'ERROR_AUTHENTICATOR_PREVIOUSLY_REGISTERED',
        status: 400,
      );

      await tester.tap(find.text('CREAR MI HUELLA'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });
}

/// The container and the router, for the helpers above.
class ProviderContainerOf {
  const ProviderContainerOf(this.container, this.router);

  final ProviderContainer container;
  final GoRouter router;

  void go(String location) => router.go(location);
}
