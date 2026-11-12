import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'errors.dart';
import 'keys.dart';
import 'validate.dart';

/// Twin of packages/crypto/src/wraps.ts.
enum WrapKind { passkey, recovery, device, assistant }

class WrapContext {
  const WrapContext({required this.kind, required this.userId, required this.keyV});

  final WrapKind kind;
  final String userId;
  final int keyV;
}

/// SHA-256("wambito/v1/prf"): the same salt for every passkey (a test checks it against SHA-256).
final Uint8List prfSalt = Uint8List.fromList([
  for (var i = 0; i < _prfSaltHex.length; i += 2)
    int.parse(_prfSaltHex.substring(i, i + 2), radix: 16),
]);
const _prfSaltHex = '999d11fd4d3213d08d6d21fd1e08fa663b32f6c21c4d60374015461bfcfdbedb';

final AesGcm _aes = AesGcm.with256bits();
const _tagBytes = 16;

void assertWrapContext(WrapContext ctx) {
  assertUserId(ctx.userId);
  assertKeyV(ctx.keyV);
}

Uint8List wrapAssociatedData(WrapContext ctx) {
  assertWrapContext(ctx);
  return Uint8List.fromList(
    utf8.encode('wambito/v1/wrap/${ctx.kind.name}/${ctx.userId}/${ctx.keyV}'),
  );
}

/// HKDF-SHA-256 (empty salt) from a secret to an AES-256-GCM key, info `wambito/v1/wrap/<kind>`.
Future<SecretKey> deriveWrapKey(Uint8List secret, WrapKind kind) =>
    hkdfKey(secret, 'wambito/v1/wrap/${kind.name}');

Future<Uint8List> gcmSeal(SecretKey key, Uint8List aad, Uint8List plain, Uint8List nonce) async {
  final box = await _aes.encrypt(plain, secretKey: key, nonce: nonce, aad: aad);
  return Uint8List.fromList([...nonce, ...box.cipherText, ...box.mac.bytes]);
}

/// nonce (12) || ciphertext || tag, opened; `cannot_open` for anything that does not open.
Future<Uint8List> gcmOpen(SecretKey key, Uint8List aad, Uint8List wrapped) async {
  try {
    if (wrapped.length < nonceBytes + _tagBytes) throw const CryptoError('cannot_open');
    final box = SecretBox(
      wrapped.sublist(nonceBytes, wrapped.length - _tagBytes),
      nonce: wrapped.sublist(0, nonceBytes),
      mac: Mac(wrapped.sublist(wrapped.length - _tagBytes)),
    );
    return Uint8List.fromList(await _aes.decrypt(box, secretKey: key, aad: aad));
  } on Object {
    throw const CryptoError('cannot_open');
  }
}

Uint8List _checkSecretWrap(Uint8List secret, WrapContext ctx) {
  final aad = wrapAssociatedData(ctx);
  if (ctx.kind == WrapKind.device) {
    throw const CryptoError('bad_input', 'device wraps use sealToDevice');
  }
  final want = ctx.kind == WrapKind.recovery ? 16 : 32;
  if (secret.length != want) {
    throw CryptoError('bad_input', 'secret must be $want bytes for ${ctx.kind.name}');
  }
  return aad;
}

/// Wraps the data key under a secret (passkey PRF output, recovery secret or `S`).
/// Result = nonce (12) || AES-256-GCM ciphertext and tag. [nonce] is only for test vectors.
Future<Uint8List> wrapDataKey(
  Uint8List secret,
  WrapContext ctx,
  Uint8List dataKey, {
  Uint8List? nonce,
}) async {
  final aad = _checkSecretWrap(secret, ctx);
  assertBytes(dataKey, 32, 'data key');
  final iv = nonce ?? randomNonce();
  assertNonce(iv);
  return gcmSeal(await deriveWrapKey(secret, ctx.kind), aad, dataKey, iv);
}

Future<Uint8List> unwrapDataKey(Uint8List secret, WrapContext ctx, Uint8List wrapped) async {
  final aad = _checkSecretWrap(secret, ctx);
  final key = await deriveWrapKey(secret, ctx.kind);
  final dataKey = await gcmOpen(key, aad, wrapped);
  if (dataKey.length != 32) throw const CryptoError('cannot_open');
  return dataKey;
}
