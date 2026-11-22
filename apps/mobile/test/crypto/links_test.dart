import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/crypto.dart';

import 'helpers.dart';

const user = 'kX3mQ9vTz2LpR8wYb5NcHd7JfA1sUe4B';
const ctx = LinkContext(userId: user, keyV: 2);

void main() {
  test('a link opens to the older key', () async {
    final newKey = generateDataKey();
    final oldKey = generateDataKey();
    final link = await sealKeyLink(newKey, oldKey, ctx);
    expect(link.length, linkBytes);
    expect(linkBytes, 60);
    expect(await openKeyLink(newKey, ctx, link), oldKey);
  });

  test(
    'a link does not open under another key, version or account, or with a flipped byte',
    () async {
      final newKey = generateDataKey();
      final link = await sealKeyLink(newKey, generateDataKey(), ctx);
      expect(await code(() => openKeyLink(generateDataKey(), ctx, link)), 'cannot_open');
      expect(
        await code(() => openKeyLink(newKey, const LinkContext(userId: user, keyV: 3), link)),
        'cannot_open',
      );
      expect(
        await code(
          () => openKeyLink(
            newKey,
            const LinkContext(userId: 'Zq8Rt2WnY5vLc1MbXe9HjD4sAf7GuK0p', keyV: 2),
            link,
          ),
        ),
        'cannot_open',
      );
      for (final i in [0, 12, 59]) {
        expect(await code(() => openKeyLink(newKey, ctx, flipped(link, i))), 'cannot_open');
      }
    },
  );

  test('keyV below 2, a bad user id, keys that are not 32 bytes or a link that is not 60 bytes is bad_input', () async {
    final k = generateDataKey();
    final link = await sealKeyLink(k, generateDataKey(), ctx);
    // keyV is an int in Dart: 1.5 cannot be written.
    for (final keyV in [0, 1, -1, 32768]) {
      final c = LinkContext(userId: user, keyV: keyV);
      expect(await code(() => sealKeyLink(k, k, c)), 'bad_input');
      expect(await code(() => openKeyLink(k, c, link)), 'bad_input');
    }
    expect(
      await code(() => sealKeyLink(k, k, const LinkContext(userId: 'a/b', keyV: 2))),
      'bad_input',
    );
    expect(
      await code(() => openKeyLink(k, const LinkContext(userId: '', keyV: 2), link)),
      'bad_input',
    );
    expect(await code(() => sealKeyLink(k.sublist(0, 31), k, ctx)), 'bad_input');
    expect(await code(() => sealKeyLink(k, k.sublist(0, 31), ctx)), 'bad_input');
    expect(await code(() => openKeyLink(k.sublist(0, 31), ctx, link)), 'bad_input');
    expect(await code(() => openKeyLink(k, ctx, link.sublist(0, 59))), 'bad_input');
    expect(await code(() => openKeyLink(k, ctx, Uint8List(61))), 'bad_input');
    expect(await code(() => sealKeyLink(k, k, ctx, nonce: Uint8List(11))), 'bad_input');
  });
}
