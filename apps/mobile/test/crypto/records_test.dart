import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/crypto.dart';

import 'helpers.dart';

const u1 = '0194f3a2-7b1c-7d2e-9a4f-3c5b6d7e8f90';
const u2 = '0194f3a2-7b1c-7d2e-9a4f-3c5b6d7e8f91';
const r1 = '11111111-2222-4333-8444-555555555555';
const r2 = '11111111-2222-4333-8444-555555555556';
const ctx = RecordContext(userId: u1, type: RecordType.transaction, id: r1, keyV: 1);
const value = {'s': 1, 'name': 'Almuerzo', 'amount': 1800000, 'note': 'piña colada ñandú'};

Future<RecordKeys> keys([int fill = 7]) => deriveRecordKeys(filled(32, fill));

RecordContext withCtx({String? userId, RecordType? type, String? id, int? keyV}) => RecordContext(
  userId: userId ?? ctx.userId,
  type: type ?? ctx.type,
  id: id ?? ctx.id,
  keyV: keyV ?? ctx.keyV,
);

void main() {
  test('generates 32 random bytes', () {
    final a = generateDataKey();
    expect(a, hasLength(32));
    expect(a, isNot(generateDataKey()));
  });

  test('seal then open returns the same value', () async {
    final k = await keys();
    expect(await openRecord(k, ctx, await sealRecord(k, ctx, value)), value);
  });

  test('body length is 12 + 16 + a multiple of 64', () async {
    final k = await keys();
    for (final n in [1, 63, 64, 65]) {
      // The number 5 is 1 byte of JSON; a string of n-2 chars is n bytes.
      final body = await sealRecord(k, ctx, n == 1 ? 5 : 'a' * (n - 2));
      final padded = ((n + 63) ~/ 64) * 64;
      expect(body.length, 12 + padded + 16);
    }
  });

  test('two seals of the same value differ', () async {
    final k = await keys();
    expect(await sealRecord(k, ctx, value), isNot(await sealRecord(k, ctx, value)));
  });

  test('uses the given nonce as the first 12 bytes', () async {
    final k = await keys();
    final nonce = filled(12, 9);
    expect((await sealRecord(k, ctx, value, nonce: nonce)).sublist(0, 12), nonce);
  });

  test('swapped associated data fails', () async {
    final k = await keys();
    final body = await sealRecord(k, ctx, value);
    final others = [
      withCtx(userId: u2),
      withCtx(type: RecordType.budget),
      withCtx(id: r2),
      withCtx(keyV: 2),
    ];
    for (final other in others) {
      expect(await code(() => openRecord(k, other, body)), 'cannot_open');
    }
  });

  test('a flipped byte, a truncated body or another key fails', () async {
    final k = await keys();
    final body = await sealRecord(k, ctx, value);
    final bad = [flipped(body, 20), body.sublist(0, body.length - 1), body.sublist(0, 5)];
    for (final b in bad) {
      expect(await code(() => openRecord(k, ctx, b)), 'cannot_open');
    }
    expect(await code(() async => openRecord(await keys(8), ctx, body)), 'cannot_open');
  });

  test('dedupe tags are stable and key-dependent', () async {
    final a = await keys(1);
    final b = await keys(2);
    final t = await dedupeTag(a, 'revolut|1800|2026-11-08');
    expect(t, await dedupeTag(a, 'revolut|1800|2026-11-08'));
    expect(t, isNot(await dedupeTag(b, 'revolut|1800|2026-11-08')));
    expect(t, isNot(await dedupeTag(a, 'other')));
    expect(t, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
  });

  test('round-trips trailing spaces and multibyte text', () async {
    final k = await keys();
    const v = {'note': 'ñ   '};
    expect(await openRecord(k, ctx, await sealRecord(k, ctx, v)), v);
  });

  test('rejects an upper-case record id', () async {
    final k = await keys();
    final c = withCtx(id: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'.toUpperCase());
    expect(await code(() => sealRecord(k, c, value)), 'bad_input');
  });

  test('takes a Better Auth shaped user id as is, case included', () async {
    final k = await keys();
    final c = withCtx(userId: 'kX3mQ9vTz2LpR8wYb5NcHd7JfA1sUe_-');
    final body = await sealRecord(k, c, value);
    expect(await openRecord(k, c, body), value);
    final lower = withCtx(userId: c.userId.toLowerCase());
    expect(await code(() => openRecord(k, lower, body)), 'cannot_open');
  });

  test('rejects a user id with a slash, empty or longer than 128', () async {
    final k = await keys();
    for (final userId in ['a/b', '', 'a' * 129, 'a b', 'ñ']) {
      expect(await code(() => sealRecord(k, withCtx(userId: userId), value)), 'bad_input');
    }
    final c = withCtx(userId: 'a' * 128);
    expect(await openRecord(k, c, await sealRecord(k, c, value)), value);
  });

  test('rejects bad input with bad_input', () async {
    final k = await keys();
    final body = await sealRecord(k, ctx, value);
    // keyV is an int in Dart and the record type an enum: a fractional or NaN keyV and an unknown
    // type cannot be written, so those TS cases have no Dart twin.
    final badCtx = [
      withCtx(userId: 'u/1'),
      withCtx(id: 'r1'),
      withCtx(id: '$r1/x'),
      withCtx(keyV: -1),
      withCtx(keyV: 32768),
    ];
    for (final c in badCtx) {
      expect(await code(() => sealRecord(k, c, value)), 'bad_input');
      expect(await code(() => openRecord(k, c, body)), 'bad_input');
    }
    for (final keyV in [0, 32767]) {
      final c = withCtx(keyV: keyV);
      expect(await openRecord(k, c, await sealRecord(k, c, value)), value);
    }
    Future<Uint8List> nonce(int n) => sealRecord(k, ctx, value, nonce: Uint8List(n));
    expect(await code(() => nonce(11)), 'bad_input');
    expect(await code(() => nonce(13)), 'bad_input');
    // A value that is not JSON (a function; TS: undefined or a function).
    expect(await code(() => sealRecord(k, ctx, () => 1)), 'bad_input');
  });

  test('every record type has its wire name', () {
    expect(RecordType.values.map((t) => t.name), [
      'transaction',
      'category',
      'budget',
      'recurrence',
      'merchant',
      'settings',
      'account',
    ]);
  });
}
