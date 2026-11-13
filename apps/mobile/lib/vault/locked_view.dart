// The web's Locked (apps/web/app/features/vault/Locked.tsx): the vault could not be opened. Says
// why, offers a retry when one can help, and always a sign-out. A guest locked out of its data can
// also delete the account (two taps: ask, then confirm).
import 'dart:async';

import 'package:flutter/material.dart';

import '../entry/sign_in_frame.dart';
import '../home/wambi_face.dart';
import '../l10n/app_localizations.dart';
import '../theme/tokens.g.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import 'vault_gate.dart';

class LockedView extends StatelessWidget {
  const LockedView({
    super.key,
    required this.kind,
    required this.retrying,
    required this.onRetry,
    required this.onSignOut,
    this.onDeleteAccount,
  });

  final LockedKind kind;
  final bool retrying;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  /// A guest's way out for good: deletes the account. Resolves to whether it worked.
  final Future<bool> Function()? onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (title, lead) = switch (kind) {
      LockedKind.error => (l10n.vaultLockedTitle, l10n.vaultLockedLead),
      LockedKind.offline => (l10n.vaultLockedOfflineTitle, l10n.vaultLockedOfflineLead),
      LockedKind.unsupported => (l10n.vaultLockedUnsupportedTitle, l10n.vaultLockedUnsupportedLead),
      LockedKind.guest => (l10n.vaultLockedGuestTitle, l10n.vaultLockedGuestLead),
    };
    final canRetry = kind == LockedKind.error || kind == LockedKind.offline;
    final delete = onDeleteAccount;
    return SignInFrame(
      mood: WambiMood.worried,
      children: [
        EntryTitle(title),
        EntryLead(lead),
        if (canRetry)
          SizedBox(
            width: double.infinity,
            child: PressButton.text(
              retrying ? l10n.vaultLockedRetrying : l10n.vaultLockedRetry,
              key: const Key('vault.retry'),
              onPressed: retrying ? null : onRetry,
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: PressButton.text(
            l10n.settingsSignOut,
            key: const Key('vault.signOut'),
            tone: canRetry ? PressTone.ghost : PressTone.primary,
            onPressed: onSignOut,
          ),
        ),
        if (kind == LockedKind.guest && delete != null) _DeleteGuest(onDelete: delete),
      ],
    );
  }
}

enum _Step { idle, confirm, busy, failed }

class _DeleteGuest extends StatefulWidget {
  const _DeleteGuest({required this.onDelete});

  final Future<bool> Function() onDelete;

  @override
  State<_DeleteGuest> createState() => _DeleteGuestState();
}

class _DeleteGuestState extends State<_DeleteGuest> {
  var _step = _Step.idle;

  Future<void> _delete() async {
    setState(() => _step = _Step.busy);
    var done = false;
    try {
      done = await widget.onDelete();
    } on Object {
      done = false;
    }
    // Deleted: the session ends and this screen goes with it.
    if (mounted && !done) setState(() => _step = _Step.failed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final over = TextStyle(color: colors.over);
    if (_step == _Step.idle) {
      return SizedBox(
        width: double.infinity,
        child: PressButton(
          key: const Key('vault.deleteAccount'),
          tone: PressTone.ghost,
          onPressed: () => setState(() => _step = _Step.confirm),
          child: Text(l10n.vaultLockedDeleteAccount.toUpperCase(), style: over),
        ),
      );
    }
    final busy = _step == _Step.busy;
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WambitoTokens.space2,
        children: [
          Text(
            l10n.vaultLockedDeleteLead,
            textAlign: TextAlign.center,
            style: DefaultTextStyle.of(context).style.copyWith(color: colors.ink, fontSize: 15),
          ),
          if (_step == _Step.failed) FieldError(l10n.vaultLockedDeleteFailed),
          PressButton(
            key: const Key('vault.deleteConfirm'),
            tone: PressTone.secondary,
            onPressed: busy ? null : () => unawaited(_delete()),
            child: Text(
              (busy ? l10n.vaultLockedDeleting : l10n.vaultLockedDeleteConfirm).toUpperCase(),
              style: over,
            ),
          ),
          PressButton.text(
            l10n.cancel,
            key: const Key('vault.deleteCancel'),
            tone: PressTone.ghost,
            onPressed: busy ? null : () => setState(() => _step = _Step.idle),
          ),
        ],
      ),
    );
  }
}
