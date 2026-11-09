import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/client.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/welcome/onboarding_repository.dart';

/// What the welcome sends the API, as the API reads it (apps/api routes/me.ts, categories.ts).
class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final bodies = <String>[];
  int status = 200;
  Object? reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    bodies.add(utf8.decode(bytes));
    return ResponseBody.fromString(
      jsonEncode(reply ?? _profile),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _profile = {
  'id': 'u1',
  'email': 'ana@example.com',
  'timezone': 'UTC',
  'locale': 'es',
  'onboardingCompletedAt': null,
  'currency': 'EUR',
  'isAnonymous': false,
  'encryption': 'plain',
};

const _category = {
  'id': 'c1',
  'name': 'Supermercado',
  'kind': 'expense',
  'icon': '🛒',
  'color': '#ff9f1c',
  'sortOrder': 0,
  'archived': false,
  'currentBudget': null,
};

void main() {
  late _Adapter adapter;
  late ApiOnboardingRepository repo;

  setUp(() {
    final client = ApiClient.forServer(Uri.parse('https://example.test'), token: 'tok');
    adapter = _Adapter();
    client.dio.httpClientAdapter = adapter;
    repo = ApiOnboardingRepository(client.api.getDefaultApi(), client.dio);
  });

  dynamic sent() => jsonDecode(adapter.bodies.single);

  group('PATCH /v1/me', () {
    test('the onboarding flag goes as the boolean true, which is what the API reads', () async {
      await repo.patchMe(onboardingCompleted: true);
      expect(adapter.requests.single.method, 'PATCH');
      expect(adapter.requests.single.path, '/v1/me');
      expect(sent(), {'onboardingCompleted': true});
    });

    test('the currency and the time zone go alone, and what is not given is not sent', () async {
      await repo.patchMe(currency: 'COP');
      expect(sent(), {'currency': 'COP'});
      adapter.bodies.clear();
      adapter.requests.clear();
      await repo.patchMe(timezone: 'America/Bogota');
      expect(sent(), {'timezone': 'America/Bogota'});
    });

    test('a refusal is a failure with the API\'s code', () async {
      adapter
        ..status = 409
        ..reply = {'code': 'currency_locked'};
      await expectLater(
        repo.patchMe(currency: 'USD'),
        throwsA(
          isA<HomeFailure>()
              .having((f) => f.status, 'status', 409)
              .having((f) => f.code, 'code', 'currency_locked'),
        ),
      );
    });
  });

  group('categories', () {
    test('a suggestion is created with its place in the list', () async {
      adapter.reply = _category;
      await repo.createCategory(
        name: 'Supermercado',
        kind: CategoryKindEnum.expense,
        icon: '🛒',
        color: '#ff9f1c',
        sortOrder: 0,
      );
      expect(adapter.requests.single.path, '/v1/categories');
      expect(sent(), {
        'name': 'Supermercado',
        'kind': 'expense',
        'icon': '🛒',
        'color': '#ff9f1c',
        'sortOrder': 0,
      });
    });

    test('an edit sends only what changed', () async {
      adapter.reply = _category;
      await repo.updateCategory('c1', archived: true);
      expect(adapter.requests.single.method, 'PATCH');
      expect(adapter.requests.single.path, '/v1/categories/c1');
      expect(sent(), {'archived': true});
    });

    test('every category is asked for, archived ones too', () async {
      adapter.reply = [_category];
      final all = await repo.allCategories();
      expect(all.single.name, 'Supermercado');
      expect(adapter.requests.single.queryParameters, {'includeArchived': 'true'});
    });

    test('a category\'s transactions are counted in pages of 200, in any month', () async {
      adapter.reply = {'items': [], 'nextCursor': null};
      await repo.categoryTransactions('c1', cursor: 'next');
      expect(adapter.requests.single.queryParameters, {
        'category': isA<ListParam>().having((p) => p.value, 'value', ['c1']),
        'limit': 200,
        'cursor': 'next',
      });
    });

    test('a budget is set from a month on', () async {
      adapter.reply = _category;
      await repo.setBudget('c1', 30000, month: '2026-10');
      expect(adapter.requests.single.method, 'PUT');
      expect(adapter.requests.single.path, '/v1/categories/c1/budget');
      expect(sent(), {'amount': 30000, 'effectiveFrom': '2026-10'});
    });
  });
}
