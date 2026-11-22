import 'dart:convert';
import 'dart:typed_data';

import 'errors.dart';
import 'keys.dart';
import 'validate.dart';
import 'wraps.dart';

/// Twin of packages/crypto/src/links.ts: nonce (12) || AES-256-GCM(older data key, 32) with its
/// tag (16).
const linkBytes = 60;

class LinkContext {
  const LinkContext({required this.userId, required this.keyV});

  final String userId;

  /// The newer version (the one whose key seals the link); at least 2.
  final int keyV;
}

Uint8List _checkContext(LinkContext ctx) {
  assertUserId(ctx.userId);
  assertKeyV(ctx.keyV);
  if (ctx.keyV < 2) throw const CryptoError('bad_input', 'keyV of a link must be at least 2');
  return Uint8List.fromList(utf8.encode('wambito/v1/link/${ctx.userId}/${ctx.keyV}'));
}

/// Seals the older data key under a key derived from the newer one. 60 bytes.
Future<Uint8List> sealKeyLink(
  Uint8List newKey,
  Uint8List oldKey,
  LinkContext ctx, {
  Uint8List? nonce,
}) async {
  assertBytes(newKey, 32, 'new key');
  assertBytes(oldKey, 32, 'old key');
  final aad = _checkContext(ctx);
  final iv = nonce ?? randomNonce();
  assertNonce(iv);
  return gcmSeal(await hkdfKey(newKey, 'wambito/v1/link'), aad, oldKey, iv);
}

/// Opens a link with the newer data key; returns the older one. Throws [CryptoError] on failure.
Future<Uint8List> openKeyLink(Uint8List newKey, LinkContext ctx, Uint8List link) async {
  assertBytes(newKey, 32, 'new key');
  final aad = _checkContext(ctx);
  assertBytes(link, linkBytes, 'link');
  final oldKey = await gcmOpen(await hkdfKey(newKey, 'wambito/v1/link'), aad, link);
  if (oldKey.length != 32) throw const CryptoError('cannot_open');
  return oldKey;
}
