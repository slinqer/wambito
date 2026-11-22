@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/settings/settings_categories.dart';
import 'package:wambito/ui/app_shell.dart';

import '../support/parity.dart';
import '../support/parity_home.dart';
import '../support/parity_settings.dart';

/// Italian and European Portuguese, at night, against the stories that show them
/// (`home-home--transactions-italian|portuguese`, `home-home--more-options-italian|portuguese` and
/// `settings-parity--*-italian|portuguese`, in Home.stories.tsx and
/// SettingsParity.stories.tsx): the longer words of the tabs, the bottom bar, the add sheet, the
/// settings menu and each category it shares with the web (spec §3), each as Storybook shows it
/// after its `play` function.
///
/// Update the goldens with `flutter test --update-goldens test/parity/it_pt_parity_test.dart`, then
/// compare with `dart run tool/parity/compose.dart` (docs/mobile/parity.md).

Widget _home() => ShellFrame(
  padding: const EdgeInsets.all(16),
  // The web has no 🎤 (spec §5).
  showMic: false,
  child: HomeScreen(menu: (context, close) => const SizedBox.shrink()),
);

/// A click focuses what it clicks in Chrome, and `userEvent` does it from script, which counts as
/// keyboard: the control rings.
Future<void> _clickFocus(WidgetTester t, Finder finder) async {
  await t.sendKeyEvent(LogicalKeyboardKey.shift);
  Focus.of(t.element(find.descendant(of: finder, matching: find.byType(RichText)).first))
      .requestFocus();
  await t.pumpAndSettle();
}

Future<void> _keys(WidgetTester t, String keys) async {
  for (final key in keys.split('')) {
    await t.tap(find.byKey(Key(key == ',' ? 'keypad.decimal' : 'keypad.$key')));
    await t.pump();
  }
  await t.pumpAndSettle();
}

Future<void> _homeTransactions(
  WidgetTester t, {
  required String id,
  required String story,
  required Locale locale,
  required String movements,
}) async {
  final fixture = ParityFixtures.load(story);
  await parityGolden(
    t,
    id,
    _home(),
    theme: 'night',
    locale: locale,
    overrides: parityHomeOverrides(FixtureHomeRepository(fixture)),
    act: (t) async {
      await precacheWambi(t);
      await t.tap(find.text(movements));
      await t.pumpAndSettle();
    },
  );
}

Future<void> _addSheet(
  WidgetTester t, {
  required String id,
  required String story,
  required Locale locale,
}) async {
  final fixture = ParityFixtures.load(story);
  await parityGolden(
    t,
    id,
    _home(),
    theme: 'night',
    locale: locale,
    overrides: parityHomeOverrides(
      FixtureHomeRepository(fixture),
      add: FixtureAddRepository(fixture),
    ),
    act: (t) async {
      await precacheWambi(t);
      await t.tap(find.byKey(const Key('home.add')));
      await t.pumpAndSettle();
      await _keys(t, '39,9');
      await t.tap(find.byKey(const Key('category.cat-groceries')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('add.more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('add.pending')));
      await t.pumpAndSettle();
      await _clickFocus(t, find.byKey(const Key('add.pending')));
    },
  );
}

Future<void> _settingsPage(
  WidgetTester t, {
  required String id,
  required String story,
  required SettingsCategory? category,
  required Locale locale,
}) async {
  final fixture = ParityFixtures.load(story);
  await parityGolden(
    t,
    id,
    settingsParityPage(category),
    theme: 'night',
    locale: locale,
    overrides: settingsParityOverrides(fixture, 'night'),
  );
}

// The ids are written out in full: test/parity/harness_test.dart looks for each one in its file.
void main() {
  testWidgets('it/pt parity: Movimenti, the list (italian, night)', (t) async {
    await _homeTransactions(
      t,
      id: 'home-transactions-italian',
      story: 'home-home--transactions-italian',
      locale: const Locale('it'),
      movements: 'Movimenti',
    );
  });

  testWidgets('it/pt parity: Movimentos, the list (portuguese, night)', (t) async {
    await _homeTransactions(
      t,
      id: 'home-transactions-portuguese',
      story: 'home-home--transactions-portuguese',
      locale: const Locale('pt'),
      movements: 'Movimentos',
    );
  });

  testWidgets('it/pt parity: the add sheet, more options open, pending ticked (italian, night)', (
    t,
  ) async {
    await _addSheet(
      t,
      id: 'add-sheet-more-options-italian',
      story: 'home-home--more-options-italian',
      locale: const Locale('it'),
    );
  });

  testWidgets(
    'it/pt parity: the add sheet, more options open, pending ticked (portuguese, night)',
    (t) async {
      await _addSheet(
        t,
        id: 'add-sheet-more-options-portuguese',
        story: 'home-home--more-options-portuguese',
        locale: const Locale('pt'),
      );
    },
  );

  testWidgets('it/pt parity: the settings menu (italian, night)', (t) async {
    await _settingsPage(
      t,
      id: 'settings-menu-italian',
      story: 'settings-parity--menu-italian',
      category: null,
      locale: const Locale('it'),
    );
  });

  testWidgets('it/pt parity: the settings menu (portuguese, night)', (t) async {
    await _settingsPage(
      t,
      id: 'settings-menu-portuguese',
      story: 'settings-parity--menu-portuguese',
      category: null,
      locale: const Locale('pt'),
    );
  });

  testWidgets('it/pt parity: Mis agentes (italian, night)', (t) async {
    await _settingsPage(
      t,
      id: 'settings-agents-italian',
      story: 'settings-parity--agents-italian',
      category: SettingsCategory.agents,
      locale: const Locale('it'),
    );
  });

  testWidgets('it/pt parity: Mis agentes (portuguese, night)', (t) async {
    await _settingsPage(
      t,
      id: 'settings-agents-portuguese',
      story: 'settings-parity--agents-portuguese',
      category: SettingsCategory.agents,
      locale: const Locale('pt'),
    );
  });

  testWidgets('it/pt parity: Cuenta y seguridad (italian, night)', (t) async {
    await _settingsPage(
      t,
      id: 'settings-account-italian',
      story: 'settings-parity--account-italian',
      category: SettingsCategory.account,
      locale: const Locale('it'),
    );
  });

  testWidgets('it/pt parity: Cuenta y seguridad (portuguese, night)', (t) async {
    await _settingsPage(
      t,
      id: 'settings-account-portuguese',
      story: 'settings-parity--account-portuguese',
      category: SettingsCategory.account,
      locale: const Locale('pt'),
    );
  });

  testWidgets('it/pt parity: Preferencias (italian, night)', (t) async {
    await _settingsPage(
      t,
      id: 'settings-preferences-italian',
      story: 'settings-parity--preferences-italian',
      category: SettingsCategory.preferences,
      locale: const Locale('it'),
    );
  });

  testWidgets('it/pt parity: Preferencias (portuguese, night)', (t) async {
    await _settingsPage(
      t,
      id: 'settings-preferences-portuguese',
      story: 'settings-parity--preferences-portuguese',
      category: SettingsCategory.preferences,
      locale: const Locale('pt'),
    );
  });

  testWidgets('it/pt parity: Tus datos (italian, night)', (t) async {
    await _settingsPage(
      t,
      id: 'settings-data-italian',
      story: 'settings-parity--data-italian',
      category: SettingsCategory.data,
      locale: const Locale('it'),
    );
  });

  testWidgets('it/pt parity: Tus datos (portuguese, night)', (t) async {
    await _settingsPage(
      t,
      id: 'settings-data-portuguese',
      story: 'settings-parity--data-portuguese',
      category: SettingsCategory.data,
      locale: const Locale('pt'),
    );
  });

  testWidgets('it/pt parity: Más (italian, night)', (t) async {
    await _settingsPage(
      t,
      id: 'settings-more-italian',
      story: 'settings-parity--more-italian',
      category: SettingsCategory.more,
      locale: const Locale('it'),
    );
  });

  testWidgets('it/pt parity: Más (portuguese, night)', (t) async {
    await _settingsPage(
      t,
      id: 'settings-more-portuguese',
      story: 'settings-parity--more-portuguese',
      category: SettingsCategory.more,
      locale: const Locale('pt'),
    );
  });
}
