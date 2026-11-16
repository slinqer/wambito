import 'package:flutter/foundation.dart';

import '../crypto/crypto.dart';
import 'ids.dart';
import 'keys.dart';

/// Twin of apps/web/app/local/rotate.ts, the recovery part ([newRecoveryKey], [checkRecoveryKey])
/// plus the recovery verifier (spec 2026-11-15 section 6, plan decision D16): the server deletes
/// the verifier when a recovery wrap is replaced and keeps it on a rotation, so the phone sends it
/// after every recovery wrap it makes. Nothing here logs or keeps a secret, a key, a hash or a
/// recovery key beyond what its doc says.

/// The test seam of the web's mock of `newRecoverySecret` (to check that the secret is zeroed).
/// Production code never changes it.
@visibleForTesting
Uint8List Function() keysNewRecoverySecret = newRecoverySecret;

/// The two hashes the server stores to let a recovery key sign in (`lookup_hash`, `auth_hash`).
typedef VerifierHashes = ({Uint8List lookupHash, Uint8List authHash});

/// The verifier hashes of a 16-byte recovery secret: SHA-256 of its two HKDF outputs
/// ([recoveryVerifier], [verifierHash]). The caller owns [secret] and zeroes it.
Future<VerifierHashes> verifierHashesOf(Uint8List secret) async {
  final verifier = await recoveryVerifier(secret);
  return (
    lookupHash: await verifierHash(verifier.lookup),
    authHash: await verifierHash(verifier.auth),
  );
}

/// `PUT /v2/recovery/verifier {lookupHash, authHash}` (base64url, as `recovery.ts` reads them):
/// replaces the account's verifier. The server needs the account's recovery wrap first (409
/// `recovery_required`) and refuses a lookup another account holds (409 `verifier_taken`); both
/// are `server` here, and no network is `offline`.
Future<void> putRecoveryVerifier(KeysOptions options, VerifierHashes hashes) async {
  await api(options)(
    '/v2/recovery/verifier',
    method: 'PUT',
    data: {'lookupHash': toBase64Url(hashes.lookupHash), 'authHash': toBase64Url(hashes.authHash)},
  );
}

/// A new recovery key, made but not yet sent: see [newRecoveryKey].
class NewRecoveryKey {
  const NewRecoveryKey({required this.recoveryKey, required this.commit});

  /// The formatted recovery key to show.
  final String recoveryKey;

  /// Puts the recovery wrap, then the verifier. Retry-safe: the same wrap id and bytes on every
  /// try, a wrap already saved is not put again, and a double tap shares the call in flight.
  final Future<void> Function() commit;
}

/// `wrong_recovery_key` unless [secret] opens the account's current recovery wrap.
Future<void> _checkRecovery(String userId, List<WrapDto> wraps, Uint8List secret) async {
  final wrap = wraps.where((w) => w.kind == 'recovery').firstOrNull;
  if (wrap == null) throw const KeysError('wrong_recovery_key');
  final Uint8List opened;
  try {
    opened = await unwrapDataKey(
      secret,
      WrapContext(kind: WrapKind.recovery, userId: userId, keyV: wrap.keyV),
      fromBase64Url(wrap.wrapped),
    );
  } on Object {
    throw const KeysError('wrong_recovery_key');
  }
  opened.fillRange(0, opened.length, 0);
}

/// Settings' confirmation before a new recovery key (stage 2b Ruling 1): resolves when [text]
/// opens the account's current recovery wrap; `bad_recovery_key` / `wrong_recovery_key` otherwise.
/// Nothing is made or sent; the secret is zeroed.
Future<void> checkRecoveryKey(KeysOptions options, String text) async {
  final Uint8List secret;
  try {
    secret = keysParseRecoveryKey(text);
  } on Object {
    throw const KeysError('bad_recovery_key');
  }
  try {
    await _checkRecovery(options.userId, await listWraps(api(options)), secret);
  } finally {
    secret.fillRange(0, secret.length, 0);
  }
}

/// A new recovery key (spec 7.5: no rotation): a new secret wraps DK, opened from this phone's own
/// device wrap, at the current `keyV`. `recoveryKey` is shown; `commit()` PUTs the wrap, which
/// replaces the account's recovery wrap (`rotated_elsewhere` when the key version moved meanwhile:
/// make it again), then PUTs the new key's verifier (the server deleted the old one with the old
/// wrap). Retry-safe: the same id and wrap on every try, and a PUT whose answer was lost counts as
/// saved when `GET /v2/keys` shows the prepared wrap (`landed()`). Any other failure may still
/// have been saved: the caller keeps showing the key and retries. DK and the secret are zeroed
/// before this returns; only the wrapped bytes and the two hashes are kept for `commit()`.
Future<NewRecoveryKey> newRecoveryKey(KeysOptions options) async {
  final userId = options.userId;
  final call = api(options);
  final secret = keysNewRecoverySecret();
  try {
    final recoveryKey = formatRecoveryKey(secret);
    final hashes = await verifierHashesOf(secret);
    final body = await withDataKey(options, (dataKey, keyV) async {
      return <String, Object?>{
        'kind': 'recovery',
        'keyV': keyV,
        'wrapped': toBase64Url(
          await wrapDataKey(
            secret,
            WrapContext(kind: WrapKind.recovery, userId: userId, keyV: keyV),
            dataKey,
          ),
        ),
      };
    });
    final id = uuidv7();

    /// The server's recovery wrap is the prepared one: an answer lost on the way was a success.
    Future<bool> landed() async {
      try {
        final wrap = (await listWraps(call)).where((w) => w.kind == 'recovery').firstOrNull;
        return wrap?.id == id && wrap?.wrapped == body['wrapped'];
      } on Object {
        return false;
      }
    }

    var wrapSent = false;
    Future<void> send() async {
      if (!wrapSent) {
        try {
          await call('/v2/keys/$id', method: 'PUT', data: body);
        } on KeysError catch (error) {
          // `rotated_elsewhere` was refused for sure; anything else may have been kept.
          if (error.code == 'rotated_elsewhere' || !await landed()) rethrow;
        }
        wrapSent = true;
      }
      await putRecoveryVerifier(options, hashes);
    }

    Future<void>? sent;
    return NewRecoveryKey(
      recoveryKey: recoveryKey,
      commit: () => sent ??= send().catchError((Object error) {
        sent = null;
        throw error;
      }),
    );
  } finally {
    secret.fillRange(0, secret.length, 0);
  }
}
