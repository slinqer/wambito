import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/entry/passkey_offer_screen.dart';
import 'package:wambito/ui/press_button.dart';

import '../support/ui_app.dart';

/// The passkey offer (the web's PasskeyOffer.stories.tsx): what a passkey is, "Crear mi huella" and
/// "Ahora no".
void main() {
  final add = find.byKey(const Key('offer.add'));
  final notNow = find.byKey(const Key('offer.notNow'));

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<PressButton>(button).onPressed != null;

  Future<List<bool>> pumpOffer(
    WidgetTester tester,
    Future<PasskeyOfferOutcome> Function() make, {
    Locale locale = const Locale('es'),
  }) async {
    final answers = <bool>[];
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      uiApp(
        locale: locale,
        width: 412,
        SizedBox(
          height: 915,
          child: PasskeyOfferScreen(add: make, onAnswered: answers.add),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return answers;
  }

  testWidgets('says what a passkey is in four points, and offers two ways out', (tester) async {
    await pumpOffer(tester, () async => PasskeyOfferOutcome.added);

    expect(find.text('¿Entrar con tu huella la próxima vez?'), findsOneWidget);
    expect(find.text('Así entras sin esperar el código.'), findsOneWidget);
    for (final point in [
      'Una passkey es una llave guardada en este teléfono, en Google, Samsung Pass, iCloud o Proton Pass.',
      'Tu huella o tu cara solo la desbloquean. Wambito nunca las recibe.',
      'Se sincroniza con tus otros dispositivos que usan la misma cuenta.',
      'Tu correo sigue funcionando como respaldo.',
    ]) {
      expect(find.text(point), findsOneWidget);
    }
    expect(find.text('CREAR MI HUELLA'), findsOneWidget);
    expect(find.text('AHORA NO'), findsOneWidget);
  });

  testWidgets('in English', (tester) async {
    await pumpOffer(tester, () async => PasskeyOfferOutcome.added, locale: const Locale('en'));
    expect(find.text('Sign in with your fingerprint next time?'), findsOneWidget);
    expect(find.text('CREATE MY FINGERPRINT'), findsOneWidget);
    expect(find.text('NOT NOW'), findsOneWidget);
  });

  testWidgets('"Crear mi huella" makes the passkey and ends the offer', (tester) async {
    var made = 0;
    final answers = await pumpOffer(tester, () async {
      made++;
      return PasskeyOfferOutcome.added;
    });

    await tester.tap(add);
    await tester.pumpAndSettle();

    expect(made, 1);
    expect(answers, [true]);
  });

  testWidgets('"Ahora no" ends the offer without a passkey', (tester) async {
    var made = 0;
    final answers = await pumpOffer(tester, () async {
      made++;
      return PasskeyOfferOutcome.added;
    });

    await tester.tap(notNow);
    await tester.pumpAndSettle();

    expect(made, 0);
    expect(answers, [false]);
  });

  testWidgets('while the phone asks for the fingerprint both buttons wait, and say so', (
    tester,
  ) async {
    final prompt = Completer<PasskeyOfferOutcome>();
    final answers = await pumpOffer(tester, () => prompt.future);

    await tester.tap(add);
    await tester.pump();

    expect(find.text('ESPERANDO TU HUELLA…'), findsOneWidget);
    expect(enabled(tester, add), isFalse);
    expect(enabled(tester, notNow), isFalse);

    prompt.complete(PasskeyOfferOutcome.added);
    await tester.pumpAndSettle();
    expect(answers, [true]);
  });

  testWidgets('two quick taps open one prompt', (tester) async {
    final prompt = Completer<PasskeyOfferOutcome>();
    var made = 0;
    await pumpOffer(tester, () {
      made++;
      return prompt.future;
    });

    await tester.tap(add);
    await tester.tap(add, warnIfMissed: false);
    await tester.pump();

    expect(made, 1);
  });

  testWidgets('closing the phone\'s prompt is silent: the offer stays and can be tried again', (
    tester,
  ) async {
    var made = 0;
    final answers = await pumpOffer(tester, () async {
      made++;
      return PasskeyOfferOutcome.cancelled;
    });

    await tester.tap(add);
    await tester.pumpAndSettle();

    expect(answers, isEmpty);
    expect(find.textContaining('No pudimos'), findsNothing);
    expect(enabled(tester, add), isTrue);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(made, 2);
  });

  testWidgets('a passkey that could not be saved says so, and "Ahora no" is still there', (
    tester,
  ) async {
    final answers = await pumpOffer(tester, () async => PasskeyOfferOutcome.failed);

    await tester.tap(add);
    await tester.pumpAndSettle();

    expect(
      find.text('No pudimos guardar tu huella. Inténtalo otra vez o sigue sin ella.'),
      findsOneWidget,
    );
    expect(answers, isEmpty);
    expect(enabled(tester, notNow), isTrue);
    await tester.tap(notNow);
    await tester.pumpAndSettle();
    expect(answers, [false]);
  });

  testWidgets('something thrown by the prompt is a failure, not a stuck button', (tester) async {
    await pumpOffer(tester, () async => throw StateError('bug'));

    await tester.tap(add);
    await tester.pumpAndSettle();

    expect(find.textContaining('No pudimos guardar tu huella'), findsOneWidget);
    expect(enabled(tester, add), isTrue);
  });

  testWidgets('a passkey that gives no PRF: the add notice stays, and Seguir answers', (
    tester,
  ) async {
    final answers = await pumpOffer(tester, () async => PasskeyOfferOutcome.addedWithoutPrf);
    await tester.tap(add);
    await tester.pumpAndSettle();
    const notice =
        'Esta huella sirve para entrar, pero tu gestor de contraseñas no le permite abrir tus '
        'datos. Guarda tu clave de recuperación: la vas a necesitar en un dispositivo nuevo.';
    expect(find.text(notice), findsOneWidget);
    // Not answered yet: the notice waits for the person, it does not pass.
    expect(answers, isEmpty);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text(notice), findsOneWidget);
    expect(find.text('SEGUIR'), findsOneWidget);
    await tester.tap(find.byKey(const Key('offer.continue')));
    await tester.pumpAndSettle();
    expect(answers, [true]);
  });
}
