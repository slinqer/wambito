// Ports packages/core/src/records.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/core/records.dart';
import 'package:wambito/crypto/records.dart' show RecordType;

const id = '0190a8a0-0000-7000-8000-000000000001';

final Map<String, Json> valid = {
  'transaction': {
    's': 1,
    'name': 'Lunch',
    'amount': -18000,
    'currency': 'COP',
    'date': '2026-10-21',
    'status': 'paid',
    'categoryId': id,
    'source': 'app',
  },
  'category': {
    's': 1,
    'name': 'Food',
    'kind': 'expense',
    'icon': 'food',
    'color': 'red',
    'sortOrder': 0,
  },
  'budget': {'s': 1, 'categoryId': id, 'amount': 50000, 'effectiveFrom': '2026-10'},
  'recurrence': {
    's': 1,
    'name': 'Rent',
    'amount': -80000,
    'categoryId': id,
    'frequency': 'monthly',
    'dayOfMonth': 1,
    'startDate': '2026-01-01',
  },
  'merchant': {'s': 1, 'merchantKey': 'rappi', 'categoryId': id},
  'settings': {'s': 1, 'currency': 'COP', 'locale': 'es', 'timezone': 'America/Bogota'},
  'account': {'s': 1, 'name': 'Main', 'currency': 'COP'},
};

void main() {
  group('parseRecord', () {
    test('covers every record type', () {
      expect(RecordType.values.map((t) => t.name).toList()..sort(), valid.keys.toList()..sort());
    });

    for (final type in RecordType.values) {
      test('${type.name}: accepts a valid body and fills defaults', () {
        expect(parseRecord(type, valid[type.name]).ok, isTrue);
      });

      test('${type.name}: requires s', () {
        final rest = {...valid[type.name]!}..remove('s');
        expect(parseRecord(type, rest).ok, isFalse);
      });

      test("${type.name}: keeps unknown keys, so a newer client's fields survive", () {
        final r = parseRecord(type, {
          ...valid[type.name]!,
          'future': {'x': 1},
        });
        expect(r.ok, isTrue);
        expect(r.value!['future'], {'x': 1});
      });

      test('${type.name}: never throws on garbage', () {
        for (final junk in <Object?>[null, 1, 'x', <Object?>[], <String, Object?>{}]) {
          expect(parseRecord(type, junk).ok, isFalse);
        }
      });

      test('${type.name}: parseRecordBody throws RecordBodyError with the path', () {
        expect(
          () => parseRecordBody(type, null),
          throwsA(
            isA<RecordBodyError>()
                .having((e) => e.type, 'type', type)
                .having((e) => e.path, 'path', ''),
          ),
        );
      });
    }

    test('a transaction defaults its optional fields', () {
      final r = parseRecord(RecordType.transaction, valid['transaction']);
      expect(r.ok, isTrue);
      expect(r.value!['note'], isNull);
      expect(r.value!['recurrenceId'], isNull);
      expect(r.value!['occurrenceMonth'], isNull);
      expect(r.value!['needsReview'], false);
      expect(r.value!.containsKey('note'), isTrue);
      expect(r.value!.containsKey('updatedAt'), isFalse);
    });

    test('rejects a zero amount and a bad date', () {
      expect(
        parseRecord(RecordType.transaction, {...valid['transaction']!, 'amount': 0}).ok,
        false,
      );
      expect(
        parseRecord(RecordType.transaction, {...valid['transaction']!, 'date': '2026-13-01'}).ok,
        false,
      );
    });

    test("a recurrence's rev defaults to 0 and must be a non-negative integer", () {
      expect(parseRecord(RecordType.recurrence, valid['recurrence']).value!['rev'], 0);
      expect(
        parseRecord(RecordType.recurrence, {...valid['recurrence']!, 'rev': 3}).value!['rev'],
        3,
      );
      expect(parseRecord(RecordType.recurrence, {...valid['recurrence']!, 'rev': -1}).ok, false);
    });

    test("a transaction's updatedAt is optional", () {
      expect(parseRecord(RecordType.transaction, valid['transaction']).ok, isTrue);
      final r = parseRecord(RecordType.transaction, {
        ...valid['transaction']!,
        'updatedAt': '2026-10-21T10:00:00Z',
      });
      expect(r.value!['updatedAt'], '2026-10-21T10:00:00Z');
    });

    test('a JSON whole double is an integer, as in JavaScript', () {
      final r = parseRecord(RecordType.transaction, {...valid['transaction']!, 'amount': -18000.0});
      expect(r.ok, isTrue);
      expect(r.value!['amount'], isA<int>());
    });

    test('reports the failing paths like the TypeScript', () {
      expect(
        parseRecord(RecordType.settings, {
          's': 2,
          'currency': 'X',
          'locale': 'fr',
          'timezone': 'Nope',
        }).error,
        's: Invalid input: expected 1; '
        'currency: Invalid option: expected one of "COP"|"USD"|"EUR"; '
        'locale: Invalid option: expected one of "es"|"en"|"it"|"pt"; '
        'timezone: Unknown time zone',
      );
      expect(
        parseRecord(RecordType.account, null).error,
        '(body): Invalid input: expected object, received null',
      );
      expect(
        parseRecord(RecordType.transaction, {
          ...valid['transaction']!,
          'captureSource': 'foo',
          'accountId': 'x',
        }).error,
        'accountId: Invalid UUID; captureSource: Invalid option: expected one of "revolut"|"google_wallet"',
      );
    });
  });

  group('settings revokedDevices', () {
    final settings = valid['settings']!;
    const uuid = '0190a1b2-c3d4-7e5f-8a6b-7c8d9e0f1a2b';

    test('settings without revokedDevices parses to []', () {
      expect(parseRecord(RecordType.settings, settings).value!['revokedDevices'], <Object?>[]);
    });

    test('revokedDevices keeps lower-case uuids', () {
      final r = parseRecord(RecordType.settings, {
        ...settings,
        'revokedDevices': [uuid],
      });
      expect(r.value!['revokedDevices'], [uuid]);
    });

    test('each parse gets its own default list', () {
      final a = parseRecord(RecordType.settings, settings).value!['revokedDevices'] as List;
      a.add(uuid);
      final b = parseRecord(RecordType.settings, settings).value!['revokedDevices'] as List;
      expect(identical(a, b), isFalse);
      expect(b, isEmpty);
    });

    test('a non-uuid in revokedDevices fails', () {
      expect(
        parseRecord(RecordType.settings, {
          ...settings,
          'revokedDevices': ['nope'],
        }).ok,
        false,
      );
    });
  });
}
