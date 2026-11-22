import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../local/vault_session.dart';
import '../ui/confirm_sheet.dart';
import '../ui/press_button.dart';

/// Before a sign-out of a `preview` account (spec 2026-11-12 section 6.5): when the open [vault]
/// holds changes not sent yet, a sheet says "You have N changes not synced yet" and offers to sync
/// first ("Sync and sign out"), to sign out anyway ("Sign out anyway", the changes are lost with
/// the vault) or to back out. True when the sign-out may go on; false when the person backed out.
/// Nothing to send, or no open vault (a `plain` account, a vault not open): true at once.
///
/// A sync that leaves changes behind (offline, the server failed) asks again, so they are never
/// given up without a "Sign out anyway".
Future<bool> confirmUnsyncedSignOut(BuildContext context, VaultSession? vault) async {
  if (vault == null) return true;
  return confirmUnsentSignOut(context, count: vault.pendingChanges, sync: vault.sync);
}

/// The sheet of [confirmUnsyncedSignOut] over any count of changes not sent: [count] says how many,
/// [sync] sends them. Without [sync] (a vault kept but not open: Unlock, Locked) it offers only
/// "Sign out anyway" and backing out.
Future<bool> confirmUnsentSignOut(
  BuildContext context, {
  required Future<int> Function() count,
  Future<Object?> Function()? sync,
}) async {
  while (true) {
    final int pending;
    try {
      pending = await count();
    } on Object {
      // The count is a courtesy: a store that will not answer never keeps someone signed in.
      return true;
    }
    if (pending <= 0) return true;
    if (!context.mounted) return false;
    final l10n = AppLocalizations.of(context);
    final choice = await ChoiceSheet.show<_Unsynced>(
      context,
      title: l10n.settingsSignOut,
      body: l10n.vaultUnsyncedChanges(pending),
      choices: [
        if (sync != null)
          SheetChoice(
            key: const Key('vault.syncAndSignOut'),
            label: l10n.vaultSyncAndSignOut,
            value: _Unsynced.sync,
            tone: PressTone.primary,
          ),
        SheetChoice(
          key: const Key('vault.signOutAnyway'),
          label: l10n.vaultSignOutAnyway,
          value: _Unsynced.anyway,
          danger: true,
        ),
      ],
    );
    switch (choice) {
      case _Unsynced.anyway:
        return true;
      case null:
        return false;
      case _Unsynced.sync:
        try {
          await sync!();
        } on Object {
          // Counted again below: what is still there is asked about again.
        }
    }
  }
}

enum _Unsynced { sync, anyway }
