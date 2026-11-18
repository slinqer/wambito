import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/entry/code_input.dart';
import 'package:wambito/home/home_controller.dart' show clockProvider;
import 'package:wambito/progress/progress_screen.dart';
import 'package:wambito/router.dart';
import 'package:wambito/ui/press_button.dart';

import 'fakes.dart';

/// What the entry screens do as the web's sign-in screens look: the code waits for six digits, back
/// leaves a step, the passkey's own problems sit under its button, the day/night switch works, and
/// nothing overflows at a big font on a small phone. How they look is test/parity's job.
void main() {
  late FakeAuthApi auth;
  setUp(() {
    auth = FakeAuthApi();
    mockStorage();
  });

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<PressButton>(button).onPressed != null;

  Future<void> openEmail(
    WidgetTester tester, {
    FakePasskeys? passkeys,
    Locale locale = const Locale('es'),
  }) async {
    final container = await pumpApp(tester, auth: auth, passkeys: passkeys, locale: locale);
    container.read(routerProvider).go('/entry/email');
    await tester.pumpAndSettle();
  }

  Future<void> toCodeStep(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('entry.email')), 'ana@correo.com');
    await tester.tap(find.byKey(const Key('entry.send')));
    await tester.pumpAndSettle();
  }

  group('the code step', () {
    testWidgets('"Entrar" waits for the whole code', (tester) async {
      await openEmail(tester);
      await toCodeStep(tester);
      final submit = find.byKey(const Key('entry.submitCode'));
      final field = find.byKey(const Key('entry.code'));

      expect(enabled(tester, submit), isFalse);
      await tester.enterText(field, '12345');
      await tester.pump();
      expect(enabled(tester, submit), isFalse);
      await tester.enterText(field, '123456');
      await tester.pump();
      expect(enabled(tester, submit), isTrue);
      // And empties again when a digit goes.
      await tester.enterText(field, '12345');
      await tester.pump();
      expect(enabled(tester, submit), isFalse);
    });

    testWidgets('the keyboard\'s "done" sends a whole code, and nothing short of one', (
      tester,
    ) async {
      await openEmail(tester);
      await toCodeStep(tester);
      final field = find.byKey(const Key('entry.code'));

      await tester.enterText(field, '123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(auth.calls.where((c) => c.startsWith('verifyCode')), isEmpty);

      await tester.enterText(field, '123456');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        auth.calls.where((c) => !c.startsWith('isGuest')).last,
        'verifyCode ana@correo.com 123456',
      );
    });

    testWidgets('the boxes are the code field: six of them, and the email in bold in the lead', (
      tester,
    ) async {
      await openEmail(tester);
      await toCodeStep(tester);

      expect(find.byType(CodeInput), findsOneWidget);
      expect(find.byType(EditableText), findsOneWidget);
      // The address is its own run, in the page's ink, as the web's <strong>.
      final lead = tester.widget<RichText>(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().startsWith('Te mandamos un código'),
        ),
      );
      final strong = <String>[];
      lead.text.visitChildren((span) {
        if (span is TextSpan && span.style?.fontWeight == FontWeight.w900) strong.add(span.text!);
        return true;
      });
      expect(strong, ['ana@correo.com']);
    });

    testWidgets('back goes from the code to the email, as "Usar otro correo" does, then leaves', (
      tester,
    ) async {
      await pumpApp(tester, auth: auth);
      await tester.tap(find.byKey(const Key('entry.withEmail')));
      await tester.pumpAndSettle();
      await toCodeStep(tester);
      expect(find.text('Revisa tu correo'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Entra a Wambito'), findsOneWidget);
      expect(find.text('Revisa tu correo'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // The first screen, with "Probar sin correo" where it always was.
      expect(find.byKey(const Key('entry.guest')), findsOneWidget);
    });
  });

  group('"Reenviar código" waits 30 s after a code was sent, as the web\'s does', () {
    var now = DateTime.utc(2026, 10, 21, 15);

    /// The phone's clock, moved by [seconds] a second at a time, as the page's timer sees it.
    Future<void> wait(WidgetTester tester, int seconds) async {
      for (var i = 0; i < seconds; i++) {
        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
    }

    Future<void> openCode(WidgetTester tester) async {
      now = DateTime.utc(2026, 10, 21, 15);
      final container = await pumpApp(
        tester,
        auth: auth,
        overrides: [clockProvider.overrideWithValue(() => now)],
      );
      container.read(routerProvider).go('/entry/email');
      await tester.pumpAndSettle();
      await toCodeStep(tester);
    }

    testWidgets('it is locked with the seconds left, counting down', (tester) async {
      await openCode(tester);
      expect(find.text('REENVIAR EN 30 S'), findsOneWidget);
      expect(enabled(tester, find.widgetWithText(PressButton, 'REENVIAR EN 30 S')), isFalse);

      await wait(tester, 1);
      expect(find.text('REENVIAR EN 29 S'), findsOneWidget);
      await wait(tester, 28);
      expect(find.text('REENVIAR EN 1 S'), findsOneWidget);
    });

    testWidgets('after 30 s it unlocks, sends again, and waits again', (tester) async {
      await openCode(tester);
      await wait(tester, 30);
      final resend = find.widgetWithText(PressButton, 'REENVIAR CÓDIGO');
      expect(enabled(tester, resend), isTrue);

      auth.calls.clear();
      await tester.tap(resend);
      await tester.pumpAndSettle();

      expect(auth.calls, ['sendCode ana@correo.com']);
      expect(find.text('Te mandamos un código nuevo.'), findsOneWidget);
      expect(find.text('REENVIAR EN 30 S'), findsOneWidget);
    });

    testWidgets('going back to the email and sending again starts a new wait', (tester) async {
      await openCode(tester);
      await wait(tester, 30);
      await tester.tap(find.text('USAR OTRO CORREO'));
      await tester.pumpAndSettle();
      await toCodeStep(tester);
      expect(find.text('REENVIAR EN 30 S'), findsOneWidget);
    });

    testWidgets('in English', (tester) async {
      now = DateTime.utc(2026, 10, 21, 15);
      final container = await pumpApp(
        tester,
        auth: auth,
        locale: const Locale('en'),
        overrides: [clockProvider.overrideWithValue(() => now)],
      );
      container.read(routerProvider).go('/entry/email');
      await tester.pumpAndSettle();
      await toCodeStep(tester);

      expect(find.text('RESEND IN 30 S'), findsOneWidget);
      await wait(tester, 30);
      expect(find.text('RESEND CODE'), findsOneWidget);
    });

    testWidgets('a guest saving their progress waits too', (tester) async {
      mockStorage(token: 'guest-token-0', guest: true);
      auth.guests['guest-token-0'] = true;
      now = DateTime.utc(2026, 10, 21, 15);
      final container = await pumpApp(
        tester,
        auth: auth,
        overrides: [clockProvider.overrideWithValue(() => now)],
      );
      container.read(routerProvider).go('/entry/email?email=ana%40correo.com&claim=1');
      await tester.pumpAndSettle();
      expect(find.text('REENVIAR EN 30 S'), findsOneWidget);
    });
  });

  group('the email step', () {
    testWidgets('a passkey that fails says so under its button, and the email is not marked', (
      tester,
    ) async {
      auth.failures['passkeySignIn'] = const AuthFailure(code: 'PASSKEY_NOT_FOUND', status: 400);
      await openEmail(tester, passkeys: FakePasskeys());

      await tester.tap(find.byKey(const Key('entry.passkey')));
      await tester.pumpAndSettle();

      final message = find.text(
        'No pudimos hacerte entrar con tu huella. Inténtalo otra vez o usa tu correo.',
      );
      expect(message, findsOneWidget);
      // Between the passkey button and the line "o con tu correo", above the email field.
      final button = tester.getRect(find.byKey(const Key('entry.passkey')));
      final field = tester.getRect(find.byKey(const Key('entry.email')));
      final y = tester.getTopLeft(message).dy;
      expect(y, greaterThan(button.bottom));
      expect(y, lessThan(field.top));
      expect(find.text('o con tu correo'), findsOneWidget);
    });

    testWidgets('a mistake in the email is shown under the email, below the field', (tester) async {
      await openEmail(tester, passkeys: FakePasskeys());
      await tester.enterText(find.byKey(const Key('entry.email')), 'ana@');
      await tester.tap(find.byKey(const Key('entry.send')));
      await tester.pumpAndSettle();

      final message = find.text('Escribe un correo válido, como ana@correo.com.');
      expect(message, findsOneWidget);
      expect(
        tester.getTopLeft(message).dy,
        greaterThan(tester.getRect(find.byKey(const Key('entry.email'))).bottom),
      );
      // The field keeps the focus, so the keyboard stays to fix it.
      expect(
        tester.widget<EditableText>(find.byKey(const Key('entry.email'))).focusNode.hasFocus,
        isTrue,
      );
    });

    testWidgets('the passkey comes first, as on the web, when the phone has passkeys', (
      tester,
    ) async {
      await openEmail(tester, passkeys: FakePasskeys());
      expect(
        tester.getTopLeft(find.byKey(const Key('entry.passkey'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('entry.email'))).dy),
      );
    });
  });

  group('the first screen', () {
    testWidgets('keeps "Probar sin correo" first, in the secondary style, and the email primary', (
      tester,
    ) async {
      await pumpApp(tester, auth: auth);

      final guest = tester.widget<PressButton>(find.byKey(const Key('entry.guest')));
      final email = tester.widget<PressButton>(find.byKey(const Key('entry.withEmail')));
      expect(guest.tone, PressTone.secondary);
      expect(email.tone, PressTone.primary);
      expect(
        tester.getTopLeft(find.byKey(const Key('entry.guest'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('entry.withEmail'))).dy),
      );
      expect(find.text('Puedes agregar tu correo después.'), findsOneWidget);
    });

    testWidgets('the day/night switch changes the theme before anyone has signed in', (
      tester,
    ) async {
      await pumpApp(tester, auth: auth);
      Brightness shown() => Theme.of(tester.element(find.byType(Scaffold).first)).brightness;
      expect(shown(), Brightness.dark);

      await tester.tap(find.bySemanticsLabel('Cambiar a modo día'));
      await tester.pumpAndSettle();
      expect(shown(), Brightness.light);

      await tester.tap(find.bySemanticsLabel('Cambiar a modo noche'));
      await tester.pumpAndSettle();
      expect(shown(), Brightness.dark);
    });
  });

  group('at 130% on a small phone', () {
    Future<void> small(WidgetTester tester, {double width = 360}) async {
      tester.view
        ..physicalSize = Size(width, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    /// [button] can be reached by scrolling, and nothing overflowed on the way.
    Future<void> reachable(WidgetTester tester, Finder button) async {
      await tester.scrollUntilVisible(button, 100, scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(640));
    }

    testWidgets('the first screen', (tester) async {
      await small(tester);
      await pumpApp(tester, auth: auth, passkeys: FakePasskeys());
      expect(tester.takeException(), isNull);
      await reachable(tester, find.byKey(const Key('entry.withEmail')));
      // The passkey is not here; the email step has it.
      expect(find.byKey(const Key('entry.passkey')), findsNothing);
    });

    testWidgets('the email step, with a passkey and an error', (tester) async {
      await small(tester);
      await openEmail(tester, passkeys: FakePasskeys());
      await tester.enterText(find.byKey(const Key('entry.email')), 'ana@');
      await tester.tap(find.byKey(const Key('entry.send')), warnIfMissed: false);
      await tester.pumpAndSettle();
      await reachable(tester, find.byKey(const Key('entry.send')));
    });

    testWidgets('the code step, on a phone 320px wide', (tester) async {
      await small(tester, width: 320);
      await openEmail(tester);
      await toCodeStep(tester);
      await tester.enterText(find.byKey(const Key('entry.code')), '123456');
      await tester.pump();
      await reachable(tester, find.byKey(const Key('entry.submitCode')));
    });

    testWidgets('a link that could not sign in', (tester) async {
      await small(tester);
      auth.failures['verifyCode'] = const AuthFailure(status: 0);
      final container = await pumpApp(tester, auth: auth);
      container.read(routerProvider).go('/auth/verify?email=ana%40correo.com&code=654321');
      await tester.pumpAndSettle();
      await reachable(tester, find.text('ENVIAR UN CÓDIGO NUEVO'));
    });

    testWidgets('Guarda tu progreso', (tester) async {
      await small(tester);
      mockStorage(token: 'guest-token-0', guest: true);
      auth.guests['guest-token-0'] = true;
      final container = await pumpApp(tester, auth: auth, passkeys: FakePasskeys());
      container.read(routerProvider).go('/progress');
      await tester.pumpAndSettle();
      expect(find.byType(ProgressScreen), findsOneWidget);
      await reachable(tester, find.byKey(const Key('progress.passkey')));
    });
  });
}
