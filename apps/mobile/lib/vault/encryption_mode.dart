import 'dart:convert';

import 'package:dio/dio.dart';
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

/// The signed-in account as the vault needs it: its profile and its mode, and the session it was
/// read for ([owner], a hash of that session's token as [sessionOwnerOf] makes it).
class VaultAccount {
  const VaultAccount({required this.profile, required this.mode, required this.owner});

  final VaultProfile profile;
  final EncryptionMode mode;
  final String owner;
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
        owner: sessionOwnerOf(token),
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

  /// Forgets what was kept of [userId] (sign-out, a deleted account): the profile and the mode.
  /// Neither says anything of the finances, but both are personal (an email, an id): a sign-out
  /// leaves none of them on the phone.
  Future<void> forget(String userId) async {
    for (final key in [accountKey, modeKey(userId)]) {
      try {
        await _storage.delete(key: key);
      } on Object {
        // Bound to the old session's token: nobody else reads it.
      }
    }
  }
}

/// Who the app last learned the session's account to be: written by [vaultAccountProvider], read by
/// the sign-out (which cannot read that provider: it depends on the session). [owner] is the
/// session it was learned for.
class KnownAccount {
  String? owner;
  String? id;
}

final knownAccountProvider = Provider<KnownAccount>((ref) => KnownAccount());

final encryptionStoreProvider = Provider<EncryptionStore>((ref) => const EncryptionStore());

/// Whether a failed `GET /v1/me` means the server could not be asked (no network, a 5xx, an
/// answer without a profile): then what was kept may stand in. A 401 or another 4xx is the
/// server's answer, and nothing kept replaces it.
bool _unanswered(Object error) {
  if (error is GateError) return true;
  if (error is! DioException) return false;
  final status = error.response?.statusCode;
  return status == null || status >= 500;
}

/// The hash of the signed-in session's token ([sessionOwnerOf]); null when signed out.
final vaultOwnerProvider = Provider<String?>((ref) {
  final token = ref.watch(sessionProvider.select((s) => s.stored?.token));
  return token == null ? null : sessionOwnerOf(token);
});

/// The signed-in account (null when signed out): `GET /v1/me` on the network (never the vault's
/// local backend), kept for the session; when the server could not be asked, what was kept for
/// this session, else the error. No automatic retry: the app asks again when it is invalidated (a
/// reload, a new token). Riverpod keeps the previous value while it loads or after an error: read
/// [currentVaultAccountProvider] for the account of the session signed in now.
final vaultAccountProvider = FutureProvider<VaultAccount?>(retry: (_, _) => null, (ref) async {
  final token = ref.watch(sessionProvider.select((s) => s.stored?.token));
  if (token == null) return null;
  final store = ref.watch(encryptionStoreProvider);
  final known = ref.read(knownAccountProvider);
  final api = ref.watch(networkClientProvider).api.getDefaultApi();
  final Profile me;
  try {
    final data = (await api.getMe()).data;
    if (data == null) throw const GateError('server');
    me = data;
  } on Object catch (error) {
    if (!_unanswered(error)) rethrow;
    final kept = await store.recall(token);
    if (kept != null) {
      known
        ..owner = kept.owner
        ..id = kept.profile.id;
      return kept;
    }
    rethrow;
  }
  final account = VaultAccount(
    owner: sessionOwnerOf(token),
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
  known
    ..owner = account.owner
    ..id = me.id;
  // A session that has meanwhile ended (or changed) keeps nothing.
  if (ref.mounted) await store.remember(token, account);
  return account;
});

/// The account of the session signed in now, once known: never the previous session's value that
/// [vaultAccountProvider] keeps while it loads or after an error. Null while unknown or signed out.
final currentVaultAccountProvider = Provider<VaultAccount?>((ref) {
  final owner = ref.watch(vaultOwnerProvider);
  final account = ref.watch(vaultAccountProvider).value;
  return owner != null && account?.owner == owner ? account : null;
});

/// Whether the signed-in session's account is known to be `plain`: its finance calls may go to the
/// server. False when signed out, for `preview`, and while the mode is loading or failed.
final knownPlainProvider = Provider<bool>(
  (ref) => ref.watch(currentVaultAccountProvider)?.mode == EncryptionMode.plain,
);

/// The signed-in account's mode; null when signed out. An error when the server could not say and
/// nothing was kept for this session (an offline first start).
final encryptionModeProvider = FutureProvider<EncryptionMode?>(
  retry: (_, _) => null,
  (ref) async => (await ref.watch(vaultAccountProvider.future))?.mode,
);
