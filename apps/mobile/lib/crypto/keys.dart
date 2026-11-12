import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'errors.dart';
import 'validate.dart';

/// Twin of packages/crypto/src/keys.ts.
class RecordKeys {
  const RecordKeys({required this.record, required this.dedupe});

  /// The AES-256-GCM key of the records.
  final SecretKey record;

  /// The HMAC-SHA-256 key of the dedupe tags.
  final SecretKey dedupe;
}

Uint8List generateDataKey() => randomBytes(32);

/// HKDF-SHA-256 with an empty salt (RFC 5869: a salt of zeros) from [secret] to 32 bytes, under
/// the fixed [info] string.
Future<SecretKey> hkdfKey(Uint8List secret, String info) {
  return Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  ).deriveKey(secretKey: SecretKey(secret), nonce: const <int>[], info: utf8.encode(info));
}

/// Both keys come from the data key by HKDF-SHA-256 with an empty salt and a fixed info.
Future<RecordKeys> deriveRecordKeys(Uint8List dataKey) async {
  if (dataKey.length != 32) throw const CryptoError('bad_input', 'data key must be 32 bytes');
  return RecordKeys(
    record: await hkdfKey(dataKey, 'wambito/v1/record'),
    dedupe: await hkdfKey(dataKey, 'wambito/v1/dedupe'),
  );
}
