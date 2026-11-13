import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/gen/wambito_api.dart';
import '../api/session.dart';
import '../home/home_cache.dart' show sessionOwnerOf;
import '../local/vault_session.dart' show VaultProfile;
import '../storage/secure_storage.dart';
import 'vault_gate.dart' show GateError;

/// Whether the signed-in account's finances live on the server (`plain`) or in the vault on this
/// phone, end-to-end encrypted (`preview`): `GET /v1/me` → `encryption`.
enum EncryptionMode { plain, preview }

/// The signed-in account as the vault needs it: its profile and its mode.
class VaultAccount {
  const VaultAccount({required this.profile, required this.mode});

  final VaultProfile profile;
  final EncryptionMode mode;
}

/// Where the phone keeps what it last heard of the account, so a start without network still knows
/// the mode and can open the vault (the web's `rememberPreviewAccount`). In secure storage (the
/// Keychain with `first_unlock_this_device` on iOS):
/// - `wambito.encryption.<userId>`: `plain` | `preview`;
/// - `wambito.account`: the profile the vault opens with (id, email, guest, locale, time zone),
///   bound to the session that read it (a hash of its token, as the home cache), so another session
///   never reads it. Without it an offline start would not know whose mode to read.
class EncryptionStore {
  const EncryptionStore([this._storage = appSecureStorage]);

  static String modeKey(String userId) => 'wambito.encryption.$userId';
  static const accountKey = 'wambito.account';

  final FlutterSecureStorage _storage;

  /// Keeps [account] for the session of [token]. A failure is ignored: it only costs the offline
  /// start.
  Future<void> remember(String token, VaultAccount account) async {
    final profile = account.profile;
    try {
      await _storage.write(key: modeKey(profile.id), value: account.mode.name);
      await _storage.write(
        key: accountKey,
        value: jsonEncode({
          'owner': sessionOwnerOf(token),
          'id': profile.id,
          'email': profile.email,
          'isAnonymous': profile.isAnonymous,
          'locale': profile.locale,
          'timezone': profile.timezone,
        }),
      );
    } on Object {
      // See above.
    }
  }

  /// What was kept for the session of [token], or null (another session's, none, unreadable).
  Future<VaultAccount?> recall(String token) async {
    try {
      final raw = await _storage.read(key: accountKey);
      if (raw == null) return null;
      final doc = (jsonDecode(raw) as Map).cast<String, Object?>();
      if (doc['owner'] != sessionOwnerOf(token)) return null;
      final id = doc['id']! as String;
      final mode = EncryptionMode.values.asNameMap()[await _storage.read(key: modeKey(id))];
      if (mode == null) return null;
      return VaultAccount(
        profile: VaultProfile(
          id: id,
          email: doc['email']! as String,
          isAnonymous: doc['isAnonymous']! as bool,
          locale: doc['locale']! as String,
          timezone: doc['timezone']! as String,
        ),
        mode: mode,
      );
    } on Object {
      return null;
    }
  }

  /// Forgets the kept profile (sign-out). The mode of each account may stay: it says nothing of
  /// its finances, and a reinstall deletes it (`KeyStorage.deleteAllVaultKeys`).
  Future<void> forget() async {
    try {
      await _storage.delete(key: accountKey);
    } on Object {
      // Bound to the old session's token: nobody else reads it.
    }
  }
}

final encryptionStoreProvider = Provider<EncryptionStore>((ref) => const EncryptionStore());

/// The signed-in account (null when signed out): `GET /v1/me` on the network (never the vault's
/// local backend), kept for the session; without an answer, what was kept for this session, else
/// the error. No automatic retry: the app asks again when it is invalidated (a reload, a new token).
final vaultAccountProvider = FutureProvider<VaultAccount?>(retry: (_, _) => null, (ref) async {
  final token = ref.watch(sessionProvider.select((s) => s.stored?.token));
  if (token == null) return null;
  final store = ref.watch(encryptionStoreProvider);
  final api = ref.watch(networkClientProvider).api.getDefaultApi();
  final Profile me;
  try {
    final data = (await api.getMe()).data;
    if (data == null) throw const GateError('server');
    me = data;
  } on Object {
    final kept = await store.recall(token);
    if (kept != null) return kept;
    rethrow;
  }
  final account = VaultAccount(
    profile: VaultProfile(
      id: me.id,
      email: me.email,
      isAnonymous: me.isAnonymous,
      locale: me.locale,
      timezone: me.timezone,
    ),
    mode: me.encryption == ProfileEncryptionEnum.preview
        ? EncryptionMode.preview
        : EncryptionMode.plain,
  );
  await store.remember(token, account);
  return account;
});

/// The signed-in account's mode; null when signed out. An error when the server could not say and
/// nothing was kept for this session (an offline first start).
final encryptionModeProvider = FutureProvider<EncryptionMode?>(
  retry: (_, _) => null,
  (ref) async => (await ref.watch(vaultAccountProvider.future))?.mode,
);
