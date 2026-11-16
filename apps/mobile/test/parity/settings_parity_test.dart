@Tags(['golden'])
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/recurring/recurring_repository.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/settings/account_repository.dart';
import 'package:wambito/settings/passkeys_settings.dart';
import 'package:wambito/settings/preferences.dart';
import 'package:wambito/settings/settings_screen.dart';
import 'package:wambito/ui/app_shell.dart';
import 'package:wambito/ui/press_button.dart';

import '../entry/fakes.dart';
import '../support/parity.dart';
import '../support/parity_home.dart';

/// Settings against the stories that show it, `manage-settings--app-sections*`, `--time-zone-*`
/// and `--passkey-remove-sheet-open` (apps/web/app/features/settings/Settings.stories.tsx), each as
/// Storybook shows it after its `play` function.
///
/// The web's page has six cards, and the app draws them as the web does (the sheets and the
/// export's buttons too): Preferencias, "Hora y moneda", the passkeys, "Tus datos", "Comentarios e
/// ideas" and the delete card. The pairs draw what the web's stories draw (`SettingsScreen.webSectionsOnly`: no "Automático"
/// language, which the web has not, and none of the app's own cards). The app's own cards have
/// goldens of their own in `test/settings/goldens`, to review by eye. The stories that look at a card below the fold scroll the page to it (the card
/// starts 16px under the top, or as near as the page's end lets it), and so does the app's test.
///
/// The app reads who is signed in from what the story's fake API answered (test/parity/fixtures).
///
/// Update the goldens with `flutter test --update-goldens test/parity`, then compare with
/// `dart run tool/parity/compose.dart` (docs/mobile/parity.md).

/// The page in the story's frame: Storybook's 16px of padding, the bar under it, no 🎤.
///
/// [roundedUp]: the story's page is scrolled to its end, and Chrome rounds a document's height up
/// to a whole pixel (it is 0.5px taller than the layout says, and scrolls that much further).
Widget _page({bool roundedUp = false}) => ShellFrame(
  padding: EdgeInsets.fromLTRB(16, 16, 16, roundedUp ? 16.5 : 16),
  showMic: false,
  child: const SettingsScreen(webSectionsOnly: true),
);

/// The story's passkeys (the web's `storyPasskeys`: in memory, not on its API).
class _StoryPasskeys implements SettingsPasskeys {
  _StoryPasskeys(this.items);

  final List<PasskeyItem> items;

  @override
  Future<bool> supported() async => true;

  @override
  Future<List<PasskeyItem>> list() async => List.of(items);

  @override
  Future<PasskeyOutcome> add({PasskeyPrfUse? prf}) async => PasskeyOutcome.added;

  @override
  Future<void> remove(String id) async => items.removeWhere((item) => item.id == id);
}

/// The story's recurring payments, as its API answered them.
class _FixtureRecurring implements RecurringRepository {
  _FixtureRecurring(this.fixture);

  final ParityFixture fixture;

  @override
  Future<List<Recurrence>> list() async => [
    for (final r in fixtureJson(fixture, '/v1/recurrences')! as List)
      readBuilt(Recurrence.serializer, r),
  ];

  @override
  Future<Recurrence> create(NewRecurrence values) => throw UnimplementedError();

  @override
  Future<Recurrence> update(String id, NewRecurrence values, {required bool categoryChanged}) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();
}

/// The two passkeys `AppSectionsPasskeys` lists (one named, one synced).
List<PasskeyItem> _twoPasskeys() => [
  PasskeyItem(id: 'pk-1', createdAt: DateTime.utc(2026, 10, 2, 9), synced: true),
  PasskeyItem(id: 'pk-2', name: 'Pixel 9', createdAt: DateTime.utc(2026, 10, 5, 10)),
];

/// What the page needs besides the story's API: someone signed in with an email, on a fake server.
List<Override> _overrides(
  ParityFixture fixture,
  String theme, {
  List<PasskeyItem> passkeys = const [],
}) {
  mockStorage(token: 'email-token-0');
  final auth = FakeAuthApi()..guests['email-token-0'] = false;
  return [
    authApiProvider.overrideWithValue(auth),
    // The story's toolbar sets the theme, and Settings' own choice follows it.
    themeModeProvider.overrideWith(() => _Theme(theme == 'day' ? ThemeMode.light : ThemeMode.dark)),
    ...parityHomeOverrides(FixtureHomeRepository(fixture, fromFixture: true)),
    recurringRepositoryProvider.overrideWithValue(_FixtureRecurring(fixture)),
    settingsPasskeysProvider.overrideWithValue(_StoryPasskeys([...passkeys])),
  ];
}

/// The account's server: a delete it refuses (the story's `failDelete`, a 503).
class _RefusingAccount implements AccountRepository {
  @override
  Future<ExportFile> export(ExportFormat format) => throw const HomeFailure(503);

  @override
  Future<void> deleteAccount() => throw const HomeFailure(503, code: 'internal_error');
}

class _Theme extends ThemeModeSetting {
  _Theme(this.mode);

  final ThemeMode mode;

  @override
  ThemeMode build() => mode;
}

Future<void> _tab(WidgetTester t, int times) async {
  for (var i = 0; i < times; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
  }
}

/// The story's `scrollTo`: the page moves until [card] starts 16px under the top of the viewport, or
/// as far as it goes.
Future<void> _scrollTo(WidgetTester t, String card) async {
  final position = t.state<ScrollableState>(find.byType(Scrollable).first).position;
  final top = t.getTopLeft(find.byKey(Key(card))).dy;
  // Chrome scrolls to a whole pixel.
  position.jumpTo(math.min((position.pixels + top - 16).roundToDouble(), position.maxScrollExtent));
  await t.pumpAndSettle();
}

Future<void> _openZones(WidgetTester t, String query) async {
  final change = t.widget<PressButton>(find.byKey(const Key('settings.timezone.change')));
  change.onPressed!();
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('settings.timezone.search')));
  await t.enterText(find.byKey(const Key('settings.timezone.search')), query);
  await t.pumpAndSettle();
}

/// The story's `openDeleteSheet`: the card scrolled to (16px under the top, or as near as the page's
/// end lets it), then its button pressed, as the story's click does.
Future<void> _openDeleteSheet(WidgetTester t) async {
  await _scrollTo(t, 'settings.card.delete');
  t.widget<PressButton>(find.byKey(const Key('settings.delete'))).onPressed!();
  await t.pumpAndSettle();
}

/// What the story's `userEvent.type` does: focuses the email field and types.
Future<void> _typeEmail(WidgetTester t, String text) async {
  await t.tap(find.byKey(const Key('settings.delete.field')));
  await t.enterText(find.byKey(const Key('settings.delete.field')), text);
  await t.pumpAndSettle();
}

void main() {
  for (final theme in ['night', 'day']) {
    testWidgets('settings parity: Preferencias ($theme)', (t) async {
      final fixture = ParityFixtures.load('manage-settings--app-sections');
      await parityGolden(
        t,
        'settings-app-sections',
        _page(),
        theme: theme,
        overrides: _overrides(fixture, theme),
      );
    });

    testWidgets('settings parity: sounds turned off, the keyboard on them ($theme)', (t) async {
      final fixture = ParityFixtures.load('manage-settings--app-sections-sound-off');
      await parityGolden(
        t,
        'settings-app-sections-sound-off',
        _page(),
        theme: theme,
        overrides: _overrides(fixture, theme),
        act: (t) async {
          await t.tap(find.byKey(const Key('settings.sound')));
          await t.pumpAndSettle();
          // The click leaves the focus on the switch, and Chrome rings it: Tab, back, the language,
          // the theme, the switch.
          await _tab(t, 4);
        },
      );
    });

    testWidgets('settings parity: the currency still open, its options scrolled to ($theme)', (
      t,
    ) async {
      final fixture = ParityFixtures.load('manage-settings--app-sections-currency-open');
      await parityGolden(
        t,
        'settings-currency-open',
        _page(),
        theme: theme,
        overrides: _overrides(fixture, theme),
        act: (t) => _scrollTo(t, 'settings.currency.group'),
      );
    });

    testWidgets('settings parity: the passkeys listed, scrolled to ($theme)', (t) async {
      final fixture = ParityFixtures.load('manage-settings--app-sections-passkeys');
      await parityGolden(
        t,
        'settings-passkeys',
        _page(roundedUp: true),
        theme: theme,
        overrides: _overrides(fixture, theme, passkeys: _twoPasskeys()),
        act: (t) => _scrollTo(t, 'settings.card.passkeys'),
      );
    });

    testWidgets('settings parity: "Tus datos" at the foot of the page ($theme)', (t) async {
      final fixture = ParityFixtures.load('manage-settings--app-sections-data');
      await parityGolden(
        t,
        'settings-data',
        _page(),
        theme: theme,
        overrides: _overrides(fixture, theme),
        act: (t) => _scrollTo(t, 'settings.card.data'),
      );
    });

    testWidgets('settings parity: the time zone sheet after searching a country ($theme)', (
      t,
    ) async {
      final fixture = ParityFixtures.load('manage-settings--time-zone-sheet-open');
      await parityGolden(
        t,
        'settings-time-zone-sheet',
        _page(),
        theme: theme,
        overrides: _overrides(fixture, theme),
        act: (t) => _openZones(t, 'colombia'),
      );
    });

    testWidgets('settings parity: the zone in use says "Actual" ($theme)', (t) async {
      final fixture = ParityFixtures.load('manage-settings--time-zone-sheet-current');
      await parityGolden(
        t,
        'settings-time-zone-current',
        _page(),
        theme: theme,
        overrides: _overrides(fixture, theme),
        act: (t) => _openZones(t, 'madrid'),
      );
    });

    testWidgets('settings parity: a search that finds nothing ($theme)', (t) async {
      final fixture = ParityFixtures.load('manage-settings--time-zone-no-match');
      await parityGolden(
        t,
        'settings-time-zone-no-match',
        _page(),
        theme: theme,
        overrides: _overrides(fixture, theme),
        act: (t) => _openZones(t, 'zzzz'),
      );
    });

    testWidgets('settings parity: the delete card at the foot of the page ($theme)', (t) async {
      final fixture = ParityFixtures.load('manage-settings--app-sections-delete');
      await parityGolden(
        t,
        'settings-delete',
        _page(),
        theme: theme,
        overrides: _overrides(fixture, theme),
        act: (t) => _scrollTo(t, 'settings.card.delete'),
      );
    });

    testWidgets(
      'settings parity: comments and ideas, between the data and the delete card ($theme)',
      (t) async {
        final fixture = ParityFixtures.load('manage-settings--app-sections-feedback');
        await parityGolden(
          t,
          'settings-feedback',
          _page(),
          theme: theme,
          overrides: _overrides(fixture, theme),
          act: (t) => _scrollTo(t, 'settings.card.feedback'),
        );
      },
    );

    testWidgets('settings parity: the question before deleting the account ($theme)', (t) async {
      final fixture = ParityFixtures.load('manage-settings--delete-sheet-open');
      await parityGolden(
        t,
        'settings-delete-sheet',
        _page(),
        theme: theme,
        overrides: _overrides(fixture, theme),
        act: _openDeleteSheet,
      );
    });

    testWidgets('settings parity: the email typed, the deleting button on ($theme)', (t) async {
      final fixture = ParityFixtures.load('manage-settings--delete-sheet-ready');
      await parityGolden(
        t,
        'settings-delete-sheet-ready',
        _page(),
        theme: theme,
        overrides: _overrides(fixture, theme),
        act: (t) async {
          await _openDeleteSheet(t);
          await _typeEmail(t, '  ANA@Example.com ');
        },
      );
    });

    testWidgets('settings parity: a delete the server refused ($theme)', (t) async {
      final fixture = ParityFixtures.load('manage-settings--delete-sheet-failed');
      await parityGolden(
        t,
        'settings-delete-sheet-failed',
        _page(),
        theme: theme,
        overrides: [
          ..._overrides(fixture, theme),
          accountRepositoryProvider.overrideWithValue(_RefusingAccount()),
        ],
        act: (t) async {
          await _openDeleteSheet(t);
          await _typeEmail(t, 'ana@example.com');
          await t.tap(find.byKey(const Key('settings.delete.confirm')));
          await t.pumpAndSettle();
          // The story ends with the focus nowhere (the browser takes it off the button while it
          // deletes, and the story lets go of whatever has it).
          FocusManager.instance.primaryFocus?.unfocus();
          await t.pumpAndSettle();
        },
      );
    });

    testWidgets('settings parity: the question before deleting a passkey ($theme)', (t) async {
      final fixture = ParityFixtures.load('manage-settings--passkey-remove-sheet-open');
      await parityGolden(
        t,
        'settings-passkey-remove-sheet',
        _page(),
        theme: theme,
        overrides: _overrides(
          fixture,
          theme,
          passkeys: [
            PasskeyItem(id: 'pk-1', createdAt: DateTime.utc(2026, 10, 2, 9), synced: true),
          ],
        ),
        act: (t) async {
          // The story's click brings the button to the middle of the viewport, as the browser does
          // (the page ends up scrolled to a whole pixel).
          final button = find.byKey(const Key('settings.passkeys.remove.pk-1'));
          final position = t.state<ScrollableState>(find.byType(Scrollable).first).position;
          position.jumpTo(
            (position.pixels + t.getCenter(button).dy - 915 / 2).roundToDouble().clamp(
              0,
              position.maxScrollExtent,
            ),
          );
          await t.pumpAndSettle();
          t.widget<PressButton>(button).onPressed!();
          await t.pumpAndSettle();
        },
      );
    });
  }

  testWidgets('settings parity: the deletion sheet by day, in English (day)', (t) async {
    final fixture = ParityFixtures.load('manage-settings--delete-sheet-day-english');
    await parityGolden(
      t,
      'settings-delete-sheet-day-english',
      _page(),
      theme: 'day',
      locale: const Locale('en'),
      overrides: _overrides(fixture, 'day'),
      act: _openDeleteSheet,
    );
  });

  testWidgets('settings parity: by day, in English (day)', (t) async {
    final fixture = ParityFixtures.load('manage-settings--app-sections-day-english');
    await parityGolden(
      t,
      'settings-app-sections-day-english',
      _page(),
      theme: 'day',
      locale: const Locale('en'),
      overrides: _overrides(fixture, 'day'),
    );
  });
}
