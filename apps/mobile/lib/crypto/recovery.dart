import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'errors.dart';
import 'keys.dart';
import 'validate.dart';

/// Twin of packages/crypto/src/recovery.ts.

/// Crockford base32 (no I, L, O, U).
const crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const _dataChars = 26;

Uint8List newRecoverySecret() => randomBytes(16);

const recoveryLookupInfo = 'wambito/v1/recovery/lookup';
const recoveryAuthInfo = 'wambito/v1/recovery/auth';

/// What the server stores (as SHA-256 hashes) to let a recovery key sign in without the data key.
class RecoveryVerifier {
  const RecoveryVerifier({required this.lookup, required this.auth});

  /// 16 bytes: finds the verifier row.
  final Uint8List lookup;

  /// 32 bytes: proves the person holds the recovery key.
  final Uint8List auth;
}

/// HKDF-SHA-256 (empty salt) of the 16-byte recovery secret under two infos, different from the
/// wrap info, so what the server sees never opens the recovery wrap.
Future<RecoveryVerifier> recoveryVerifier(Uint8List secret) async {
  assertBytes(secret, 16, 'recovery secret');
  return RecoveryVerifier(
    lookup: await hkdfBytes(secret, recoveryLookupInfo, 16),
    auth: await hkdfBytes(secret, recoveryAuthInfo, 32),
  );
}

/// SHA-256 of verifier bytes: what the server stores as `lookup_hash` and `auth_hash`.
Future<Uint8List> verifierHash(Uint8List bytes) async =>
    Uint8List.fromList((await Sha256().hash(bytes)).bytes);

/// Luhn mod N check character (N = 32, code points = index in the Crockford alphabet) over the 26
/// data characters. It is always alphanumeric, catches every single-character error and almost
/// every swap of two adjacent characters.
String _luhnCheck(String data) {
  var factor = 2;
  var sum = 0;
  for (var i = data.length - 1; i >= 0; i--) {
    final addend = factor * crockford.indexOf(data[i]);
    factor = factor == 2 ? 1 : 2;
    sum += addend ~/ 32 + addend % 32;
  }
  return crockford[(32 - (sum % 32)) % 32];
}

/// 128 bits as 26 base32 characters (the last one carries 3 data bits and 2 zero bits) plus a
/// Luhn mod 32 check character, in groups of four.
String formatRecoveryKey(Uint8List secret) {
  assertBytes(secret, 16, 'recovery secret');
  var value = BigInt.zero;
  for (final b in secret) {
    value = (value << 8) | BigInt.from(b);
  }
  final padded = value << 2; // 130 bits
  final text = StringBuffer();
  for (var i = _dataChars - 1; i >= 0; i--) {
    text.write(crockford[((padded >> (i * 5)) & BigInt.from(31)).toInt()]);
  }
  final data = text.toString();
  final all = data + _luhnCheck(data);
  return [
    for (var i = 0; i < all.length; i += 4)
      all.substring(i, i + 4 > all.length ? all.length : i + 4),
  ].join('-');
}

Uint8List parseRecoveryKey(String input) {
  const bad = CryptoError('bad_recovery_key', 'that recovery key is not valid');
  final text = input
      .replaceAll(RegExp(r'[\s-]+'), '')
      .toUpperCase()
      .replaceAll(RegExp('[IL]'), '1')
      .replaceAll('O', '0');
  if (text.length != _dataChars + 1) throw bad;
  var padded = BigInt.zero;
  for (var i = 0; i < _dataChars; i++) {
    final v = crockford.indexOf(text[i]);
    if (v < 0) throw bad;
    padded = (padded << 5) | BigInt.from(v);
  }
  if ((padded & BigInt.from(3)) != BigInt.zero) throw bad;
  final value = padded >> 2;
  if (_luhnCheck(text.substring(0, _dataChars)) != text[_dataChars]) throw bad;
  final out = Uint8List(16);
  for (var i = 15; i >= 0; i--) {
    out[i] = ((value >> ((15 - i) * 8)) & BigInt.from(255)).toInt();
  }
  return out;
}
