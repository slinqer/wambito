import 'dart:async';

import 'package:flutter/widgets.dart';

import '../home/home_widgets.dart' show QuietSpinner;
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/failure_row.dart';
import '../ui/keypad.dart';
import '../ui/press_button.dart';
import '../ui/sheet.dart' show compactFooterBelow;
import 'add_session.dart';
import 'save_outcome.dart';

/// What is pinned at the bottom of the sheet, so every key and Guardar are in view even on a short
/// phone: the keypad, and Guardar (with Eliminar beside it when editing). A refused or failed save
/// is said above them, with Reintentar when sending it again can work.
class AddFooter extends StatelessWidget {
  const AddFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AddSession.of(context);
    final form = session.form;
    if (form == null) return const SizedBox.shrink();
    final l10n = session.l10n;
    final failure = session.failure;
    final editing = form.editing != null;
    final compact = MediaQuery.sizeOf(context).height < compactFooterBelow;
    // With the phone's keyboard up (typing a name), it takes the keypad's place.
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    // `.lk-sheet-footer`: a gap of `--space-2` between its parts, `--space-1` on a short phone.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: compact ? WambitoTokens.space1 : WambitoTokens.space2,
      children: [
        if (failure != null)
          SaveFailureRow(
            message: saveFailureMessage(l10n, failure),
            retryLabel: canRetrySave(failure) ? l10n.retry : null,
            onRetry: () => unawaited(session.save()),
            retryKey: const Key('add.retry'),
          ),
        if (!keyboardUp)
          Keypad(
            value: form.raw,
            currentValue: () => form.raw,
            onChange: (next) {
              if (!session.saving) form.setRaw(next);
            },
            locale: l10n.localeName,
            currency: form.currency,
            compact: compact,
          ),
        Row(
          spacing: WambitoTokens.space2,
          children: [
            if (editing)
              PressButton.text(
                l10n.addDelete,
                key: const Key('add.delete'),
                // A destructive action: the delete colour.
                tone: PressTone.danger,
                horizontalPadding: WambitoTokens.space4,
                onPressed: session.saving ? null : session.delete,
              ),
            Expanded(
              child: PressButton(
                key: const Key('add.save'),
                horizontalPadding: WambitoTokens.space4,
                onPressed: form.valid && !session.saving ? () => unawaited(session.save()) : null,
                child: session.saving
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: WambitoTokens.space2,
                        children: [const QuietSpinner(), Text(LkText.upperCase(l10n.addSaving))],
                      )
                    : Text(LkText.upperCase(editing ? l10n.addSaveChanges : l10n.addSave)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
