// A whole-screen step over Settings: a new recovery key's setup (the web's `Takeover` around
// `RecoveryKeySetup`, in RemoveDeviceSheet.tsx and SecuritySection.tsx). The key is shown with the
// four-character check, and `commit()` runs only after those characters are typed back, so the
// person has the key written down before it becomes the only recovery key (D17). A save that fails
// for any reason but `rotated_elsewhere` may have been saved: the screen stays with the same key, says
// so, and "Try again" calls the same `commit()` again (it is retry-safe); a rotation refused for
// sure comes back to the caller, who starts over.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../files/files_channel.dart';
import '../../l10n/app_localizations.dart';
import '../../local/keys_error.dart';
import '../../vault/recovery_key_setup_view.dart';

/// How the setup ended: saved ([value]), or refused for sure ([refused], `rotated_elsewhere`).
/// A screen left before saving pops null.
class SetupOutcome<T> {
  const SetupOutcome.saved(T this.value) : refused = null;
  const SetupOutcome.refused(Object this.refused) : value = null;

  final T? value;
  final Object? refused;
}

/// The positions the check asks for (4, 1-based); random unless a test pins them.
@visibleForTesting
List<int>? setupPositions;

class RecoverySetupPage<T> extends ConsumerStatefulWidget {
  const RecoverySetupPage({
    super.key,
    required this.recoveryKey,
    required this.commit,
    this.refused,
  });

  final String recoveryKey;

  /// Saves the key (retry-safe). Throws what the save threw.
  final Future<T> Function() commit;

  /// Whether the last failure was a refusal for good (`tampered`): a retry would say the same.
  final bool Function()? refused;

  /// Opens the page over [context]'s screen; the outcome, or null when the person gave up.
  static Future<SetupOutcome<T>?> open<T>(
    BuildContext context, {
    required String recoveryKey,
    required Future<T> Function() commit,
    bool Function()? refused,
  }) => Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<SetupOutcome<T>>(
      fullscreenDialog: true,
      builder: (_) =>
          RecoverySetupPage<T>(recoveryKey: recoveryKey, commit: commit, refused: refused),
    ),
  );

  @override
  ConsumerState<RecoverySetupPage<T>> createState() => _RecoverySetupPageState<T>();
}

class _RecoverySetupPageState<T> extends ConsumerState<RecoverySetupPage<T>> {
  var _saving = false;

  /// A save failed: the key may be kept, so it stays until it is done.
  var _failed = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final T value;
    try {
      value = await widget.commit();
    } on Object catch (error) {
      if (!mounted) return;
      if (error is KeysError &&
          (error.code == 'rotated_elsewhere' || (widget.refused?.call() ?? false))) {
        Navigator.of(context).pop(SetupOutcome<T>.refused(error));
        return;
      }
      setState(() {
        _saving = false;
        _failed = true;
      });
      return;
    }
    if (mounted) Navigator.of(context).pop(SetupOutcome<T>.saved(value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      // No way out while saving or after a failed save: the key may be the only one that works.
      canPop: !_saving && !_failed,
      child: RecoveryKeySetupView(
        recoveryKey: widget.recoveryKey,
        positions: setupPositions,
        busy: _saving,
        problem: _failed && !_saving ? l10n.settingsSecurityMaybeSaved : null,
        continueLabel: _failed ? l10n.retry : null,
        onContinue: () => unawaited(_save()),
        onCancel: _failed ? null : () => Navigator.of(context).pop(),
        onShare: (name, text) async {
          await ref.read(filesChannelProvider).shareFile(name, utf8.encode(text), 'text/plain');
        },
      ),
    );
  }
}
