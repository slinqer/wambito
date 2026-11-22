import 'dart:typed_data';

import 'package:wambito/crypto/crypto.dart';

/// The code of the [CryptoError] a call throws, 'none' when it returns, 'other' for anything else.
Future<String> code(Future<Object?> Function() call) async {
  try {
    await call();
  } on CryptoError catch (e) {
    return e.code;
  } on Object {
    return 'other';
  }
  return 'none';
}

String codeSync(Object? Function() call) {
  try {
    call();
  } on CryptoError catch (e) {
    return e.code;
  } on Object {
    return 'other';
  }
  return 'none';
}

Uint8List filled(int length, int value) => Uint8List(length)..fillRange(0, length, value);

/// A copy of [bytes] with the low bit of byte [i] flipped.
Uint8List flipped(Uint8List bytes, int i) => Uint8List.fromList(bytes)..[i] ^= 1;
