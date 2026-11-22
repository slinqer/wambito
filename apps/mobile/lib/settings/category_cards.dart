// What each settings category holds, for now the long page's own cards, regrouped (a later task
// redraws them): `SettingsCategoryScreen` builds the cards of one `SettingsCategory` inside
// `SettingsCategoryPage`. The state it keeps (a server change under way, the precise voice model's
// download) is what those cards need.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/device.dart';
import '../api/server_url.dart';
import '../api/session.dart';
import '../feedback/feedback.dart';
import '../l10n/app_localizations.dart';
import '../progress/guest_warning.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/confirm_sheet.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/press_link.dart';
import '../ui/sheet.dart';
import '../ui/toast.dart';
import '../ui/web_text_field.dart';
import '../vault/preview.dart';
import '../vault/unsynced_sheet.dart';
import '../vault/vault_providers.dart' show vaultSessionProvider;
import 'assistants_section.dart';
import 'account_screen.dart';
import 'capture_screen.dart';
import 'export_settings.dart';
import 'feedback.dart';
import 'server_status.dart';
import 'locale_resolution.dart';
import 'preferences.dart';
import 'profile_settings.dart';
import 'settings_parts.dart';
import 'time_money_section.dart';
import 'url_opener.dart';
import 'category_screen.dart';
import 'leave_guard.dart';
import 'settings_categories.dart';
import 'settings_screen.dart' show debugToolsProvider;

/// Preferencias' card: language, theme, sound and, on the phone, vibration.
class PreferencesCard extends ConsumerWidget {
  const PreferencesCard({super.key, this.webSectionsOnly = false});

  final bool webSectionsOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final webOnly = webSectionsOnly;
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeOverrideProvider);
    final sound = ref.watch(soundEnabledProvider);
    final vibration = ref.watch(vibrationEnabledProvider);
    return SettingsSection(
      title: l10n.settingsPreferences,
      children: [
        Choices<String>(
          legend: l10n.settingsLanguage,
          value:
              locale?.languageCode ??
              (webOnly ? Localizations.localeOf(context).languageCode : 'auto'),
          options: [
            if (!webOnly)
              Choice('auto', l10n.settingsLanguageAuto, key: const Key('settings.language.auto')),
            Choice('es', l10n.settingsLanguageEs, key: const Key('settings.language.es')),
            Choice('en', l10n.settingsLanguageEn, key: const Key('settings.language.en')),
            Choice('it', l10n.settingsLanguageIt, key: const Key('settings.language.it')),
            Choice('pt', l10n.settingsLanguagePt, key: const Key('settings.language.pt')),
          ],
          onChanged: (code) => unawaited(
            ref.read(localeOverrideProvider.notifier).set(code == 'auto' ? null : Locale(code)),
          ),
        ),
        Choices<ThemeMode>(
          legend: l10n.settingsTheme,
          hint: l10n.settingsThemeHint,
          value: themeMode,
          options: [
            Choice(
              ThemeMode.system,
              l10n.settingsThemeSystem,
              key: const Key('settings.theme.system'),
            ),
            Choice(ThemeMode.dark, l10n.settingsThemeNight, key: const Key('settings.theme.night')),
            Choice(ThemeMode.light, l10n.settingsThemeDay, key: const Key('settings.theme.day')),
          ],
          onChanged: (mode) => unawaited(ref.read(themeModeProvider.notifier).set(mode)),
        ),
        SettingSwitch(
          key: const Key('settings.sound'),
          label: l10n.settingsSound,
          // The web's line says vibration stays on; here it is a setting of its own.
          hint: vibration ? l10n.settingsSoundHint : l10n.settingsSoundHintVibrationOff,
          value: sound,
          onChanged: (on) => unawaited(ref.read(soundEnabledProvider.notifier).set(on)),
        ),
        if (!webOnly)
          SettingSwitch(
            key: const Key('settings.vibration'),
            label: l10n.settingsVibration,
            hint: l10n.settingsVibrationHint,
            value: vibration,
            onChanged: (on) => unawaited(ref.read(vibrationEnabledProvider.notifier).set(on)),
          ),
      ],
    );
  }
}

/// One category's page: [category]'s cards under its title.
class SettingsCategoryScreen extends ConsumerStatefulWidget {
  const SettingsCategoryScreen({super.key, required this.category, this.webSectionsOnly = false});

  final SettingsCategory category;

  /// As `SettingsScreen.webSectionsOnly`: only what the web's page also has.
  final bool webSectionsOnly;

  @override
  ConsumerState<SettingsCategoryScreen> createState() => _SettingsCategoryScreenState();
}

class _SettingsCategoryScreenState extends ConsumerState<SettingsCategoryScreen> {
  /// Changing server is under way (the old server is told, if it answers).
  bool _busy = false;

  // -- server --------------------------------------------------------------------------------

  // -- server --------------------------------------------------------------------------------

  Future<void> _changeServer() async {
    final next = await LkSheet.show<Uri>(
      context,
      title: AppLocalizations.of(context).settingsServerTitle,
      children: [_ServerForm(current: ref.read(serverUrlProvider))],
    );
    if (!mounted || next == null) return;
    if (next != ref.read(serverUrlProvider) &&
        !await mayLeaveSettings(context, ref, GuestLeaving.changeServer)) {
      return;
    }
    if (!mounted) return;
    // Another server signs out (and wipes the vault): a `preview` account's changes not sent yet
    // are asked about first, as at a sign-out.
    if (next != ref.read(serverUrlProvider) &&
        !await confirmUnsyncedSignOut(context, ref.read(vaultSessionProvider))) {
      return;
    }
    if (!mounted) return;
    final toasts = ToastHost.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final changed = await ref.read(serverUrlProvider.notifier).change(next.toString());
      if (changed) toasts.say(l10n.settingsServerChanged(next.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -- the rest ------------------------------------------------------------------------------

  /// Opens one of the web's public pages in the browser: the landing, or the roadmap. They are
  /// prerendered per language, Spanish with no prefix and the others under `/en`, `/it` and `/pt`
  /// (the web's `LANDING_PATH` and `ROADMAP_PATH`).
  Future<void> _openWeb({bool roadmap = false}) async {
    final toasts = ToastHost.of(context);
    final l10n = AppLocalizations.of(context);
    final server = ref.read(serverUrlProvider);
    final path = webPagePath(l10n.localeName, roadmap: roadmap);
    // The Spanish landing is the server's own address, as it always was.
    final page = path == '/' ? server : server.resolve(path);
    final opened = await ref.read(urlOpenerProvider).open(page);
    if (!opened && mounted) toasts.say(l10n.settingsWebFailed, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final webOnly = widget.webSectionsOnly;
    final profile = ref.watch(settingsProfileProvider).value;
    final timeZone = profile?.timezone ?? ref.watch(deviceHintsProvider).timezone;
    final guest = ref.watch(sessionProvider.select((s) => s.isGuest));
    final preview = ref.watch(isPreviewProvider);
    final children = switch (widget.category) {
      // "Mis agentes" (spec 2026-11-22): the web has it too, but its story is not in the parity
      // pairs yet, so the web-only pictures leave it out.
      SettingsCategory.agents => [
        if (!webOnly) AgentsScreen(timeZone: timeZone, guest: guest),
      ],
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
      SettingsCategory.preferences => [
        PreferencesCard(webSectionsOnly: webOnly),
        if (profile != null) TimeAndMoneySection(profile: profile),
      ],
      SettingsCategory.capture => [if (!webOnly) const CaptureScreen()],
      SettingsCategory.data => [_dataCard(context, guest: guest, preview: preview)],
      SettingsCategory.more => _more(context),
    };
    return SettingsCategoryPage(category: widget.category, children: children);
  }

  /// "Tus datos" (the web's Settings.tsx): the import links to its page; the export joins it.
  Widget _dataCard(BuildContext context, {required bool guest, required bool preview}) {
    final l10n = AppLocalizations.of(context);
    return SettingsSection(
      key: const Key('settings.card.data'),
      title: l10n.settingsDataTitle,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WambitoTokens.space2,
          children: [
            // An encrypted account's data is on the phone: the server's import waits for encryption.
            if (preview) ...[
              SettingLabel(label: l10n.settingsImportTitle),
              const ComingSoonNotice(key: Key('settings.import.comingSoon')),
            ] else ...[
              SettingLabel(label: l10n.settingsImportTitle, hint: l10n.settingsImportLead),
              _SelfStart(
                child: PressLink.text(
                  l10n.settingsImportAction,
                  key: const Key('settings.import'),
                  tone: PressTone.secondary,
                  onPressed: () => unawaited(context.push<void>('/import')),
                ),
              ),
            ],
          ],
        ),
        ExportBlock(guest: guest),
      ],
    );
  }

  List<Widget> _more(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final server = ref.watch(serverUrlProvider);
    return [
      const FeedbackSection(),
      if (!widget.webSectionsOnly) ...[
        SettingsSection(
          title: l10n.settingsServer,
          lead: server.toString(),
          children: [
            const ServerStatus(),
            _SelfStart(
              child: PressButton.text(
                l10n.settingsServerChange,
                key: const Key('settings.server'),
                tone: PressTone.secondary,
                onPressed: _busy ? null : _changeServer,
              ),
            ),
          ],
        ),
        SettingsSection(
          title: l10n.settingsWeb,
          lead: l10n.settingsWebHint,
          children: [
            _SelfStart(
              child: PressLink.text(
                l10n.settingsWebOpen,
                key: const Key('settings.web'),
                tone: PressTone.secondary,
                onPressed: _openWeb,
              ),
            ),
            _SelfStart(
              child: PressLink.text(
                l10n.settingsRoadmapOpen,
                key: const Key('settings.roadmap'),
                tone: PressTone.secondary,
                onPressed: () => unawaited(_openWeb(roadmap: true)),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: l10n.settingsAbout,
          lead: l10n.aboutLegalese,
          children: [
            _SelfStart(
              child: PressButton.text(
                l10n.settingsAboutOpen,
                key: const Key('settings.about'),
                tone: PressTone.secondary,
                onPressed: () => context.push('/settings/about'),
              ),
            ),
            if (ref.watch(debugToolsProvider))
              _SelfStart(
                child: PressButton.text(
                  'PRF probe',
                  key: const Key('settings.prfProbe'),
                  tone: PressTone.secondary,
                  onPressed: () => context.push('/debug/prf'),
                ),
              ),
          ],
        ),
      ],
    ];
  }
}

/// `className="self-start"`: a button as wide as its label, at the start of its column.
class _SelfStart extends StatelessWidget {
  const _SelfStart({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(alignment: Alignment.centerLeft, child: child);
}

/// The server address, asked for in a sheet: [current] to start with. Pops the checked address, or
/// null. The sheet is `Sheet` as the web's delete-account one is: what it is about, the field with
/// its label, what is wrong with it, and the ways out.
class _ServerForm extends StatefulWidget {
  const _ServerForm({required this.current});

  final Uri current;

  @override
  State<_ServerForm> createState() => _ServerFormState();
}

class _ServerFormState extends State<_ServerForm> {
  late final _field = TextEditingController(text: widget.current.toString());
  final _focus = FocusNode();
  bool _invalid = false;

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final url = parseServerUrl(_field.text);
    if (url == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(url);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final wide = MediaQuery.sizeOf(context).width >= 400;
    final change = PressButton.text(
      l10n.settingsServerChange,
      key: const Key('settings.server.change'),
      onPressed: _submit,
    );
    final cancel = PressButton.text(
      l10n.cancel,
      tone: PressTone.ghost,
      onPressed: () => Navigator.of(context).pop(),
    );
    return Padding(
      padding: const EdgeInsets.only(top: WambitoTokens.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WambitoTokens.space4,
        children: [
          Text(l10n.settingsServerLead, style: LkText.body.copyWith(color: colors.ink)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WambitoTokens.space1,
            children: [
              Text(l10n.settingsServerField, style: LkText.bodySm.copyWith(color: colors.ink)),
              WebTextField(
                controller: _field,
                focusNode: _focus,
                fieldKey: const Key('settings.server.field'),
                label: l10n.settingsServerField,
                invalid: _invalid,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                onChanged: (_) {
                  if (_invalid) setState(() => _invalid = false);
                },
              ),
            ],
          ),
          if (_invalid)
            Semantics(
              liveRegion: true,
              container: true,
              child: Text(
                l10n.settingsServerInvalid,
                style: LkText.body.copyWith(color: colors.over),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: PressButton.text(
              l10n.settingsServerUseDefault,
              key: const Key('settings.server.default'),
              tone: PressTone.ghost,
              onPressed: () => setState(() {
                _field.text = defaultServerUrl.toString();
                _invalid = false;
              }),
            ),
          ),
          if (wide)
            // The ghost has 8px of padding each side, the primary 24px.
            flexOneRow(gap: WambitoTokens.space2, items: [(16, cancel), (48, change)])
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: WambitoTokens.space2,
              children: [change, cancel],
            ),
        ],
      ),
    );
  }
}
