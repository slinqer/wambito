// The web's Unlock (apps/web/app/features/vault/Unlock.tsx): a phone on an account that has keys
// types the recovery key, or touches a passkey whose PRF opens its wrap, to open the data here.
// "Add this phone from another device" opens the pairing screen (pair_new_device_view.dart).
import 'dart:async';

import 'package:flutter/material.dart';

import '../entry/sign_in_frame.dart';
import '../l10n/app_localizations.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/web_text_field.dart';
import 'vault_gate.dart';

/// The words of an Unlock error: the gate's codes (`unlockErrors`), anything else is the server's.
String unlockErrorText(AppLocalizations l10n, String code) => switch (code) {
  'bad_recovery_key' => l10n.vaultUnlockErrorBadKey,
  'wrong_recovery_key' => l10n.vaultUnlockErrorWrongKey,
  'no_prf' => l10n.vaultUnlockErrorNoPrf,
  'no_passkey_wrap' => l10n.vaultUnlockErrorNoPasskeyWrap,
  'offline' => l10n.vaultUnlockErrorOffline,
  _ => l10n.vaultUnlockErrorServer,
};

class UnlockView extends StatefulWidget {
  const UnlockView({
    super.key,
    this.notice,
    this.error,
    required this.onUnlock,
    this.onPasskey,
    this.onPair,
    required this.onSignOut,
  });

  /// [Unlock.removed] or [Unlock.unverified]: why the phone is asked again.
  final String? notice;

  /// The error to show at first (the recovery key from the sign-in did not open the data).
  final String? error;

  /// Tries the typed text (any case, spaces or dashes). Resolves to the error code, or null.
  final Future<String?> Function(String text) onUnlock;

  /// "Use a passkey": resolves to the error code, or null (it worked, or the prompt was closed).
  /// Without it there is no button.
  final Future<String?> Function()? onPasskey;

  /// "Add this phone from another device": the pairing screen, where a device that has the data
  /// approves this one. Without it there is no button.
  final VoidCallback? onPair;

  /// Signs out (and wipes this phone's vault): the way out.
  final VoidCallback onSignOut;

  @override
  State<UnlockView> createState() => _UnlockViewState();
}

class _UnlockViewState extends State<UnlockView> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  var _busy = false;
  String? _error;
  String? _passkeyError;

  @override
  void initState() {
    super.initState();
    _error = widget.error;
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

  Future<void> _run(Future<String?> Function() attempt, {required bool passkey}) async {
    setState(() {
      _busy = true;
      _error = null;
      _passkeyError = null;
    });
    String? error;
    try {
      error = await attempt();
    } finally {
      // The gate may have moved on (the screen is gone): nothing to show.
      if (mounted) {
        setState(() {
          _busy = false;
          if (passkey) {
            _passkeyError = error;
          } else {
            _error = error;
          }
        });
      }
    }
  }

  void _submit() {
    if (_canSubmit) unawaited(_run(() => widget.onUnlock(_text.text), passkey: false));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final notice = switch (widget.notice) {
      Unlock.removed => l10n.vaultRemoved,
      Unlock.unverified => l10n.vaultUnverified,
      _ => null,
    };
    final onPasskey = widget.onPasskey;
    final onPair = widget.onPair;
    return SignInFrame(
      children: [
        EntryTitle(l10n.vaultUnlockTitle),
        if (notice != null)
          SizedBox(
            width: double.infinity,
            child: Semantics(
              liveRegion: true,
              container: true,
              child: DecoratedBox(
                decoration: LkSurface.rowCard(context.lk),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(notice, style: LkText.note.copyWith(color: colors.ink)),
                ),
              ),
            ),
          ),
        EntryLead(l10n.vaultUnlockLead),
        SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WambitoTokens.space3,
            children: [
              FieldCaption(l10n.vaultUnlockLabel),
              WebTextField(
                fieldKey: const Key('vault.recoveryKey'),
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
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) FieldError(unlockErrorText(l10n, _error!)),
              PressButton.text(
                _busy ? l10n.vaultUnlockBusy : l10n.vaultUnlockSubmit,
                key: const Key('vault.unlockSubmit'),
                onPressed: _canSubmit ? _submit : null,
              ),
            ],
          ),
        ),
        if (onPasskey != null)
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: WambitoTokens.space2,
              children: [
                PressButton.text(
                  l10n.vaultUnlockPasskey,
                  key: const Key('vault.passkey'),
                  tone: PressTone.secondary,
                  onPressed: _busy ? null : () => unawaited(_run(onPasskey, passkey: true)),
                ),
                if (_passkeyError != null) FieldError(unlockErrorText(l10n, _passkeyError!)),
              ],
            ),
          ),
        if (onPair != null)
          SizedBox(
            width: double.infinity,
            child: PressButton.text(
              l10n.vaultUnlockPair,
              key: const Key('vault.pair'),
              tone: PressTone.secondary,
              onPressed: _busy ? null : onPair,
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: PressButton.text(
            l10n.settingsSignOut,
            key: const Key('vault.signOut'),
            tone: PressTone.ghost,
            onPressed: _busy ? null : widget.onSignOut,
          ),
        ),
      ],
    );
  }
}
