import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../api/auth_api.dart';
import '../api/passkeys.dart';
import '../api/session.dart';
import '../local/key_storage.dart';
import '../local/keys.dart' as keys;
import '../local/keys.dart' show KeysOptions, LocalKeys;
import '../local/keys_error.dart';
import '../local/prf.dart' as prf;
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

/// The gate of the signed-in `preview` account, started; null for `plain`, while the mode is not
/// known yet, and when signed out. A new gate only for another account (or mode): a new token of
/// the same account keeps it, and its calls read the network client of the moment.
final vaultGateProvider = Provider<AppVaultGate?>((ref) {
  final id = ref.watch(vaultAccountProvider.select((a) => a.value?.profile.id));
  final mode = ref.watch(vaultAccountProvider.select((a) => a.value?.mode));
  final profile = ref.read(vaultAccountProvider).value?.profile;
  if (id == null || mode != EncryptionMode.preview || profile == null) return null;
  return _gateFor(ref, profile)..start();
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

AppVaultGate _gateFor(Ref ref, VaultProfile profile) {
  final userId = profile.id;
  late final AppVaultGate gate;

  /// The providers of the moment; a call of a gate whose provider is gone fails (nobody shows it).
  T read<T>(ProviderListenable<T> provider) {
    if (!ref.mounted) throw const GateError('closed');
    return ref.read(provider);
  }

  KeyStorage storage() => read(keyStorageProvider);

  /// The network, without the vault's interceptor: `/v2`, the live routes and `/auth`.
  Dio network() => read(networkClientProvider).dio;

  KeysOptions options() => KeysOptions(userId: userId, dio: network(), storage: storage());

  /// The session ended under the vault (a 401): wipe it, then sign in again. The server already
  /// dropped the session, so even a guest's goes.
  Future<void> signInAgain() async {
    if (!ref.mounted) return;
    final session = ref.read(sessionProvider.notifier);
    try {
      await forgetVault(userId, ref.read(keyStorageProvider));
    } on Object {
      // Sign-in still has to happen; the next sign-out tries the wipe again.
    }
    try {
      await session.signOut(discardGuest: true);
    } on Object {
      // Forgotten here all the same at the next start (the server says 401).
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
    if (!ref.mounted) return;
    if (nobody) {
      unawaited(signInAgain());
    } else {
      ref.invalidate(vaultAccountProvider);
    }
  }

  /// The session the gate's listeners are on, so a reused one is not wired twice.
  VaultSession? wired;

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
        final session = await openVaultSession(
          OpenVaultOptions(
            profile: profile,
            keys: localKeys,
            fresh: fresh,
            network: network(),
            storage: storage(),
            onUnauthorized: () => unawaited(signInAgain()),
            onSessionChanged: () => gate.sessionChanged(),
          ),
        );
        if (!identical(wired, session)) {
          wired = session;
          session
            ..onClosed(gate.closed)
            // Removed from the account by another device: the vault is gone, Unlock says so.
            ..onRemoved(gate.removed)
            // A new key version did not verify: the vault is kept, Unlock asks again.
            ..onUnverified(gate.unverified);
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
