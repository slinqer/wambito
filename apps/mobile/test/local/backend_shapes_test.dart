// The local backend answers like the API: for each scenario, the answer over a memory store
// seeded from test/fixtures/local_backend/seed.json must equal <scenario>.json, which the web's
// own backend recorded over the same seed (apps/web/scripts/record-local-backend-fixtures.ts).
// Also the interceptor: what it answers and what it lets through.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/core/records.dart' show Json;
import 'package:wambito/crypto/records.dart' show RecordType;
import 'package:wambito/local/backend.dart';
import 'package:wambito/local/backend_interceptor.dart';
import 'package:wambito/local/memory_store.dart';
import 'package:wambito/local/store.dart';

const _dir = 'test/fixtures/local_backend';
final _now = DateTime.utc(2026, 10, 21, 18);
const _profile = LocalProfile(
  id: 'u1',
  email: 'ana@example.test',
  isAnonymous: false,
  encryption: 'preview',
);

Object? _read(String name) => jsonDecode(File('$_dir/$name').readAsStringSync());

Future<FinanceStore> _seeded() async {
  final store = createMemoryStore();
  final seed = _read('seed.json')! as Map;
  await store.transaction((s) async {
    for (final entry in seed.entries) {
      final type = RecordType.values.byName(entry.key as String);
      for (final r in entry.value as List) {
        final record = r as Map;
        await s.put(type, record['id'] as String, (record['body'] as Map).cast<String, Object?>());
        if (record['deleted'] == true) await s.delete(type, record['id'] as String);
      }
    }
  });
  return store;
}

LocalBackend _backend(FinanceStore store) {
  var counter = 0x900;
  return createLocalBackend(
    store: store,
    now: () => _now,
    unavailable: localUnavailable,
    timezone: 'UTC',
    profile: _profile,
    newId: () => '01930000-0000-7000-8000-${(counter++).toRadixString(16).padLeft(12, '0')}',
  );
}

class _Recorder implements HttpClientAdapter {
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    return ResponseBody.fromString('{"from":"network"}', 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('local backend answers like the API', () {
    final scenarios = (_read('scenarios.json')! as List).cast<Map>();
    for (final scenario in scenarios) {
      final name = scenario['name'] as String;
      test(name, () async {
        final backend = _backend(await _seeded());
        final query = <String, Object>{
          for (final e in ((scenario['query'] ?? const {}) as Map).entries)
            e.key as String: e.value is List ? (e.value as List).cast<String>() : e.value as String,
        };
        final res = await backend.handle(
          scenario['method'] as String,
          scenario['path'] as String,
          query,
          scenario['body'],
        );
        final expected = _read('$name.json')! as Map;
        expect(res, isNotNull);
        expect(res!.status, expected['status']);
        expect(jsonDecode(jsonEncode(res.body)), expected['body']);
      });
    }
  });

  group('LocalBackendInterceptor', () {
    Future<({Dio dio, _Recorder adapter, List<int> writes})> setup() async {
      final adapter = _Recorder();
      final writes = <int>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://wambito.example/api'))
        ..httpClientAdapter = adapter;
      dio.interceptors.add(
        LocalBackendInterceptor(_backend(await _seeded()), afterWrite: () => writes.add(1)),
      );
      return (dio: dio, adapter: adapter, writes: writes);
    }

    test('interceptorLetsAuthAndV2Through', () async {
      final t = await setup();
      await t.dio.get<Object?>('/v1/me');
      await t.dio.get<Object?>('/v2/sync');
      await t.dio.post<Object?>('/auth/sign-in/email-otp', data: {'email': 'a@b.c'});
      await t.dio.get<Object?>('/v1/passkeys');
      expect([for (final r in t.adapter.seen) r.uri.path], [
        '/api/v1/me',
        '/api/v2/sync',
        '/api/auth/sign-in/email-otp',
        '/api/v1/passkeys',
      ]);
      final local = await t.dio.get<Object?>('/v1/transactions', queryParameters: {'month': '2026-10'});
      expect(t.adapter.seen.length, 4);
      expect(((local.data! as Map)['items'] as List), isNotEmpty);
      await t.dio.delete<Object?>('/v1/me');
      expect(t.adapter.seen.last.method, 'DELETE');
    });

    test('answers a write locally and calls afterWrite only for a 2xx write', () async {
      final t = await setup();
      await t.dio.get<Object?>('/v1/categories');
      expect(t.writes, isEmpty);
      final created = await t.dio.post<Object?>(
        '/v1/categories',
        data: {'name': 'Pets', 'kind': 'expense', 'icon': 'paw', 'color': '#f0f'},
      );
      expect(created.statusCode, 201);
      expect(t.writes.length, 1);
      await expectLater(
        t.dio.post<Object?>('/v1/categories', data: {'name': 'Pets', 'kind': 'expense', 'icon': 'x', 'color': 'y'}),
        throwsA(
          isA<DioException>().having((e) => e.response?.statusCode, 'status', 409).having(
            (e) => (e.response?.data as Json)['code'],
            'code',
            'category_name_taken',
          ),
        ),
      );
      expect(t.writes.length, 1);
      expect(t.adapter.seen, isEmpty);
    });

    test('a JSON text body and repeated query values reach the backend', () async {
      final t = await setup();
      final res = await t.dio.get<Object?>(
        '/v1/transactions',
        queryParameters: {'q': ['almuerzo', 'bus'], 'match': 'any'},
      );
      expect(((res.data! as Map)['items'] as List).length, 3);
      await expectLater(
        t.dio.post<Object?>('/v1/categories', data: '{not json'),
        throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 400)),
      );
    });

    test('the turned-off routes answer 403 demo_unavailable', () async {
      final t = await setup();
      await expectLater(
        t.dio.get<Object?>('/v1/me/export'),
        throwsA(isA<DioException>().having((e) => (e.response?.data as Json)['code'], 'code', 'demo_unavailable')),
      );
      expect(t.adapter.seen, isEmpty);
    });
  });
}
