import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/crypto.dart';

/// The shared vectors of packages/crypto (`test-vectors.json`): the Dart port must match the
/// TypeScript one byte for byte. Twin of packages/crypto/test/vectors.test.ts.
void main() {
  final vectors = jsonDecode(
    File('../../packages/crypto/test-vectors.json').readAsStringSync(),
  ) as Map<String, Object?>;

  List<Map<String, Object?>> section(String name) =>
      (vectors[name]! as List).cast<Map<String, Object?>>();
  Uint8List b(Object? text) => fromBase64Url(text! as String);

  RecordContext recordCtx(Object? raw) {
    final m = (raw! as Map).cast<String, Object?>();
    return RecordContext(
      userId: m['userId']! as String,
      type: RecordType.values.byName(m['type']! as String),
      id: m['id']! as String,
      keyV: m['keyV']! as int,
    );
  }

  WrapContext wrapCtx(Object? raw) {
    final m = (raw! as Map).cast<String, Object?>();
    return WrapContext(
      kind: WrapKind.values.byName(m['kind']! as String),
      userId: m['userId']! as String,
      keyV: m['keyV']! as int,
    );
  }

  LinkContext linkCtx(Object? raw) {
    final m = (raw! as Map).cast<String, Object?>();
    return LinkContext(userId: m['userId']! as String, keyV: m['keyV']! as int);
  }

  test('has the documented shape and coverage', () {
    expect(vectors['_about'], matches(RegExp('never edit', caseSensitive: false)));
    expect(section('records').length, greaterThanOrEqualTo(3));
    expect(section('devices').length, greaterThanOrEqualTo(2));
    expect(section('rejects').length, greaterThanOrEqualTo(4));
  });

  test('records: seal with the fixed nonce is exact, open gives the value', () async {
    for (final r in section('records')) {
      final keys = await deriveRecordKeys(b(r['dataKey']));
      final ctx = recordCtx(r['ctx']);
      final body = await sealRecord(keys, ctx, r['value'], nonce: b(r['nonce']));
      expect(toBase64Url(body), r['body']);
      expect(await openRecord(keys, ctx, b(r['body'])), r['value']);
      final dedupe = (r['dedupe']! as Map).cast<String, Object?>();
      expect(await dedupeTag(keys, dedupe['text']! as String), dedupe['tag']);
    }
  });

  test('wraps: wrap with the fixed nonce is exact, unwrap gives the data key', () async {
    for (final w in section('wraps')) {
      final ctx = wrapCtx(w['ctx']);
      final wrapped = await wrapDataKey(b(w['secret']), ctx, b(w['dataKey']), nonce: b(w['nonce']));
      expect(toBase64Url(wrapped), w['wrapped']);
      expect(await unwrapDataKey(b(w['secret']), ctx, b(w['wrapped'])), b(w['dataKey']));
    }
  });

  test('recovery: text and secret match both ways', () {
    for (final r in section('recovery')) {
      expect(parseRecoveryKey(r['text']! as String), b(r['secret']));
      expect(formatRecoveryKey(b(r['secret'])), r['text']);
    }
  });

  test('devices: the sealed blob opens to the data key', () async {
    for (final d in section('devices')) {
      expect(
        await openFromDevice(b(d['privateKey']), wrapCtx(d['ctx']), b(d['sealed'])),
        b(d['dataKey']),
      );
    }
  });

  test('pairing: numbers match from either side', () async {
    for (final p in section('pairing')) {
      expect(await pairingNumber(b(p['a']), b(p['b'])), p['number']);
      expect(await pairingNumber(b(p['b']), b(p['a'])), p['number']);
    }
  });

  test('approvals: commitment, number, and the sealed blob open under the approver key', () async {
    expect(section('approvals').length, greaterThanOrEqualTo(2));
    for (final p in section('approvals')) {
      expect(toBase64Url(await pairingCommitment(b(p['newPublicKey']))), p['commitment']);
      expect(await pairingNumber(b(p['newPublicKey']), b(p['approverPublicKey'])), p['number']);
      expect(
        await openFromPairing(
          b(p['newPrivateKey']),
          wrapCtx(p['ctx']),
          b(p['sealed']),
          b(p['approverPublicKey']),
        ),
        b(p['dataKey']),
      );
    }
  });

  test('attestations: the HMAC is exact and verifies', () async {
    expect(section('attestations').length, greaterThanOrEqualTo(2));
    for (final a in section('attestations')) {
      final input = DeviceAttestationInput(
        userId: a['userId']! as String,
        wrapId: a['wrapId']! as String,
        publicKey: b(a['publicKey']),
      );
      expect(toBase64Url(await deviceAttestation(b(a['dataKey']), input)), a['attestation']);
      expect(await verifyDeviceAttestation(b(a['dataKey']), input, b(a['attestation'])), isTrue);
    }
  });

  test('links: sealKeyLink is exact and openKeyLink returns oldKey', () async {
    expect(section('links').length, greaterThanOrEqualTo(2));
    for (final l in section('links')) {
      final ctx = linkCtx(l['ctx']);
      final link = await sealKeyLink(b(l['newKey']), b(l['oldKey']), ctx, nonce: b(l['nonce']));
      expect(toBase64Url(link), l['link']);
      expect(await openKeyLink(b(l['newKey']), ctx, b(l['link'])), b(l['oldKey']));
    }
  });

  test('rejects: every input is refused with the expected code', () async {
    for (final r in section('rejects')) {
      var got = 'none';
      try {
        switch (r['op']) {
          case 'sealRecord':
            final keys = await deriveRecordKeys(b(r['dataKey']));
            await sealRecord(keys, recordCtx(r['ctx']), r['value'], nonce: b(r['nonce']));
          case 'wrapDataKey':
            await wrapDataKey(
              b(r['secret']),
              wrapCtx(r['ctx']),
              b(r['dataKey']),
              nonce: b(r['nonce']),
            );
          case 'openFromPairing':
            await openFromPairing(
              b(r['privateKey']),
              wrapCtx(r['ctx']),
              b(r['sealed']),
              b(r['approverKey']),
            );
          case 'openKeyLink':
            await openKeyLink(b(r['newKey']), linkCtx(r['ctx']), b(r['link']));
          case 'parseRecoveryKey':
            parseRecoveryKey(r['text']! as String);
          default:
            throw StateError('unknown op ${r['op']}');
        }
      } on CryptoError catch (e) {
        got = e.code;
      } on Object catch (e) {
        got = 'other: $e';
      }
      expect(got, r['code'], reason: r['name']! as String);
    }
  });
}
