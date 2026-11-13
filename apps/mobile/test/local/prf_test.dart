import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/passkeys.dart';
import 'package:wambito/local/keys_error.dart';
import 'package:wambito/local/prf.dart';

/// Ports apps/web/app/local/prf.test.ts. PRF_SALT is SHA-256("wambito/v1/prf") (packages/crypto).
const _saltHex = '999d11fd4d3213d08d6d21fd1e08fa663b32f6c21c4d60374015461bfcfdbedb';
const _saltB64 = 'mZ0R_U0yE9CNbSH9Hgj6Zjsy9sIcTWA3QBVGG_z9vts';

Uint8List bytes(int n, [int fill = 7]) => Uint8List(n)..fillRange(0, n, fill);
String b64(Uint8List b) => base64Url.encode(b).replaceAll('=', '');

class FakePasskeys implements Passkeys {
  FakePasskeys(this.response);
  final String Function(String options) response;
  final calls = <String>[];

  @override
  Future<String> get(String optionsJson) async {
    calls.add(optionsJson);
    return response(optionsJson);
  }

  @override
  Future<bool> supported() async => true;
  @override
  Future<String> getAvailable(String optionsJson) => get(optionsJson);
  @override
  Future<String> create(String optionsJson) => get(optionsJson);
}

String credentialJson(String id, Object? results) =>
    jsonEncode({'id': id, 'clientExtensionResults': results});

void main() {
  group('prfExtension', () {
    test('asks for the PRF evaluated at PRF_SALT', () {
      final first = ((prfExtension()['prf']! as Map)['eval']! as Map)['first'];
      expect(first, _saltB64);
      expect(base64Url.decode(base64Url.normalize(first! as String)), [
        for (var i = 0; i < 64; i += 2) int.parse(_saltHex.substring(i, i + 2), radix: 16),
      ]);
    });
  });

  group('readPrf', () {
    test('is null with no prf', () {
      expect(readPrf({}), isNull);
    });

    test('is null with prf: {} (the Proton Pass shape)', () {
      expect(readPrf({'prf': <String, Object?>{}}), isNull);
      expect(
        readPrf({
          'prf': {'enabled': true},
        }),
        isNull,
      );
    });

    test('is null with 16 bytes', () {
      expect(
        readPrf({
          'prf': {
            'results': {'first': b64(bytes(16))},
          },
        }),
        isNull,
      );
    });

    test('takes results.first as base64url of 32 bytes', () {
      expect(
        readPrf({
          'prf': {
            'results': {'first': b64(bytes(32))},
          },
        }),
        bytes(32),
      );
    });

    test('is null with something that is not base64url', () {
      expect(
        readPrf({
          'prf': {
            'results': {'first': '!!!'},
          },
        }),
        isNull,
      );
      expect(
        readPrf({
          'prf': {
            'results': {'first': 5},
          },
        }),
        isNull,
      );
    });
  });

  group('prfEnabledWithoutResults', () {
    test('is true for enabled without results', () {
      expect(
        prfEnabledWithoutResults({
          'prf': {'enabled': true},
        }),
        isTrue,
      );
    });

    test('is false with results, without prf, or not enabled', () {
      expect(
        prfEnabledWithoutResults({
          'prf': {
            'enabled': true,
            'results': {'first': b64(bytes(32))},
          },
        }),
        isFalse,
      );
      expect(prfEnabledWithoutResults({}), isFalse);
      expect(prfEnabledWithoutResults({'prf': <String, Object?>{}}), isFalse);
    });
  });

  group('evaluatePrf', () {
    const options =
        '{"challenge":"AQIDBA","rpId":"app.wambito.test","userVerification":"required"}';

    test('adds the extension to the options, calls get, and returns the bytes', () async {
      final fake = FakePasskeys(
        (_) => credentialJson('AQID', {
          'prf': {
            'results': {'first': b64(bytes(32))},
          },
        }),
      );
      final result = await evaluatePrf(fake, options);
      expect(result?.credentialId, 'AQID');
      expect(result?.prf, bytes(32));
      final sent = jsonDecode(fake.calls.single) as Map<String, Object?>;
      expect(sent['rpId'], 'app.wambito.test');
      expect(sent['userVerification'], 'required');
      expect(sent['extensions'], prfExtension());
    });

    test('a passkey without PRF results is no_prf', () async {
      final fake = FakePasskeys((_) => credentialJson('c', {'prf': <String, Object?>{}}));
      expect(
        evaluatePrf(fake, options),
        throwsA(isA<KeysError>().having((e) => e.code, 'code', 'no_prf')),
      );
    });

    test('a response without a credential id is a bad_response, not a TypeError', () async {
      final fake = FakePasskeys((_) => jsonEncode({'clientExtensionResults': <String, Object?>{}}));
      expect(
        evaluatePrf(fake, options),
        throwsA(isA<KeysError>().having((e) => e.code, 'code', 'bad_response')),
      );
    });

    test('is null when the person cancels', () async {
      final fake = FakePasskeys(
        (_) => throw const AuthFailure(code: 'AUTH_CANCELLED', status: 400),
      );
      expect(await evaluatePrf(fake, options), isNull);
    });
  });
}
