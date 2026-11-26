// "Captura automática" in Settings (rows in a light group): the steps ("¿Cómo funciona?") before the first switch on, the missing-permission
// row and the restricted-settings steps, the status read again when the app resumes, and no section
// where there is no Android side.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/capture_auto/auto_capture_section.dart';
import 'package:wambito/capture_auto/capture_platform.dart';
import 'package:wambito/capture_auto/how_capture_works.dart';
import 'package:wambito/capture_auto/wallet_setup.dart';

import 'package:wambito/notices/notice_platform.dart';
import 'package:wambito/ui/lk_brand_logo.dart';

import '../notices/fakes.dart';
import '../settings/harness.dart';
import 'fakes.dart';

Future<(SettingsEnv, FakeAutoCapturePlatform)> _pump(
  WidgetTester t, {
  FakeAutoCapturePlatform? platform,
  Locale locale = const Locale('es'),
  String? shortcutUrl,
}) async {
  final fake = platform ?? FakeAutoCapturePlatform();
  final env = await pumpSettingsApp(
    t,
    locale: locale,
    location: '/settings/capture',
    overrides: [
      autoCapturePlatformProvider.overrideWithValue(fake),
      if (shortcutUrl != null) walletShortcutUrlProvider.overrideWithValue(shortcutUrl),
    ],
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

    await _show(t, const Key('autoCapture.google_wallet'));
    await t.tap(find.byKey(const Key('autoCapture.google_wallet')));
    await t.pumpAndSettle();

    expect(find.byType(HowCaptureWorks), findsNothing);
    expect(fake.sources, {'revolut', 'google_wallet'});
  });

  testWidgets('ActivoBank has its own switch, with its logo', (t) async {
    final (_, fake) = await _pump(t);
    await _show(t, const Key('autoCapture.activobank'));
    expect(said('ActivoBank'), findsWidgets);
    expect(
      find.byWidgetPredicate((w) => w is LkBrandLogo && w.brand == LkBrand.activobank),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('autoCapture.activobank')));
    await t.pumpAndSettle();
    await _toLastStep(t);
    await t.tap(find.byKey(const Key('autoCapture.explainer.confirm')));
    await t.pumpAndSettle();
    expect(fake.sources, {'activobank'});
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

  testWidgets('with access granted the source says Activa and nothing is missing', (t) async {
    await _pump(t, platform: FakeAutoCapturePlatform(access: true, sources: {'google_wallet'}));
    await _show(t, const Key('autoCapture.google_wallet'));

    expect(find.text('Activa'), findsOneWidget);
    expect(find.text('Apagada'), findsNWidgets(2));
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
    expect(find.text('Activa'), findsOneWidget);
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

  group('on the iPhone', () {
    testWidgets('only Apple Pay, configured or not, and no Android rows', (t) async {
      await _pump(t, platform: FakeAutoCapturePlatform.iphone(configured: true));
      await _show(t, const Key('autoCapture.apple_wallet'));
      expect(find.byKey(const Key('autoCapture.revolut')), findsNothing);
      expect(find.byKey(const Key('autoCapture.google_wallet')), findsNothing);
      expect(find.text('Apple Pay'), findsOneWidget);
      expect(find.text('Configurada'), findsOneWidget);
      expect(find.byKey(const Key('autoCapture.missing')), findsNothing);
      expect(find.byKey(const Key('autoCapture.grant')), findsNothing);
    });

    testWidgets('on but no payment yet says it is not set up', (t) async {
      await _pump(t, platform: FakeAutoCapturePlatform.iphone());
      await _show(t, const Key('autoCapture.apple_wallet'));
      expect(find.text('Sin configurar'), findsOneWidget);
    });

    testWidgets('Configurar en Atajos opens the setup sheet', (t) async {
      await _pump(t, platform: FakeAutoCapturePlatform.iphone());
      await _show(t, const Key('autoCapture.setup'));
      await t.tap(find.byKey(const Key('autoCapture.setup')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('walletSetup.sheet')), findsOneWidget);
    });

    testWidgets('Probar asks for notices, then posts the sample notification', (t) async {
      final fake = FakeAutoCapturePlatform.iphone();
      final notices = FakeNoticePlatform();
      await pumpSettingsApp(
        t,
        locale: const Locale('es'),
        location: '/settings/capture',
        overrides: [
          autoCapturePlatformProvider.overrideWithValue(fake),
          noticePlatformProvider.overrideWithValue(notices),
        ],
      );
      await _show(t, const Key('autoCapture.test'));
      await t.tap(find.byKey(const Key('autoCapture.test')));
      await t.pumpAndSettle();
      expect(fake.testBodies, hasLength(1));
      expect(fake.testBodies.single, contains('Prueba de Wambito'));
      expect(notices.callsNamed('requestPermission'), hasLength(1));
      expect(find.text('Listo: mira el aviso arriba'), findsOneWidget);
    });

    testWidgets('the first switch on explains it for Apple Pay and goes to the setup', (t) async {
      final (_, fake) = await _pump(t, platform: FakeAutoCapturePlatform.iphone(on: false));
      await _show(t, const Key('autoCapture.apple_wallet'));
      await t.tap(find.byKey(const Key('autoCapture.apple_wallet')));
      await t.pumpAndSettle();
      expect(find.byType(HowCaptureWorks), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await t.ensureVisible(find.byKey(const Key('autoCapture.how.next')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('autoCapture.how.next')));
        await t.pumpAndSettle();
      }
      expect(said('Apple Pay'), findsWidgets);
      expect(find.byKey(const Key('autoCapture.explainer.confirm')), findsNothing);
      await t.ensureVisible(find.byKey(const Key('autoCapture.setup.start')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('autoCapture.setup.start')));
      await t.pumpAndSettle();
      expect(fake.callsNamed('setSource'), ['setSource apple_wallet true']);
      expect(fake.callsNamed('openAccessSettings'), isEmpty);
      expect(find.byKey(const Key('walletSetup.sheet')), findsOneWidget);
    });

    testWidgets('with the shortcut link the first switch on installs it and shows what is left', (
      t,
    ) async {
      const link = 'https://www.icloud.com/shortcuts/0123456789abcdef0123456789abcdef';
      final (env, fake) = await _pump(
        t,
        platform: FakeAutoCapturePlatform.iphone(on: false),
        shortcutUrl: link,
      );
      await _show(t, const Key('autoCapture.apple_wallet'));
      await t.tap(find.byKey(const Key('autoCapture.apple_wallet')));
      await t.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await t.ensureVisible(find.byKey(const Key('autoCapture.how.next')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('autoCapture.how.next')));
        await t.pumpAndSettle();
      }
      await t.ensureVisible(find.byKey(const Key('autoCapture.setup.start')));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('autoCapture.setup.start')),
          matching: find.text('INSTALAR EL ATAJO'),
        ),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('autoCapture.setup.start')));
      await t.pumpAndSettle();
      expect(fake.callsNamed('setSource'), ['setSource apple_wallet true']);
      expect(env.opener.opened, [Uri.parse(link)]);
      // No setup sheet in between: back from Shortcuts, only what is left.
      expect(find.byKey(const Key('walletSetup.sheet')), findsNothing);
      expect(find.byKey(const Key('walletSetup.finish')), findsOneWidget);
      expect(find.text('Falta un paso'), findsOneWidget);
      expect(said('toca Editar'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('walletSetup.openShortcuts')));
      await t.tap(find.byKey(const Key('walletSetup.openShortcuts')));
      await t.pumpAndSettle();
      expect(fake.callsNamed('openShortcuts'), hasLength(1));
    });

    testWidgets('below iOS 27 the link is not used: the first switch on shows the guide', (
      t,
    ) async {
      final (env, _) = await _pump(
        t,
        platform: FakeAutoCapturePlatform.iphone(on: false, iosMajor: 26),
        shortcutUrl: 'https://www.icloud.com/shortcuts/0123456789abcdef0123456789abcdef',
      );
      await _show(t, const Key('autoCapture.apple_wallet'));
      await t.tap(find.byKey(const Key('autoCapture.apple_wallet')));
      await t.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await t.ensureVisible(find.byKey(const Key('autoCapture.how.next')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('autoCapture.how.next')));
        await t.pumpAndSettle();
      }
      await t.ensureVisible(find.byKey(const Key('autoCapture.setup.start')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('autoCapture.setup.start')));
      await t.pumpAndSettle();
      expect(env.opener.opened, isEmpty);
      expect(find.byKey(const Key('walletSetup.guide')), findsOneWidget);
    });

    testWidgets('switching it off offers to remove the automation in Shortcuts', (t) async {
      final (_, fake) = await _pump(t, platform: FakeAutoCapturePlatform.iphone(configured: true));
      await _show(t, const Key('autoCapture.apple_wallet'));
      await t.tap(find.byKey(const Key('autoCapture.apple_wallet')));
      await t.pumpAndSettle();
      expect(fake.callsNamed('setSource'), ['setSource apple_wallet false']);
      await _show(t, const Key('autoCapture.remove'));
      await t.tap(find.byKey(const Key('autoCapture.remove')));
      await t.pumpAndSettle();
      expect(fake.callsNamed('openShortcuts'), hasLength(1));
    });

    testWidgets('Android has no iPhone rows', (t) async {
      await _pump(t, platform: FakeAutoCapturePlatform(sources: {'revolut'}, access: true));
      await _show(t, const Key('autoCapture.how'));
      expect(find.byKey(const Key('autoCapture.setup')), findsNothing);
      expect(find.byKey(const Key('autoCapture.test')), findsNothing);
      expect(find.byKey(const Key('autoCapture.apple_wallet')), findsNothing);
    });
  });
}
