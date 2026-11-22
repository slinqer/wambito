@Tags(['golden'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/app.dart';
import 'package:wambito/capture/models_download.dart';
import 'package:wambito/entry/guest_dialogs.dart';
import 'package:wambito/feedback/stored_flag.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/l10n/app_localizations.dart';
import 'package:wambito/settings/assistants_repository.dart';
import 'package:wambito/settings/category_cards.dart';
import 'package:wambito/settings/settings_categories.dart';
import 'package:wambito/settings/settings_screen.dart';
import 'package:wambito/settings/server_status.dart';

import '../entry/fakes.dart';
import '../home/fakes.dart';
import '../support/parity.dart';
import 'fakes.dart';
import 'harness.dart' show DeletableModelStore;

/// What Settings has that the web's has not, to review by eye: the menu with Captura, the guest's
/// "Guarda tu progreso", signing out and the version; the Captura page (the phone's own switches,
/// the voice models, the notices, the widget); Más with the server, the roadmap, the web and About;
/// Preferencias with vibration and "Automático". They are drawn with the web's parts
/// (`SettingsGroup`, `SettingsRow`, `PressButton`), so the web has no story of them and the parity
/// pairs (`settings-*` in test/parity) leave them out. The sheets the guest dialogs became (the
/// sign-out warning, the claim offer), the server's sheet and the voice models' question are here
/// too.
///
/// The goldens are the Mac's pixels, tagged `golden`; update them with
/// `flutter test --update-goldens test/settings/settings_golden_test.dart`.

/// A page taller than a phone, so one picture shows all of it.
const _page = Size(412, 1600);

List<Override> _overrides({required bool guest}) {
  final token = guest ? 'guest-token-0' : 'email-token-0';
  mockStorage(token: token, guest: guest);
  final auth = FakeAuthApi()..guests[token] = guest;
  return [
    toastBarAnimatesProvider.overrideWithValue(false),
    serverHealthCheckProvider.overrideWithValue(
      (server) async => const ServerHealth(online: true, version: '0.0.0-dev.abc1234'),
    ),
    serverDotPulsesProvider.overrideWithValue(false),
    authApiProvider.overrideWithValue(auth),
    homeRepositoryProvider.overrideWithValue(FakeHomeRepository()),
    flagStoreProvider.overrideWith((ref, key) => FakeFlagStore()),
    modelStoreProvider.overrideWithValue(DeletableModelStore()),
    assistantsRepositoryProvider.overrideWithValue(FakeAssistantsRepository()),
  ];
}

Future<void> _golden(
  WidgetTester t,
  String name,
  String theme, {
  required bool guest,
  Size size = _page,
  double textScale = 1,
  SettingsCategory? category,
  Future<void> Function(WidgetTester t)? act,
}) async {
  await t.runAsync(loadParityFonts);
  if (textScale != 1) {
    t.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  }
  t.view
    ..physicalSize = size * parityPixelRatio
    ..devicePixelRatio = parityPixelRatio;
  addTearDown(t.view.reset);
  debugDisableShadows = false;
  try {
    await t.pumpWidget(
      ProviderScope(
        overrides: _overrides(guest: guest),
        child: MaterialApp(
          theme: parityTheme(theme),
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          debugShowCheckedModeBanner: false,
          builder: (context, child) => withAppHosts(child!, animateToastBar: false),
          home: category == null
              ? const SettingsScreen()
              : SettingsCategoryScreen(category: category),
        ),
      ),
    );
    await t.pumpAndSettle();
    if (act != null) {
      await act(t);
      await t.pumpAndSettle();
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        Uri.file('${Directory.current.path}/test/settings/goldens/${name}_$theme.png'),
      ),
    );
  } finally {
    debugDisableShadows = true;
  }
}

void main() {
  for (final theme in ['night', 'day']) {
    testWidgets('the menu, a guest: Guarda tu progreso, Captura, signing out ($theme)', (t) async {
      await _golden(t, 'settings_guest', theme, guest: true);
    });

    testWidgets('the menu, with an email ($theme)', (t) async {
      await _golden(t, 'settings_email', theme, guest: false);
    });

    testWidgets('Captura: the phone\'s own switches and the voice models ($theme)', (t) async {
      await _golden(t, 'settings_capture', theme, guest: false, category: SettingsCategory.capture);
    });

    testWidgets('Más: the server, the roadmap, the web and About ($theme)', (t) async {
      await _golden(t, 'settings_more', theme, guest: false, category: SettingsCategory.more);
    });

    // The phone's font at 130 %: Idioma keeps "Automático" whole, on one line.
    testWidgets('Preferencias at text scale 1.3 ($theme)', (t) async {
      await _golden(
        t,
        'settings_preferences_scale_1_3',
        theme,
        guest: false,
        size: parityViewSize,
        textScale: 1.3,
        category: SettingsCategory.preferences,
      );
      final words = find.text('Automático');
      expect(words, findsWidgets);
      for (final word in words.evaluate()) {
        final paragraph = word.renderObject! as RenderParagraph;
        expect(
          paragraph
              .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 10))
              .length,
          1,
        );
        expect(paragraph.size.height, lessThan(30));
      }
    });

    testWidgets('the server\'s sheet ($theme)', (t) async {
      await _golden(
        t,
        'server_sheet',
        theme,
        guest: false,
        size: parityViewSize,
        category: SettingsCategory.more,
        act: (t) async {
          await t.scrollUntilVisible(find.byKey(const Key('settings.server')), 200);
          await t.tap(find.byKey(const Key('settings.server')));
          await t.pumpAndSettle();
        },
      );
    });

    testWidgets('the voice models\' question ($theme)', (t) async {
      await _golden(
        t,
        'voice_sheet',
        theme,
        guest: false,
        size: parityViewSize,
        category: SettingsCategory.capture,
        act: (t) async {
          await t.scrollUntilVisible(find.byKey(const Key('settings.deleteVoice')), 200);
          await t.tap(find.byKey(const Key('settings.deleteVoice')));
          await t.pumpAndSettle();
        },
      );
    });

    testWidgets('the guest\'s warning before signing out ($theme)', (t) async {
      await _golden(
        t,
        'guest_signout_sheet',
        theme,
        guest: true,
        size: parityViewSize,
        act: (t) async {
          await t.scrollUntilVisible(find.byKey(const Key('settings.signOut')), 300);
          await t.tap(find.byKey(const Key('settings.signOut')));
          await t.pumpAndSettle();
        },
      );
    });
  }

  // The claim offer (a guest who typed an email) is asked from the email screen: here it opens
  // over Settings' menu to be drawn.
  for (final theme in ['night', 'day']) {
    testWidgets('the guest\'s offer to save their progress ($theme)', (t) async {
      await _golden(
        t,
        'guest_claim_sheet',
        theme,
        guest: true,
        size: parityViewSize,
        act: (t) async {
          final context = t.element(find.byType(SettingsScreen));
          // Not awaited: the sheet stays open for the picture.
          unawaited(askGuestChoice(context, 'ana@correo.com'));
          await t.pumpAndSettle();
        },
      );
    });
  }
}
