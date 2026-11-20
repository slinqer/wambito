// What "Protect your data" does (phone-first spec 5.2): step 1 makes and shows a recovery key, step 2
// adds a passkey whose PRF wraps the data key. Step 1 replaces the hidden recovery wrap that the guest
// setup uploaded (its secret was never shown nor kept) with a shown one on the same key version: no
// rotation, since nobody ever held the old secret. Shared by the Settings block, the home card
// (Task 4) and the recovery key after an email is added (Task 9, `canLeave: false`).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/session.dart'
    show SessionController, SessionStatus, claimFinishingProvider, sessionProvider;
import '../crypto/records.dart' show RecordType;
import '../l10n/app_localizations.dart';
import '../local/rotate.dart' show NewRecoveryKey;
import '../local/vault_session.dart' show VaultSession;
import '../security/screen_lock.dart';
import '../settings/passkeys_section.dart' show settingsPasskeyListProvider;
import '../settings/passkeys_settings.dart';
import '../settings/security/recovery_setup_page.dart';
import '../settings/security/security_api.dart';
import '../storage/secure_storage.dart' show appSecureStorage;
import '../ui/toast.dart';
import '../vault/preview.dart' show isPreviewProvider;
import '../vault/vault_providers.dart' show vaultSessionProvider;
import 'protect_status.dart';

/// Writes `recoveryKeySavedAt` = [now] (ISO UTC) into the settings record in one store transaction,
/// then syncs, so the account's other phones see the step done. Nothing when the vault has no
/// settings record yet (every vault is seeded with one when it opens).
Future<void> markRecoveryKeySaved(VaultSession session, DateTime now) async {
  await session.store.transaction((tx) async {
    final settings = (await tx.list(RecordType.settings)).firstOrNull;
    if (settings == null) return;
    await tx.put(RecordType.settings, settings.id, {
      ...settings.body,
      'recoveryKeySavedAt': now.toUtc().toIso8601String(),
    });
  });
  await session.sync();
}

/// How many times a key refused because the keys moved on another device is made again before
/// giving up (each time the sync first takes the other device's keys).
const _maxAttempts = 3;

/// Step 1: asks the screen lock (with no lock and no key saved yet there is nothing to type, ruling
/// 3), makes a new recovery key, shows it with its four-character check and saves it; then marks
/// the settings record. A save refused because the keys moved elsewhere (`rotated_elsewhere`)
/// takes the new keys and makes the key again. True once a key is saved. With [canLeave] false
/// the setup page has no way out before the key is saved.
Future<bool> protectWithRecoveryKey(
  BuildContext context,
  WidgetRef ref, {
  bool canLeave = true,
}) async {
  final security = ref.read(securityApiProvider);
  final session = ref.read(vaultSessionProvider);
  if (security == null || session == null) return false;
  final l10n = AppLocalizations.of(context);
  final toasts = ToastHost.maybeOf(context);
  final savedAt = await recoveryKeySavedAt(session.store);
  if (!context.mounted) return false;
  final ok = await confirmSensitive(
    context,
    ref,
    reason: l10n.protectLockReason,
    checkRecoveryKey: security.checkRecoveryKey,
    noKeyYet: savedAt == null,
  );
  if (!ok) return false;
  for (var attempt = 1; ; attempt++) {
    if (!context.mounted) return false;
    final NewRecoveryKey prepared;
    try {
      prepared = await security.newRecoveryKey();
    } on Object catch (error) {
      toasts?.say(
        codeOf(error) == 'offline'
            ? l10n.vaultUnlockErrorOffline
            : l10n.settingsSecurityNewKeyFailed,
        error: true,
      );
      return false;
    }
    if (!context.mounted) {
      prepared.forget();
      return false;
    }
    final outcome = await RecoverySetupPage.open<void>(
      context,
      recoveryKey: prepared.recoveryKey,
      commit: prepared.commit,
      refused: () => prepared.refused,
      canLeave: canLeave,
    );
    // Saved, gave up or refused for sure: whatever it held is let go.
    prepared.forget();
    if (outcome == null) return false;
    final refused = outcome.refused;
    if (refused == null) break;
    ref.invalidate(securitySnapshotProvider);
    if (codeOf(refused) != 'rotated_elsewhere' || attempt >= _maxAttempts) {
      toasts?.say(l10n.settingsSecurityNewKeyFailed, error: true);
      return false;
    }
    // The keys moved on another device: the sync takes them, then the key is made again.
    try {
      await security.reloadKeys();
    } on Object {
      // The next key says what is wrong, if anything still is.
    }
  }
  try {
    await markRecoveryKeySaved(session, DateTime.now());
  } on Object {
    // The key is saved on the server; only the step's mark failed (it is made again next time).
  }
  ref
    ..invalidate(protectStatusProvider)
    ..invalidate(securitySnapshotProvider);
  toasts?.say(l10n.protectKeySaved);
  return true;
}

/// Whether an account still owes the recovery key its claim asked for: secure storage
/// `wambito.protect.<userId>.keyAfterClaim`, written just before a `preview` guest's claim and
/// cleared once the key is saved. A process killed on the key page (or a key that could not be
/// made) leaves it, so the key page comes back when the vault next opens ([resumeKeyAfterClaim]).
/// The account's `recoveryKeySavedAt` alone cannot say it: accounts made on the web have it null too.
abstract interface class KeyAfterClaimMarks {
  Future<bool> owed(String userId);
  Future<void> owe(String userId);
  Future<void> clear(String userId);
}

/// The secure-storage key of [KeyAfterClaimMarks] (persistent: renaming it needs a migration).
String keyAfterClaimKey(String userId) => 'wambito.protect.$userId.keyAfterClaim';

class SecureKeyAfterClaimMarks implements KeyAfterClaimMarks {
  const SecureKeyAfterClaimMarks(this.storage);

  final FlutterSecureStorage storage;

  @override
  Future<bool> owed(String userId) async =>
      await storage.read(key: keyAfterClaimKey(userId)) != null;

  @override
  Future<void> owe(String userId) => storage.write(key: keyAfterClaimKey(userId), value: '1');

  @override
  Future<void> clear(String userId) => storage.delete(key: keyAfterClaimKey(userId));
}

final keyAfterClaimMarksProvider = Provider<KeyAfterClaimMarks>(
  (ref) => const SecureKeyAfterClaimMarks(appSecureStorage),
);

/// What follows a `preview` guest's claim of an email (phone-first spec 7.1, ruling 20): the
/// recovery key, with no way out until it is saved, when the vault's settings record says none was
/// saved yet (read from the record itself: `protectStatusProvider` says nothing once the account
/// has an email), then the passkey offer ([SessionController.offerPasskey]), the only one after a
/// claim. A key that could not be made (the screen lock refused, offline) is still owed: the mark
/// ([KeyAfterClaimMarks]) stays, nothing else is offered, and the key page comes back when the vault
/// next opens. The mark goes once the key is saved (or one already was).
Future<void> afterClaim(BuildContext context, WidgetRef ref) async {
  final session = ref.read(vaultSessionProvider);
  final marks = ref.read(keyAfterClaimMarksProvider);
  if (session != null) {
    final savedAt = await recoveryKeySavedAt(session.store);
    if (!context.mounted) return;
    if (savedAt == null && !await protectWithRecoveryKey(context, ref, canLeave: false)) return;
    try {
      await marks.clear(session.userId);
    } on Object {
      // The key is saved: a mark left behind only finds `recoveryKeySavedAt` set and goes then.
    }
  }
  await ref.read(sessionProvider.notifier).offerPasskey();
}

/// When the vault opens (home, at start or after an unlock): an account with an email whose claim
/// still owes its recovery key ([KeyAfterClaimMarks]) gets [afterClaim] again, the key page with no
/// way out, then the passkey offer. A key saved meanwhile (from Settings, or another phone) only
/// clears the mark. Nothing for a guest, a `plain` account, or while the email screen finishes a
/// claim itself.
Future<void> resumeKeyAfterClaim(BuildContext context, WidgetRef ref) async {
  final session = ref.read(vaultSessionProvider);
  // A vault with no session read yet (a screen shown on its own, as tests do) owes nothing here.
  if (session == null || !ref.exists(sessionProvider)) return;
  final signedIn = ref.read(sessionProvider);
  if (signedIn.status != SessionStatus.signedIn ||
      signedIn.isGuest ||
      !ref.read(isPreviewProvider) ||
      ref.read(claimFinishingProvider)) {
    return;
  }
  final marks = ref.read(keyAfterClaimMarksProvider);
  if (!await marks.owed(session.userId)) return;
  if (await recoveryKeySavedAt(session.store) != null) {
    await marks.clear(session.userId);
    return;
  }
  if (!context.mounted || ref.read(vaultSessionProvider) != session) return;
  await afterClaim(context, ref);
}

/// Step 2: adds a passkey whose PRF wraps the data key (`SettingsPasskeys.add(prf:)`). A password
/// manager that gives no PRF still adds a passkey that signs in; the status then says it cannot
/// open the data.
///
/// [onPrfKept] is told when the new passkey's PRF made its wrap (the passkey opens the data); an
/// `added` without it is a passkey that only signs in.
///
/// [onNoPrf] is told when the passkey itself gave no PRF (after the second touch when the
/// registration said `enabled` without results): the caller then says `settingsPasskeysAddNoPrf`
/// at once, as text that stays, in place of the "added" toast. The passkey is kept. A PRF whose wrap
/// could not be saved is not that: it ends as before.
Future<PasskeyOutcome> protectWithPasskey(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onPrfKept,
  VoidCallback? onNoPrf,
}) async {
  final security = ref.read(securityApiProvider);
  if (security == null) return PasskeyOutcome.failed;
  final l10n = AppLocalizations.of(context);
  final toasts = ToastHost.maybeOf(context);
  var withoutPrf = false;
  final outcome = await ref
      .read(settingsPasskeysProvider)
      .add(
        prf: PasskeyPrfUse(
          explainSecondTouch: () => toasts?.say(l10n.settingsPasskeysSecondTouch),
          keep: (passkey) async {
            await security.addPasskeyWrap(passkey);
            onPrfKept?.call();
          },
          onNoPrf: () => withoutPrf = true,
        ),
      );
  switch (outcome) {
    case PasskeyOutcome.added:
      ref
        ..invalidate(securitySnapshotProvider)
        ..invalidate(settingsPasskeyListProvider)
        ..invalidate(protectStatusProvider);
      if (withoutPrf && onNoPrf != null) {
        onNoPrf();
      } else {
        toasts?.say(l10n.settingsPasskeysAdded);
      }
    case PasskeyOutcome.failed:
      toasts?.say(l10n.settingsPasskeysAddFailed, error: true);
    case PasskeyOutcome.cancelled:
      break;
  }
  return outcome;
}
