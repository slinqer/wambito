import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'recovery.dart';
import 'validate.dart';

/// Twin of packages/crypto/src/pairing.ts.

/// 8 Crockford base32 characters the new device shows and the signed-in device types in.
String pairingCode() {
  final bytes = randomBytes(8);
  // 256 is a multiple of 32: no bias.
  return [for (final b in bytes) crockford[b & 31]].join();
}

int _compare(Uint8List a, Uint8List b) {
  for (var i = 0; i < a.length; i++) {
    final d = a[i] - b[i];
    if (d != 0) return d;
  }
  return 0;
}

Future<Uint8List> _sha256(List<int> input) async =>
    Uint8List.fromList((await Sha256().hash(input)).bytes);

/// Six digits both devices show, from SHA-256("wambito/v1/pairing" || the two public keys sorted),
/// so the number is the same from either side and a swapped key shows a different one.
Future<String> pairingNumber(Uint8List a, Uint8List b) async {
  assertBytes(a, 32, 'public key');
  assertBytes(b, 32, 'public key');
  final sorted = _compare(a, b) <= 0 ? [a, b] : [b, a];
  final hash = await _sha256([...utf8.encode('wambito/v1/pairing'), ...sorted[0], ...sorted[1]]);
  final n = ByteData.sublistView(hash).getUint32(0) % 1000000;
  return n.toString().padLeft(6, '0');
}

/// The new device's commitment: SHA-256("wambito/v1/pairing-commit" || its public key). It sends
/// this first and reveals the key last, so the server cannot choose the approver key after seeing it.
Future<Uint8List> pairingCommitment(Uint8List publicKey) {
  assertBytes(publicKey, 32, 'public key');
  return _sha256([...utf8.encode('wambito/v1/pairing-commit'), ...publicKey]);
}
