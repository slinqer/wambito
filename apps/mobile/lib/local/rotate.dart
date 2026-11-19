import 'package:flutter/foundation.dart';

import '../crypto/crypto.dart';
import 'ids.dart';
import 'keys.dart';
import 'prf.dart';
import 'store.dart';

/// Twin of apps/web/app/local/rotate.ts. Rotating the data key now serves "Change keys" (spec
/// 2026-11-08 section 7.5, addendum 2026-11-08-e2e-stage-1b section 2, stage 2b Rulings 1, 2 and 7;
/// removing a device no longer rotates: one `DELETE /v2/keys/{id}`, spec 2026-11-18), and a new
/// recovery key replaces the recovery wrap. Both are two steps, like `prepareAccount`: everything
/// is made in memory first (DK from this phone's own device wrap and the recovery secret are zeroed
/// before the first step returns) and nothing reaches the server until `commit()`. Unlike the web,
/// which keeps derived non-extractable keys, the phone keeps raw data keys ([KeyStorage]): a
/// rotation holds its new DK in memory until its commit is done or refused for good, then zeroes
/// it. The recovery verifier (spec 2026-11-15 section 6, plan decision D16): the server deletes it
/// when a recovery wrap is replaced and keeps it on a rotation, so the phone sends it after every
/// recovery wrap whose key is new. Nothing here logs a secret, a key, a hash or a recovery key.

/// The test seams of the web's mocks of `newRecoverySecret`, `generateDataKey` and
/// `unwrapDataKey` (to check that every secret and key they hand out is zeroed). Production code
/// never changes them.
@visibleForTesting
Uint8List Function() keysNewRecoverySecret = newRecoverySecret;
@visibleForTesting
Uint8List Function() keysRotateDataKey = generateDataKey;
@visibleForTesting
Future<Uint8List> Function(Uint8List secret, WrapContext ctx, Uint8List wrapped) keysUnwrapDataKey =
    unwrapDataKey;

void _zero(Uint8List? key) => key?.fillRange(0, key.length, 0);

/// A device wrap a rotation leaves out.
@immutable
class DroppedWrap {
  const DroppedWrap({required this.id, required this.label, required this.reason});

  final String id;
  final String? label;

  /// `removed`: asked for now; `revoked`: in `settings.revokedDevices`; `attestation`: forged.
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is DroppedWrap && other.id == id && other.label == label && other.reason == reason;

  @override
  int get hashCode => Object.hash(id, label, reason);

  @override
  String toString() => 'DroppedWrap($id, $label, $reason)';
}

class RotateResult {
  const RotateResult({required this.keyV, required this.dropped});

  final int keyV;
  final List<DroppedWrap> dropped;
}

/// The recovery wrap of the new DK (D15): the typed recovery key ([TypedRecovery]: it must open
/// the current recovery wrap, else `wrong_recovery_key`; the same key is re-wrapped), or a new one
/// ([FreshRecovery]: shown by the caller before `commit()`).
sealed class RotateRecovery {
  const RotateRecovery();
}

final class TypedRecovery extends RotateRecovery {
  const TypedRecovery(this.text);

  final String text;
}

final class FreshRecovery extends RotateRecovery {
  const FreshRecovery();
}

/// A rotation, made but not yet sent: see [rotateKeys].
class PreparedRotation {
  const PreparedRotation({
    required this.recoveryKey,
    required this.commit,
    this.forget = _nothing,
    this.refusedForGood = _no,
  });

  /// The new recovery key to show ([FreshRecovery]); `null` for a typed one.
  final String? recoveryKey;

  /// Posts the rotation, keeps it on this phone, then (a fresh key) PUTs its verifier. Retry-safe:
  /// a step done is not done again, and a double tap shares the call in flight.
  final Future<RotateResult> Function() commit;

  /// The person gave up before committing: zeroes the new DK held for `commit()`, which then
  /// throws `abandoned` (nothing is posted). Only for a rotation that never left the phone: nothing
  /// happens once a POST was attempted (the server may hold it, and only `commit()` keeps it here and
  /// writes `revokedDevices`; retry it), once the commit is done, or while one is in flight.
  final void Function() forget;

  /// Asks whether the commit was refused for good (`rotated_elsewhere`, `tampered`, or given up):
  /// every `commit()` now throws the same error, so a retry is pointless.
  final bool Function() refusedForGood;

  /// Whether the commit was refused for good; false after `offline` and other retryable failures.
  bool get refused => refusedForGood();
}

void _nothing() {}
bool _no() => false;

/// `wrong_recovery_key` unless [secret] opens the account's current recovery wrap.
Future<void> _checkRecovery(String userId, List<WrapDto> wraps, Uint8List secret) async {
  final wrap = wraps.where((w) => w.kind == 'recovery').firstOrNull;
  if (wrap == null) throw const KeysError('wrong_recovery_key');
  final Uint8List opened;
  try {
    opened = await keysUnwrapDataKey(
      secret,
      WrapContext(kind: WrapKind.recovery, userId: userId, keyV: wrap.keyV),
      fromBase64Url(wrap.wrapped),
    );
  } on Object {
    throw const KeysError('wrong_recovery_key');
  }
  _zero(opened);
}

/// Whether a device wrap's attestation checks out under [dataKey] (Settings → Devices shows the
/// rest as "Not verified").
Future<bool> attested(String userId, Uint8List dataKey, WrapDto wrap) async {
  final publicKey = wrap.publicKey;
  final attestation = wrap.attestation;
  if (publicKey == null || attestation == null) return false;
  try {
    return await verifyDeviceAttestation(
      dataKey,
      DeviceAttestationInput(userId: userId, wrapId: wrap.id, publicKey: fromBase64Url(publicKey)),
      fromBase64Url(attestation),
    );
  } on Object {
    return false;
  }
}

/// The settings record's `revokedDevices` (none when the vault has no settings yet).
Future<List<String>> revokedDevices(FinanceStore store) async {
  final settings = (await store.list(RecordType.settings)).firstOrNull;
  return _idsOf(settings?.body['revokedDevices']);
}

List<String> _idsOf(Object? raw) => raw is List ? raw.whereType<String>().toList() : <String>[];

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
    _zero(secret);
  }
}

/// What [rotateKeys] prepares inside `withDataKey`: the wraps and link to post, the new DK (kept
/// until the commit is done or refused for good) and what is reported.
typedef _Prepared = ({
  int keyV,
  List<Map<String, Object?>> wraps,
  String link,
  Uint8List newKey,
  List<DroppedWrap> dropped,
  String ownId,
});

/// Removes devices and rotates the data key, in the order of spec 7.5 and addendum section 2:
/// 1. the typed recovery key must open the current recovery wrap (before anything is made);
/// 2. this phone's own wrap id may not be in [remove] or `settings.revokedDevices`
///    ([ArgumentError], nothing sent): a phone never removes itself;
/// 3. `refreshKeys` first (this phone then holds every version up to the account's current one),
///    then DK from this phone's own device wrap (`device_removed` when the server no longer lists
///    it); every other device wrap's attestation is verified under it, and the ids in [remove] and
///    in `settings.revokedDevices` are left out, whatever the server lists (reported in `dropped`,
///    with a forged attestation as `attestation`);
/// 4. a new DK at `keyV + 1`, and its wraps: one recovery, the kept devices (same id, ref and
///    label, sealed to their public keys with fresh attestations; this phone's own always, with
///    the public key it kept), the touched [passkey]. Assistants have no phone wraps yet.
///
/// `commit()` then `POST /v2/keys/rotate`s them with the key link (the old DK sealed under the new
/// one; 409 `key_version_mismatch` = `rotated_elsewhere`: another device rotated first, nothing is
/// kept and the new DK is zeroed), keeps the new version's data key on this phone and makes it
/// current, writes the removed ids into `settings.revokedDevices` (a local write through [store]:
/// the sync seals it under the new version), and for a [FreshRecovery] PUTs the new key's verifier
/// (D16; a typed key's verifier stands). The caller then calls the session's `reloadKeys()`, whose
/// sync's upgrade pass re-seals the old records. Retry-safe: a failed post is sent again with the
/// same wraps, and a post whose answer was lost counts as ours when the server lists this phone's
/// prepared wrap (`landed()`). The PRF of [passkey] is used up: zeroed before this returns.
Future<PreparedRotation> rotateKeys(
  KeysOptions options, {
  required FinanceStore store,
  required List<String> remove,
  required RotateRecovery recovery,
  PasskeyPrf? passkey,
}) async {
  final userId = options.userId;
  final storage = options.storage;
  final call = api(options);
  Uint8List? secret;
  try {
    switch (recovery) {
      case TypedRecovery(:final text):
        try {
          secret = keysParseRecoveryKey(text);
        } on Object {
          throw const KeysError('bad_recovery_key');
        }
        await _checkRecovery(userId, await listWraps(call), secret);
      case FreshRecovery():
        secret = keysNewRecoverySecret();
    }
    final recoverySecret = secret;
    final fresh = recovery is FreshRecovery;
    final recoveryKey = fresh ? formatRecoveryKey(recoverySecret) : null;
    // A typed key's verifier is already the server's (a rotation keeps it).
    final verifier = fresh ? await verifierHashesOf(recoverySecret) : null;
    final revoked = {...await revokedDevices(store), ...remove};
    final ownId = await storage.deviceWrapId(userId);
    final ownPublicKey = await storage.devicePublicKey(userId);
    if (ownId == null || ownPublicKey == null) throw const KeysError('device_removed');
    // Before anything reaches the server: removing this phone would lock it out of the vault.
    if (revoked.contains(ownId)) throw ArgumentError('this phone cannot remove itself');
    // Holds every version up to the account's current one first: `withDataKey` alone would accept
    // a verified wrap above the held current without keeping the versions in between.
    await refreshKeys(options);

    final prepared = await withDataKey<_Prepared>(options, (dataKey, keyV) async {
      final wraps = await listWraps(call);
      final dropped = <DroppedWrap>[];
      final kept = <WrapDto>[];
      for (final wrap in wraps) {
        if (wrap.kind != 'device') continue;
        final label = wrap.label;
        if (wrap.id == ownId) {
          kept.add(wrap);
        } else if (remove.contains(wrap.id)) {
          dropped.add(DroppedWrap(id: wrap.id, label: label, reason: 'removed'));
        } else if (revoked.contains(wrap.id)) {
          dropped.add(DroppedWrap(id: wrap.id, label: label, reason: 'revoked'));
        } else if (!await attested(userId, dataKey, wrap)) {
          dropped.add(DroppedWrap(id: wrap.id, label: label, reason: 'attestation'));
        } else {
          kept.add(wrap);
        }
      }
      // `withDataKey` opened this very wrap, so it is listed; checked again all the same.
      if (!kept.any((w) => w.id == ownId)) throw const KeysError('device_removed');

      final nextV = keyV + 1;
      final newKey = keysRotateDataKey();
      try {
        final body = <Map<String, Object?>>[];
        final recoveryWrap = wraps.where((w) => w.kind == 'recovery').firstOrNull;
        body.add({
          'id': !fresh && recoveryWrap != null ? recoveryWrap.id : uuidv7(),
          'kind': 'recovery',
          'keyV': nextV,
          'wrapped': toBase64Url(
            await wrapDataKey(
              recoverySecret,
              WrapContext(kind: WrapKind.recovery, userId: userId, keyV: nextV),
              newKey,
            ),
          ),
        });
        for (final device in kept) {
          // this phone's own: the public key it kept (`withDataKey` checked the listed one is it)
          final publicKeyText = device.id == ownId ? ownPublicKey : device.publicKey!;
          final publicKey = fromBase64Url(publicKeyText);
          final wrapped = await sealToDevice(
            publicKey,
            WrapContext(kind: WrapKind.device, userId: userId, keyV: nextV),
            newKey,
          );
          final attestation = await deviceAttestation(
            newKey,
            DeviceAttestationInput(userId: userId, wrapId: device.id, publicKey: publicKey),
          );
          body.add({
            'id': device.id,
            'kind': 'device',
            if (device.ref != null) 'ref': device.ref,
            'keyV': nextV,
            'wrapped': toBase64Url(wrapped),
            'publicKey': publicKeyText,
            'attestation': toBase64Url(attestation),
            if (device.label != null) 'label': device.label,
          });
        }
        if (passkey != null) {
          final existing = wraps
              .where((w) => w.kind == 'passkey' && w.ref == passkey.credentialId)
              .firstOrNull;
          body.add({
            'id': existing?.id ?? uuidv7(),
            'kind': 'passkey',
            'ref': passkey.credentialId,
            'keyV': nextV,
            'wrapped': toBase64Url(
              await wrapDataKey(
                passkey.prf,
                WrapContext(kind: WrapKind.passkey, userId: userId, keyV: nextV),
                newKey,
              ),
            ),
            if (existing?.label != null) 'label': existing!.label,
          });
        }
        // The link: the old DK (version `keyV`) sealed under the new one, so other devices can
        // follow the rotation. Made here, kept in `prepared`: a retried commit posts the same one.
        final link = toBase64Url(
          await sealKeyLink(newKey, dataKey, LinkContext(userId: userId, keyV: nextV)),
        );
        return (
          keyV: nextV,
          wraps: body,
          link: link,
          newKey: newKey,
          dropped: dropped,
          ownId: ownId,
        );
      } on Object {
        _zero(newKey);
        rethrow;
      }
    });

    /// The server's current wraps include this phone's prepared wrap: the rotation is ours. A
    /// listing that could not be had is `offline`, never `false` (R13): only a server that answered
    /// with someone else's wraps refuses this rotation for good.
    Future<bool> landed() async {
      final own = prepared.wraps.where((w) => w['id'] == prepared.ownId).firstOrNull;
      final List<WrapDto> wraps;
      try {
        wraps = await listWraps(call);
      } on Object {
        throw const KeysError('offline');
      }
      final wrap = wraps.where((w) => w.id == prepared.ownId).firstOrNull;
      return own != null && wrap?.keyV == prepared.keyV && wrap?.wrapped == own['wrapped'];
    }

    var posted = false;

    /// A POST was tried: the server may hold the rotation, so it is never given up (R17).
    var attempted = false;
    var kept = false;
    var verifierSent = false;
    KeysError? refused;
    RotateResult? done;
    Future<RotateResult>? running;

    /// Done, or refused for good ([error]): the new DK is never used again.
    void drop(KeysError? error) {
      refused = error;
      _zero(prepared.newKey);
    }

    Future<RotateResult> run() async {
      final result = done;
      if (result != null) return result;
      final failure = refused;
      if (failure != null) throw failure;
      if (!posted) {
        attempted = true;
        try {
          await call(
            '/v2/keys/rotate',
            method: 'POST',
            data: {'keyV': prepared.keyV, 'wraps': prepared.wraps, 'link': prepared.link},
          );
        } on KeysError catch (error) {
          // The rotate is not idempotent: a post whose answer was lost (`offline`), retried, gets
          // 409 (`rotated_elsewhere`). Ours if the server holds this phone's prepared wrap.
          final lost = error.code == 'offline' || error.code == 'rotated_elsewhere';
          // `landed()` throws `offline` when it cannot ask: nothing is latched, a retry asks again.
          if (!lost || !await landed()) {
            // Another device's rotation won: this one is never posted again.
            if (error.code == 'rotated_elsewhere') drop(error);
            rethrow;
          }
        }
        posted = true;
      }
      if (!kept) {
        try {
          await _keepRotated(options, store, prepared.keyV, prepared.newKey, remove);
        } on KeysError catch (error) {
          if (error.code == 'tampered') drop(error);
          rethrow;
        }
        kept = true;
      }
      // After the rotation is kept here: a failure only leaves the verifier to send again.
      if (verifier != null && !verifierSent) {
        await putRecoveryVerifier(options, verifier);
        verifierSent = true;
      }
      final finished = RotateResult(keyV: prepared.keyV, dropped: prepared.dropped);
      done = finished;
      drop(null);
      return finished;
    }

    return PreparedRotation(
      recoveryKey: recoveryKey,
      commit: () => running ??= run().whenComplete(() => running = null),
      refusedForGood: () => refused != null,
      forget: () {
        if (done == null && running == null && refused == null && !attempted) {
          drop(const KeysError('abandoned'));
          _zero(verifier?.lookupHash);
          _zero(verifier?.authHash);
        }
      },
    );
  } finally {
    _zero(secret);
    _zero(passkey?.prf);
  }
}

/// The new version's data key is kept and made current, and the removed ids join
/// `settings.revokedDevices`. A `dk.<keyV>` already held (a refresh met this rotation first, or an
/// earlier try failed half-way) is kept when it is the same key; another key is never overwritten:
/// `tampered`, nothing written. `current` only grows: a refresh that already moved past [keyV]
/// stays where it is.
Future<void> _keepRotated(
  KeysOptions options,
  FinanceStore store,
  int keyV,
  Uint8List newKey,
  List<String> removed,
) async {
  final userId = options.userId;
  final storage = options.storage;
  final held = await storage.readDataKey(userId, keyV);
  try {
    if (held != null) {
      // a version this phone holds is never replaced by another key (versions only grow)
      if (!timingSafeEqual(held, newKey)) throw const KeysError('tampered');
    } else {
      await storage.writeDataKey(userId, keyV, newKey);
    }
  } finally {
    _zero(held);
  }
  final current = await storage.current(userId);
  if (current == null || current < keyV) await storage.setCurrent(userId, keyV);
  await store.transaction((tx) async {
    final settings = (await tx.list(RecordType.settings)).firstOrNull;
    if (settings == null) return;
    final before = _idsOf(settings.body['revokedDevices']);
    final revoked = {...before, ...removed}.toList();
    if (revoked.length == before.length) return;
    await tx.put(RecordType.settings, settings.id, {...settings.body, 'revokedDevices': revoked});
  });
}

/// A new recovery key, made but not yet sent: see [newRecoveryKey].
class NewRecoveryKey {
  const NewRecoveryKey({
    required this.recoveryKey,
    required this.commit,
    this.forget = _nothing,
    this.refusedForGood = _no,
  });

  /// The formatted recovery key to show.
  final String recoveryKey;

  /// Puts the recovery wrap, then the verifier. Retry-safe: the same wrap id and bytes on every
  /// try, a wrap already saved is not put again, and a double tap shares the call in flight.
  final Future<void> Function() commit;

  /// The person gave up before committing: zeroes the verifier hashes held for `commit()`, which
  /// then throws `abandoned` (nothing is sent). The wrap's bytes are no secret and just go. Nothing
  /// happens once a PUT was attempted (the server may hold it: retry `commit()`), once the commit
  /// is done, or while one is in flight.
  final void Function() forget;

  /// Asks whether the server refused it for sure (`rotated_elsewhere`): make the key again.
  final bool Function() refusedForGood;

  bool get refused => refusedForGood();
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
    var attempted = false;
    var refusedSure = false;
    Future<void> send() async {
      if (!wrapSent) {
        attempted = true;
        try {
          await call('/v2/keys/$id', method: 'PUT', data: body);
        } on KeysError catch (error) {
          // `rotated_elsewhere` was refused for sure; anything else may have been kept.
          if (error.code == 'rotated_elsewhere') refusedSure = true;
          if (error.code == 'rotated_elsewhere' || !await landed()) rethrow;
        }
        wrapSent = true;
      }
      await putRecoveryVerifier(options, hashes);
    }

    Future<void>? sent;
    var abandoned = false;
    var done = false;
    return NewRecoveryKey(
      recoveryKey: recoveryKey,
      commit: () {
        if (abandoned) return Future<void>.error(const KeysError('abandoned'));
        return sent ??= send()
            .then<void>((_) {
              done = true;
            })
            .catchError((Object error) {
              sent = null;
              throw error;
            });
      },
      refusedForGood: () => refusedSure || abandoned,
      forget: () {
        if (done || attempted || sent != null || abandoned) return;
        abandoned = true;
        _zero(hashes.lookupHash);
        _zero(hashes.authHash);
      },
    );
  } finally {
    _zero(secret);
  }
}
