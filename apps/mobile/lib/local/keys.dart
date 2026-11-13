import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../crypto/crypto.dart';
import 'ids.dart';
import 'key_storage.dart';
import 'keys_error.dart';
import 'prf.dart';

export 'key_storage.dart';
export 'keys_error.dart';

/// Keys on the phone: the twin of apps/web/app/local/keys.ts (specs 2026-11-08 sections 4.1, 5.2,
/// 7.1, 7.2, 7.4, 7.5; 2026-11-10 key links; 2026-11-12 section 3). The phone keeps the raw data
/// key DK of each held key version, its X25519 device private key and its device wrap's id and
/// public key in [KeyStorage] (Keystore / Keychain); the record keys are derived at load. The web
/// keeps derived non-extractable `CryptoKey`s instead, so where it checks a key with a canary the
/// phone compares the two data keys in constant time. All network goes through [KeysOptions.dio]
/// (base `<server>/api`), every call naming the vault's account.
///
/// The loading and acceptance half (Task 9) comes first; the setup and unlock half (Task 10:
/// [enrollDevice], [prepareAccount], [unlockWithRecovery], [unlockWithPasskey], [addPasskeyWrap])
/// builds on [olderForTrustedKey] at the end.
///
/// Codes of [KeysError] (as `KeysErrorCode` in keys.ts): `already_set_up`, `bad_recovery_key`,
/// `wrong_recovery_key`, `offline`, `server`, `unsupported_browser`, `session_changed`,
/// `device_removed`, `rotated_elsewhere`, `no_prf`, `no_passkey_wrap`, `unknown_passkey`,
/// `tampered`.

/// The key version a new account starts at.
const firstKeyV = 1;

class KeysOptions {
  const KeysOptions({required this.userId, required this.dio, required this.storage});

  final String userId;

  /// The network client (base `<server>/api`), without the local interceptor.
  final Dio dio;
  final KeyStorage storage;
}

/// The record keys this phone holds, by key version (ascending); [current] is the account's newest.
class Keyring {
  const Keyring({required this.current, required this.byVersion});

  final int current;
  final Map<int, RecordKeys> byVersion;
}

class LocalKeys {
  const LocalKeys({required this.keyring});

  final Keyring keyring;
}

/// The record keys of the keyring's current version (always present in a loaded keyring).
RecordKeys currentRecordKeys(LocalKeys local) {
  final keys = local.keyring.byVersion[local.keyring.current];
  if (keys == null) throw StateError('no record keys for key version ${local.keyring.current}');
  return keys;
}

/// A wrap as `GET /v2/keys` lists it.
class WrapDto {
  const WrapDto({
    required this.id,
    required this.kind,
    required this.keyV,
    required this.wrapped,
    this.ref,
    this.publicKey,
    this.attestation,
    this.label,
  });

  factory WrapDto.fromJson(Map<String, Object?> json) => WrapDto(
    id: json['id']! as String,
    kind: json['kind']! as String,
    ref: json['ref'] as String?,
    keyV: json['keyV']! as int,
    wrapped: json['wrapped']! as String,
    publicKey: json['publicKey'] as String?,
    attestation: json['attestation'] as String?,
    label: json['label'] as String?,
  );

  final String id;
  final String kind;
  final String? ref;
  final int keyV;
  final String wrapped;
  final String? publicKey;
  final String? attestation;
  final String? label;
}

/// A data key and its version, at the top of a walk down the links.
typedef TopKey = ({int keyV, Uint8List dataKey});

/// One `/v2/keys` call for the vault's account; the errors come as [KeysError]s.
typedef KeysApi = Future<Response<Object?>> Function(
  String path, {
  String method,
  Object? data,
  Map<String, String>? headers,
});

/// The test seams of the web's mocks of `openKeyLink` and `openFromDevice` (to check that every key
/// they hand out is zeroed). Production code never changes them.
@visibleForTesting
Future<Uint8List> Function(Uint8List newKey, LinkContext ctx, Uint8List link) keysOpenKeyLink =
    openKeyLink;
@visibleForTesting
Future<Uint8List> Function(Uint8List privateKey, WrapContext ctx, Uint8List sealed)
keysOpenFromDevice = openFromDevice;

/// The test seam of the web's mock of `parseRecoveryKey` (to check that unlock zeroes the secret).
@visibleForTesting
Uint8List Function(String text) keysParseRecoveryKey = parseRecoveryKey;

/// Test seams of [prepareAccount]: the keys it makes (to check they are zeroed) and the wrap that
/// may fail. Production code never changes them.
@visibleForTesting
Uint8List Function() keysGenerateDataKey = generateDataKey;
@visibleForTesting
Future<DeviceKeyPair> Function() keysGenerateDeviceKeyPair = generateDeviceKeyPair;
@visibleForTesting
Future<Uint8List> Function(Uint8List secret, WrapContext ctx, Uint8List dataKey) keysWrapDataKey =
    wrapDataKey;

/// `/v2/keys` calls for the vault's account. Every call carries `x-wambito-user`: a session that
/// now belongs to someone else gets a 409 `session_changed`.
KeysApi api(KeysOptions options) {
  return (path, {method = 'GET', data, headers}) async {
    final Response<Object?> response;
    try {
      response = await options.dio.request<Object?>(
        path,
        data: data,
        options: Options(
          method: method,
          headers: {...?headers, 'x-wambito-user': options.userId},
          validateStatus: (_) => true,
        ),
      );
    } on DioException {
      throw const KeysError('offline');
    }
    final status = response.statusCode ?? 0;
    if (status < 200 || status > 299) {
      final code = _problemCode(response.data);
      final mapped = switch ((status, code)) {
        (409, 'already_set_up') => 'already_set_up',
        (409, 'session_changed') => 'session_changed',
        (409, 'key_version_mismatch') => 'rotated_elsewhere',
        (422, 'unknown_passkey') => 'unknown_passkey',
        _ => 'server',
      };
      throw KeysError(mapped, status: status);
    }
    return response;
  };
}

String? _problemCode(Object? body) {
  try {
    final json = body is String ? jsonDecode(body) : body;
    if (json is Map && json['code'] is String) return json['code'] as String;
  } on Object {
    // no problem body
  }
  return null;
}

/// `GET /v2/keys`: the wraps, and the links by the version whose key seals them (`link(v)` holds
/// DK(v-1) under DK(v)). A link whose base64url does not decode counts as missing. A body that is
/// not the listing is `server`.
Future<({List<WrapDto> wraps, Map<int, Uint8List> links})> listKeys(KeysApi call) async {
  final response = await call('/v2/keys');
  try {
    final raw = response.data;
    final body = (raw is String ? jsonDecode(raw) : raw)! as Map;
    final wraps = [
      for (final w in body['wraps']! as List) WrapDto.fromJson((w as Map).cast<String, Object?>()),
    ];
    final links = <int, Uint8List>{};
    for (final entry in (body['links'] as List?) ?? const []) {
      try {
        final e = entry as Map;
        links[e['keyV']! as int] = fromBase64Url(e['link']! as String);
      } on Object {
        // missing
      }
    }
    return (wraps: wraps, links: links);
  } on KeysError {
    rethrow;
  } on Object {
    throw KeysError('server', status: response.statusCode);
  }
}

Future<List<WrapDto>> listWraps(KeysApi call) async => (await listKeys(call)).wraps;

/// Zeroes every data key in the map.
void _zeroKeys(Map<int, Uint8List> keys) {
  for (final key in keys.values) {
    key.fillRange(0, key.length, 0);
  }
}

void _zero(Uint8List? key) => key?.fillRange(0, key.length, 0);

/// Walks the key links down from [top] (spec 2026-11-10 section 2.2): the data keys of the versions
/// `top.keyV - 1` down to [floor], each opened from the link of the version above it. [strict]: a
/// missing or failing link is `KeysError('tampered')`; otherwise the walk stops there and returns
/// what it reached. On a throw every key it opened is zeroed; on success the caller owns them (and
/// `top.dataKey` stays the caller's either way).
Future<Map<int, Uint8List>> chainDown(
  String userId,
  TopKey top,
  Map<int, Uint8List> links,
  int floor,
  bool strict,
) async {
  final older = <int, Uint8List>{};
  try {
    var key = top.dataKey;
    for (var v = top.keyV; v >= 2 && v - 1 >= floor; v--) {
      final link = links[v];
      Uint8List? opened;
      if (link != null) {
        try {
          opened = await keysOpenKeyLink(key, LinkContext(userId: userId, keyV: v), link);
        } on Object {
          opened = null;
        }
      }
      if (opened == null) {
        if (strict) throw const KeysError('tampered');
        break;
      }
      older[v - 1] = opened;
      key = opened;
    }
    return older;
  } on Object {
    _zeroKeys(older);
    rethrow;
  }
}

/// Whether [dataKey] is the data key this phone keeps for that version ([held]), in constant time.
/// The device wrap is an anonymous sealed box, so this is what stops a server from handing this
/// phone another DK at a version it already holds. (The web, holding only derived keys, checks the
/// same with a canary record: `sameDataKey` in keys.ts.)
bool _sameDataKey(Uint8List dataKey, Uint8List held) => timingSafeEqual(dataKey, held);

/// A data key at `top.keyV`, at or above the [current] version this phone holds, is accepted only
/// when the links lead strictly down to [current] and the key reached there is the one this phone
/// holds; else `tampered`, with every key opened on the way zeroed. Returns the older keys from
/// `top.keyV - 1` down to [current] (empty when `top.keyV` is [current]).
Future<Map<int, Uint8List>> _chainToHeld(
  KeyStorage storage,
  String userId,
  TopKey top,
  Map<int, Uint8List> links,
  int current,
) async {
  if (top.keyV < current) throw const KeysError('tampered');
  final older = await chainDown(userId, top, links, current, true);
  Uint8List? held;
  try {
    final reached = top.keyV == current ? top.dataKey : older[current];
    held = await storage.readDataKey(userId, current);
    if (reached == null || held == null || !_sameDataKey(reached, held)) {
      throw const KeysError('tampered');
    }
    return older;
  } on Object {
    _zeroKeys(older);
    rethrow;
  } finally {
    _zero(held);
  }
}

/// How a trusted way in treats a vault held here. [strict] (pairing): the links must lead down to
/// its current version and reach the key it holds. [secret] (a passkey or recovery wrap, opened with
/// the person's secret, which the server cannot forge; spec 2026-11-10 section 5 over 2.3's
/// mismatch rule): the walk is not strict, and a chain that stops or ends elsewhere is no error.
enum HeldVault { strict, secret }

/// The older keys a data key from a trusted way in (a passkey or recovery wrap, or pairing) brings
/// along: every version the links reach, down to the first, stopping silently at the first missing
/// or failing link. With a vault held here, a trusted version below its current one is `tampered`
/// (a replay: versions only grow), and [HeldVault.strict] walks strictly down to the held key
/// instead. Nothing is written: the caller keeps the versions it does not hold yet (a held version
/// is never replaced) and owns and zeroes the returned keys. Task 10's unlocks and enroll use it.
Future<Map<int, Uint8List>> olderForTrustedKey(
  String userId,
  TopKey top,
  Map<int, Uint8List> links,
  HeldVault held,
  KeyStorage storage,
) async {
  final current = await storage.current(userId);
  if (current != null) {
    final heldKey = await storage.readDataKey(userId, current);
    if (heldKey != null) {
      _zero(heldKey);
      if (held == HeldVault.strict) return _chainToHeld(storage, userId, top, links, current);
      if (top.keyV < current) throw const KeysError('tampered');
    }
  }
  return chainDown(userId, top, links, firstKeyV, false);
}

/// The keys this phone kept for [userId], or `null` when it was never set up or lacks the current
/// version's key (the app is locked). Only names under `wambito.vault.<userId>.` are read: another
/// account's keys are never loaded. The raw data keys are zeroed once derived.
Future<LocalKeys?> loadLocalKeys(String userId, KeyStorage storage) async {
  final current = await storage.current(userId);
  if (current == null) return null;
  final byVersion = <int, RecordKeys>{};
  for (final v in await storage.versions(userId)) {
    final dk = await storage.readDataKey(userId, v);
    if (dk == null) continue;
    try {
      byVersion[v] = await deriveRecordKeys(dk);
    } finally {
      _zero(dk);
    }
  }
  if (!byVersion.containsKey(current)) return null;
  return LocalKeys(
    keyring: Keyring(current: current, byVersion: byVersion),
  );
}

/// Opens DK from this phone's own `device` wrap (spec 7.5, Ruling 1 of stage 2b). The wrap is the
/// one whose id this phone kept at enroll, and it must still be sealed to this phone's public key;
/// else `device_removed` (the phone never had a 2a vault, so unlike the web it does not search the
/// device wraps when no id is kept). A wrap at a version above the current one this phone holds is
/// accepted only through its links ([_chainToHeld], spec 2026-11-10 section 2.2), which also give
/// `older`: the data keys from `keyV - 1` down to the held current version. At a held version, DK
/// must be the one this phone keeps; below the current version, the version must be held and pass
/// the same check. Else `tampered`. On a throw every key is zeroed; storage is never written.
Future<({Uint8List dataKey, int keyV, Map<int, Uint8List> older})> _openOwnDeviceKey(
  KeysOptions options,
) async {
  final userId = options.userId;
  final storage = options.storage;
  Uint8List? dataKey;
  Uint8List? privateKey;
  Uint8List? held;
  var older = <int, Uint8List>{};
  try {
    privateKey = await storage.devicePrivateKey(userId);
    if (privateKey == null) throw const KeysError('device_removed');
    final wrapId = await storage.deviceWrapId(userId);
    final publicKey = await storage.devicePublicKey(userId);
    if (wrapId == null || publicKey == null) throw const KeysError('device_removed');
    final listed = await listKeys(api(options));
    final wrap = listed.wraps.where((w) => w.kind == 'device' && w.id == wrapId).firstOrNull;
    // base64url of the same 32 bytes is one string: compare as text
    if (wrap == null || wrap.publicKey != publicKey) throw const KeysError('device_removed');
    try {
      dataKey = await keysOpenFromDevice(
        privateKey,
        WrapContext(kind: WrapKind.device, userId: userId, keyV: wrap.keyV),
        fromBase64Url(wrap.wrapped),
      );
    } on Object {
      throw const KeysError('device_removed');
    }
    final keyV = wrap.keyV;
    final current = await storage.current(userId);
    // a device key without a current version: nothing to check a new version against
    if (current == null) throw const KeysError('tampered');
    if (keyV > current) {
      older = await _chainToHeld(
        storage,
        userId,
        (keyV: keyV, dataKey: dataKey),
        listed.links,
        current,
      );
    } else {
      held = await storage.readDataKey(userId, keyV);
      // below current: only a version this phone holds, with the key it holds (versions only
      // grow; a server that withheld the links at an unlock could otherwise hand it any key there)
      if (held == null && keyV < current) throw const KeysError('tampered');
      if (held != null && !_sameDataKey(dataKey, held)) throw const KeysError('tampered');
    }
    return (dataKey: dataKey, keyV: keyV, older: older);
  } on Object {
    _zero(dataKey);
    _zeroKeys(older);
    rethrow;
  } finally {
    _zero(privateKey);
    _zero(held);
  }
}

/// [_openOwnDeviceKey] for one operation: [fn] runs, then DK and the older keys are zeroed.
Future<T> _withOwnDeviceKey<T>(
  KeysOptions options,
  Future<T> Function(Uint8List dk, int keyV, Map<int, Uint8List> older) fn,
) async {
  final opened = await _openOwnDeviceKey(options);
  try {
    return await fn(opened.dataKey, opened.keyV, opened.older);
  } finally {
    _zero(opened.dataKey);
    _zeroKeys(opened.older);
  }
}

/// Opens DK from this phone's own `device` wrap for one operation: [fn] gets DK and the wrap's
/// `keyV`, and DK is zeroed once [fn] settles. `device_removed` when this phone's wrap is gone or
/// sealed to another key. A version this phone holds must be the DK it keeps, a version below the
/// current one must be held, and a newer one must lead back to it through its links; else
/// `tampered` (every key zeroed, [fn] never runs). See [_openOwnDeviceKey].
Future<T> withDataKey<T>(KeysOptions options, Future<T> Function(Uint8List dk, int keyV) fn) =>
    _withOwnDeviceKey(options, (dk, keyV, _) => fn(dk, keyV));

/// The account moved to a new key version (a rotation): opens this phone's device wrap and, only
/// when its `keyV` (n) is higher than the current one (c) and its links lead back to the key held
/// for c, keeps the data keys of every version from c + 1 to n beside the older ones (records
/// under them still need opening) and makes n current. Key versions only grow: a wrap at or below
/// the current version (a stale listing, or a server replaying an old wrap) changes nothing only
/// when it is a held version whose key passes the check; one below the current version that this
/// phone does not hold is `tampered`. A version already held is never overwritten. Returns the
/// keyring. `device_removed` (nothing held for [KeysOptions.userId], or its wrap is gone) and
/// `tampered` (nothing kept, storage as it was) as [withDataKey].
Future<LocalKeys> refreshKeys(KeysOptions options) async {
  final userId = options.userId;
  final storage = options.storage;
  final before = await loadLocalKeys(userId, storage);
  if (before == null) throw const KeysError('device_removed');
  await _withOwnDeviceKey(options, (dataKey, keyV, older) async {
    final current = before.keyring.current;
    final byVersion = before.keyring.byVersion;
    if (keyV <= current || byVersion.containsKey(keyV)) return;
    final fresh = <int, Uint8List>{keyV: dataKey};
    for (final MapEntry(key: v, value: key) in older.entries) {
      if (v > current && !byVersion.containsKey(v)) fresh[v] = key;
    }
    for (final MapEntry(key: v, value: key) in fresh.entries) {
      await storage.writeDataKey(userId, v, key);
    }
    // current last: a write that fails half-way leaves the held version current
    await storage.setCurrent(userId, keyV);
  });
  final local = await loadLocalKeys(userId, storage);
  if (local == null) throw const KeysError('device_removed');
  return local;
}

/// Forgets one old key version's data key, once no local record uses it.
Future<void> dropKeyVersion(String userId, int keyV, KeyStorage storage) =>
    storage.deleteDataKey(userId, keyV);

/// Signing out: deletes every `wambito.vault.<userId>.*` key of this phone (the vault file is
/// deleted by the vault session).
Future<void> forgetDevice(String userId, KeyStorage storage) => storage.deleteAll(userId);

// ---------------------------------------------------------------------------------------------
// Setup and unlock (Task 10).

/// A device wrap's label, so the person can tell their devices apart in Settings → Security. The
/// web's is `"<browser> on <OS>"` (device-label.ts); the phone's is the app on its system.
String _deviceLabel() => switch (defaultTargetPlatform) {
  TargetPlatform.android => 'Wambito on Android',
  TargetPlatform.iOS => 'Wambito on iOS',
  _ => 'Wambito',
};

/// A device key pair and its wrap of DK, made in memory; nothing sent yet.
typedef _Device = ({String id, Uint8List privateKey, String publicKey, Map<String, Object?> body});

Future<_Device> _prepareDevice(
  String userId,
  Uint8List dataKey,
  int keyV,
  DeviceKeyPair pair,
) async {
  final id = uuidv7();
  final wrapped = await sealToDevice(
    pair.publicKey,
    WrapContext(kind: WrapKind.device, userId: userId, keyV: keyV),
    dataKey,
  );
  final attestation = await deviceAttestation(
    dataKey,
    DeviceAttestationInput(userId: userId, wrapId: id, publicKey: pair.publicKey),
  );
  final publicKey = toBase64Url(pair.publicKey);
  return (
    id: id,
    privateKey: pair.privateKey,
    publicKey: publicKey,
    body: {
      'kind': 'device',
      'ref': id,
      'keyV': keyV,
      'wrapped': toBase64Url(wrapped),
      'publicKey': publicKey,
      'attestation': toBase64Url(attestation),
      'label': _deviceLabel(),
    },
  );
}

/// Keeps the data key of [keyV] (made current) and of every [older] version this phone does not
/// hold yet (a held version is never replaced), the device private key and its wrap's id and public
/// key. `current` is written last: a write that fails half-way leaves the previous state current
/// (or, on a fresh phone, nothing loadable). The caller owns and zeroes the data keys.
Future<LocalKeys> _keepLocally(
  KeyStorage storage,
  String userId,
  Uint8List dataKey,
  int keyV,
  _Device device,
  Map<int, Uint8List> older,
) async {
  for (final MapEntry(key: v, value: key) in {keyV: dataKey, ...older}.entries) {
    final held = await storage.readDataKey(userId, v);
    if (held != null) {
      _zero(held);
      continue;
    }
    await storage.writeDataKey(userId, v, key);
  }
  await storage.setDevicePrivateKey(userId, device.privateKey);
  await storage.setDeviceWrap(userId, id: device.id, publicKey: device.publicKey);
  await storage.setCurrent(userId, keyV);
  final local = await loadLocalKeys(userId, storage);
  if (local == null) throw StateError('no record keys for key version $keyV');
  return local;
}

/// Enrolls with a trusted DK (passkey, recovery, pairing), after its walk; nothing sent before.
/// With a vault held here (unlocking again after a key version that did not verify), the new device
/// wrap replaces this phone's previous one: once the new one is kept, `DELETE /v2/keys/{previous}`
/// (the server never ends the caller's own session). A failed delete only leaves the old wrap
/// listed, for Settings to remove. The private key of [pair] is zeroed here.
Future<LocalKeys> _enrollTrusted(
  KeysOptions options,
  KeysApi call,
  Uint8List dataKey,
  int keyV,
  Map<int, Uint8List> links,
  DeviceKeyPair pair,
  HeldVault held,
) async {
  final userId = options.userId;
  final storage = options.storage;
  final LocalKeys local;
  final String? previous;
  try {
    final older = await olderForTrustedKey(
      userId,
      (keyV: keyV, dataKey: dataKey),
      links,
      held,
      storage,
    );
    try {
      previous = await storage.deviceWrapId(userId);
      final device = await _prepareDevice(userId, dataKey, keyV, pair);
      await call('/v2/keys/${device.id}', method: 'PUT', data: device.body);
      local = await _keepLocally(storage, userId, dataKey, keyV, device, older);
    } finally {
      _zeroKeys(older);
    }
  } finally {
    _zero(pair.privateKey);
  }
  if (previous != null) {
    try {
      await call('/v2/keys/$previous', method: 'DELETE');
    } on Object catch (error) {
      // The unlock stands: the old wrap only stays listed (Settings can remove it). Said once,
      // with the error's code only (never an id or a key).
      debugPrint(
        'The previous device wrap could not be removed: '
        '${error is KeysError ? error.code : 'unknown'}',
      );
    }
  }
  return local;
}

/// Adds this phone as a device: a key pair, a wrap of DK sealed to its own public key with an
/// attestation of that key under DK, then the data keys, the private key and the wrap's id and
/// public key kept locally. The caller owns [dataKey] and zeroes it. The end of pairing: DK came
/// authenticated by the number, and the links bring the older versions it reaches
/// ([olderForTrustedKey]; with a vault held here strictly down to its key, else `tampered`).
Future<LocalKeys> enrollDevice(KeysOptions options, Uint8List dataKey, int keyV) async {
  final pair = await generateDeviceKeyPair();
  final call = api(options);
  final Map<int, Uint8List> links;
  try {
    links = (await listKeys(call)).links;
  } on Object {
    _zero(pair.privateKey);
    rethrow;
  }
  return _enrollTrusted(options, call, dataKey, keyV, links, pair, HeldVault.strict);
}

/// A new account's keys, made but not yet sent: see [prepareAccount].
class PreparedAccount {
  const PreparedAccount({required this.recoveryKey, required this.commit});

  /// The formatted recovery key to show; `null` for a guest (nothing to show).
  final String? recoveryKey;

  /// Sends the recovery wrap, then the device wrap, then keeps the keys on this phone. Retry-safe:
  /// after a failure, calling it again sends the same wraps under the same ids. After success DK is
  /// zeroed, and a further call only returns the same keys. A double tap shares the call in flight.
  final Future<LocalKeys> Function() commit;
}

/// First run of an account (spec 2026-11-08 section 7.1): DK, the recovery secret and this
/// device's key pair, all in memory. Nothing reaches the server until `commit()`, which the setup
/// screen calls only once the person has typed back four characters of the key, so the account
/// never ends up with a recovery wrap whose key nobody saw. The recovery wrap goes first (the
/// server refuses any other kind first), then the device wrap. A guest has no recovery key to show
/// (E2E design section 10): its recovery secret is never shown, which still satisfies the server's
/// first-wrap rule, and the caller commits at once; turning the guest into a real account later
/// replaces that wrap with a recovery key the person keeps. Throws `already_set_up` when the
/// account has wraps: the caller shows Unlock. The recovery wrap goes with `If-None-Match: *`: if
/// another setup (another phone or browser) made the account's keys between this check and the
/// commit, `commit()` throws `already_set_up` too and this data key is dropped for good.
Future<PreparedAccount> prepareAccount(KeysOptions options, {required bool guest}) async {
  final userId = options.userId;
  final storage = options.storage;
  final pair = await keysGenerateDeviceKeyPair();
  final call = api(options);
  try {
    if ((await listWraps(call)).isNotEmpty) throw const KeysError('already_set_up');
  } on Object {
    _zero(pair.privateKey);
    rethrow;
  }

  final dataKey = keysGenerateDataKey();
  final secret = newRecoverySecret();
  final recoveryId = uuidv7();
  final Map<String, Object?> recoveryBody;
  final _Device device;
  final String? recoveryKey;
  try {
    recoveryBody = {
      'kind': 'recovery',
      'keyV': firstKeyV,
      'wrapped': toBase64Url(
        await keysWrapDataKey(
          secret,
          WrapContext(kind: WrapKind.recovery, userId: userId, keyV: firstKeyV),
          dataKey,
        ),
      ),
    };
    device = await _prepareDevice(userId, dataKey, firstKeyV, pair);
    recoveryKey = guest ? null : formatRecoveryKey(secret);
  } on Object {
    // Nothing was prepared: neither key is ever used.
    _zero(dataKey);
    _zero(pair.privateKey);
    rethrow;
  } finally {
    _zero(secret);
  }

  var recoverySent = false;
  var lost = false;
  LocalKeys? done;
  Future<LocalKeys>? running;

  void drop() {
    _zero(dataKey);
    _zero(device.privateKey);
  }

  Future<LocalKeys> run() async {
    final kept = done;
    if (kept != null) return kept;
    // Another setup won: this data key was zeroed and is never sent again.
    if (lost) throw const KeysError('already_set_up', status: 409);
    if (!recoverySent) {
      try {
        // Create-only: of two setups at once, one makes the account's data key.
        await call(
          '/v2/keys/$recoveryId',
          method: 'PUT',
          data: recoveryBody,
          headers: {'if-none-match': '*'},
        );
      } on KeysError catch (error) {
        if (error.code == 'already_set_up') {
          lost = true;
          drop();
        }
        rethrow;
      }
      recoverySent = true;
    }
    await call('/v2/keys/${device.id}', method: 'PUT', data: device.body);
    final local = await _keepLocally(storage, userId, dataKey, firstKeyV, device, const {});
    done = local;
    drop();
    return local;
  }

  return PreparedAccount(
    recoveryKey: recoveryKey,
    commit: () => running ??= run().whenComplete(() => running = null),
  );
}

/// Unlocks this phone with the typed recovery key: opens the recovery wrap, enrolls this device
/// and keeps the data keys, of the older versions the links reach too ([olderForTrustedKey], not
/// strict: the recovery secret authenticates the key, so with a vault held here a chain that does
/// not reach its key is no error, its held versions stay as they are; a recovery wrap below its
/// current version is `tampered`, nothing sent or kept). The caller then runs a full sync.
/// `bad_recovery_key` is a key that does not parse (nothing was sent); `wrong_recovery_key` one
/// that parses but opens nothing. Parsing accepts lower case, spaces and dashes, O for 0 and I or L
/// for 1.
Future<LocalKeys> unlockWithRecovery(KeysOptions options, String text) async {
  final userId = options.userId;
  final Uint8List secret;
  try {
    secret = keysParseRecoveryKey(text);
  } on Object {
    throw const KeysError('bad_recovery_key');
  }
  try {
    final pair = await generateDeviceKeyPair();
    final call = api(options);
    Uint8List? dataKey;
    try {
      final (:wraps, :links) = await listKeys(call);
      final wrap = wraps.where((w) => w.kind == 'recovery').firstOrNull;
      if (wrap == null) throw const KeysError('wrong_recovery_key');
      try {
        dataKey = await unwrapDataKey(
          secret,
          WrapContext(kind: WrapKind.recovery, userId: userId, keyV: wrap.keyV),
          fromBase64Url(wrap.wrapped),
        );
      } on Object {
        throw const KeysError('wrong_recovery_key');
      }
      return await _enrollTrusted(options, call, dataKey, wrap.keyV, links, pair, HeldVault.secret);
    } finally {
      _zero(dataKey);
      _zero(pair.privateKey);
    }
  } finally {
    _zero(secret);
  }
}

/// Unlocks this phone with a passkey's PRF (spec 2026-11-08 section 7.2): opens the passkey wrap
/// whose `ref` is the credential, enrolls this device and keeps the data keys, as
/// [unlockWithRecovery] (the same walk of the links, not strict; `tampered` only for a wrap below a
/// held vault's current version). The caller owns the PRF and zeroes it. `no_passkey_wrap` when no
/// wrap has that `ref` or the PRF does not open it (nothing is sent).
Future<LocalKeys> unlockWithPasskey(KeysOptions options, PasskeyPrf passkey) async {
  final userId = options.userId;
  final pair = await generateDeviceKeyPair();
  final call = api(options);
  Uint8List? dataKey;
  try {
    final (:wraps, :links) = await listKeys(call);
    final wrap = wraps
        .where((w) => w.kind == 'passkey' && w.ref == passkey.credentialId)
        .firstOrNull;
    if (wrap == null) throw const KeysError('no_passkey_wrap');
    try {
      dataKey = await unwrapDataKey(
        passkey.prf,
        WrapContext(kind: WrapKind.passkey, userId: userId, keyV: wrap.keyV),
        fromBase64Url(wrap.wrapped),
      );
    } on Object {
      throw const KeysError('no_passkey_wrap');
    }
    return await _enrollTrusted(options, call, dataKey, wrap.keyV, links, pair, HeldVault.secret);
  } finally {
    _zero(dataKey);
    _zero(pair.privateKey);
  }
}

/// Adds (or replaces) the wrap of DK for one passkey: DK from this phone's own device wrap
/// ([withDataKey], Ruling 1 of stage 2b; the touch on that passkey is the confirmation), wrapped
/// under its PRF at the current `keyV`, PUT as `kind: "passkey"`, `ref: credentialId`. A passkey
/// that already has a wrap keeps its id. The caller owns the PRF and zeroes it. The server stores
/// it only for one of the signed-in account's passkeys: another credential is
/// `KeysError('unknown_passkey')`, so a wrap is never made under someone else's passkey; a rotation
/// by another device in between is `rotated_elsewhere`.
Future<void> addPasskeyWrap(KeysOptions options, PasskeyPrf passkey) =>
    withDataKey(options, (dataKey, keyV) async {
      final call = api(options);
      final existing = (await listWraps(call))
          .where((w) => w.kind == 'passkey' && w.ref == passkey.credentialId)
          .firstOrNull;
      final wrapped = await wrapDataKey(
        passkey.prf,
        WrapContext(kind: WrapKind.passkey, userId: options.userId, keyV: keyV),
        dataKey,
      );
      await call(
        '/v2/keys/${existing?.id ?? uuidv7()}',
        method: 'PUT',
        data: {
          'kind': 'passkey',
          'ref': passkey.credentialId,
          'keyV': keyV,
          'wrapped': toBase64Url(wrapped),
        },
      );
    });
