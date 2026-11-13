import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:wambito/crypto/crypto.dart';

/// One request the fake saw.
class FakeRequest {
  FakeRequest(this.method, this.uri, this.user, this.body);

  final String method;
  final Uri uri;

  /// The `x-wambito-user` header.
  final String? user;
  final Map<String, Object?>? body;

  String get path => uri.path;

  /// The ids of a push's changes.
  List<String> get changeIds => [
    for (final c in (body?['changes'] as List?) ?? const []) (c as Map)['id']! as String,
  ];
}

/// An answer: the status and the JSON body.
typedef FakeAnswer = (int, Object?);

/// Thrown by an intercept to fail a request as if the network were down.
class Offline implements Exception {
  const Offline();
}

/// A `/v2/sync` server written from the contract (the twin of `fakeServer` in
/// apps/web/app/local/sync.test.ts): versions from a counter, conflicts, purges, and the key
/// version rule. Behind a Dio [HttpClientAdapter]; no network.
class FakeSync implements HttpClientAdapter {
  int counter = 0;
  int purgeThrough = 0;
  bool offline = false;
  int posts = 0;
  int gets = 0;
  int? pullLimit;

  /// The account's key wraps: the record keys this device's wrap opens, by key version (empty: the
  /// account has no wraps, any `keyV` is taken).
  final Map<int, RecordKeys> wraps = {};

  /// No wrap of this device is left.
  bool removed = false;

  /// This device's wrap holds a version whose links do not lead back to its key.
  bool tampered = false;
  final Map<String, Map<String, Object?>> rows = {};
  final List<FakeRequest> requests = [];

  /// Sees each request: answers it, calls `real` for the fake's answer, or throws [Offline].
  Future<FakeAnswer> Function(FakeRequest request, Future<FakeAnswer> Function() real)? intercept;

  Dio dio() => Dio(BaseOptions(baseUrl: 'http://x/api'))..httpClientAdapter = this;

  /// Purges every tombstone, as the daily job does after 180 days.
  void purge() {
    var through = 0;
    for (final id in rows.keys.toList()) {
      final r = rows[id]!;
      if (r['deleted'] == true) {
        through = max(through, r['version']! as int);
        rows.remove(id);
      }
    }
    purgeThrough = max(purgeThrough, through);
  }

  Future<FakeAnswer> serve(FakeRequest request) async {
    if (request.method == 'POST') {
      posts += 1;
      final changes = [
        for (final c in request.body!['changes']! as List) (c as Map).cast<String, Object?>(),
      ];
      final current = wraps.isEmpty ? null : wraps.keys.reduce(max);
      final results = [for (final c in changes) _apply(c, current)];
      return (200, {'results': results});
    }
    gets += 1;
    final q = request.uri.queryParameters;
    final since = int.parse(q['since']!);
    final limit = min(int.parse(q['limit']!), pullLimit ?? 1000);
    final base = int.parse(q['base'] ?? '$since');
    final latest = rows.values.fold(0, (m, r) => max(m, r['version']! as int));
    if (base > 0 && base < purgeThrough) return (410, {'code': 'resync_required'});
    final list =
        rows.values
            .where((r) => (r['version']! as int) > since && (r['version']! as int) <= latest)
            .toList()
          ..sort((x, y) => (x['version']! as int).compareTo(y['version']! as int));
    final page = list.take(limit).toList();
    return (
      200,
      {
        'records': [for (final r in page) Map.of(r)],
        'next': list.length > limit ? (page.isEmpty ? null : page.last['version']) : null,
        'latest': latest,
      },
    );
  }

  Map<String, Object?> _apply(Map<String, Object?> c, int? current) {
    final id = c['id']! as String;
    // Task 1's rule: with wraps, only the account's current key version is taken.
    if (current != null && c['keyV'] != current) {
      return {'id': id, 'error': 'key_version_mismatch', 'keyV': current};
    }
    final cur = rows[id];
    Map<String, Object?> put() {
      final row = Map.of(c)
        ..remove('baseVersion')
        ..['version'] = ++counter;
      rows[id] = row;
      return {'id': id, 'version': row['version']};
    }

    if (c['baseVersion'] == null) {
      if (cur == null) return put();
      if (cur['body'] == c['body'] && cur['deleted'] == c['deleted']) {
        return {'id': id, 'version': cur['version']};
      }
      return {'id': id, 'conflict': Map.of(cur)};
    }
    if (cur == null) return {'id': id, 'error': 'not_found'};
    if (cur['version'] != c['baseVersion'] || cur['type'] != c['type']) {
      return {'id': id, 'conflict': Map.of(cur)};
    }
    return put();
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = options.data;
    final body = data is Map
        ? jsonDecode(jsonEncode(data)) as Map<String, Object?>
        : data is String && data.isNotEmpty
        ? (jsonDecode(data) as Map).cast<String, Object?>()
        : null;
    final request = FakeRequest(
      options.method.toUpperCase(),
      options.uri,
      options.headers['x-wambito-user'] as String?,
      body,
    );
    requests.add(request);
    FakeAnswer answer;
    try {
      if (offline) throw const Offline();
      final hook = intercept;
      answer = hook != null ? await hook(request, () => serve(request)) : await serve(request);
    } on Offline {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    final (status, json) = answer;
    return ResponseBody.fromString(
      jsonEncode(json),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
