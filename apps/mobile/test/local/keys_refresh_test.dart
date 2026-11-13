import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/keys.dart';

import 'fake_keys.dart';

/// The loading-and-acceptance half of apps/web/app/local/keys.test.ts (Task 9). The setup and
/// unlock flows are Task 10's (keys_setup_test.dart); here an enrolled phone is seeded directly.

class Enrolled {
  Enrolled(this.api, this.storage, this.userId, this.dk, this.device);

  final FakeKeys api;
  final KeyStorage storage;
  final String userId;
  final Uint8List dk;
  final FakeWrap device;

  KeysOptions get options => KeysOptions(userId: userId, dio: api.dio(), storage: storage);
}

/// An account set up on this phone at v1, with its DK for checks.
Future<Enrolled> enrolledAccount() async {
  final api = FakeKeys();
  final storage = memoryKeyStorage();
  final userId = newUser();
  final dk = generateDataKey();
  final seeded = await seedDevice(
    api: api,
    storage: storage,
    userId: userId,
    held: {1: Uint8List.fromList(dk)},
    current: 1,
    deviceDk: dk,
    deviceV: 1,
  );
  return Enrolled(api, storage, userId, dk, seeded.device);
}

void main() {
  recordOpenedKeys();

  group('KeyStorage', () {
    test('keeps each key under wambito.vault.<userId>.*, base64url', () async {
      final storage = memoryKeyStorage();
      final dk = generateDataKey();
      final priv = generateDataKey();
      await storage.writeDataKey('user_a', 2, dk);
      await storage.setCurrent('user_a', 2);
      await storage.setDevicePrivateKey('user_a', priv);
      await storage.setDeviceWrap('user_a', id: rec, publicKey: 'cHVi');
      expect(await storedEntries(), {
        'wambito.vault.user_a.current': '2',
        'wambito.vault.user_a.device': toBase64Url(priv),
        'wambito.vault.user_a.devicePublicKey': 'cHVi',
        'wambito.vault.user_a.deviceWrapId': rec,
        'wambito.vault.user_a.dk.2': toBase64Url(dk),
      });
      expect(await storage.readDataKey('user_a', 2), dk);
      expect(await storage.current('user_a'), 2);
      expect(await storage.devicePrivateKey('user_a'), priv);
      expect(await storage.versions('user_a'), [2]);
    });

    test('refuses a device private key that is not 32 bytes', () async {
      final storage = memoryKeyStorage();
      for (final length in [0, 31, 33, 64]) {
        expect(() => storage.setDevicePrivateKey('user_a', Uint8List(length)), throwsArgumentError);
      }
      expect(await storedEntries(), isEmpty);
    });

    test('refuses a user id that could reach into another account\'s names', () async {
      final storage = memoryKeyStorage();
      for (final id in ['', 'a.b', 'a/b', 'a b']) {
        expect(() => storage.current(id), throwsArgumentError);
      }
    });

    test('deleteAll removes one account\'s keys only', () async {
      final storage = memoryKeyStorage({
        'wambito.encryption.user_a': 'preview',
        'wambito.vault.user_ab.current': '1',
        'session.token': 'abc',
      });
      await storage.writeDataKey('user_a', 1, generateDataKey());
      await storage.setCurrent('user_a', 1);
      await storage.deleteAll('user_a');
      expect((await storedEntries()).keys, [
        'session.token',
        'wambito.encryption.user_a',
        'wambito.vault.user_ab.current',
      ]);
    });
  });

  group('loadLocalKeys', () {
    test('is null in a browser that was never set up', () async {
      expect(await loadLocalKeys(newUser(), memoryKeyStorage()), isNull);
    });

    test('keysOfAnotherAccountAreNeverLoaded', () async {
      final a = await enrolledAccount();
      expect(await loadLocalKeys(a.userId, a.storage), isNotNull);
      final b = newUser();
      // B has a current version and device names of its own, but only A holds `dk.1`
      await a.storage.setCurrent(b, 1);
      await a.storage.setDevicePrivateKey(b, generateDataKey());
      await a.storage.setDeviceWrap(b, id: a.device.id, publicKey: a.device.publicKey!);
      expect(await a.storage.versions(b), isEmpty);
      expect(await loadLocalKeys(b, a.storage), isNull);
      // and B's refresh finds no keys of its own: it never opens A's device wrap
      final err = await caught(
        () => refreshKeys(KeysOptions(userId: b, dio: a.api.dio(), storage: a.storage)),
      );
      expect(err, isKeysError('device_removed'));
      expect(a.api.calls, isEmpty);
      expect(openedDevice, isEmpty);
    });

    test('is null when the current version\'s key is missing', () async {
      final a = await enrolledAccount();
      await a.storage.setCurrent(a.userId, 2);
      expect(await loadLocalKeys(a.userId, a.storage), isNull);
    });

    test('derives the record keys of every held version', () async {
      final a = await enrolledAccount();
      final local = (await loadLocalKeys(a.userId, a.storage))!;
      expect(local.keyring.current, 1);
      expect(local.keyring.byVersion.keys, [1]);
      expect(await opensUnder(local, a.userId, a.dk, 1), isTrue);
    });
  });

  group('forgetDevice', () {
    test('removes the keys', () async {
      final a = await enrolledAccount();
      await forgetDevice(a.userId, a.storage);
      expect(await loadLocalKeys(a.userId, a.storage), isNull);
      expect(await storedEntries(), isEmpty);
    });
  });

  group('the signed-in account', () {
    test('every /v2/keys call names the vault\'s account', () async {
      final a = await enrolledAccount();
      await rotateDeviceWrap(a.api, a.userId, a.device, generateDataKey(), 2, a.dk);
      await refreshKeys(a.options);
      expect(a.api.calls, isNotEmpty);
      expect(a.api.calls.every((c) => c.user == a.userId), isTrue);
    });

    test('409 session_changed throws session_changed and stores nothing', () async {
      final a = await enrolledAccount();
      final before = await storedEntries();
      a.api.answerAll = (409, {'code': 'session_changed'});
      final err = await caught(() => refreshKeys(a.options));
      expect(err, isKeysError('session_changed', 409));
      expect(await storedEntries(), before);
    });

    test('the other error answers map as the web maps them', () async {
      final a = await enrolledAccount();
      final call = api(a.options);
      for (final (status, code, expected) in [
        (409, 'already_set_up', 'already_set_up'),
        (409, 'key_version_mismatch', 'rotated_elsewhere'),
        (422, 'unknown_passkey', 'unknown_passkey'),
        (409, 'other', 'server'),
        (500, null, 'server'),
      ]) {
        a.api.answerAll = (status, {'code': code});
        expect(await caught(() => call('/v2/keys')), isKeysError(expected, status));
      }
      a.api
        ..answerAll = null
        ..offline = true;
      expect(await caught(() => call('/v2/keys')), isKeysError('offline'));
    });
  });

  group('the keyring', () {
    test('dropKeyVersion removes record:1 and dedupe:1 only', () async {
      final a = await enrolledAccount();
      await rotateDeviceWrap(a.api, a.userId, a.device, generateDataKey(), 2, a.dk);
      await refreshKeys(a.options);

      await dropKeyVersion(a.userId, 1, a.storage);
      expect(await a.storage.readDataKey(a.userId, 1), isNull);
      expect(await a.storage.readDataKey(a.userId, 2), isNotNull);
      expect(await a.storage.devicePrivateKey(a.userId), isNotNull);
      final local = await loadLocalKeys(a.userId, a.storage);
      expect(local?.keyring.current, 2);
      expect(local?.keyring.byVersion.keys, [2]);
    });
  });

  group('withDataKey', () {
    test('withDataKey opens this browser\'s device wrap and zeroes DK after', () async {
      final a = await enrolledAccount();
      Uint8List? seen;
      Uint8List? copy;
      final result = await withDataKey(a.options, (key, keyV) async {
        seen = key;
        copy = Uint8List.fromList(key);
        return keyV;
      });
      expect(result, 1);
      expect(copy, a.dk);
      expect(zeroed(seen!), isTrue);
    });

    test('zeroes DK when fn throws too', () async {
      final a = await enrolledAccount();
      Uint8List? seen;
      final err = await caught(
        () => withDataKey<int>(a.options, (key, _) async {
          seen = key;
          throw StateError('boom');
        }),
      );
      expect((err! as StateError).message, 'boom');
      expect(zeroed(seen!), isTrue);
    });

    test('a device key with no current version is tampered: fn never runs', () async {
      final a = await enrolledAccount();
      await const FlutterSecureStorage().delete(key: 'wambito.vault.${a.userId}.current');
      final before = await storedEntries();
      var ran = false;
      final err = await caught(() => withDataKey(a.options, (_, _) async => ran = true));
      expect(err, isKeysError('tampered'));
      expect(ran, isFalse);
      expect(openedDevice, hasLength(1));
      expect(openedDevice.every(zeroed), isTrue);
      expect(await storedEntries(), before);
    });

    test('withDataKey throws device_removed when no device wrap has this browser\'s id', () async {
      final a = await enrolledAccount();
      a.api.wraps.removeWhere((w) => w.id == a.device.id);
      var ran = false;
      final err = await caught(() => withDataKey(a.options, (_, _) async => ran = true));
      expect(err, isKeysError('device_removed'));
      expect(ran, isFalse);
    });

    test('a wrap at a held keyV that holds another DK is tampered: fn never runs', () async {
      final a = await enrolledAccount();
      await rotateDeviceWrap(a.api, a.userId, a.device, generateDataKey(), 1);
      var ran = false;
      final err = await caught(() => withDataKey(a.options, (_, _) async => ran = true));
      expect(err, isKeysError('tampered'));
      expect(ran, isFalse);
      expect(openedDevice, hasLength(1));
      expect(openedDevice.every(zeroed), isTrue);
    });

    test('withDataKey refuses a forged v+1: no link, or a link to another key, is tampered; fn never runs', () async {
      final a = await enrolledAccount();
      final forged = generateDataKey();
      await rotateDeviceWrap(a.api, a.userId, a.device, forged, 2);
      var ran = false;
      expect(
        await caught(() => withDataKey(a.options, (_, _) async => ran = true)),
        isKeysError('tampered'),
      );

      // a link the server made: it leads to a key this browser never held
      await addLink(a.api, a.userId, forged, generateDataKey(), 2);
      openedLinks.clear();
      expect(
        await caught(() => withDataKey(a.options, (_, _) async => ran = true)),
        isKeysError('tampered'),
      );
      expect(ran, isFalse);
      expect(openedLinks, hasLength(1));
      expect(openedLinks.every(zeroed), isTrue);
      expect(openedDevice.every(zeroed), isTrue);
    });

    test(
      'withDataKey accepts v+1 whose link leads to the held key, and zeroes what it opened',
      () async {
        final a = await enrolledAccount();
        final next = generateDataKey();
        await rotateDeviceWrap(a.api, a.userId, a.device, next, 2, a.dk);
        openedLinks.clear();
        Uint8List? copy;
        final keyV = await withDataKey(a.options, (key, v) async {
          copy = Uint8List.fromList(key);
          return v;
        });
        expect(keyV, 2);
        expect(copy, next);
        expect(openedLinks, hasLength(1));
        expect(openedLinks.every(zeroed), isTrue);
      },
    );

    test(
      'a vault without its device wrap id is device_removed (the phone has no 2a scan)',
      () async {
        final a = await enrolledAccount();
        final entries = await storedEntries();
        final storage = memoryKeyStorage({
          for (final MapEntry(:key, :value) in entries.entries)
            if (!key.endsWith('.deviceWrapId')) key: value,
        });
        var ran = false;
        final err = await caught(
          () => withDataKey(
            KeysOptions(userId: a.userId, dio: a.api.dio(), storage: storage),
            (_, _) async => ran = true,
          ),
        );
        expect(err, isKeysError('device_removed'));
        expect(ran, isFalse);
      },
    );
  });

  group('refreshKeys', () {
    test('refreshKeys adds the new version and keeps the old one', () async {
      final a = await enrolledAccount();
      final next = generateDataKey();
      await rotateDeviceWrap(a.api, a.userId, a.device, next, 2, a.dk);

      final local = await refreshKeys(a.options);
      expect(local.keyring.current, 2);
      expect(local.keyring.byVersion.keys, [1, 2]);
      final sealed = await sealRecord(await deriveRecordKeys(next), ctx(a.userId, 2), {'s': 2});
      expect(await openRecord(currentKeys(local), ctx(a.userId, 2), sealed), {'s': 2});

      final again = await loadLocalKeys(a.userId, a.storage);
      expect(again?.keyring.current, 2);
      expect(again?.keyring.byVersion.keys, [1, 2]);
    });

    test('a replayed lower-version wrap leaves current and the stored keys unchanged', () async {
      final a = await enrolledAccount();
      final next = generateDataKey();
      await rotateDeviceWrap(a.api, a.userId, a.device, next, 2, a.dk);
      await refreshKeys(a.options);
      // the server replays the old keyV 1 wrap (it opens: it is sealed to this browser)
      await rotateDeviceWrap(a.api, a.userId, a.device, a.dk, 1);
      final before = await storedEntries();

      final local = await refreshKeys(a.options);
      expect(local.keyring.current, 2);
      expect(await a.storage.current(a.userId), 2);
      expect(await storedEntries(), before);
      final again = (await loadLocalKeys(a.userId, a.storage))!;
      expect(again.keyring.current, 2);
      expect(await opensUnder(again, a.userId, a.dk, 1), isTrue);
      expect(await opensUnder(again, a.userId, next, 2), isTrue);
    });

    test(
      'a same-version wrap under another DK is tampered and does not overwrite record:<v>',
      () async {
        final a = await enrolledAccount();
        final before = await storedEntries();
        await rotateDeviceWrap(a.api, a.userId, a.device, generateDataKey(), 1);

        expect(await caught(() => refreshKeys(a.options)), isKeysError('tampered'));
        expect(await storedEntries(), before);
        final local = (await loadLocalKeys(a.userId, a.storage))!;
        expect(local.keyring.current, 1);
        expect(await opensUnder(local, a.userId, a.dk, 1), isTrue);
        expect(openedDevice.every(zeroed), isTrue);
      },
    );

    test('refreshKeys refuses a forged v+1, keeps nothing, and current stays v', () async {
      final a = await enrolledAccount();
      final before = await storedEntries();
      final forged = generateDataKey();
      await rotateDeviceWrap(a.api, a.userId, a.device, forged, 2);
      expect(await caught(() => refreshKeys(a.options)), isKeysError('tampered'));
      await addLink(a.api, a.userId, forged, generateDataKey(), 2);
      expect(await caught(() => refreshKeys(a.options)), isKeysError('tampered'));
      expect(await storedEntries(), before);
      expect((await loadLocalKeys(a.userId, a.storage))?.keyring.current, 1);
      expect(openedDevice, hasLength(2));
      expect(openedDevice.every(zeroed), isTrue);
    });

    test(
      'refreshKeys at v reaching v+2 keeps v+1 and v+2, and a record sealed under v+1 opens',
      () async {
        final a = await enrolledAccount();
        final dk2 = generateDataKey();
        final dk3 = generateDataKey();
        await addLink(a.api, a.userId, dk2, a.dk, 2);
        await rotateDeviceWrap(a.api, a.userId, a.device, dk3, 3, dk2);
        openedLinks.clear();

        final local = await refreshKeys(a.options);
        expect(local.keyring.current, 3);
        expect(local.keyring.byVersion.keys, [1, 2, 3]);
        expect(await opensUnder(local, a.userId, a.dk, 1), isTrue);
        expect(await opensUnder(local, a.userId, dk2, 2), isTrue);
        expect(await opensUnder(local, a.userId, dk3, 3), isTrue);
        expect(openedLinks, hasLength(2));
        expect(openedLinks.every(zeroed), isTrue);
        expect(openedDevice.every(zeroed), isTrue);
      },
    );

    test(
      'a broken middle link (v+2 → v+1 fine, v+1 → v wrong) is tampered and keeps nothing',
      () async {
        final a = await enrolledAccount();
        final before = await storedEntries();
        final dk2 = generateDataKey();
        final dk3 = generateDataKey();
        await addLink(a.api, a.userId, dk2, generateDataKey(), 2);
        await rotateDeviceWrap(a.api, a.userId, a.device, dk3, 3, dk2);
        openedLinks.clear();

        expect(await caught(() => refreshKeys(a.options)), isKeysError('tampered'));
        expect(await storedEntries(), before);
        expect((await loadLocalKeys(a.userId, a.storage))?.keyring.current, 1);
        expect(openedLinks, hasLength(2));
        expect(openedLinks.every(zeroed), isTrue);
      },
    );

    test('refreshKeys refuses a device wrap whose public key is not this browser\'s', () async {
      final a = await enrolledAccount();
      final other = await generateDeviceKeyPair();
      a.api.wraps.firstWhere((w) => w.id == a.device.id).publicKey = toBase64Url(other.publicKey);
      expect(await caught(() => refreshKeys(a.options)), isKeysError('device_removed'));
      expect((await loadLocalKeys(a.userId, a.storage))?.keyring.current, 1);
    });

    test('refreshKeys without held keys is device_removed and calls nothing', () async {
      final api = FakeKeys();
      final err = await caught(
        () => refreshKeys(
          KeysOptions(userId: newUser(), dio: api.dio(), storage: memoryKeyStorage()),
        ),
      );
      expect(err, isKeysError('device_removed'));
      expect(api.calls, isEmpty);
    });
  });

  group('unlocking an account that rotated', () {
    /// DK(1..3) and links 2 and 3 (unless left out or wrong), as `rotatedTwice` in keys.test.ts.
    Future<({FakeKeys api, String userId, Uint8List dk1, Uint8List dk2, Uint8List dk3})>
    rotatedTwice({String? link2}) async {
      final api = FakeKeys();
      final userId = newUser();
      final dk1 = generateDataKey();
      final dk2 = generateDataKey();
      final dk3 = generateDataKey();
      if (link2 == null) await addLink(api, userId, dk2, dk1, 2);
      if (link2 == 'wrong') await addLink(api, userId, dk2, generateDataKey(), 2);
      await addLink(api, userId, dk3, dk2, 3);
      return (api: api, userId: userId, dk1: dk1, dk2: dk2, dk3: dk3);
    }

    test('an own device wrap below the held current version, at a version this browser does not hold, is tampered', () async {
      final r = await rotatedTwice();
      final storage = memoryKeyStorage();
      // the server withheld every link at a fresh unlock: the phone holds only v3
      final seeded = await seedDevice(
        api: r.api,
        storage: storage,
        userId: r.userId,
        held: {3: Uint8List.fromList(r.dk3)},
        current: 3,
        deviceDk: r.dk3,
        deviceV: 3,
      );
      // later it serves this phone's own wrap id at v2, sealed with a key of its own
      await rotateDeviceWrap(r.api, r.userId, seeded.device, generateDataKey(), 2);
      final before = await storedEntries();
      openedDevice.clear();
      var ran = false;
      final err = await caught(
        () => withDataKey(
          KeysOptions(userId: r.userId, dio: r.api.dio(), storage: storage),
          (_, _) async => ran = true,
        ),
      );
      expect(err, isKeysError('tampered'));
      expect(ran, isFalse);
      expect(openedDevice, hasLength(1));
      expect(openedDevice.every(zeroed), isTrue);
      expect(await storedEntries(), before);
    });

    test('an own device wrap below the held current version with the held key of that version still opens', () async {
      final r = await rotatedTwice();
      final storage = memoryKeyStorage();
      final seeded = await seedDevice(
        api: r.api,
        storage: storage,
        userId: r.userId,
        held: {
          1: Uint8List.fromList(r.dk1),
          2: Uint8List.fromList(r.dk2),
          3: Uint8List.fromList(r.dk3),
        },
        current: 3,
        deviceDk: r.dk3,
        deviceV: 3,
      );
      await rotateDeviceWrap(r.api, r.userId, seeded.device, r.dk2, 2);
      final options = KeysOptions(userId: r.userId, dio: r.api.dio(), storage: storage);
      expect(await withDataKey(options, (_, v) async => v), 2);
    });

    // The walks of the trusted ways in (passkey and recovery: not strict; pairing: strict). Task
    // 10 ports the full unlock flows with these names; here `olderForTrustedKey` runs alone.
    group('olderForTrustedKey', () {
      test('unlockWithRecovery on a fresh browser keeps every version the links reach', () async {
        final r = await rotatedTwice();
        final storage = memoryKeyStorage();
        final older = await olderForTrustedKey(
          r.userId,
          (keyV: 3, dataKey: r.dk3),
          (await listKeys(api(KeysOptions(userId: r.userId, dio: r.api.dio(), storage: storage))))
              .links,
          HeldVault.secret,
          storage,
        );
        expect(older.keys, [2, 1]);
        expect(older[2], r.dk2);
        expect(older[1], r.dk1);
        expect(openedLinks, hasLength(2));
      });

      test('unlockWithRecovery on an account whose link 2 is missing keeps v2 and v3 only, without error', () async {
        final r = await rotatedTwice(link2: 'missing');
        final storage = memoryKeyStorage();
        final older = await olderForTrustedKey(
          r.userId,
          (keyV: 3, dataKey: r.dk3),
          await _links(r.api, r.userId, storage),
          HeldVault.secret,
          storage,
        );
        expect(older.keys, [2]);
        expect(older[2], r.dk2);
      });

      test('unlockWithPasskey on a browser holding v whose chain does not reach its key unlocks, keeps the held v and the trusted n', () async {
        final r = await rotatedTwice(link2: 'wrong');
        final storage = memoryKeyStorage();
        await seedDevice(
          api: r.api,
          storage: storage,
          userId: r.userId,
          held: {1: Uint8List.fromList(r.dk1)},
          current: 1,
          deviceDk: r.dk1,
          deviceV: 1,
        );
        final before = await storedEntries();
        final older = await olderForTrustedKey(
          r.userId,
          (keyV: 3, dataKey: r.dk3),
          await _links(r.api, r.userId, storage),
          HeldVault.secret,
          storage,
        );
        expect(older[2], r.dk2);
        // the walk never writes: the held v1 stays the phone's own (Task 10's keep skips it)
        expect(await storedEntries(), before);
        expect(await storage.readDataKey(r.userId, 1), r.dk1);
      });

      test(
        'unlockWithRecovery on a browser holding v whose v+1 has no link keeps v and v+1',
        () async {
          final api = FakeKeys();
          final userId = newUser();
          final storage = memoryKeyStorage();
          final dk1 = generateDataKey();
          await seedDevice(
            api: api,
            storage: storage,
            userId: userId,
            held: {1: Uint8List.fromList(dk1)},
            current: 1,
            deviceDk: dk1,
            deviceV: 1,
          );
          final older = await olderForTrustedKey(
            userId,
            (keyV: 2, dataKey: generateDataKey()),
            await _links(api, userId, storage),
            HeldVault.secret,
            storage,
          );
          expect(older, isEmpty);
        },
      );

      test(
        'a recovery wrap below the held current version is tampered: nothing sent, kept or deleted',
        () async {
          final r = await rotatedTwice();
          final storage = memoryKeyStorage();
          await seedDevice(
            api: r.api,
            storage: storage,
            userId: r.userId,
            held: {
              1: Uint8List.fromList(r.dk1),
              2: Uint8List.fromList(r.dk2),
              3: Uint8List.fromList(r.dk3),
            },
            current: 3,
            deviceDk: r.dk3,
            deviceV: 3,
          );
          final before = await storedEntries();
          final links = await _links(r.api, r.userId, storage);
          final calls = r.api.calls.length;
          for (final held in HeldVault.values) {
            expect(
              await caught(
                () => olderForTrustedKey(r.userId, (keyV: 1, dataKey: r.dk1), links, held, storage),
              ),
              isKeysError('tampered'),
            );
          }
          expect(r.api.calls.length, calls);
          expect(await storedEntries(), before);
        },
      );

      test(
        'unlockWithRecovery on a browser holding v walks down to its key and keeps the newer ones',
        () async {
          final r = await rotatedTwice();
          final storage = memoryKeyStorage();
          await seedDevice(
            api: r.api,
            storage: storage,
            userId: r.userId,
            held: {1: Uint8List.fromList(r.dk1)},
            current: 1,
            deviceDk: r.dk1,
            deviceV: 1,
          );
          for (final held in HeldVault.values) {
            final older = await olderForTrustedKey(
              r.userId,
              (keyV: 3, dataKey: r.dk3),
              await _links(r.api, r.userId, storage),
              held,
              storage,
            );
            expect(older.keys, [2, 1]);
            expect(older[2], r.dk2);
            expect(older[1], r.dk1);
          }
        },
      );

      test('enrollDevice (pairing) keeps the older versions the links reach', () async {
        final r = await rotatedTwice();
        final storage = memoryKeyStorage();
        final older = await olderForTrustedKey(
          r.userId,
          (keyV: 3, dataKey: r.dk3),
          await _links(r.api, r.userId, storage),
          HeldVault.strict,
          storage,
        );
        expect(older.keys, [2, 1]);
        expect(r.dk3.any((b) => b != 0), isTrue);
      });

      test('enrollDevice (pairing) with a vault held here stays strict: a chain that does not reach its key is tampered', () async {
        final r = await rotatedTwice(link2: 'wrong');
        final storage = memoryKeyStorage();
        await seedDevice(
          api: r.api,
          storage: storage,
          userId: r.userId,
          held: {1: Uint8List.fromList(r.dk1)},
          current: 1,
          deviceDk: r.dk1,
          deviceV: 1,
        );
        final before = await storedEntries();
        openedLinks.clear();
        expect(
          await caught(
            () => olderForTrustedKey(
              r.userId,
              (keyV: 3, dataKey: r.dk3),
              r.api.links.map((v, l) => MapEntry(v, fromBase64Url(l))),
              HeldVault.strict,
              storage,
            ),
          ),
          isKeysError('tampered'),
        );
        expect(await storedEntries(), before);
        expect(openedLinks, hasLength(2));
        expect(openedLinks.every(zeroed), isTrue);
        expect(r.dk3.any((b) => b != 0), isTrue);
      });
    });
  });

  group('chainDown', () {
    test('strict: a missing link is tampered; not strict: the walk stops there', () async {
      final userId = newUser();
      final dk1 = generateDataKey();
      final dk2 = generateDataKey();
      final dk3 = generateDataKey();
      final link3 = await sealKeyLink(dk3, dk2, LinkContext(userId: userId, keyV: 3));
      final links = {3: link3};
      expect(
        await caught(() => chainDown(userId, (keyV: 3, dataKey: dk3), links, 1, true)),
        isKeysError('tampered'),
      );
      expect(openedLinks.every(zeroed), isTrue);
      final older = await chainDown(userId, (keyV: 3, dataKey: dk3), links, 1, false);
      expect(older.keys, [2]);
      expect(older[2], dk2);
      links[2] = await sealKeyLink(dk2, dk1, LinkContext(userId: userId, keyV: 2));
      expect((await chainDown(userId, (keyV: 3, dataKey: dk3), links, 2, true)).keys, [2]);
    });
  });
}

Future<Map<int, Uint8List>> _links(FakeKeys fake, String userId, KeyStorage storage) async =>
    (await listKeys(api(KeysOptions(userId: userId, dio: fake.dio(), storage: storage)))).links;
