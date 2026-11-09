// "¿Cómo funciona?": the five steps of automatic capture in a sheet, on the first switch on (ending
// with "Activar acceso") and from the section's link (ending with "Entendido").
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/capture_auto/auto_capture_section.dart';
import 'package:wambito/capture_auto/capture_platform.dart';
import 'package:wambito/capture_auto/how_capture_works.dart';
import 'package:wambito/money/format.dart';

import '../settings/harness.dart';
import 'fakes.dart';

Future<(SettingsEnv, FakeAutoCapturePlatform)> _pump(
  WidgetTester t, {
  Locale locale = const Locale('es'),
}) async {
  final fake = FakeAutoCapturePlatform();
  final env = await pumpSettingsApp(
    t,
    locale: locale,
    location: '/settings',
    overrides: [autoCapturePlatformProvider.overrideWithValue(fake)],
  );
  return (env, fake);
}

Future<void> _show(WidgetTester t, Key key) async {
  await t.scrollUntilVisible(find.byKey(key), 300, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

Future<void> _tap(WidgetTester t, Key key) async {
  await t.ensureVisible(find.byKey(key));
  await t.pumpAndSettle();
  await t.tap(find.byKey(key));
  await t.pumpAndSettle();
}

Future<void> _toLastStep(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await _tap(t, const Key('autoCapture.how.next'));
  }
}

Future<void> _switchOn(WidgetTester t) async {
  await _show(t, const Key('autoCapture.revolut'));
  await t.tap(find.byKey(const Key('autoCapture.revolut')));
  await t.pumpAndSettle();
}

const _confirm = Key('autoCapture.explainer.confirm');

void main() {
  testWidgets('first switch-on shows the steps and Activar acceso turns the source on', (t) async {
    final (env, fake) = await _pump(t);
    await _switchOn(t);

    expect(find.byType(HowCaptureWorks), findsOneWidget);
    expect(find.text('Pagas como siempre'), findsOneWidget);
    expect(fake.callsNamed('setSource'), isEmpty);

    await _toLastStep(t);
    await _tap(t, _confirm);

    expect(find.byType(HowCaptureWorks), findsNothing);
    final order = fake.calls.where((c) => c.startsWith('setSource') || c == 'openAccessSettings');
    expect(order, ['setSource revolut true', 'openAccessSettings']);
    expect(env.container.read(autoCaptureExplainedProvider), isTrue);
  });

  testWidgets('closing the steps keeps the source off', (t) async {
    final (env, fake) = await _pump(t);
    await _switchOn(t);
    expect(find.byType(HowCaptureWorks), findsOneWidget);

    await t.binding.handlePopRoute();
    await t.pumpAndSettle();

    expect(find.byType(HowCaptureWorks), findsNothing);
    expect(fake.callsNamed('setSource'), isEmpty);
    expect(env.container.read(autoCaptureExplainedProvider), isFalse);

    await t.tap(find.byKey(const Key('autoCapture.revolut')));
    await t.pumpAndSettle();
    expect(find.byType(HowCaptureWorks), findsOneWidget);
  });

  testWidgets('the last step carries the disclosure', (t) async {
    await _pump(t);
    await _switchOn(t);

    for (var i = 0; i < 4; i++) {
      await t.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await t.pumpAndSettle();
    }

    expect(find.text('Hoy y lo que viene'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Wambito lee las notificaciones de las apps que actives. Solo el monto, el comercio, la '
        'fecha y la app salen de tu teléfono.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(_confirm), findsOneWidget);
    expect(find.byKey(const Key('autoCapture.how.next')), findsNothing);

    // Both in view without scrolling, the disclosure right above the button.
    final screen = Offset.zero & t.view.physicalSize / t.view.devicePixelRatio;
    final disclosure = t.getRect(find.byKey(const Key('autoCapture.how.disclosure')));
    final button = t.getRect(find.byKey(_confirm));
    expect(screen.intersect(disclosure), disclosure);
    expect(screen.intersect(button), button);
    expect(disclosure.bottom, lessThanOrEqualTo(button.top));
  });

  testWidgets('the demos show the invented movement with its signs', (t) async {
    await _pump(t);
    await _switchOn(t);
    Finder inSheet(Finder f) => find.descendant(of: find.byType(HowCaptureWorks), matching: f);
    String money(int cents, {bool plus = false}) =>
        formatMoney(cents, 'EUR', 'es', sign: plus ? MoneySign.always : MoneySign.auto);

    expect(find.text('💳 ${money(-1250)}'), findsOneWidget);
    expect(find.textContaining('Otros gastos · por revisar', findRichText: true), findsOneWidget);

    await _tap(t, const Key('autoCapture.how.next'));
    expect(find.text(money(1250)), findsOneWidget, reason: 'the chip has no sign');
    expect(find.text(money(1250, plus: true)), findsNothing);
    expect(find.text('Pastelaria Aurora'), findsOneWidget);

    await _tap(t, const Key('autoCapture.how.next'));
    expect(inSheet(find.text('BIEN')), findsOneWidget);
    expect(inSheet(find.text('CAMBIAR')), findsOneWidget);
    expect(find.textContaining('Anoté ${money(-1250)} en Pastelaria Aurora'), findsOneWidget);

    await _tap(t, const Key('autoCapture.how.next'));
    expect(find.textContaining('Otros gastos · por revisar', findRichText: true), findsOneWidget);
    expect(find.textContaining('Restaurante', findRichText: true), findsOneWidget);
  });

  testWidgets('Cómo funciona shows the steps and ends with Entendido', (t) async {
    final (_, fake) = await _pump(t);
    await _show(t, const Key('autoCapture.how'));
    await t.tap(find.byKey(const Key('autoCapture.how')));
    await t.pumpAndSettle();

    expect(find.byType(HowCaptureWorks), findsOneWidget);
    await _toLastStep(t);

    expect(find.byKey(const Key('autoCapture.how.done')), findsOneWidget);
    expect(find.byKey(_confirm), findsNothing);

    await _tap(t, const Key('autoCapture.how.done'));

    expect(find.byType(HowCaptureWorks), findsNothing);
    expect(fake.callsNamed('setSource'), isEmpty);
    expect(fake.callsNamed('openAccessSettings'), isEmpty);
  });

  testWidgets('swiping and Siguiente move steps', (t) async {
    await _pump(t);
    await _switchOn(t);

    await t.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await t.pumpAndSettle();
    expect(find.text('Wambito la lee en tu teléfono'), findsOneWidget);
    expect(find.text('Pagas como siempre'), findsNothing);

    await _tap(t, const Key('autoCapture.how.next'));
    expect(find.text('Te avisa y tú decides'), findsOneWidget);
    bool selected(int dot) =>
        t.getSemantics(find.byKey(Key('autoCapture.how.dot.$dot'))).flagsCollection.isSelected ==
        Tristate.isTrue;
    expect(selected(2), isTrue);
    expect(selected(1), isFalse);
    expect(t.getSemantics(find.byKey(const Key('autoCapture.how.dot.2'))).label, 'Paso 3 de 5');

    await _tap(t, const Key('autoCapture.how.dot.0'));
    expect(find.text('Pagas como siempre'), findsOneWidget);
  });

  testWidgets('reduced motion jumps between steps', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(t);
    await _switchOn(t);
    expect(t.binding.platformDispatcher.accessibilityFeatures.disableAnimations, isTrue);

    await t.tap(find.byKey(const Key('autoCapture.how.next')));
    await t.pump();

    expect(find.text('Wambito la lee en tu teléfono'), findsOneWidget);
    expect(find.text('Pagas como siempre'), findsNothing);
  });

  testWidgets('Cómo funciona sits under the apps it explains', (t) async {
    await _pump(t);
    await _show(t, const Key('autoCapture.how'));
    final link = t.getRect(find.byKey(const Key('autoCapture.how')));
    for (final source in CaptureSource.values) {
      final row = t.getRect(find.byKey(Key('autoCapture.${source.wire}')));
      expect(link.top, greaterThanOrEqualTo(row.bottom), reason: source.wire);
    }
  });

  testWidgets('every step keeps the same height, the last one too', (t) async {
    await _pump(t);
    await _show(t, const Key('autoCapture.how'));
    await t.tap(find.byKey(const Key('autoCapture.how')));
    await t.pumpAndSettle();

    final heights = <double>[];
    for (var i = 0; i < 5; i++) {
      heights.add(t.getSize(find.byType(PageView)).height);
      if (i < 4) await _tap(t, const Key('autoCapture.how.next'));
    }
    expect(heights.toSet(), hasLength(1), reason: '$heights');
  });

  testWidgets('the sheet keeps its size up to the last step, disclosure included', (t) async {
    await _pump(t);
    // A screen where the steps fit, so the sheet takes its content's height.
    t.view
      ..physicalSize = const Size(412, 732) * 2.625
      ..devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpAndSettle();
    await _switchOn(t);
    final title = find.descendant(
      of: find.byType(HowCaptureWorks),
      matching: find.text('Captura automática'),
    );

    final tops = <double>[];
    for (var i = 0; i < 5; i++) {
      tops.add(t.getRect(title).top);
      if (i < 4) await _tap(t, const Key('autoCapture.how.next'));
    }
    expect(tops.toSet(), hasLength(1), reason: 'the sheet moved: $tops');
  });

  for (final locale in const [Locale('es'), Locale('pt')]) {
    // A short phone (the emulator's 412×732, with Android's status bar and button bar taking their
    // part): every step, demo included, shows whole between the sheet's title and its footer,
    // without scrolling.
    testWidgets('fits a short phone without scrolling ($locale)', (t) async {
      await _pump(t, locale: locale);
      t.view
        ..physicalSize = const Size(412, 732) * 2.625
        ..devicePixelRatio = 2.625
        ..padding = const FakeViewPadding(top: 24 * 2.625, bottom: 48 * 2.625)
        ..viewPadding = const FakeViewPadding(top: 24 * 2.625, bottom: 48 * 2.625);
      addTearDown(t.view.reset);
      await t.pumpAndSettle();
      await _show(t, const Key('autoCapture.how'));
      await t.tap(find.byKey(const Key('autoCapture.how')));
      await t.pumpAndSettle();

      final pages = t.getRect(find.byType(PageView));
      final footer = t.getRect(find.byKey(const Key('autoCapture.how.dot.0')));
      expect(pages.top, greaterThanOrEqualTo(0));
      expect(pages.bottom, lessThanOrEqualTo(footer.top), reason: 'the tallest step is cut');
    });

    // A tall phone that is not "short" (a Galaxy S25 Ultra at its default display size: 412×892,
    // status bar and gesture bar) and the first switch on, whose footer keeps the disclosure's room:
    // the first step, demo included, still shows whole above the footer.
    testWidgets('fits a tall phone on the first switch on ($locale)', (t) async {
      await _pump(t, locale: locale);
      t.view
        ..physicalSize = const Size(412, 892) * 2.625
        ..devicePixelRatio = 2.625
        ..padding = const FakeViewPadding(top: 36 * 2.625, bottom: 24 * 2.625)
        ..viewPadding = const FakeViewPadding(top: 36 * 2.625, bottom: 24 * 2.625);
      addTearDown(t.view.reset);
      await t.pumpAndSettle();
      await _switchOn(t);

      for (var i = 0; i < 5; i++) {
        final pages = t.getRect(find.byType(PageView));
        final footer = t.getRect(find.byKey(const Key('autoCapture.how.dot.0')));
        expect(pages.bottom, lessThanOrEqualTo(footer.top), reason: 'step $i is cut');
        if (i < 4) await _tap(t, const Key('autoCapture.how.next'));
      }
    });

    testWidgets('fits a 360 dp phone ($locale)', (t) async {
      await _pump(t, locale: locale);
      t.view
        ..physicalSize = const Size(360, 740) * 3
        ..devicePixelRatio = 3;
      await t.pumpAndSettle();
      await _show(t, const Key('autoCapture.how'));
      await t.tap(find.byKey(const Key('autoCapture.how')));
      await t.pumpAndSettle();

      for (var i = 0; i < 5; i++) {
        expect(t.takeException(), isNull, reason: 'step $i');
        if (i < 4) await _tap(t, const Key('autoCapture.how.next'));
      }
      expect(find.byKey(const Key('autoCapture.how.done')), findsOneWidget);
    });
  }
}
