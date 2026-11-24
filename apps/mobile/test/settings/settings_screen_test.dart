import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/capture/models_download.dart';
import 'package:wambito/feedback/feedback.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/entry/entry_screen.dart';
import 'package:wambito/settings/licenses.dart';
import 'package:wambito/settings/preferences.dart';
import 'package:wambito/settings/settings_parts.dart' show LkSwitch;
import 'package:wambito/settings/settings_screen.dart' show debugToolsProvider;
import 'package:wambito/ui/sheet.dart' show LkSheetScope;
import 'package:wambito/api/server_url.dart';
import 'package:wambito/local/backend.dart' show LocalBackend, createLocalBackend;
import 'package:wambito/local/memory_store.dart' show createMemoryStore;
import 'package:wambito/local/vault_session.dart' show VaultSession;
import 'package:wambito/vault/vault_providers.dart' show vaultSessionProvider;
import 'package:wambito/protect/protect_status.dart';
import 'package:wambito/security/screen_lock.dart' show LockCheck, screenLockProvider;
import 'package:wambito/settings/security/security_api.dart'
    show securityApiProvider, securitySnapshotProvider;
import 'package:flutter_riverpod/misc.dart' show Override;

import '../protect/fakes.dart' show FakeVault;

import 'package:wambito/vault/recovery_key_setup_view.dart' show RecoveryKeySetupView;
import 'package:wambito/vault/preview.dart' show isPreviewProvider;

import '../home/fakes.dart';
import 'harness.dart';
import 'security/fake_security.dart' show FakeLock, FakeSecurity, snapshotOf;

const _honestEs = 'Sin correo, si pierdes el teléfono o borras la app, pierdes tus datos.';
const _honestEn = 'Without an email, losing the phone or deleting the app loses your data.';

Future<void> _scrollTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _scrollTo(tester, key);
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// A `preview` guest's vault and the protect answers around it: [recoveryKey] and [passkey] say
/// which way back is done; [passkeyReadable] false is the phone being offline.
List<Override> _previewGuest({
  bool recoveryKey = false,
  bool passkey = false,
  bool passkeyReadable = true,
}) => [
  protectStatusProvider.overrideWith(
    (ref) async => ProtectStatus(
      recoveryKey: recoveryKey,
      passkey: passkey,
      passkeyOffered: true,
      passkeyWithoutPrf: false,
    ),
  ),
  securityApiProvider.overrideWithValue(FakeSecurity()),
  securitySnapshotProvider.overrideWith(
    (ref) async => passkeyReadable ? snapshotOf() : throw StateError('offline'),
  ),
  screenLockProvider.overrideWithValue(FakeLock(LockCheck.noLock)),
];

Future<void> _changeServerTo(WidgetTester tester, String url) async {
  await _tap(tester, 'settings.server');
  await tester.enterText(find.byKey(const Key('settings.server.field')), url);
  await tester.tap(find.byKey(const Key('settings.server.change')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(registerExtraLicenses);

  group('as the web\'s Settings', () {
    testWidgets('says who is signed in, as the web does, and a guest that there is no email', (
      tester,
    ) async {
      await pumpSettingsApp(
        tester,
        location: '/settings',
        homeRepo: FakeHomeRepository(email: 'ana@correo.com'),
      );
      expect(find.text('Entraste como ana@correo.com'), findsOneWidget);
    });

    testWidgets('the web\'s public pages (landing, roadmap) have a card of their own, with links', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await pumpSettingsApp(tester, location: '/settings/more');
      await _scrollTo(tester, 'settings.web');
      // The pages the app has not (the landing, the roadmap): named in the card, with the links.
      // The web's app pages (import, recurring, categories) have their places in the app.
      expect(find.text('Abrir Wambito en la web'), findsOneWidget);
      expect(find.text('La página de Wambito y lo que viene.'), findsOneWidget);
      expect(find.byKey(const Key('settings.roadmap')), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings.web')));
      await tester.pumpAndSettle();
      expect(env.opener.opened, [defaultServerUrl]);
      handle.dispose();
    });

    testWidgets('the choices are the web\'s radios: one chosen, the arrows move it', (
      tester,
    ) async {
      final env = await pumpSettingsApp(tester, location: '/settings/preferences');
      // Night is chosen; the right arrow, with the focus on it, picks Día.
      await _tap(tester, 'settings.theme');
      Focus.of(tester.element(find.byKey(const Key('settings.theme.night')))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.light);
      expect(env.settings.values['setting.theme'], 'light');
    });

    testWidgets('the sound switch says the vibration is its own setting', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSettingsApp(tester, locale: const Locale('en'), location: '/settings/preferences');
      expect(
        tester.getSemantics(find.byKey(const Key('settings.sound'))).hint,
        contains('Vibration stays on.'),
      );
      await _tap(tester, 'settings.vibration');
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings.sound')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byKey(const Key('settings.sound'))).hint,
        contains('Vibration stays off.'),
      );
      handle.dispose();
    });

    testWidgets('the guest\'s questions are the web\'s sheet, not a dialog', (tester) async {
      await pumpSettingsApp(tester, guest: true, location: '/settings');
      await _tap(tester, 'settings.signOut');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(LkSheetScope), findsOneWidget);
      expect(find.text('¿Cerrar sesión sin guardar tu progreso?'), findsOneWidget);
      // The web's sheet has a "Cerrar" and the question's own ways out, one under the other.
      expect(find.text('CERRAR'), findsOneWidget);
      expect(find.byKey(const Key('guest.saveInstead')), findsOneWidget);
      expect(find.byKey(const Key('guest.signOutConfirm')), findsOneWidget);
    });

    testWidgets('the server is changed in a sheet, and the voice models\' question is one too', (
      tester,
    ) async {
      final env = await pumpSettingsApp(tester, location: '/settings/more');
      await _tap(tester, 'settings.server');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Cambiar de servidor'), findsOneWidget);
      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();
      env.router.go('/settings/capture');
      await tester.pumpAndSettle();
      await _tap(tester, 'settings.deleteVoice');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('¿Borrar los modelos de voz?'), findsOneWidget);
    });

    testWidgets('a toast is the web\'s: it says what happened, above the bottom bar', (
      tester,
    ) async {
      final env = await pumpSettingsApp(tester, location: '/settings/more');
      env.opener.works = false;
      await _tap(tester, 'settings.web');
      expect(find.byType(SnackBar), findsNothing);
      final toast = tester.getRect(find.text('No pudimos abrir el navegador.'));
      final bar = tester.getRect(find.byKey(const Key('home.add')));
      expect(toast.bottom, lessThan(bar.top), reason: 'the toast sits above the ＋ and the bar');
    });
  });

  group('the phone\'s font size', () {
    for (final guest in [false, true]) {
      testWidgets('at text scale 1.3 settings has no overflow${guest ? ', for a guest' : ''}', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpSettingsApp(tester, guest: guest, location: '/settings');
        tester.view
          ..physicalSize = const Size(360, 640)
          ..devicePixelRatio = 1;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Down the whole page: every card, its buttons and its switches, with the long labels.
        final page = find.byType(Scrollable).first;
        for (var i = 0; i < 40; i++) {
          await tester.drag(page, const Offset(0, -300));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'after $i drags');
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // The last button is reachable and not clipped by the bar.
        final signOut = tester.getRect(find.byKey(const Key('settings.signOut')));
        expect(signOut.bottom, lessThanOrEqualTo(640));
        expect(signOut.height, greaterThanOrEqualTo(44));
      });
    }

    testWidgets('at text scale 1.3 the sheets have no overflow either', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final env = await pumpSettingsApp(tester, guest: true, location: '/settings');
      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1;
      await tester.pumpAndSettle();
      await _tap(tester, 'settings.signOut');
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('guest.saveInstead')), findsOneWidget);
      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();
      env.router.go('/settings/more');
      await tester.pumpAndSettle();
      await _tap(tester, 'settings.server');
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('settings.server.change')), findsOneWidget);
    });
  });

  group('opening Settings', () {
    testWidgets(
      'home\'s face button opens a menu with Ajustes; a guest also sees Guarda tu progreso',
      (tester) async {
        await pumpSettingsApp(tester, guest: true);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byKey(const Key('home.settings')), findsNothing, reason: 'the menu is closed');
        await openAccountMenu(tester);
        expect(find.byKey(const Key('home.saveProgress')), findsOneWidget);

        await tester.tap(find.byKey(const Key('home.settings')));
        await tester.pumpAndSettle();
        expect(find.text('Ajustes'), findsWidgets);
        expect(find.byKey(const Key('settings.menu.preferences')), findsOneWidget);
      },
    );

    testWidgets('a preview guest\'s home menu offers Crear tu cuenta first, to /progress', (
      tester,
    ) async {
      await pumpSettingsApp(
        tester,
        guest: true,
        overrides: [isPreviewProvider.overrideWithValue(true)],
      );
      await openAccountMenu(tester);
      expect(find.byKey(const Key('home.saveProgress')), findsNothing);
      final create = find.byKey(const Key('home.createAccount'));
      expect(find.descendant(of: create, matching: find.text('Crear tu cuenta')), findsOneWidget);
      expect(
        tester.getTopLeft(create).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('home.recurring'))).dy),
      );
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('progress.email')), findsOneWidget, reason: '/progress');
    });

    testWidgets('someone with an email sees no Guarda tu progreso anywhere', (tester) async {
      await pumpSettingsApp(tester);
      await openAccountMenu(tester);
      expect(find.byKey(const Key('home.settings')), findsOneWidget);
      expect(find.byKey(const Key('home.saveProgress')), findsNothing);
      expect(find.byKey(const Key('home.createAccount')), findsNothing);

      await tester.tap(find.byKey(const Key('home.settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings.saveProgress')), findsNothing);
      expect(find.text('Guarda tu progreso'), findsNothing);
    });

    testWidgets('a guest\'s Settings offers Guarda tu progreso at the top', (tester) async {
      await pumpSettingsApp(tester, guest: true, location: '/settings');
      expect(find.text('Estás usando Wambito sin correo.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings.saveProgress')));
      await tester.pumpAndSettle();
      expect(find.text(_honestEs), findsOneWidget);
    });

    testWidgets('a plain guest still sees Guarda tu progreso and no Protect block', (tester) async {
      await pumpSettingsApp(tester, guest: true, location: '/settings');
      expect(find.byKey(const Key('settings.saveProgress')), findsOneWidget);
      expect(find.byKey(const Key('protect.block')), findsNothing);
    });

    testWidgets('a preview guest sees Protect your data at the top instead of Guarda tu progreso', (
      tester,
    ) async {
      await pumpSettingsApp(
        tester,
        guest: true,
        location: '/settings',
        overrides: [
          isPreviewProvider.overrideWithValue(true),
          securityApiProvider.overrideWithValue(FakeSecurity()),
          protectStatusProvider.overrideWith(
            (ref) async => const ProtectStatus(
              recoveryKey: false,
              passkey: false,
              passkeyOffered: true,
              passkeyWithoutPrf: false,
            ),
          ),
        ],
      );
      expect(find.byKey(const Key('protect.block')), findsOneWidget);
      expect(find.byKey(const Key('protect.recovery')), findsOneWidget);
      expect(find.byKey(const Key('settings.saveProgress')), findsNothing);
    });

    testWidgets('in English', (tester) async {
      await pumpSettingsApp(tester, locale: const Locale('en'), location: '/settings/preferences');
      expect(find.text('SETTINGS'), findsWidgets);
      expect(find.text('Sound'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('settings.vibration')),
          matching: find.text('Vibration'),
        ),
        findsOneWidget,
      );
    });
  });

  group('sound, vibration, notices and the widget', () {
    testWidgets('sounds and vibration start on, and each switch is its own setting', (
      tester,
    ) async {
      final env = await pumpSettingsApp(tester, location: '/settings/preferences');
      expect(
        tester
            .widget<LkSwitch>(
              find.descendant(
                of: find.byKey(const Key('settings.sound')),
                matching: find.byType(LkSwitch),
              ),
            )
            .value,
        isTrue,
      );

      await tester.tap(find.byKey(const Key('settings.sound')));
      await tester.pumpAndSettle();
      expect(env.container.read(soundEnabledProvider), isFalse);
      expect(env.container.read(vibrationEnabledProvider), isTrue);
      expect(env.flags['setting.sound']?.value, isFalse);

      await _tap(tester, 'settings.vibration');
      expect(env.container.read(vibrationEnabledProvider), isFalse);
      expect(env.flags['setting.vibration']?.value, isFalse);
    });

    testWidgets('the due notice hint gives the exact hour on Android', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSettingsApp(tester, location: '/settings/capture');
      await _scrollTo(tester, 'settings.dueNotice');
      expect(
        tester.getSemantics(find.byKey(const Key('settings.dueNotice'))).hint,
        'A las 9:00, un aviso con los pagos recurrentes que vencen hoy.',
      );
      handle.dispose();
    });

    testWidgets('the due notice hint says around 9:00 on iOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final handle = tester.ensureSemantics();
        await pumpSettingsApp(tester, location: '/settings/capture');
        await _scrollTo(tester, 'settings.dueNotice');
        expect(
          tester.getSemantics(find.byKey(const Key('settings.dueNotice'))).hint,
          'Hacia las 9:00, un aviso con los pagos recurrentes que vencen hoy. '
          'iOS decide la hora exacta.',
        );
        handle.dispose();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('the widget\'s amount switch is Android\'s, and iOS has none', (tester) async {
      await pumpSettingsApp(tester, location: '/settings/capture');
      await _scrollTo(tester, 'settings.guestNotice');
      expect(find.byKey(const Key('settings.hideAmount')), findsOneWidget);
    });

    testWidgets('on iOS there is no widget setting', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpSettingsApp(tester, location: '/settings/capture');
        await _scrollTo(tester, 'settings.guestNotice');
        expect(find.byKey(const Key('settings.hideAmount')), findsNothing);
        expect(find.text('Ocultar el monto'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'a preview account has no switch for the 45-day guest warning, which it never gets',
      (tester) async {
        await pumpSettingsApp(
          tester,
          guest: true,
          location: '/settings/capture',
          overrides: [..._previewGuest(), isPreviewProvider.overrideWithValue(true)],
        );
        await _scrollTo(tester, 'settings.dueNotice');
        expect(find.byKey(const Key('settings.guestNotice')), findsNothing);
        expect(find.text('Si no tienes correo'), findsNothing);
      },
    );

    testWidgets('the two notices are on, and the widget\'s amount is shown, until chosen', (
      tester,
    ) async {
      final env = await pumpSettingsApp(tester, location: '/settings/capture');
      expect(env.container.read(dueNoticeEnabledProvider), isTrue);
      expect(env.container.read(guestNoticeEnabledProvider), isTrue);
      expect(env.container.read(hideWidgetAmountProvider), isFalse);

      await _tap(tester, 'settings.dueNotice');
      await _tap(tester, 'settings.guestNotice');
      await _tap(tester, 'settings.hideAmount');

      expect(env.container.read(dueNoticeEnabledProvider), isFalse);
      expect(env.container.read(guestNoticeEnabledProvider), isFalse);
      expect(env.container.read(hideWidgetAmountProvider), isTrue);
      expect(env.flags['setting.notice.due']?.value, isFalse);
      expect(env.flags['setting.notice.guest']?.value, isFalse);
      expect(env.flags['setting.widget.hideAmount']?.value, isTrue);
    });
  });

  group('theme and language', () {
    testWidgets('night is the default; Day and System can be picked, and the choice is kept', (
      tester,
    ) async {
      final env = await pumpSettingsApp(tester, location: '/settings/preferences');
      MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app().themeMode, ThemeMode.dark);
      expect(app().locale, isNull);

      await _tap(tester, 'settings.theme');
      await tester.tap(find.byKey(const Key('settings.theme.day')));
      await tester.pumpAndSettle();
      expect(app().themeMode, ThemeMode.light);
      expect(env.settings.values['setting.theme'], 'light');

      await _tap(tester, 'settings.theme');
      await tester.tap(find.byKey(const Key('settings.theme.system')));
      await tester.pumpAndSettle();
      expect(app().themeMode, ThemeMode.system);
      expect(env.settings.values['setting.theme'], 'system');

      await _tap(tester, 'settings.theme');
      await tester.tap(find.byKey(const Key('settings.theme.night')));
      await tester.pumpAndSettle();
      expect(app().themeMode, ThemeMode.dark);
      expect(env.settings.values['setting.theme'], 'dark');
    });

    testWidgets('picking English changes every word at once; Automático goes back to the phone', (
      tester,
    ) async {
      final env = await pumpSettingsApp(tester, location: '/settings/preferences');
      expect(find.text('AJUSTES'), findsWidgets);

      await _tap(tester, 'settings.language');
      await tester.tap(find.byKey(const Key('settings.language.en')));
      await tester.pumpAndSettle();
      expect(find.text('SETTINGS'), findsWidgets);
      expect(find.text('AJUSTES'), findsNothing);
      expect(env.settings.values['setting.locale'], 'en');

      await _tap(tester, 'settings.language');
      await tester.tap(find.byKey(const Key('settings.language.auto')));
      await tester.pumpAndSettle();
      expect(find.text('AJUSTES'), findsWidgets);
      expect(env.settings.values.containsKey('setting.locale'), isFalse);
    });
  });

  group('the four languages', () {
    testWidgets('the picker lists Español, English, Italiano and Português by their own names', (
      tester,
    ) async {
      await pumpSettingsApp(tester, location: '/settings/preferences');
      await _tap(tester, 'settings.language');
      for (final (key, name) in [
        ('es', 'Español'),
        ('en', 'English'),
        ('it', 'Italiano'),
        ('pt', 'Português'),
      ]) {
        expect(find.text(name), findsOneWidget);
        expect(find.byKey(Key('settings.language.$key')), findsOneWidget);
      }
    });

    for (final (code, settings, web) in [
      ('it', 'IMPOSTAZIONI', '/it'),
      ('pt', 'DEFINIÇÕES', '/pt'),
    ]) {
      testWidgets('picking $code changes every word at once and is kept', (tester) async {
        final env = await pumpSettingsApp(tester, location: '/settings/preferences');
        await _tap(tester, 'settings.language');
        await tester.tap(find.byKey(Key('settings.language.$code')));
        await tester.pumpAndSettle();
        expect(find.text(settings), findsWidgets);
        expect(find.text('AJUSTES'), findsNothing);
        expect(env.settings.values['setting.locale'], code);
        expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).locale, Locale(code));
      });

      testWidgets('in $code the web links are the $web landing and roadmap', (tester) async {
        final env = await pumpSettingsApp(tester, location: '/settings/preferences');
        await _tap(tester, 'settings.language');
        await tester.tap(find.byKey(Key('settings.language.$code')));
        await tester.pumpAndSettle();
        env.router.go('/settings/more');
        await tester.pumpAndSettle();
        await _tap(tester, 'settings.web');
        await _tap(tester, 'settings.roadmap');
        expect(env.opener.opened, [
          defaultServerUrl.resolve(web),
          defaultServerUrl.resolve('$web/roadmap'),
        ]);
      });
    }
  });

  group('sign out', () {
    testWidgets('someone with an email signs out at once and lands on the first screen', (
      tester,
    ) async {
      final env = await pumpSettingsApp(tester, location: '/settings');
      await _tap(tester, 'settings.signOut');

      expect(env.auth.calls, contains('signOut email-token-0'));
      expect(env.container.read(sessionProvider).status, SessionStatus.signedOut);
      expect(find.byType(EntryScreen), findsOneWidget);
    });

    testWidgets('a guest is warned first, with the honest copy, and cancelling changes nothing', (
      tester,
    ) async {
      final env = await pumpSettingsApp(tester, guest: true, location: '/settings');
      await _tap(tester, 'settings.signOut');

      expect(find.text('¿Cerrar sesión sin guardar tu progreso?'), findsOneWidget);
      expect(find.textContaining(_honestEs), findsOneWidget);
      expect(env.auth.calls.where((c) => c.startsWith('signOut')), isEmpty);

      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();
      expect(env.container.read(sessionProvider).status, SessionStatus.signedIn);
      expect(env.stored?.guest, isTrue);
      expect(find.byType(EntryScreen), findsNothing);
    });

    testWidgets('the warning in English says it too', (tester) async {
      await pumpSettingsApp(tester, guest: true, locale: const Locale('en'), location: '/settings');
      await _tap(tester, 'settings.signOut');
      expect(find.text('Sign out without saving your progress?'), findsOneWidget);
      expect(find.textContaining(_honestEn), findsOneWidget);
    });

    testWidgets('a guest who goes ahead anyway is signed out, and everything on the phone goes', (
      tester,
    ) async {
      final env = await pumpSettingsApp(tester, guest: true, location: '/settings');
      await _tap(tester, 'settings.signOut');
      await tester.tap(find.byKey(const Key('guest.signOutConfirm')));
      await tester.pumpAndSettle();

      expect(env.auth.calls, contains('signOut guest-token-0'));
      expect(env.container.read(sessionProvider).status, SessionStatus.signedOut);
      expect(await SessionStore().read(), isNull);
      expect(find.byType(EntryScreen), findsOneWidget);
    });

    testWidgets('the warning offers Guarda tu progreso instead, and signs nobody out', (
      tester,
    ) async {
      final env = await pumpSettingsApp(tester, guest: true, location: '/settings');
      await _tap(tester, 'settings.signOut');
      await tester.tap(find.byKey(const Key('guest.saveInstead')));
      await tester.pumpAndSettle();

      expect(env.auth.calls.where((c) => c.startsWith('signOut')), isEmpty);
      expect(env.container.read(sessionProvider).status, SessionStatus.signedIn);
      expect(find.byKey(const Key('progress.email')), findsOneWidget);
    });

    testWidgets(
      'an unprotected preview guest signing out is warned and Protect first opens the key',
      (tester) async {
        final vault = FakeVault();
        await tester.runAsync(() => vault.seeded);
        final env = await pumpSettingsApp(
          tester,
          guest: true,
          location: '/settings',
          locale: const Locale('en'),
          overrides: [..._previewGuest(), vaultSessionProvider.overrideWithValue(vault)],
        );
        await _tap(tester, 'settings.signOut');

        expect(find.text('Sign out with no way back?'), findsOneWidget);
        expect(find.byKey(const Key('guest.saveInstead')), findsNothing);
        // The passkey state is known: no note about it.
        expect(find.textContaining('could not check your passkeys'), findsNothing);
        expect(env.auth.calls.where((c) => c.startsWith('signOut')), isEmpty);

        await tester.tap(find.byKey(const Key('unprotected.protectFirst')));
        await tester.pumpAndSettle();
        expect(find.byType(RecoveryKeySetupView), findsOneWidget);
        expect(env.auth.calls.where((c) => c.startsWith('signOut')), isEmpty);
        expect(env.container.read(sessionProvider).status, SessionStatus.signedIn);
      },
    );

    testWidgets(
      'offline, the warning says it could not check the passkeys instead of claiming none',
      (tester) async {
        await pumpSettingsApp(
          tester,
          guest: true,
          location: '/settings',
          locale: const Locale('en'),
          overrides: _previewGuest(passkeyReadable: false),
        );
        await _tap(tester, 'settings.signOut');
        expect(find.text('Sign out with no way back?'), findsOneWidget);
        expect(find.textContaining('could not check your passkeys'), findsOneWidget);
      },
    );

    testWidgets('an unprotected preview guest who leaves anyway is signed out', (tester) async {
      final env = await pumpSettingsApp(
        tester,
        guest: true,
        location: '/settings',
        overrides: _previewGuest(),
      );
      await _tap(tester, 'settings.signOut');
      await tester.tap(find.byKey(const Key('unprotected.signOutConfirm')));
      await tester.pumpAndSettle();
      expect(env.container.read(sessionProvider).status, SessionStatus.signedOut);
    });

    testWidgets('a protected preview guest signs out without the warning', (tester) async {
      for (final overrides in [_previewGuest(recoveryKey: true), _previewGuest(passkey: true)]) {
        final env = await pumpSettingsApp(
          tester,
          guest: true,
          location: '/settings',
          overrides: overrides,
        );
        await _tap(tester, 'settings.signOut');
        expect(find.byKey(const Key('unprotected.protectFirst')), findsNothing);
        expect(find.byKey(const Key('guest.saveInstead')), findsNothing);
        expect(env.container.read(sessionProvider).status, SessionStatus.signedOut);
      }
    });

    testWidgets('a plain guest still gets warnGuestLeaving', (tester) async {
      await pumpSettingsApp(tester, guest: true, location: '/settings');
      await _tap(tester, 'settings.signOut');
      expect(find.byKey(const Key('guest.saveInstead')), findsOneWidget);
      expect(find.byKey(const Key('unprotected.protectFirst')), findsNothing);
    });
  });

  group('the server URL', () {
    testWidgets('it shows the current server, and an invalid address is refused in the dialog', (
      tester,
    ) async {
      final env = await pumpSettingsApp(tester, location: '/settings/more');
      await _scrollTo(tester, 'settings.server');
      expect(find.text('https://app.wambito.com'), findsOneWidget);

      await _tap(tester, 'settings.server');
      await tester.enterText(find.byKey(const Key('settings.server.field')), 'http://example.com');
      await tester.tap(find.byKey(const Key('settings.server.change')));
      await tester.pumpAndSettle();

      expect(find.textContaining('empiece por https://'), findsOneWidget);
      expect(env.container.read(serverUrlProvider), defaultServerUrl);
      expect(env.container.read(sessionProvider).status, SessionStatus.signedIn);
    });

    testWidgets('changing it signs out and points every call there', (tester) async {
      final env = await pumpSettingsApp(tester, location: '/settings/more');
      await _tap(tester, 'settings.server');
      await tester.enterText(
        find.byKey(const Key('settings.server.field')),
        'https://my.server.org',
      );
      await tester.tap(find.byKey(const Key('settings.server.change')));
      await tester.pumpAndSettle();

      expect(env.container.read(serverUrlProvider).toString(), 'https://my.server.org');
      expect(env.container.read(sessionProvider).status, SessionStatus.signedOut);
      expect(env.settings.values['setting.server'], 'https://my.server.org');
      expect(find.byType(EntryScreen), findsOneWidget);
    });

    testWidgets('a preview account with changes not synced is asked first, as at a sign-out', (
      tester,
    ) async {
      final env = await pumpSettingsApp(
        tester,
        location: '/settings/more',
        overrides: [vaultSessionProvider.overrideWithValue(_Unsynced(2))],
      );
      Future<void> change() async {
        await _tap(tester, 'settings.server');
        await tester.enterText(
          find.byKey(const Key('settings.server.field')),
          'https://my.server.org',
        );
        await tester.tap(find.byKey(const Key('settings.server.change')));
        await tester.pumpAndSettle();
      }

      await change();
      expect(find.text('Tienes 2 cambios sin sincronizar'), findsOneWidget);
      // Backing out keeps the server, the session and the vault.
      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();
      expect(env.container.read(serverUrlProvider), defaultServerUrl);
      expect(env.container.read(sessionProvider).status, SessionStatus.signedIn);

      await change();
      await tester.tap(find.byKey(const Key('vault.signOutAnyway')));
      await tester.pumpAndSettle();
      expect(env.container.read(serverUrlProvider).toString(), 'https://my.server.org');
      expect(env.container.read(sessionProvider).status, SessionStatus.signedOut);
    });

    testWidgets('the dev stack\'s http address is accepted', (tester) async {
      final env = await pumpSettingsApp(tester, location: '/settings/more');
      await _tap(tester, 'settings.server');
      await tester.enterText(
        find.byKey(const Key('settings.server.field')),
        'http://10.0.2.2:3000',
      );
      await tester.tap(find.byKey(const Key('settings.server.change')));
      await tester.pumpAndSettle();
      expect(env.container.read(serverUrlProvider).toString(), 'http://10.0.2.2:3000');
    });

    testWidgets('a guest is warned before the server changes; cancelling keeps everything', (
      tester,
    ) async {
      final env = await pumpSettingsApp(tester, guest: true, location: '/settings/more');
      await _tap(tester, 'settings.server');
      await tester.enterText(
        find.byKey(const Key('settings.server.field')),
        'https://my.server.org',
      );
      await tester.tap(find.byKey(const Key('settings.server.change')));
      await tester.pumpAndSettle();

      expect(find.text('¿Cambiar de servidor sin guardar tu progreso?'), findsOneWidget);
      expect(find.textContaining(_honestEs), findsOneWidget);

      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();
      expect(env.container.read(serverUrlProvider), defaultServerUrl);
      expect(env.container.read(sessionProvider).status, SessionStatus.signedIn);
    });

    testWidgets('a guest who goes ahead anyway moves to the new server, signed out', (
      tester,
    ) async {
      final env = await pumpSettingsApp(tester, guest: true, location: '/settings/more');
      await _tap(tester, 'settings.server');
      await tester.enterText(
        find.byKey(const Key('settings.server.field')),
        'https://my.server.org',
      );
      await tester.tap(find.byKey(const Key('settings.server.change')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guest.serverConfirm')));
      await tester.pumpAndSettle();

      expect(env.container.read(serverUrlProvider).toString(), 'https://my.server.org');
      expect(env.container.read(sessionProvider).status, SessionStatus.signedOut);
    });

    testWidgets('changing server warns the same', (tester) async {
      final env = await pumpSettingsApp(
        tester,
        guest: true,
        location: '/settings/more',
        locale: const Locale('en'),
        overrides: _previewGuest(),
      );
      await _changeServerTo(tester, 'https://my.server.org');
      expect(find.text('Change server with no way back?'), findsOneWidget);
      expect(find.byKey(const Key('guest.saveInstead')), findsNothing);

      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(env.container.read(serverUrlProvider), defaultServerUrl);

      await _changeServerTo(tester, 'https://my.server.org');
      await tester.tap(find.byKey(const Key('unprotected.serverConfirm')));
      await tester.pumpAndSettle();
      expect(env.container.read(serverUrlProvider).toString(), 'https://my.server.org');
      expect(env.container.read(sessionProvider).status, SessionStatus.signedOut);
    });

    testWidgets('a protected preview guest changes server without the warning', (tester) async {
      final env = await pumpSettingsApp(
        tester,
        guest: true,
        location: '/settings/more',
        overrides: _previewGuest(passkey: true),
      );
      await _changeServerTo(tester, 'https://my.server.org');
      expect(find.byKey(const Key('unprotected.protectFirst')), findsNothing);
      expect(env.container.read(serverUrlProvider).toString(), 'https://my.server.org');
    });

    testWidgets('"Usar el de Wambito" puts the default address back in the field', (tester) async {
      await pumpSettingsApp(tester, location: '/settings/more');
      await _tap(tester, 'settings.server');
      await tester.enterText(find.byKey(const Key('settings.server.field')), 'https://x.org');
      await tester.tap(find.byKey(const Key('settings.server.default')));
      await tester.pumpAndSettle();
      final field = tester.widget<EditableText>(find.byKey(const Key('settings.server.field')));
      expect(field.controller.text, defaultServerUrl.toString());
    });
  });

  group('Más en la web', () {
    testWidgets('opens the web app at the current server in the browser', (tester) async {
      final env = await pumpSettingsApp(tester, location: '/settings/more');
      await _tap(tester, 'settings.web');
      expect(env.opener.opened, [defaultServerUrl]);
    });

    testWidgets('it says so when there is no browser', (tester) async {
      final env = await pumpSettingsApp(tester, location: '/settings/more');
      env.opener.works = false;
      await _tap(tester, 'settings.web');
      expect(find.text('No pudimos abrir el navegador.'), findsOneWidget);
    });
  });

  group('the precise voice model', () {
    bool switchOn(WidgetTester tester) => tester
        .widget<LkSwitch>(
          find.descendant(
            of: find.byKey(const Key('settings.voicePrecise')),
            matching: find.byType(LkSwitch),
          ),
        )
        .value;

    testWidgets('a phone that does not qualify has no switch', (tester) async {
      await pumpSettingsApp(tester, location: '/settings/capture');
      expect(find.byKey(const Key('settings.voicePrecise')), findsNothing);
    });

    testWidgets('on iOS the voice model row covers it: no precise switch', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpSettingsApp(tester, location: '/settings/capture', preciseEligible: true);
      await _scrollTo(tester, 'settings.guestNotice');
      expect(find.byKey(const Key('settings.voicePrecise')), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('the switch names the size, and turning it on downloads canary only', (
      tester,
    ) async {
      final env = await pumpSettingsApp(
        tester,
        location: '/settings/capture',
        preciseEligible: true,
      );
      await _scrollTo(tester, 'settings.voicePrecise');
      expect(find.text('Mejorar la precisión'), findsOneWidget);
      expect(find.text('+150 MB · corrige al terminar de hablar'), findsOneWidget);
      expect(switchOn(tester), isFalse);
      await tester.tap(find.byKey(const Key('settings.voicePrecise')));
      await tester.pumpAndSettle();
      expect(env.precise.downloaded, ['es']);
      expect(env.models.downloads, 0);
      expect(switchOn(tester), isTrue);
      expect(env.flags['wambito.voice.preciseOffer']?.value, isTrue);
    });

    testWidgets('leaving Settings during the download throws nothing', (tester) async {
      final env = await pumpSettingsApp(
        tester,
        location: '/settings/capture',
        preciseEligible: true,
      );
      env.precise.gate = Completer<void>();
      await _scrollTo(tester, 'settings.voicePrecise');
      await tester.tap(find.byKey(const Key('settings.voicePrecise')));
      await tester.pump(const Duration(milliseconds: 100));
      env.router.go('/');
      await tester.pumpAndSettle();
      env.precise.gate!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('on when installed; turning it off deletes only canary', (tester) async {
      final env = await pumpSettingsApp(
        tester,
        location: '/settings/capture',
        preciseEligible: true,
        preciseInstalled: true,
      );
      await _scrollTo(tester, 'settings.voicePrecise');
      expect(switchOn(tester), isTrue);
      await tester.tap(find.byKey(const Key('settings.voicePrecise')));
      await tester.pumpAndSettle();
      expect(env.precise.deletedOne, ['es']);
      expect(env.precise.deletes, 0);
      expect(env.models.deletes, 0);
      expect(env.models.installed, isTrue, reason: 'vosk stays');
      expect(switchOn(tester), isFalse);
      expect(env.flags['wambito.voice.preciseOffer']?.value, isFalse, reason: 'no offer after off');
    });

    testWidgets('a download that fails says so and leaves the switch off', (tester) async {
      final env = await pumpSettingsApp(
        tester,
        location: '/settings/capture',
        preciseEligible: true,
      );
      env.precise.failure = const ModelDownloadFailure();
      await _scrollTo(tester, 'settings.voicePrecise');
      await tester.tap(find.byKey(const Key('settings.voicePrecise')));
      await tester.pumpAndSettle();
      expect(
        find.text('No pudimos descargar el modelo preciso. Inténtalo otra vez.'),
        findsOneWidget,
      );
      expect(switchOn(tester), isFalse);
    });
  });

  group('the voice models', () {
    testWidgets('a button deletes them, after asking', (tester) async {
      final env = await pumpSettingsApp(tester, location: '/settings/capture');
      await _tap(tester, 'settings.deleteVoice');
      expect(find.text('¿Borrar los modelos de voz?'), findsOneWidget);
      expect(env.models.deletes, 0);

      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();
      expect(env.models.deletes, 0);

      await tester.tap(find.byKey(const Key('settings.deleteVoice')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings.deleteVoice.confirm')));
      await tester.pumpAndSettle();
      expect(env.models.deletes, 1);
      expect(find.text('Listo: borramos los modelos de voz.'), findsOneWidget);
      expect(
        find.byKey(const Key('settings.deleteVoice')),
        findsNothing,
        reason: 'nothing left to delete',
      );
    });

    testWidgets('with no model downloaded, there is nothing to delete', (tester) async {
      final env = await pumpSettingsApp(
        tester,
        location: '/settings/capture',
        modelsInstalled: false,
      );
      expect(env.models.installed, isFalse);
      expect(find.byKey(const Key('settings.deleteVoice')), findsNothing);
    });

    testWidgets('a failed delete says so', (tester) async {
      final env = await pumpSettingsApp(tester, location: '/settings/capture');
      env.models.deleteFailure = StateError('disk');
      await _tap(tester, 'settings.deleteVoice');
      await tester.tap(find.byKey(const Key('settings.deleteVoice.confirm')));
      await tester.pumpAndSettle();
      expect(
        find.text('No pudimos borrar los modelos de voz. Inténtalo otra vez.'),
        findsOneWidget,
      );
    });
  });

  group('Debug tools', () {
    testWidgets('the PRF probe row is there with the debug flag on', (tester) async {
      await pumpSettingsApp(
        tester,
        location: '/settings/more',
        overrides: [debugToolsProvider.overrideWithValue(true)],
      );
      await tester.scrollUntilVisible(find.byKey(const Key('settings.prfProbe')), 200);
      expect(find.byKey(const Key('settings.prfProbe')), findsOneWidget);
    });

    testWidgets('and not with it off', (tester) async {
      await pumpSettingsApp(tester, location: '/settings/more');
      expect(find.byKey(const Key('settings.prfProbe'), skipOffstage: false), findsNothing);
    });
  });

  group('About', () {
    testWidgets('About lists every dependency\'s licence and the model\'s', (tester) async {
      await pumpSettingsApp(tester, location: '/settings/more');
      await _tap(tester, 'settings.about');
      expect(find.text('Acerca de Wambito'), findsOneWidget);
      expect(find.textContaining('AGPL-3.0'), findsOneWidget);

      await tester.tap(find.byKey(const Key('about.licenses')));
      await tester.pumpAndSettle();

      // Flutter's own page lists the packages of the registry; the app's extras are in it: the
      // models, the speech engine, an Android library, the sounds.
      final list = find
          .descendant(of: find.byType(LicensePage), matching: find.byType(Scrollable))
          .first;
      for (final name in [
        'Wambito feedback sounds',
        'androidx.core:core 1.18.0',
        'vosk-android 0.3.75',
        'vosk-model-small-en-us-0.15',
        'vosk-model-small-es-0.42',
        'vosk-model-small-it-0.22',
        'vosk-model-small-pt-0.3',
      ]) {
        // From the top each time: the page's order is not alphabetical.
        await tester.fling(list, const Offset(0, 10000), 10000);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text(name), 100, scrollable: list, maxScrolls: 200);
        expect(find.text(name), findsOneWidget, reason: name);
      }
    });
  });
}

/// An open vault with [pending] changes not sent yet.
class _Unsynced extends Fake implements VaultSession {
  _Unsynced(this.pending);

  final int pending;

  @override
  String get userId => 'u1';

  @override
  LocalBackend get backend => createLocalBackend(store: createMemoryStore(), now: DateTime.now);

  @override
  void Function() subscribe(void Function() listener) => () {};

  @override
  Future<int> pendingChanges() async => pending;
}
