import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../api/auth_api.dart';
import '../api/passkeys.dart';
import '../api/session.dart';
import '../local/db.dart' show pendingChangesInVault;
import '../local/key_storage.dart';
import '../local/keys.dart' as keys;
import '../local/keys.dart' show KeysOptions, LocalKeys;
import '../local/keys_error.dart';
import '../local/prf.dart' as prf;
import '../local/stale_vaults.dart';
import '../local/vault_session.dart';
import 'encryption_mode.dart';
import 'vault_gate.dart';

/// The vault gate in the app: how `VaultGate.tsx` wires `vault-gate.ts` to the keys, the passkeys
/// and the vault session, as Riverpod providers. A `preview` account gets a gate, started at once;
/// a `plain` one (or none signed in) gets null and the app runs as before.

/// The app's gate: the real keys and the real vault session.
typedef AppVaultGate = VaultGate<LocalKeys, VaultSession>;

/// Where the vault's keys live: the Keystore / Keychain (lib/local/key_storage.dart).
final keyStorageProvider = Provider<KeyStorage>((ref) => KeyStorage());

/// Opens a vault session: [openVaultSession]; tests put their own store folder in.
final openVaultSessionProvider = Provider<Future<VaultSession> Function(OpenVaultOptions)>(
  (ref) => openVaultSession,
);

/// Wipes an account's vault (its file and its keys): [forgetVault]; tests put their own in.
final forgetVaultProvider = Provider<Future<void> Function(String userId, KeyStorage storage)>(
  (ref) =>
      (userId, storage) => forgetVault(userId, storage),
);

/// The gate of the signed-in `preview` account, started; null for `plain`, while the mode of the
/// session signed in now is not known yet, and when signed out. It is bound to that session (the
/// owner of [currentVaultAccountProvider]): another token, even a new one of the same account,
/// disposes it, closes the vault session it opened (its file and keys stay), and a new gate starts
/// once the new session's account is known. Its calls read the network client of the moment.
final vaultGateProvider = Provider<AppVaultGate?>((ref) {
  final key = ref.watch(
    currentVaultAccountProvider.select((a) => a == null ? null : (a.owner, a.profile.id, a.mode)),
  );
  final account = ref.read(currentVaultAccountProvider);
  if (key == null || account == null || account.mode != EncryptionMode.preview) return null;
  return _gateFor(ref, account.profile, account.owner)..start();
});

/// The gate's state (null without a gate); rebuilt on every change.
final vaultGateStateProvider = Provider<VaultGateState<VaultSession>?>((ref) {
  final gate = ref.watch(vaultGateProvider);
  if (gate == null) return null;
  ref.onDispose(gate.subscribe(ref.invalidateSelf));
  return gate.state;
});

/// The open vault while the gate is `Ready`; else null.
final vaultSessionProvider = Provider<VaultSession?>((ref) {
  final state = ref.watch(vaultGateStateProvider);
  return state is Ready<VaultSession> ? state.session : null;
});

/// Whether Unlock offers "Use a passkey": this phone can use passkeys and the account has some
/// (the web's `passkeysSupported()` and `accountPasskeyIds`; whether one gives a PRF is known only
/// when it is touched, and Unlock then says so). A list that cannot be read leaves the button there:
/// the gate asks again, and the server refuses a credential that is not the account's.
final unlockPasskeyOfferedProvider = FutureProvider.autoDispose<bool>((ref) async {
  if (!await ref.watch(passkeysSupportedProvider.future)) return false;
  try {
    return (await accountPasskeyIds(ref.read(networkClientProvider).dio)).isNotEmpty;
  } on Object {
    return true;
  }
});

/// The signed-in account's passkey credential ids (Better Auth's list, `credentialID`, as the
/// web's `accountPasskeyIds`); throws when unreadable.
Future<List<String>> accountPasskeyIds(Dio network) async {
  final Response<Object?> response;
  try {
    response = await network.get<Object?>('/auth/passkey/list-user-passkeys');
  } on DioException {
    throw const GateError('passkeys_unavailable');
  }
  final data = response.data is String ? jsonDecode(response.data! as String) : response.data;
  if (data is! List) throw const GateError('passkeys_unavailable');
  return [
    for (final entry in data)
      if (entry is Map && entry['credentialID'] is String) entry['credentialID']! as String,
  ];
}

/// Touches one of the person's passkeys (one of [credentialIds] when given) for its PRF: the
/// server's passkey request options (for its `rpId` and a challenge; nothing is verified), limited to
/// those credentials, through [prf.evaluatePrf]. Null when cancelled; `no_prf` without a PRF,
/// `no_passkey_wrap` when the phone has no passkey for this server, `offline` without network.
Future<prf.PasskeyPrf?> touchPasskey(
  AuthApi auth,
  Passkeys passkeys,
  List<String>? credentialIds,
) async {
  final PasskeyChallenge challenge;
  try {
    challenge = await auth.passkeySignInOptions();
  } on AuthFailure catch (error) {
    throw KeysError(error.status == 0 ? 'offline' : 'server');
  }
  var options = challenge.optionsJson;
  if (credentialIds != null) {
    final json = (jsonDecode(options) as Map).cast<String, Object?>();
    json['allowCredentials'] = [
      for (final id in credentialIds) {'type': 'public-key', 'id': id},
    ];
    options = jsonEncode(json);
  }
  try {
    return await prf.evaluatePrf(passkeys, options);
  } on AuthFailure catch (error) {
    throw KeysError(error.code == 'NO_CREDENTIAL' ? 'no_passkey_wrap' : 'server');
  }
}

AppVaultGate _gateFor(Ref ref, VaultProfile profile, String owner) {
  final userId = profile.id;
  late final AppVaultGate gate;

  /// Whether this gate is still the signed-in session's: its provider is there, the gate was not
  /// disposed, and the session signed in now is the one it was made for.
  bool current() => ref.mounted && !gate.disposed && ref.read(vaultOwnerProvider) == owner;

  /// The providers of the moment; a call of a gate that is no longer the session's fails (nobody
  /// shows it), so nothing is made, unlocked or wiped for another session.
  T read<T>(ProviderListenable<T> provider) {
    if (!current()) throw const GateError('closed');
    return ref.read(provider);
  }

  KeyStorage storage() => read(keyStorageProvider);

  /// The network, without the vault's interceptor: `/v2`, the live routes and `/auth`.
  Dio network() => read(networkClientProvider).dio;

  KeysOptions options() => KeysOptions(userId: userId, dio: network(), storage: storage());

  /// The session ended under the vault (a 401: it expired, or the account signed out
  /// everywhere): the session ends here, then sign in again. The vault, its keys and its changes not
  /// sent yet stay for this account's next sign-in ([SessionController.sessionExpired]); unlike the
  /// web's `signInAgain`, which wipes them (spec 2026-11-12 sections 3 and 6.5: only a sign-out and
  /// a removed device wipe the vault). The server already dropped the session, so even a guest's
  /// goes.
  Future<void> signInAgain() async {
    // A late 401 of a session that is gone never ends the one signed in now.
    if (!current()) return;
    final session = ref.read(sessionProvider.notifier);
    final token = ref.read(sessionProvider).stored?.token;
    try {
      await session.sessionExpired(token: token);
    } on Object {
      // Ended here all the same at the next start (the server says 401).
    }
  }

  /// A 401 from `/v2/keys`: sign in again, the gate stays put.
  Future<T> signInAgainOn401<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on KeysError catch (error) {
      if (error.status == 401) unawaited(signInAgain());
      rethrow;
    }
  }

  /// Who answered the last [sessionUserId]: null is no one (the session is gone).
  var nobody = false;

  /// Who is signed in now (`GET /v1/me` on the network): null when no one; throws when it cannot
  /// tell.
  Future<String?> sessionUserId() async {
    final token = read(sessionProvider).stored?.token;
    nobody = token == null;
    if (token == null) return null;
    try {
      final me = (await read(networkClientProvider).api.getDefaultApi().getMe()).data;
      if (me == null) throw const GateError('server');
      return me.id;
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) rethrow;
      nobody = true;
      return null;
    }
  }

  /// Another account signed in: the account's providers again, for them (a new gate). No one: the
  /// session is gone, so sign in again.
  void reload() {
    if (!current()) return;
    if (nobody) {
      unawaited(signInAgain());
    } else {
      ref.invalidate(freshVaultAccountProvider);
    }
  }

  /// The session the gate's listeners are on, so a reused one is not wired twice, and their
  /// unsubscribes.
  VaultSession? wired;
  final detach = <void Function()>[];

  // Another session signed in (or none): the gate keeps nothing, tells nothing, and its vault
  // session closes; the vault file and the keys stay (a sign-out deletes them, Task 14).
  ref.onDispose(() {
    gate.dispose();
    for (final unsubscribe in detach) {
      unsubscribe();
    }
    detach.clear();
    final session = wired;
    wired = null;
    if (session != null) unawaited(session.close().catchError((Object _) {}));
  });

  gate = AppVaultGate(
    VaultGateDeps(
      loadLocalKeys: () => keys.loadLocalKeys(userId, storage()),
      prepareAccount: () async {
        final prepared = await signInAgainOn401(
          () => keys.prepareAccount(options(), guest: profile.isAnonymous),
        );
        return GatePrepared(recoveryKey: prepared.recoveryKey, commit: prepared.commit);
      },
      unlockWithRecovery: (text) =>
          signInAgainOn401(() => keys.unlockWithRecovery(options(), text)),
      unlockWithPasskey: (passkey) =>
          signInAgainOn401(() => keys.unlockWithPasskey(options(), passkey)),
      addPasskeyWrap: (passkey) => keys.addPasskeyWrap(options(), passkey),
      evaluatePrf: (ids) => touchPasskey(read(authApiProvider), read(passkeysProvider), ids),
      accountPasskeyIds: () => accountPasskeyIds(network()),
      open: (localKeys, fresh) async {
        final session = await read(openVaultSessionProvider)(
          OpenVaultOptions(
            profile: profile,
            keys: localKeys,
            fresh: fresh,
            network: network(),
            storage: storage(),
            onUnauthorized: () => unawaited(signInAgain()),
            onSessionChanged: () {
              if (current()) gate.sessionChanged();
            },
          ),
        );
        if (!current()) {
          // Opened for a session that is gone meanwhile: closed again, never handed out.
          unawaited(session.close().catchError((Object _) {}));
          throw const GateError('closed');
        }
        if (!identical(wired, session)) {
          wired = session;
          detach
            ..add(session.onClosed(gate.closed))
            // Removed from the account by another device: the vault is gone, Unlock says so.
            ..add(session.onRemoved(gate.removed))
            // A new key version did not verify: the vault is kept, Unlock asks again.
            ..add(session.onUnverified(gate.unverified));
        }
        return session;
      },
      guest: profile.isAnonymous,
      userId: userId,
      sessionUserId: sessionUserId,
      reload: reload,
    ),
  );
  return gate;
}

/// Deletes the vault (file, keys, kept mode and account) of every account on this phone but
/// [keepUserId] ([deleteStaleVaults]): at each answer of `GET /v1/me` with the signed-in account, and
/// on a signed-out start with the account whose session ended without a sign-out. Never throws.
final staleVaultsProvider = Provider<Future<void> Function(String? keepUserId)>((ref) {
  final keys = ref.read(keyStorageProvider);
  final forget = ref.read(forgetVaultProvider);
  return (keep) => deleteStaleVaults(keep, forget: (id) => forget(id, keys));
});

/// How many changes not sent yet the signed-in account's vault file holds, read without opening the
/// vault ([pendingChangesInVault]); 0 when the account is not known. For Unlock and Locked, whose
/// vault may be kept with changes (a key version that did not verify, a failed open).
final unsentChangesProvider = Provider<Future<int> Function()>((ref) {
  return () async {
    final account = ref.read(currentVaultAccountProvider);
    if (account == null || account.mode != EncryptionMode.preview) return 0;
    return pendingChangesInVault(account.profile.id);
  };
});
