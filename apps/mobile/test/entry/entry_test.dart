import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/home/wambi_face.dart';
import 'package:wambito/progress/progress_screen.dart';
import 'package:wambito/router.dart';
import 'package:wambito/ui/lk_icons.dart';
import 'package:wambito/ui/press_button.dart';
import 'package:wambito/vault/vault_providers.dart';
import 'package:wambito/vault/vault_screen.dart';

import 'fakes.dart';

Future<void> _enterEmail(WidgetTester tester, String email) async {
  await tester.enterText(find.byKey(const Key('entry.email')), email);
  await tester.tap(find.text('ENVIAR CÓDIGO'));
  await tester.pumpAndSettle();
}

Future<void> _enterCode(WidgetTester tester, String code, {String submit = 'Entrar'}) async {
  await tester.enterText(find.byKey(const Key('entry.code')), code);
  await tester.pump();
  await tester.tap(find.widgetWithText(PressButton, submit.toUpperCase()));
  await tester.pumpAndSettle();
}

StoredSession? _stored(ProviderContainer container) => container.read(sessionProvider).stored;

/// The calls of the sign-in itself, without the profile reads that follow it (whether the account is
/// a guest, and whether it has the welcome to do) and the welcome's mark.
Iterable<String> _signInCalls(FakeAuthApi auth) =>
    auth.calls.where((c) => !c.startsWith('isGuest') && !c.startsWith('completeOnboarding'));

void main() {
  late FakeAuthApi auth;
  setUp(() {
    auth = FakeAuthApi();
    mockStorage();
  });

  /// The passkey button lives on the email step, not on the first screen.
  Future<ProviderContainer> pumpEmailStep(WidgetTester tester, FakePasskeys passkeys) async {
    final container = await pumpApp(tester, auth: auth, passkeys: passkeys);
    container.read(routerProvider).go('/entry/email');
    await tester.pumpAndSettle();
    // Opening the step asks the phone what it has already; the tests look at what the tap does.
    auth.calls.clear();
    passkeys.calls.clear();
    return container;
  }

  group('first run', () {
    String location(ProviderContainer container) =>
        container.read(routerProvider).routerDelegate.currentConfiguration.last.matchedLocation;

    bool enabled(WidgetTester tester, String key) =>
        tester.widget<PressButton>(find.byKey(Key(key))).onPressed != null;

    testWidgets('the welcome shows Wambi, Start and I already have an account, and nothing else to '
        'fill', (tester) async {
      await pumpApp(tester, auth: auth, passkeys: FakePasskeys(isSupported: false));

      expect(find.byType(WambiFace), findsOneWidget);
      expect(find.byKey(const Key('entry.start')), findsOneWidget);
      expect(find.text('EMPEZAR'), findsOneWidget);
      expect(find.byKey(const Key('entry.haveAccount')), findsOneWidget);
      expect(find.text('YA TENGO UNA CUENTA'), findsOneWidget);
      // "Start" is the primary; "I already have an account" is a link.
      expect(
        tester.widget<PressButton>(find.byKey(const Key('entry.start'))).tone,
        PressTone.primary,
      );
      expect(tester.widget<PressButton>(find.byKey(const Key('entry.haveAccount'))).link, isTrue);
      expect(
        tester.getTopLeft(find.byKey(const Key('entry.start'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('entry.haveAccount'))).dy),
      );
      // Nothing to fill, nothing else to choose.
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('PROBAR SIN CORREO'), findsNothing);
      expect(find.text('ENTRAR CON MI CORREO'), findsNothing);
      expect(find.text('ENTRAR CON HUELLA'), findsNothing);
    });

    testWidgets('with a passkey provider on the phone, still only Start and the link', (
      tester,
    ) async {
      await pumpApp(tester, auth: auth, passkeys: FakePasskeys(isSupported: true));

      expect(find.text('EMPEZAR'), findsOneWidget);
      expect(find.text('YA TENGO UNA CUENTA'), findsOneWidget);
      expect(find.text('ENTRAR CON HUELLA'), findsNothing);
    });

    testWidgets('in English, the same welcome', (tester) async {
      await pumpApp(
        tester,
        auth: auth,
        passkeys: FakePasskeys(isSupported: true),
        locale: const Locale('en'),
      );

      expect(find.text('START'), findsOneWidget);
      expect(find.text('I ALREADY HAVE AN ACCOUNT'), findsOneWidget);
      expect(find.text('SIGN IN WITH FINGERPRINT'), findsNothing);
    });

    testWidgets('the first screen has no fingerprint button, even with passkeys', (tester) async {
      final container = await pumpApp(tester, auth: auth, passkeys: FakePasskeys());

      expect(find.byKey(const Key('entry.passkey')), findsNothing);
      expect(find.byType(FingerprintIcon), findsNothing);

      container.read(routerProvider).go('/entry/email');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('entry.passkey')), findsOneWidget);
    });

    testWidgets('Start signs in anonymously once and lands home', (tester) async {
      final container = await pumpApp(tester, auth: auth);

      await tester.tap(find.byKey(const Key('entry.start')));
      await tester.pumpAndSettle();

      expect(auth.signInAsGuestCalls, 1);
      expect(auth.calls, ['signInAsGuest']);
      expect(location(container), '/');
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(_stored(container)?.guest, isTrue);
      expect((await SessionStore().read())?.token, 'guest-token-1');
    });

    testWidgets('I already have an account opens the email screen', (tester) async {
      final container = await pumpApp(tester, auth: auth);

      await tester.tap(find.byKey(const Key('entry.haveAccount')));
      await tester.pumpAndSettle();

      expect(location(container), '/entry/email');
      expect(find.text('Entra a Wambito'), findsOneWidget);
      // No anonymous user is made on the way.
      expect(auth.signInAsGuestCalls, 0);
    });

    testWidgets('with GUEST_SIGNUP closed, Start shows the server\'s refusal and the buttons work '
        'again', (tester) async {
      final container = await pumpApp(tester, auth: auth);
      auth.failures['signInAsGuest'] = const AuthFailure(
        code: 'guest_signup_disabled',
        status: 403,
      );

      await tester.tap(find.byKey(const Key('entry.start')));
      await tester.pumpAndSettle();

      expect(find.text('Por ahora no se pueden crear cuentas de invitado.'), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(enabled(tester, 'entry.start'), isTrue);
      expect(enabled(tester, 'entry.haveAccount'), isTrue);
      expect(find.text('EMPEZAR'), findsOneWidget);

      await tester.tap(find.byKey(const Key('entry.haveAccount')));
      await tester.pumpAndSettle();
      expect(location(container), '/entry/email');
    });

    testWidgets('Start on a server that makes plain users keeps today\'s guest: no vault, '
        '/progress reachable', (tester) async {
      // pumpApp's account is `plainAccount()`: what `GET /v1/me` says for a plain user.
      final container = await pumpApp(tester, auth: auth);

      await tester.tap(find.byKey(const Key('entry.start')));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(container.read(vaultGateProvider), isNull);
      expect(find.byType(VaultScreen), findsNothing);

      container.read(routerProvider).go('/progress');
      await tester.pumpAndSettle();
      expect(location(container), '/progress');
      expect(find.byType(ProgressScreen), findsOneWidget);
    });
  });

  group('email', () {
    testWidgets('the email code signs in', (tester) async {
      final container = await pumpApp(tester, auth: auth);

      await tester.tap(find.byKey(const Key('entry.haveAccount')));
      await tester.pumpAndSettle();
      await _enterEmail(tester, ' Ana@Correo.com ');

      expect(auth.calls, ['sendCode ana@correo.com']);
      expect(find.text('Revisa tu correo'), findsOneWidget);

      await _enterCode(tester, '123456');

      expect(_signInCalls(auth).last, 'verifyCode ana@correo.com 123456');
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(_stored(container)?.guest, isFalse);
      expect((await SessionStore().read())?.token, 'email-token-1');
    });

    testWidgets('a code pasted whole, with spaces, dashes or words around it, is the code', (
      tester,
    ) async {
      await pumpApp(tester, auth: auth);
      await tester.tap(find.byKey(const Key('entry.haveAccount')));
      await tester.pumpAndSettle();
      await _enterEmail(tester, 'ana@correo.com');

      final field = find.byKey(const Key('entry.code'));
      String shown() => tester.widget<EditableText>(field).controller.text;
      for (final pasted in [
        '123456',
        '123 456',
        '123-456',
        ' 123\u00A0456\n',
        'Tu código: 123456',
      ]) {
        await tester.enterText(field, pasted);
        await tester.pump();
        expect(shown(), '123456', reason: 'pasted "$pasted"');
      }

      await tester.pump();
      await tester.tap(find.widgetWithText(PressButton, 'ENTRAR'));
      await tester.pumpAndSettle();
      expect(_signInCalls(auth).last, 'verifyCode ana@correo.com 123456');
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets(
      'a whole code pasted over digits already typed replaces them; typing stops at six',
      (tester) async {
        await pumpApp(tester, auth: auth);
        await tester.tap(find.byKey(const Key('entry.haveAccount')));
        await tester.pumpAndSettle();
        await _enterEmail(tester, 'ana@correo.com');

        final field = find.byKey(const Key('entry.code'));
        String shown() => tester.widget<EditableText>(field).controller.text;
        await tester.enterText(field, '12');
        await tester.pump();
        expect(shown(), '12');
        // The result of pasting "654 321" at the end of "12" (and in the middle of it).
        await tester.enterText(field, '12654 321');
        await tester.pump();
        expect(shown(), '654321');
        await tester.enterText(field, '1');
        await tester.enterText(field, '1654-3212');
        await tester.pump();
        expect(shown(), '654321');
        // Typed one digit at a time, the seventh is not taken.
        await tester.enterText(field, '12345');
        await tester.enterText(field, '123456');
        await tester.enterText(field, '1234567');
        await tester.pump();
        expect(shown(), '123456');
      },
    );

    testWidgets('a not-allowlisted email shows "Wambito todavía no está abierto al público…"', (
      tester,
    ) async {
      await pumpApp(tester, auth: auth);
      auth.failures['sendCode'] = const AuthFailure(code: 'sign_in_not_allowed', status: 403);

      await tester.tap(find.byKey(const Key('entry.haveAccount')));
      await tester.pumpAndSettle();
      await _enterEmail(tester, 'nadie@correo.com');

      expect(
        find.text(
          'Wambito todavía no está abierto al público. Si quieres probarlo, escríbele a quien te '
          'invitó.',
        ),
        findsOneWidget,
      );
      expect(find.text('Revisa tu correo'), findsNothing);
    });

    testWidgets('a suspended account says so when the code is entered', (tester) async {
      await pumpApp(tester, auth: auth);
      await tester.tap(find.byKey(const Key('entry.haveAccount')));
      await tester.pumpAndSettle();
      await _enterEmail(tester, 'ana@correo.com');
      auth.failures['verifyCode'] = const AuthFailure(code: 'account_suspended', status: 403);

      await _enterCode(tester, '123456');

      expect(
        find.text('Tu cuenta está suspendida. Escríbenos a privacy@wambito.com.'),
        findsOneWidget,
      );
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('a mistyped email is caught before asking the server', (tester) async {
      await pumpApp(tester, auth: auth);

      await tester.tap(find.byKey(const Key('entry.haveAccount')));
      await tester.pumpAndSettle();
      await _enterEmail(tester, 'ana@correo');

      expect(find.text('Escribe un correo válido, como ana@correo.com.'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('a wrong code says so and keeps the person on the code', (tester) async {
      await pumpApp(tester, auth: auth);
      await tester.tap(find.byKey(const Key('entry.haveAccount')));
      await tester.pumpAndSettle();
      await _enterEmail(tester, 'ana@correo.com');
      auth.failures['verifyCode'] = const AuthFailure(code: 'INVALID_OTP', status: 400);

      await _enterCode(tester, '000000');

      expect(
        find.text('Ese código no es correcto. Revísalo e inténtalo otra vez.'),
        findsOneWidget,
      );
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('no connection says so', (tester) async {
      await pumpApp(tester, auth: auth);
      auth.failures['sendCode'] = const AuthFailure(status: 0);

      await tester.tap(find.byKey(const Key('entry.haveAccount')));
      await tester.pumpAndSettle();
      await _enterEmail(tester, 'ana@correo.com');

      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
    });
  });

  group('magic link', () {
    testWidgets('opening the magic link in the app signs in', (tester) async {
      final container = await pumpApp(tester, auth: auth);

      container.read(routerProvider).go('/auth/verify?email=ana%40correo.com&code=654321&lang=es');
      await tester.pumpAndSettle();

      expect(_signInCalls(auth), ['verifyCode ana@correo.com 654321']);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(_stored(container)?.guest, isFalse);
    });

    testWidgets('a used link says so and offers a new code for that email', (tester) async {
      final container = await pumpApp(tester, auth: auth);
      auth.failures['verifyCode'] = const AuthFailure(code: 'INVALID_OTP', status: 400);

      container.read(routerProvider).go('/auth/verify?email=ana%40correo.com&code=654321');
      await tester.pumpAndSettle();

      expect(find.text('No pudimos hacerte entrar'), findsOneWidget);
      expect(
        find.text('Este código ya no sirve: venció o ya se usó. Pide uno nuevo.'),
        findsOneWidget,
      );
      await tester.tap(find.text('ENVIAR UN CÓDIGO NUEVO'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byKey(const Key('entry.email'))).controller.text,
        'ana@correo.com',
      );
    });
  });

  group('a suspended account', () {
    testWidgets('the magic link says the account is suspended', (tester) async {
      final container = await pumpApp(tester, auth: auth);
      auth.failures['verifyCode'] = const AuthFailure(code: 'account_suspended', status: 403);

      container.read(routerProvider).go('/auth/verify?email=ana%40correo.com&code=654321');
      await tester.pumpAndSettle();

      expect(
        find.text('Tu cuenta está suspendida. Escríbenos a privacy@wambito.com.'),
        findsOneWidget,
      );
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('the passkey says the account is suspended, not that the passkey failed', (
      tester,
    ) async {
      await pumpEmailStep(tester, FakePasskeys());
      auth.failures['passkeySignIn'] = const AuthFailure(code: 'account_suspended', status: 403);

      await tester.tap(find.byKey(const Key('entry.passkey')));
      await tester.pumpAndSettle();

      expect(
        find.text('Tu cuenta está suspendida. Escríbenos a privacy@wambito.com.'),
        findsOneWidget,
      );
      expect(find.byType(HomeScreen), findsNothing);
    });
  });

  group('a guest choosing to enter with an email', () {
    setUp(() {
      mockStorage(token: 'guest-token-0', guest: true);
      auth.guests['guest-token-0'] = true;
    });

    Future<ProviderContainer> openEmail(WidgetTester tester) async {
      final container = await pumpApp(tester, auth: auth);
      auth.calls.clear();
      container.read(routerProvider).go('/entry/email');
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('is offered to save their progress, and claims the email in place', (tester) async {
      final container = await openEmail(tester);

      await _enterEmail(tester, 'ana@correo.com');

      // Nothing is sent before the person decides.
      expect(auth.calls.where((c) => c.startsWith('sendCode')), isEmpty);
      expect(find.text('¿Guardamos lo que ya anotaste?'), findsOneWidget);

      await tester.tap(find.text('GUARDAR MI PROGRESO'));
      await tester.pumpAndSettle();
      expect(auth.calls, ['claimSend guest-token-0 ana@correo.com']);
      expect(find.text('Revisa tu correo'), findsOneWidget);

      await _enterCode(tester, '111222', submit: 'Guardar');

      expect(_signInCalls(auth).last, 'claimVerify guest-token-0 ana@correo.com 111222');
      // The guest's start was its welcome: the claimed account is marked as having done it.
      expect(auth.calls.last, 'completeOnboarding guest-token-0');
      // The same user, the same token: no second account, nothing left behind.
      expect(
        auth.calls.where((c) => c.startsWith('sendCode') || c.startsWith('verifyCode')),
        isEmpty,
      );
      expect(_stored(container)?.token, 'guest-token-0');
      expect(_stored(container)?.guest, isFalse);
      expect((await SessionStore().read())?.guest, isFalse);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('is warned before signing in as another account, and nothing happens on cancel', (
      tester,
    ) async {
      final container = await openEmail(tester);
      await _enterEmail(tester, 'ana@correo.com');

      await tester.tap(find.text('ENTRAR CON OTRA CUENTA'));
      await tester.pumpAndSettle();
      expect(find.text('¿Dejar tu cuenta de invitado?'), findsOneWidget);
      expect(
        find.textContaining('lo que anotaste como invitado se queda en esa cuenta'),
        findsOneWidget,
      );

      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();
      expect(auth.calls, isEmpty);
      expect(_stored(container)?.token, 'guest-token-0');
    });

    testWidgets('who confirms the warning signs in with the email', (tester) async {
      final container = await openEmail(tester);
      await _enterEmail(tester, 'ana@correo.com');
      await tester.tap(find.text('ENTRAR CON OTRA CUENTA'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ENTRAR DE TODOS MODOS'));
      await tester.pumpAndSettle();
      expect(auth.calls, ['sendCode ana@correo.com']);

      await _enterCode(tester, '123456');
      expect(_stored(container)?.token, 'email-token-1');
      expect(_stored(container)?.guest, isFalse);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('who goes back to change the email is asked again', (tester) async {
      await openEmail(tester);
      await _enterEmail(tester, 'ana@correo.com');
      await tester.tap(find.text('ENTRAR CON OTRA CUENTA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ENTRAR DE TODOS MODOS'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('USAR OTRO CORREO'));
      await tester.pumpAndSettle();
      await _enterEmail(tester, 'luis@correo.com');

      expect(find.text('¿Guardamos lo que ya anotaste?'), findsOneWidget);
      expect(auth.calls, ['sendCode ana@correo.com']);
    });

    testWidgets('gets email_taken: told to sign in with it, and the guest stays', (tester) async {
      final container = await openEmail(tester);
      auth.failures['claimSend'] = const AuthFailure(code: 'email_taken', status: 409);
      await _enterEmail(tester, 'ana@correo.com');

      await tester.tap(find.text('GUARDAR MI PROGRESO'));
      await tester.pumpAndSettle();

      expect(find.text('Ese correo ya tiene una cuenta. Entra con él.'), findsOneWidget);
      expect(_stored(container)?.token, 'guest-token-0');
      expect(_stored(container)?.guest, isTrue);
    });

    testWidgets('opening a magic link is warned before replacing the guest', (tester) async {
      final container = await pumpApp(tester, auth: auth);
      auth.calls.clear();

      container.read(routerProvider).go('/auth/verify?email=ana%40correo.com&code=654321');
      await tester.pumpAndSettle();

      expect(auth.calls, isEmpty);
      expect(find.text('¿Dejar tu cuenta de invitado?'), findsOneWidget);

      await tester.tap(find.text('ENTRAR DE TODOS MODOS'));
      await tester.pumpAndSettle();
      expect(_signInCalls(auth), ['verifyCode ana@correo.com 654321']);
      expect(_stored(container)?.guest, isFalse);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  group('passkey', () {
    testWidgets('Entrar con huella signs in with the passkey', (tester) async {
      final passkeys = FakePasskeys();
      final container = await pumpEmailStep(tester, passkeys);

      await tester.tap(find.byKey(const Key('entry.passkey')));
      await tester.pumpAndSettle();

      expect(passkeys.calls, ['get {"challenge":"sign-in"}']);
      expect(auth.calls.take(3), [
        'passkeySignInOptions',
        'passkeySignIn {"assertion":true}',
        'isGuest passkey-token-1',
      ]);
      expect(_stored(container)?.token, 'passkey-token-1');
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('closing the phone prompt says nothing; a failure suggests the email', (
      tester,
    ) async {
      final passkeys = FakePasskeys();
      await pumpEmailStep(tester, passkeys);

      passkeys.failure = const AuthFailure(code: 'AUTH_CANCELLED', status: 400);
      await tester.tap(find.byKey(const Key('entry.passkey')));
      await tester.pumpAndSettle();
      expect(find.textContaining('huella. Inténtalo'), findsNothing);

      passkeys.failure = const AuthFailure(code: 'NO_CREDENTIAL', status: 400);
      await tester.tap(find.byKey(const Key('entry.passkey')));
      await tester.pumpAndSettle();
      expect(
        find.text('No pudimos hacerte entrar con tu huella. Inténtalo otra vez o usa tu correo.'),
        findsOneWidget,
      );
      expect(find.byType(HomeScreen), findsNothing);
    });
  });

  group('passkey on the email screen', () {
    const getAvailable = 'getAvailable {"challenge":"sign-in"}';

    Future<ProviderContainer> openEmail(
      WidgetTester tester,
      FakePasskeys passkeys, {
      Locale locale = const Locale('es'),
    }) async {
      final container = await pumpApp(tester, auth: auth, passkeys: passkeys, locale: locale);
      auth.calls.clear();
      passkeys.calls.clear();
      container.read(routerProvider).go('/entry/email');
      await tester.pumpAndSettle();
      return container;
    }

    bool emailFocused(WidgetTester tester) =>
        tester.widget<EditableText>(find.byKey(const Key('entry.email'))).focusNode.hasFocus;

    testWidgets('a passkey the phone already has (made on the web) is offered on opening, and '
        'signing in with it completes', (tester) async {
      final passkeys = FakePasskeys(hasPasskey: true);
      final container = await openEmail(tester, passkeys);

      // Only the credentials available at once are asked for, with no click.
      expect(passkeys.calls, [getAvailable]);
      expect(auth.calls, [
        'passkeySignInOptions',
        'passkeySignIn {"assertion":true}',
        startsWith('isGuest'),
      ]);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(_stored(container)?.token, 'passkey-token-1');
      expect(_stored(container)?.guest, isFalse);
      expect((await SessionStore().read())?.token, 'passkey-token-1');
    });

    testWidgets('with no passkey on the phone nothing shows, and the email field is ready', (
      tester,
    ) async {
      final passkeys = FakePasskeys();
      await openEmail(tester, passkeys);

      expect(passkeys.calls, [getAvailable]);
      expect(auth.calls, ['passkeySignInOptions']);
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.textContaining('Inténtalo'), findsNothing);
      expect(find.text('Entra a Wambito'), findsOneWidget);
      expect(emailFocused(tester), isTrue);

      // And the email still works.
      await _enterEmail(tester, 'ana@correo.com');
      expect(auth.calls.last, 'sendCode ana@correo.com');
      expect(find.text('Revisa tu correo'), findsOneWidget);
    });

    testWidgets('closing the phone\'s sheet says nothing and leaves the email field focused', (
      tester,
    ) async {
      final passkeys = FakePasskeys(hasPasskey: true);
      final container = await pumpApp(tester, auth: auth, passkeys: passkeys);
      passkeys.failure = const AuthFailure(code: 'AUTH_CANCELLED', status: 400);
      container.read(routerProvider).go('/entry/email');
      await tester.pumpAndSettle();

      expect(passkeys.calls.where((c) => c.startsWith('getAvailable')), hasLength(1));
      expect(find.textContaining('Inténtalo'), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);
      expect(emailFocused(tester), isTrue);
    });

    testWidgets('a sheet that fails to open is as silent as no passkey', (tester) async {
      final passkeys = FakePasskeys(hasPasskey: true);
      final container = await pumpApp(tester, auth: auth, passkeys: passkeys);
      passkeys.failure = const AuthFailure(code: 'PASSKEY_FAILED', status: 400);
      container.read(routerProvider).go('/entry/email');
      await tester.pumpAndSettle();

      expect(find.textContaining('Inténtalo'), findsNothing);
      expect(emailFocused(tester), isTrue);
    });

    testWidgets('a passkey the server does not accept says so, and the email still works', (
      tester,
    ) async {
      final passkeys = FakePasskeys(hasPasskey: true);
      final container = await pumpApp(tester, auth: auth, passkeys: passkeys);
      auth.failures['passkeySignIn'] = const AuthFailure(code: 'PASSKEY_NOT_FOUND', status: 401);
      container.read(routerProvider).go('/entry/email');
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos hacerte entrar con tu huella. Inténtalo otra vez o usa tu correo.'),
        findsOneWidget,
      );
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.byKey(const Key('entry.send')), findsOneWidget);
    });

    testWidgets('a phone without passkeys is not asked, and has no button', (tester) async {
      final passkeys = FakePasskeys(isSupported: false, hasPasskey: true);
      await openEmail(tester, passkeys);

      expect(passkeys.calls, isEmpty);
      expect(auth.calls, isEmpty);
      expect(find.byKey(const Key('entry.passkey')), findsNothing);
      expect(find.text('USAR PASSKEY'), findsNothing);
      expect(emailFocused(tester), isTrue);
    });

    testWidgets('"Usar passkey" is visible when the phone supports passkeys, and signs in', (
      tester,
    ) async {
      final passkeys = FakePasskeys();
      final container = await openEmail(tester, passkeys);

      expect(find.widgetWithText(PressButton, 'USAR PASSKEY'), findsOneWidget);
      passkeys.calls.clear();
      auth.calls.clear();
      await tester.tap(find.text('USAR PASSKEY'));
      await tester.pumpAndSettle();

      // The button may show the provider's picker (a passkey made anywhere), not only what is at hand.
      expect(passkeys.calls, ['get {"challenge":"sign-in"}']);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(_stored(container)?.token, 'passkey-token-1');
    });

    testWidgets('"Use a passkey", in English', (tester) async {
      await openEmail(tester, FakePasskeys(), locale: const Locale('en'));
      expect(find.widgetWithText(PressButton, 'USE A PASSKEY'), findsOneWidget);
    });

    testWidgets('closing the sheet of the button says nothing; a failure suggests the code', (
      tester,
    ) async {
      final passkeys = FakePasskeys();
      await openEmail(tester, passkeys);

      passkeys.failure = const AuthFailure(code: 'AUTH_CANCELLED', status: 400);
      await tester.tap(find.text('USAR PASSKEY'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Inténtalo'), findsNothing);
      expect(emailFocused(tester), isTrue);

      passkeys.failure = const AuthFailure(code: 'PASSKEY_FAILED', status: 400);
      await tester.tap(find.text('USAR PASSKEY'));
      await tester.pumpAndSettle();
      expect(
        find.text('No pudimos hacerte entrar con tu huella. Inténtalo otra vez o usa tu correo.'),
        findsOneWidget,
      );
    });

    group('for a guest', () {
      setUp(() {
        mockStorage(token: 'guest-token-0', guest: true);
        auth.guests['guest-token-0'] = true;
      });

      testWidgets('nothing is asked on opening: a passkey would replace the guest unasked', (
        tester,
      ) async {
        final passkeys = FakePasskeys(hasPasskey: true);
        final container = await openEmail(tester, passkeys);

        expect(passkeys.calls, isEmpty);
        expect(auth.calls, isEmpty);
        expect(_stored(container)?.token, 'guest-token-0');
        expect(find.text('USAR PASSKEY'), findsOneWidget);
      });

      testWidgets('the button warns first; cancelling keeps the guest and asks nothing', (
        tester,
      ) async {
        final passkeys = FakePasskeys(hasPasskey: true);
        final container = await openEmail(tester, passkeys);

        await tester.tap(find.text('USAR PASSKEY'));
        await tester.pumpAndSettle();
        expect(find.text('¿Dejar tu cuenta de invitado?'), findsOneWidget);
        await tester.tap(find.text('CANCELAR'));
        await tester.pumpAndSettle();

        expect(passkeys.calls, isEmpty);
        expect(auth.calls, isEmpty);
        expect(_stored(container)?.token, 'guest-token-0');
        expect((await SessionStore().read())?.token, 'guest-token-0');
      });

      testWidgets('the warning offers to save their progress instead, with the email field ready', (
        tester,
      ) async {
        final passkeys = FakePasskeys(hasPasskey: true);
        final container = await openEmail(tester, passkeys);

        await tester.tap(find.text('USAR PASSKEY'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('guest.save')));
        await tester.pumpAndSettle();

        expect(passkeys.calls, isEmpty);
        expect(emailFocused(tester), isTrue);
        expect(_stored(container)?.token, 'guest-token-0');
        // The email that follows is offered the claim, as ever.
        await _enterEmail(tester, 'ana@correo.com');
        expect(find.text('¿Guardamos lo que ya anotaste?'), findsOneWidget);
      });

      testWidgets('who confirms the warning signs in with the passkey', (tester) async {
        final passkeys = FakePasskeys();
        final container = await openEmail(tester, passkeys);

        await tester.tap(find.text('USAR PASSKEY'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('guest.leaveConfirm')));
        await tester.pumpAndSettle();

        expect(passkeys.calls, ['get {"challenge":"sign-in"}']);
        expect(_stored(container)?.token, 'passkey-token-1');
        expect(find.byType(HomeScreen), findsOneWidget);
      });
    });

    testWidgets('saving a guest\'s progress (the claim) does not ask for a passkey', (
      tester,
    ) async {
      mockStorage(token: 'guest-token-0', guest: true);
      auth.guests['guest-token-0'] = true;
      final passkeys = FakePasskeys(hasPasskey: true);
      final container = await pumpApp(tester, auth: auth, passkeys: passkeys);
      passkeys.calls.clear();
      container.read(routerProvider).go('/entry/email?email=ana%40correo.com&claim=1');
      await tester.pumpAndSettle();

      expect(passkeys.calls, isEmpty);
      expect(auth.calls.where((c) => c.startsWith('claimSend')), hasLength(1));
    });
  });

  group('errors that are not an AuthFailure', () {
    const network = 'Sin conexión. Revisa tu internet e inténtalo de nuevo.';
    const generic = 'Algo salió mal. Inténtalo de nuevo en un momento.';

    bool enabled(WidgetTester tester, Finder button) =>
        tester.widget<PressButton>(button).onPressed != null;

    testWidgets('a timeout on Start says no connection and the button works again', (tester) async {
      await pumpApp(tester, auth: auth);
      auth.failures['signInAsGuest'] = TimeoutException('slow network');

      await tester.tap(find.text('EMPEZAR'));
      await tester.pumpAndSettle();

      expect(find.text(network), findsOneWidget);
      expect(enabled(tester, find.byKey(const Key('entry.start'))), isTrue);
      expect(find.text('EMPEZAR'), findsOneWidget);

      await tester.tap(find.text('EMPEZAR'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('a network failure sending the code says so and the screen stays usable', (
      tester,
    ) async {
      await pumpApp(tester, auth: auth);
      await tester.tap(find.byKey(const Key('entry.haveAccount')));
      await tester.pumpAndSettle();
      auth.failures['sendCode'] = const SocketException('Network is unreachable');

      await _enterEmail(tester, 'ana@correo.com');

      expect(find.text(network), findsOneWidget);
      expect(find.text('Enviando…'), findsNothing);
      expect(enabled(tester, find.byKey(const Key('entry.send'))), isTrue);

      await _enterEmail(tester, 'ana@correo.com');
      expect(find.text('Revisa tu correo'), findsOneWidget);
    });

    testWidgets('anything else while checking the code says something went wrong, and the '
        'button stops saying Entrando…', (tester) async {
      await pumpApp(tester, auth: auth);
      await tester.tap(find.byKey(const Key('entry.haveAccount')));
      await tester.pumpAndSettle();
      await _enterEmail(tester, 'ana@correo.com');
      auth.failures['verifyCode'] = StateError('storage write failed');

      await _enterCode(tester, '123456');

      expect(find.text(generic), findsOneWidget);
      expect(find.text('Entrando…'), findsNothing);
      expect(enabled(tester, find.byKey(const Key('entry.submitCode'))), isTrue);
    });

    testWidgets('a timeout on a magic link stops the spinner and offers to try again', (
      tester,
    ) async {
      final container = await pumpApp(tester, auth: auth);
      auth.failures['verifyCode'] = TimeoutException('slow network');

      container.read(routerProvider).go('/auth/verify?email=ana%40correo.com&code=654321');
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No pudimos hacerte entrar'), findsOneWidget);
      expect(find.text(network), findsOneWidget);
      await tester.tap(find.text('REINTENTAR'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('a broken answer from the passkey prompt suggests the email', (tester) async {
      final passkeys = FakePasskeys();
      await pumpEmailStep(tester, passkeys);
      passkeys.failure = const FormatException('not JSON');

      await tester.tap(find.byKey(const Key('entry.passkey')));
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos hacerte entrar con tu huella. Inténtalo otra vez o usa tu correo.'),
        findsOneWidget,
      );
      expect(enabled(tester, find.byKey(const Key('entry.passkey'))), isTrue);
    });

    testWidgets('in English, the same message in English', (tester) async {
      await pumpApp(tester, auth: auth, locale: const Locale('en'));
      auth.failures['signInAsGuest'] = TimeoutException('slow network');

      await tester.tap(find.text('START'));
      await tester.pumpAndSettle();

      expect(find.text('No connection. Check your internet and try again.'), findsOneWidget);
    });
  });

  testWidgets('a returning person goes straight home', (tester) async {
    mockStorage(token: 'email-token-9');
    await pumpApp(tester, auth: auth);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('EMPEZAR'), findsNothing);
  });

  testWidgets('a session the server no longer knows goes back to the first screen', (tester) async {
    mockStorage(token: 'email-token-9');
    auth.failures['isGuest'] = const AuthFailure(code: 'unauthenticated', status: 401);
    await pumpApp(tester, auth: auth);

    expect(find.text('EMPEZAR'), findsOneWidget);
    expect(await SessionStore().read(), isNull);
  });
}
