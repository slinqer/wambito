// Twin of apps/web/app/features/settings/security.ts: Settings → Security's effects, as an
// interface so tests stand in for the vault, the passkey prompt and `/v2/keys`. Errors carry a
// `code` (`KeysError` / `PairingError` codes).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/passkeys.dart' show passkeysProvider;
import '../../api/session.dart' show authApiProvider, networkClientProvider;
import '../../local/keys.dart';
import '../../local/keys.dart' as keys;
import '../../local/pairing.dart' as pair;
import '../../local/pairing.dart' show ApproverPairing, PairingError;
import '../../local/prf.dart' show PasskeyPrf;
import '../../local/rotate.dart' as rot;
import '../../local/signin_approval.dart' as signin;
import '../../local/signin_approval.dart' show SigninApproval, SigninError;
import '../../local/rotate.dart'
    show NewRecoveryKey, PreparedRotation, RotateRecovery, attested, revokedDevices;
import '../../local/vault_session.dart';
import '../../vault/vault_providers.dart'
    show keyStorageProvider, touchPasskey, vaultSessionProvider;

/// What Settings → Security reads: the wraps, this phone's, the revoked list, the checks.
class SecuritySnapshot {
  const SecuritySnapshot({
    required this.wraps,
    required this.ownId,
    required this.revoked,
    required this.verified,
    required this.unreadable,
  });

  final List<WrapDto> wraps;

  /// This phone's device wrap id, null when unknown.
  final String? ownId;
  final List<String> revoked;

  /// Device wrap ids whose attestation checks out under the data key.
  final Set<String> verified;

  /// Records the sync could not open (the vault's quarantine).
  final int unreadable;
}

abstract interface class SecurityApi {
  Future<SecuritySnapshot> load();

  /// Removes devices and rotates the data key (`rotateKeys`); nothing reaches the server until the
  /// prepared rotation's `commit()`. A touched [passkey] keeps its wrap; its PRF is used up.
  Future<PreparedRotation> rotate({
    required List<String> remove,
    required RotateRecovery recovery,
    PasskeyPrf? passkey,
  });

  /// Resolves when [text] opens the current recovery wrap (`bad_` / `wrong_recovery_key`).
  Future<void> checkRecoveryKey(String text);

  Future<NewRecoveryKey> newRecoveryKey();

  /// After a rotation committed: the sync takes the new keyring.
  Future<void> reloadKeys();

  /// A passkey touch for its PRF: null when cancelled; `no_prf` without one.
  Future<PasskeyPrf?> evaluatePrf(List<String>? credentialIds);

  /// The touched passkey's wrap, from this phone's device wrap. The caller zeroes the PRF.
  Future<void> addPasskeyWrap(PasskeyPrf passkey);

  /// What approving a new device runs on.
  KeysOptions get pairing;

  /// Approving a new device: finds the request by its typed [code] or its scanned [qr].
  Future<ApproverPairing> findPairing({String? code, String? qr});

  /// Approving a web sign-in (phone-first spec 8.1): finds the browser's request by its typed
  /// [code] or its scanned [qr] ([fromLink]: the QR came in a `wambito://signin` link, not from the
  /// in-app scanner). Nothing is posted until [SigninApproval.approve].
  Future<SigninApproval> findSigninRequest({String? code, String? qr, bool fromLink = false});
}

/// The open vault's keys, against the real `/v2/keys`. [touch] is the passkey prompt for
/// [SecurityApi.evaluatePrf].
SecurityApi liveSecurity(
  VaultSession session,
  KeysOptions options, {
  Future<PasskeyPrf?> Function(List<String>? credentialIds)? touch,
}) => _LiveSecurity(session, options, touch);

class _LiveSecurity implements SecurityApi {
  _LiveSecurity(this._session, this._options, this._touch);

  final VaultSession _session;
  final KeysOptions _options;
  final Future<PasskeyPrf?> Function(List<String>? credentialIds)? _touch;

  @override
  KeysOptions get pairing => _options;

  @override
  Future<SecuritySnapshot> load() async {
    final userId = _options.userId;
    final wraps = await listWraps(api(_options));
    final ownId = await _options.storage.deviceWrapId(userId);
    final unreadable = await _session.unreadableCount();
    final revoked = await revokedDevices(_session.store);
    final verified = <String>{};
    final others = wraps.where((w) => w.kind == 'device' && w.id != ownId);
    if (others.isNotEmpty) {
      await withDataKey<void>(_options, (dataKey, _) async {
        for (final wrap in others) {
          if (await attested(userId, dataKey, wrap)) verified.add(wrap.id);
        }
      });
    }
    return SecuritySnapshot(
      wraps: wraps,
      ownId: ownId,
      revoked: revoked,
      verified: verified,
      unreadable: unreadable,
    );
  }

  @override
  Future<PreparedRotation> rotate({
    required List<String> remove,
    required RotateRecovery recovery,
    PasskeyPrf? passkey,
  }) => rot.rotateKeys(
    _options,
    store: _session.store,
    remove: remove,
    recovery: recovery,
    passkey: passkey,
  );

  @override
  Future<void> checkRecoveryKey(String text) => rot.checkRecoveryKey(_options, text);

  @override
  Future<NewRecoveryKey> newRecoveryKey() => rot.newRecoveryKey(_options);

  @override
  Future<void> reloadKeys() => _session.reloadKeys();

  @override
  Future<PasskeyPrf?> evaluatePrf(List<String>? credentialIds) {
    final touch = _touch;
    if (touch == null) throw const KeysError('no_prf');
    return touch(credentialIds);
  }

  @override
  Future<void> addPasskeyWrap(PasskeyPrf passkey) => keys.addPasskeyWrap(_options, passkey);

  @override
  Future<ApproverPairing> findPairing({String? code, String? qr}) =>
      pair.findPairing(_options, code: code, qr: qr);

  @override
  Future<SigninApproval> findSigninRequest({String? code, String? qr, bool fromLink = false}) =>
      signin.findSigninRequest(_options, code: code, qr: qr, fromLink: fromLink);
}

/// The open vault's [SecurityApi]; null while no vault is open (signed out, a `plain` account, or
/// locked), so Settings shows nothing of it.
final securityApiProvider = Provider<SecurityApi?>((ref) {
  final session = ref.watch(vaultSessionProvider);
  if (session == null) return null;
  final options = KeysOptions(
    userId: session.userId,
    dio: ref.watch(networkClientProvider).dio,
    storage: ref.watch(keyStorageProvider),
  );
  final auth = ref.watch(authApiProvider);
  final passkeys = ref.watch(passkeysProvider);
  return liveSecurity(session, options, touch: (ids) => touchPasskey(auth, passkeys, ids));
});

/// The react-query key of the web's `SecurityApi.load()`: Security and the passkeys' "Opens your
/// data" share it. Invalidated after any change of the keys.
final securitySnapshotProvider = FutureProvider.autoDispose<SecuritySnapshot>((ref) {
  final security = ref.watch(securityApiProvider);
  if (security == null) throw StateError('no open vault');
  return security.load();
});

/// The code an error carries (`KeysError`, `PairingError` and `SigninError`), if any.
String? codeOf(Object? error) => switch (error) {
  KeysError(:final code) => code,
  PairingError(:final code) => code,
  SigninError(:final code) => code,
  _ => null,
};
