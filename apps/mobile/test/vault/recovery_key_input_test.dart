// The recovery key's field (spec 2026-11-20 section 3), the same cases as the web's
// apps/web/app/features/vault/recovery-key-input.test.ts.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/vault/recovery_key_input.dart';

const full = 'ABCD-EFGH-2345-6789-ABCD-EFGH-234';

TextEditingValue _value(String text, int caret) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: caret),
);

void main() {
  group('groupRecoveryKey', () {
    test('groups while typing', () {
      expect(groupRecoveryKey('abcd2'), 'ABCD-2');
    });

    test('regroups a paste in any shape', () {
      expect(groupRecoveryKey('abcd efgh\n2345-6789 abcd efgh 234 '), full);
    });

    test('keeps O, I and L, drops what the alphabet lacks', () {
      expect(groupRecoveryKey('o0il!?'), 'O0IL');
      expect(groupRecoveryKey('uU'), '');
    });

    test('never grows past a full key', () {
      expect(groupRecoveryKey('$full-5678'), full);
      expect(groupRecoveryKey('a' * 60), hasLength(33));
    });
  });

  group('groupRecoveryKeyEdit', () {
    test('deleting just after a dash removes the character before it and keeps the caret', () {
      // "ABCD-E" with the caret after the dash: Backspace removed the dash only. The character
      // before it goes instead, the rest regroups and the caret stays after "ABC".
      expect(groupRecoveryKeyEdit('ABCD-E', 'ABCDE', 4), (text: 'ABCE', caret: 3));
    });

    test('typing in the middle keeps the caret after the typed character', () {
      expect(groupRecoveryKeyEdit('ABCD-EFGH', 'ABCXD-EFGH', 4), (text: 'ABCX-DEFG-H', caret: 4));
      // the typed character lands right before a dash that regrouping moves: caret after the dash
      expect(groupRecoveryKeyEdit('ABCD-EFGH', 'ABCDX-EFGH', 5), (text: 'ABCD-XEFG-H', caret: 6));
    });

    test('appending at the end puts the caret at the end', () {
      expect(groupRecoveryKeyEdit('ABCD', 'ABCDE', 5), (text: 'ABCD-E', caret: 6));
    });

    test('a paste puts the caret at the end of what was kept', () {
      expect(groupRecoveryKeyEdit('', 'abcd efgh', 9), (text: 'ABCD-EFGH', caret: 9));
    });
  });

  group('isFullRecoveryKey', () {
    test('is true only at 27 characters', () {
      expect(isFullRecoveryKey(full), isTrue);
      expect(isFullRecoveryKey(full.substring(0, full.length - 1)), isFalse);
      expect(isFullRecoveryKey(''), isFalse);
    });
  });

  group('RecoveryKeyFormatter', () {
    const formatter = RecoveryKeyFormatter();

    test('groups and upper-cases what is typed, the caret after it', () {
      final out = formatter.formatEditUpdate(_value('ABCD', 4), _value('ABCDe', 5));
      expect(out.text, 'ABCD-E');
      expect(out.selection, const TextSelection.collapsed(offset: 6));
    });

    test('Backspace over a dash removes the character before it', () {
      final out = formatter.formatEditUpdate(_value('ABCD-E', 5), _value('ABCDE', 4));
      expect(out.text, 'ABCE');
      expect(out.selection, const TextSelection.collapsed(offset: 3));
    });

    test('a paste in any shape is regrouped and capped at a full key', () {
      final out = formatter.formatEditUpdate(
        _value('', 0),
        _value('abcd efgh\n2345-6789 abcd efgh 234 5678', 38),
      );
      expect(out.text, full);
      expect(out.selection, const TextSelection.collapsed(offset: full.length));
    });

    test('never hands a composing range back to the keyboard', () {
      final out = formatter.formatEditUpdate(
        _value('ABCD', 4),
        const TextEditingValue(
          text: 'ABCDe',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 4, end: 5),
        ),
      );
      expect(out.text, 'ABCD-E');
      expect(out.composing, TextRange.empty);
    });
  });
}
