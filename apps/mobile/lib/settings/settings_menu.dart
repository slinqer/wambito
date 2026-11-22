// The settings menu's rows (the web's `SettingsMenu`, apps/web/app/features/settings/SettingsMenu.tsx):
// one row per category, each on its own route: a 40px icon tile, the name, a muted line of what is
// inside, a chevron. Preferencias' line is live: the language, the theme and the currency in use.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/css_text.dart';
import '../ui/lk_brand_logo.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/pixel_snap.dart';
import '../ui/pressable.dart';
import 'category_screen.dart' show settingsCategoryTitle;
import 'preferences.dart';
import 'profile_settings.dart';
import 'settings_categories.dart';

/// One row of the menu (`.rowcard`): a 40px `surface-sunken` tile with the icon in `brand`, [title]
/// (15, heavy), a muted one-line [line] and a chevron, on a `surface-row` card with a 2px stroke and
/// the small edge. The whole row is one pressable.
class SettingsMenuRow extends StatelessWidget {
  const SettingsMenuRow({
    super.key,
    required this.icon,
    required this.title,
    required this.line,
    required this.onTap,
  });

  final Widget icon;
  final String title;
  final String line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lk = context.lk;
    final colors = lk.colors;
    final titleStyle = LkText.cardTitle.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: colors.ink,
    );
    final lineStyle = LkText.fieldLabel.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: colors.inkMuted,
    );
    return Pressable(
      onPressed: onTap,
      label: title,
      hint: line,
      builder: (context, state) => RingBox(
        radius: state.focusVisible ? LkSurface.radius(LkRadius.lg) : null,
        color: colors.focus,
        offset: 2,
        child: Opacity(
          opacity: state.pressed ? 0.7 : 1,
          child: SnappedDecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceRow,
              borderRadius: LkSurface.radius(LkRadius.lg),
              border: Border.all(color: colors.stroke, width: 2),
              boxShadow: LkSurface.edgeShadow(lk, LkEdge.sm),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12 + 2, vertical: 10 + 2),
                child: Row(
                  // `.lk-rowcard`'s gap.
                  spacing: 10,
                  children: [
                    ExcludeSemantics(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceSunken,
                          borderRadius: LkSurface.radius(LkRadius.sm),
                        ),
                        child: SizedBox(width: 40, height: 40, child: Center(child: icon)),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 2,
                        children: [
                          // As tall as CSS makes them (22.5 and 18.75px), not rounded up.
                          CssLines(
                            style: titleStyle,
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            ),
                          ),
                          CssLines(
                            style: lineStyle,
                            child: Text(
                              line,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: lineStyle,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ExcludeSemantics(
                      child: LkIcon(LkIconName.chevronRight, size: 16, color: colors.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The four apps Wambito works with, two by two, in the agents row's tile.
class _AgentsTile extends StatelessWidget {
  const _AgentsTile();

  @override
  Widget build(BuildContext context) {
    final brand = context.lkColors.brand;
    const brands = [LkBrand.chatgpt, LkBrand.claude, LkBrand.lumo, LkBrand.grok];
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        for (var row = 0; row < 2; row++)
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 2,
            children: [
              for (final b in brands.skip(row * 2).take(2)) LkBrandLogo(b, size: 13, color: brand),
            ],
          ),
      ],
    );
  }
}

Widget _iconOf(BuildContext context, SettingsCategory category) {
  final brand = context.lkColors.brand;
  LkIcon icon(LkIconName name) => LkIcon(name, size: 22, color: brand);
  return switch (category) {
    SettingsCategory.agents => const _AgentsTile(),
    SettingsCategory.account => icon(LkIconName.shield),
    SettingsCategory.preferences => icon(LkIconName.sliders),
    SettingsCategory.capture => icon(LkIconName.bell),
    SettingsCategory.data => icon(LkIconName.folder),
    SettingsCategory.more => icon(LkIconName.info),
  };
}

/// The language, theme and currency now in use, "Español · Noche · COP".
String _preferencesLine(BuildContext context, WidgetRef ref, AppLocalizations l10n) {
  final code = ref.watch(localeOverrideProvider)?.languageCode ?? l10n.localeName;
  final language = switch (code) {
    'en' => l10n.settingsLanguageEn,
    'it' => l10n.settingsLanguageIt,
    'pt' => l10n.settingsLanguagePt,
    _ => l10n.settingsLanguageEs,
  };
  final theme = switch (ref.watch(themeModeProvider)) {
    ThemeMode.system => l10n.settingsThemeSystem,
    ThemeMode.dark => l10n.settingsThemeNight,
    ThemeMode.light => l10n.settingsThemeDay,
  };
  final currency = ref.watch(settingsProfileProvider).value?.currency ?? '';
  // The currency is not known until the profile loads (or offline): the line has the two it has.
  return l10n
      .settingsMenuPreferencesLine(language, theme, currency)
      .replaceFirst(RegExp(r' · $'), '');
}

/// The six rows, in menu order; with [webSectionsOnly] the phone's own Captura is left out.
class SettingsMenu extends ConsumerWidget {
  const SettingsMenu({super.key, this.webSectionsOnly = false});

  final bool webSectionsOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    String lineOf(SettingsCategory category) => switch (category) {
      SettingsCategory.agents => l10n.settingsMenuAgentsLine,
      SettingsCategory.account => l10n.settingsMenuAccountLine,
      SettingsCategory.preferences => _preferencesLine(context, ref, l10n),
      SettingsCategory.capture => l10n.settingsMenuCaptureLine,
      SettingsCategory.data => l10n.settingsMenuDataLine,
      // Only the web's rows (the parity pictures): the web's line, feedback alone.
      SettingsCategory.more =>
        webSectionsOnly ? l10n.settingsMenuMoreWebLine : l10n.settingsMenuMoreLine,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space2,
      children: [
        for (final category in settingsCategories(webSectionsOnly: webSectionsOnly))
          SettingsMenuRow(
            key: Key('settings.menu.${category.name}'),
            icon: _iconOf(context, category),
            title: settingsCategoryTitle(l10n, category),
            line: lineOf(category),
            onTap: () => unawaited(context.push<void>(category.path)),
          ),
      ],
    );
  }
}
