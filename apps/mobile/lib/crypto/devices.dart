import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';
import 'errors.dart';
import 'validate.dart';
import 'wraps.dart';

/// Twin of packages/crypto/src/devices.ts: X25519 device keys and the blobs sealed to them.
///
/// The private key is the raw 32-byte scalar (the TS "noble" shape): the phone keeps it in the
/// Keychain / Keystore (lib/local), never in a file.
const _keyBytes = 32;
final X25519 _x25519 = X25519();

class DeviceKeyPair {
  const DeviceKeyPair({required this.publicKey, required this.privateKey});

  final Uint8List publicKey;
  final Uint8List privateKey;
}

Future<DeviceKeyPair> generateDeviceKeyPair() async {
  final pair = await _x25519.newKeyPair();
  return DeviceKeyPair(
    publicKey: Uint8List.fromList((await pair.extractPublicKey()).bytes),
    privateKey: Uint8List.fromList(await pair.extractPrivateKeyBytes()),
  );
}

/// X25519 shared secret of a raw private key and a raw public key.
Future<Uint8List> _ecdh(Uint8List privateKey, Uint8List publicKey) async {
  if (privateKey.length != _keyBytes) {
    throw const CryptoError('bad_input', 'not a device private key');
  }
  final pair = await _x25519.newKeyPairFromSeed(privateKey);
  final shared = await _x25519.sharedSecretKey(
    keyPair: pair,
    remotePublicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
  );
  return Uint8List.fromList(await shared.extractBytes());
}

/// Sealed = ephemeral public key (32) || nonce (12) || AES-256-GCM ciphertext and tag. The
/// ephemeral pair is made here unless the caller passes one (pairing: the approver's key behind
/// the number).
Future<Uint8List> sealToDevice(
  Uint8List publicKey,
  WrapContext ctx,
  Uint8List dataKey, {
  DeviceKeyPair? ephemeral,
}) async {
  assertBytes(publicKey, _keyBytes, 'public key');
  assertBytes(dataKey, 32, 'data key');
  assertWrapContext(ctx);
  if (ctx.kind != WrapKind.device) throw const CryptoError('bad_input', 'kind must be device');
  final aad = wrapAssociatedData(ctx);
  if (ephemeral != null) assertBytes(ephemeral.publicKey, _keyBytes, 'ephemeral public key');
  final eph = ephemeral ?? await generateDeviceKeyPair();
  final Uint8List shared;
  try {
    shared = await _ecdh(eph.privateKey, publicKey);
  } on Object {
    throw const CryptoError('bad_input', 'not a valid public key');
  }
  final sealed = await gcmSeal(
    await deriveWrapKey(shared, WrapKind.device),
    aad,
    dataKey,
    randomNonce(),
  );
  return Uint8List.fromList([...eph.publicKey, ...sealed]);
}

Future<Uint8List> openFromDevice(Uint8List privateKey, WrapContext ctx, Uint8List sealed) async {
  assertWrapContext(ctx);
  if (ctx.kind != WrapKind.device) throw const CryptoError('bad_input', 'kind must be device');
  final aad = wrapAssociatedData(ctx);
  if (sealed.length < _keyBytes + nonceBytes) throw const CryptoError('cannot_open');
  try {
    final shared = await _ecdh(privateKey, sealed.sublist(0, _keyBytes));
    final dataKey = await gcmOpen(
      await deriveWrapKey(shared, WrapKind.device),
      aad,
      sealed.sublist(_keyBytes),
    );
    if (dataKey.length != 32) throw const CryptoError('cannot_open');
    return dataKey;
  } on CryptoError catch (e) {
    if (e.code == 'bad_input') rethrow;
    throw const CryptoError('cannot_open');
  } on Object {
    throw const CryptoError('cannot_open');
  }
}

/// [openFromDevice] for pairing: refuses (`cannot_open`) a blob whose first 32 bytes, the ephemeral
/// key, are not the approver key both devices saw behind the number.
Future<Uint8List> openFromPairing(
  Uint8List privateKey,
  WrapContext ctx,
  Uint8List sealed,
  Uint8List approverKey,
) {
  assertBytes(approverKey, _keyBytes, 'approver key');
  if (sealed.length < _keyBytes || !timingSafeEqual(sealed.sublist(0, _keyBytes), approverKey)) {
    throw const CryptoError('cannot_open');
  }
  return openFromDevice(privateKey, ctx, sealed);
}
