// `SecurityApi.removeDevice`'s call (twin of `removeDevice` in security.ts): `DELETE /v2/keys/{id}`;
// a wrap already gone (404) counts as removed; no connection is `offline`, anything else `failed`.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/local/keys.dart' show KeysApi;
import 'package:wambito/local/keys_error.dart';
import 'package:wambito/settings/security/security_api.dart';

KeysApi _answering(List<String> calls, [Object? failure]) =>
    (path, {method = 'GET', data, headers}) async {
      calls.add('$method $path');
      if (failure != null) throw failure;
      return Response<Object?>(requestOptions: RequestOptions(path: path), statusCode: 204);
    };

Future<String?> _codeOf(Future<void> future) async {
  try {
    await future;
    return null;
  } on Object catch (error) {
    return codeOf(error);
  }
}

void main() {
  test('deletes the wrap by its id', () async {
    final calls = <String>[];
    await removeDeviceWrap(_answering(calls), 'abc');
    expect(calls, ['DELETE /v2/keys/abc']);
  });

  test('a wrap already gone (404) is done', () async {
    final calls = <String>[];
    await removeDeviceWrap(_answering(calls, const KeysError('server', status: 404)), 'abc');
    expect(calls, hasLength(1));
  });

  test('no connection is offline', () async {
    expect(
      await _codeOf(removeDeviceWrap(_answering([], const KeysError('offline')), 'abc')),
      'offline',
    );
  });

  test('anything else is failed', () async {
    for (final failure in [
      const KeysError('server', status: 500),
      const KeysError('unauthenticated', status: 401),
      StateError('boom'),
    ]) {
      expect(await _codeOf(removeDeviceWrap(_answering([], failure), 'abc')), 'failed');
    }
  });
}
