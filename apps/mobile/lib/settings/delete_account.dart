// The web's DeleteAccount (apps/web/app/features/settings/DeleteAccount.tsx): a card with a button,
// and a sheet that says what goes, offers the export first ("Descarga tus datos antes"), and only
// enables "Sí, eliminar mi cuenta" once the account's email is typed (case and surrounding spaces
// don't matter). Then the account goes (lib/settings/account_deletion.dart) and the person lands on
// the entry screen. A failed delete stays in the sheet and says why.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/session.dart';
import '../home/home_repository.dart';
import '../l10n/app_localizations.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/confirm_sheet.dart' show flexOneRow;
import '../ui/css_text.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/sheet.dart';
import '../ui/toast.dart';
import '../ui/web_text_field.dart';
import 'account_deletion.dart';
import 'account_repository.dart';
import 'export_settings.dart';
import 'profile_settings.dart';
import 'settings_model.dart';
import 'settings_parts.dart';
import 'settings_screen.dart' show settingsEmailProvider;

/// The red row at the foot of Cuenta y seguridad. A guest has no email to confirm with, so the row is off and
/// a line says an email comes first (the same for the export).
class DeleteAccountCard extends ConsumerWidget {
  const DeleteAccountCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final guest = ref.watch(sessionProvider.select((s) => s.isGuest));
    final email = ref.watch(settingsEmailProvider);
    final known = email.value;
    // An account whose email the phone could not read (no connection) cannot type it either.
    final unknown = !guest && !email.isLoading && known == null;
    final note = guest
        ? l10n.settingsAccountDeleteGuest
        : unknown
        ? l10n.errorNetwork
        : null;
    final enabled = !guest && known != null;
    return SettingsGroup(
      key: const Key('settings.card.delete'),
      rows: [
        SettingsRow(
          key: const Key('settings.delete'),
          danger: true,
          icon: LkIcon(LkIconName.trash, size: 20, color: colors.over),
          title: l10n.settingsAccountDeleteTitle,
          line: l10n.settingsAccountDeleteLine,
          trailing: const RowChevron(),
          onTap: enabled ? () => unawaited(_open(context, known)) : null,
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: CssParagraph(note, style: LkText.bodySm.copyWith(color: colors.inkMuted)),
          ),
      ],
    );
  }

  Future<void> _open(BuildContext context, String email) async {
    // While the DELETE is on its way the person cannot close the sheet, as the web's `close()`
    // ignores `busy`: the form turns this on and off.
    final busy = ValueNotifier(false);
    try {
      await LkSheet.show<bool>(
        context,
        title: AppLocalizations.of(context).settingsAccountDeleteSheetTitle,
        locked: busy,
        children: [_DeleteForm(email: email, busy: busy)],
      );
    } finally {
      busy.dispose();
    }
  }
}

class _DeleteForm extends ConsumerStatefulWidget {
  const _DeleteForm({required this.email, required this.busy});

  final String email;

  /// Told whether a delete is under way, for the sheet around the form.
  final ValueNotifier<bool> busy;

  @override
  ConsumerState<_DeleteForm> createState() => _DeleteFormState();
}

class _DeleteFormState extends ConsumerState<_DeleteForm> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _ready => emailMatches(_field.text, widget.email);

  Future<void> _remove() async {
    // Set at once, not after a frame: a double tap, or Enter and a tap together, send one DELETE.
    if (!_ready || _busy) return;
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final toasts = ToastHost.of(context);
    widget.busy.value = true;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountDeletionProvider).delete();
    } on AccountSessionExpired {
      // Signed out, with the account still there: say so where the person is now (entry).
      toasts.say(l10n.settingsAccountDeleteExpired, error: true);
      if (mounted) {
        widget.busy.value = false;
        navigator.pop(false);
      }
      return;
    } on Object catch (error) {
      final failure = error is HomeFailure ? error : const HomeFailure(0, code: 'internal_error');
      final message = profileFailureMessage(l10n, failure);
      if (!mounted) {
        // Something other than the person closed the sheet meanwhile: the failure is still said.
        toasts.say(message, error: true);
        return;
      }
      widget.busy.value = false;
      setState(() {
        _busy = false;
        _error = message;
      });
      return;
    }
    widget.busy.value = false;
    // The session is over and entry is showing under the sheet: the sheet goes.
    if (mounted) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final exporting = ref.watch(exportBusyProvider) != null;
    final wide = MediaQuery.sizeOf(context).width >= 400;
    final confirm = PressButton(
      key: const Key('settings.delete.confirm'),
      tone: PressTone.secondary,
      onPressed: !_ready || _busy ? null : _remove,
      child: Text(
        LkText.upperCase(_busy ? l10n.settingsAccountDeleting : l10n.settingsAccountDeleteConfirm),
        style: TextStyle(color: colors.over),
      ),
    );
    final cancel = PressButton.text(
      l10n.cancel,
      key: const Key('settings.delete.cancel'),
      tone: PressTone.ghost,
      onPressed: _busy ? null : () => Navigator.of(context).pop(false),
    );
    return Padding(
      padding: const EdgeInsets.only(top: WambitoTokens.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WambitoTokens.space4,
        children: [
          CssParagraph(
            l10n.settingsAccountDeleteSheetBody,
            style: LkText.body.copyWith(color: colors.ink),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: PressButton.text(
              l10n.settingsAccountDeleteExportFirst,
              key: const Key('settings.delete.export'),
              tone: PressTone.secondary,
              onPressed: exporting || _busy
                  ? null
                  : () => unawaited(runExport(context, ExportFormat.json)),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WambitoTokens.space1,
            children: [
              Text(
                l10n.settingsAccountDeleteConfirmLabel,
                style: LkText.bodySm.copyWith(color: colors.ink),
              ),
              WebTextField(
                controller: _field,
                focusNode: _focus,
                fieldKey: const Key('settings.delete.field'),
                label: l10n.settingsAccountDeleteConfirmLabel,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_remove()),
                onChanged: (_) => setState(() {}),
              ),
              CssParagraph(
                l10n.settingsAccountDeleteConfirmHint(widget.email),
                style: LkText.fieldLabel.copyWith(color: colors.inkMuted),
              ),
            ],
          ),
          if (_error != null)
            Semantics(
              liveRegion: true,
              container: true,
              child: CssParagraph(
                _error!,
                key: const Key('settings.delete.error'),
                style: LkText.body.copyWith(color: colors.over),
              ),
            ),
          if (wide)
            // The ghost has 8px of padding each side, the secondary 24px and a 2px border.
            flexOneRow(gap: WambitoTokens.space2, items: [(16, cancel), (52, confirm)])
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: WambitoTokens.space2,
              children: [confirm, cancel],
            ),
        ],
      ),
    );
  }
}
