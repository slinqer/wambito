// The export in "Tus datos": the web's apps/web/app/features/settings/use-export.ts and the export
// block of Settings.tsx. The web fetches the file and hands it to the browser's download; the phone
// fetches it the same way and asks what to do with it: save it where the person chooses
// (`ACTION_CREATE_DOCUMENT`) or share it (the share sheet), both through lib/files.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/session.dart';
import '../files/files_channel.dart';
import '../home/home_repository.dart';
import '../l10n/app_localizations.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/confirm_sheet.dart';
import '../ui/css_text.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/toast.dart';
import '../vault/preview.dart';
import 'account_repository.dart';
import 'profile_settings.dart';
import 'settings_parts.dart';

/// The format being prepared, null when none is (the web's `busy`): while one is, both buttons are
/// off, so a second tap asks nothing.
class ExportBusy extends Notifier<ExportFormat?> {
  @override
  ExportFormat? build() => null;

  void set(ExportFormat? format) => state = format;
}

final exportBusyProvider = NotifierProvider<ExportBusy, ExportFormat?>(ExportBusy.new);

enum _ExportChoice { save, share }

/// Downloads the export (`GET /v1/me/export`) and asks what to do with it. A failure is a toast on
/// this page, in the catalogue's words, as the web's is.
Future<void> runExport(BuildContext context, ExportFormat format) async {
  final container = ProviderScope.containerOf(context);
  final busy = container.read(exportBusyProvider.notifier);
  if (container.read(exportBusyProvider) != null) return;
  final toasts = ToastHost.of(context);
  final l10n = AppLocalizations.of(context);
  busy.set(format);
  final ExportFile file;
  try {
    file = await container.read(accountRepositoryProvider).export(format);
  } on Object catch (error) {
    final failure = error is HomeFailure ? error : const HomeFailure(0);
    // The server no longer knows the session: signed out, as every other call ends it.
    if (failure.unauthorized) {
      unawaited(container.read(sessionProvider.notifier).signOut(discardGuest: true));
    }
    toasts.say(profileFailureMessage(l10n, failure), error: true);
    return;
  } finally {
    busy.set(null);
  }
  if (!context.mounted) return;
  final choice = await ChoiceSheet.show<_ExportChoice>(
    context,
    title: l10n.settingsExportReadyTitle,
    body: l10n.settingsExportReadyBody(file.name),
    choices: [
      SheetChoice(
        label: l10n.settingsExportSave,
        value: _ExportChoice.save,
        tone: PressTone.primary,
        key: const Key('settings.export.save'),
      ),
      SheetChoice(
        label: l10n.settingsExportShare,
        value: _ExportChoice.share,
        key: const Key('settings.export.share'),
      ),
    ],
  );
  if (choice == null) return;
  final files = container.read(filesChannelProvider);
  switch (choice) {
    case _ExportChoice.save:
      try {
        // False: the person closed the picker. Nothing was saved, and nothing to say.
        if (await files.saveFile(file.name, file.bytes, file.mime)) {
          toasts.say(l10n.settingsExportSaved(file.name));
        }
      } on Object {
        toasts.say(l10n.settingsExportSaveFailed, error: true);
      }
    case _ExportChoice.share:
      // The share sheet is the feedback: only a failure is said.
      try {
        await files.shareFile(file.name, file.bytes, file.mime);
      } on FilesFailure catch (failure) {
        toasts.say(
          failure.kind == FilesFailureKind.unavailable
              ? l10n.settingsExportShareFailed
              : l10n.errorGeneric,
          error: true,
        );
      } on Object {
        toasts.say(l10n.errorGeneric, error: true);
      }
  }
}

/// The export's block in "Tus datos": its name and what it gives, and the two buttons (the web's
/// `flex flex-wrap gap-2`). A guest has no email to export under: both are off, and a line says why.
class ExportBlock extends ConsumerWidget {
  const ExportBlock({super.key, required this.guest});

  final bool guest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final busy = ref.watch(exportBusyProvider);
    // The export is the server's (`GET /v1/me/export`); an encrypted account's data is on the phone.
    if (ref.watch(isPreviewProvider)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: WambitoTokens.space2,
        children: [
          SettingLabel(label: l10n.settingsExportTitle),
          const ComingSoonNotice(key: Key('settings.export.comingSoon')),
        ],
      );
    }
    VoidCallback? press(ExportFormat format) =>
        guest || busy != null ? null : () => unawaited(runExport(context, format));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: WambitoTokens.space2,
      children: [
        SettingLabel(label: l10n.settingsExportTitle, hint: l10n.settingsExportLead),
        Wrap(
          spacing: WambitoTokens.space2,
          runSpacing: WambitoTokens.space2,
          children: [
            PressButton.text(
              l10n.settingsExportJson,
              key: const Key('settings.export.json'),
              tone: PressTone.secondary,
              onPressed: press(ExportFormat.json),
            ),
            PressButton.text(
              l10n.settingsExportCsv,
              key: const Key('settings.export.csv'),
              tone: PressTone.secondary,
              onPressed: press(ExportFormat.csv),
            ),
          ],
        ),
        if (guest)
          CssParagraph(
            l10n.settingsExportGuest,
            style: LkText.bodySm.copyWith(color: colors.inkMuted),
          ),
      ],
    );
  }
}
