import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/server_address.dart';
import 'locale_resolution.dart';
import 'settings_store.dart';

/// The settings the app needs before it draws or calls anything: the server, the theme and the
/// language. They are read once at start (main.dart's `bootstrap`), so the first screen is already
/// in the right colours and the first request already goes to the right server.
class InitialSettings {
  const InitialSettings({
    required this.serverUrl,
    required this.themeMode,
    this.locale,
    this.hideAmounts = false,
  });

  /// The defaults: the Wambito server, night (spec section 6.2), and the phone's own language
  /// (Spanish, English, Italian or Portuguese; Spanish for any other).
  static final defaults = InitialSettings(serverUrl: defaultServerUrl, themeMode: ThemeMode.dark);

  final Uri serverUrl;
  final ThemeMode themeMode;

  /// A language the person picked (one of [appLanguages]), or null to follow the phone.
  final Locale? locale;

  /// Home's eye was left closed: every amount starts hidden, from the first frame.
  final bool hideAmounts;

  /// What [store] holds. A value nobody understands, or a store that cannot be read, gives the
  /// default for that setting.
  static Future<InitialSettings> read(SettingsStore store) async {
    Future<String?> get(String key) async {
      try {
        return await store.read(key);
      } on Object {
        return null;
      }
    }

    final server = await get(serverUrlKey);
    return InitialSettings(
      serverUrl: (server == null ? null : parseServerUrl(server)) ?? defaultServerUrl,
      themeMode: switch (await get(themeModeKey)) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      },
      locale: switch (await get(localeKey)) {
        final code? when appLanguages.contains(code) => Locale(code),
        _ => null,
      },
      hideAmounts: await get(hideAmountsKey) == 'on',
    );
  }
}

/// The settings read at start; main.dart overrides it.
final initialSettingsProvider = Provider<InitialSettings>((ref) => InitialSettings.defaults);
