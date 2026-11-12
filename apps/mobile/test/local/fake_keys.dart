import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/key_storage.dart';

/// A wrap as the fake `/v2/keys` keeps it (the twin of `Wrap` in apps/web/app/local/keys.test.ts).
class FakeWrap {
  FakeWrap({
    required this.id,
    required this.kind,
    required this.keyV,
    required this.wrapped,
    this.ref,
    this.publicKey,
    this.attestation,
    this.label,
  });

  String id;
  String kind;
  String? ref;
  int keyV;
  String wrapped;
  String? publicKey;
  String? attestation;
  String? label;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'ref': ref,
    'keyV': keyV,
    'wrapped': wrapped,
    'publicKey': publicKey,
    'attestation': attestation,
    'label': label,
  };
}

/// One request the fake saw.
class FakeCall {
  const FakeCall(this.method, this.path, this.user, this.ifNoneMatch, this.body);

  final String method;
  final String path;

  /// The `x-wambito-user` header.
  final String? user;
  final String? ifNoneMatch;
  final Map<String, Object?>? body;
}

/// A fake `/v2/keys` behind a Dio [HttpClientAdapter] that enforces the rules the tests care about
/// (the real one: apps/api/src/routes/keys.ts; the web's twin: `fakeKeys` in keys.test.ts). No
/// network.
class FakeKeys implements HttpClientAdapter {
  FakeKeys({this.passkeys});

  /// The account's passkey credential ids; `null`: any credential is accepted.
  final List<String>? passkeys;
  final List<FakeWrap> wraps = [];

  /// `link(v)` by the version whose key seals it, base64url.
  final Map<int, String> links = {};
  final List<FakeCall> calls = [];
  final List<String> deletes = [];
  bool failDeletes = false;

  /// When set, every request gets this answer instead (status, JSON body).
  (int, Object?)? answerAll;

  /// When set, every request fails as if the network were down.
  bool offline = false;

  Dio dio() => Dio(BaseOptions(baseUrl: 'http://x/api'))..httpClientAdapter = this;

  List<FakeCall> get puts => calls.where((c) => c.method == 'PUT').toList();

  ResponseBody _json(Object? body, [int status = 200]) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (offline) {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    final method = options.method.toUpperCase();
    final path = options.uri.path;
    final data = options.data;
    final body = data is Map
        ? data.cast<String, Object?>()
        : data is String && data.isNotEmpty
        ? (jsonDecode(data) as Map).cast<String, Object?>()
        : null;
    final ifNoneMatch = options.headers['if-none-match'] as String?;
    calls.add(
      FakeCall(method, path, options.headers['x-wambito-user'] as String?, ifNoneMatch, body),
    );
    if (answerAll != null) return _json(answerAll!.$2, answerAll!.$1);

    if (path == '/api/v2/keys' && method == 'GET') {
      final sorted = links.keys.toList()..sort();
      return _json({
        'wraps': [for (final w in wraps) w.toJson()],
        'links': [
          for (final v in sorted) {'keyV': v, 'link': links[v]},
        ],
      });
    }
    final match = RegExp(r'^/api/v2/keys/([0-9a-f-]{36})$').firstMatch(path);
    if (match != null && method == 'DELETE') {
      final id = match.group(1)!;
      deletes.add(id);
      if (failDeletes) return _json({'code': 'unavailable'}, 503);
      wraps.removeWhere((w) => w.id == id);
      return ResponseBody.fromString('', 204);
    }
    if (match != null && method == 'PUT' && body != null) {
      final id = match.group(1)!;
      if (ifNoneMatch == '*' && wraps.any((w) => w.id != id)) {
        return _json({'code': 'already_set_up'}, 409);
      }
      if (wraps.isEmpty && body['kind'] != 'recovery') {
        return _json({'code': 'recovery_required'}, 422);
      }
      if (body['kind'] == 'passkey' && passkeys != null && !passkeys!.contains(body['ref'])) {
        return _json({'code': 'unknown_passkey'}, 422);
      }
      if (body['kind'] == 'device' && (body['publicKey'] == null || body['attestation'] == null)) {
        return _json({'code': 'attestation_required'}, 422);
      }
      final wrap = FakeWrap(
        id: id,
        kind: body['kind']! as String,
        ref: body['ref'] as String?,
        keyV: body['keyV']! as int,
        wrapped: body['wrapped']! as String,
        publicKey: body['publicKey'] as String?,
        attestation: body['attestation'] as String?,
        label: body['label'] as String?,
      );
      wraps.removeWhere(
        (w) =>
            w.id == id ||
            (w.kind == 'recovery' && wrap.kind == 'recovery') ||
            (w.kind == 'passkey' && wrap.kind == 'passkey' && w.ref == wrap.ref),
      );
      wraps.add(wrap);
      return _json(wrap.toJson());
    }
    return ResponseBody.fromString('', 404);
  }

  @override
  void close({bool force = false}) {}
}

/// A [KeyStorage] over the plugin's in-memory mock (no Keychain, no Keystore), empty.
KeyStorage memoryKeyStorage([Map<String, String> values = const {}]) {
  FlutterSecureStorage.setMockInitialValues(Map.of(values));
  return KeyStorage(const FlutterSecureStorage());
}

/// Everything the secure storage holds, sorted by name: to check that nothing changed.
Future<Map<String, String>> storedEntries() async {
  final all = await const FlutterSecureStorage().readAll();
  final names = all.keys.toList()..sort();
  return {for (final n in names) n: all[n]!};
}

/// Stores `link(keyV)`: [oldKey] sealed under [newKey].
Future<void> addLink(
  FakeKeys api,
  String userId,
  Uint8List newKey,
  Uint8List oldKey,
  int keyV,
) async {
  api.links[keyV] = toBase64Url(
    await sealKeyLink(newKey, oldKey, LinkContext(userId: userId, keyV: keyV)),
  );
}

/// The server re-wrapped [dk] to the device's public key under [keyV] (a rotation). With
/// [previous], the rotation also left `link(keyV)`: [previous] sealed under [dk].
Future<void> rotateDeviceWrap(
  FakeKeys api,
  String userId,
  FakeWrap device,
  Uint8List dk,
  int keyV, [
  Uint8List? previous,
]) async {
  if (previous != null) await addLink(api, userId, dk, previous, keyV);
  final wrap = api.wraps.firstWhere((w) => w.id == device.id);
  wrap
    ..keyV = keyV
    ..wrapped = toBase64Url(
      await sealToDevice(
        fromBase64Url(device.publicKey!),
        WrapContext(kind: WrapKind.device, userId: userId, keyV: keyV),
        dk,
      ),
    );
}

/// An account whose device wrap (id [deviceId]) this phone holds: its key pair, [held] data keys
/// by version kept in [storage] with [current] current, and a device wrap of [deviceDk] at
/// [deviceV] on the server. Seeds what Task 10's enroll leaves behind, without it.
Future<({FakeWrap device, Uint8List privateKey})> seedDevice({
  required FakeKeys api,
  required KeyStorage storage,
  required String userId,
  required Map<int, Uint8List> held,
  required int current,
  required Uint8List deviceDk,
  required int deviceV,
  String deviceId = '01930000-0000-7000-8000-0000000000d1',
}) async {
  final pair = await generateDeviceKeyPair();
  final device = FakeWrap(
    id: deviceId,
    kind: 'device',
    ref: deviceId,
    keyV: deviceV,
    wrapped: toBase64Url(
      await sealToDevice(
        pair.publicKey,
        WrapContext(kind: WrapKind.device, userId: userId, keyV: deviceV),
        deviceDk,
      ),
    ),
    publicKey: toBase64Url(pair.publicKey),
    attestation: toBase64Url(
      await deviceAttestation(
        deviceDk,
        DeviceAttestationInput(userId: userId, wrapId: deviceId, publicKey: pair.publicKey),
      ),
    ),
    label: 'Phone',
  );
  api.wraps.add(device);
  for (final MapEntry(key: v, value: dk) in held.entries) {
    await storage.writeDataKey(userId, v, dk);
  }
  await storage.setDevicePrivateKey(userId, pair.privateKey);
  await storage.setDeviceWrap(userId, id: deviceId, publicKey: device.publicKey!);
  await storage.setCurrent(userId, current);
  return (device: device, privateKey: pair.privateKey);
}
