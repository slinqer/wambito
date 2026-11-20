import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../api/auth_api.dart';
import '../api/passkeys.dart';
import '../api/session.dart';
import '../api/unauthorized.dart';
import '../background/background_channel.dart';
import '../home/home_cache.dart' show sessionOwnerOf;
import '../local/db.dart' show VaultHold, VaultHoldKind, pendingChangesInVault, vaultHoldOf;
import '../local/key_storage.dart';
import '../local/keys.dart' as keys;
import '../local/keys.dart' show KeysOptions, LocalKeys;
import '../local/keys_error.dart';
import '../local/pairing.dart' as pairing;
import '../local/prf.dart' as prf;
import '../local/stale_vaults.dart';
import '../local/vault_session.dart';
import '../protect/protect_actions.dart' show markRecoveryKeySaved;
import '../protect/protect_status.dart' show recoveryKeySavedAt;
import 'encryption_mode.dart';
import 'sign_in_prf.dart';
import 'unlock_hint.dart';
import 'vault_gate.dart';

/// The vault gate in the app: how `VaultGate.tsx` wires `vault-gate.ts` to the keys, the passkeys
/// and the vault session, as Riverpod providers. A `preview` account gets a gate, started at once;
/// a `plain` one (or none signed in) gets null and the app runs as before.

/// The app's gate: the real keys and the real vault session.
typedef AppVaultGate = VaultGate<LocalKeys, VaultSession>;

/// Where the vault's keys live: the Keystore / Keychain (lib/local/key_storage.dart).
final keyStorageProvider = Provider<KeyStorage>((ref) => KeyStorage());

/// Replaced in tests: where `vaultChanged` comes from.
final backgroundListenerProvider = Provider<BackgroundListener>(
  (ref) => const BackgroundListener(),
);

/// A headless run changed the vault file (D7): the open [VaultSession] re-notifies its listeners
/// and schedules a sync. The app watches it for as long as it runs (app.dart).
final vaultChangedProvider = Provider<void>((ref) {
  final remove = ref.read(backgroundListenerProvider).listen(() {
    ref.read(vaultSessionProvider)?.externalChange();
  });
  ref.onDispose(remove);
});

/// Opens a vault session: [openVaultSession]; tests put their own store folder in.
final openVaultSessionProvider = Provider<Future<VaultSession> Function(OpenVaultOptions)>(
  (ref) => openVaultSession,
);

/// Wipes an account's vault (its file and its keys): [forgetVault]; tests put their own in.
final forgetVaultProvider = Provider<Future<void> Function(String userId, KeyStorage storage)>(
  (ref) =>
      (userId, storage) => forgetVault(userId, storage),
);

/// Whether the last adoption of a deleted account's vault stopped at a `plain` new user
/// (`SessionController.adoptionStepped`): a change makes the waiting gate check again, so it says
/// why at once.
final adoptionNeedsEncryptedServerProvider = Provider<ValueNotifier<bool>>((ref) {
  final notifier = ValueNotifier(false);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// Reads a vault's hold from its file ([vaultHoldOf]); tests put their own folder in.
final vaultHoldReaderProvider = Provider<Future<VaultHold?> Function(String userId)>(
  (ref) => vaultHoldOf,
);

/// The gate of the signed-in `preview` account, started; null for `plain`, while the mode of the
/// session signed in now is not known yet, and when signed out. It is bound to that session (the
/// owner of [currentVaultAccountProvider]): another token, even a new one of the same account,
/// disposes it, closes the vault session it opened (its file and keys stay), and a new gate starts
/// once the new session's account is known. Its calls read the network client of the moment. A
/// `plain` account has no vault to open: the passkey sign-in's PRF is zeroed then, not kept until
/// the sign-out (the web's `clearSignInPrf` in the `/app` and `/welcome` loaders).
final vaultGateProvider = Provider<AppVaultGate?>((ref) {
  final key = ref.watch(
    currentVaultAccountProvider.select((a) => a == null ? null : (a.owner, a.profile.id, a.mode)),
  );
  final account = ref.read(currentVaultAccountProvider);
  if (key == null || account == null) return null;
  if (account.mode != EncryptionMode.preview) {
    ref.read(signInPrfProvider).clear();
    return null;
  }
  return _gateFor(ref, account.profile, account.owner)..start();
});

/// The gate's state (null without a gate); rebuilt on every change.
final vaultGateStateProvider = Provider<VaultGateState<VaultSession>?>((ref) {
  final gate = ref.watch(vaultGateProvider);
  if (gate == null) return null;
  ref.onDispose(gate.subscribe(ref.invalidateSelf));
  return gate.state;
});

/// The account's time zone, for the time a pairing code stops working; UTC while it is not known.
final pairingTimeZoneProvider = Provider<String>(
  (ref) => ref.watch(currentVaultAccountProvider.select((a) => a?.profile.timezone)) ?? 'UTC',
);

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

/// A new phone's request for the gate: `local/pairing.dart` with the keys it ends in.
class _GatePairing implements GatePairing<LocalKeys> {
  const _GatePairing(this._request);

  final pairing.NewDevicePairing _request;

  @override
  String get id => _request.id;
  @override
  String get code => _request.code;
  @override
  String get qr => _request.qr;
  @override
  String get expiresAt => _request.expiresAt;
  @override
  Future<String> number() => _request.number();
  @override
  Future<LocalKeys> finish() => _request.finish();
  @override
  void cancel() => _request.cancel();
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

  /// The session ended under the vault (a 401), and [kind] says why
  /// ([SessionController.sessionEnded]): it expired or the account signed out everywhere, and the
  /// vault, its keys and its changes not sent yet stay for this account's next sign-in (unlike the
  /// web's `signInAgain`, which wipes them: spec 2026-11-12 sections 3 and 6.5); this phone was
  /// removed (`device_removed`), and the vault is wiped; the account was deleted (`user_deleted`),
  /// and a new user adopts the vault. The server already dropped the session, so even a guest's goes.
  Future<void> signInAgain([Unauthorized kind = Unauthorized.expired]) async {
    // A late 401 of a session that is gone never ends the one signed in now.
    if (!current()) return;
    final session = ref.read(sessionProvider.notifier);
    final token = ref.read(sessionProvider).stored?.token;
    try {
      await session.sessionEnded(token: token, kind: kind);
    } on Object {
      // Ended here all the same at the next start (the server says 401).
    }
  }

  /// A 401 from `/v2/keys`: the session ends as its code says ([signInAgain]), the gate stays put.
  Future<T> signInAgainOn401<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on KeysError catch (error) {
      if (error.status == 401) unawaited(signInAgain(unauthorizedOf(error.code)));
      rethrow;
    }
  }

  /// Who answered the last [sessionUserId]: null is no one (the session is gone), and
  /// [nobodyBecause] says why.
  var nobody = false;
  var nobodyBecause = Unauthorized.expired;

  /// Who is signed in now (`GET /v1/me` on the network): null when no one; throws when it cannot
  /// tell.
  Future<String?> sessionUserId() async {
    final token = read(sessionProvider).stored?.token;
    nobody = token == null;
    if (token == null) return null;
    try {
      // Naming the vault's account (ruling 17): a deleted one answers `user_deleted`.
      final me = (await read(
        networkClientProvider,
      ).api.getDefaultApi().getMe(headers: {'x-wambito-user': userId})).data;
      if (me == null) throw const GateError('server');
      return me.id;
    } on DioException catch (error) {
      final kind = unauthorizedOfError(error);
      if (kind == null) rethrow;
      nobody = true;
      nobodyBecause = kind;
      return null;
    }
  }

  /// Another account signed in: the account's providers again, for them (a new gate). No one: the
  /// session is gone, so sign in again.
  void reload() {
    if (!current()) return;
    if (nobody) {
      unawaited(signInAgain(nobodyBecause));
    } else {
      ref.invalidate(freshVaultAccountProvider);
    }
  }

  /// A vault held `orphaned` (or `provisional`, an offline first run's) is being adopted into a new
  /// user (lib/local/adopt.dart): it never opens (a write now would be lost when the adoption
  /// forgets it), the adoption is asked to go on, and
  /// the gate says why it waits: `plain_server` when the new user would keep data in clear, else
  /// `adopting` (shown as offline; a retry asks again). A hold that cannot be read opens as before.
  Future<void> refuseAdopted() async {
    VaultHold? hold;
    try {
      hold = await read(vaultHoldReaderProvider)(userId);
    } on GateError {
      rethrow;
    } on Object {
      return;
    }
    // A `provisional` hold is an offline first run's vault being promoted: no write may land in
    // it after the carry read it, so it never opens as an account's vault either.
    if (hold?.kind != VaultHoldKind.orphaned && hold?.kind != VaultHoldKind.provisional) return;
    final session = read(sessionProvider.notifier);
    unawaited(session.resumeAdoptions().catchError((Object _) {}));
    throw GateError(session.adoptionNeedsEncryptedServer ? 'plain_server' : 'adopting');
  }

  /// The vault was just unlocked with the recovery key typed at sign-in: the person has that key,
  /// so once it opens "Protect your data"'s first step is marked done when it is not yet.
  var openedWithSignInKey = false;

  /// The session the gate's listeners are on, so a reused one is not wired twice, and their
  /// unsubscribes.
  VaultSession? wired;
  final detach = <void Function()>[];

  // The adoption's stop changed (a `plain` new user, or no longer): a Locked gate checks again.
  void adoptionChanged() {
    if (!gate.disposed) gate.retry();
  }

  final adoptionWait = ref.read(adoptionNeedsEncryptedServerProvider)..addListener(adoptionChanged);
  detach.add(() => adoptionWait.removeListener(adoptionChanged));

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
      // The key typed at sign-in, this account's only, and never for a gate no longer current.
      takeSignInRecoverySecret: () =>
          current() ? ref.read(signInRecoveryKeyProvider).take(userId) : null,
      unlockWithRecoverySecret: (secret) async {
        final local = await signInAgainOn401(
          () => keys.unlockWithRecoverySecret(options(), secret),
        );
        openedWithSignInKey = true;
        return local;
      },
      // The passkey sign-in's PRF, this account's only, and never for a gate no longer current.
      takeSignInPrf: () => current() ? ref.read(signInPrfProvider).take(userId) : null,
      unlockWithPasskey: (passkey) =>
          signInAgainOn401(() => keys.unlockWithPasskey(options(), passkey)),
      addPasskeyWrap: (passkey) => keys.addPasskeyWrap(options(), passkey),
      evaluatePrf: (ids) => touchPasskey(read(authApiProvider), read(passkeysProvider), ids),
      accountPasskeyIds: () => accountPasskeyIds(network()),
      startPairing: () async =>
          _GatePairing(await signInAgainOn401(() => pairing.startPairing(options()))),
      open: (localKeys, fresh) async {
        // Read and reset before anything can fail: a failed open never leaves it set for a later one.
        final markKeySaved = openedWithSignInKey;
        openedWithSignInKey = false;
        await refuseAdopted();
        final token = read(sessionProvider).stored?.token;
        final session = await read(openVaultSessionProvider)(
          OpenVaultOptions(
            profile: profile,
            keys: localKeys,
            fresh: fresh,
            network: network(),
            storage: storage(),
            // A kept vault under a new session links its device wrap to it (a removal ends it).
            sessionOwner: token == null ? null : sessionOwnerOf(token),
            onUnauthorized: (kind) => unawaited(signInAgain(kind)),
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
        try {
          // Held while it opened (the adoption began meanwhile): closed again before any write.
          await refuseAdopted();
        } on Object {
          await session.close().catchError((Object _) {});
          rethrow;
        }
        if (markKeySaved) unawaited(_markKeySavedIfNot(session));
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
      userId: userId,
      sessionUserId: sessionUserId,
      reload: reload,
      // The "no PRF here" hint of this account (a pref), and its passkey wraps for Unlock's layout.
      passkeyGaveNoPrf: () => read(unlockHintProvider).gaveNoPrf(userId),
      notePasskeyWithoutPrf: () => read(unlockHintProvider).noteWithoutPrf(userId),
      notePasskeyOpened: () => read(unlockHintProvider).noteOpened(userId),
      // Any failure (offline, a 5xx, a 401) counts as a wrap: the screen never hides the passkey on
      // a guess, and the read never ends the session nor locks the gate.
      hasPasskeyWrap: () async {
        try {
          return await keys.hasPasskeyWrap(options());
        } on Object {
          return true;
        }
      },
    ),
  );
  return gate;
}

/// Marks `recoveryKeySavedAt` in the settings record when it is still null: the vault was opened
/// with the recovery key the person typed to sign in, so they have it. Best effort: a failure only
/// leaves the step to do.
Future<void> _markKeySavedIfNot(VaultSession session) async {
  try {
    if (await recoveryKeySavedAt(session.store) != null) return;
    await markRecoveryKeySaved(session, DateTime.now());
  } on Object {
    // The step stays to do; Settings shows it.
  }
}

/// Deletes the vault (file, keys, kept mode and account) of every account on this phone but
/// [keepUserId] ([deleteStaleVaults]): at each answer of `GET /v1/me` with the signed-in account, and
/// on a signed-out start with the account whose session ended without a sign-out. Never throws.
final staleVaultsProvider = Provider<Future<void> Function(String? keepUserId)>((ref) {
  final keys = ref.read(keyStorageProvider);
  final forget = ref.read(forgetVaultProvider);
  return (keep) => deleteStaleVaults(
    keep,
    forget: (id) => forget(id, keys),
    // Asked again before each delete: an account that signed in meanwhile keeps its vault.
    inUse: (id) => vaultInUse(id) || ref.read(knownAccountProvider).id == id,
    holdOf: vaultHoldOf,
  );
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
