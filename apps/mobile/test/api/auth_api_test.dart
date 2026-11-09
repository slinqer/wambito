import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/device.dart';

/// One canned answer: status, JSON body and headers.
class _Reply {
  const _Reply(this.status, [this.body = const <String, Object?>{}, this.headers = const {}]);
  final int status;
  final Object? body;
  final Map<String, List<String>> headers;
}

/// Answers each `METHOD /path` from [replies] (200 `{}` otherwise) and records every request.
class _ScriptedAdapter implements HttpClientAdapter {
  final replies = <String, _Reply>{};
  final requests = <RequestOptions>[];
  final bodies = <Object?>[];
  bool offline = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    bodies.add(options.data);
    if (offline) {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    final reply = replies['${options.method} ${options.uri.path}'] ?? const _Reply(200);
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [
          reply.status >= 400 && reply.body is Map && (reply.body as Map).containsKey('type')
              ? 'application/problem+json'
              : Headers.jsonContentType,
        ],
        ...reply.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _hints = DeviceHints(timezone: 'America/Bogota', locale: 'es-CO');

void main() {
  late _ScriptedAdapter adapter;
  late HttpAuthApi api;

  setUp(() {
    adapter = _ScriptedAdapter();
    api = HttpAuthApi(server: Uri.parse('https://wambito.example/'), hints: _hints);
    api.dio.httpClientAdapter = adapter;
  });

  RequestOptions last() => adapter.requests.last;

  test('every request carries the device time zone and locale', () async {
    await api.sendCode('ana@correo.com');
    expect(last().headers['x-wambito-timezone'], 'America/Bogota');
    expect(last().headers['x-wambito-locale'], 'es-CO');
  });

  test(
    'every request says it comes from the Android app, so the email link opens the app',
    () async {
      await api.sendCode('ana@correo.com');
      expect(last().headers['x-wambito-client'], 'android');
    },
  );

  test('signInAsGuest posts {} to the anonymous sign-in and returns set-auth-token', () async {
    adapter.replies['POST /api/auth/sign-in/anonymous'] = const _Reply(
      200,
      {
        'token': 'ignored',
        'user': {'id': 'u1'},
      },
      {
        'set-auth-token': ['tok.sig'],
      },
    );
    expect(await api.signInAsGuest(), 'tok.sig');
    expect(last().uri.toString(), 'https://wambito.example/api/auth/sign-in/anonymous');
    expect(adapter.bodies.last, <String, Object?>{});
  });

  test('sendCode and verifyCode follow the web: email-otp with type sign-in', () async {
    adapter.replies['POST /api/auth/sign-in/email-otp'] = const _Reply(
      200,
      {
        'user': {'id': 'u1'},
      },
      {
        'set-auth-token': ['email.tok'],
      },
    );
    await api.sendCode('ana@correo.com');
    expect(last().uri.path, '/api/auth/email-otp/send-verification-otp');
    expect(adapter.bodies.last, {'email': 'ana@correo.com', 'type': 'sign-in'});

    expect(await api.verifyCode('ana@correo.com', '123456'), 'email.tok');
    expect(last().uri.path, '/api/auth/sign-in/email-otp');
    expect(adapter.bodies.last, {'email': 'ana@correo.com', 'otp': '123456'});
    expect(last().headers.containsKey('Authorization'), isFalse);
  });

  test('a sign-in without set-auth-token is a failure, not an empty session', () async {
    await expectLater(
      api.verifyCode('ana@correo.com', '123456'),
      throwsA(isA<AuthFailure>().having((f) => f.status, 'status', 500)),
    );
  });

  test("Better Auth's errors keep their code and status", () async {
    adapter.replies['POST /api/auth/email-otp/send-verification-otp'] = const _Reply(403, {
      'code': 'sign_in_not_allowed',
      'message': 'Sign-in is not open to this address',
    });
    await expectLater(
      api.sendCode('nadie@correo.com'),
      throwsA(
        isA<AuthFailure>()
            .having((f) => f.code, 'code', 'sign_in_not_allowed')
            .having((f) => f.status, 'status', 403),
      ),
    );
  });

  test("the API's problem+json errors keep their code; a 429 its retry delay", () async {
    adapter.replies['POST /api/v1/me/claim-email/send'] = const _Reply(
      429,
      {'type': 'about:blank', 'status': 429, 'code': 'too_many_requests'},
      {
        'x-retry-after': ['42'],
      },
    );
    await expectLater(
      api.claimSend('tok', 'ana@correo.com'),
      throwsA(
        isA<AuthFailure>()
            .having((f) => f.code, 'code', 'too_many_requests')
            .having((f) => f.status, 'status', 429)
            .having((f) => f.retryAfter, 'retryAfter', 42),
      ),
    );
  });

  test('no connection is status 0', () async {
    adapter.offline = true;
    await expectLater(
      api.sendCode('ana@correo.com'),
      throwsA(isA<AuthFailure>().having((f) => f.status, 'status', 0)),
    );
  });

  test('isGuest reads isAnonymous from /v1/me with the bearer token', () async {
    adapter.replies['GET /api/v1/me'] = const _Reply(200, {
      'id': 'u1',
      'email': 'x@guest.wambito.invalid',
      'timezone': 'America/Bogota',
      'locale': 'es',
      'onboardingCompletedAt': null,
      'currency': 'COP',
      'isAnonymous': true,
      'encryption': 'plain',
    });
    expect(await api.isGuest('tok'), isTrue);
    expect(last().headers['Authorization'], 'Bearer tok');
  });

  test('accountId reads the id from /v1/me with the bearer token', () async {
    adapter.replies['GET /api/v1/me'] = const _Reply(200, {
      'id': 'u1',
      'email': 'ana@correo.com',
      'timezone': 'America/Bogota',
      'locale': 'es',
      'onboardingCompletedAt': null,
      'currency': 'COP',
      'isAnonymous': false,
      'encryption': 'plain',
    });
    expect(await api.accountId('tok'), 'u1');
    expect(last().headers['Authorization'], 'Bearer tok');
  });

  group('standing, the account as /v1/me says it', () {
    const base = {
      'id': 'u1',
      'email': 'ana@correo.com',
      'timezone': 'America/Bogota',
      'locale': 'es',
      'currency': 'COP',
    };

    test('a new email account is not a guest and has the welcome to do', () async {
      adapter.replies['GET /api/v1/me'] = const _Reply(200, {
        ...base,
        'onboardingCompletedAt': null,
        'isAnonymous': false,
        'encryption': 'plain',
      });
      final standing = await api.standing('tok');
      expect(standing.guest, isFalse);
      expect(standing.onboardingPending, isTrue);
      expect(last().headers['Authorization'], 'Bearer tok');
    });

    test('an account with onboardingCompletedAt has not', () async {
      adapter.replies['GET /api/v1/me'] = const _Reply(200, {
        ...base,
        'onboardingCompletedAt': '2026-10-21T10:00:00.000Z',
        'isAnonymous': false,
        'encryption': 'plain',
      });
      expect((await api.standing('tok')).onboardingPending, isFalse);
    });

    test('a guest never has a welcome to do', () async {
      adapter.replies['GET /api/v1/me'] = const _Reply(200, {
        ...base,
        'onboardingCompletedAt': null,
        'isAnonymous': true,
        'encryption': 'plain',
      });
      final standing = await api.standing('tok');
      expect(standing.guest, isTrue);
      expect(standing.onboardingPending, isFalse);
    });

    test('completeOnboarding sends the boolean true, which is what the API reads', () async {
      adapter.replies['PATCH /api/v1/me'] = const _Reply(200, {
        ...base,
        'onboardingCompletedAt': '2026-10-21T10:00:00.000Z',
        'isAnonymous': false,
        'encryption': 'plain',
      });
      await api.completeOnboarding('tok');
      expect(last().method, 'PATCH');
      expect(last().headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(jsonEncode(adapter.bodies.last)), {'onboardingCompleted': true});
    });
  });

  group('passkeyCount, the web\'s listUserPasskeys', () {
    test('counts the passkeys Better Auth lists for the signed-in user', () async {
      adapter.replies['GET /api/auth/passkey/list-user-passkeys'] = const _Reply(200, [
        {'id': 'a'},
        {'id': 'b'},
      ]);
      expect(await api.passkeyCount('tok'), 2);
      expect(last().headers['Authorization'], 'Bearer tok');

      adapter.replies['GET /api/auth/passkey/list-user-passkeys'] = const _Reply(200, <Object>[]);
      expect(await api.passkeyCount('tok'), 0);
    });

    test('an answer that is not a list is not a count', () async {
      adapter.replies['GET /api/auth/passkey/list-user-passkeys'] = const _Reply(200, {
        'oops': true,
      });
      expect(await api.passkeyCount('tok'), isNull);
    });

    test('a refusal is an AuthFailure', () async {
      adapter.replies['GET /api/auth/passkey/list-user-passkeys'] = const _Reply(401, {
        'code': 'UNAUTHORIZED',
      });
      await expectLater(
        api.passkeyCount('tok'),
        throwsA(isA<AuthFailure>().having((f) => f.status, 'status', 401)),
      );
    });
  });

  group('listPasskeys and deletePasskey, the web\'s livePasskeys', () {
    test(
      'lists the passkeys oldest first: name or none, when it was made and whether it syncs',
      () async {
        adapter.replies['GET /api/auth/passkey/list-user-passkeys'] = const _Reply(200, [
          {
            'id': 'b',
            'name': 'Pixel',
            'createdAt': '2026-10-05T10:00:00.000Z',
            'backedUp': false,
            'publicKey': 'x',
          },
          {'id': 'a', 'name': null, 'createdAt': '2026-10-02T09:00:00.000Z', 'backedUp': true},
        ]);
        final items = await api.listPasskeys('tok');
        expect(last().headers['Authorization'], 'Bearer tok');
        expect(items.map((p) => p.id), ['a', 'b']);
        expect(items[0].name, isNull);
        expect(items[0].synced, isTrue);
        expect(items[0].createdAt, DateTime.utc(2026, 10, 2, 9));
        expect(items[1].name, 'Pixel');
        expect(items[1].synced, isFalse);
      },
    );

    test('an answer that is not a list cannot be read: passkeys_unavailable', () async {
      adapter.replies['GET /api/auth/passkey/list-user-passkeys'] = const _Reply(200, {'x': 1});
      await expectLater(
        api.listPasskeys('tok'),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'passkeys_unavailable')),
      );
    });

    test('a refusal is an AuthFailure with its status', () async {
      adapter.replies['GET /api/auth/passkey/list-user-passkeys'] = const _Reply(401, {
        'code': 'UNAUTHORIZED',
      });
      await expectLater(
        api.listPasskeys('tok'),
        throwsA(isA<AuthFailure>().having((f) => f.status, 'status', 401)),
      );
    });

    test('deletes one by its id with a POST, as Better Auth\'s deletePasskey', () async {
      adapter.replies['POST /api/auth/passkey/delete-passkey'] = const _Reply(200, {
        'status': true,
      });
      await api.deletePasskey('tok', 'pk-1');
      expect(last().uri.path, '/api/auth/passkey/delete-passkey');
      expect(last().headers['Authorization'], 'Bearer tok');
      expect(adapter.bodies.last, {'id': 'pk-1'});
    });

    test('a refused delete throws', () async {
      adapter.replies['POST /api/auth/passkey/delete-passkey'] = const _Reply(404, {
        'code': 'PASSKEY_NOT_FOUND',
      });
      await expectLater(api.deletePasskey('tok', 'pk-1'), throwsA(isA<AuthFailure>()));
    });
  });

  test('the claim sends the email, then the email and code, as the guest', () async {
    adapter.replies['POST /api/v1/me/claim-email/send'] = const _Reply(204, null);
    adapter.replies['POST /api/v1/me/claim-email/verify'] = const _Reply(200, {
      'id': 'u1',
      'email': 'ana@correo.com',
      'timezone': 'America/Bogota',
      'locale': 'es',
      'onboardingCompletedAt': null,
      'currency': 'COP',
      'isAnonymous': false,
      'encryption': 'plain',
    });

    await api.claimSend('tok', 'ana@correo.com');
    expect(last().uri.path, '/api/v1/me/claim-email/send');
    expect(last().headers['Authorization'], 'Bearer tok');
    expect(jsonDecode(jsonEncode(adapter.bodies.last)), {'email': 'ana@correo.com'});

    await api.claimVerify('tok', 'ana@correo.com', '111222');
    expect(last().uri.path, '/api/v1/me/claim-email/verify');
    expect(jsonDecode(jsonEncode(adapter.bodies.last)), {
      'email': 'ana@correo.com',
      'code': '111222',
    });
  });

  group('passkeys', () {
    test('sign-in: the options and their challenge cookie, then the response with that cookie '
        'and the server origin', () async {
      adapter.replies['GET /api/auth/passkey/generate-authenticate-options'] = const _Reply(
        200,
        {'challenge': 'abc', 'rpId': 'wambito.example'},
        {
          'set-cookie': [
            '__Secure-better-auth.better-auth-passkey=signed.value; Max-Age=300; Path=/; '
                'HttpOnly; Secure; SameSite=Lax',
          ],
        },
      );
      adapter.replies['POST /api/auth/passkey/verify-authentication'] = const _Reply(
        200,
        {
          'session': {},
          'user': {'id': 'u1'},
        },
        {
          'set-auth-token': ['pk.tok'],
        },
      );

      final challenge = await api.passkeySignInOptions();
      expect(jsonDecode(challenge.optionsJson), {'challenge': 'abc', 'rpId': 'wambito.example'});
      expect(challenge.cookie, '__Secure-better-auth.better-auth-passkey=signed.value');

      final token = await api.passkeySignIn(challenge, '{"id":"cred","type":"public-key"}');
      expect(token, 'pk.tok');
      expect(last().uri.path, '/api/auth/passkey/verify-authentication');
      expect(last().headers['cookie'], '__Secure-better-auth.better-auth-passkey=signed.value');
      expect(last().headers['origin'], 'https://wambito.example');
      expect(adapter.bodies.last, {
        'response': {'id': 'cred', 'type': 'public-key'},
      });
    });

    test('registration: the options and the response as the signed-in user', () async {
      adapter.replies['GET /api/auth/passkey/generate-register-options'] = const _Reply(
        200,
        {'challenge': 'xyz'},
        {
          'set-cookie': ['better-auth.better-auth-passkey=v2; Path=/'],
        },
      );
      final challenge = await api.passkeyRegisterOptions('tok');
      expect(last().headers['Authorization'], 'Bearer tok');

      await api.passkeyRegister('tok', challenge, '{"id":"cred"}');
      expect(last().uri.path, '/api/auth/passkey/verify-registration');
      expect(last().headers['Authorization'], 'Bearer tok');
      expect(last().headers['cookie'], 'better-auth.better-auth-passkey=v2');
      expect(last().headers['origin'], 'https://wambito.example');
      expect(adapter.bodies.last, {
        'response': {'id': 'cred'},
      });
    });

    test('a passkey answer that is not JSON is an AuthFailure, not a crash', () async {
      const challenge = PasskeyChallenge(optionsJson: '{}', cookie: 'better-auth-passkey=v');
      await expectLater(
        api.passkeySignIn(challenge, 'not json'),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'PASSKEY_FAILED')),
      );
      expect(adapter.requests, isEmpty);
    });

    test('options without a challenge cookie are a failure', () async {
      await expectLater(api.passkeySignInOptions(), throwsA(isA<AuthFailure>()));
    });
  });
}
