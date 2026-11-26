// Captura, the light version (spec 2026-11-22, "Captura, inside"): groups with an icon head and
// one-line rows. "Captura automática" (Android: a switch row per source, "Activa" / "Apagada", the
// missing-permission row with "Dar acceso" inside, "¿Cómo funciona?"), "Voz" (only with a model
// installed: "Mejorar la precisión" and the red "Borrar los modelos de voz"), "Avisos" and
// "Widget" (Android: "Añadir widget" while none is on the home screen, "Ocultar el monto").
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/capture_auto/capture_platform.dart';
import 'package:wambito/settings/preferences.dart';
import 'package:wambito/vault/preview.dart' show isPreviewProvider;

import '../capture_auto/fakes.dart';
import '../home/fakes.dart';
import 'harness.dart';

import 'package:wambito/capture_auto/how_capture_works.dart';
import 'package:wambito/home/widget_pin.dart';

Future<SettingsEnv> _pump(
  WidgetTester t, {
  FakeAutoCapturePlatform? platform,
  FakeWidgetPin? pin,
  bool modelsInstalled = true,
  bool preciseEligible = false,
  bool preview = false,
}) => pumpSettingsApp(
  t,
  location: '/settings/capture',
  modelsInstalled: modelsInstalled,
  preciseEligible: preciseEligible,
  overrides: [
    autoCapturePlatformProvider.overrideWithValue(platform ?? FakeAutoCapturePlatform()),
    if (pin != null) widgetPinProvider.overrideWithValue(pin),
    if (preview) isPreviewProvider.overrideWithValue(true),
  ],
);

Future<void> _show(WidgetTester t, Key key) async {
  await t.scrollUntilVisible(find.byKey(key), 200, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Android: the four groups, each with its icon head and line', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t, pin: FakeWidgetPin(isInstalled: false));
    expect(find.text('Captura automática'), findsOneWidget);
    expect(find.text('Desde las notificaciones de tus apps'), findsOneWidget);
    expect(find.text('Revolut'), findsOneWidget);
    expect(find.text('Google Wallet'), findsOneWidget);
    expect(find.text('ActivoBank'), findsOneWidget);
    expect(find.text('Apagada'), findsNWidgets(3));
    expect(find.text('¿Cómo funciona?'), findsOneWidget);
    await _show(t, const Key('settings.hideAmount'));
    expect(find.text('Voz'), findsOneWidget);
    expect(find.text('Dictar sin internet'), findsOneWidget);
    expect(find.text('Borrar los modelos de voz'), findsOneWidget);
    expect(find.text('Libera espacio; se descargan al dictar'), findsOneWidget);
    expect(find.text('Avisos'), findsOneWidget);
    expect(find.text('Lo que Wambito te recuerda'), findsOneWidget);
    expect(find.text('Hoy vence…'), findsOneWidget);
    expect(find.text('A las 9:00, los pagos que vencen hoy'), findsOneWidget);
    expect(find.text('Si no tienes correo'), findsOneWidget);
    expect(find.text('Antes de que se borren tus datos'), findsOneWidget);
    expect(find.text('Widget'), findsOneWidget);
    expect(find.text('Anota desde tu pantalla de inicio'), findsOneWidget);
    expect(find.text('Añadir widget'), findsOneWidget);
    expect(find.text('Ocultar el monto'), findsOneWidget);
    expect(find.text('En este teléfono'), findsNothing);
    handle.dispose();
  });

  testWidgets('a source row says Activa when on, and its switch toggles the source', (t) async {
    final fake = FakeAutoCapturePlatform(access: true, sources: {'google_wallet'});
    await _pump(t, platform: fake);
    expect(find.text('Activa'), findsOneWidget);
    expect(find.text('Apagada'), findsNWidgets(2));
    await t.tap(find.byKey(const Key('autoCapture.google_wallet')));
    await t.pumpAndSettle();
    expect(fake.sources, isEmpty);
    expect(find.text('Apagada'), findsNWidgets(3));
  });

  testWidgets('the first switch on still shows the steps', (t) async {
    final fake = FakeAutoCapturePlatform(access: true);
    await _pump(t, platform: fake);
    await t.tap(find.byKey(const Key('autoCapture.revolut')));
    await t.pumpAndSettle();
    expect(find.byType(HowCaptureWorks), findsOneWidget);
    expect(fake.callsNamed('setSource'), isEmpty);
  });

  testWidgets('a source on with no notification access shows "Dar acceso" in the group', (t) async {
    final fake = FakeAutoCapturePlatform(sources: {'revolut'});
    await _pump(t, platform: fake);
    expect(find.byKey(const Key('autoCapture.missing')), findsOneWidget);
    expect(find.text('Falta el permiso'), findsOneWidget);
    expect(find.text('Dar acceso'), findsOneWidget);
    await t.tap(find.byKey(const Key('autoCapture.grant')));
    await t.pumpAndSettle();
    expect(fake.callsNamed('openAccessSettings'), hasLength(1));
  });

  testWidgets('"¿Cómo funciona?" opens the explainer', (t) async {
    await _pump(t);
    await t.tap(find.byKey(const Key('autoCapture.how')));
    await t.pumpAndSettle();
    expect(find.byType(HowCaptureWorks), findsOneWidget);
  });

  testWidgets('iOS: no automatic capture and no widget group', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _pump(t, platform: FakeAutoCapturePlatform(available: false));
    await _show(t, const Key('settings.dueNotice'));
    expect(find.text('Captura automática'), findsNothing);
    expect(find.byKey(const Key('autoCapture.revolut')), findsNothing);
    expect(find.text('Hacia las 9:00, los pagos que vencen hoy'), findsOneWidget);
    expect(find.text('Widget'), findsNothing);
    expect(find.byKey(const Key('settings.hideAmount')), findsNothing);
    expect(find.byKey(const Key('settings.addWidget')), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('with no voice model there is no Voz group', (t) async {
    await _pump(t, modelsInstalled: false);
    expect(find.text('Voz'), findsNothing);
    expect(find.byKey(const Key('settings.deleteVoice')), findsNothing);
    expect(find.byKey(const Key('settings.voicePrecise')), findsNothing);
  });

  testWidgets('a phone that qualifies: the precise switch says its size, and downloads', (t) async {
    final env = await _pump(t, preciseEligible: true);
    await _show(t, const Key('settings.voicePrecise'));
    expect(find.text('Mejorar la precisión'), findsOneWidget);
    expect(find.text('+150 MB · corrige al terminar de hablar'), findsOneWidget);
    await t.tap(find.byKey(const Key('settings.voicePrecise')));
    await t.pumpAndSettle();
    expect(env.precise.downloaded, ['es']);
  });

  testWidgets('the delete row is red and asks first', (t) async {
    final env = await _pump(t);
    await _show(t, const Key('settings.deleteVoice'));
    await t.tap(find.byKey(const Key('settings.deleteVoice')));
    await t.pumpAndSettle();
    expect(find.text('¿Borrar los modelos de voz?'), findsOneWidget);
    expect(env.models.deletes, 0);
    await t.tap(find.byKey(const Key('settings.deleteVoice.confirm')));
    await t.pumpAndSettle();
    expect(env.models.deletes, 1);
    expect(find.text('Voz'), findsNothing, reason: 'the group goes with the models');
  });

  testWidgets('each notice and the widget switch toggles its own provider', (t) async {
    final env = await _pump(t);
    await _show(t, const Key('settings.hideAmount'));
    for (final key in ['settings.dueNotice', 'settings.guestNotice', 'settings.hideAmount']) {
      await _show(t, Key(key));
      await t.tap(find.byKey(Key(key)));
      await t.pumpAndSettle();
    }
    expect(env.container.read(dueNoticeEnabledProvider), isFalse);
    expect(env.container.read(guestNoticeEnabledProvider), isFalse);
    expect(env.container.read(hideWidgetAmountProvider), isTrue);
  });

  testWidgets('an encrypted account has no guest notice row', (t) async {
    await _pump(t, preview: true);
    await _show(t, const Key('settings.dueNotice'));
    expect(find.byKey(const Key('settings.guestNotice')), findsNothing);
    expect(find.text('Si no tienes correo'), findsNothing);
  });

  testWidgets('"Añadir widget" is there while no widget is on the home screen', (t) async {
    final pin = FakeWidgetPin(isInstalled: false);
    await _pump(t, pin: pin);
    await _show(t, const Key('settings.addWidget'));
    expect(find.text('Ponlo en tu pantalla de inicio'), findsOneWidget);
    await t.tap(find.byKey(const Key('settings.addWidget')));
    await t.pumpAndSettle();
    expect(pin.pins, 1);
  });

  testWidgets('with a widget on the home screen only "Ocultar el monto" stays', (t) async {
    await _pump(t, pin: FakeWidgetPin(isInstalled: true));
    await _show(t, const Key('settings.hideAmount'));
    expect(find.byKey(const Key('settings.addWidget')), findsNothing);
  });

  testWidgets('the notice switches say the full sentence to a screen reader', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t);
    await _show(t, const Key('settings.guestNotice'));
    expect(
      t.getSemantics(find.byKey(const Key('settings.dueNotice'))).hint,
      'A las 9:00, un aviso con los pagos recurrentes que vencen hoy.',
    );
    expect(
      t.getSemantics(find.byKey(const Key('settings.guestNotice'))).hint,
      'Si pasan 45 días sin abrir Wambito y no tienes correo, te avisamos: a los 60 días sin '
      'abrirlo se borran tus datos.',
    );
    handle.dispose();
  });

  testWidgets('iOS: the due switch says around 9:00 and that iOS picks the time', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final handle = t.ensureSemantics();
    await _pump(t, platform: FakeAutoCapturePlatform(available: false));
    await _show(t, const Key('settings.dueNotice'));
    expect(
      t.getSemantics(find.byKey(const Key('settings.dueNotice'))).hint,
      'Hacia las 9:00, un aviso con los pagos recurrentes que vencen hoy. '
      'iOS decide la hora exacta.',
    );
    handle.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
