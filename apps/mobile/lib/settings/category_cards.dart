// What each settings category holds, for now the long page's own cards, regrouped (a later task
// redraws them): `SettingsCategoryScreen` builds the cards of one `SettingsCategory` inside
// `SettingsCategoryPage`. The state it keeps (a server change under way, the precise voice model's
// download) is what those cards need.
import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/device.dart';
import '../api/server_url.dart';
import '../api/session.dart';
import '../capture/models_download.dart';
import '../capture/precise_offer.dart';
import '../capture/capture_language.dart' show captureLanguage;
import '../capture_auto/auto_capture_section.dart';
import '../feedback/feedback.dart';
import '../home/widget_card.dart';
import '../l10n/app_localizations.dart';
import '../progress/guest_warning.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/confirm_sheet.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/press_link.dart';
import '../ui/pressable.dart';
import '../ui/sheet.dart';
import '../ui/toast.dart';
import '../ui/web_text_field.dart';
import '../vault/preview.dart';
import '../vault/unsynced_sheet.dart';
import '../vault/vault_providers.dart' show vaultSessionProvider;
import 'assistants_section.dart';
import 'delete_account.dart';
import 'export_settings.dart';
import 'feedback.dart';
import 'passkeys_section.dart';
import 'server_status.dart';
import 'locale_resolution.dart';
import 'preferences.dart';
import 'profile_settings.dart';
import 'security/security_section.dart';
import 'settings_parts.dart';
import 'time_money_section.dart';
import 'url_opener.dart';
import 'category_screen.dart';
import 'leave_guard.dart';
import 'settings_categories.dart';
import 'settings_screen.dart'
    show debugToolsProvider, preciseModelInstalledProvider, voiceModelsInstalledProvider;

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

  /// How far the precise model's download is (0 to 1); null when none runs.
  double? _preciseProgress;

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

  Future<void> _deleteVoice() async {
    final toasts = ToastHost.of(context);
    final l10n = AppLocalizations.of(context);
    final models = ref.read(modelStoreProvider);
    final done = await ConfirmSheet.show(
      context,
      title: l10n.settingsDeleteVoiceTitle,
      body: l10n.settingsDeleteVoiceBody,
      confirmLabel: l10n.settingsDeleteVoiceConfirm,
      confirmKey: const Key('settings.deleteVoice.confirm'),
      onConfirm: () async {
        try {
          await models.deleteModels();
        } on Object {
          // The sheet stays for another try, and says why.
          toasts.say(l10n.settingsDeleteVoiceFailed, error: true);
          rethrow;
        }
        toasts.say(l10n.settingsDeleteVoiceDone);
      },
    );
    if (done && mounted) {
      ref.invalidate(voiceModelsInstalledProvider);
      ref.invalidate(preciseModelInstalledProvider);
    }
  }

  /// The precise model's switch: on downloads it (the bar's percentage replaces the hint), off
  /// deletes it alone; Vosk's model stays.
  Future<void> _setPrecise(String locale, {required bool on}) async {
    if (_preciseProgress != null) return;
    final toasts = ToastHost.of(context);
    final l10n = AppLocalizations.of(context);
    final store = ref.read(preciseModelStoreProvider);
    final offer = ref.read(preciseOfferProvider(locale));
    try {
      if (on) {
        setState(() => _preciseProgress = 0);
        await store.download(
          locale,
          onProgress: (received, total) {
            if (mounted && total > 0) setState(() => _preciseProgress = received / total);
          },
        );
      } else {
        await store.deleteModel(locale);
      }
      // The switch is the person's answer: on or off, the capture sheet's one-time offer is done.
      await offer.answer(accepted: on);
    } on Object {
      toasts.say(
        on ? l10n.settingsVoicePreciseFailed : l10n.settingsDeleteVoiceFailed,
        error: true,
      );
    } finally {
      // Settings may have been left during the download: nothing to refresh then.
      if (mounted) {
        setState(() => _preciseProgress = null);
        ref.invalidate(preciseModelInstalledProvider(locale));
      }
    }
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
        PasskeysSection(
          timeZone: timeZone,
          // A `preview` guest adds a passkey here too ("Protect your data" step 2).
          guest: guest && !webOnly && !preview,
        ),
        // An encrypted account's devices and recovery key, with or without email. Plain accounts
        // see nothing of it.
        if (!webOnly && preview) SecuritySection(timeZone: timeZone),
        const DeleteAccountCard(),
      ],
      SettingsCategory.preferences => [
        PreferencesCard(webSectionsOnly: webOnly),
        if (profile != null) TimeAndMoneySection(profile: profile),
      ],
      SettingsCategory.capture => _capture(context, preview: preview),
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

  List<Widget> _capture(BuildContext context, {required bool preview}) {
    if (widget.webSectionsOnly) return const [];
    final l10n = AppLocalizations.of(context);
    final voiceInstalled = ref.watch(voiceModelsInstalledProvider).value ?? false;
    final voice = captureLanguage(l10n.localeName);
    final preciseEligible = ref.watch(preciseEligibleProvider(voice)).value ?? false;
    final preciseInstalled = ref.watch(preciseModelInstalledProvider(voice)).value ?? false;
    final preciseProgress = _preciseProgress;
    return [
      // Android only: hidden where the capture channel does not exist.
      const AutoCaptureSection(),
      if (voiceInstalled)
        SettingsSection(
          title: l10n.settingsVoice,
          lead: l10n.settingsDeleteVoiceHint,
          children: [
            // On iOS the voice model is the precise one, and its row above covers it.
            if (preciseEligible && defaultTargetPlatform != TargetPlatform.iOS)
              SettingSwitch(
                key: const Key('settings.voicePrecise'),
                label: l10n.settingsVoicePrecise(
                  ((preciseModels[voice]?.bytes ?? 0) / 1e6).round(),
                ),
                hint: preciseProgress == null
                    ? l10n.settingsVoicePreciseHint
                    : l10n.captureDownloading((preciseProgress * 100).floor()),
                value: preciseInstalled || preciseProgress != null,
                onChanged: (on) => unawaited(_setPrecise(voice, on: on)),
              ),
            _SelfStart(
              child: PressButton.text(
                l10n.settingsDeleteVoice,
                key: const Key('settings.deleteVoice'),
                tone: PressTone.secondary,
                onPressed: _deleteVoice,
              ),
            ),
          ],
        ),
      SettingsSection(
        title: l10n.settingsPhone,
        children: [
          // "Hoy vence…" is computed on the phone for an encrypted account (lib/notices/due_list.dart).
          SettingSwitch(
            key: const Key('settings.dueNotice'),
            label: l10n.settingsDueNotice,
            hint: defaultTargetPlatform == TargetPlatform.iOS
                ? l10n.settingsDueNoticeHintIos
                : l10n.settingsDueNoticeHint,
            value: ref.watch(dueNoticeEnabledProvider),
            onChanged: (on) => unawaited(ref.read(dueNoticeEnabledProvider.notifier).set(on)),
          ),
          // The 45-day guest warning is a `plain` guest's: an encrypted guest is kept 12 or 24
          // months and never gets it (lib/notices/notice_sync.dart).
          if (!preview)
            SettingSwitch(
              key: const Key('settings.guestNotice'),
              label: l10n.settingsGuestNotice,
              hint: l10n.settingsGuestNoticeHint,
              value: ref.watch(guestNoticeEnabledProvider),
              onChanged: (on) => unawaited(ref.read(guestNoticeEnabledProvider.notifier).set(on)),
            ),
          // The widgets are Android's: iOS has none, so no setting about them.
          if (defaultTargetPlatform == TargetPlatform.android &&
              ref.watch(widgetOnHomeProvider).value == false)
            _AddWidgetRow(key: const Key('settings.addWidget')),
          if (defaultTargetPlatform == TargetPlatform.android)
            SettingSwitch(
              key: const Key('settings.hideAmount'),
              label: l10n.settingsHideAmount,
              hint: l10n.settingsHideAmountHint,
              value: ref.watch(hideWidgetAmountProvider),
              onChanged: (on) => unawaited(ref.read(hideWidgetAmountProvider.notifier).set(on)),
            ),
        ],
      ),
    ];
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

/// "Añadir widget": asks the launcher, or shows the steps; there only until a widget is on the home
/// screen (Android).
class _AddWidgetRow extends ConsumerWidget {
  const _AddWidgetRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    return Pressable(
      label: l10n.settingsAddWidget,
      hint: l10n.settingsAddWidgetHint,
      onPressed: () => unawaited(addWidget(context, ref)),
      builder: (context, state) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          spacing: WambitoTokens.space3,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: WambitoTokens.space1,
                children: [
                  Text(l10n.settingsAddWidget, style: LkText.body.copyWith(color: colors.ink)),
                  Text(
                    l10n.settingsAddWidgetHint,
                    style: LkText.fieldLabel.copyWith(
                      color: colors.inkMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            ExcludeSemantics(
              child: Text('›', style: LkText.label.copyWith(color: colors.inkMuted)),
            ),
          ],
        ),
      ),
    );
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
