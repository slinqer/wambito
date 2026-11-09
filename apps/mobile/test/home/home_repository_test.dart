import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/client.dart';
import 'package:wambito/home/home_repository.dart';

const _transaction = {
  'id': 't1',
  'name': 'Arriendo',
  'amount': -50000000,
  'currency': 'COP',
  'date': '2026-10-25',
  'status': 'paid',
  'note': null,
  'categoryId': 'c1',
  'recurrenceId': null,
  'importId': null,
  'needsReview': false,
  'source': 'app',
  'createdAt': '2026-10-01T10:00:00.000Z',
  'updatedAt': '2026-10-01T10:00:00.000Z',
};

/// Answers by method and path, remembers every request, and fails when told to.
class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int? status;
  bool noAnswer = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (noAnswer) {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    final Object? body = switch ((options.method, options.path)) {
      ('GET', '/v1/me') => {
        'id': 'u1',
        'email': 'a@b.co',
        'timezone': 'America/Bogota',
        'locale': 'es',
        'onboardingCompletedAt': null,
        'currency': 'COP',
        'isAnonymous': true,
        'encryption': 'plain',
      },
      ('GET', '/v1/summary') => {
        'month': '2026-10',
        'budgetTotal': 100,
        'spent': 40,
        'remaining': 60,
        'income': 0,
        'balance': -40,
        'categories': <Object>[],
      },
      ('GET', '/v1/categories') => [
        {
          'id': 'c1',
          'name': 'Mercado',
          'kind': 'expense',
          'icon': '🛒',
          'color': '#2fd388',
          'sortOrder': 0,
          'archived': false,
          'currentBudget': null,
        },
      ],
      ('GET', '/v1/transactions') => {
        'items': [_transaction],
        'nextCursor': 'abc',
      },
      ('DELETE', _) => null,
      (_, _) => _transaction,
    };
    if (status != null) {
      return ResponseBody.fromString('{}', status!, headers: _json);
    }
    if (body == null) return ResponseBody.fromString('', 204);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: _json);
  }

  static const _json = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Adapter adapter;
  late ApiHomeRepository repo;
  setUp(() {
    final client = ApiClient.forServer(Uri.parse('https://example.test'), token: 'tok');
    adapter = _Adapter();
    client.dio.httpClientAdapter = adapter;
    repo = ApiHomeRepository(client.api.getDefaultApi());
  });

  test('reads the profile, the month summary and every category (archived too)', () async {
    final profile = await repo.profile();
    expect((profile.currency, profile.timezone), ('COP', 'America/Bogota'));
    expect((await repo.summary('2026-10')).remaining, 60);
    expect((await repo.categories()).single.name, 'Mercado');
    expect(adapter.requests[1].queryParameters, {'month': '2026-10'});
    expect(adapter.requests[2].queryParameters, {'includeArchived': 'true'});
  });

  test('pages the month: a page size, then the cursor', () async {
    final first = await repo.transactions('2026-10');
    expect(first.items.single.name, 'Arriendo');
    expect(first.nextCursor, 'abc');
    await repo.transactions('2026-10', cursor: 'abc');
    expect(adapter.requests[0].queryParameters, {
      'month': '2026-10',
      'limit': transactionsPageSize,
    });
    expect(adapter.requests[1].queryParameters, {
      'month': '2026-10',
      'cursor': 'abc',
      'limit': transactionsPageSize,
    });
  });

  test('asks whether there is any transaction at all: one, in no month in particular', () async {
    expect(await repo.hasTransactions(), isTrue);
    expect(adapter.requests.single.queryParameters, {'limit': 1});
  });

  test('deletes, restores and marks paid with the right calls', () async {
    await repo.delete('t1');
    final back = await repo.restore('t1');
    final paid = await repo.markPaid('t1');
    expect(back.id, 't1');
    expect(paid.id, 't1');
    expect(adapter.requests.map((r) => '${r.method} ${r.path}'), [
      'DELETE /v1/transactions/t1',
      'POST /v1/transactions/t1/restore',
      'PATCH /v1/transactions/t1',
    ]);
    expect(jsonDecode(jsonEncode(adapter.requests[2].data)), {'status': 'paid'});
    expect(adapter.requests[0].headers['Authorization'], 'Bearer tok');
  });

  test('a refusal carries its status; no answer at all is status 0 (offline)', () async {
    adapter.status = 500;
    await expectLater(
      repo.summary('2026-10'),
      throwsA(isA<HomeFailure>().having((f) => f.status, 'status', 500)),
    );
    adapter.status = 401;
    await expectLater(
      repo.delete('t1'),
      throwsA(isA<HomeFailure>().having((f) => f.unauthorized, 'unauthorized', true)),
    );
    adapter.status = null;
    adapter.noAnswer = true;
    await expectLater(
      repo.profile(),
      throwsA(isA<HomeFailure>().having((f) => f.offline, 'offline', true)),
    );
  });
}
