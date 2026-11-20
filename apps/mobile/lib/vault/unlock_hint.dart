import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings_store.dart';

/// "A passkey touch here gave no PRF" (spec 2026-11-20, section 1): a non-secret hint per user id,
/// so the unlock screen leads with the recovery key on a phone whose password manager signs the
/// person in but will not open the data. The phone's twin of apps/web/app/local/unlock-hint.ts. A
/// boolean, never a credential id. It survives a restart and a sign-out; deleting the account's
/// local data forgets it. Storage that fails reads false, and nothing here throws.
class UnlockHint {
  const UnlockHint(this._store);

  final SettingsStore _store;

  /// The pref of [userId]'s hint. A persistent name.
  static String keyOf(String userId) => 'wambito.unlock.no_prf.$userId';

  /// Whether the last passkey touch for [userId] on this phone gave no PRF.
  Future<bool> gaveNoPrf(String userId) async {
    try {
      return await _store.read(keyOf(userId)) == '1';
    } on Object {
      return false;
    }
  }

  /// A passkey touch for [userId] (sign-in or unlock) gave no PRF.
  Future<void> noteWithoutPrf(String userId) async {
    try {
      await _store.write(keyOf(userId), '1');
    } on Object {
      // Not remembered: only the layout of the next Unlock differs.
    }
  }

  /// A passkey's PRF opened [userId]'s data here: the hint no longer holds.
  Future<void> noteOpened(String userId) => forget(userId);

  /// Removes the hint (the account's local data is deleted).
  Future<void> forget(String userId) async {
    try {
      await _store.delete(keyOf(userId));
    } on Object {
      // Left behind: a boolean, of no use to anyone else.
    }
  }
}

final unlockHintProvider = Provider<UnlockHint>(
  (ref) => UnlockHint(ref.read(settingsStoreProvider)),
);
