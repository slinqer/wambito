import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/crypto.dart';

import 'helpers.dart';

Uint8List random32() => generateDataKey();

void main() {
  group('pairing', () {
    test('codes are 8 Crockford characters', () {
      final seen = <String>{};
      for (var i = 0; i < 200; i++) {
        final c = pairingCode();
        expect(c, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{8}$')));
        seen.add(c);
      }
      expect(seen.length, greaterThan(190));
    });

    test('the number is the same from both sides, 6 digits', () async {
      final a = random32();
      final b = random32();
      final n = await pairingNumber(a, b);
      expect(n, await pairingNumber(b, a));
      expect(n, matches(RegExp(r'^\d{6}$')));
    });

    test('keeps leading zeros and depends on both keys', () async {
      final seen = <String>{};
      var zero = 0;
      for (var i = 0; i < 400; i++) {
        final n = await pairingNumber(random32(), random32());
        expect(n, hasLength(6));
        if (n.startsWith('0')) zero++;
        seen.add(n);
      }
      expect(zero, greaterThan(0));
      expect(seen.length, greaterThan(300));
      final a = filled(32, 1);
      expect(await pairingNumber(a, filled(32, 2)), isNot(await pairingNumber(a, filled(32, 3))));
    });
  });

  group('pairingCommitment', () {
    test('is SHA-256 of the label and the key', () async {
      final key = filled(32, 7);
      final expected = await Sha256().hash([...utf8.encode('wambito/v1/pairing-commit'), ...key]);
      expect(await pairingCommitment(key), expected.bytes);
    });

    test('is 32 bytes, depends on the key and rejects other lengths', () async {
      final a = await pairingCommitment(filled(32, 1));
      expect(a, hasLength(32));
      expect(a, isNot(await pairingCommitment(filled(32, 2))));
      expect(await code(() => pairingCommitment(Uint8List(31))), 'bad_input');
    });
  });

  group('openFromPairing', () {
    const ctx = WrapContext(kind: WrapKind.device, userId: 'userOne', keyV: 2);
    final dataKey = filled(32, 9);

    test("opens a seal made with the approver's ephemeral key", () async {
      final n = await generateDeviceKeyPair();
      final a = await generateDeviceKeyPair();
      final sealed = await sealToDevice(n.publicKey, ctx, dataKey, ephemeral: a);
      expect(sealed.sublist(0, 32), a.publicKey);
      expect(await openFromPairing(n.privateKey, ctx, sealed, a.publicKey), dataKey);
    });

    test('refuses a blob whose ephemeral key is not the approver key', () async {
      final n = await generateDeviceKeyPair();
      final a = await generateDeviceKeyPair();
      final other = await generateDeviceKeyPair();
      final sealed = await sealToDevice(n.publicKey, ctx, dataKey, ephemeral: other);
      expect(
        await code(() => openFromPairing(n.privateKey, ctx, sealed, a.publicKey)),
        'cannot_open',
      );
      // openFromDevice would have accepted it
      expect(await openFromDevice(n.privateKey, ctx, sealed), dataKey);
    });

    // "refuses a sealed blob that is not bytes" has no Dart twin: the type is Uint8List.

    test('sealToDevice without an ephemeral still makes a fresh key each time', () async {
      final n = await generateDeviceKeyPair();
      final s1 = await sealToDevice(n.publicKey, ctx, dataKey);
      final s2 = await sealToDevice(n.publicKey, ctx, dataKey);
      expect(s1.sublist(0, 32), isNot(s2.sublist(0, 32)));
    });
  });
}
