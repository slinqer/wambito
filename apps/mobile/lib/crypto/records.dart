import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';
import 'errors.dart';
import 'keys.dart';
import 'validate.dart';

/// Twin of packages/crypto/src/records.ts. The wire name of a type is its `.name`.
enum RecordType { transaction, category, budget, recurrence, merchant, settings, account }

class RecordContext {
  const RecordContext({
    required this.userId,
    required this.type,
    required this.id,
    required this.keyV,
  });

  final String userId;
  final RecordType type;
  final String id;
  final int keyV;
}

const _padTo = 64;
final AesGcm _aes = AesGcm.with256bits();
const _tagBytes = 16;

Uint8List _associatedData(RecordContext ctx) {
  assertUserId(ctx.userId);
  assertUuid(ctx.id, 'id');
  assertKeyV(ctx.keyV);
  return Uint8List.fromList(
    utf8.encode('wambito/v1/record/${ctx.userId}/${ctx.type.name}/${ctx.id}/${ctx.keyV}'),
  );
}

/// body = nonce (12) || AES-256-GCM ciphertext and tag, over JSON padded with spaces to 64 bytes.
/// [nonce] is only for test vectors: leave it out so a fresh random one is used.
Future<Uint8List> sealRecord(
  RecordKeys keys,
  RecordContext ctx,
  Object? value, {
  Uint8List? nonce,
}) async {
  final aad = _associatedData(ctx);
  final iv = nonce ?? randomNonce();
  assertNonce(iv);
  final String text;
  try {
    text = jsonEncode(value);
  } on Object {
    throw const CryptoError('bad_input', 'value is not JSON');
  }
  final json = utf8.encode(text);
  final padded = ((json.length + _padTo - 1) ~/ _padTo) * _padTo;
  final plain = Uint8List(padded)
    ..fillRange(0, padded, 0x20)
    ..setRange(0, json.length, json);
  final box = await _aes.encrypt(plain, secretKey: keys.record, nonce: iv, aad: aad);
  return Uint8List.fromList([...iv, ...box.cipherText, ...box.mac.bytes]);
}

Future<Object?> openRecord(RecordKeys keys, RecordContext ctx, Uint8List body) async {
  final aad = _associatedData(ctx);
  try {
    if (body.length < nonceBytes + _tagBytes) throw const CryptoError('cannot_open');
    final box = SecretBox(
      body.sublist(nonceBytes, body.length - _tagBytes),
      nonce: body.sublist(0, nonceBytes),
      mac: Mac(body.sublist(body.length - _tagBytes)),
    );
    final plain = await _aes.decrypt(box, secretKey: keys.record, aad: aad);
    return jsonDecode(utf8.decode(plain));
  } on Object {
    throw const CryptoError('cannot_open');
  }
}

/// Stable keyed tag of a text (base64url HMAC-SHA-256), for server-side duplicate detection.
Future<String> dedupeTag(RecordKeys keys, String text) async {
  final mac = await Hmac.sha256().calculateMac(utf8.encode(text), secretKey: keys.dedupe);
  return toBase64Url(Uint8List.fromList(mac.bytes));
}
