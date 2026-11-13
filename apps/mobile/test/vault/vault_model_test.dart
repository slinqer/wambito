// Port of apps/web/app/features/vault/vault-model.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/vault/vault_model.dart';

const _key = 'ABCD-EFGH-JKMN-PQRS-TVWX-YZ01-234';

void main() {
  group('pickPositions', () {
    test('returns four distinct ascending positions among the 26 data characters', () {
      for (var i = 0; i < 50; i++) {
        final p = pickPositions();
        expect(p, hasLength(4));
        expect([...p]..sort(), p);
        expect(p.toSet(), hasLength(4));
        for (final n in p) {
          expect(n, greaterThanOrEqualTo(1));
          expect(n, lessThanOrEqualTo(26));
        }
      }
    });
  });

  group('groupPosition', () {
    test('names a position by its group of four and its place in it', () {
      expect([1, 4, 5, 6, 14, 26].map(groupPosition).toList(), [
        (group: 1, char: 1),
        (group: 1, char: 4),
        (group: 2, char: 1),
        (group: 2, char: 2),
        (group: 4, char: 2),
        (group: 7, char: 2),
      ]);
    });
  });

  group('charsAt', () {
    test('reads 1-based positions ignoring the dashes', () {
      expect(charsAt(_key, [1, 5, 9, 26]), ['A', 'E', 'J', '3']);
    });
  });

  group('confirmationMatches', () {
    test('accepts any case, and O or I typed for 0 or 1', () {
      expect(confirmationMatches(_key, [1, 5, 9, 26], ['a', 'e', 'j', '3']), isTrue);
      expect(confirmationMatches(_key, [23, 24], ['o', 'i']), isTrue);
      expect(confirmationMatches(_key, [23, 24], ['0', 'L']), isTrue);
    });

    test('rejects blanks and wrong characters', () {
      expect(confirmationMatches(_key, [1, 5], ['A', '']), isFalse);
      expect(confirmationMatches(_key, [1, 5], ['A', 'X']), isFalse);
    });
  });

  group('recoveryFileText', () {
    test('holds the key, a short line and the date, and nothing else', () {
      final text = recoveryFileText(title: 'T', key: _key, line: 'L', date: 'D');
      expect(text, 'T\n\n$_key\n\nL\nD\n');
    });
  });
}
