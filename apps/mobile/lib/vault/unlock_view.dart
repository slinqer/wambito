// The web's Unlock (apps/web/app/features/vault/Unlock.tsx): a phone on an account that has keys
// opens the data here with a passkey whose PRF opens its wrap, another device that approves this one
// ("Add this phone from another device", pair_new_device_view.dart), or the recovery key. One of
// three layouts (`unlockLayout`, spec 2026-11-20 section 1); the rest under "More options".
import 'dart:async';

import 'package:flutter/material.dart';

import '../entry/sign_in_frame.dart';
import '../l10n/app_localizations.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import 'recovery_key_input.dart';
import 'unlock_layout.dart';
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
    this.merging = false,
    this.noPrfHere = false,
    this.passkeyWrap = true,
  });

  /// [Unlock.removed] or [Unlock.unverified]: why the phone is asked again.
  final String? notice;

  /// The error to show at first (the recovery key from the sign-in did not open the data).
  final String? error;

  /// Tries the typed text (any case, spaces or dashes). Resolves to the error code, or null.
  final Future<String?> Function(String text) onUnlock;

  /// "Open with my passkey": resolves to the error code, or null (it worked, or the prompt was
  /// closed). Without it (the phone cannot use passkeys, or the account has none) there is no
  /// passkey button.
  final Future<String?> Function()? onPasskey;

  /// "Add this phone from another device": the pairing screen, where a device that has the data
  /// approves this one. Without it there is no button.
  final VoidCallback? onPair;

  /// Signs out (and wipes this phone's vault): the way out.
  final VoidCallback onSignOut;

  /// A merge waits for this account's data: one line says why it is asked.
  final bool merging;

  /// This phone's last passkey touch for the account gave no PRF ([Unlock.noPrfHere]): the recovery
  /// key leads, with a line saying why.
  final bool noPrfHere;

  /// The account has a passkey wrap ([Unlock.passkeyWrap]).
  final bool passkeyWrap;

  @override
  State<UnlockView> createState() => _UnlockViewState();
}

class _UnlockViewState extends State<UnlockView> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  var _busy = false;
  String? _error;
  String? _passkeyError;

  /// "More options" is open: closed at first, opened by a tap or by a passkey above it that cannot
  /// open the data.
  var _moreOpen = false;

  UnlockPlacement get _layout => unlockLayout(
    noPrfHere: widget.noPrfHere,
    passkeyWrap: widget.passkeyWrap,
    passkeysSupported: widget.onPasskey != null,
    canPair: widget.onPair != null,
  );

  @override
  void initState() {
    super.initState();
    _error = widget.error;
    // The sign-in's recovery key did not open the data: its field is in sight with the error.
    if (_error != null && _layout.more.contains(UnlockAction.key)) _moreOpen = true;
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

  bool get _canSubmit => !_busy && isFullRecoveryKey(_text.text);

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
            // The passkey above "More options" cannot open the data: the recovery key comes into
            // sight (the error is announced; the field does not take the focus).
            if (_layout.main == UnlockAction.passkey &&
                (error == 'no_prf' || error == 'no_passkey_wrap')) {
              _moreOpen = true;
            }
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

  void _toggleMore() {
    setState(() => _moreOpen = !_moreOpen);
    // Opened by hand onto the recovery key: the field takes the focus once it is built.
    if (_moreOpen && _layout.more.contains(UnlockAction.key)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  Widget _keyForm(AppLocalizations l10n, {required bool primary}) => SizedBox(
    width: double.infinity,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space3,
      children: [
        FieldCaption(l10n.vaultUnlockLabel),
        RecoveryKeyField(
          fieldKey: const Key('vault.recoveryKey'),
          pasteKey: const Key('vault.paste'),
          controller: _text,
          focusNode: _focus,
          invalid: _error != null,
          readOnly: _busy,
          // Leading, the field is what the screen asks for; under "More options" it waits.
          autofocus: primary,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) FieldError(unlockErrorText(l10n, _error!)),
        PressButton.text(
          _busy ? l10n.vaultUnlockBusy : l10n.vaultUnlockSubmit,
          key: const Key('vault.unlockSubmit'),
          tone: primary ? PressTone.primary : PressTone.secondary,
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
    ),
  );

  Widget _passkeyButton(AppLocalizations l10n, {required bool primary}) {
    final onPasskey = widget.onPasskey!;
    final label = primary ? l10n.vaultUnlockPasskey : l10n.vaultUnlockOtherPasskey;
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WambitoTokens.space2,
        children: [
          PressButton(
            key: const Key('vault.passkey'),
            tone: primary ? PressTone.primary : PressTone.secondary,
            onPressed: _busy ? null : () => unawaited(_run(onPasskey, passkey: true)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: WambitoTokens.space2,
              children: [
                const FingerprintIcon(),
                Flexible(child: Text(LkText.upperCase(label))),
              ],
            ),
          ),
          if (_passkeyError != null) FieldError(unlockErrorText(l10n, _passkeyError!)),
        ],
      ),
    );
  }

  Widget _pairButton(AppLocalizations l10n, {required bool primary}) => SizedBox(
    width: double.infinity,
    child: PressButton.text(
      l10n.vaultUnlockPair,
      key: const Key('vault.pair'),
      tone: primary ? PressTone.primary : PressTone.secondary,
      onPressed: _busy ? null : widget.onPair,
    ),
  );

  Widget _place(AppLocalizations l10n, UnlockAction what, {required bool primary}) =>
      switch (what) {
        UnlockAction.key => _keyForm(l10n, primary: primary),
        UnlockAction.passkey => _passkeyButton(l10n, primary: primary),
        UnlockAction.pair => _pairButton(l10n, primary: primary),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final notice = switch (widget.notice) {
      Unlock.removed => l10n.vaultRemoved,
      Unlock.unverified => l10n.vaultUnverified,
      _ => null,
    };
    final layout = _layout;
    final keyLeads = layout.main == UnlockAction.key;
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
        if (widget.merging)
          EntryLead(l10n.unlockMergeWaiting, key: const Key('unlock.mergeWaiting'), ink: true),
        EntryLead(keyLeads ? l10n.vaultUnlockLead : l10n.vaultUnlockLeadOther),
        if (keyLeads && widget.noPrfHere)
          EntryLead(l10n.vaultUnlockNoPrfLine, key: const Key('vault.noPrfLine'), ink: true),
        _place(l10n, layout.main, primary: true),
        for (final what in layout.below) _place(l10n, what, primary: false),
        if (layout.more.isNotEmpty) ...[
          SizedBox(
            width: double.infinity,
            child: PressButton.text(
              l10n.vaultUnlockMore,
              key: const Key('vault.more'),
              tone: PressTone.ghost,
              expanded: _moreOpen,
              onPressed: _toggleMore,
            ),
          ),
          if (_moreOpen)
            for (final what in layout.more) _place(l10n, what, primary: false),
        ],
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
