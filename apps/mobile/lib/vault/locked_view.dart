// The web's Locked (apps/web/app/features/vault/Locked.tsx): the vault could not be opened. Says
// why, offers a retry when one can help, and always a sign-out. An account without email that cannot
// open its data here is not Locked: it gets Unlock, whose "Add this phone from another device" pairs.
import 'package:flutter/material.dart';

import '../entry/sign_in_frame.dart';
import '../home/wambi_face.dart';
import '../l10n/app_localizations.dart';
import '../ui/press_button.dart';
import 'vault_gate.dart';

class LockedView extends StatelessWidget {
  const LockedView({
    super.key,
    required this.kind,
    required this.retrying,
    required this.onRetry,
    required this.onSignOut,
  });

  final LockedKind kind;
  final bool retrying;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (title, lead) = switch (kind) {
      LockedKind.error => (l10n.vaultLockedTitle, l10n.vaultLockedLead),
      LockedKind.offline => (l10n.vaultLockedOfflineTitle, l10n.vaultLockedOfflineLead),
      LockedKind.unsupported => (l10n.vaultLockedUnsupportedTitle, l10n.vaultLockedUnsupportedLead),
    };
    final canRetry = kind == LockedKind.error || kind == LockedKind.offline;
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
      ],
    );
  }
}
