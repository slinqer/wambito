import 'dart:convert';

import 'package:dio/dio.dart';

/// Why the server no longer knows a session (phone-first spec 10 step 1): its 401's `code`.
/// The phone acts only on the explicit codes; anything else is a session that expired.
enum Unauthorized {
  /// `device_removed`: this phone was removed from the account. Its vault is wiped (3a 6.5).
  deviceRemoved,

  /// `user_deleted`: the account was deleted (the inactivity cleanup; the server says so only when
  /// the request names the account in `x-wambito-user`). Its vault is adopted by a new user.
  userDeleted,

  /// `unauthenticated`, no code, or one this build does not know: the session expired or was
  /// signed out everywhere. The vault is kept for the same account's next sign-in.
  expired,
}

/// The kind of a 401 with [code] (`device_removed`, `user_deleted`, anything else).
Unauthorized unauthorizedOf(String? code) => switch (code) {
  'device_removed' => Unauthorized.deviceRemoved,
  'user_deleted' => Unauthorized.userDeleted,
  _ => Unauthorized.expired,
};

/// The `code` of a problem body (a map, or its JSON text); null when it has none.
String? problemCodeOf(Object? body) {
  Object? json = body;
  if (body is String) {
    try {
      json = jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
  return json is Map && json['code'] is String ? json['code']! as String : null;
}

/// The kind of [error] when it is a 401 answer of Dio; null for anything else.
Unauthorized? unauthorizedOfError(Object error) {
  if (error is! DioException || error.response?.statusCode != 401) return null;
  return unauthorizedOf(problemCodeOf(error.response?.data));
}
