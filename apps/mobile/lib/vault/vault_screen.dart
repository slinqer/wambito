// `/unlock`: the vault gate on screen (the web's VaultGate.tsx switch over its state). A `preview`
// account is kept here until its vault is open (lib/router.dart): the recovery key to set up,
// Unlock, Locked, or a loading line while the gate checks, commits or opens.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/session.dart';
import '../entry/sign_in_frame.dart';
import '../files/files_channel.dart';
import '../l10n/app_localizations.dart';
import '../settings/account_deletion.dart';
import 'encryption_mode.dart';
import 'locked_view.dart';
import 'recovery_key_setup_view.dart';
import 'unlock_view.dart';
import 'vault_gate.dart';
import 'vault_providers.dart';

/// While the vault checks the account's keys, commits a new setup or opens: nothing to press.
class VaultLoading extends StatelessWidget {
  const VaultLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SignInFrame(
      children: [
        Semantics(liveRegion: true, container: true, child: EntryTitle(l10n.vaultLoading)),
      ],
    );
  }
}

class VaultScreen extends ConsumerWidget {
  /// [positions] pins the characters the recovery key asks back; random otherwise (tests pin them).
  const VaultScreen({super.key, this.positions});

  final List<int>? positions;

  Future<void> _signOut(WidgetRef ref) async {
    try {
      // The vault is not open, so there is nothing unsent to ask about; a guest is not warned
      // either: its data lives on another device, and this phone holds none of it.
      await ref.read(sessionProvider.notifier).signOut(discardGuest: true);
    } on Object {
      // The session is forgotten here all the same once the server cannot be told.
    }
  }

  Future<bool> _deleteAccount(WidgetRef ref) async {
    try {
      await ref.read(accountDeletionProvider).delete();
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(vaultGateProvider);
    final state = ref.watch(vaultGateStateProvider);
    void signOut() => unawaited(_signOut(ref));
    if (gate == null || state == null) {
      // No gate: the mode of the account is not known yet, or could not be learned (an offline
      // first start with nothing kept). A `plain` account never stays here (the router).
      final account = ref.watch(vaultAccountProvider);
      if (account.hasError) {
        return LockedView(
          kind: LockedKind.offline,
          retrying: account.isLoading,
          onRetry: () => ref.invalidate(vaultAccountProvider),
          onSignOut: signOut,
        );
      }
      return const VaultLoading();
    }
    return switch (state) {
      Setup(:final recoveryKey) => RecoveryKeySetupView(
        recoveryKey: recoveryKey,
        positions: positions,
        onContinue: () => unawaited(gate.confirmSetup()),
        onSignOut: signOut,
        onShare: (name, text) async {
          await ref.read(filesChannelProvider).shareFile(name, utf8.encode(text), 'text/plain');
        },
      ),
      Unlock(:final notice) => UnlockView(
        // A new passkey, a recovery key typed again: a new notice is a new screen.
        key: ValueKey(notice),
        notice: notice,
        onUnlock: gate.unlock,
        onPasskey: (ref.watch(unlockPasskeyOfferedProvider).value ?? false)
            ? gate.unlockWithPasskey
            : null,
        onSignOut: signOut,
      ),
      Locked(:final kind, :final retrying) => LockedView(
        kind: kind,
        retrying: retrying,
        onRetry: gate.retry,
        onSignOut: signOut,
        onDeleteAccount: kind == LockedKind.guest ? () => _deleteAccount(ref) : null,
      ),
      _ => const VaultLoading(),
    };
  }
}
