// The web's Settings (apps/web/app/features/settings/Settings.tsx), as a menu: the page's title and
// who is signed in, the urgent block ("Protect your data" or "Guarda tu progreso") and one row per
// category (`SettingsMenu`), each on its own route (`SettingsCategoryScreen`), then "Cerrar sesión"
// and the app's version. An offline first run has no menu: only the preferences.
import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../add/add_sheet.dart';
import '../api/session.dart';
import '../capture/capture_sheet.dart';
import '../capture/models_download.dart';
import '../home/shell_navigation.dart';
import '../l10n/app_localizations.dart';
import '../progress/guest_warning.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_theme.dart';
import '../ui/manage_page.dart';
import '../ui/page_header.dart';
import '../ui/press_button.dart';
import '../vault/preview.dart';
import '../vault/unsynced_sheet.dart';
import '../vault/vault_providers.dart' show vaultSessionProvider;
import 'feedback.dart';
import 'profile_settings.dart';
import 'settings_parts.dart';
import 'preferences_screen.dart' show PreferencesGroups;
import 'leave_guard.dart';
import 'settings_menu.dart';

/// Whether a voice model is downloaded (so there is something to delete).
final voiceModelsInstalledProvider = FutureProvider.autoDispose<bool>((ref) async {
  final models = ref.watch(modelStoreProvider);
  for (final locale in voiceModels.keys) {
    if (await models.installedPath(locale) != null) return true;
  }
  return false;
});

/// Whether the precise voice model is downloaded for [locale] (a `voiceLocale`).
final preciseModelInstalledProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, locale) async => await ref.watch(preciseModelStoreProvider).installedPath(locale) != null,
);

/// The account's email, for "Entraste como…" (null while it is not known: offline, or not loaded).
final settingsEmailProvider = FutureProvider.autoDispose<String?>((ref) async {
  final email = (await ref.watch(settingsProfileProvider.future))?.email;
  return email == null || email.isEmpty ? null : email;
});

/// Settings (spec section 6.1.6): language, theme, sound, time zone and currency, the passkeys,
/// "Conecta tu asistente", the import, vibration, the two local notices, hiding the amount in the
/// widget, the voice models, the server, About, "Más en la web" and sign out.
/// A `plain` guest also finds "Guarda tu progreso" at the top; a `preview` guest's ways back live in
/// Cuenta y seguridad, whose menu line says "Sin proteger" until one exists. A guest is warned
/// before anything that would leave their account behind (signing out, changing server).
/// Whether Settings shows its debug-only rows (the passkey PRF probe): debug builds only. A provider
/// so a test can switch it.
final debugToolsProvider = Provider<bool>((ref) => kDebugMode);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.webSectionsOnly = false});

  /// Draws only what the web's Settings page also has: the menu without Captura, and no signing
  /// out. For the parity pictures, which a story of the web's can only match that far (the app's
  /// own cards have none).
  final bool webSectionsOnly;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Signing out is under way (the old server is told, if it answers).
  bool _busy = false;

  Future<void> _signOut() async {
    final session = ref.read(sessionProvider.notifier);
    if (!await mayLeaveSettings(context, ref, GuestLeaving.signOut) || !mounted) return;
    // A `preview` account with changes not sent yet: sync them first, or sign out anyway.
    if (!await confirmUnsyncedSignOut(context, ref.read(vaultSessionProvider))) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await session.signOut(discardGuest: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/');
    }
  }

  /// Where the email in "Entraste como…" comes from; a guest has none, and the line says so.
  String? _signedInAs(AppLocalizations l10n, {required bool guest}) {
    if (guest) return l10n.settingsGuestAccount;
    final email = ref.watch(settingsEmailProvider).value;
    return email == null ? null : l10n.settingsSignedInAs(email);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final guest = ref.watch(sessionProvider.select((s) => s.isGuest));
    final webOnly = widget.webSectionsOnly;
    final signedInAs = _signedInAs(l10n, guest: guest && !webOnly);
    final titleStyle = LkText.pageTitle.copyWith(color: colors.ink);
    final signedInStyle = LkText.bodySm.copyWith(color: colors.inkMuted);
    final provisional = ref.watch(sessionProvider.select((s) => s.isProvisional));
    final block = ref.watch(sessionProvider.select((s) => s.provisionalBlock));
    final header = PageHeader(
      backLabel: l10n.manageBack,
      backShort: l10n.manageBackShort,
      onBack: _back,
    );
    // An offline first run (lib/local/provisional.dart): no account yet, so only this phone's own
    // preferences and why the account waits; no menu, no sign-in, no server, no account card.
    if (provisional && !webOnly) {
      return ManagePage(
        current: 'settings',
        onAdd: () => unawaited(openAddSheet(context)),
        onMic: () => unawaited(openCapture(context, listen: true)),
        onNavigate: (to) => navigateFromShell(context, ref, to, current: 'settings'),
        header: header,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WambitoTokens.space1,
            children: [
              Semantics(header: true, child: Text(l10n.settingsTitle, style: titleStyle)),
              Text(
                switch (block) {
                  ProvisionalBlock.plainServer => l10n.provisionalPlainServer,
                  ProvisionalBlock.noGuests => l10n.provisionalNoGuests,
                  null => l10n.provisionalWaiting,
                },
                key: const Key('settings.provisional'),
                style: signedInStyle,
              ),
            ],
          ),
          const PreferencesGroups(),
        ],
      );
    }
    final version = ref.watch(appVersionProvider).value;
    return ManagePage(
      current: 'settings',
      onAdd: () => unawaited(openAddSheet(context)),
      onMic: () => unawaited(openCapture(context, listen: true)),
      onNavigate: (to) => navigateFromShell(context, ref, to, current: 'settings'),
      header: header,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WambitoTokens.space1,
          children: [
            Semantics(header: true, child: Text(l10n.settingsTitle, style: titleStyle)),
            if (signedInAs != null) Text(signedInAs, style: signedInStyle),
          ],
        ),
        // Its block offers adding an email, so "Guarda tu progreso" is for a `plain` guest only.
        if (guest && !webOnly && !ref.watch(isPreviewProvider))
          SettingsSection(
            title: l10n.progressTitle,
            lead: l10n.progressLead,
            children: [
              PressButton.text(
                l10n.progressSave,
                key: const Key('settings.saveProgress'),
                tone: PressTone.secondary,
                onPressed: () => context.push('/progress'),
              ),
            ],
          ),
        if (webOnly)
          SettingsMenu(webSectionsOnly: webOnly)
        else
          // Sign out sits 12px under the rows (not the page's 16): the menu, sign out and the
          // version still show above the bottom bar at 360 x 740.
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WambitoTokens.space3,
            children: [
              SettingsMenu(webSectionsOnly: webOnly),
              Column(
                spacing: WambitoTokens.space2,
                children: [
                  Align(
                    child: PressButton(
                      key: const Key('settings.signOut'),
                      tone: PressTone.secondary,
                      onPressed: _busy ? null : _signOut,
                      child: Text(
                        LkText.upperCase(l10n.settingsSignOut),
                        style: TextStyle(color: colors.over),
                      ),
                    ),
                  ),
                  if (version != null)
                    Text(
                      l10n.settingsVersion(version),
                      textAlign: TextAlign.center,
                      style: LkText.fieldLabel.copyWith(color: colors.inkMuted),
                    ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}
