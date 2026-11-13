// Port of apps/web/app/local/ids.ts: ids of the local backend. Lower-case UUID v7 for new
// records, v5 for recurrence occurrences.
import 'dart:convert' show utf8;
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha1;

final Random _random = Random.secure();

String _hex(Uint8List bytes) {
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

int _lastMs = 0;
int _sequence = 0;

/// A UUID v7 (RFC 9562): 48 bits of milliseconds, a 12-bit sequence, 62 random bits. Ids made in
/// the same process always increase, even within one millisecond or if the clock steps back: the
/// sequence counts up (the time borrows a millisecond if it overflows).
String uuidv7([int? nowMs]) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final random = Uint8List.fromList([for (var i = 0; i < 10; i++) _random.nextInt(256)]);
  if (now > _lastMs) {
    _lastMs = now;
    // Start below the top so a burst within one millisecond has room to count up.
    _sequence = ((random[0] << 8) | random[1]) & 0x7ff;
  } else {
    _sequence += 1;
    if (_sequence > 0xfff) {
      _lastMs += 1;
      _sequence = 0;
    }
  }
  final bytes = Uint8List(16);
  var ms = _lastMs;
  for (var i = 5; i >= 0; i--) {
    bytes[i] = ms % 256;
    ms = ms ~/ 256;
  }
  bytes[6] = 0x70 | (_sequence >> 8);
  bytes[7] = _sequence & 0xff;
  bytes[8] = 0x80 | (random[2] & 0x3f);
  for (var i = 3; i < 10; i++) {
    bytes[6 + i] = random[i];
  }
  return _hex(bytes);
}

/// A UUID v5 (RFC 4122): SHA-1 of the namespace id and the name. Sync here (the web's is async
/// only because WebCrypto has no sync hash).
String uuidv5(String namespace, String name) {
  final ns = namespace.replaceAll('-', '');
  if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(ns)) {
    throw ArgumentError('uuidv5: the namespace must be a UUID');
  }
  final nsBytes = [for (var i = 0; i < 32; i += 2) int.parse(ns.substring(i, i + 2), radix: 16)];
  final input = [...nsBytes, ...utf8.encode(name)];
  final digest = Uint8List.fromList(sha1.convert(input).bytes.sublist(0, 16));
  digest[6] = 0x50 | (digest[6] & 0x0f);
  digest[8] = 0x80 | (digest[8] & 0x3f);
  return _hex(digest);
}
