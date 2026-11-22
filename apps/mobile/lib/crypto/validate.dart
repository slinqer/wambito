import 'dart:math';
import 'dart:typed_data';

import 'errors.dart';

/// Twin of packages/crypto/src/validate.ts: every check throws `bad_input`.

/// Only lower-case canonical UUIDs: they go byte for byte into the associated data.
final RegExp _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

/// The account's exact id (Better Auth ids: letters, digits, `-`, `_`; case is significant). No `/`,
/// so the associated data stays unambiguous.
final RegExp _userId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

const nonceBytes = 12;

void assertUuid(String value, String what) {
  if (!_uuid.hasMatch(value)) throw CryptoError('bad_input', '$what must be a lower-case UUID');
}

void assertUserId(String value) {
  if (!_userId.hasMatch(value)) {
    throw const CryptoError('bad_input', "userId must be 1 to 128 letters, digits, '-' or '_'");
  }
}

void assertKeyV(int value) {
  if (value < 0 || value > 32767) {
    throw const CryptoError('bad_input', 'keyV must be an integer from 0 to 32767');
  }
}

void assertNonce(Uint8List nonce) {
  if (nonce.length != nonceBytes) throw const CryptoError('bad_input', 'nonce must be 12 bytes');
}

void assertBytes(Uint8List value, int length, String what) {
  if (value.length != length) throw CryptoError('bad_input', '$what must be $length bytes');
}

final Random _random = Random.secure();

Uint8List randomBytes(int length) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) _random.nextInt(256)]);

Uint8List randomNonce() => randomBytes(nonceBytes);
