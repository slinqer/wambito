// Ports apps/web/app/local/backend.test.ts: the local backend over the memory store.
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/core/records.dart' show Json;
import 'package:wambito/crypto/records.dart' show RecordType;
import 'package:wambito/local/backend.dart';
import 'package:wambito/local/ids.dart';
import 'package:wambito/local/memory_store.dart';
import 'package:wambito/local/store.dart';

final _v7 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
final _now = DateTime.utc(2026, 10, 21, 18);
const _includeDeleted = ReadOptions(includeDeleted: true);

class Api {
  Api(this.backend);
  final LocalBackend backend;

  Future<LocalResponse> call(
    String method,
    String path, {
    Map<String, Object> query = const {},
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    final res = await backend.handle(method, path, query, body, headers: headers);
    if (res == null) throw StateError('not served: $method $path');
    return res;
  }

  /// A 2xx answer's body; throws on a refusal (the web's client rejects on a 4xx).
  Future<Object?> ok(
    String method,
    String path, {
    Map<String, Object> query = const {},
    Object? body,
  }) async {
    final res = await call(method, path, query: query, body: body);
    if (res.status >= 400) throw StateError('$method $path -> ${res.status} ${res.body}');
    return res.body;
  }
}

typedef Ctx = ({FinanceStore store, Api api});

Ctx setup({List<UnavailableRoute> unavailable = const []}) {
  final store = createMemoryStore();
  final backend = createLocalBackend(
    store: store,
    now: () => _now,
    unavailable: unavailable,
    timezone: 'UTC',
  );
  return (store: store, api: Api(backend));
}

Future<String> onboard(Api api) async {
  await api.ok(
    'PATCH',
    '/v1/me',
    body: {
      'currency': 'COP',
      'locale': 'es',
      'timezone': 'America/Bogota',
      'onboardingCompleted': true,
    },
  );
  final food = await api.ok(
    'POST',
    '/v1/categories',
    body: {'name': 'Food', 'kind': 'expense', 'icon': 'fork', 'color': '#f90'},
  ) as Map;
  return food['id'] as String;
}

Json _body(Object? o) => (o! as Map).cast<String, Object?>();
List<Json> _items(Object? o) => [for (final i in (_body(o)['items'] as List)) _body(i)];

void main() {
  group('createLocalBackend over the memory store', () {
    test('starts as a fresh account and keeps its settings as a record', () async {
      final (:store, :api) = setup();
      expect(_body(await api.ok('GET', '/v1/me')), containsPair('onboardingCompletedAt', null));
      await onboard(api);
      final [settings] = await store.list(RecordType.settings);
      expect(settings.id, matches(_v7));
      expect(settings.body, containsPair('currency', 'COP'));
      expect(settings.body, containsPair('timezone', 'America/Bogota'));
      final me = _body(await api.ok('GET', '/v1/me'));
      expect(me, containsPair('currency', 'COP'));
      expect(me, containsPair('locale', 'es'));
    });

    test('makes records with lower-case UUID v7 ids, written through the store', () async {
      final (:store, :api) = setup();
      final food = await onboard(api);
      expect(food, matches(_v7));
      final created = _body(
        await api.ok(
          'POST',
          '/v1/transactions',
          body: {'name': 'Lunch', 'amount': -1800000, 'categoryId': food, 'date': '2026-10-21'},
        ),
      );
      final id = created['id'] as String;
      expect(id, matches(_v7));
      expect(id.compareTo(food) > 0, true);
      final stored = await store.get(RecordType.transaction, id);
      expect(stored?.body, containsPair('s', 1));
      expect(stored?.body, containsPair('name', 'Lunch'));
      expect(stored?.body, containsPair('currency', 'COP'));
      expect(stored?.body, containsPair('source', 'app'));
    });

    test('deletes to a tombstone and restores', () async {
      final (:store, :api) = setup();
      final food = await onboard(api);
      final id =
          _body(
                await api.ok(
                  'POST',
                  '/v1/transactions',
                  body: {
                    'name': 'Lunch',
                    'amount': -100000,
                    'categoryId': food,
                    'date': '2026-10-21',
                  },
                ),
              )['id']
              as String;
      await api.ok('DELETE', '/v1/transactions/$id');
      expect(await store.get(RecordType.transaction, id), isNull);
      expect((await store.get(RecordType.transaction, id, _includeDeleted))?.deleted, true);
      await api.ok('POST', '/v1/transactions/$id/restore');
      expect((await store.get(RecordType.transaction, id))?.deleted, false);
    });

    Future<({Ctx ctx, String food, String ruleId, Future<List<Json>> Function(String) month})>
    ruleWithOctober() async {
      final ctx = setup();
      final food = await onboard(ctx.api);
      final rule = _body(
        await ctx.api.ok(
          'POST',
          '/v1/recurrences',
          body: {
            'name': 'Rent',
            'amount': -50000000,
            'categoryId': food,
            'frequency': 'monthly',
            'dayOfMonth': 5,
            'startDate': '2026-09-05',
          },
        ),
      );
      final ruleId = rule['id'] as String;
      Future<List<Json>> month(String m) async => [
        for (final t in _items(await ctx.api.ok('GET', '/v1/transactions', query: {'month': m})))
          if (t['recurrenceId'] == ruleId) t,
      ];
      return (ctx: ctx, food: food, ruleId: ruleId, month: month);
    }

    test(
      "names a recurrence's occurrences by UUID v5 of the rule, the month and the revision",
      () async {
        final r = await ruleWithOctober();
        final data = _items(
          await r.ctx.api.ok('GET', '/v1/transactions', query: {'month': '2026-10'}),
        );
        final occurrence = data.firstWhere((t) => t['recurrenceId'] == r.ruleId);
        expect(occurrence['status'], 'pending');
        expect(occurrence['id'], uuidv5(r.ruleId, '2026-10:0'));
        final stored = await r.ctx.store.get(RecordType.transaction, occurrence['id']! as String);
        expect(stored?.body, containsPair('occurrenceMonth', '2026-10'));
        expect(stored?.body, containsPair('source', 'recurrence'));
        // Reading again makes no second one.
        expect((await r.month('2026-10')).length, 1);
      },
    );

    test("bumps the rule's rev on an edit: the pending occurrences are tombstoned and come back under new ids", () async {
      final r = await ruleWithOctober();
      final before = (await r.month('2026-10')).first;
      expect((await r.ctx.store.get(RecordType.recurrence, r.ruleId))?.body['rev'], 0);
      await r.ctx.api.ok('PATCH', '/v1/recurrences/${r.ruleId}', body: {'amount': -60000000});
      expect((await r.ctx.store.get(RecordType.recurrence, r.ruleId))?.body['rev'], 1);
      expect(
        (await r.ctx.store.get(
          RecordType.transaction,
          before['id']! as String,
          _includeDeleted,
        ))?.deleted,
        true,
      );
      final after = await r.month('2026-10');
      expect(after.length, 1);
      expect(after[0]['id'], uuidv5(r.ruleId, '2026-10:1'));
      expect(after[0]['amount'], -60000000);
    });

    test('keeps a deleted occurrence deleted across an edit', () async {
      final r = await ruleWithOctober();
      final occ = (await r.month('2026-10')).first;
      await r.ctx.api.ok('DELETE', '/v1/transactions/${occ['id']}');
      expect(await r.month('2026-10'), isEmpty);
      await r.ctx.api.ok('PATCH', '/v1/recurrences/${r.ruleId}', body: {'amount': -60000000});
      expect(await r.month('2026-10'), isEmpty);
    });

    test('keeps a paid occurrence and makes no second one after an edit', () async {
      final r = await ruleWithOctober();
      final occ = (await r.month('2026-10')).first;
      await r.ctx.api.ok('PATCH', '/v1/transactions/${occ['id']}', body: {'status': 'paid'});
      await r.ctx.api.ok('PATCH', '/v1/recurrences/${r.ruleId}', body: {'amount': -60000000});
      expect([for (final t in await r.month('2026-10')) t['id']], [occ['id']]);
    });

    test('stamps updatedAt on create and on PATCH', () async {
      final r = await ruleWithOctober();
      final id =
          _body(
                await r.ctx.api.ok(
                  'POST',
                  '/v1/transactions',
                  body: {
                    'name': 'Lunch',
                    'amount': -100000,
                    'categoryId': r.food,
                    'date': '2026-10-21',
                  },
                ),
              )['id']
              as String;
      expect(
        (await r.ctx.store.get(RecordType.transaction, id))?.body['updatedAt'],
        '2026-10-21T18:00:00.000Z',
      );
      final patched = _body(
        await r.ctx.api.ok('PATCH', '/v1/transactions/$id', body: {'name': 'Dinner'}),
      );
      expect(patched['updatedAt'], '2026-10-21T18:00:00.000Z');
    });

    test('leaves the store untouched when a request is refused', () async {
      final (:store, :api) = setup();
      await onboard(api);
      final before = await store.list(RecordType.transaction, _includeDeleted);
      final res = await api.call(
        'POST',
        '/v1/transactions',
        body: {
          'name': 'Bad',
          'amount': -100,
          'categoryId': '01930000-0000-7000-8000-0000000000ff',
          'date': '2026-10-21',
        },
      );
      expect(res.status, 422);
      final after = await store.list(RecordType.transaction, _includeDeleted);
      expect(
        [for (final r in after) (r.id, r.body, r.deleted)],
        [for (final r in before) (r.id, r.body, r.deleted)],
      );
    });

    test("notifies the store's subscribers after a write, not after a read", () async {
      final (:store, :api) = setup();
      var calls = 0;
      store.subscribe(() => calls++);
      await api.ok('GET', '/v1/categories');
      expect(calls, 0);
      await onboard(api);
      expect(calls, greaterThan(0));
    });

    test('answers 403 demo_unavailable only for the routes it is told to', () async {
      final open = setup();
      expect((await open.api.backend.handle('GET', '/v1/me/export', {}, null))?.status, isNot(403));
      final closed = setup(unavailable: localUnavailable);
      final res = await closed.api.call('GET', '/v1/me/export');
      expect(res.status, 403);
      expect(_body(res.body), containsPair('code', 'demo_unavailable'));
      expect((await closed.api.call('GET', '/v1/imports/abc')).status, 403);
      expect((await closed.api.call('POST', '/v1/me/assistants/x')).status, 403);
      // The account itself goes to the network: not served here, in either setup.
      expect(await closed.api.backend.handle('DELETE', '/v1/me', {}, null), isNull);
      expect(_body(await closed.api.ok('GET', '/v1/me')), isNotEmpty);
    });
  });

  group('POST /v1/transactions/review', () {
    Future<String> toReview(Ctx c, String food, String name) async {
      final id =
          _body(
                await c.api.ok(
                  'POST',
                  '/v1/transactions',
                  body: {'name': name, 'amount': -500000, 'categoryId': food, 'date': '2026-10-21'},
                ),
              )['id']
              as String;
      final found = await c.store.get(RecordType.transaction, id);
      if (found == null) throw StateError('not saved');
      await c.store.transaction(
        (s) => s.put(RecordType.transaction, id, {...found.body, 'needsReview': true}),
      );
      return id;
    }

    test('confirms every id at once and answers them in request order', () async {
      final c = setup();
      final food = await onboard(c.api);
      final a = await toReview(c, food, 'A');
      final b = await toReview(c, food, 'B');
      final res = await c.api.call(
        'POST',
        '/v1/transactions/review',
        body: {
          'ids': [b, a, b],
        },
      );
      expect(res.status, 200);
      expect(
        [
          for (final t in _items(res.body)) [t['id'], t['needsReview']],
        ],
        [
          [b, false],
          [a, false],
          [b, false],
        ],
      );
      expect((await c.store.get(RecordType.transaction, a))?.body['needsReview'], false);
    });

    test('is all or nothing: an unknown or deleted id is 404 and nothing changes', () async {
      final c = setup();
      final food = await onboard(c.api);
      final a = await toReview(c, food, 'A');
      final gone = await toReview(c, food, 'Gone');
      await c.api.ok('DELETE', '/v1/transactions/$gone');
      for (final other in [gone, '0193a000-0000-7000-8000-0000000000ff']) {
        final res = await c.api.call(
          'POST',
          '/v1/transactions/review',
          body: {
            'ids': [a, other],
          },
        );
        expect(res.status, 404);
        expect(_body(res.body), containsPair('code', 'not_found'));
      }
      expect((await c.store.get(RecordType.transaction, a))?.body['needsReview'], true);
    });

    test('validates like the API (1 to 50 uuids)', () async {
      final c = setup();
      await onboard(c.api);
      final res = await c.api.call('POST', '/v1/transactions/review', body: {'ids': <String>[]});
      expect(res.status, 422);
      expect(_body(res.body), containsPair('code', 'validation_failed'));
    });
  });

  // Hand-written from apps/api/src/routes/transactions.ts and apps/api/test/batch.test.ts: the web's
  // backend has no batch routes, so there is no recorded answer.
  group('POST /v1/transactions/batch and /batch-delete (quick capture)', () {
    var n = 0;
    Map<String, String> key() => {'Idempotency-Key': 'batch-key-${++n}'};
    Json item(String category, String name, int amount, [Json extra = const {}]) => {
      'name': name,
      'amount': amount,
      'categoryId': category,
      'date': '2026-10-21',
      ...extra,
    };
    Future<List<StoredRecord>> live(Ctx c) => c.store.list(RecordType.transaction);

    test('saves 2 items in one call, in request order, with the single create\'s shape', () async {
      final c = setup();
      final food = await onboard(c.api);
      final res = await c.api.call(
        'POST',
        '/v1/transactions/batch',
        headers: key(),
        body: {
          'items': [
            item(food, 'cinema', -95000),
            item(food, 'rent', -400000, {'source': 'widget'}),
          ],
        },
      );
      expect(res.status, 201);
      final items = _items(res.body);
      expect(items.length, 2);
      expect(items[0], containsPair('name', 'cinema'));
      expect(items[0], containsPair('currency', 'COP'));
      expect(items[0], containsPair('source', 'app'));
      expect(items[1], containsPair('source', 'widget'));
      expect(items[0]['id'], matches(_v7));
      expect((await live(c)).length, 2);
    });

    test('all or nothing: an unknown or archived category in item 2 saves neither', () async {
      final c = setup();
      final food = await onboard(c.api);
      final res = await c.api.call(
        'POST',
        '/v1/transactions/batch',
        headers: key(),
        body: {
          'items': [
            item(food, 'first', -100),
            item('00000000-0000-4000-8000-000000000000', 'second', -200),
          ],
        },
      );
      expect(res.status, 422);
      expect(_body(res.body), containsPair('code', 'category_not_found'));
      expect(await live(c), isEmpty);
    });

    test('replaying the same Idempotency-Key returns the same items and creates nothing', () async {
      final c = setup();
      final food = await onboard(c.api);
      final headers = key();
      final items = [item(food, 'replayed one', -111), item(food, 'replayed two', -222)];
      final first = await c.api.call(
        'POST',
        '/v1/transactions/batch',
        headers: headers,
        body: {'items': items},
      );
      final second = await c.api.call(
        'POST',
        '/v1/transactions/batch',
        headers: headers,
        body: {'items': items},
      );
      expect(second.status, 201);
      expect(second.body, first.body);
      expect((await live(c)).length, 2);
      final other = await c.api.call(
        'POST',
        '/v1/transactions/batch',
        headers: headers,
        body: {
          'items': [item(food, 'different', -1)],
        },
      );
      expect(other.status, 422);
      expect(_body(other.body), containsPair('code', 'idempotency_key_reused'));
    });

    test(
      'a batch without an Idempotency-Key is refused with 400 idempotency_key_required',
      () async {
        final c = setup();
        final food = await onboard(c.api);
        final res = await c.api.call(
          'POST',
          '/v1/transactions/batch',
          body: {
            'items': [item(food, 'no key', -100)],
          },
        );
        expect(res.status, 400);
        expect(_body(res.body), containsPair('code', 'idempotency_key_required'));
        expect(await live(c), isEmpty);
      },
    );

    test('21 items are refused, and so is an empty list; 20 are fine', () async {
      final c = setup();
      final food = await onboard(c.api);
      final many = [for (var i = 0; i < 21; i++) item(food, 'bulk $i', -1)];
      expect(
        (await c.api.call(
          'POST',
          '/v1/transactions/batch',
          headers: key(),
          body: {'items': many},
        )).status,
        422,
      );
      expect(
        (await c.api.call(
          'POST',
          '/v1/transactions/batch',
          headers: key(),
          body: {'items': <Json>[]},
        )).status,
        422,
      );
      expect(await live(c), isEmpty);
      final ok = await c.api.call(
        'POST',
        '/v1/transactions/batch',
        headers: key(),
        body: {'items': many.take(20).toList()},
      );
      expect(ok.status, 201);
    });

    test('an item is validated like a single create, repeat refinement included', () async {
      final c = setup();
      final food = await onboard(c.api);
      final res = await c.api.call(
        'POST',
        '/v1/transactions/batch',
        headers: key(),
        body: {
          'items': [
            item(food, 'ok', -1),
            item(food, '', -1, {
              'repeat': {'frequency': 'monthly', 'endDate': '2026-01-01'},
            }),
          ],
        },
      );
      expect(res.status, 422);
      final paths = [for (final e in (_body(res.body)['errors'] as List)) (e as Map)['path']];
      expect(paths, containsAll(['items.1.name', 'items.1.repeat.endDate']));
    });

    test('an item with repeat makes its recurrence, as a single create does', () async {
      final c = setup();
      final food = await onboard(c.api);
      final res = await c.api.call(
        'POST',
        '/v1/transactions/batch',
        headers: key(),
        body: {
          'items': [
            item(food, 'Netflix', -30000, {
              'repeat': {'frequency': 'monthly'},
            }),
          ],
        },
      );
      expect(res.status, 201);
      expect((await c.store.list(RecordType.recurrence)).length, 1);
      expect(_items(res.body).single['recurrenceId'], isNotNull);
    });

    test('batch-delete soft-deletes the live ones and ignores unknown or deleted ids', () async {
      final c = setup();
      final food = await onboard(c.api);
      final saved = _items(
        (await c.api.call(
          'POST',
          '/v1/transactions/batch',
          headers: key(),
          body: {
            'items': [item(food, 'del 1', -1), item(food, 'del 2', -2), item(food, 'keep', -3)],
          },
        )).body,
      );
      final res = await c.api.call(
        'POST',
        '/v1/transactions/batch-delete',
        body: {
          'ids': [saved[0]['id'], saved[1]['id'], '00000000-0000-4000-8000-000000000000'],
        },
      );
      expect(res.status, 204);
      expect([for (final r in await live(c)) r.id], [saved[2]['id']]);
      // Soft: the single restore brings one back.
      await c.api.ok('POST', '/v1/transactions/${saved[0]['id']}/restore');
      expect((await live(c)).length, 2);
      expect(
        (await c.api.call(
          'POST',
          '/v1/transactions/batch-delete',
          body: {
            'ids': [saved[1]['id']],
          },
        )).status,
        204,
      );
    });

    test('batch-delete refuses 0 or 21 ids', () async {
      final c = setup();
      await onboard(c.api);
      expect(
        (await c.api.call(
          'POST',
          '/v1/transactions/batch-delete',
          body: {'ids': <String>[]},
        )).status,
        422,
      );
      final ids = [
        for (var i = 0; i < 21; i++) '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
      ];
      expect(
        (await c.api.call('POST', '/v1/transactions/batch-delete', body: {'ids': ids})).status,
        422,
      );
    });
  });

  group('failures', () {
    test('a multipart import is 403 before its body is read', () async {
      final c = setup(unavailable: localUnavailable);
      final res = await c.api.call('POST', '/v1/imports', body: Object());
      expect(res.status, 403);
      expect(_body(res.body), containsPair('code', 'demo_unavailable'));
    });

    test('a non-JSON body on a served route is a 400', () async {
      final c = setup();
      final res = await c.api.call('POST', '/v1/categories', body: Object());
      expect(res.status, 400);
    });

    test('a bug inside is a 500 problem, not an escaped exception', () async {
      final backend = createLocalBackend(store: _BrokenStore(), now: () => _now);
      final res = await backend.handle('GET', '/v1/categories', {}, null);
      expect(res?.status, 500);
      expect(_body(res?.body), containsPair('code', 'internal_error'));
    });
  });
}

class _BrokenStore implements FinanceStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('broken');
}
