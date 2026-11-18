import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'client.dart';
import 'device.dart';
import 'server_url.dart';
import 'gen/wambito_api.dart';

/// A failed auth call: the server's error `code` when it sent one (Better Auth's, such as
/// `INVALID_OTP`, or the API's, such as `sign_in_not_allowed`), the HTTP status (0: no response),
/// and the seconds to wait when the server said (a 429). The same shape as the web's
/// `AuthFailure` (apps/web/app/features/sign-in/auth.ts), so the messages match.
class AuthFailure implements Exception {
  const AuthFailure({this.code, required this.status, this.retryAfter});

  final String? code;
  final int status;
  final int? retryAfter;

  @override
  String toString() => 'AuthFailure($status, $code)';
}

/// Who the account behind a token is, as `GET /v1/me` says it: a guest or not, and whether it still
/// has the welcome to do. The web decides the welcome with `onboardingCompletedAt` (apps/web/app/
/// auth/session.ts, `requireOnboarded`); a guest has none, as the web has no guests.
class AccountStanding {
  const AccountStanding({required this.guest, required this.onboardingPending, this.userId});

  final bool guest;

  /// The account's id, when the answer had it.
  final String? userId;

  /// A signed-up account whose `onboardingCompletedAt` is still null.
  final bool onboardingPending;
}

/// One of the person's passkeys, as Settings lists it (the web's `PasskeyItem`).
class PasskeyItem {
  const PasskeyItem({
    required this.id,
    this.credentialId,
    this.name,
    required this.createdAt,
    this.synced = false,
  });

  final String id;

  /// The WebAuthn credential id (base64url, Better Auth's `credentialID`): a passkey wrap's `ref`.
  final String? credentialId;

  /// The name it was given, if any.
  final String? name;

  /// When it was created (UTC).
  final DateTime createdAt;

  /// Saved in a synced password manager (Google, Proton Pass...), not only on one device.
  final bool synced;
}

/// A passkey ceremony's options from the server, and the challenge cookie that must go back with
/// the phone's answer (Better Auth keeps the challenge behind a signed cookie).
class PasskeyChallenge {
  const PasskeyChallenge({required this.optionsJson, required this.cookie});

  /// The WebAuthn options as JSON, which Android's Credential Manager reads as they are.
  final String optionsJson;

  /// `name=value` of the challenge cookie.
  final String cookie;
}

/// What the app needs from the auth server: Better Auth's guest, email-code and passkey routes, and
/// the API's guest claim (spec section 4). Every sign-in returns the session's bearer token.
abstract interface class AuthApi {
  /// A guest: an account without an email (`POST /auth/sign-in/anonymous`).
  Future<String> signInAsGuest();

  /// Emails a 6-digit code and a magic link (one email carries both).
  Future<void> sendCode(String email);

  /// Signs in (or up) with the code from the email or its link.
  Future<String> verifyCode(String email, String code);

  /// Whether the user behind [token] is still a guest (`GET /v1/me`, `isAnonymous`).
  Future<bool> isGuest(String token);

  /// Whether the user behind [token] is a guest and has the welcome to do (`GET /v1/me`).
  Future<AccountStanding> standing(String token);

  /// Marks the welcome done for the account behind [token] (`PATCH /v1/me` with
  /// `onboardingCompleted`). The API stamps it once; a later call keeps the first time.
  Future<void> completeOnboarding(String token);

  /// The id of the account behind [token] (`GET /v1/me`): what the passkey offer's answer is kept for.
  Future<String> accountId(String token);

  /// How many passkeys the account behind [token] has, on any device (Better Auth's
  /// `GET /passkey/list-user-passkeys`, as the web's `listUserPasskeys`), or null when the answer is
  /// not a list.
  Future<int?> passkeyCount(String token);

  /// Saving a guest's progress (spec section 4.2): mails a claim code to [email].
  Future<void> claimSend(String token, String email);

  /// Gives the guest behind [token] the email: same user, same token, every row kept.
  Future<void> claimVerify(String token, String email, String code);

  /// The passkeys of the account behind [token], oldest first (Better Auth's
  /// `GET /passkey/list-user-passkeys`, as the web's `livePasskeys.list`). Throws an [AuthFailure]
  /// when they cannot be read, an answer that is not a list included (code `passkeys_unavailable`).
  Future<List<PasskeyItem>> listPasskeys(String token);

  /// Deletes the passkey [id] of the account behind [token] (`POST /passkey/delete-passkey`).
  Future<void> deletePasskey(String token, String id);

  Future<PasskeyChallenge> passkeySignInOptions();

  /// Signs in with the phone's answer ([responseJson]) to [challenge].
  Future<String> passkeySignIn(PasskeyChallenge challenge, String responseJson);

  Future<PasskeyChallenge> passkeyRegisterOptions(String token);

  /// Adds the phone's new passkey ([responseJson]) to the user behind [token].
  Future<void> passkeyRegister(String token, PasskeyChallenge challenge, String responseJson);

  /// Signs in with the recovery key (`POST /v2/recovery/sign-in`): [lookup] (16 bytes) and [auth]
  /// (32 bytes) are what the key derives (`recoveryVerifier`), never the key itself. A key that
  /// signs in nothing is 401 `recovery_key_invalid`; too many tries, 429 with `retryAfter`.
  Future<String> recoverySignIn(Uint8List lookup, Uint8List auth);

  /// Ends the session on the server (best effort).
  Future<void> signOut(String token);
}

/// [AuthApi] over HTTP, with the request shapes of the web app's sign-in (Better Auth's routes
/// under `<server>/api/auth`) and the generated client for the API's own routes.
class HttpAuthApi implements AuthApi {
  HttpAuthApi({required Uri server, required DeviceHints hints})
    : _client = ApiClient.forServer(server, hints: hints),
      _origin = server.origin;

  final ApiClient _client;

  /// The server's origin, sent as `Origin` where the challenge cookie goes back: Better Auth checks
  /// the Origin of any request carrying a cookie against its trusted origins (the web's).
  final String _origin;

  /// The HTTP client every call goes through (tests replace its adapter).
  Dio get dio => _client.dio;

  DefaultApi get _api => _client.api.getDefaultApi();

  static Map<String, String> _bearer(String token) => {'Authorization': 'Bearer $token'};

  /// The session token Better Auth's bearer plugin returns in `set-auth-token`.
  static String _token(Response<Object?> response) {
    final token = response.headers.value('set-auth-token');
    if (token == null || token.isEmpty) throw AuthFailure(status: 500);
    return token;
  }

  /// [call], with any Dio error turned into an [AuthFailure].
  static Future<T> _settle<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  static AuthFailure _failure(DioException error) {
    final response = error.response;
    if (response == null) return const AuthFailure(status: 0);
    Object? body = response.data;
    if (body is String) {
      try {
        body = jsonDecode(body);
      } on FormatException {
        body = null;
      }
    }
    final code = body is Map ? body['code'] : null;
    final rawRetry =
        response.headers.value('x-retry-after') ?? response.headers.value('retry-after');
    final retry = rawRetry == null ? null : num.tryParse(rawRetry);
    return AuthFailure(
      code: code is String ? code : null,
      status: response.statusCode ?? 500,
      retryAfter: retry != null && retry > 0 ? retry.ceil() : null,
    );
  }

  @override
  Future<String> signInAsGuest() => _settle(() async {
    final response = await dio.post<Object?>('/auth/sign-in/anonymous', data: <String, Object?>{});
    return _token(response);
  });

  @override
  Future<void> sendCode(String email) => _settle(() async {
    await dio.post<Object?>(
      '/auth/email-otp/send-verification-otp',
      data: {'email': email, 'type': 'sign-in'},
    );
  });

  @override
  Future<String> verifyCode(String email, String code) => _settle(() async {
    final response = await dio.post<Object?>(
      '/auth/sign-in/email-otp',
      data: {'email': email, 'otp': code},
    );
    return _token(response);
  });

  @override
  Future<bool> isGuest(String token) => _settle(() async {
    final response = await _api.getMe(headers: _bearer(token));
    final profile = response.data;
    if (profile == null) throw const AuthFailure(status: 500);
    return profile.isAnonymous;
  });

  @override
  Future<AccountStanding> standing(String token) => _settle(() async {
    final response = await _api.getMe(headers: _bearer(token));
    final profile = response.data;
    if (profile == null) throw const AuthFailure(status: 500);
    return AccountStanding(
      guest: profile.isAnonymous,
      onboardingPending: !profile.isAnonymous && profile.onboardingCompletedAt == null,
      userId: profile.id,
    );
  });

  @override
  Future<void> completeOnboarding(String token) => _settle(() async {
    // Plain JSON: the generated client writes the flag's `true` as the text "true", which the API
    // refuses.
    await dio.patch<Object?>(
      '/v1/me',
      data: {'onboardingCompleted': true},
      options: Options(headers: _bearer(token)),
    );
  });

  @override
  Future<String> accountId(String token) => _settle(() async {
    final response = await _api.getMe(headers: _bearer(token));
    final profile = response.data;
    if (profile == null) throw const AuthFailure(status: 500);
    return profile.id;
  });

  @override
  Future<int?> passkeyCount(String token) => _settle(() async {
    final response = await dio.get<Object?>(
      '/auth/passkey/list-user-passkeys',
      options: Options(headers: _bearer(token)),
    );
    final data = response.data;
    return data is List ? data.length : null;
  });

  @override
  Future<List<PasskeyItem>> listPasskeys(String token) => _settle(() async {
    final response = await dio.get<Object?>(
      '/auth/passkey/list-user-passkeys',
      options: Options(headers: _bearer(token)),
    );
    final data = response.data;
    if (data is! List) throw const AuthFailure(code: 'passkeys_unavailable', status: 502);
    final items = [
      for (final entry in data)
        if (entry is Map && entry['id'] is String)
          PasskeyItem(
            id: entry['id']! as String,
            credentialId: entry['credentialID'] is String ? entry['credentialID']! as String : null,
            name: entry['name'] is String && (entry['name']! as String).isNotEmpty
                ? entry['name']! as String
                : null,
            createdAt: DateTime.tryParse('${entry['createdAt']}')?.toUtc() ?? DateTime.utc(1970),
            synced: entry['backedUp'] == true,
          ),
    ];
    // Oldest first, as the web sorts them; the order of equal times is the server's.
    return items..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  });

  @override
  Future<void> deletePasskey(String token, String id) => _settle(() async {
    await dio.post<Object?>(
      '/auth/passkey/delete-passkey',
      data: {'id': id},
      options: Options(headers: _bearer(token)),
    );
  });

  @override
  Future<void> claimSend(String token, String email) => _settle(() async {
    await _api.claimEmailSend(
      claimEmailSend: ClaimEmailSend((b) => b..email = email),
      headers: _bearer(token),
    );
  });

  @override
  Future<void> claimVerify(String token, String email, String code) => _settle(() async {
    await _api.claimEmailVerify(
      claimEmailVerify: ClaimEmailVerify(
        (b) => b
          ..email = email
          ..code = code,
      ),
      headers: _bearer(token),
    );
  });

  /// The options at [path] and their challenge cookie.
  Future<PasskeyChallenge> _passkeyOptions(String path, {String? token}) => _settle(() async {
    final response = await dio.get<Object?>(
      path,
      options: Options(headers: token == null ? null : _bearer(token)),
    );
    final cookie = (response.headers['set-cookie'] ?? const <String>[])
        .map((line) => line.split(';').first.trim())
        .where((pair) => pair.split('=').first.endsWith('better-auth-passkey'))
        .firstOrNull;
    // Handed to Credential Manager as JSON text, whichever way Dio read it.
    final data = response.data;
    final options = data is String ? data : (data is Map ? jsonEncode(data) : null);
    if (cookie == null || options == null) throw const AuthFailure(status: 500);
    return PasskeyChallenge(optionsJson: options, cookie: cookie);
  });

  /// The phone's answer to [challenge], posted to [path] with the challenge cookie. An answer that
  /// is not JSON fails as a passkey failure, before anything is sent.
  Future<Response<Object?>> _passkeyVerify(
    String path,
    PasskeyChallenge challenge,
    String responseJson, {
    String? token,
  }) {
    final Object? answer;
    try {
      answer = jsonDecode(responseJson);
    } on FormatException {
      throw const AuthFailure(code: 'PASSKEY_FAILED', status: 400);
    }
    return _postAnswer(path, challenge, answer, token: token);
  }

  Future<Response<Object?>> _postAnswer(
    String path,
    PasskeyChallenge challenge,
    Object? answer, {
    String? token,
  }) => dio.post<Object?>(
    path,
    data: {'response': answer},
    options: Options(
      headers: {
        'cookie': challenge.cookie,
        'origin': _origin,
        if (token != null) ..._bearer(token),
      },
    ),
  );

  @override
  Future<PasskeyChallenge> passkeySignInOptions() =>
      _passkeyOptions('/auth/passkey/generate-authenticate-options');

  @override
  Future<String> passkeySignIn(PasskeyChallenge challenge, String responseJson) =>
      _settle(() async {
        final response = await _passkeyVerify(
          '/auth/passkey/verify-authentication',
          challenge,
          responseJson,
        );
        return _token(response);
      });

  @override
  Future<PasskeyChallenge> passkeyRegisterOptions(String token) =>
      _passkeyOptions('/auth/passkey/generate-register-options', token: token);

  @override
  Future<void> passkeyRegister(String token, PasskeyChallenge challenge, String responseJson) =>
      _settle(() async {
        await _passkeyVerify(
          '/auth/passkey/verify-registration',
          challenge,
          responseJson,
          token: token,
        );
      });

  @override
  Future<String> recoverySignIn(Uint8List lookup, Uint8List auth) => _settle(() async {
    final response = await _api.recoverySignIn(
      recoverySignIn: RecoverySignIn(
        (b) => b
          ..lookup = _base64Url(lookup)
          ..auth = _base64Url(auth),
      ),
    );
    return _token(response);
  });

  /// Unpadded base64url, as the API reads bytes.
  static String _base64Url(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');

  @override
  Future<void> signOut(String token) => _settle(() async {
    await dio.post<Object?>(
      '/auth/sign-out',
      data: <String, Object?>{},
      options: Options(headers: _bearer(token)),
    );
  });
}

/// The auth server at the configured URL, with the phone's hints.
final authApiProvider = Provider<AuthApi>(
  (ref) => HttpAuthApi(server: ref.watch(serverUrlProvider), hints: ref.watch(deviceHintsProvider)),
);
