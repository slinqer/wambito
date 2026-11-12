// Ports the request schemas of packages/core/src/schemas.ts and capture.ts; the expected issues
// are what zod 4 reports for the same inputs (the local backend sends them in its 422 body).
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/core/schemas.dart';

const id = '0190a8a0-0000-7000-8000-000000000001';

Json ok(Schema<Json> schema, Object? body) {
  final r = validate(schema, body);
  expect(r, isA<Valid<Json>>(), reason: r is Invalid<Json> ? r.issues.join(', ') : null);
  return (r as Valid<Json>).data;
}

List<String> bad(Schema<Json> schema, Object? body) {
  final r = validate(schema, body);
  expect(r, isA<Invalid<Json>>(), reason: 'expected a failure for $body');
  return [for (final i in (r as Invalid<Json>).issues) '${i.path}|${i.message}'];
}

Json tx([Json extra = const {}]) => {
  'name': 'a',
  'amount': 5,
  'categoryId': id,
  'date': '2026-01-01',
  ...extra,
};

void main() {
  group('createTransactionSchema', () {
    test('defaults status and source, trims the name, strips unknown keys', () {
      final v = ok(createTransactionSchema, tx({'name': ' a ', 'x': 1, 'note': null}));
      expect(v, {
        'name': 'a',
        'amount': 5,
        'categoryId': id,
        'date': '2026-01-01',
        'status': 'paid',
        'note': null,
        'source': 'app',
      });
    });

    test('a missing field is reported with its type', () {
      expect(bad(createTransactionSchema, <String, Object?>{}), [
        'name|Invalid input: expected string, received undefined',
        'amount|Invalid input: expected number, received undefined',
        'categoryId|Invalid input: expected string, received undefined',
        'date|Invalid input: expected string, received undefined',
      ]);
    });

    test('a body that is not an object', () {
      expect(bad(createTransactionSchema, null), [
        '|Invalid input: expected object, received null',
      ]);
      expect(bad(createTransactionSchema, <Object?>[]), [
        '|Invalid input: expected object, received array',
      ]);
      expect(bad(createTransactionSchema, 'x'), [
        '|Invalid input: expected object, received string',
      ]);
    });

    test('every field rule at once', () {
      expect(
        bad(createTransactionSchema, {
          'name': '  ',
          'amount': 0.5,
          'categoryId': 'x',
          'date': '2026-13-01',
          'status': 'z',
          'note': 5,
          'source': 'import',
          'repeat': {'frequency': 'x', 'endDate': 5},
        }),
        [
          'name|Too small: expected string to have >=1 characters',
          'amount|Invalid input: expected int, received number',
          'categoryId|Invalid UUID',
          'date|Expected a date as YYYY-MM-DD',
          'status|Invalid option: expected one of "paid"|"pending"',
          'note|Invalid input: expected string, received number',
          'source|Invalid option: expected one of "app"|"web"|"widget"|"mcp"',
          'repeat.frequency|Invalid option: expected one of "monthly"|"yearly"',
          'repeat.endDate|Invalid input: expected string, received number',
        ],
      );
    });

    test('type errors', () {
      expect(bad(createTransactionSchema, {...tx(), 'name': 5, 'amount': '5', 'date': 5}), [
        'name|Invalid input: expected string, received number',
        'amount|Invalid input: expected number, received string',
        'date|Invalid input: expected string, received number',
      ]);
      expect(bad(createTransactionSchema, tx({'status': null})), [
        'status|Invalid option: expected one of "paid"|"pending"',
      ]);
    });

    test('length limits', () {
      expect(bad(createTransactionSchema, tx({'name': 'a' * 121, 'note': 'n' * 1001})), [
        'name|Too big: expected string to have <=120 characters',
        'note|Too big: expected string to have <=1000 characters',
      ]);
      ok(createTransactionSchema, tx({'name': 'a' * 120, 'note': 'n' * 1000}));
    });

    test('the amount is a safe, non-zero integer', () {
      expect(bad(createTransactionSchema, tx({'amount': 0})), ['amount|Amount cannot be zero']);
      expect(bad(createTransactionSchema, tx({'amount': 1e20})), [
        'amount|Too big: expected int to be <=9007199254740991',
        'amount|Amount is too large',
      ]);
      expect(bad(createTransactionSchema, tx({'amount': -1e20})), [
        'amount|Too small: expected int to be >=-9007199254740991',
        'amount|Amount is too large',
      ]);
      ok(createTransactionSchema, tx({'amount': 9007199254740991}));
      ok(createTransactionSchema, tx({'amount': -9007199254740991}));
    });

    test('a JSON 5.0 is the integer 5', () {
      final v = ok(createTransactionSchema, tx({'amount': 5.0}));
      expect(v['amount'], isA<int>());
    });

    test('uuids of any version and case are accepted, like zod 4', () {
      ok(createTransactionSchema, tx({'categoryId': '00000000-0000-0000-0000-000000000000'}));
      ok(createTransactionSchema, tx({'categoryId': id.toUpperCase()}));
    });

    test('repeat: an endDate before the date is refused', () {
      final repeat = {'frequency': 'monthly', 'endDate': '2025-01-01'};
      expect(bad(createTransactionSchema, tx({'repeat': repeat})), [
        'repeat.endDate|endDate must be on or after date',
      ]);
      // type errors stop the cross-field check, as in zod
      expect(bad(createTransactionSchema, tx({'name': 5, 'repeat': repeat})), [
        'name|Invalid input: expected string, received number',
      ]);
      // a failed check (not a type error) does not
      expect(bad(createTransactionSchema, tx({'name': '', 'repeat': repeat})), [
        'name|Too small: expected string to have >=1 characters',
        'repeat.endDate|endDate must be on or after date',
      ]);
      expect(
        bad(
          createTransactionSchema,
          tx({
            'repeat': {'frequency': 'x', 'endDate': '2025-01-01'},
          }),
        ),
        ['repeat.frequency|Invalid option: expected one of "monthly"|"yearly"'],
      );
    });

    test('repeat: endDate may be null or missing; repeat itself may not be null', () {
      final v = ok(
        createTransactionSchema,
        tx({
          'repeat': {'frequency': 'monthly', 'endDate': null},
        }),
      );
      expect(v['repeat'], {'frequency': 'monthly', 'endDate': null});
      expect(
        ok(
          createTransactionSchema,
          tx({
            'repeat': {'frequency': 'yearly'},
          }),
        )['repeat'],
        {'frequency': 'yearly'},
      );
      expect(bad(createTransactionSchema, tx({'repeat': null})), [
        'repeat|Invalid input: expected object, received null',
      ]);
    });
  });

  group('updateTransactionSchema', () {
    test('needs at least one field', () {
      expect(bad(updateTransactionSchema, <String, Object?>{}), ['|Provide at least one field']);
      expect(bad(updateTransactionSchema, {'x': 1}), ['|Provide at least one field']);
    });

    test('keeps only the fields it was given', () {
      expect(ok(updateTransactionSchema, {'note': null, 'status': 'paid', 'x': 1}), {
        'status': 'paid',
        'note': null,
      });
      expect(ok(updateTransactionSchema, {'name': 'xx  '}), {'name': 'xx'});
    });

    test('needsReview only allows confirming', () {
      expect(bad(updateTransactionSchema, {'needsReview': true}), [
        'needsReview|Invalid input: expected false',
      ]);
      expect(ok(updateTransactionSchema, {'needsReview': false}), {'needsReview': false});
    });

    test('a null where a value is needed is a type error, and skips the at-least-one check', () {
      expect(bad(updateTransactionSchema, {'amount': null}), [
        'amount|Invalid input: expected number, received null',
      ]);
      expect(bad(updateTransactionSchema, {'amount': -1e20}), [
        'amount|Too small: expected int to be >=-9007199254740991',
        'amount|Amount is too large',
      ]);
    });
  });

  group('createCategorySchema', () {
    final category = {'name': ' a ', 'icon': 'i', 'color': 'c', 'kind': 'income'};

    test('trims, optional sortOrder', () {
      expect(ok(createCategorySchema, {...category, 'sortOrder': 3}), {
        'name': 'a',
        'icon': 'i',
        'color': 'c',
        'sortOrder': 3,
        'kind': 'income',
      });
      expect(ok(createCategorySchema, category).containsKey('sortOrder'), isFalse);
    });

    test('rules', () {
      expect(bad(createCategorySchema, {'name': 'a', 'icon': '', 'color': 'c', 'kind': 'x'}), [
        'icon|Too small: expected string to have >=1 characters',
        'kind|Invalid option: expected one of "expense"|"income"',
      ]);
      expect(bad(createCategorySchema, {...category, 'sortOrder': 2.5}), [
        'sortOrder|Invalid input: expected int, received number',
      ]);
      expect(bad(createCategorySchema, {...category, 'sortOrder': 1e20}), [
        'sortOrder|Too big: expected int to be <=9007199254740991',
      ]);
      expect(bad(createCategorySchema, {...category, 'name': 'n' * 41}), [
        'name|Too big: expected string to have <=40 characters',
      ]);
    });
  });

  group('updateCategorySchema', () {
    test('needs a field; archived is a boolean', () {
      expect(bad(updateCategorySchema, <String, Object?>{}), ['|Provide at least one field']);
      expect(bad(updateCategorySchema, {'archived': 'x'}), [
        'archived|Invalid input: expected boolean, received string',
      ]);
      expect(ok(updateCategorySchema, {'archived': true, 'kind': 'expense'}), {
        'kind': 'expense',
        'archived': true,
      });
    });
  });

  group('setBudgetSchema', () {
    test('accepts zero and a month', () {
      expect(ok(setBudgetSchema, {'amount': 0, 'effectiveFrom': '2026-01'}), {
        'amount': 0,
        'effectiveFrom': '2026-01',
      });
    });

    test('rules', () {
      expect(bad(setBudgetSchema, {'amount': -1, 'effectiveFrom': 'x'}), [
        'amount|Too small: expected number to be >=0',
        'effectiveFrom|Expected a month as YYYY-MM',
      ]);
      expect(bad(setBudgetSchema, {'amount': 1.5, 'effectiveFrom': '2026-01'}), [
        'amount|Invalid input: expected int, received number',
      ]);
      expect(bad(setBudgetSchema, {'amount': 1e20, 'effectiveFrom': '2026-01'}), [
        'amount|Too big: expected int to be <=9007199254740991',
        'amount|Invalid input',
      ]);
      expect(bad(setBudgetSchema, {'amount': -1e20, 'effectiveFrom': '2026-01'}), [
        'amount|Too small: expected int to be >=-9007199254740991',
        'amount|Too small: expected number to be >=0',
        'amount|Invalid input',
      ]);
    });
  });

  group('createRecurrenceSchema', () {
    final rec = {
      'name': 'a',
      'amount': 1,
      'categoryId': id,
      'frequency': 'monthly',
      'dayOfMonth': 1,
      'startDate': '2026-01-01',
    };

    test('a monthly rule; optional fields stay absent', () {
      final v = ok(createRecurrenceSchema, rec);
      expect(v, rec);
    });

    test('yearly needs monthOfYear, and the end cannot precede the start', () {
      expect(
        bad(createRecurrenceSchema, {
          ...rec,
          'frequency': 'yearly',
          'dayOfMonth': 32,
          'endDate': '2025-01-01',
        }),
        [
          'dayOfMonth|Too big: expected number to be <=31',
          'monthOfYear|Yearly recurrences need monthOfYear',
          'endDate|endDate must be on or after startDate',
        ],
      );
      expect(bad(createRecurrenceSchema, {...rec, 'frequency': 'yearly', 'monthOfYear': null}), [
        'monthOfYear|Yearly recurrences need monthOfYear',
      ]);
      ok(createRecurrenceSchema, {...rec, 'frequency': 'yearly', 'monthOfYear': 3});
    });

    test('type errors stop the cross-field checks', () {
      expect(
        bad(createRecurrenceSchema, {
          ...rec,
          'name': 5,
          'frequency': 'yearly',
          'endDate': '2025-01-01',
        }),
        ['name|Invalid input: expected string, received number'],
      );
      expect(bad(createRecurrenceSchema, {...rec, 'dayOfMonth': 1.5}), [
        'dayOfMonth|Invalid input: expected int, received number',
      ]);
    });

    test('bounds', () {
      expect(bad(createRecurrenceSchema, {...rec, 'monthOfYear': 13}), [
        'monthOfYear|Too big: expected number to be <=12',
      ]);
      expect(bad(createRecurrenceSchema, {...rec, 'dayOfMonth': 1e20}), [
        'dayOfMonth|Too big: expected int to be <=9007199254740991',
        'dayOfMonth|Too big: expected number to be <=31',
      ]);
      expect(bad(createRecurrenceSchema, {...rec, 'dayOfMonth': 0}), [
        'dayOfMonth|Too small: expected number to be >=1',
      ]);
    });
  });

  group('updateRecurrenceSchema', () {
    test('needs a field; no cross-field rule here', () {
      expect(bad(updateRecurrenceSchema, <String, Object?>{}), ['|Provide at least one field']);
      expect(ok(updateRecurrenceSchema, {'frequency': 'yearly'}), {'frequency': 'yearly'});
      expect(ok(updateRecurrenceSchema, {'endDate': null, 'monthOfYear': null}), {
        'monthOfYear': null,
        'endDate': null,
      });
      expect(bad(updateRecurrenceSchema, {'frequency': 'yearly', 'dayOfMonth': 0}), [
        'dayOfMonth|Too small: expected number to be >=1',
      ]);
    });
  });

  group('updateProfileSchema', () {
    test('needs a field', () {
      expect(bad(updateProfileSchema, <String, Object?>{}), ['|Provide at least one field']);
    });

    test('rules', () {
      expect(
        bad(updateProfileSchema, {
          'timezone': 'Nope/X',
          'locale': 'fr',
          'currency': 'XXX',
          'onboardingCompleted': false,
        }),
        [
          'timezone|Unknown time zone',
          'locale|Invalid option: expected one of "es"|"en"|"it"|"pt"',
          'currency|Invalid option: expected one of "COP"|"USD"|"EUR"',
          'onboardingCompleted|Invalid input: expected true',
        ],
      );
      expect(
        ok(updateProfileSchema, {
          'timezone': 'America/Bogota',
          'locale': 'es',
          'currency': 'COP',
          'onboardingCompleted': true,
        }),
        {
          'timezone': 'America/Bogota',
          'locale': 'es',
          'currency': 'COP',
          'onboardingCompleted': true,
        },
      );
    });
  });

  group('reviewTransactionsSchema', () {
    const uuid = '00000000-0000-4000-8000-000000000000';

    test('needs 1 to 50 uuids', () {
      expect(bad(reviewTransactionsSchema, {'ids': <Object?>[]}), [
        'ids|Too small: expected array to have >=1 items',
      ]);
      expect(bad(reviewTransactionsSchema, {'ids': List.filled(51, uuid)}), [
        'ids|Too big: expected array to have <=50 items',
      ]);
      expect(
        (ok(reviewTransactionsSchema, {
              'ids': [uuid],
            })['ids']
            as List),
        hasLength(1),
      );
    });

    test('rules', () {
      expect(bad(reviewTransactionsSchema, <String, Object?>{}), [
        'ids|Invalid input: expected array, received undefined',
      ]);
      expect(
        bad(reviewTransactionsSchema, {
          'ids': ['x'],
        }),
        ['ids.0|Invalid UUID'],
      );
      expect(
        ok(reviewTransactionsSchema, {
          'ids': [uuid],
          'z': 1,
        }),
        {
          'ids': [uuid],
        },
      );
    });
  });
}
