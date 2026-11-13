// Ports apps/web/app/local/ids.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/local/ids.dart';

final _v7 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

void main() {
  group('uuidv7', () {
    test('is a lower-case version 7 UUID carrying the time in its first 48 bits', () {
      final at = DateTime.utc(2026, 11, 8, 12).millisecondsSinceEpoch;
      final id = uuidv7(at);
      expect(id, matches(_v7));
      expect(int.parse(id.replaceAll('-', '').substring(0, 12), radix: 16), at);
    });

    test('sorts in creation order, also within one millisecond or when the clock goes back', () {
      final at = DateTime.utc(2026, 11, 8).millisecondsSinceEpoch;
      final ids = [uuidv7(at), uuidv7(at), uuidv7(at), uuidv7(at - 5), uuidv7(at + 1)];
      expect([...ids]..sort(), ids);
      expect(ids.toSet().length, ids.length);
    });

    test('uses the current time by default', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final ms = int.parse(uuidv7().replaceAll('-', '').substring(0, 12), radix: 16);
      expect(ms, greaterThanOrEqualTo(before));
      expect(ms, lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch + 1));
    });
  });

  group('uuidv5', () {
    test('matches the RFC 4122 example (DNS namespace, python.org)', () {
      expect(
        uuidv5('6ba7b810-9dad-11d1-80b4-00c04fd430c8', 'python.org'),
        '886313e1-3b8a-5372-9b90-0c9aee199e5d',
      );
    });

    test('is stable per rule and month and differs between them', () {
      const rule = '01930000-0000-7000-8000-000000000001';
      final a = uuidv5(rule, '2026-10');
      expect(uuidv5(rule, '2026-10'), a);
      expect(uuidv5(rule, '2026-11'), isNot(a));
      expect(a, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });
  });
}
