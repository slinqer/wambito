// Twin of apps/web/app/features/settings/RemoveDeviceSheet.tsx. Removing a device rotates the data
// key (stage 2b Ruling 2, D15): the person types the recovery key (re-wrapped, nothing new to write
// down), or makes a new one, shown through the setup screen and committed only after its four
// characters are typed back. The caller asked the screen lock first (confirmSensitive). Then the
// sync takes the new keys and the sheet lists what was left out.
//
// What the web leaves to its caller, this does (reviews of 3b tasks 11 and 12): after a commit the
// session's `reloadKeys()` runs; a commit that fails after the rotation was posted is retried with
// the same prepared rotation (never a new one); a prepared rotation the person gives up on is
// `forget()`ten, which zeroes the new data key it holds.
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
import 'security_model.dart';

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

abstract final class RemoveDeviceSheet {
  /// Opens the sheet for [device] (never this phone's own). [hasPasskeys]: the account's passkeys
  /// have wraps, which a rotation drops (the sheet says so when it is done). [onChanged]: the
  /// account's keys changed (or may have): read them again.
  static Future<void> show(
    BuildContext context, {
    required DeviceRow device,
    required SecurityApi security,
    required bool hasPasskeys,
    required VoidCallback onChanged,
  }) async {
    final l10n = AppLocalizations.of(context);
    final locked = ValueNotifier(false);
    try {
      await LkSheet.show<void>(
        context,
        title: l10n.settingsSecurityRemoveTitle(device.label ?? l10n.settingsSecurityUnnamed),
        locked: locked,
        children: [
          _RemoveBody(
            device: device,
            security: security,
            hasPasskeys: hasPasskeys,
            onChanged: onChanged,
            locked: locked,
          ),
        ],
      );
    } finally {
      locked.dispose();
    }
  }
}

class _RemoveBody extends StatefulWidget {
  const _RemoveBody({
    required this.device,
    required this.security,
    required this.hasPasskeys,
    required this.onChanged,
    required this.locked,
  });

  final DeviceRow device;
  final SecurityApi security;
  final bool hasPasskeys;
  final VoidCallback onChanged;
  final ValueNotifier<bool> locked;

  @override
  State<_RemoveBody> createState() => _RemoveBodyState();
}

class _RemoveBodyState extends State<_RemoveBody> {
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
      // The sync picks up the other device's keys; the list follows.
      unawaited(widget.security.reloadKeys().catchError((Object _) {}));
      widget.onChanged();
    }
    // The keys' links do not check out: the message says to stop, and the list shows what is there.
    if (problem == _Problem.tampered) widget.onChanged();
    _asking(problem: problem);
  }

  Future<void> _finish(RotateResult result) async {
    _pending = null;
    try {
      await widget.security.reloadKeys();
    } on Object {
      // The sync tries again on its own; the rotation is kept.
    }
    widget.onChanged();
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
        remove: [widget.device.id],
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
      prepared = await widget.security.rotate(
        remove: [widget.device.id],
        recovery: const FreshRecovery(),
      );
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
    final name = widget.device.label ?? l10n.settingsSecurityUnnamed;
    return Padding(
      padding: const EdgeInsets.only(top: WambitoTokens.space3),
      child: done != null ? _doneView(l10n, name, done) : _askView(l10n),
    );
  }

  Widget _doneView(AppLocalizations l10n, String name, RotateResult done) {
    final colors = context.lkColors;
    final dropped = [
      for (final d in done.dropped)
        if (d.id != widget.device.id) d,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space3,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.settingsSecurityDoneTitle,
            style: LkText.body.copyWith(color: colors.ink, fontWeight: FontWeight.w700),
          ),
        ),
        CssParagraph(
          l10n.settingsSecurityDoneLead(name),
          style: LkText.body.copyWith(color: colors.ink),
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
          l10n.settingsSecurityRemoveBody,
          style: LkText.body.copyWith(color: colors.ink),
        ),
        FieldCaption(l10n.settingsSecurityKeyLabel),
        WebTextField(
          fieldKey: const Key('security.remove.key'),
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
                ? l10n.settingsSecurityRemoving
                : retrying
                ? l10n.retry
                : l10n.settingsSecurityRemoveConfirm,
            key: const Key('security.remove.confirm'),
            tone: PressTone.secondary,
            onPressed: _canSubmit ? () => unawaited(_withKey()) : null,
          ),
        if (!retrying && !stopped)
          PressButton.text(
            l10n.settingsSecurityOrNew,
            key: const Key('security.remove.newKey'),
            tone: PressTone.ghost,
            onPressed: _busy ? null : () => unawaited(_withNewKey()),
          ),
        if (problem != null)
          FieldError(switch (problem) {
            _Problem.offline => l10n.vaultUnlockErrorOffline,
            _Problem.rotatedElsewhere => l10n.settingsSecurityRotatedElsewhere,
            _Problem.tampered => l10n.settingsSecurityTampered,
            _Problem.failed => l10n.settingsSecurityRemoveFailed,
          }),
      ],
    );
  }
}
