// "Captura automática" in Settings: the steps ("¿Cómo funciona?") before the first switch on, the missing-permission
// row and the restricted-settings steps, the status read again when the app resumes, and no section
// where there is no Android side.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/capture_auto/auto_capture_section.dart';
import 'package:wambito/capture_auto/capture_platform.dart';
import 'package:wambito/capture_auto/how_capture_works.dart';

import '../settings/harness.dart';
import 'fakes.dart';

Future<(SettingsEnv, FakeAutoCapturePlatform)> _pump(
  WidgetTester t, {
  FakeAutoCapturePlatform? platform,
  Locale locale = const Locale('es'),
}) async {
  final fake = platform ?? FakeAutoCapturePlatform();
  final env = await pumpSettingsApp(
    t,
    locale: locale,
    location: '/settings',
    overrides: [autoCapturePlatformProvider.overrideWithValue(fake)],
  );
  return (env, fake);
}

/// A text drawn by `CssParagraph`: found by what a screen reader reads (a part of it).
Finder said(String part) => find.bySemanticsLabel(RegExp(RegExp.escape(part)));

Future<void> _show(WidgetTester t, Key key) async {
  await t.scrollUntilVisible(find.byKey(key), 300, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

/// Goes through the steps to the last one, where "Activar acceso" is.
Future<void> _toLastStep(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.ensureVisible(find.byKey(const Key('autoCapture.how.next')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('autoCapture.how.next')));
    await t.pumpAndSettle();
  }
  await t.ensureVisible(find.byKey(const Key('autoCapture.explainer.confirm')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the first switch on shows the steps before opening the access screen', (t) async {
    final (_, fake) = await _pump(t);
    await _show(t, const Key('autoCapture.revolut'));
    await t.tap(find.byKey(const Key('autoCapture.revolut')));
    await t.pumpAndSettle();

    expect(find.byType(HowCaptureWorks), findsOneWidget);
    expect(fake.callsNamed('setSource'), isEmpty);
    expect(fake.callsNamed('openAccessSettings'), isEmpty);

    await _toLastStep(t);
    expect(said('salen de tu teléfono'), findsOneWidget);
    await t.tap(find.byKey(const Key('autoCapture.explainer.confirm')));
    await t.pumpAndSettle();

    final order = fake.calls.where((c) => c.startsWith('setSource') || c == 'openAccessSettings');
    expect(order, ['setSource revolut true', 'openAccessSettings']);
  });

  testWidgets('the steps show once: the next switch on goes straight to Android', (t) async {
    final (env, fake) = await _pump(t);
    await _show(t, const Key('autoCapture.revolut'));
    await t.tap(find.byKey(const Key('autoCapture.revolut')));
    await t.pumpAndSettle();
    await _toLastStep(t);
    await t.tap(find.byKey(const Key('autoCapture.explainer.confirm')));
    await t.pumpAndSettle();
    expect(env.container.read(autoCaptureExplainedProvider), isTrue);

    await t.tap(find.byKey(const Key('autoCapture.google_wallet')));
    await t.pumpAndSettle();

    expect(find.byType(HowCaptureWorks), findsNothing);
    expect(fake.sources, {'revolut', 'google_wallet'});
  });

  testWidgets('closing the steps changes nothing', (t) async {
    final (_, fake) = await _pump(t);
    await _show(t, const Key('autoCapture.revolut'));
    await t.tap(find.byKey(const Key('autoCapture.revolut')));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(195, 20));
    await t.pumpAndSettle();

    expect(fake.callsNamed('setSource'), isEmpty);
  });

  testWidgets('a source on with no access says the permission is missing, with Activar', (t) async {
    final (_, fake) = await _pump(t, platform: FakeAutoCapturePlatform(sources: {'revolut'}));
    await _show(t, const Key('autoCapture.missing'));

    expect(said('Falta el permiso'), findsOneWidget);
    expect(find.byKey(const Key('autoCapture.stuck')), findsNothing);
    await t.tap(find.byKey(const Key('autoCapture.grant')));
    await t.pumpAndSettle();

    expect(fake.callsNamed('openAccessSettings'), hasLength(1));
  });

  testWidgets('after trying, "¿No te deja?" shows the steps and opens the app info', (t) async {
    final (_, fake) = await _pump(t, platform: FakeAutoCapturePlatform(sources: {'revolut'}));
    await _show(t, const Key('autoCapture.grant'));
    await t.tap(find.byKey(const Key('autoCapture.grant')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('autoCapture.stuck')));
    await t.pumpAndSettle();

    expect(said('Permitir ajustes restringidos'), findsOneWidget);
    await t.tap(find.byKey(const Key('autoCapture.openInfo')));
    await t.pumpAndSettle();

    expect(fake.callsNamed('openAppInfo'), hasLength(1));
  });

  testWidgets('with access granted the section says it is active', (t) async {
    await _pump(t, platform: FakeAutoCapturePlatform(access: true, sources: {'google_wallet'}));
    await _show(t, const Key('autoCapture.active'));

    expect(find.byKey(const Key('autoCapture.missing')), findsNothing);
  });

  testWidgets('the status is read again when the app resumes', (t) async {
    final (_, fake) = await _pump(t, platform: FakeAutoCapturePlatform(sources: {'revolut'}));
    await _show(t, const Key('autoCapture.missing'));
    final before = fake.callsNamed('status').length;

    fake.access = true;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();

    expect(fake.callsNamed('status').length, before + 1);
    expect(find.byKey(const Key('autoCapture.missing')), findsNothing);
    expect(find.byKey(const Key('autoCapture.active')), findsOneWidget);
  });

  testWidgets('without an Android side the section is not drawn', (t) async {
    await _pump(t, platform: FakeAutoCapturePlatform(available: false));

    expect(find.byKey(const Key('settings.card.autoCapture')), findsNothing);
    expect(said('Captura automática'), findsNothing);
  });

  testWidgets('the copy exists in English', (t) async {
    await _pump(t, locale: const Locale('en'));
    await _show(t, const Key('autoCapture.revolut'));

    expect(said('Automatic capture'), findsWidgets);
  });
}
