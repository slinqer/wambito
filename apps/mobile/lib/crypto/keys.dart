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

/// HKDF-SHA-256 with an empty salt from [secret] to 32 bytes, under the fixed [info] string.
///
/// The salt is passed as 32 zero bytes, which RFC 5869 makes the same as an empty one (the bytes of
/// packages/crypto do not change): cryptography_flutter's Android HMAC refuses an empty key.
Future<SecretKey> hkdfKey(Uint8List secret, String info) {
  return Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  ).deriveKey(secretKey: SecretKey(secret), nonce: _zeroSalt, info: utf8.encode(info));
}

final Uint8List _zeroSalt = Uint8List(32);

/// Both keys come from the data key by HKDF-SHA-256 with an empty salt and a fixed info.
Future<RecordKeys> deriveRecordKeys(Uint8List dataKey) async {
  if (dataKey.length != 32) throw const CryptoError('bad_input', 'data key must be 32 bytes');
  return RecordKeys(
    record: await hkdfKey(dataKey, 'wambito/v1/record'),
    dedupe: await hkdfKey(dataKey, 'wambito/v1/dedupe'),
  );
}
