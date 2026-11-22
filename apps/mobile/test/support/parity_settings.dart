import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/recurring/recurring_repository.dart';
import 'package:wambito/settings/assistants_repository.dart';
import 'package:wambito/settings/category_cards.dart';
import 'package:wambito/settings/passkeys_settings.dart';
import 'package:wambito/settings/preferences.dart';
import 'package:wambito/settings/settings_categories.dart';
import 'package:wambito/settings/settings_screen.dart';
import 'package:wambito/ui/app_shell.dart';

import '../entry/fakes.dart';
import 'parity.dart';
import 'parity_home.dart';

/// What the settings pairs share (`settings_parity_test.dart`, `it_pt_parity_test.dart`): the
/// stories `settings-parity--*` (apps/web/app/features/settings/SettingsParity.stories.tsx) draw
/// the menu and each category the web shares with the phone, at rest.

/// A screen of the pairs: the menu (null) or one category's page, in the story's frame
/// (Storybook's 16px of padding, the bar under it, no 🎤), with only what the web also has
/// (`webSectionsOnly`).
Widget settingsParityPage(SettingsCategory? category) => ShellFrame(
  padding: const EdgeInsets.all(16),
  showMic: false,
  child: category == null
      ? const SettingsScreen(webSectionsOnly: true)
      : SettingsCategoryScreen(category: category, webSectionsOnly: true),
);

/// The story's two passkeys (`PARITY_PASSKEYS`: in memory, not on its API).
List<PasskeyItem> settingsParityPasskeys() => [
  PasskeyItem(
    id: 'pk-1',
    credentialId: 'cred-1',
    createdAt: DateTime.utc(2026, 10, 2, 9),
    synced: true,
  ),
  PasskeyItem(
    id: 'pk-2',
    credentialId: 'cred-2',
    name: 'Pixel 9',
    createdAt: DateTime.utc(2026, 10, 5, 10),
  ),
];

/// What the pages need besides the story's API: someone signed in with an email, on the default
/// server (the web's story pins "Mis agentes"' address to it), the story's passkeys and assistants.
List<Override> settingsParityOverrides(ParityFixture fixture, String theme) {
  mockStorage(token: 'email-token-0');
  final auth = FakeAuthApi()..guests['email-token-0'] = false;
  return [
    authApiProvider.overrideWithValue(auth),
    // The story's toolbar sets the theme, and Settings' own choice follows it.
    themeModeProvider.overrideWith(() => _Theme(theme == 'day' ? ThemeMode.light : ThemeMode.dark)),
    ...parityHomeOverrides(FixtureHomeRepository(fixture, fromFixture: true)),
    recurringRepositoryProvider.overrideWithValue(_FixtureRecurring(fixture)),
    settingsPasskeysProvider.overrideWithValue(_StoryPasskeys(settingsParityPasskeys())),
    assistantsRepositoryProvider.overrideWithValue(_FixtureAssistants(fixture)),
  ];
}

class _Theme extends ThemeModeSetting {
  _Theme(this.mode);

  final ThemeMode mode;

  @override
  ThemeMode build() => mode;
}

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

/// The story's connected assistants, as its API answered them.
class _FixtureAssistants implements AssistantsRepository {
  _FixtureAssistants(this.fixture);

  final ParityFixture fixture;

  @override
  Future<List<ConnectedAssistant>> list() async => [
    for (final item in (fixtureJson(fixture, '/v1/me/assistants')! as Map)['items'] as List)
      ConnectedAssistant(
        clientId: (item as Map)['clientId'] as String,
        name: item['name'] as String,
        domain: item['domain'] as String?,
        connectedAt: DateTime.parse(item['connectedAt'] as String),
        lastUsedAt: switch (item['lastUsedAt']) {
          final String at => DateTime.parse(at),
          _ => null,
        },
      ),
  ];

  @override
  Future<void> revoke(String clientId) => throw UnimplementedError();
}
