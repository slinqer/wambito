// Captura (`/settings/capture`, phone only), the light version (spec 2026-11-22, "Captura,
// inside"): groups with an icon head and one-line rows. "Captura automática" (Android, its own file
// `AutoCaptureSection`), "Voz" (only with a model installed: the precise model's switch and the red
// "Borrar los modelos de voz"), "Avisos" ("Hoy vence…" and, for a plain account, the guest warning)
// and "Widget" (Android: "Añadir widget" while none is on the home screen, "Ocultar el monto").
import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capture/capture_language.dart' show captureLanguage;
import '../capture/models_download.dart';
import '../capture/precise_offer.dart';
import '../capture_auto/auto_capture_section.dart';
import '../home/widget_card.dart';
import '../l10n/app_localizations.dart';
import '../theme/tokens.g.dart';
import '../ui/confirm_sheet.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/toast.dart';
import '../vault/preview.dart';
import 'preferences.dart';
import 'settings_parts.dart';
import 'settings_screen.dart' show preciseModelInstalledProvider, voiceModelsInstalledProvider;

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  /// How far the precise model's download is (0 to 1); null when none runs.
  double? _preciseProgress;

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

  /// The precise model's switch: on downloads it (the progress replaces the line), off deletes it
  /// alone; Vosk's model stays.
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
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final tint = colors.inkMuted;
    final android = defaultTargetPlatform == TargetPlatform.android;
    final preview = ref.watch(isPreviewProvider);
    final voiceInstalled = ref.watch(voiceModelsInstalledProvider).value ?? false;
    final voice = captureLanguage(l10n.localeName);
    final preciseEligible = ref.watch(preciseEligibleProvider(voice)).value ?? false;
    final preciseInstalled = ref.watch(preciseModelInstalledProvider(voice)).value ?? false;
    final preciseProgress = _preciseProgress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space3,
      children: [
        // Android only: hidden where the capture channel does not exist.
        const AutoCaptureSection(),
        if (voiceInstalled)
          SettingsGroup(
            key: const Key('settings.card.voice'),
            head: SettingsGroupHead(
              icon: LkIcon(LkIconName.mic, size: 22, color: colors.brand),
              title: l10n.settingsVoice,
              line: l10n.settingsVoiceLine,
            ),
            rows: [
              // On iOS the voice model is the precise one, and the delete row covers it.
              if (preciseEligible && defaultTargetPlatform != TargetPlatform.iOS)
                SettingsRow(
                  key: const Key('settings.voicePrecise'),
                  icon: LkIcon(LkIconName.wand, size: 20, color: tint),
                  title: l10n.settingsVoicePrecise,
                  line: preciseProgress == null
                      ? l10n.settingsVoicePreciseLine(
                          ((preciseModels[voice]?.bytes ?? 0) / 1e6).round(),
                        )
                      : l10n.captureDownloading((preciseProgress * 100).floor()),
                  trailing: RowSwitch(
                    value: preciseInstalled || preciseProgress != null,
                    onChanged: (on) => unawaited(_setPrecise(voice, on: on)),
                  ),
                ),
              SettingsRow(
                key: const Key('settings.deleteVoice'),
                icon: LkIcon(LkIconName.trash, size: 20, color: colors.over),
                title: l10n.settingsDeleteVoice,
                line: l10n.settingsDeleteVoiceHint,
                danger: true,
                trailing: const RowNone(),
                onTap: () => unawaited(_deleteVoice()),
              ),
            ],
          ),
        SettingsGroup(
          key: const Key('settings.card.notices'),
          head: SettingsGroupHead(
            icon: LkIcon(LkIconName.bell, size: 22, color: colors.brand),
            title: l10n.settingsNotices,
            line: l10n.settingsNoticesLine,
          ),
          rows: [
            // "Hoy vence…" is computed on the phone for an encrypted account (lib/notices/due_list.dart).
            SettingsRow(
              key: const Key('settings.dueNotice'),
              icon: LkIcon(LkIconName.calendar, size: 20, color: tint),
              title: l10n.settingsDueNotice,
              line: defaultTargetPlatform == TargetPlatform.iOS
                  ? l10n.settingsDueNoticeHintIos
                  : l10n.settingsDueNoticeHint,
              semanticsHint: defaultTargetPlatform == TargetPlatform.iOS
                  ? l10n.settingsDueNoticeFullIos
                  : l10n.settingsDueNoticeFull,
              trailing: RowSwitch(
                value: ref.watch(dueNoticeEnabledProvider),
                onChanged: (on) => unawaited(ref.read(dueNoticeEnabledProvider.notifier).set(on)),
              ),
            ),
            // The 45-day guest warning is a `plain` guest's: an encrypted guest is kept 12 or 24
            // months and never gets it (lib/notices/notice_sync.dart).
            if (!preview)
              SettingsRow(
                key: const Key('settings.guestNotice'),
                icon: LkIcon(LkIconName.info, size: 20, color: tint),
                title: l10n.settingsGuestNotice,
                line: l10n.settingsGuestNoticeHint,
                semanticsHint: l10n.settingsGuestNoticeFull,
                trailing: RowSwitch(
                  value: ref.watch(guestNoticeEnabledProvider),
                  onChanged: (on) =>
                      unawaited(ref.read(guestNoticeEnabledProvider.notifier).set(on)),
                ),
              ),
          ],
        ),
        // The widgets are Android's: iOS has none, so no setting about them.
        if (android)
          SettingsGroup(
            key: const Key('settings.card.widget'),
            head: SettingsGroupHead(
              icon: LkIcon(LkIconName.widget, size: 22, color: colors.brand),
              title: l10n.settingsWidget,
              line: l10n.settingsWidgetLine,
            ),
            rows: [
              if (ref.watch(widgetOnHomeProvider).value == false)
                SettingsRow(
                  key: const Key('settings.addWidget'),
                  icon: LkIcon(LkIconName.plus, size: 20, color: tint),
                  title: l10n.settingsAddWidget,
                  line: l10n.settingsAddWidgetHint,
                  trailing: const RowChevron(),
                  onTap: () => unawaited(addWidget(context, ref)),
                ),
              SettingsRow(
                key: const Key('settings.hideAmount'),
                icon: LkIcon(LkIconName.eyeOff, size: 20, color: tint),
                title: l10n.settingsHideAmount,
                line: l10n.settingsHideAmountHint,
                trailing: RowSwitch(
                  value: ref.watch(hideWidgetAmountProvider),
                  onChanged: (on) => unawaited(ref.read(hideWidgetAmountProvider.notifier).set(on)),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
