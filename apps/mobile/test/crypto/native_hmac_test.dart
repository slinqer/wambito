import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/crypto/keys.dart' show hkdfKey;

/// cryptography_flutter's Android HMAC builds a `SecretKeySpec`, which refuses an empty key
/// ("Empty key"). This HMAC refuses one the same way, so the derivations are checked against what
/// the phone really runs, not only the pure Dart implementation.
class _NoEmptyKeyHmac extends DartHmac {
  const _NoEmptyKeyHmac() : super(const DartSha256());

  @override
  Future<Mac> calculateMac(
    List<int> bytes, {
    required SecretKey secretKey,
    List<int> nonce = const <int>[],
    List<int> aad = const <int>[],
  }) async {
    if ((await secretKey.extractBytes()).isEmpty) throw ArgumentError('Empty key');
    return super.calculateMac(bytes, secretKey: secretKey, nonce: nonce, aad: aad);
  }
}

class _NativeLikeCryptography extends DartCryptography {
  @override
  Hmac hmac(HashAlgorithm hashAlgorithm) =>
      hashAlgorithm is Sha256 ? const _NoEmptyKeyHmac() : super.hmac(hashAlgorithm);
}

void main() {
  late Cryptography previous;
  setUp(() {
    previous = Cryptography.instance;
    Cryptography.instance = _NativeLikeCryptography();
  });
  tearDown(() => Cryptography.instance = previous);

  test('the record keys derive with an HMAC that refuses an empty key', () async {
    final keys = await deriveRecordKeys(Uint8List(32));
    expect(await keys.record.extractBytes(), hasLength(32));
    expect(await keys.dedupe.extractBytes(), hasLength(32));
  });

  test('an empty salt and a salt of 32 zero bytes give the same key (RFC 5869)', () async {
    Cryptography.instance = previous;
    final secret = Uint8List.fromList(List.generate(32, (i) => i));
    final empty = await Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    ).deriveKey(secretKey: SecretKey(secret), nonce: const <int>[], info: const [1, 2, 3]);
    final zeros = await hkdfKey(secret, String.fromCharCodes(const [1, 2, 3]));
    expect(await zeros.extractBytes(), await empty.extractBytes());
  });
}
