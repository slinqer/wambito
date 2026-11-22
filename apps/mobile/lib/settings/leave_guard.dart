// Warning a guest before an action that would leave their account behind (signing out, changing
// server), shared by the menu's "Cerrar sesión" and the server card.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/session.dart';
import '../progress/guest_warning.dart';
import '../protect/leaving_warning.dart';
import '../protect/protect_actions.dart' show protectWithRecoveryKey;
import '../protect/protect_status.dart' show ProtectStatus, protectStatusProvider;
import 'security/security_api.dart' show securitySnapshotProvider;

/// How long a guest waits for the protect status before the warning shows without it.
const _statusWait = Duration(seconds: 4);

/// Warns a guest before [leaving]; true when it may go on. A `preview` guest is asked about its
/// way back ([protectStatusProvider]): with a recovery key or a passkey there is no warning; with
/// neither, "Protect first" opens the recovery key and nothing is left. When the passkey cannot
/// be read (offline) the sheet says so instead of claiming there is none. A `plain` guest (or a
/// vault not open) gets today's [warnGuestLeaving].
Future<bool> mayLeaveSettings(BuildContext context, WidgetRef ref, GuestLeaving leaving) async {
  if (!ref.read(sessionProvider).isGuest) return true;
  // Kept alive while the question is asked, so the passkey wraps it read are not fetched again.
  final hold = ref.listenManual(protectStatusProvider, (_, _) {});
  try {
    ProtectStatus? status;
    var unreadable = false;
    try {
      status = await ref.read(protectStatusProvider.future).timeout(_statusWait);
    } on TimeoutException {
      // Offline and slow: nothing is known, so the warning shows with the passkey unknown.
      unreadable = true;
    } on Object {
      status = null;
    }
    if (!context.mounted) return false;
    if (status != null || unreadable) {
      if (status != null && status.protected) return true;
      var passkeyUnknown = unreadable;
      if (!unreadable) {
        try {
          await ref.read(securitySnapshotProvider.future).timeout(_statusWait);
        } on Object {
          passkeyUnknown = true;
        }
      }
      if (!context.mounted) return false;
      final choice = await warnUnprotectedLeaving(context, leaving, passkeyUnknown: passkeyUnknown);
      if (!context.mounted || choice == null) return false;
      if (choice == UnprotectedChoice.protectFirst) {
        await protectWithRecoveryKey(context, ref);
        return false;
      }
      return true;
    }
  } finally {
    hold.close();
  }
  final choice = await warnGuestLeaving(context, leaving);
  if (!context.mounted || choice == null) return false;
  if (choice == GuestWarning.saveInstead) {
    unawaited(context.push('/progress'));
    return false;
  }
  return true;
}
