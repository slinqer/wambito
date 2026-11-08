import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/client.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/categories/categories_repository.dart';
import 'package:wambito/categories/category_model.dart';
import 'package:wambito/home/home_repository.dart';

const _category = {
  'id': 'c1',
  'name': 'Mascotas',
  'kind': 'expense',
  'icon': '🐶',
  'color': '#3fa7ff',
  'sortOrder': 0,
  'archived': false,
  'currentBudget': null,
};

/// Answers by method and path, remembers every request (and its body), and fails when told to.
class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;
  String? code;
  bool noAnswer = false;
  List<Object?> transactions = const [];

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
    final Object? body = status >= 400
        ? {'code': code ?? 'internal_error'}
        : switch ((options.method, options.path)) {
            ('POST', '/v1/categories') => _category,
            ('PATCH', '/v1/categories/c1') => _category,
            ('GET', '/v1/transactions') => {'items': transactions, 'nextCursor': null},
            ('GET', '/v1/recurrences') => [
              {
                'id': 'r1',
                'name': 'Spotify',
                'amount': -3500,
                'categoryId': 'c1',
                'frequency': 'monthly',
                'dayOfMonth': 2,
                'monthOfYear': null,
                'startDate': '2026-01-01',
                'endDate': null,
              },
            ],
            _ => null,
          };
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(CategoriesRepository, _Adapter) _make() {
  final adapter = _Adapter();
  final client = ApiClient.forServer(Uri.parse('https://example.test'), token: 'tok')
    ..dio.httpClientAdapter = adapter;
  return (ApiCategoriesRepository(client.api.getDefaultApi()), adapter);
}

void main() {
  test('creating sends the name, kind, emoji and colour', () async {
    final (repo, adapter) = _make();
    await repo.create(
      const NewCategory(
        name: 'Mascotas',
        glyph: '🐶',
        tint: '#3fa7ff',
        kind: CategoryKindEnum.income,
      ),
    );
    final request = adapter.requests.single;
    expect((request.method, request.path), ('POST', '/v1/categories'));
    expect(request.data, {'name': 'Mascotas', 'kind': 'income', 'icon': '🐶', 'color': '#3fa7ff'});
  });

  test('changing sends only what changed', () async {
    final (repo, adapter) = _make();
    await repo.update('c1', name: 'Pets', icon: '🎁');
    expect(adapter.requests.single.data, {'name': 'Pets', 'icon': '🎁'});
    adapter.requests.clear();
    await repo.update('c1', archived: true);
    expect(adapter.requests.single.data, {'archived': true});
    adapter.requests.clear();
    await repo.update('c1', kind: CategoryKindEnum.income, archived: false);
    expect(adapter.requests.single.data, {'kind': 'income', 'archived': false});
  });

  test('the API\'s refusal arrives with its code', () async {
    final (repo, adapter) = _make();
    adapter
      ..status = 409
      ..code = 'category_name_taken';
    await expectLater(
      repo.update('c1', name: 'Hogar'),
      throwsA(
        isA<HomeFailure>()
            .having((f) => f.status, 'status', 409)
            .having((f) => f.code, 'code', 'category_name_taken'),
      ),
    );
  });

  test('no answer at all is an offline failure', () async {
    final (repo, adapter) = _make();
    adapter.noAnswer = true;
    await expectLater(
      repo.create(NewCategory.blank()),
      throwsA(isA<HomeFailure>().having((f) => f.offline, 'offline', true)),
    );
  });

  test('a category has transactions when one page of them is not empty', () async {
    final (repo, adapter) = _make();
    expect(await repo.hasTransactions('c1'), isFalse);
    expect(adapter.requests.single.queryParameters, {
      'category': isA<ListParam>().having((p) => p.value, 'value', ['c1']),
      'limit': 200,
    });
    adapter.transactions = [
      {
        'id': 't1',
        'name': 'Pienso',
        'amount': -1000,
        'currency': 'COP',
        'date': '2026-10-01',
        'status': 'paid',
        'note': null,
        'categoryId': 'c1',
        'recurrenceId': null,
        'importId': null,
        'needsReview': false,
        'source': 'app',
        'createdAt': '2026-10-01T10:00:00.000Z',
        'updatedAt': '2026-10-01T10:00:00.000Z',
      },
    ];
    expect(await repo.hasTransactions('c1'), isTrue);
  });

  test('the recurring payments are the account\'s', () async {
    final (repo, _) = _make();
    final rules = await repo.recurrences();
    expect([for (final r in rules) r.name], ['Spotify']);
  });
}
