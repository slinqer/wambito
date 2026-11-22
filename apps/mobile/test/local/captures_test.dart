// Ports the cases of apps/api/test/captures.test.ts that do not involve auth: the phone's local
// `POST /v1/captures` and the merchant memory it reads and `review`/`PATCH` write.
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/core/records.dart' show Json;
import 'package:wambito/crypto/records.dart' show RecordType;
import 'package:wambito/local/backend.dart';
import 'package:wambito/local/captures.dart';
import 'package:wambito/local/ids.dart';
import 'package:wambito/local/memory_store.dart';
import 'package:wambito/local/store.dart';

const _userId = 'user-1';
final _now = DateTime.utc(2026, 11, 4, 16);

typedef Ctx = ({FinanceStore store, LocalBackend backend});

Ctx _setup({String locale = 'es', String timezone = 'UTC'}) {
  final store = createMemoryStore();
  final backend = createLocalBackend(
    store: store,
    now: () => _now,
    profile: const LocalProfile(id: _userId),
  );
  final ctx = (store: store, backend: backend);
  _call(ctx, 'PATCH', '/v1/me', body: {'currency': 'EUR', 'locale': locale, 'timezone': timezone});
  return ctx;
}

int _keyCounter = 0;

Future<LocalResponse> _call(
  Ctx ctx,
  String method,
  String path, {
  Object? body,
  Map<String, String>? headers,
}) async {
  final res = await ctx.backend.handle(method, path, const {}, body, headers: headers ?? const {});
  if (res == null) throw StateError('not served: $method $path');
  return res;
}

Json _json(Object? o) => (o! as Map).cast<String, Object?>();

Map<String, Object?> _body([Map<String, Object?> extra = const {}]) => {
  'kind': 'expense',
  'amount': 1250,
  'currency': 'EUR',
  'merchant': 'Mercadona',
  'capturedAt': '2026-11-04T15:00:00Z',
  'source': 'revolut',
  ...extra,
};

Future<LocalResponse> _capture(
  Ctx ctx, [
  Map<String, Object?> extra = const {},
  String? key = '',
]) => _call(
  ctx,
  'POST',
  '/v1/captures',
  body: _body(extra),
  headers: {if (key != null) 'idempotency-key': key.isEmpty ? 'capture-key-${++_keyCounter}' : key},
);

Future<Json> _created(Ctx ctx, [Map<String, Object?> extra = const {}]) async {
  final res = await _capture(ctx, extra);
  expect(res.status, anyOf(200, 201), reason: '${res.body}');
  return _json(res.body);
}

Json _tx(Json out) => _json(out['transaction']);
Json _category(Json out) => _json(out['category']);

Future<String> _newCategory(
  Ctx ctx,
  String name, {
  String kind = 'expense',
  bool archived = false,
}) async {
  final made = await _call(
    ctx,
    'POST',
    '/v1/categories',
    body: {'name': name, 'kind': kind, 'icon': 'x', 'color': '#fff'},
  );
  final id = _json(made.body)['id']! as String;
  if (archived) await _call(ctx, 'PATCH', '/v1/categories/$id', body: {'archived': true});
  return id;
}

Future<void> _learned(Ctx ctx, String key, String categoryId) => ctx.store.put(
  RecordType.merchant,
  merchantRecordId(_userId, key),
  {'s': 1, 'merchantKey': key, 'categoryId': categoryId},
);

Future<List<StoredRecord>> _memory(Ctx ctx) => ctx.store.list(RecordType.merchant);

void main() {
  group('merchantRecordId', () {
    test('is the uuid v5 of the account namespace and the merchant key', () {
      expect(
        merchantRecordId(_userId, 'mercadona'),
        uuidv5(uuidv5(seedNamespace, _userId), 'merchant:mercadona'),
      );
      expect(merchantRecordId(_userId, 'lidl'), isNot(merchantRecordId(_userId, 'mercadona')));
      expect(merchantRecordId('user-2', 'lidl'), isNot(merchantRecordId(_userId, 'lidl')));
    });
  });

  group('create', () {
    test('creates a capture to review', () async {
      final ctx = _setup();
      final res = await _capture(ctx, {'merchant': 'Create Shop'});
      expect(res.status, 201);
      final out = _json(res.body);
      expect(out['result'], 'created');
      expect(
        _tx(out),
        allOf(
          containsPair('amount', -1250),
          containsPair('currency', 'EUR'),
          containsPair('needsReview', true),
          containsPair('source', 'capture'),
          containsPair('captureSource', 'revolut'),
          containsPair('note', null),
          containsPair('date', '2026-11-04'),
        ),
      );
      expect(_category(out), {'name': 'Otros gastos', 'fallback': true});
      final stored = await ctx.store.get(RecordType.transaction, _tx(out)['id']! as String);
      expect(stored?.body, containsPair('captureMerchantKey', 'create shop'));
      expect(stored?.body, containsPair('capturedAt', '2026-11-04T15:00:00.000Z'));
      expect(stored?.body, containsPair('name', 'Create Shop'));
    });

    test('a signed amount: an expense of 1250000 is -1250000', () async {
      final ctx = _setup();
      final out = await _created(ctx, {'amount': 1250000});
      expect(_tx(out)['amount'], -1250000);
    });

    test('income lands in Otros ingresos', () async {
      final ctx = _setup();
      final out = await _created(ctx, {'kind': 'income', 'amount': 500, 'merchant': 'Income Co'});
      expect(_tx(out)['amount'], 500);
      expect(_category(out), {'name': 'Otros ingresos', 'fallback': true});
    });

    test('a merchant with no letters still saves, into the fallback', () async {
      final ctx = _setup();
      final res = await _capture(ctx, {'merchant': '***', 'amount': 777});
      expect(res.status, 201);
      expect(_category(_json(res.body)), {'name': 'Otros gastos', 'fallback': true});
      final stored = await ctx.store.get(
        RecordType.transaction,
        _tx(_json(res.body))['id']! as String,
      );
      expect(stored?.body, containsPair('captureMerchantKey', null));
    });

    test('a note keeps the original amount when the currency differs', () async {
      final ctx = _setup();
      final out = await _created(ctx, {'currency': 'USD', 'amount': 1250, 'merchant': 'Abroad'});
      expect(_tx(out)['note'], '12.50 USD');
      expect(_tx(out)['needsReview'], true);
      expect(_tx(out)['amount'], -1250);
      expect(_tx(out)['currency'], 'EUR');
    });

    test('takes a payment from Apple Wallet', () async {
      final ctx = _setup();
      final res = await _capture(ctx, {'source': 'apple_wallet', 'amount': 1800});
      expect(res.status, 201);
      final stored = await ctx.store.get(
        RecordType.transaction,
        _tx(_json(res.body))['id']! as String,
      );
      expect(stored?.body, containsPair('captureSource', 'apple_wallet'));
    });

    test('dates by the profile zone', () async {
      final ctx = _setup(timezone: 'America/Bogota');
      final out = await _created(ctx, {'capturedAt': '2026-11-05T03:30:00Z'});
      expect(_tx(out)['date'], '2026-11-04');
    });
  });

  group('validation', () {
    test('answers 422 validation_failed for a body that is not a capture', () async {
      final ctx = _setup();
      for (final extra in [
        {'amount': 0},
        {'amount': -5},
        {'amount': 12.5},
        {'kind': 'transfer'},
        {'currency': 'eur'},
        {'merchant': '   '},
        {'capturedAt': 'yesterday'},
        {'source': 'sms'},
      ]) {
        final res = await _capture(ctx, extra);
        expect(res.status, 422, reason: '$extra');
        expect(_json(res.body)['code'], 'validation_failed', reason: '$extra');
      }
      expect((await ctx.store.list(RecordType.transaction)), isEmpty);
    });
  });

  group('de-duplication', () {
    test('merges within 10 minutes', () async {
      final ctx = _setup();
      final first = await _created(ctx, {'amount': 1111, 'capturedAt': '2026-11-04T10:00:00Z'});
      final res = await _capture(ctx, {
        'amount': 1111,
        'source': 'google_wallet',
        'capturedAt': '2026-11-04T10:09:00Z',
      });
      expect(res.status, 200);
      final out = _json(res.body);
      expect(out['result'], 'merged');
      expect(_tx(out)['id'], _tx(first)['id']);
      expect(_category(out)['fallback'], true);
      expect(await ctx.store.list(RecordType.transaction), hasLength(1));
    });

    test('does not merge after 10 minutes', () async {
      final ctx = _setup();
      final first = await _created(ctx, {'amount': 2222, 'capturedAt': '2026-11-04T10:00:00Z'});
      final second = await _created(ctx, {'amount': 2222, 'capturedAt': '2026-11-04T10:11:00Z'});
      expect(second['result'], 'created');
      expect(_tx(second)['id'], isNot(_tx(first)['id']));
    });

    test('does not merge across kind', () async {
      final ctx = _setup();
      await _created(ctx, {'amount': 3333, 'capturedAt': '2026-11-04T10:00:00Z'});
      final out = await _created(ctx, {
        'amount': 3333,
        'kind': 'income',
        'capturedAt': '2026-11-04T10:01:00Z',
      });
      expect(out['result'], 'created');
    });

    test('does not merge across amount or currency', () async {
      final ctx = _setup();
      await _created(ctx, {'amount': 4444, 'capturedAt': '2026-11-04T10:00:00Z'});
      expect(
        (await _created(ctx, {'amount': 4445, 'capturedAt': '2026-11-04T10:01:00Z'}))['result'],
        'created',
      );
      expect(
        (await _created(ctx, {
          'amount': 4444,
          'currency': 'USD',
          'capturedAt': '2026-11-04T10:01:00Z',
        }))['result'],
        'created',
      );
    });

    test('merges into a confirmed capture', () async {
      final ctx = _setup();
      final first = await _created(ctx, {'amount': 5555, 'capturedAt': '2026-11-04T10:00:00Z'});
      final id = _tx(first)['id']! as String;
      final stored = (await ctx.store.get(RecordType.transaction, id))!;
      await ctx.store.put(RecordType.transaction, id, {...stored.body, 'needsReview': false});
      final out = await _created(ctx, {
        'amount': 5555,
        'source': 'google_wallet',
        'capturedAt': '2026-11-04T10:05:00Z',
      });
      expect(out['result'], 'merged');
      expect(_tx(out)['id'], id);
    });

    test('never merges with a hand-typed transaction', () async {
      final ctx = _setup();
      final cat = await _newCategory(ctx, 'Food');
      await _call(
        ctx,
        'POST',
        '/v1/transactions',
        body: {'name': 'by hand', 'amount': -6666, 'categoryId': cat, 'date': '2026-11-04'},
      );
      final out = await _created(ctx, {'amount': 6666, 'capturedAt': '2026-11-04T10:02:00Z'});
      expect(out['result'], 'created');
    });

    test('never merges with a deleted capture', () async {
      final ctx = _setup();
      final first = await _created(ctx, {'amount': 5151, 'capturedAt': '2026-11-04T10:00:00Z'});
      await _call(ctx, 'DELETE', '/v1/transactions/${_tx(first)['id']}');
      final out = await _created(ctx, {'amount': 5151, 'capturedAt': '2026-11-04T10:01:00Z'});
      expect(out['result'], 'created');
    });

    test('merges a foreign-currency capture', () async {
      final ctx = _setup();
      final first = await _created(ctx, {
        'currency': 'USD',
        'amount': 8800,
        'capturedAt': '2026-11-04T10:00:00Z',
      });
      final second = await _created(ctx, {
        'currency': 'USD',
        'amount': 8800,
        'source': 'google_wallet',
        'capturedAt': '2026-11-04T10:04:00Z',
      });
      expect(second['result'], 'merged');
      expect(_tx(second)['id'], _tx(first)['id']);
    });

    test('merges into the nearest of two captures in the window', () async {
      final ctx = _setup();
      await _created(ctx, {'amount': 9100, 'capturedAt': '2026-11-04T10:00:00Z'});
      final late = await _created(ctx, {'amount': 9100, 'capturedAt': '2026-11-04T10:11:00Z'});
      final out = await _created(ctx, {'amount': 9100, 'capturedAt': '2026-11-04T10:09:00Z'});
      expect(out['result'], 'merged');
      expect(_tx(out)['id'], _tx(late)['id']);
    });
  });

  group('category', () {
    test('uses the merchant memory', () async {
      final ctx = _setup();
      final cat = await _newCategory(ctx, 'Super');
      await _learned(ctx, 'mercadona', cat);
      final out = await _created(ctx, {'merchant': 'MERCADONA 1234'});
      expect(_tx(out)['categoryId'], cat);
      expect(_category(out), {'name': 'Super', 'fallback': false});
    });

    test(
      "a branch of a learned chain gets the chain's category, the longest learned name first",
      () async {
        final ctx = _setup();
        final chain = await _newCategory(ctx, 'Super');
        final branch = await _newCategory(ctx, 'Barrio');
        await _learned(ctx, 'lidl', chain);
        final first = await _created(ctx, {
          'merchant': 'LIDL CASAL RIBEIRO',
          'capturedAt': '2026-11-04T10:00:00Z',
        });
        expect(_category(first), {'name': 'Super', 'fallback': false});
        await _learned(ctx, 'lidl casal', branch);
        final second = await _created(ctx, {
          'merchant': 'LIDL CASAL RIBEIRO',
          'amount': 4321,
          'capturedAt': '2026-11-05T10:00:00Z',
        });
        expect(_category(second), {'name': 'Barrio', 'fallback': false});
      },
    );

    test('an exact learned name wins over its chain', () async {
      final ctx = _setup();
      final chain = await _newCategory(ctx, 'Super');
      final exact = await _newCategory(ctx, 'Gasolina');
      await _learned(ctx, 'repsol', chain);
      await _learned(ctx, 'repsol estacion', exact);
      final out = await _created(ctx, {'merchant': 'REPSOL ESTACION'});
      expect(_category(out), {'name': 'Gasolina', 'fallback': false});
    });

    test('a first word under 3 letters never matches by prefix', () async {
      final ctx = _setup();
      final cat = await _newCategory(ctx, 'Bar');
      await _learned(ctx, 'el', cat);
      final out = await _created(ctx, {'merchant': 'EL CORTE INGLES'});
      expect(_category(out), {'name': 'Otros gastos', 'fallback': true});
    });

    test('ignores a remembered category of the other kind', () async {
      final ctx = _setup();
      final cat = await _newCategory(ctx, 'Salary', kind: 'income');
      await _learned(ctx, 'mercadona', cat);
      final out = await _created(ctx);
      expect(_category(out), {'name': 'Otros gastos', 'fallback': true});
    });

    test('falls back when the remembered category was archived', () async {
      final ctx = _setup();
      final cat = await _newCategory(ctx, 'Old', archived: true);
      await _learned(ctx, 'mercadona', cat);
      final out = await _created(ctx);
      expect(_category(out), {'name': 'Otros gastos', 'fallback': true});
    });

    test('falls back when the remembered category no longer exists', () async {
      final ctx = _setup();
      await _learned(ctx, 'mercadona', '0190c0de-0000-7000-8000-000000000001');
      final out = await _created(ctx);
      expect(_category(out), {'name': 'Otros gastos', 'fallback': true});
    });

    test('creates the fallback category once', () async {
      final ctx = _setup();
      final a = await _created(ctx, {'amount': 11});
      final b = await _created(ctx, {'amount': 12, 'merchant': 'Other Shop'});
      expect(_tx(a)['categoryId'], _tx(b)['categoryId']);
      final fallback = [
        for (final r in await ctx.store.list(RecordType.category))
          if (r.body['systemKey'] == 'other') r,
      ];
      expect(fallback, hasLength(1));
      expect(
        fallback.single.body,
        allOf(
          containsPair('name', 'Otros gastos'),
          containsPair('kind', 'expense'),
          containsPair('icon', '📦'),
          containsPair('color', '#8e8e9a'),
          containsPair('archivedAt', null),
        ),
      );
    });

    test('adopts an existing Otros gastos instead of a second one', () async {
      final ctx = _setup();
      final id = await _newCategory(ctx, 'Otros gastos');
      final out = await _created(ctx);
      expect(_tx(out)['categoryId'], id);
      expect(_category(out)['fallback'], true);
      expect((await ctx.store.get(RecordType.category, id))?.body['systemKey'], 'other');
    });

    test('creates a new fallback after archiving it', () async {
      final ctx = _setup();
      final first = await _created(ctx, {'amount': 11});
      final firstId = _tx(first)['categoryId']! as String;
      await _call(ctx, 'PATCH', '/v1/categories/$firstId', body: {'archived': true});
      expect((await ctx.store.get(RecordType.category, firstId))?.body['systemKey'], isNull);
      final second = await _created(ctx, {'amount': 12});
      expect(_tx(second)['categoryId'], isNot(firstId));
      expect(_category(second), {'name': 'Otros gastos', 'fallback': true});
    });

    test('names the fallback in the profile language', () async {
      final ctx = _setup(locale: 'en');
      expect(_category(await _created(ctx))['name'], 'Other expenses');
      expect(_category(await _created(ctx, {'kind': 'income'}))['name'], 'Other income');
    });
  });

  group('idempotency', () {
    test('requires an idempotency key', () async {
      final ctx = _setup();
      final res = await _capture(ctx, const {}, null);
      expect(res.status, 400);
      expect(_json(res.body)['code'], 'idempotency_key_required');
    });

    test('a retry returns the first answer', () async {
      final ctx = _setup();
      final first = await _capture(ctx, {'amount': 99}, 'retry-1');
      final second = await _capture(ctx, {'amount': 99}, 'retry-1');
      expect(first.status, 201);
      expect(second.status, 201);
      expect(_tx(_json(second.body))['id'], _tx(_json(first.body))['id']);
      expect(await ctx.store.list(RecordType.transaction), hasLength(1));
    });
  });

  group('review', () {
    Future<LocalResponse> review(Ctx ctx, List<String> ids) =>
        _call(ctx, 'POST', '/v1/transactions/review', body: {'ids': ids});
    Future<LocalResponse> patch(Ctx ctx, String id, Json body) =>
        _call(ctx, 'PATCH', '/v1/transactions/$id', body: body);

    Future<String> recategorize(Ctx ctx, String id, String categoryId) async {
      final stored = (await ctx.store.get(RecordType.transaction, id))!;
      await ctx.store.put(RecordType.transaction, id, {...stored.body, 'categoryId': categoryId});
      return id;
    }

    test('reviewing a capture row learns the merchant', () async {
      final ctx = _setup();
      final comida = await _newCategory(ctx, 'Comida');
      final first = await _created(ctx, {'merchant': 'MERCADONA 12'});
      final id = await recategorize(ctx, _tx(first)['id']! as String, comida);
      expect((await review(ctx, [id])).status, 200);
      final [memory] = await _memory(ctx);
      expect(memory.id, merchantRecordId(_userId, 'mercadona'));
      expect(memory.body, {'s': 1, 'merchantKey': 'mercadona', 'categoryId': comida});
      final next = await _created(ctx, {
        'merchant': 'MERCADONA 99',
        'amount': 777,
        'capturedAt': '2026-11-05T10:00:00Z',
      });
      expect(_category(next), {'name': 'Comida', 'fallback': false});
    });

    test('a fallback category is not learned', () async {
      final ctx = _setup();
      final first = await _created(ctx);
      expect((await review(ctx, [_tx(first)['id']! as String])).status, 200);
      expect(await _memory(ctx), isEmpty);
    });

    test('an archived category is not learned', () async {
      final ctx = _setup();
      final old = await _newCategory(ctx, 'Old');
      final first = await _created(ctx);
      final id = await recategorize(ctx, _tx(first)['id']! as String, old);
      await _call(ctx, 'PATCH', '/v1/categories/$old', body: {'archived': true});
      expect((await review(ctx, [id])).status, 200);
      expect(await _memory(ctx), isEmpty);
    });

    test('a category of the other kind is not learned', () async {
      final ctx = _setup();
      final salary = await _newCategory(ctx, 'Salary', kind: 'income');
      final first = await _created(ctx);
      final id = await recategorize(ctx, _tx(first)['id']! as String, salary);
      await review(ctx, [id]);
      expect(await _memory(ctx), isEmpty);
    });

    test('a row that was not a capture teaches nothing', () async {
      final ctx = _setup();
      final comida = await _newCategory(ctx, 'Comida');
      final made = await _call(
        ctx,
        'POST',
        '/v1/transactions',
        body: {'name': 'Mercadona', 'amount': -100, 'categoryId': comida, 'date': '2026-11-04'},
      );
      final id = _json(made.body)['id']! as String;
      final stored = (await ctx.store.get(RecordType.transaction, id))!;
      await ctx.store.put(RecordType.transaction, id, {...stored.body, 'needsReview': true});
      await review(ctx, [id]);
      expect(await _memory(ctx), isEmpty);
    });

    test('confirming a capture twice learns once and the second call changes nothing', () async {
      final ctx = _setup();
      final comida = await _newCategory(ctx, 'Comida');
      final first = await _created(ctx);
      final id = await recategorize(ctx, _tx(first)['id']! as String, comida);
      await review(ctx, [id]);
      final other = await _newCategory(ctx, 'Otra');
      await recategorize(ctx, id, other);
      await review(ctx, [id]);
      final [memory] = await _memory(ctx);
      expect(memory.body['categoryId'], comida);
    });

    test('a PATCH with needsReview false and a new categoryId learns that category', () async {
      final ctx = _setup();
      final comida = await _newCategory(ctx, 'Comida');
      final first = await _created(ctx, {'merchant': 'MERCADONA 12'});
      final res = await patch(ctx, _tx(first)['id']! as String, {
        'categoryId': comida,
        'needsReview': false,
      });
      expect(res.status, 200);
      final [memory] = await _memory(ctx);
      expect(memory.body, {'s': 1, 'merchantKey': 'mercadona', 'categoryId': comida});
    });

    test('a PATCH that does not confirm does not learn', () async {
      final ctx = _setup();
      final comida = await _newCategory(ctx, 'Comida');
      final first = await _created(ctx);
      await patch(ctx, _tx(first)['id']! as String, {'categoryId': comida});
      expect(await _memory(ctx), isEmpty);
    });

    test('a renamed row still teaches the merchant as notified', () async {
      final ctx = _setup();
      final comida = await _newCategory(ctx, 'Comida');
      final first = await _created(ctx, {'merchant': 'MERCADONA 12'});
      await patch(ctx, _tx(first)['id']! as String, {
        'name': 'Compra del mes',
        'categoryId': comida,
        'needsReview': false,
      });
      final [memory] = await _memory(ctx);
      expect(memory.body['merchantKey'], 'mercadona');
    });

    test('a row stored without a key teaches by its name', () async {
      final ctx = _setup();
      final comida = await _newCategory(ctx, 'Comida');
      final first = await _created(ctx, {'merchant': 'MERCADONA 12'});
      final id = _tx(first)['id']! as String;
      final stored = (await ctx.store.get(RecordType.transaction, id))!;
      await ctx.store.put(RecordType.transaction, id, {
        ...stored.body,
        'captureMerchantKey': null,
        'categoryId': comida,
      });
      await review(ctx, [id]);
      final [memory] = await _memory(ctx);
      expect(memory.body['merchantKey'], 'mercadona');
    });

    test('a merchant with nothing alphanumeric is skipped', () async {
      final ctx = _setup();
      final comida = await _newCategory(ctx, 'Comida');
      final first = await _created(ctx, {'merchant': '***'});
      final id = await recategorize(ctx, _tx(first)['id']! as String, comida);
      expect((await review(ctx, [id])).status, 200);
      expect(await _memory(ctx), isEmpty);
    });
  });
}
