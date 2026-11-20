// What "Conecta tu asistente" asks of the server (spec §6.2): `GET /v1/me/assistants` and
// `DELETE /v1/me/assistants/{clientId}`, and the MCP's address next to the server's.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/client.dart';
import 'package:wambito/api/session.dart' show apiClientProvider;
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/local/vault_session.dart' show VaultProfile;
import 'package:wambito/settings/assistants_repository.dart';
import 'package:wambito/vault/encryption_mode.dart';

const _claude = 'https://claude.ai/oauth/mcp-oauth-client-metadata';

/// Answers the list with two assistants and a delete with 204, remembers every request.
class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int? status;
  String? code;
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
    final json = {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    };
    if (status != null) {
      return ResponseBody.fromString(
        jsonEncode({'code': code ?? (status == 404 ? 'not_found' : 'internal_error')}),
        status!,
        headers: json,
      );
    }
    if (options.method == 'DELETE') return ResponseBody.fromString('', 204);
    return ResponseBody.fromString(
      jsonEncode({
        'items': [
          {
            'clientId': _claude,
            'name': 'Claude',
            'icon': 'https://claude.ai/favicon.ico',
            'uri': 'https://claude.ai',
            'domain': 'claude.ai',
            'scopes': ['finance:read', 'finance:write'],
            'connectedAt': '2026-10-30T14:00:00.000Z',
            'lastUsedAt': '2026-10-31T09:15:00.000Z',
          },
          {
            'clientId': 'abc123',
            'name': 'abc123',
            'icon': null,
            'uri': null,
            'domain': null,
            'scopes': ['finance:read'],
            'connectedAt': '2026-10-29T08:00:00.000Z',
            'lastUsedAt': null,
          },
        ],
      }),
      200,
      headers: json,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Adapter adapter;
  late ApiAssistantsRepository repo;
  setUp(() {
    final client = ApiClient.forServer(Uri.parse('https://example.test'), token: 'tok');
    adapter = _Adapter();
    client.dio.httpClientAdapter = adapter;
    repo = ApiAssistantsRepository(client.api.getDefaultApi());
  });

  test('lists them from GET /v1/me/assistants, with their dates read', () async {
    final items = await repo.list();
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/v1/me/assistants');
    expect(items, hasLength(2));
    final claude = items.first;
    expect(claude.clientId, _claude);
    expect(claude.name, 'Claude');
    expect(claude.domain, 'claude.ai');
    expect(claude.connectedAt, DateTime.utc(2026, 10, 30, 14));
    expect(claude.lastUsedAt, DateTime.utc(2026, 10, 31, 9, 15));
    final other = items.last;
    expect(other.domain, isNull);
    expect(other.lastUsedAt, isNull, reason: 'never used');
  });

  test('a failed list is a HomeFailure with the status, and no answer is offline', () async {
    adapter.status = 500;
    await expectLater(
      repo.list(),
      throwsA(isA<HomeFailure>().having((f) => f.status, 'status', 500)),
    );
    adapter.status = null;
    adapter.noAnswer = true;
    await expectLater(
      repo.list(),
      throwsA(isA<HomeFailure>().having((f) => f.offline, 'offline', isTrue)),
    );
  });

  test('revokes with DELETE /v1/me/assistants/{clientId}, a URL id as one segment', () async {
    await repo.revoke(_claude);
    final request = adapter.requests.single;
    expect(request.method, 'DELETE');
    expect(request.uri.pathSegments, ['api', 'v1', 'me', 'assistants', _claude]);
  });

  test('one the server no longer knows (404) counts as revoked', () async {
    adapter.status = 404;
    await repo.revoke('abc123');
    expect(adapter.requests.single.method, 'DELETE');
  });

  test('a refused revoke is a HomeFailure, and no answer is offline', () async {
    adapter.status = 401;
    await expectLater(
      repo.revoke('abc123'),
      throwsA(isA<HomeFailure>().having((f) => f.unauthorized, 'unauthorized', isTrue)),
    );
    adapter.status = null;
    adapter.noAnswer = true;
    await expectLater(
      repo.revoke('abc123'),
      throwsA(isA<HomeFailure>().having((f) => f.offline, 'offline', isTrue)),
    );
  });

  group('an encrypted account', () {
    late ApiAssistantsRepository named;
    setUp(() {
      final client = ApiClient.forServer(Uri.parse('https://example.test'), token: 'tok');
      client.dio.httpClientAdapter = adapter;
      named = ApiAssistantsRepository(client.api.getDefaultApi(), userId: 'user-1');
    });

    test('both calls name the account they mean (x-wambito-user)', () async {
      await named.list();
      await named.revoke(_claude);
      expect(adapter.requests, hasLength(2));
      for (final request in adapter.requests) {
        expect(request.headers['x-wambito-user'], 'user-1', reason: request.method);
      }
    });

    test('a plain account\'s calls name none', () async {
      await repo.list();
      await repo.revoke(_claude);
      for (final request in adapter.requests) {
        expect(request.headers.containsKey('x-wambito-user'), isFalse);
      }
    });

    test('a session that changed hands is 409 session_changed, never counted as revoked', () async {
      adapter
        ..status = 409
        ..code = 'session_changed';
      await expectLater(
        named.revoke(_claude),
        throwsA(
          isA<HomeFailure>()
              .having((f) => f.status, 'status', 409)
              .having((f) => f.code, 'code', 'session_changed'),
        ),
      );
    });
  });

  group('the provider', () {
    VaultAccount account(EncryptionMode mode) => VaultAccount(
      owner: 'owner-1',
      mode: mode,
      profile: const VaultProfile(
        id: 'user-9',
        email: 'ana@wambito.test',
        isAnonymous: false,
        locale: 'es',
        timezone: 'America/Bogota',
      ),
    );

    Future<RequestOptions> listedWith(VaultAccount? signedIn) async {
      final client = ApiClient.forServer(Uri.parse('https://example.test'), token: 'tok');
      client.dio.httpClientAdapter = adapter;
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          currentVaultAccountProvider.overrideWithValue(signedIn),
        ],
      );
      addTearDown(container.dispose);
      await container.read(assistantsRepositoryProvider).list();
      return adapter.requests.last;
    }

    test('an encrypted account\'s calls name it', () async {
      final request = await listedWith(account(EncryptionMode.preview));
      expect(request.headers['x-wambito-user'], 'user-9');
      expect(request.headers['Authorization'], 'Bearer tok', reason: 'the session\'s bearer');
    });

    test('a plain account\'s, or one not known yet, name none', () async {
      expect(
        (await listedWith(account(EncryptionMode.plain))).headers.containsKey('x-wambito-user'),
        isFalse,
      );
      expect((await listedWith(null)).headers.containsKey('x-wambito-user'), isFalse);
    });
  });

  group('the MCP\'s address', () {
    test('is the server\'s origin with /mcp', () {
      expect(
        mcpUrl(Uri.parse('https://app.wambito.com')).toString(),
        'https://app.wambito.com/mcp',
      );
      expect(
        mcpUrl(Uri.parse('https://app.wambito.com/')).toString(),
        'https://app.wambito.com/mcp',
      );
    });

    test('keeps a port and a sub-path, and drops a query or fragment', () {
      expect(
        mcpUrl(Uri.parse('http://10.0.2.2:8080/wambito/?x=1#y')).toString(),
        'http://10.0.2.2:8080/wambito/mcp',
      );
    });
  });
}
