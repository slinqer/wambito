import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/crypto.dart';

import 'helpers.dart';

final dataKey = filled(32, 5);
const wrapId = '0194f3a2-8c00-7000-8000-000000000001';
DeviceAttestationInput input({String? userId, String? wrap, Uint8List? publicKey}) =>
    DeviceAttestationInput(
      userId: userId ?? 'userOne',
      wrapId: wrap ?? wrapId,
      publicKey: publicKey ?? filled(32, 3),
    );

void main() {
  test('is 32 bytes and verifies', () async {
    final att = await deviceAttestation(dataKey, input());
    expect(att, hasLength(32));
    expect(await verifyDeviceAttestation(dataKey, input(), att), isTrue);
  });

  test('matches HMAC with the HKDF attest key', () async {
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(dataKey),
      nonce: const <int>[],
      info: utf8.encode('wambito/v1/device-attest'),
    );
    final msg = [...utf8.encode('userOne'), 0, ...utf8.encode(wrapId), 0, ...filled(32, 3)];
    final expected = (await Hmac.sha256().calculateMac(msg, secretKey: key)).bytes;
    expect(await deviceAttestation(dataKey, input()), expected);
  });

  test('fails for another key, user, wrap, public key or length', () async {
    final att = await deviceAttestation(dataKey, input());
    expect(await verifyDeviceAttestation(filled(32, 6), input(), att), isFalse);
    expect(await verifyDeviceAttestation(dataKey, input(userId: 'userTwo'), att), isFalse);
    expect(
      await verifyDeviceAttestation(
        dataKey,
        input(wrap: '0194f3a2-8c00-7000-8000-000000000002'),
        att,
      ),
      isFalse,
    );
    expect(await verifyDeviceAttestation(dataKey, input(publicKey: filled(32, 4)), att), isFalse);
    expect(await verifyDeviceAttestation(dataKey, input(), att.sublist(0, 31)), isFalse);
    expect(await verifyDeviceAttestation(dataKey, input(), Uint8List(33)), isFalse);
  });

  test('validates its inputs', () async {
    expect(await code(() => deviceAttestation(dataKey, input(userId: 'a/b'))), 'bad_input');
    expect(
      await code(() => deviceAttestation(dataKey, input(wrap: wrapId.toUpperCase()))),
      'bad_input',
    );
    expect(
      await code(() => deviceAttestation(dataKey, input(publicKey: Uint8List(31)))),
      'bad_input',
    );
    expect(await code(() => deviceAttestation(Uint8List(31), input())), 'bad_input');
  });
}
