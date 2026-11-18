// "Protect your data" (phone-first spec 5.2): how far a `preview` account without an email is from a
// way back to its data. Step 1, the recovery key, is the synced settings field `recoveryKeySavedAt`
// (ruling 1: the server cannot say whether a verifier exists, and a flag on the phone would nag again
// on every new phone). Step 2, the passkey, counts only when a passkey wrap exists (`anyPasskeyWrap`):
// a passkey without PRF signs in but cannot open the data.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/passkeys.dart' show passkeysSupportedProvider;
import '../crypto/records.dart' show RecordType;
import '../local/store.dart' show FinanceStore;
import '../settings/passkeys_section.dart' show settingsPasskeyListProvider;
import '../settings/security/security_api.dart' show securitySnapshotProvider;
import '../settings/security/security_model.dart' show anyPasskeyWrap;
import '../vault/encryption_mode.dart';
import '../vault/vault_providers.dart' show vaultSessionProvider;

class ProtectStatus {
  const ProtectStatus({
    required this.recoveryKey,
    required this.passkey,
    required this.passkeyOffered,
    required this.passkeyWithoutPrf,
  });

  /// A recovery key the person saw was saved (`settings.recoveryKeySavedAt`).
  final bool recoveryKey;

  /// A passkey wrap exists: a passkey opens the data.
  final bool passkey;

  /// This phone reports passkey support: the passkey step is shown.
  final bool passkeyOffered;

  /// The account has a passkey but no passkey wrap (the password manager gave no PRF).
  final bool passkeyWithoutPrf;

  /// How many of the two ways back are done ("N of 2").
  int get done => (recoveryKey ? 1 : 0) + (passkey ? 1 : 0);

  /// Either way back is done.
  bool get protected => recoveryKey || passkey;
}

/// The settings record's `recoveryKeySavedAt` (ISO UTC), null while no shown key was saved or the
/// vault has no settings yet. Read straight from the vault, so it works for any account (Task 9 reads
/// it after an email was added, when [protectStatusProvider] is null).
Future<String?> recoveryKeySavedAt(FinanceStore store) async {
  final settings = (await store.list(RecordType.settings)).firstOrNull;
  final at = settings?.body['recoveryKeySavedAt'];
  return at is String ? at : null;
}

/// The block's status; null unless the account is `preview`, has no email and its vault is open
/// (so `plain` accounts and email accounts never see the block). Read again on every vault commit
/// (a sync may bring the field from another phone).
final protectStatusProvider = FutureProvider.autoDispose<ProtectStatus?>((ref) async {
  final account = ref.watch(currentVaultAccountProvider);
  if (account == null || account.mode != EncryptionMode.preview || !account.profile.isAnonymous) {
    return null;
  }
  final session = ref.watch(vaultSessionProvider);
  if (session == null) return null;
  ref.onDispose(session.subscribe(ref.invalidateSelf));
  final savedAt = await recoveryKeySavedAt(session.store);
  bool offered;
  try {
    offered = await ref.watch(passkeysSupportedProvider.future);
  } on Object {
    offered = false;
  }
  var passkey = false;
  try {
    passkey = anyPasskeyWrap((await ref.watch(securitySnapshotProvider.future)).wraps);
  } on Object {
    // The wraps could not be read (offline): the step shows as not done until they can.
  }
  var withoutPrf = false;
  if (!passkey && offered) {
    try {
      withoutPrf = (await ref.watch(settingsPasskeyListProvider.future)).isNotEmpty;
    } on Object {
      // The list could not be read: no line about it.
    }
  }
  return ProtectStatus(
    recoveryKey: savedAt != null,
    passkey: passkey,
    passkeyOffered: offered,
    passkeyWithoutPrf: withoutPrf,
  );
});
