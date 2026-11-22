import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Wambi's scenes shared with the web: the five "¿Cómo funciona?" steps and the four handshakes of
/// the `Conectar <app>` sheet. The same files on the web (/wambi/) and in the app's assets, each a
/// 512 px VP8X WebP with alpha.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  final scenes = [
    for (var n = 1; n <= 5; n++) 'capture-step$n',
    for (final agent in ['claude', 'chatgpt', 'lumo', 'grok']) 'handshake-$agent',
  ];

  for (final scene in scenes) {
    test('$scene is byte-identical to the web copy', () {
      final mobile = File('assets/wambi/$scene.webp').readAsBytesSync();
      final web = File('../web/public/wambi/$scene.webp').readAsBytesSync();
      expect(mobile, equals(web));
    });

    test('$scene is a VP8X WebP with alpha, 512 px wide', () {
      final bytes = File('assets/wambi/$scene.webp').readAsBytesSync();
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 16)), 'WEBPVP8X');
      expect(bytes[20] & 0x10, isNot(0), reason: 'the alpha flag');
      final width = 1 + bytes[24] + (bytes[25] << 8) + (bytes[26] << 16);
      expect(width, 512);
    });

    test('pubspec declares $scene', () {
      expect(pubspec, contains('assets/wambi/$scene.webp'));
    });
  }
}
