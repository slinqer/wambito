import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/gen/wambito_api.dart';
import '../api/session.dart';
import '../home/home_cache.dart' show homeCacheStoreProvider, sessionOwnerOf;
import '../local/vault_session.dart' show VaultProfile;
import '../offline/pending_saves.dart' show pendingSavesStoreProvider;
import '../storage/secure_storage.dart';
import 'vault_gate.dart' show GateError;
import 'vault_providers.dart' show staleVaultsProvider;

/// Whether the signed-in account's finances live on the server (`plain`) or in the vault on this
/// phone, end-to-end encrypted (`preview`): `GET /v1/me` → `encryption`.
enum EncryptionMode { plain, preview }

/// The signed-in account as the vault needs it: its profile and its mode, and the session it was
/// read for ([owner], a hash of that session's token as [sessionOwnerOf] makes it).
class VaultAccount {
  const VaultAccount({
    required this.profile,
    required this.mode,
    required this.owner,
    this.inferred = false,
  });

  final VaultProfile profile;
  final EncryptionMode mode;
  final String owner;

  /// Neither the server nor the phone said the mode: the account is taken for `plain` because this
  /// session holds plaintext `/v1` data (a home cache or saves waiting for the network), which only
  /// a `plain` account ever received (the first start after the update, with nothing kept). Good
  /// for routing and the offline path only: its finance calls still wait for the server's answer,
  /// and its [profile] holds only what the cache knew.
  final bool inferred;
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

  /// The id of the account kept last, whatever its session (null when none or unreadable): the
  /// account whose session ended without a sign-out (a 401), whose vault waits for it.
  Future<String?> keptAccountId() async {
    try {
      final raw = await _storage.read(key: accountKey);
      if (raw == null) return null;
      final id = (jsonDecode(raw) as Map)['id'];
      return id is String ? id : null;
    } on Object {
      return null;
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

/// What the server says of the signed-in account: `GET /v1/me` on the network (never the vault's
/// local backend), kept for the session ([EncryptionStore.remember]); null when signed out. Each
/// answer also sweeps the vaults of every other account off this phone ([staleVaultsProvider]: the
/// web's `deleteStaleVaults` at sign-in). No automatic retry: it is asked again when invalidated.
final freshVaultAccountProvider = FutureProvider<VaultAccount?>(retry: (_, _) => null, (ref) async {
  final token = ref.watch(sessionProvider.select((s) => s.stored?.token));
  if (token == null) return null;
  final store = ref.watch(encryptionStoreProvider);
  final api = ref.watch(networkClientProvider).api.getDefaultApi();
  final me = (await api.getMe()).data;
  if (me == null) throw const GateError('server');
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
  // A session that has meanwhile ended (or changed) keeps nothing and sweeps nothing.
  if (!ref.mounted) return account;
  await store.remember(token, account);
  if (ref.mounted) {
    final sweep = ref.read(staleVaultsProvider);
    unawaited(sweep(me.id).catchError((Object _) {}));
  }
  return account;
});

/// Whether this session holds plaintext `/v1` data: a home cache or a queue of saves bound to its
/// token. Only a `plain` account ever received any.
Future<bool> _holdsPlainData(Ref ref, String token) async {
  final owner = sessionOwnerOf(token);
  for (final read in [
    ref.read(homeCacheStoreProvider).read,
    ref.read(pendingSavesStoreProvider).read,
  ]) {
    try {
      final raw = await read();
      if (raw == null) continue;
      final doc = jsonDecode(raw);
      if (doc is Map && doc['owner'] == owner) return true;
    } on Object {
      // Unreadable: proves nothing.
    }
  }
  return false;
}

/// What the phone kept of the signed-in account, read without the network: the account kept for
/// this session; else, when this session holds plaintext `/v1` data, a `plain` account
/// ([VaultAccount.inferred]); else null.
final keptVaultAccountProvider = FutureProvider<VaultAccount?>(retry: (_, _) => null, (ref) async {
  final token = ref.watch(sessionProvider.select((s) => s.stored?.token));
  if (token == null) return null;
  final kept = await ref.watch(encryptionStoreProvider).recall(token);
  if (kept != null) return kept;
  if (!await _holdsPlainData(ref, token)) return null;
  final guest = ref.read(sessionProvider).isGuest;
  return VaultAccount(
    owner: sessionOwnerOf(token),
    inferred: true,
    profile: VaultProfile(id: '', email: '', isAnonymous: guest, locale: 'es', timezone: 'UTC'),
    mode: EncryptionMode.plain,
  );
});

/// The signed-in account (null when signed out), stale-while-revalidate: what the phone kept for
/// this session ([keptVaultAccountProvider]) at once, then the server's answer
/// ([freshVaultAccountProvider]) once it comes, which wins when it differs. With nothing kept, the
/// server's answer is waited for. The server's error stands when it answered (a 401 or another
/// 4xx); when it could not be asked (no network, a 5xx) what was kept stands in, else the error.
/// Riverpod keeps the previous value while it loads or after an error: read
/// [currentVaultAccountProvider] for the account of the session signed in now.
final vaultAccountProvider = FutureProvider<VaultAccount?>(retry: (_, _) => null, (ref) async {
  final token = ref.watch(sessionProvider.select((s) => s.stored?.token));
  if (token == null) return null;
  final owner = sessionOwnerOf(token);
  final known = ref.read(knownAccountProvider);
  // Once this has answered, a later answer of the server (it came in, or it was asked again) is
  // read anew. Not a watch: an answer that comes while this still waits for it is just awaited.
  var answered = false;
  ref.listen(freshVaultAccountProvider, (_, next) {
    if (answered && !next.isLoading) ref.invalidateSelf();
  });
  final fresh = ref.read(freshVaultAccountProvider);
  final keptFuture = ref.watch(keptVaultAccountProvider.future);
  final account = await _accountOf(ref, owner, fresh, keptFuture);
  answered = true;
  if (account != null && !account.inferred) {
    known
      ..owner = account.owner
      ..id = account.profile.id;
  }
  return account;
});

Future<VaultAccount?> _accountOf(
  Ref ref,
  String owner,
  AsyncValue<VaultAccount?> fresh,
  Future<VaultAccount?> keptFuture,
) async {
  if (!fresh.isLoading) {
    final error = fresh.error;
    if (error != null) {
      if (!_unanswered(error)) Error.throwWithStackTrace(error, fresh.stackTrace!);
    } else {
      final account = fresh.value;
      if (account == null || account.owner == owner) return account;
    }
  }
  VaultAccount? kept;
  try {
    kept = await keptFuture;
  } on Object {
    kept = null;
  }
  if (kept != null && kept.owner == owner) return kept;
  // Nothing kept: the server's answer, once it comes (an error when it could not be asked).
  final error = fresh.error;
  if (!fresh.isLoading && error != null) Error.throwWithStackTrace(error, fresh.stackTrace!);
  if (!ref.mounted) throw const GateError('closed');
  return ref.read(freshVaultAccountProvider.future);
}

/// The account of the session signed in now, once known: never the previous session's value that
/// [vaultAccountProvider] keeps while it loads or after an error. Null while unknown or signed out.
final currentVaultAccountProvider = Provider<VaultAccount?>((ref) {
  final owner = ref.watch(vaultOwnerProvider);
  final account = ref.watch(vaultAccountProvider).value;
  return owner != null && account?.owner == owner ? account : null;
});

/// Whether the signed-in session's account is known to be `plain`: its finance calls may go to the
/// server. False when signed out, for `preview`, while the mode is loading or failed, and for an
/// account only [VaultAccount.inferred] to be `plain` (its calls wait for the server's answer).
final knownPlainProvider = Provider<bool>((ref) {
  final account = ref.watch(currentVaultAccountProvider);
  return account != null && !account.inferred && account.mode == EncryptionMode.plain;
});

/// The signed-in account's mode; null when signed out. An error when the server could not say and
/// nothing was kept for this session (an offline first start).
final encryptionModeProvider = FutureProvider<EncryptionMode?>(
  retry: (_, _) => null,
  (ref) async => (await ref.watch(vaultAccountProvider.future))?.mode,
);
