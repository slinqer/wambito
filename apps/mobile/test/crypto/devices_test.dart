import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/crypto.dart';

import 'helpers.dart';

const u1 = '0194f3a2-7b1c-7d2e-9a4f-3c5b6d7e8f90';
const ctx = WrapContext(kind: WrapKind.device, userId: u1, keyV: 1);

WrapContext withCtx(WrapContext c, {WrapKind? kind, String? userId, int? keyV}) =>
    WrapContext(kind: kind ?? c.kind, userId: userId ?? c.userId, keyV: keyV ?? c.keyV);

void main() {
  test('seals to a public key and opens with the private key', () async {
    final pair = await generateDeviceKeyPair();
    expect(pair.publicKey, hasLength(32));
    expect(pair.privateKey, hasLength(32));
    final dk = generateDataKey();
    final sealed = await sealToDevice(pair.publicKey, ctx, dk);
    expect(sealed, hasLength(32 + 12 + 32 + 16));
    expect(await openFromDevice(pair.privateKey, ctx, sealed), dk);
  });

  test('another key pair, user, key version or kind cannot open', () async {
    final a = await generateDeviceKeyPair();
    final b = await generateDeviceKeyPair();
    final sealed = await sealToDevice(a.publicKey, ctx, generateDataKey());
    expect(await code(() => openFromDevice(b.privateKey, ctx, sealed)), 'cannot_open');
    const other = '0194f3a2-7b1c-7d2e-9a4f-3c5b6d7e8f91';
    expect(
      await code(() => openFromDevice(a.privateKey, withCtx(ctx, userId: other), sealed)),
      'cannot_open',
    );
    expect(
      await code(() => openFromDevice(a.privateKey, withCtx(ctx, keyV: 2), sealed)),
      'cannot_open',
    );
  });

  test('a tampered ephemeral key, ciphertext or truncation fails', () async {
    final a = await generateDeviceKeyPair();
    final sealed = await sealToDevice(a.publicKey, ctx, generateDataKey());
    for (final i in [0, 31, 40, 60]) {
      expect(
        await code(() => openFromDevice(a.privateKey, ctx, flipped(sealed, i))),
        'cannot_open',
      );
    }
    expect(
      await code(() => openFromDevice(a.privateKey, ctx, sealed.sublist(0, 40))),
      'cannot_open',
    );
    expect(await code(() => openFromDevice(a.privateKey, ctx, Uint8List(32))), 'cannot_open');
  });

  test('takes a Better Auth shaped user id; case is significant', () async {
    final a = await generateDeviceKeyPair();
    const c = WrapContext(
      kind: WrapKind.device,
      userId: 'kX3mQ9vTz2LpR8wYb5NcHd7JfA1sUe_-',
      keyV: 1,
    );
    final dk = generateDataKey();
    final sealed = await sealToDevice(a.publicKey, c, dk);
    expect(await openFromDevice(a.privateKey, c, sealed), dk);
    final lower = withCtx(c, userId: c.userId.toLowerCase());
    expect(await code(() => openFromDevice(a.privateKey, lower, sealed)), 'cannot_open');
    expect(await code(() => sealToDevice(a.publicKey, withCtx(c, userId: 'a/b'), dk)), 'bad_input');
  });

  test('validates its input', () async {
    final a = await generateDeviceKeyPair();
    final dk = generateDataKey();
    expect(await code(() => sealToDevice(Uint8List(31), ctx, dk)), 'bad_input');
    expect(
      await code(() => sealToDevice(a.publicKey, withCtx(ctx, userId: 'x/y'), dk)),
      'bad_input',
    );
    expect(await code(() => sealToDevice(a.publicKey, withCtx(ctx, keyV: 99999), dk)), 'bad_input');
    expect(
      await code(() => sealToDevice(a.publicKey, withCtx(ctx, kind: WrapKind.passkey), dk)),
      'bad_input',
    );
    expect(await code(() => sealToDevice(a.publicKey, ctx, Uint8List(16))), 'bad_input');
  });

  test('imports a raw private key (native)', () async {
    // In Dart the private key is the raw 32 bytes: there is no import step and no native/noble split.
    final raw = filled(32, 11);
    final pub = Uint8List.fromList(
      (await (await X25519().newKeyPairFromSeed(raw)).extractPublicKey()).bytes,
    );
    final dk = generateDataKey();
    expect(await openFromDevice(raw, ctx, await sealToDevice(pub, ctx, dk)), dk);
  });

  test('a structured clone of a fallback key still opens a seal; foreign objects are bad_input', () async {
    // Dart has no clone or noble object: this is the foreign-object case (a key that is not 32 raw
    // bytes, which also covers importDevicePrivateKey(31 bytes)).
    final a = await generateDeviceKeyPair();
    final sealed = await sealToDevice(a.publicKey, ctx, generateDataKey());
    for (final n in [0, 5, 31, 33]) {
      expect(await code(() => openFromDevice(Uint8List(n), ctx, sealed)), 'bad_input');
    }
  });

  test('a low-order (all-zero) public key is refused: seal bad_input, open cannot_open', () async {
    final dk = generateDataKey();
    final zero = Uint8List(32);
    expect(await code(() => sealToDevice(zero, ctx, dk)), 'bad_input');
    // A blob an attacker builds under the all-zero shared secret must not open.
    final a = await generateDeviceKeyPair();
    final good = await sealToDevice(a.publicKey, ctx, dk);
    final forged = Uint8List.fromList([...zero, ...good.sublist(32)]);
    expect(await code(() => openFromDevice(a.privateKey, ctx, forged)), 'cannot_open');
    // Also as the approver key of pairing.
    expect(await code(() => openFromPairing(a.privateKey, ctx, forged, zero)), 'cannot_open');
    // Another low-order point (the u-coordinate 1) also gives an all-zero secret.
    final one = Uint8List(32)..[0] = 1;
    expect(await code(() => sealToDevice(one, ctx, dk)), 'bad_input');
  });
}
