import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/core/money.dart';

void main() {
  group('parseDecimalToMinor bounds', () {
    test('accepts the largest safe amount', () {
      expect(parseDecimalToMinor('90071992547409.91'), 9007199254740991);
      expect(parseDecimalToMinor('-90071992547409.91'), -9007199254740991);
    });

    test('rejects a value over 2^53 - 1', () {
      expect(() => parseDecimalToMinor('90071992547409.92'), throwsA(isA<InvalidAmountError>()));
    });

    // Dart ints are 64-bit and wrap: 184467440737095516 * 100 wraps below the guard.
    test('rejects a whole part whose product with 100 would wrap', () {
      expect(() => parseDecimalToMinor('184467440737095516'), throwsA(isA<InvalidAmountError>()));
      expect(() => parseDecimalToMinor('92233720368547759'), throwsA(isA<InvalidAmountError>()));
      expect(
        () => parseDecimalToMinor('99999999999999999999999'),
        throwsA(isA<InvalidAmountError>()),
      );
    });
  });
}
