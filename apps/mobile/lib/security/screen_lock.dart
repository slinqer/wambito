// The screen lock before a sensitive operation (spec section 7.7, D15, D18): removing a device,
// making a new recovery key and showing it. (Approving a device is not one of them; Task 16 does not
// use this for it.) The phone's own lock (biometrics or the PIN, through
// `local_auth`) stands in for the web's passkey touch; a phone with no lock asks the current
// recovery key instead.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../entry/sign_in_frame.dart';
import '../l10n/app_localizations.dart';
import '../local/keys_error.dart';
import '../theme/tokens.g.dart';
import '../ui/press_button.dart';
import '../ui/sheet.dart';
import '../ui/web_text_field.dart';
import '../vault/unlock_view.dart' show unlockErrorText;

/// What the phone's lock answered.
enum LockCheck {
  /// The person proved it is them.
  passed,

  /// The person closed the prompt, or it could not be shown: nothing is done.
  cancelled,

  /// The phone has no screen lock to ask: the caller asks the recovery key instead.
  noLock,
}

abstract interface class ScreenLock {
  /// Asks the phone's lock, with [reason] as the prompt's text.
  Future<LockCheck> confirm(String reason);
}

/// `local_auth`: the fingerprint or face, or the PIN, pattern or password when there is none.
class LocalAuthScreenLock implements ScreenLock {
  /// [isSupported] and [authenticate] are `local_auth`'s own, unless a test gives others.
  LocalAuthScreenLock({
    Future<bool> Function()? isSupported,
    Future<bool> Function(String reason)? authenticate,
  }) : _isSupported = isSupported ?? _platform.isDeviceSupported,
       _authenticate =
           authenticate ??
           ((reason) => _platform.authenticate(localizedReason: reason, biometricOnly: false));

  static final _platform = LocalAuthentication();

  final Future<bool> Function() _isSupported;
  final Future<bool> Function(String reason) _authenticate;

  @override
  Future<LockCheck> confirm(String reason) async {
    try {
      // False when the phone has neither a lock nor a biometric: nothing to ask.
      if (!await _isSupported()) return LockCheck.noLock;
      return await _authenticate(reason) ? LockCheck.passed : LockCheck.cancelled;
    } on LocalAuthException catch (error) {
      return error.code == LocalAuthExceptionCode.noCredentialsSet
          ? LockCheck.noLock
          : LockCheck.cancelled;
    } on Object {
      // A platform failure (a PlatformException from the support check): never escapes to the caller.
      return LockCheck.cancelled;
    }
  }
}

final screenLockProvider = Provider<ScreenLock>((ref) => LocalAuthScreenLock());

/// Asks before a sensitive operation; true when the person may go on.
///
/// The lock passed: true. The prompt closed: false. No lock on the phone: a sheet asks the current
/// recovery key, checked by [checkRecoveryKey] (`KeysError` `bad_recovery_key` or
/// `wrong_recovery_key` keep the sheet open with the reason); true once it opens the account.
Future<bool> confirmSensitive(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
  required Future<void> Function(String text) checkRecoveryKey,
}) async {
  final check = await ref.read(screenLockProvider).confirm(reason);
  if (check == LockCheck.passed) return true;
  if (check == LockCheck.cancelled || !context.mounted) return false;
  final l10n = AppLocalizations.of(context);
  final done = await LkSheet.show<bool>(
    context,
    title: l10n.screenLockTitle,
    children: [_RecoveryKeyBody(checkRecoveryKey: checkRecoveryKey)],
  );
  return done ?? false;
}

class _RecoveryKeyBody extends StatefulWidget {
  const _RecoveryKeyBody({required this.checkRecoveryKey});

  final Future<void> Function(String text) checkRecoveryKey;

  @override
  State<_RecoveryKeyBody> createState() => _RecoveryKeyBodyState();
}

class _RecoveryKeyBodyState extends State<_RecoveryKeyBody> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_busy && _text.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await widget.checkRecoveryKey(_text.text);
      if (mounted) Navigator.of(context).pop(true);
      return;
    } on KeysError catch (e) {
      error = e.code;
    } on Object {
      error = 'server';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: WambitoTokens.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WambitoTokens.space3,
        children: [
          EntryLead(l10n.screenLockLead),
          FieldCaption(l10n.vaultUnlockLabel),
          WebTextField(
            fieldKey: const Key('screenLock.key'),
            controller: _text,
            focusNode: _focus,
            label: l10n.vaultUnlockLabel,
            placeholder: l10n.vaultUnlockPlaceholder,
            invalid: _error != null,
            readOnly: _busy,
            autofocus: true,
            enableIMEPersonalizedLearning: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => unawaited(_submit()),
          ),
          if (_error != null) FieldError(unlockErrorText(l10n, _error!)),
          PressButton.text(
            _busy ? l10n.screenLockBusy : l10n.screenLockSubmit,
            key: const Key('screenLock.submit'),
            onPressed: _canSubmit ? () => unawaited(_submit()) : null,
          ),
          PressButton.text(
            l10n.cancel,
            tone: PressTone.ghost,
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}
