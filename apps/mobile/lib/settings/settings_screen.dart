// The web's Settings (apps/web/app/features/settings/Settings.tsx): the page's header, its title and
// who is signed in, and a card per kind of setting, drawn with the web's parts (`parts.tsx`):
// Preferencias, "Hora y moneda", the passkeys and "Tus datos" (the import links to its page).
//
// What the web has and the app does not yet, stays on the web: the export and deleting the account
// (until their ports land). One card ("Más en la web") links to the web's public pages: the landing
// and the roadmap. What only the app has (vibration, the two local notices, the widget, the voice
// models, the server, About, signing out) is drawn in the same style: a card per kind, a muted
// line on what it is, and the web's switches and buttons.
import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../add/add_sheet.dart';
import '../api/device.dart';
import '../api/server_url.dart';
import '../api/session.dart';
import '../capture/capture_sheet.dart';
import '../capture/models_download.dart';
import '../capture/precise_offer.dart';
import '../capture/capture_language.dart' show captureLanguage;
import '../capture_auto/auto_capture_section.dart';
import '../feedback/feedback.dart';
import '../home/shell_navigation.dart';
import '../l10n/app_localizations.dart';
import '../progress/guest_warning.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/confirm_sheet.dart';
import '../ui/lk_theme.dart';
import '../ui/manage_page.dart';
import '../ui/page_header.dart';
import '../ui/press_button.dart';
import '../ui/press_link.dart';
import '../ui/sheet.dart';
import '../ui/toast.dart';
import '../ui/web_text_field.dart';
import 'assistants_section.dart';
import 'delete_account.dart';
import 'export_settings.dart';
import 'feedback.dart';
import 'passkeys_section.dart';
import 'server_status.dart';
import 'locale_resolution.dart';
import 'preferences.dart';
import 'profile_settings.dart';
import 'settings_parts.dart';
import 'time_money_section.dart';
import 'url_opener.dart';

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
/// A guest also finds "Guarda tu progreso" at the top, and is warned before anything that would
/// leave their account behind (signing out, changing server).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.webSectionsOnly = false});

  /// Draws only what the web's Settings page also has, as the web draws it: Preferencias with its
  /// language and theme choices and the sound switch, "Hora y moneda", the passkeys and "Tus datos".
  /// For the parity pictures of the page, which a story of the web's can only match that far (the
  /// app's own cards have none).
  final bool webSectionsOnly;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Signing out or changing server is under way (the old server is told, if it answers).
  bool _busy = false;

  /// How far the precise model's download is (0 to 1); null when none runs.
  double? _preciseProgress;

  // -- sign out ------------------------------------------------------------------------------

  Future<void> _signOut() async {
    final session = ref.read(sessionProvider.notifier);
    if (ref.read(sessionProvider).isGuest) {
      final choice = await warnGuestLeaving(context, GuestLeaving.signOut);
      if (!mounted || choice == null) return;
      if (choice == GuestWarning.saveInstead) {
        unawaited(context.push('/progress'));
        return;
      }
    }
    setState(() => _busy = true);
    try {
      await session.signOut(discardGuest: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -- server --------------------------------------------------------------------------------

  Future<void> _changeServer() async {
    final next = await LkSheet.show<Uri>(
      context,
      title: AppLocalizations.of(context).settingsServerTitle,
      children: [_ServerForm(current: ref.read(serverUrlProvider))],
    );
    if (!mounted || next == null) return;
    if (ref.read(sessionProvider).isGuest && next != ref.read(serverUrlProvider)) {
      final choice = await warnGuestLeaving(context, GuestLeaving.changeServer);
      if (!mounted || choice == null) return;
      if (choice == GuestWarning.saveInstead) {
        unawaited(context.push('/progress'));
        return;
      }
    }
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

  void _back() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/');
    }
  }

  // -- build ---------------------------------------------------------------------------------

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
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeOverrideProvider);
    final server = ref.watch(serverUrlProvider);
    final sound = ref.watch(soundEnabledProvider);
    final vibration = ref.watch(vibrationEnabledProvider);
    final voiceInstalled = ref.watch(voiceModelsInstalledProvider).value ?? false;
    final voice = captureLanguage(l10n.localeName);
    final preciseEligible = ref.watch(preciseEligibleProvider(voice)).value ?? false;
    final preciseInstalled = ref.watch(preciseModelInstalledProvider(voice)).value ?? false;
    final preciseProgress = _preciseProgress;
    final webOnly = widget.webSectionsOnly;
    final profile = ref.watch(settingsProfileProvider).value;
    final signedInAs = _signedInAs(l10n, guest: guest && !webOnly);
    final titleStyle = LkText.pageTitle.copyWith(color: colors.ink);
    final signedInStyle = LkText.bodySm.copyWith(color: colors.inkMuted);

    return ManagePage(
      current: 'settings',
      onAdd: () => unawaited(openAddSheet(context)),
      onMic: () => unawaited(openCapture(context, listen: true)),
      onNavigate: (to) => navigateFromShell(context, ref, to, current: 'settings'),
      header: PageHeader(
        backLabel: l10n.manageBack,
        backShort: l10n.manageBackShort,
        onBack: _back,
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WambitoTokens.space1,
          children: [
            Semantics(header: true, child: Text(l10n.settingsTitle, style: titleStyle)),
            if (signedInAs != null) Text(signedInAs, style: signedInStyle),
          ],
        ),
        if (guest && !webOnly)
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
        SettingsSection(
          title: l10n.settingsPreferences,
          children: [
            Choices<String>(
              legend: l10n.settingsLanguage,
              value:
                  locale?.languageCode ??
                  (webOnly ? Localizations.localeOf(context).languageCode : 'auto'),
              options: [
                if (!webOnly)
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
            SettingSwitch(
              key: const Key('settings.sound'),
              label: l10n.settingsSound,
              // The web's line says vibration stays on; here it is a setting of its own.
              hint: vibration ? l10n.settingsSoundHint : l10n.settingsSoundHintVibrationOff,
              value: sound,
              onChanged: (on) => unawaited(ref.read(soundEnabledProvider.notifier).set(on)),
            ),
          ],
        ),
        if (profile != null) TimeAndMoneySection(profile: profile),
        PasskeysSection(
          timeZone: profile?.timezone ?? ref.watch(deviceHintsProvider).timezone,
          guest: guest && !webOnly,
        ),
        // "Conecta tu asistente" (spec §6.2): the web has it too, but its story is not in the parity
        // pairs yet, so the web-only pictures leave it out.
        if (!webOnly)
          AssistantsSection(
            timeZone: profile?.timezone ?? ref.watch(deviceHintsProvider).timezone,
            guest: guest,
          ),
        // Android only: hidden where the capture channel does not exist.
        if (!webOnly) const AutoCaptureSection(),
        // The web's "Tus datos" (Settings.tsx): the import links to its page; the export joins it.
        SettingsSection(
          key: const Key('settings.card.data'),
          title: l10n.settingsDataTitle,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: WambitoTokens.space2,
              children: [
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
            ),
            ExportBlock(guest: guest),
          ],
        ),
        // The web's next card, and its last: in the app it is the page's last, under signing out.
        const FeedbackSection(),
        if (webOnly) const DeleteAccountCard(),
        if (!webOnly) ...[
          SettingsSection(
            title: l10n.settingsPhone,
            children: [
              SettingSwitch(
                key: const Key('settings.vibration'),
                label: l10n.settingsVibration,
                hint: l10n.settingsVibrationHint,
                value: vibration,
                onChanged: (on) => unawaited(ref.read(vibrationEnabledProvider.notifier).set(on)),
              ),
              SettingSwitch(
                key: const Key('settings.dueNotice'),
                label: l10n.settingsDueNotice,
                hint: defaultTargetPlatform == TargetPlatform.iOS
                    ? l10n.settingsDueNoticeHintIos
                    : l10n.settingsDueNoticeHint,
                value: ref.watch(dueNoticeEnabledProvider),
                onChanged: (on) => unawaited(ref.read(dueNoticeEnabledProvider.notifier).set(on)),
              ),
              SettingSwitch(
                key: const Key('settings.guestNotice'),
                label: l10n.settingsGuestNotice,
                hint: l10n.settingsGuestNoticeHint,
                value: ref.watch(guestNoticeEnabledProvider),
                onChanged: (on) => unawaited(ref.read(guestNoticeEnabledProvider.notifier).set(on)),
              ),
              // The widgets are Android's: iOS has none, so no setting about them.
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
          if (voiceInstalled)
            SettingsSection(
              title: l10n.settingsVoice,
              lead: l10n.settingsDeleteVoiceHint,
              children: [
                if (preciseEligible)
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
            ],
          ),
          SettingsSection(
            title: l10n.settingsSignOut,
            children: [
              _SelfStart(
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
            ],
          ),
          const DeleteAccountCard(),
        ],
      ],
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
