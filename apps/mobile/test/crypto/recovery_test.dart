import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/crypto.dart';

import 'helpers.dart';

const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

void main() {
  test('makes 16 random bytes', () {
    final s = newRecoverySecret();
    expect(s, hasLength(16));
    expect(s, isNot(newRecoverySecret()));
  });

  test('formats as 26 + 1 characters in groups of four', () {
    for (var i = 0; i < 20; i++) {
      expect(
        formatRecoveryKey(newRecoverySecret()),
        matches(RegExp(r'^([0-9A-Z]{4}-){6}[0-9A-Z]{3}$')),
      );
    }
  });

  test('round trips; lower case, spaces and missing dashes are accepted', () {
    final s = newRecoverySecret();
    final t = formatRecoveryKey(s);
    expect(parseRecoveryKey(t), s);
    expect(parseRecoveryKey(t.toLowerCase()), s);
    expect(parseRecoveryKey(' ${t.replaceAll('-', ' ')} '), s);
    expect(parseRecoveryKey(t.replaceAll('-', '')), s);
  });

  test('all-zero and all-ones secrets round trip', () {
    for (final fill in [0, 255]) {
      final s = filled(16, fill);
      expect(parseRecoveryKey(formatRecoveryKey(s)), s);
    }
  });

  test('O reads as 0, I and L read as 1', () {
    final s = Uint8List(16); // zero secret: all data characters are 0
    final t = formatRecoveryKey(s);
    expect(parseRecoveryKey(t.replaceAll('0', 'O')), s);
    final ones = filled(16, 0x08)..[0] = 0x42;
    final tt = formatRecoveryKey(ones);
    expect(parseRecoveryKey(tt.replaceAll('1', 'I')), ones);
    expect(parseRecoveryKey(tt.replaceAll('1', 'l')), ones);
    expect(parseRecoveryKey(tt.replaceAll('0', 'o')), ones);
  });

  test('one wrong character is caught by the check character', () {
    for (var n = 0; n < 50; n++) {
      final t = formatRecoveryKey(newRecoverySecret()).replaceAll('-', '');
      for (var i = 0; i < t.length; i++) {
        for (final c in alphabet.split('')) {
          if (c == t[i]) continue;
          final mutated = t.substring(0, i) + c + t.substring(i + 1);
          // I/L/O are not in the alphabet, so a mutation never aliases the original.
          expect(codeSync(() => parseRecoveryKey(mutated)), 'bad_recovery_key');
        }
      }
    }
  });

  test('a swap of two adjacent different characters is caught for at least 95% of keys', () {
    final random = Random();
    var caught = 0;
    for (var n = 0; n < 200; n++) {
      final t = formatRecoveryKey(newRecoverySecret()).replaceAll('-', '');
      var i = random.nextInt(25);
      while (t[i] == t[i + 1]) {
        i = (i + 1) % 25;
      }
      final swapped = t.substring(0, i) + t[i + 1] + t[i] + t.substring(i + 2);
      if (codeSync(() => parseRecoveryKey(swapped)) == 'bad_recovery_key') caught++;
    }
    expect(caught, greaterThanOrEqualTo(190));
  });

  // A non-string is not representable in Dart: the TS case has no twin.

  test('rejects wrong length and foreign characters', () {
    final t = formatRecoveryKey(newRecoverySecret());
    expect(codeSync(() => parseRecoveryKey('')), 'bad_recovery_key');
    expect(codeSync(() => parseRecoveryKey(t.substring(0, t.length - 1))), 'bad_recovery_key');
    expect(codeSync(() => parseRecoveryKey('${t}0')), 'bad_recovery_key');
    expect(
      codeSync(() => parseRecoveryKey('${t.substring(0, 5)}!${t.substring(6)}')),
      'bad_recovery_key',
    );
  });

  test('rejects non-16-byte secrets when formatting', () {
    expect(codeSync(() => formatRecoveryKey(Uint8List(15))), 'bad_input');
  });
}
