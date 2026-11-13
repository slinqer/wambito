import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/crypto.dart';

import 'helpers.dart';

void main() {
  test('base64url has no padding and round trips', () {
    for (var n = 0; n < 6; n++) {
      final bytes = Uint8List.fromList([for (var i = 0; i < n; i++) 250 - i]);
      final text = toBase64Url(bytes);
      expect(text, isNot(contains('=')));
      expect(text, isNot(matches(RegExp(r'[+/]'))));
      expect(fromBase64Url(text), bytes);
    }
    expect(toBase64Url(Uint8List.fromList([0xfb, 0xff])), '-_8');
  });

  test('fromBase64Url refuses foreign characters, padding and a length of 1 mod 4', () {
    for (final text in ['a b', 'ab==', 'a+b/', 'abcde', 'ñ']) {
      expect(codeSync(() => fromBase64Url(text)), 'bad_input');
    }
  });

  test('timingSafeEqual compares lengths and bytes', () {
    expect(timingSafeEqual(filled(4, 1), filled(4, 1)), isTrue);
    expect(timingSafeEqual(filled(4, 1), filled(4, 2)), isFalse);
    expect(timingSafeEqual(filled(4, 1), filled(5, 1)), isFalse);
  });
}
