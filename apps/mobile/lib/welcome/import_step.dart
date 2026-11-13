// The welcome's import: the web's ImportStep (apps/web/app/features/onboarding/ImportStep.tsx).
// "¿Vienes de otra app?": a list of sources, before the categories (so they can start from what the
// file brings). Budge opens a short how-to and the file picker, then the preview (transactions,
// duplicates, rows with problems, new categories) and the confirm; the others are "Pronto" for now.
// "No, empiezo de cero" and SALTAR move on without importing (SALTAR drops a pending preview).
import 'package:flutter/material.dart';

import '../import/import_panel.dart';
import '../import/import_state.dart';
import '../l10n/app_localizations.dart';
import '../vault/preview.dart';
import 'step_frame.dart';
import 'steps.dart';

class ImportStep extends StatelessWidget {
  const ImportStep({
    super.key,
    required this.state,
    required this.onChoose,
    required this.onConfirm,
    required this.onDiscard,
    required this.onSource,
    this.onRetry,
    this.prefillBasis,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
    this.busy = false,
    this.locked = false,
    this.preview = false,
  });

  final ImportState state;

  /// Shows the document picker (the web's file input).
  final VoidCallback onChoose;
  final VoidCallback onConfirm;

  /// Drops the preview, to pick another file.
  final VoidCallback onDiscard;

  /// From the list of sources to Budge's how-to and picker (true), and back (false).
  final void Function({required bool budge}) onSource;

  /// After an import whose follow-up (reading the categories again) failed.
  final VoidCallback? onRetry;

  /// Where prefilled budgets came from, shown under the result.
  final String? prefillBasis;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  /// A write of the welcome is in flight.
  final bool busy;

  /// A file is being read, confirmed or discarded: SALTAR and Back wait.
  final bool locked;

  /// The account is `preview` (lib/vault/preview.dart): its data is on the phone and the server's
  /// import is not offered; the step says it waits for encryption and moves on.
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = this.state;
    final skip = StepAction(label: l10n.welcomeSkip, onPressed: busy || locked ? null : onSkip);
    StepAction plain({bool disabled = false}) =>
        StepAction(label: l10n.welcomeNext, onPressed: busy || disabled ? null : onNext);
    final next = switch (state) {
      ImportSources() || ImportIdle() => plain(),
      ImportReading() => StepAction(label: l10n.importReading),
      ImportPreview() =>
        newRows(state.preview) == 0
            ? plain()
            : StepAction(
                label: state.confirming
                    ? l10n.importImporting
                    : l10n.importConfirm(newRows(state.preview)),
                key: const Key('import.confirm'),
                onPressed: state.confirming || state.discarding || busy ? null : onConfirm,
              ),
      ImportImported() => plain(disabled: state.retrying),
    };
    return StepFrame(
      step: StepId.import,
      title: l10n.welcomeImportTitle,
      lead: !preview && state is ImportSources ? l10n.welcomeImportLead : null,
      onBack: onBack,
      backDisabled: busy || locked,
      skip: preview || state is ImportImported ? null : skip,
      next: preview ? plain() : next,
      children: [
        if (preview)
          const ComingSoonNotice(key: Key('welcome.import.comingSoon'))
        else
          ImportPanel(
            state: state,
            onChoose: onChoose,
            onDiscard: onDiscard,
            onSource: onSource,
            onRetry: onRetry,
            prefillBasis: prefillBasis,
            onFresh: busy || locked ? null : onSkip,
          ),
      ],
    );
  }
}
