import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/crypto.dart';

import 'helpers.dart';

const u1 = '0194f3a2-7b1c-7d2e-9a4f-3c5b6d7e8f90';
const u2 = '0194f3a2-7b1c-7d2e-9a4f-3c5b6d7e8f91';
const kinds = [WrapKind.passkey, WrapKind.recovery, WrapKind.assistant];
final secret = filled(32, 3);
Uint8List secretFor(WrapKind kind) => filled(kind == WrapKind.recovery ? 16 : 32, 3);

WrapContext withCtx(WrapContext c, {WrapKind? kind, String? userId, int? keyV}) =>
    WrapContext(kind: kind ?? c.kind, userId: userId ?? c.userId, keyV: keyV ?? c.keyV);

void main() {
  test('PRF_SALT is SHA-256 of the fixed string', () async {
    final h = await Sha256().hash(utf8.encode('wambito/v1/prf'));
    expect(prfSalt, hasLength(32));
    expect(prfSalt, h.bytes);
  });

  test('round trips per kind with the layout nonce || ciphertext+tag', () async {
    for (final kind in kinds) {
      final ctx = WrapContext(kind: kind, userId: u1, keyV: 1);
      final dk = generateDataKey();
      final wrapped = await wrapDataKey(secretFor(kind), ctx, dk);
      expect(wrapped, hasLength(12 + 32 + 16));
      expect(await unwrapDataKey(secretFor(kind), ctx, wrapped), dk);
    }
  });

  test('uses the given nonce', () async {
    final nonce = filled(12, 5);
    final w = await wrapDataKey(
      secretFor(WrapKind.recovery),
      const WrapContext(kind: WrapKind.recovery, userId: u1, keyV: 1),
      generateDataKey(),
      nonce: nonce,
    );
    expect(w.sublist(0, 12), nonce);
  });

  test('wrong secret, user, key version or kind cannot open', () async {
    const ctx = WrapContext(kind: WrapKind.passkey, userId: u1, keyV: 1);
    final w = await wrapDataKey(secret, ctx, generateDataKey());
    expect(await code(() => unwrapDataKey(filled(32, 4), ctx, w)), 'cannot_open');
    expect(await code(() => unwrapDataKey(secret, withCtx(ctx, userId: u2), w)), 'cannot_open');
    expect(await code(() => unwrapDataKey(secret, withCtx(ctx, keyV: 2), w)), 'cannot_open');
    expect(
      await code(() => unwrapDataKey(secret, withCtx(ctx, kind: WrapKind.assistant), w)),
      'cannot_open',
    );
    expect(await code(() => unwrapDataKey(secret, ctx, flipped(w, 20))), 'cannot_open');
    expect(await code(() => unwrapDataKey(secret, ctx, w.sublist(0, 10))), 'cannot_open');
  });

  test('takes a Better Auth shaped user id; case is significant; no slash', () async {
    const ctx = WrapContext(
      kind: WrapKind.passkey,
      userId: 'kX3mQ9vTz2LpR8wYb5NcHd7JfA1sUe_-',
      keyV: 1,
    );
    final dk = generateDataKey();
    final w = await wrapDataKey(secret, ctx, dk);
    expect(await unwrapDataKey(secret, ctx, w), dk);
    final lower = withCtx(ctx, userId: ctx.userId.toLowerCase());
    expect(await code(() => unwrapDataKey(secret, lower, w)), 'cannot_open');
    for (final userId in ['a/b', '', 'a' * 129]) {
      expect(await code(() => wrapDataKey(secret, withCtx(ctx, userId: userId), dk)), 'bad_input');
    }
  });

  test('validates its input', () async {
    const ctx = WrapContext(kind: WrapKind.passkey, userId: u1, keyV: 1);
    final dk = generateDataKey();
    final w = await wrapDataKey(secret, ctx, dk);
    // keyV is an int and the kind an enum in Dart: 0.5 and an unknown kind cannot be written.
    final bad = [
      withCtx(ctx, userId: 'no pe'),
      withCtx(ctx, keyV: -1),
      withCtx(ctx, keyV: 32768),
      withCtx(ctx, kind: WrapKind.device),
    ];
    for (final c in bad) {
      expect(await code(() => wrapDataKey(secret, c, dk)), 'bad_input');
      expect(await code(() => unwrapDataKey(secret, c, w)), 'bad_input');
    }
    expect(await code(() => wrapDataKey(secret, ctx, Uint8List(31))), 'bad_input');
    expect(await code(() => wrapDataKey(Uint8List(0), ctx, dk)), 'bad_input');
    expect(await code(() => wrapDataKey(Uint8List(16), ctx, dk)), 'bad_input');
    final rec = withCtx(ctx, kind: WrapKind.recovery);
    expect(await code(() => wrapDataKey(Uint8List(32), rec, dk)), 'bad_input');
    expect(await code(() => unwrapDataKey(Uint8List(32), rec, w)), 'bad_input');
    expect(await code(() => wrapDataKey(Uint8List(16), rec, dk)), 'none');
    expect(
      await code(() => wrapDataKey(Uint8List(31), withCtx(ctx, kind: WrapKind.assistant), dk)),
      'bad_input',
    );
    expect(await code(() => wrapDataKey(secret, ctx, dk, nonce: Uint8List(8))), 'bad_input');
  });
}
