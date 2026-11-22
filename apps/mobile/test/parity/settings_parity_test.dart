@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/settings/settings_categories.dart';

import '../support/parity.dart';
import '../support/parity_settings.dart';

/// Settings against the stories that show it at rest, `settings-parity--*`
/// (apps/web/app/features/settings/SettingsParity.stories.tsx): the menu and each category the web
/// shares with the phone (Mis agentes, Cuenta y seguridad, Preferencias, Tus datos, Más), at night in
/// Spanish and by day in English. Italian and Portuguese are in `it_pt_parity_test.dart`.
///
/// The pairs draw what the web's stories draw (`webSectionsOnly`: no Captura on the menu, none of the
/// app's own rows). The app's own rows have goldens of their own in `test/settings/goldens`, to
/// review by eye.
///
/// The app reads who is signed in, and the assistants, from what the story's fake API answered
/// (test/parity/fixtures).
///
/// Update the goldens with `flutter test --update-goldens test/parity`, then compare with
/// `dart run tool/parity/compose.dart` (docs/mobile/parity.md).

Future<void> _pair(
  WidgetTester t, {
  required String id,
  required String story,
  required SettingsCategory? category,
  required String theme,
  Locale locale = const Locale('es'),
}) async {
  final fixture = ParityFixtures.load(story);
  await parityGolden(
    t,
    id,
    settingsParityPage(category),
    theme: theme,
    locale: locale,
    overrides: settingsParityOverrides(fixture, theme),
  );
}

// The ids are written out in full: test/parity/harness_test.dart looks for each one in its file.
void main() {
  testWidgets('settings parity: the menu (night)', (t) async {
    await _pair(
      t,
      id: 'settings-menu',
      story: 'settings-parity--menu-night',
      category: null,
      theme: 'night',
    );
  });

  testWidgets('settings parity: the menu, by day in English (day)', (t) async {
    await _pair(
      t,
      id: 'settings-menu-day-english',
      story: 'settings-parity--menu-day-english',
      category: null,
      theme: 'day',
      locale: const Locale('en'),
    );
  });

  testWidgets('settings parity: Mis agentes (night)', (t) async {
    await _pair(
      t,
      id: 'settings-agents',
      story: 'settings-parity--agents-night',
      category: SettingsCategory.agents,
      theme: 'night',
    );
  });

  testWidgets('settings parity: Mis agentes, by day in English (day)', (t) async {
    await _pair(
      t,
      id: 'settings-agents-day-english',
      story: 'settings-parity--agents-day-english',
      category: SettingsCategory.agents,
      theme: 'day',
      locale: const Locale('en'),
    );
  });

  testWidgets('settings parity: Cuenta y seguridad (night)', (t) async {
    await _pair(
      t,
      id: 'settings-account',
      story: 'settings-parity--account-night',
      category: SettingsCategory.account,
      theme: 'night',
    );
  });

  testWidgets('settings parity: Cuenta y seguridad, by day in English (day)', (t) async {
    await _pair(
      t,
      id: 'settings-account-day-english',
      story: 'settings-parity--account-day-english',
      category: SettingsCategory.account,
      theme: 'day',
      locale: const Locale('en'),
    );
  });

  testWidgets('settings parity: Preferencias (night)', (t) async {
    await _pair(
      t,
      id: 'settings-preferences',
      story: 'settings-parity--preferences-night',
      category: SettingsCategory.preferences,
      theme: 'night',
    );
  });

  testWidgets('settings parity: Preferencias, by day in English (day)', (t) async {
    await _pair(
      t,
      id: 'settings-preferences-day-english',
      story: 'settings-parity--preferences-day-english',
      category: SettingsCategory.preferences,
      theme: 'day',
      locale: const Locale('en'),
    );
  });

  testWidgets('settings parity: Tus datos (night)', (t) async {
    await _pair(
      t,
      id: 'settings-data',
      story: 'settings-parity--data-night',
      category: SettingsCategory.data,
      theme: 'night',
    );
  });

  testWidgets('settings parity: Tus datos, by day in English (day)', (t) async {
    await _pair(
      t,
      id: 'settings-data-day-english',
      story: 'settings-parity--data-day-english',
      category: SettingsCategory.data,
      theme: 'day',
      locale: const Locale('en'),
    );
  });

  testWidgets('settings parity: Más (night)', (t) async {
    await _pair(
      t,
      id: 'settings-more',
      story: 'settings-parity--more-night',
      category: SettingsCategory.more,
      theme: 'night',
    );
  });

  testWidgets('settings parity: Más, by day in English (day)', (t) async {
    await _pair(
      t,
      id: 'settings-more-day-english',
      story: 'settings-parity--more-day-english',
      category: SettingsCategory.more,
      theme: 'day',
      locale: const Locale('en'),
    );
  });
}
