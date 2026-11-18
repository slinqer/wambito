// "Change keys", the twin of the web's ChangeKeysSheet (SecuritySection.tsx): a rotation of the data
// key that removes no device (`rotate(remove: [])`). Removing a device no longer rotates (it only
// deletes the wrap, `RemoveDeviceSheet`), so this is how the keys change: after "That wasn't me", or
// whenever the person wants anything saved from now on out of reach of a key someone else may hold.
// The person types the recovery key (re-wrapped, nothing new to write down), or makes a new one,
// shown through the setup screen and committed only after its four characters are typed back (the
// web has only the typed key). The caller asked the screen lock first (confirmSensitive). The
// person's devices keep working; connected assistants are disconnected; the sync takes the new keys
// and the sheet lists what was left out.
//
// What the web leaves to its caller, this does (reviews of 3b tasks 11 and 12): after a commit the
// session's `reloadKeys()` runs. A commit that fails after the rotation may have been posted is
// retried with the same prepared rotation, never a new one: the server may already hold it, and a
// second rotation would be built on a key version that is no longer the current one. While such a
// commit is pending the sheet cannot be closed (R17). A prepared rotation the person gives up on
// before its commit (leaving the new key's setup) is `forget()`ten, which zeroes the new data key
// it holds.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../entry/sign_in_frame.dart';
import '../../l10n/app_localizations.dart';
import '../../local/rotate.dart' show FreshRecovery, PreparedRotation, RotateResult, TypedRecovery;
import '../../theme/text_styles.dart';
import '../../theme/tokens.g.dart';
import '../../ui/css_text.dart';
import '../../ui/lk_theme.dart';
import '../../ui/press_button.dart';
import '../../ui/sheet.dart';
import '../../ui/web_text_field.dart';
import '../../vault/unlock_view.dart' show unlockErrorText;
import 'recovery_setup_page.dart';
import 'security_api.dart';

/// Anything but a refused key, shown under the buttons.
enum _Problem { rotatedElsewhere, tampered, offline, failed }

_Problem _problemOf(Object? error) => switch (codeOf(error)) {
  'rotated_elsewhere' => _Problem.rotatedElsewhere,
  'tampered' => _Problem.tampered,
  'offline' => _Problem.offline,
  _ => _Problem.failed,
};

/// A typed recovery key's refusal, shown on the field.
String? _keyErrorOf(Object? error) {
  final code = codeOf(error);
  return code == 'bad_recovery_key' || code == 'wrong_recovery_key' ? code : null;
}

abstract final class ChangeKeysSheet {
  /// Opens the sheet; the rotation's result once the keys changed, null when they did not (or may
  /// have: the caller reads the keys again either way). [hasPasskeys]: the account's passkeys have
  /// wraps, which a rotation drops (the sheet says so when it is done).
  static Future<RotateResult?> open(
    BuildContext context, {
    required SecurityApi security,
    bool hasPasskeys = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    final locked = ValueNotifier(false);
    RotateResult? result;
    try {
      await LkSheet.show<void>(
        context,
        title: l10n.settingsSecurityChangeKeys,
        locked: locked,
        children: [
          _ChangeKeysBody(
            security: security,
            hasPasskeys: hasPasskeys,
            onDone: (done) => result = done,
            locked: locked,
          ),
        ],
      );
    } finally {
      locked.dispose();
    }
    return result;
  }
}

class _ChangeKeysBody extends StatefulWidget {
  const _ChangeKeysBody({
    required this.security,
    required this.hasPasskeys,
    required this.onDone,
    required this.locked,
  });

  final SecurityApi security;
  final bool hasPasskeys;
  final ValueChanged<RotateResult> onDone;
  final ValueNotifier<bool> locked;

  @override
  State<_ChangeKeysBody> createState() => _ChangeKeysBodyState();
}

class _ChangeKeysBodyState extends State<_ChangeKeysBody> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  var _busy = false;
  String? _keyError;
  _Problem? _problem;
  RotateResult? _done;

  /// A prepared rotation whose commit failed after it may have been posted: "Try again" commits
  /// this one, never a new one. Forgotten (its new key zeroed) when the sheet goes.
  PreparedRotation? _pending;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    // `_pending` was attempted (its commit ran), so `forget()` would do nothing: it is just let go.
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_busy && (_pending != null || _text.text.trim().isNotEmpty);

  void _setBusy(bool busy) {
    widget.locked.value = busy;
    if (mounted) setState(() => _busy = busy);
  }

  void _asking({String? keyError, _Problem? problem}) {
    // A commit was tried and failed: the server may hold the rotation, so the sheet stays until
    // "Try again" succeeds or the server refuses it for good (R17).
    widget.locked.value = _pending != null;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _keyError = keyError;
      _problem = problem;
    });
  }

  /// A refusal before anything was sent, or the commit's own.
  void _failed(Object error) {
    final keyError = _keyErrorOf(error);
    if (keyError != null) {
      _asking(keyError: keyError);
      return;
    }
    final problem = _problemOf(error);
    if (problem == _Problem.rotatedElsewhere) {
      // The sync picks up the other device's keys; the caller reads the list again.
      unawaited(widget.security.reloadKeys().catchError((Object _) {}));
    }
    // After `tampered` the message says to stop; the caller reads the list again.
    _asking(problem: problem);
  }

  Future<void> _finish(RotateResult result) async {
    _pending = null;
    try {
      await widget.security.reloadKeys();
    } on Object {
      // The sync tries again on its own; the rotation is kept.
    }
    widget.onDone(result);
    widget.locked.value = false;
    if (mounted) {
      setState(() {
        _busy = false;
        _done = result;
      });
    }
  }

  /// Commits [prepared] (typed key). A failure that may have been saved keeps it for "Try again".
  Future<void> _commit(PreparedRotation prepared) async {
    _pending = prepared;
    _setBusy(true);
    final RotateResult result;
    try {
      result = await prepared.commit();
    } on Object catch (error) {
      // Refused for good (rotated elsewhere, tampered): a retry would say the same, so the
      // sheet is free again. Anything else may have been saved: "Try again" on the same rotation.
      if (prepared.refused) _pending = null;
      _failed(error);
      return;
    }
    await _finish(result);
  }

  Future<void> _withKey() async {
    if (!_canSubmit) return;
    final pending = _pending;
    if (pending != null) {
      await _commit(pending);
      return;
    }
    _setBusy(true);
    final PreparedRotation prepared;
    try {
      prepared = await widget.security.rotate(
        remove: const [],
        recovery: TypedRecovery(_text.text),
      );
    } on Object catch (error) {
      _failed(error);
      return;
    }
    await _commit(prepared);
  }

  Future<void> _withNewKey() async {
    if (_busy) return;
    _setBusy(true);
    final PreparedRotation prepared;
    try {
      prepared = await widget.security.rotate(remove: const [], recovery: const FreshRecovery());
    } on Object catch (error) {
      _failed(error);
      return;
    }
    if (!mounted) {
      prepared.forget();
      return;
    }
    // The key is shown, and written down, before anything reaches the server.
    final outcome = await RecoverySetupPage.open<RotateResult>(
      context,
      recoveryKey: prepared.recoveryKey!,
      commit: prepared.commit,
      refused: () => prepared.refused,
    );
    final result = outcome?.value;
    if (result != null) {
      await _finish(result);
      return;
    }
    // Gave up, or refused for sure (rotated elsewhere): the prepared rotation is dropped.
    prepared.forget();
    if (outcome == null) {
      _asking();
    } else {
      _failed(outcome.refused!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final done = _done;
    return Padding(
      padding: const EdgeInsets.only(top: WambitoTokens.space3),
      child: done != null ? _doneView(l10n, done) : _askView(l10n),
    );
  }

  Widget _doneView(AppLocalizations l10n, RotateResult done) {
    final colors = context.lkColors;
    final dropped = done.dropped;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space3,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.settingsSecurityChangeKeysDone,
            style: LkText.body.copyWith(color: colors.ink, fontWeight: FontWeight.w700),
          ),
        ),
        if (dropped.isNotEmpty) ...[
          CssParagraph(
            l10n.settingsSecurityDroppedLead,
            style: LkText.body.copyWith(color: colors.ink),
          ),
          for (final d in dropped)
            CssParagraph(
              l10n.settingsSecurityDroppedItem(
                d.label ?? l10n.settingsSecurityUnnamed,
                switch (d.reason) {
                  'removed' => 'removed',
                  'revoked' => 'revoked',
                  _ => 'other',
                },
              ),
              style: LkText.body.copyWith(color: colors.ink),
            ),
        ],
        if (widget.hasPasskeys)
          CssParagraph(
            l10n.settingsSecurityPasskeysNote,
            style: LkText.bodySm.copyWith(color: colors.inkMuted),
          ),
      ],
    );
  }

  Widget _askView(AppLocalizations l10n) {
    final colors = context.lkColors;
    final problem = _problem;
    final retrying = _pending != null;
    // After `tampered` the message says not to try again: nothing to press.
    final stopped = problem == _Problem.tampered;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space3,
      children: [
        CssParagraph(
          l10n.settingsSecurityChangeKeysBody,
          style: LkText.body.copyWith(color: colors.ink),
        ),
        FieldCaption(l10n.settingsSecurityKeyLabel),
        WebTextField(
          fieldKey: const Key('security.changeKeys.key'),
          controller: _text,
          focusNode: _focus,
          label: l10n.settingsSecurityKeyLabel,
          placeholder: l10n.vaultUnlockPlaceholder,
          invalid: _keyError != null,
          readOnly: _busy || retrying,
          enableIMEPersonalizedLearning: false,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_keyError != null) setState(() => _keyError = null);
          },
          onSubmitted: (_) => unawaited(_withKey()),
        ),
        if (_keyError != null) FieldError(unlockErrorText(l10n, _keyError!)),
        if (!stopped)
          PressButton.text(
            _busy
                ? l10n.settingsSecurityChanging
                : retrying
                ? l10n.retry
                : l10n.settingsSecurityChangeKeys,
            key: const Key('security.changeKeys.confirm'),
            tone: PressTone.secondary,
            onPressed: _canSubmit ? () => unawaited(_withKey()) : null,
          ),
        if (!retrying && !stopped)
          PressButton.text(
            l10n.settingsSecurityOrNew,
            key: const Key('security.changeKeys.newKey'),
            tone: PressTone.ghost,
            onPressed: _busy ? null : () => unawaited(_withNewKey()),
          ),
        if (problem != null)
          FieldError(switch (problem) {
            _Problem.offline => l10n.vaultUnlockErrorOffline,
            _Problem.rotatedElsewhere => l10n.settingsSecurityRotatedElsewhere,
            _Problem.tampered => l10n.settingsSecurityTampered,
            _Problem.failed => l10n.settingsSecurityChangeKeysFailed,
          }),
      ],
    );
  }
}
