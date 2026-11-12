import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';
import 'keys.dart';
import 'validate.dart';

/// Twin of packages/crypto/src/attest.ts.
class DeviceAttestationInput {
  const DeviceAttestationInput({
    required this.userId,
    required this.wrapId,
    required this.publicKey,
  });

  final String userId;
  final String wrapId;
  final Uint8List publicKey;
}

/// HMAC-SHA-256 under HKDF-SHA-256(DK, empty salt, "wambito/v1/device-attest") of
/// utf8(userId) || 0x00 || utf8(wrapId) || 0x00 || publicKey. 32 bytes.
Future<Uint8List> deviceAttestation(Uint8List dataKey, DeviceAttestationInput input) async {
  assertBytes(dataKey, 32, 'data key');
  assertUserId(input.userId);
  assertUuid(input.wrapId, 'wrapId');
  assertBytes(input.publicKey, 32, 'public key');
  final key = await hkdfKey(dataKey, 'wambito/v1/device-attest');
  final msg = <int>[
    ...utf8.encode(input.userId),
    0,
    ...utf8.encode(input.wrapId),
    0,
    ...input.publicKey,
  ];
  final mac = await Hmac.sha256().calculateMac(msg, secretKey: key);
  return Uint8List.fromList(mac.bytes);
}

Future<bool> verifyDeviceAttestation(
  Uint8List dataKey,
  DeviceAttestationInput input,
  Uint8List attestation,
) async {
  if (attestation.length != 32) return false;
  return timingSafeEqual(await deviceAttestation(dataKey, input), attestation);
}
