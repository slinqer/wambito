// The frame of one settings category's page (the web's `SettingsCategoryScreen`): the app shell, a
// back link to the menu ("Volver a Ajustes"), the category's name as the title, then its cards.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../add/add_sheet.dart';
import '../capture/capture_sheet.dart';
import '../home/shell_navigation.dart';
import '../l10n/app_localizations.dart';
import '../theme/text_styles.dart';
import '../ui/lk_theme.dart';
import '../ui/manage_page.dart';
import '../ui/page_header.dart';
import 'settings_categories.dart';

/// The name the menu and the page's title give [category].
String settingsCategoryTitle(AppLocalizations l10n, SettingsCategory category) =>
    switch (category) {
      SettingsCategory.agents => l10n.settingsMenuAgents,
      SettingsCategory.account => l10n.settingsMenuAccount,
      SettingsCategory.preferences => l10n.settingsMenuPreferences,
      SettingsCategory.capture => l10n.settingsMenuCapture,
      SettingsCategory.data => l10n.settingsMenuData,
      SettingsCategory.more => l10n.settingsMenuMore,
    };

/// A category's page: [children] are its cards, 16px apart under the title.
class SettingsCategoryPage extends ConsumerWidget {
  const SettingsCategoryPage({super.key, required this.category, required this.children});

  final SettingsCategory category;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    return ManagePage(
      current: 'settings',
      onAdd: () => unawaited(openAddSheet(context)),
      onMic: () => unawaited(openCapture(context, listen: true)),
      onNavigate: (to) => navigateFromShell(context, ref, to, current: 'settings'),
      header: PageHeader(
        backLabel: l10n.settingsMenuBack,
        backShort: l10n.settingsMenuBackShort,
        onBack: () {
          final router = GoRouter.of(context);
          if (router.canPop()) {
            router.pop();
          } else {
            router.go('/settings');
          }
        },
      ),
      children: [
        Semantics(
          header: true,
          child: Text(
            settingsCategoryTitle(l10n, category),
            style: LkText.pageTitle.copyWith(color: colors.ink),
          ),
        ),
        ...children,
      ],
    );
  }
}
