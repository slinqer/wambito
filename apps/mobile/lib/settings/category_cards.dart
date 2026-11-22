// What each settings category holds: `SettingsCategoryScreen` builds the screen of one
// `SettingsCategory` inside `SettingsCategoryPage` (one file each: `assistants_section.dart`,
// `account_screen.dart`, `preferences_screen.dart`, `capture_screen.dart`, `data_screen.dart`,
// `more_screen.dart`).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/device.dart';
import '../api/session.dart';
import '../vault/preview.dart';
import 'account_screen.dart';
import 'assistants_section.dart';
import 'capture_screen.dart';
import 'category_screen.dart';
import 'data_screen.dart';
import 'more_screen.dart';
import 'preferences_screen.dart';
import 'profile_settings.dart';
import 'settings_categories.dart';

/// One category's page: [category]'s screen under its title.
class SettingsCategoryScreen extends ConsumerWidget {
  const SettingsCategoryScreen({super.key, required this.category, this.webSectionsOnly = false});

  final SettingsCategory category;

  /// As `SettingsScreen.webSectionsOnly`: only what the web's page also has.
  final bool webSectionsOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final webOnly = webSectionsOnly;
    final profile = ref.watch(settingsProfileProvider).value;
    final timeZone = profile?.timezone ?? ref.watch(deviceHintsProvider).timezone;
    final guest = ref.watch(sessionProvider.select((s) => s.isGuest));
    final preview = ref.watch(isPreviewProvider);
    final children = switch (category) {
      // "Mis agentes" (spec 2026-11-22): the web has it too (the `settings-agents*` pairs).
      SettingsCategory.agents => [AgentsScreen(timeZone: timeZone, guest: guest)],
      SettingsCategory.account => [
        AccountScreen(
          timeZone: timeZone,
          // A `preview` guest adds a passkey here too ("Protect your data" step 2).
          passkeysGuest: guest && !webOnly && !preview,
          // An encrypted account's devices and recovery key, with or without email. Plain accounts
          // see nothing of it.
          showSecurity: !webOnly && preview,
        ),
      ],
      SettingsCategory.preferences => [PreferencesScreen(webSectionsOnly: webOnly)],
      SettingsCategory.capture => [if (!webOnly) const CaptureScreen()],
      SettingsCategory.data => [DataScreen(guest: guest)],
      SettingsCategory.more => [MoreScreen(webSectionsOnly: webOnly)],
    };
    return SettingsCategoryPage(category: category, children: children);
  }
}
