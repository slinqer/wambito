import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/client.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/search/search_repository.dart';

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

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int? status;
  bool withTotals = true;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (status != null) return ResponseBody.fromString('{}', status!, headers: _json);
    final body = {
      'items': [_transaction],
      'nextCursor': 'abc',
      if (withTotals) 'totals': {'count': 12, 'expense': 340000, 'income': 5000},
    };
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
  late ApiSearchRepository repo;
  late ApiClient client;
  setUp(() {
    client = ApiClient.forServer(Uri.parse('https://example.test'), token: 'tok');
    adapter = _Adapter();
    client.dio.httpClientAdapter = adapter;
    repo = ApiSearchRepository(client.api.getDefaultApi());
  });

  test('sends the trimmed text as one q, repeated category, kind, status and totals', () async {
    final page = await repo.search(
      const SearchFilters(
        text: '  cafe con leche ',
        kind: SearchKind.expense,
        categoryIds: {'c1', 'c2'},
        status: SearchStatus.pending,
      ),
    );
    final q = adapter.requests.single.uri.queryParametersAll;
    expect(q['q'], ['cafe con leche']);
    expect(q['category'], ['c1', 'c2']);
    expect(q['kind'], ['expense']);
    expect(q['status'], ['pending']);
    expect(q['totals'], ['true']);
    expect(q['limit'], ['50']);
    expect(q.containsKey('month'), isFalse);
    expect(q.containsKey('cursor'), isFalse);
    expect(page.items.single.name, 'Arriendo');
    expect(page.nextCursor, 'abc');
    expect((page.totals!.count, page.totals!.expense, page.totals!.income), (12, 340000, 5000));
  });

  test('omits what is "all" or empty and sends the cursor when given', () async {
    await repo.search(const SearchFilters(text: 'cafe'), cursor: 'abc');
    final q = adapter.requests.single.uri.queryParametersAll;
    expect(q['q'], ['cafe']);
    expect(q['cursor'], ['abc']);
    expect(q.containsKey('category'), isFalse);
    expect(q.containsKey('kind'), isFalse);
    expect(q.containsKey('status'), isFalse);
  });

  test('sends no q for blank text', () async {
    await repo.search(const SearchFilters(text: '   ', kind: SearchKind.income));
    final q = adapter.requests.single.uri.queryParametersAll;
    expect(q.containsKey('q'), isFalse);
    expect(q['kind'], ['income']);
  });

  test('totals are null when the server sends none', () async {
    adapter.withTotals = false;
    final page = await repo.search(const SearchFilters(text: 'x'));
    expect(page.totals, isNull);
  });

  test('a failed call becomes a HomeFailure', () async {
    adapter.status = 500;
    await expectLater(
      repo.search(const SearchFilters(text: 'x')),
      throwsA(isA<HomeFailure>().having((f) => f.status, 'status', 500)),
    );
  });

  test('isSearching is false for blank text without filters, true otherwise', () {
    expect(const SearchFilters(text: '  ').isSearching, isFalse);
    expect(const SearchFilters().isSearching, isFalse);
    expect(const SearchFilters(text: 'a').isSearching, isTrue);
    expect(const SearchFilters(kind: SearchKind.expense).isSearching, isTrue);
    expect(const SearchFilters(categoryIds: {'c1'}).isSearching, isTrue);
    expect(const SearchFilters(status: SearchStatus.paid).isSearching, isTrue);
  });

  test('filters have value equality', () {
    expect(
      const SearchFilters(text: 'a', categoryIds: {'c1', 'c2'}),
      SearchFilters(text: 'a', categoryIds: {'c2', 'c1'}),
    );
    expect(const SearchFilters(text: 'a').hashCode, const SearchFilters(text: 'a').hashCode);
    expect(const SearchFilters(text: 'a') == const SearchFilters(text: 'b'), isFalse);
  });
}
