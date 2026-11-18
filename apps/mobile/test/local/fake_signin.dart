// A fake `/v2/signin` relay with the API's rules (apps/api/src/routes/signin.ts) for the phone's
// session routes, and the browser's side of a request with real crypto; anything else goes to
// [FakeKeys]. Shared by the approval's tests and its screen's.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/relay_clock.dart';

import 'fake_keys.dart';

class FakeClock implements PairingClock {
  DateTime t = DateTime.utc(2026, 11, 18, 12);
  final sleeps = <Duration>[];

  @override
  DateTime now() => t;

  @override
  Future<void> sleep(Duration d) async {
    sleeps.add(d);
    t = t.add(d);
    await Future<void>.delayed(Duration.zero);
  }
}

class SigninRow {
  SigninRow({
    required this.id,
    required this.code,
    required this.commitment,
    required this.label,
    required this.expiresAt,
  });

  final String id;
  final String code;
  String commitment;
  final String label;
  DateTime expiresAt;
  String? approverKey;
  String? publicKey;
  String? sealed;
  int? keyV;
  bool pickedUp = false;
}

/// The browser's side: its key pair `N`, as `startSignin` makes it.
class Browser {
  Browser(this.pair);

  final DeviceKeyPair pair;
  String get key => toBase64Url(pair.publicKey);
}

/// `/v2/signin` with the phone's session; anything else goes to [keys].
class FakeSignin implements HttpClientAdapter {
  FakeSignin(this.clock, this.keys);

  final FakeClock clock;
  final FakeKeys keys;
  final rows = <String, SigninRow>{};
  final log = <String>[];

  /// The server's clock is not this phone's: it runs [serverAhead] ahead (negative: behind).
  Duration serverAhead = Duration.zero;

  /// How long the server says a request lives, on its own clock.
  Duration ttlSays = const Duration(minutes: 2);

  /// Whether the server ever expires a row on its own.
  bool expires = true;

  /// The browser reveals this key once the phone approved (null: it never reveals).
  String? Function(SigninRow row)? reveal;

  /// The browser picks the seal up at once (the phone's next read is a 404).
  bool pickUp = true;

  void Function(Map<String, Object?> body)? onGet;

  /// Sees each request first: an answer (status, body, headers) replaces the relay's.
  (int, Object?, Map<String, String>)? Function(String method, String path)? intercept;

  Dio dio() => Dio(BaseOptions(baseUrl: 'http://x/api'))..httpClientAdapter = this;

  DateTime get serverNow => clock.t.add(serverAhead);

  Future<SigninRow> open(Browser browser, {String label = 'Firefox on Mac'}) async {
    final row = SigninRow(
      id: newUuid(),
      code: 'ABCD2345',
      commitment: toBase64Url(await pairingCommitment(browser.pair.publicKey)),
      label: label,
      expiresAt: serverNow.add(ttlSays),
    );
    rows[row.id] = row;
    return row;
  }

  SigninRow? _live(String id) {
    final row = rows[id];
    if (row == null || row.pickedUp) return null;
    if (expires && !row.expiresAt.isAfter(serverNow)) return null;
    return row;
  }

  ResponseBody _json(Object? body, [int status = 200, Map<String, String> headers = const {}]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
          for (final MapEntry(:key, :value) in headers.entries) key: [value],
        },
      );

  ResponseBody _problem(int status, String code) => _json({'code': code}, status);

  ResponseBody _empty(int status) => ResponseBody.fromString('', status);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst(RegExp('^/api'), '');
    if (!path.startsWith('/v2/signin')) return keys.fetch(options, requestStream, cancelFuture);
    final method = options.method.toUpperCase();
    expect(options.headers['x-wambito-user'], isNotNull);
    log.add('$method $path${options.uri.hasQuery ? '?${options.uri.query}' : ''}');
    final data = options.data;
    final body = data is Map
        ? data.cast<String, Object?>()
        : data is String && data.isNotEmpty
        ? (jsonDecode(data) as Map).cast<String, Object?>()
        : null;
    final hooked = intercept?.call(method, path);
    if (hooked != null) return _json(hooked.$2, hooked.$1, hooked.$3);

    if (path == '/v2/signin' && method == 'GET') {
      final code = options.uri.queryParameters['code'];
      final row = rows.values
          .where((r) => r.code == code && r.approverKey == null && _live(r.id) != null)
          .firstOrNull;
      if (row == null) return _problem(404, 'not_found');
      return _json({
        'id': row.id,
        'commitment': row.commitment,
        'label': row.label,
        'expiresAt': row.expiresAt.toIso8601String(),
      });
    }
    final match = RegExp(r'^/v2/signin/([0-9a-f-]{36})(?:/(\w+))?$').firstMatch(path);
    if (match == null) return _empty(404);
    final row = _live(match.group(1)!);
    if (row == null) return _problem(404, 'not_found');
    final action = match.group(2);
    if (action == null && method == 'GET') {
      if (row.approverKey != null && row.publicKey == null) row.publicKey = reveal?.call(row);
      final out = <String, Object?>{
        'id': row.id,
        'commitment': row.commitment,
        'label': row.label,
        'expiresAt': row.expiresAt.toIso8601String(),
        'publicKey': row.publicKey,
      };
      onGet?.call(out);
      return _json(out);
    }
    if (action == 'approver' && method == 'POST') {
      if (row.approverKey != null) return _problem(409, 'already_set');
      row.approverKey = body!['publicKey']! as String;
      return _empty(204);
    }
    if (action == 'seal' && method == 'POST') {
      if (row.sealed != null) return _problem(409, 'already_sealed');
      if (row.approverKey == null || row.publicKey == null) return _problem(409, 'not_ready');
      final blob = fromBase64Url(body!['sealed']! as String);
      if (toBase64Url(blob.sublist(0, 32)) != row.approverKey) {
        return _problem(422, 'approver_mismatch');
      }
      final current = keys.wraps.map((w) => w.keyV).fold(0, (a, b) => a > b ? a : b);
      if (body['keyV'] != current) return _problem(409, 'key_version_mismatch');
      row.sealed = body['sealed']! as String;
      row.keyV = body['keyV']! as int;
      if (pickUp) row.pickedUp = true;
      return _empty(204);
    }
    return _empty(404);
  }

  @override
  void close({bool force = false}) {}
}

String newUuid() {
  final b = generateDataKey().sublist(0, 16);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
