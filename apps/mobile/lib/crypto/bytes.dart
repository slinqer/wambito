import 'dart:convert';
import 'dart:typed_data';

import 'errors.dart';

/// Twin of packages/crypto/src/bytes.ts: base64url without padding.
String toBase64Url(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');

final RegExp _base64UrlChars = RegExp(r'^[A-Za-z0-9_-]*$');

Uint8List fromBase64Url(String text) {
  if (!_base64UrlChars.hasMatch(text) || text.length % 4 == 1) {
    throw const CryptoError('bad_input', 'not base64url');
  }
  return Uint8List.fromList(base64Url.decode(base64Url.normalize(text)));
}

/// Constant-time equality for byte strings (false at once only when the lengths differ).
bool timingSafeEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
