// Preferencias (`/settings/preferences`), the light version (spec 2026-11-22; twin of
// apps/web/app/features/settings/PreferencesScreen.tsx): "Apariencia" (Idioma and Tema, each a value
// row that opens a sheet of today's choices), "Sonido y tacto" (the sound and vibration switches,
// whose full sentences stay as their hints for a screen reader) and "Hora y moneda"
// (`TimeAndMoneySection`, when the profile is known).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feedback/feedback.dart';
import '../l10n/app_localizations.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import 'choice_sheet.dart';
import 'preferences.dart';
import 'profile_settings.dart';
import 'settings_parts.dart';
import 'time_money_section.dart';

/// "Apariencia" and "Sonido y tacto": what needs no account, so the offline first run shows them too.
class PreferencesGroups extends ConsumerWidget {
  const PreferencesGroups({super.key, this.webSectionsOnly = false});

  /// Only what the web's page has: no "Automático" language, no vibration.
  final bool webSectionsOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tint = context.lkColors.inkMuted;
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeOverrideProvider);
    final sound = ref.watch(soundEnabledProvider);
    final vibration = ref.watch(vibrationEnabledProvider);
    final language =
        locale?.languageCode ??
        (webSectionsOnly ? Localizations.localeOf(context).languageCode : 'auto');
    String languageName(String code) => switch (code) {
      'es' => l10n.settingsLanguageEs,
      'en' => l10n.settingsLanguageEn,
      'it' => l10n.settingsLanguageIt,
      'pt' => l10n.settingsLanguagePt,
      _ => l10n.settingsLanguageAuto,
    };
    final themeName = switch (themeMode) {
      ThemeMode.system => l10n.settingsThemeSystem,
      ThemeMode.dark => l10n.settingsThemeNight,
      ThemeMode.light => l10n.settingsThemeDay,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      // The category page's `gap-(--space-4)` between its groups.
      spacing: WambitoTokens.space4,
      children: [
        SettingsGroup(
          label: l10n.settingsAppearance,
          rows: [
            SettingsRow(
              key: const Key('settings.language'),
              icon: LkIcon(LkIconName.globe, size: 20, color: tint),
              title: l10n.settingsLanguage,
              trailing: RowChevron(value: languageName(language)),
              onTap: () => unawaited(
                ChoicesSheet.show<String>(
                  context,
                  title: l10n.settingsLanguage,
                  hint: webSectionsOnly ? null : l10n.settingsLanguageHint,
                  value: language,
                  options: [
                    if (!webSectionsOnly)
                      Choice(
                        'auto',
                        l10n.settingsLanguageAuto,
                        key: const Key('settings.language.auto'),
                      ),
                    Choice('es', l10n.settingsLanguageEs, key: const Key('settings.language.es')),
                    Choice('en', l10n.settingsLanguageEn, key: const Key('settings.language.en')),
                    Choice('it', l10n.settingsLanguageIt, key: const Key('settings.language.it')),
                    Choice('pt', l10n.settingsLanguagePt, key: const Key('settings.language.pt')),
                  ],
                  onChanged: (code) => unawaited(
                    ref
                        .read(localeOverrideProvider.notifier)
                        .set(code == 'auto' ? null : Locale(code)),
                  ),
                ),
              ),
            ),
            SettingsRow(
              key: const Key('settings.theme'),
              icon: LkIcon(LkIconName.moon, size: 20, color: tint),
              title: l10n.settingsTheme,
              trailing: RowChevron(value: themeName),
              onTap: () => unawaited(
                ChoicesSheet.show<ThemeMode>(
                  context,
                  title: l10n.settingsTheme,
                  hint: l10n.settingsThemeHint,
                  value: themeMode,
                  options: [
                    Choice(
                      ThemeMode.system,
                      l10n.settingsThemeSystem,
                      key: const Key('settings.theme.system'),
                    ),
                    Choice(
                      ThemeMode.dark,
                      l10n.settingsThemeNight,
                      key: const Key('settings.theme.night'),
                    ),
                    Choice(
                      ThemeMode.light,
                      l10n.settingsThemeDay,
                      key: const Key('settings.theme.day'),
                    ),
                  ],
                  onChanged: (mode) => unawaited(ref.read(themeModeProvider.notifier).set(mode)),
                ),
              ),
            ),
          ],
        ),
        SettingsGroup(
          label: l10n.settingsSoundTouch,
          rows: [
            SettingsRow(
              key: const Key('settings.sound'),
              icon: LkIcon(LkIconName.volume, size: 20, color: tint),
              title: l10n.settingsSoundTitle,
              line: l10n.settingsSoundLine,
              // The web's line says vibration stays on; here it is a setting of its own.
              semanticsHint: vibration
                  ? l10n.settingsSoundHint
                  : l10n.settingsSoundHintVibrationOff,
              trailing: RowSwitch(
                value: sound,
                onChanged: (on) => unawaited(ref.read(soundEnabledProvider.notifier).set(on)),
              ),
            ),
            if (!webSectionsOnly)
              SettingsRow(
                key: const Key('settings.vibration'),
                icon: LkIcon(LkIconName.phone, size: 20, color: tint),
                title: l10n.settingsVibration,
                line: l10n.settingsVibrationLine,
                semanticsHint: l10n.settingsVibrationHint,
                trailing: RowSwitch(
                  value: vibration,
                  onChanged: (on) => unawaited(ref.read(vibrationEnabledProvider.notifier).set(on)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key, this.webSectionsOnly = false});

  final bool webSectionsOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(settingsProfileProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      // The category page's `gap-(--space-4)` between its groups.
      spacing: WambitoTokens.space4,
      children: [
        PreferencesGroups(webSectionsOnly: webSectionsOnly),
        if (profile != null) TimeAndMoneySection(profile: profile),
      ],
    );
  }
}
