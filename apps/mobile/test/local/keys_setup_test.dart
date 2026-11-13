import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/keys.dart';
import 'package:wambito/local/prf.dart';

import 'fake_keys.dart';

/// The setup-and-unlock half of apps/web/app/local/keys.test.ts (Task 10): `prepareAccount`,
/// `unlockWithRecovery`, `unlockWithPasskey`, `addPasskeyWrap` and `enrollDevice`, against the
/// fake `/v2/keys`. The phone keeps raw data keys, so where the web checks `extractable: false` the
/// phone checks the stored DK. Not ported: the web's `unsupported_browser` cases (the phone keeps
/// its raw X25519 key in the Keychain / Keystore by design) and the 2a legacy vault cases (no
/// phone had a 2a vault).

final _recoveryKeyShape = RegExp(r'^([0-9A-Z]{4}-){6}[0-9A-Z]{3}$');

/// Every recovery secret `parseRecoveryKey` handed out, to check that unlock zeroes it.
final parsedSecrets = <Uint8List>[];

KeysOptions optionsOf(FakeKeys api, String userId, KeyStorage storage) =>
    KeysOptions(userId: userId, dio: api.dio(), storage: storage);

/// Prepares and commits at once, as the setup screen does once the person confirmed the key.
Future<String?> setUpAccount(KeysOptions options, {bool guest = false}) async {
  final prepared = await prepareAccount(options, guest: guest);
  await prepared.commit();
  return prepared.recoveryKey;
}

Future<Uint8List> openRecovery(FakeKeys api, String userId, String recoveryKey) {
  final recovery = api.wraps.firstWhere((w) => w.kind == 'recovery');
  return unwrapDataKey(
    parseRecoveryKey(recoveryKey),
    WrapContext(kind: WrapKind.recovery, userId: userId, keyV: recovery.keyV),
    fromBase64Url(recovery.wrapped),
  );
}

/// An account set up on this phone, then forgotten (another phone set it up): its recovery key.
class Account {
  Account(this.api, this.storage, this.userId, this.recoveryKey);

  final FakeKeys api;
  final KeyStorage storage;
  final String userId;
  final String recoveryKey;

  KeysOptions get options => optionsOf(api, userId, storage);
}

Future<Account> accountWithKey({List<String>? passkeys}) async {
  final api = FakeKeys(passkeys: passkeys);
  final storage = memoryKeyStorage();
  final userId = newUser();
  final recoveryKey = await setUpAccount(optionsOf(api, userId, storage));
  await forgetDevice(userId, storage);
  return Account(api, storage, userId, recoveryKey!);
}

const cred = 'cHJmLWNyZWRlbnRpYWw';
Uint8List prfOf(int fill) => Uint8List(32)..fillRange(0, 32, fill);

/// No `device_removed` after a setup or an unlock: this phone's device wrap is the one it kept.
Future<void> expectRefreshes(KeysOptions options) async {
  expect((await refreshKeys(options)).keyring.current, isPositive);
}

void main() {
  recordOpenedKeys();
  setUp(() {
    parsedSecrets.clear();
    keysParseRecoveryKey = (text) {
      final secret = parseRecoveryKey(text);
      parsedSecrets.add(secret);
      return secret;
    };
  });
  tearDown(() => keysParseRecoveryKey = parseRecoveryKey);

  test('firstKeyV is 1', () => expect(firstKeyV, 1));

  group('prepareAccount then commit', () {
    test(
      'puts the recovery wrap first, then an attested device wrap, and keeps only the data key',
      () async {
        final api = FakeKeys();
        final storage = memoryKeyStorage();
        final userId = newUser();
        final recoveryKey = await setUpAccount(optionsOf(api, userId, storage));

        expect(api.puts.map((p) => p.body!['kind']), ['recovery', 'device']);
        expect(recoveryKey, matches(_recoveryKeyShape));

        final device = api.wraps.firstWhere((w) => w.kind == 'device');
        final dk = await openRecovery(api, userId, recoveryKey!);
        expect(device.publicKey, isNotNull);
        expect(device.ref, device.id);
        expect(device.keyV, 1);
        expect(
          await verifyDeviceAttestation(
            dk,
            DeviceAttestationInput(
              userId: userId,
              wrapId: device.id,
              publicKey: fromBase64Url(device.publicKey!),
            ),
            fromBase64Url(device.attestation!),
          ),
          isTrue,
        );

        final local = await loadLocalKeys(userId, storage);
        expect(local?.keyring.current, 1);
        expect(await opensUnder(local!, userId, dk, 1), isTrue);
        final priv = await storage.devicePrivateKey(userId);
        expect(priv, isNotNull);
        expect(
          await openFromDevice(
            priv!,
            WrapContext(kind: WrapKind.device, userId: userId, keyV: 1),
            fromBase64Url(device.wrapped),
          ),
          dk,
        );
        expect(await storage.readDataKey(userId, 1), dk);
        // only this account's names: the data key, current, the device key and its wrap
        expect((await storedEntries()).keys, [
          'wambito.vault.$userId.current',
          'wambito.vault.$userId.device',
          'wambito.vault.$userId.devicePublicKey',
          'wambito.vault.$userId.deviceWrapId',
          'wambito.vault.$userId.dk.1',
        ]);
        await expectRefreshes(optionsOf(api, userId, storage));
      },
    );

    // The server's first wrap must be a recovery wrap (422 `recovery_required` otherwise), so a
    // guest gets one too, sealed under a secret that is never shown (keys.ts; E2E design §10).
    test('gives a guest keys and wraps but no recovery key', () async {
      final api = FakeKeys();
      final storage = memoryKeyStorage();
      final userId = newUser();
      final recoveryKey = await setUpAccount(optionsOf(api, userId, storage), guest: true);
      expect(recoveryKey, isNull);
      expect(await loadLocalKeys(userId, storage), isNotNull);
      expect(api.puts.map((p) => p.body!['kind']), ['recovery', 'device']);
      expect(api.wraps.where((w) => w.kind == 'passkey'), isEmpty);
      await expectRefreshes(optionsOf(api, userId, storage));
    });

    test('throws already_set_up when the account has wraps, and stores nothing', () async {
      final api = FakeKeys();
      final storage = memoryKeyStorage();
      final userId = newUser();
      await setUpAccount(optionsOf(api, userId, storage));
      final other = newUser();
      api.wraps.clear();
      await setUpAccount(optionsOf(api, other, storage));
      final before = await storedEntries();
      final puts = api.puts.length;
      final err = await caught(() => setUpAccount(optionsOf(api, other, storage)));
      expect(err, isKeysError('already_set_up'));
      expect(api.puts.length, puts);
      expect(await storedEntries(), before);
    });
  });

  group('prepareAccount', () {
    test('a preparation that fails zeroes the data key and the device private key', () async {
      final made = <Uint8List>[];
      keysGenerateDataKey = () {
        final dataKey = generateDataKey();
        made.add(dataKey);
        return dataKey;
      };
      keysGenerateDeviceKeyPair = () async {
        final pair = await generateDeviceKeyPair();
        made.add(pair.privateKey);
        return pair;
      };
      keysWrapDataKey = (secret, ctx, dk) async => throw StateError('the platform failed');
      addTearDown(() {
        keysGenerateDataKey = generateDataKey;
        keysGenerateDeviceKeyPair = generateDeviceKeyPair;
        keysWrapDataKey = wrapDataKey;
      });
      final api = FakeKeys();
      await expectLater(
        prepareAccount(optionsOf(api, newUser(), memoryKeyStorage()), guest: false),
        throwsA(isA<StateError>()),
      );
      expect(made, hasLength(2));
      expect(made.every(zeroed), isTrue);
      expect(api.wraps, isEmpty);
    });

    test('sends and stores nothing until commit()', () async {
      final api = FakeKeys();
      final storage = memoryKeyStorage();
      final userId = newUser();
      final prepared = await prepareAccount(optionsOf(api, userId, storage), guest: false);
      expect(prepared.recoveryKey, matches(_recoveryKeyShape));
      expect(api.puts, isEmpty);
      expect(await loadLocalKeys(userId, storage), isNull);
      expect(await storedEntries(), isEmpty);

      final keys = await prepared.commit();
      expect(api.puts.map((p) => p.body!['kind']), ['recovery', 'device']);
      expect(keys.keyring.current, 1);
      expect(await loadLocalKeys(userId, storage), isNotNull);
    });

    test('a prepared key that is never committed leaves the account without wraps', () async {
      final api = FakeKeys();
      final storage = memoryKeyStorage();
      final userId = newUser();
      await prepareAccount(optionsOf(api, userId, storage), guest: false);
      expect(api.wraps, isEmpty);
      // so the next visit prepares again (with a new key) instead of asking for Unlock
      final again = await prepareAccount(optionsOf(api, userId, storage), guest: false);
      expect(again.recoveryKey, isNotNull);
    });

    test('is retry-safe: a failed device PUT is sent again with the same ids', () async {
      final api = FakeKeys();
      final storage = memoryKeyStorage();
      final userId = newUser();
      var failDevice = true;
      api.intercept = (call) {
        if (failDevice && call.method == 'PUT' && call.body?['kind'] == 'device') {
          throw StateError('offline');
        }
        return null;
      };
      final prepared = await prepareAccount(optionsOf(api, userId, storage), guest: false);
      expect(await caught(prepared.commit), isKeysError('offline'));
      expect(await loadLocalKeys(userId, storage), isNull);
      expect(await storedEntries(), isEmpty);
      expect(api.wraps.map((w) => w.kind), ['recovery']);
      final recoveryId = api.wraps.single.id;
      final deviceId = api.puts.last.path;

      failDevice = false;
      await prepared.commit();
      expect(api.wraps.map((w) => w.kind).toList()..sort(), ['device', 'recovery']);
      expect(api.wraps.firstWhere((w) => w.kind == 'recovery').id, recoveryId);
      expect(api.puts.last.path, deviceId);
      expect(await loadLocalKeys(userId, storage), isNotNull);

      // the wrap the server kept is the one the shown key opens
      expect(await openRecovery(api, userId, prepared.recoveryKey!), hasLength(32));
      await expectRefreshes(optionsOf(api, userId, storage));
    });

    test('a second commit() after success sends nothing', () async {
      final api = FakeKeys();
      final storage = memoryKeyStorage();
      final userId = newUser();
      final prepared = await prepareAccount(optionsOf(api, userId, storage), guest: false);
      final first = await prepared.commit();
      final puts = api.puts.length;
      final second = await prepared.commit();
      expect(api.puts.length, puts);
      expect(second.keyring.current, first.keyring.current);
    });

    test('a double tap shares the commit in flight', () async {
      final api = FakeKeys();
      final storage = memoryKeyStorage();
      final userId = newUser();
      final prepared = await prepareAccount(optionsOf(api, userId, storage), guest: false);
      await Future.wait([prepared.commit(), prepared.commit()]);
      expect(api.puts.map((p) => p.body!['kind']), ['recovery', 'device']);
    });
  });

  group('two setups at once', () {
    test(
      'sends the first recovery wrap create-only (If-None-Match: *), the device wrap plainly',
      () async {
        final api = FakeKeys();
        await setUpAccount(optionsOf(api, newUser(), memoryKeyStorage()));
        expect(api.puts.map((p) => [p.body!['kind'], p.ifNoneMatch]), [
          ['recovery', '*'],
          ['device', null],
        ]);
      },
    );

    test('the setup that loses the race throws already_set_up and keeps nothing', () async {
      final api = FakeKeys();
      final storage = memoryKeyStorage();
      final userId = newUser();
      final options = optionsOf(api, userId, storage);
      final first = await prepareAccount(options, guest: false);
      final second = await prepareAccount(options, guest: false);
      await first.commit();
      await forgetDevice(userId, storage);
      expect(await caught(second.commit), isKeysError('already_set_up', 409));
      expect(api.wraps.map((w) => w.kind).toList()..sort(), ['device', 'recovery']);
      expect(await loadLocalKeys(userId, storage), isNull);
      // a retry of the losing setup never sends or keeps its (zeroed) data key
      final puts = api.puts.length;
      expect(await caught(second.commit), isKeysError('already_set_up', 409));
      expect(api.puts.length, puts);
      expect(await storedEntries(), isEmpty);
    });
  });

  group('unlockWithRecovery', () {
    test('opens the recovery wrap, adds a device wrap and stores the same record key', () async {
      final a = await accountWithKey();
      expect(await loadLocalKeys(a.userId, a.storage), isNull);
      final dk = await openRecovery(a.api, a.userId, a.recoveryKey);
      final before = a.api.wraps.length;
      // tolerant of case, spaces and dashes
      final messy = ' ${a.recoveryKey.toLowerCase().replaceAll('-', '  ')} ';
      final keys = await unlockWithRecovery(a.options, messy);
      expect(keys.keyring.current, 1);
      expect(a.api.wraps.length, before + 1);
      expect(a.api.wraps.where((w) => w.kind == 'device'), hasLength(2));
      expect(
        await opensUnder((await loadLocalKeys(a.userId, a.storage))!, a.userId, dk, 1),
        isTrue,
      );
      await expectRefreshes(a.options);
    });

    test('unlockWithRecoveryAcceptsSloppyInput', () async {
      final a = await accountWithKey();
      // the key in lower case, with spaces and dashes, O for 0 and I or L for 1
      var ones = 0;
      final sloppy = a.recoveryKey.split('').map((c) {
        if (c == '0') return 'o';
        if (c == '1') return (ones++).isEven ? 'i' : 'L';
        if (c == '-') return ' - ';
        return c.toLowerCase();
      }).join();
      final keys = await unlockWithRecovery(a.options, '  $sloppy\n');
      expect(keys.keyring.current, 1);
      await expectRefreshes(a.options);
    });

    test('rejects a malformed key with bad_recovery_key before any request', () async {
      final a = await accountWithKey();
      final calls = a.api.calls.length;
      final last = a.recoveryKey[a.recoveryKey.length - 1];
      final typo = a.recoveryKey.substring(0, a.recoveryKey.length - 1) + (last == '0' ? '1' : '0');
      for (final text in ['', 'hello', typo]) {
        expect(
          await caught(() => unlockWithRecovery(a.options, text)),
          isKeysError('bad_recovery_key'),
        );
      }
      expect(a.api.calls.length, calls);
      expect(await storedEntries(), isEmpty);
    });

    test('zeroes the recovery secret once done, whatever the outcome', () async {
      final a = await accountWithKey();
      await unlockWithRecovery(a.options, a.recoveryKey);
      await forgetDevice(a.userId, a.storage);
      final stranger = formatRecoveryKey(newRecoverySecret());
      await caught(() => unlockWithRecovery(a.options, stranger));
      expect(parsedSecrets, hasLength(2));
      expect(parsedSecrets.every(zeroed), isTrue);
    });

    test('rejects a well-formed key of another account with wrong_recovery_key', () async {
      final a = await accountWithKey();
      final puts = a.api.puts.length;
      final stranger = formatRecoveryKey(newRecoverySecret());
      expect(
        await caught(() => unlockWithRecovery(a.options, stranger)),
        isKeysError('wrong_recovery_key'),
      );
      expect(a.api.puts.length, puts);
      expect(await loadLocalKeys(a.userId, a.storage), isNull);
      expect(await storedEntries(), isEmpty);
    });

    test('an account without a recovery wrap is wrong_recovery_key', () async {
      final a = await accountWithKey();
      a.api.wraps.removeWhere((w) => w.kind == 'recovery');
      expect(
        await caught(() => unlockWithRecovery(a.options, a.recoveryKey)),
        isKeysError('wrong_recovery_key'),
      );
    });
  });

  group('the signed-in account', () {
    test('every /v2/keys call names the vault\'s account', () async {
      final api = FakeKeys();
      final userId = newUser();
      await setUpAccount(optionsOf(api, userId, memoryKeyStorage()));
      expect(api.calls.length, greaterThan(1));
      expect(api.calls.every((c) => c.user == userId), isTrue);
    });

    test('409 session_changed throws session_changed and stores nothing', () async {
      final api = FakeKeys()..answerAll = (409, {'code': 'session_changed'});
      final storage = memoryKeyStorage();
      final userId = newUser();
      expect(
        await caught(() => prepareAccount(optionsOf(api, userId, storage), guest: false)),
        isKeysError('session_changed', 409),
      );
      expect(await loadLocalKeys(userId, storage), isNull);
      expect(await storedEntries(), isEmpty);
    });
  });

  group('the device wrap', () {
    test('enroll keeps the device wrap id and public key', () async {
      final api = FakeKeys();
      final storage = memoryKeyStorage();
      final userId = newUser();
      await setUpAccount(optionsOf(api, userId, storage));
      final device = api.wraps.firstWhere((w) => w.kind == 'device');
      expect(await storage.deviceWrapId(userId), device.id);
      expect(await storage.devicePublicKey(userId), device.publicKey);
    });

    test('enroll labels the wrap after this phone', () async {
      final api = FakeKeys();
      await setUpAccount(optionsOf(api, newUser(), memoryKeyStorage()));
      final device = api.wraps.firstWhere((w) => w.kind == 'device');
      expect(device.label, 'Wambito on Android');
    });

    test('wrap ids are lower-case UUID v7', () async {
      final api = FakeKeys();
      await setUpAccount(optionsOf(api, newUser(), memoryKeyStorage()));
      for (final w in api.wraps) {
        expect(
          w.id,
          matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
        );
      }
    });
  });

  group('passkey wraps', () {
    /// An account set up on another phone: its DK, and the record keys it derives.
    Future<({Account account, Uint8List dk})> accountInAnotherPhone() async {
      final a = await accountWithKey();
      return (account: a, dk: await openRecovery(a.api, a.userId, a.recoveryKey));
    }

    FakeWrap passkeyWrap(String id, String ref, int keyV, String wrapped) =>
        FakeWrap(id: id, kind: 'passkey', ref: ref, keyV: keyV, wrapped: wrapped);

    test(
      'unlockWithPasskey opens the wrap whose ref is the credential and enrolls this browser',
      () async {
        final (:account, :dk) = await accountInAnotherPhone();
        final a = account;
        final prf = prfOf(5);
        a.api.wraps.addAll([
          passkeyWrap(
            '01930000-0000-7000-8000-0000000000b1',
            'other',
            1,
            toBase64Url(
              await wrapDataKey(
                prfOf(6),
                WrapContext(kind: WrapKind.passkey, userId: a.userId, keyV: 1),
                generateDataKey(),
              ),
            ),
          ),
          passkeyWrap(
            '01930000-0000-7000-8000-0000000000b2',
            cred,
            1,
            toBase64Url(
              await wrapDataKey(
                prf,
                WrapContext(kind: WrapKind.passkey, userId: a.userId, keyV: 1),
                dk,
              ),
            ),
          ),
        ]);
        final keys = await unlockWithPasskey(a.options, PasskeyPrf(credentialId: cred, prf: prf));
        expect(keys.keyring.current, 1);
        expect(a.api.wraps.where((w) => w.kind == 'device'), hasLength(2));
        expect(
          await opensUnder((await loadLocalKeys(a.userId, a.storage))!, a.userId, dk, 1),
          isTrue,
        );
        // the caller owns the PRF
        expect(zeroed(prf), isFalse);
        await expectRefreshes(a.options);
      },
    );

    test('unlockWithPasskey with an unknown credential is no_passkey_wrap', () async {
      final (:account, dk: _) = await accountInAnotherPhone();
      final puts = account.api.puts.length;
      expect(
        await caught(
          () => unlockWithPasskey(account.options, PasskeyPrf(credentialId: cred, prf: prfOf(5))),
        ),
        isKeysError('no_passkey_wrap'),
      );
      expect(account.api.puts.length, puts);
      expect(await loadLocalKeys(account.userId, account.storage), isNull);
    });

    test('addPasskeyWrap PUTs a wrap that unlockWithPasskey opens', () async {
      final api = FakeKeys();
      final storage = memoryKeyStorage();
      final userId = newUser();
      final options = optionsOf(api, userId, storage);
      final recoveryKey = await setUpAccount(options);
      final dk = await openRecovery(api, userId, recoveryKey!);
      await addPasskeyWrap(options, PasskeyPrf(credentialId: cred, prf: prfOf(3)));
      // Again (a second registration of the same credential): it replaces, it does not add.
      final firstId = api.wraps.firstWhere((w) => w.kind == 'passkey').id;
      await addPasskeyWrap(options, PasskeyPrf(credentialId: cred, prf: prfOf(3)));
      final passkeys = api.wraps.where((w) => w.kind == 'passkey').toList();
      expect(passkeys, hasLength(1));
      expect(passkeys.single.ref, cred);
      expect(passkeys.single.keyV, 1);
      expect(passkeys.single.id, firstId);
      expect(openedDevice.every(zeroed), isTrue);

      await forgetDevice(userId, storage);
      final keys = await unlockWithPasskey(options, PasskeyPrf(credentialId: cred, prf: prfOf(3)));
      expect(await opensUnder(keys, userId, dk, 1), isTrue);
      await expectRefreshes(options);
      // Another PRF opens nothing.
      await forgetDevice(userId, storage);
      expect(
        await caught(
          () => unlockWithPasskey(options, PasskeyPrf(credentialId: cred, prf: prfOf(4))),
        ),
        isKeysError('no_passkey_wrap'),
      );
    });

    test(
      'a credential that is not the account\'s never gets a wrap (422 unknown_passkey)',
      () async {
        final api = FakeKeys(passkeys: [cred]);
        final storage = memoryKeyStorage();
        final options = optionsOf(api, newUser(), storage);
        await setUpAccount(options);
        expect(
          await caught(
            () => addPasskeyWrap(
              options,
              PasskeyPrf(credentialId: 'c29tZW9uZS1lbHNl', prf: prfOf(3)),
            ),
          ),
          isKeysError('unknown_passkey', 422),
        );
        expect(api.wraps.where((w) => w.kind == 'passkey'), isEmpty);
      },
    );

    test('a passkey wrap made while another device rotates is rotated_elsewhere', () async {
      final api = FakeKeys();
      final storage = memoryKeyStorage();
      final options = optionsOf(api, newUser(), storage);
      await setUpAccount(options);
      api.intercept = (call) => call.method == 'PUT' && call.body?['kind'] == 'passkey'
          ? (409, {'code': 'key_version_mismatch'})
          : null;
      expect(
        await caught(() => addPasskeyWrap(options, PasskeyPrf(credentialId: cred, prf: prfOf(3)))),
        isKeysError('rotated_elsewhere', 409),
      );
      expect(api.wraps.where((w) => w.kind == 'passkey'), isEmpty);
      expect(openedDevice.every(zeroed), isTrue);
    });
  });

  group('unlocking an account that rotated', () {
    /// An account set up at v1 on this phone and rotated twice by another device: DK(1..3), links
    /// 2 and 3 (unless left out or wrong), the recovery wrap at v3. This phone keeps its vault.
    Future<
      ({
        FakeKeys api,
        KeyStorage storage,
        String userId,
        String recoveryKey,
        Uint8List dk1,
        Uint8List dk2,
        Uint8List dk3,
      })
    >
    rotatedTwice({String? link2}) async {
      final api = FakeKeys();
      final storage = memoryKeyStorage();
      final userId = newUser();
      final recoveryKey = (await setUpAccount(optionsOf(api, userId, storage)))!;
      final secret = parseRecoveryKey(recoveryKey);
      final dk1 = await openRecovery(api, userId, recoveryKey);
      final dk2 = generateDataKey();
      final dk3 = generateDataKey();
      if (link2 == null) await addLink(api, userId, dk2, dk1, 2);
      if (link2 == 'wrong') await addLink(api, userId, dk2, generateDataKey(), 2);
      await addLink(api, userId, dk3, dk2, 3);
      api.wraps.firstWhere((w) => w.kind == 'recovery')
        ..keyV = 3
        ..wrapped = toBase64Url(
          await wrapDataKey(
            secret,
            WrapContext(kind: WrapKind.recovery, userId: userId, keyV: 3),
            dk3,
          ),
        );
      return (
        api: api,
        storage: storage,
        userId: userId,
        recoveryKey: recoveryKey,
        dk1: dk1,
        dk2: dk2,
        dk3: dk3,
      );
    }

    test('unlockWithRecovery on a fresh browser keeps every version the links reach', () async {
      final r = await rotatedTwice();
      await forgetDevice(r.userId, r.storage);
      openedLinks.clear();
      final options = optionsOf(r.api, r.userId, r.storage);
      final local = await unlockWithRecovery(options, r.recoveryKey);
      expect(local.keyring.current, 3);
      expect(local.keyring.byVersion.keys, [1, 2, 3]);
      expect(openedLinks, hasLength(2));
      final loaded = (await loadLocalKeys(r.userId, r.storage))!;
      expect(loaded.keyring.byVersion.keys, [1, 2, 3]);
      expect(await opensUnder(loaded, r.userId, r.dk1, 1), isTrue);
      expect(await opensUnder(loaded, r.userId, r.dk2, 2), isTrue);
      expect(await opensUnder(loaded, r.userId, r.dk3, 3), isTrue);
      expect(openedLinks.every(zeroed), isTrue);
      await expectRefreshes(options);
    });

    test('unlockWithRecovery on an account whose link 2 is missing keeps v2 and v3 only, without error', () async {
      final r = await rotatedTwice(link2: 'missing');
      await forgetDevice(r.userId, r.storage);
      final local = await unlockWithRecovery(optionsOf(r.api, r.userId, r.storage), r.recoveryKey);
      expect(local.keyring.current, 3);
      final loaded = (await loadLocalKeys(r.userId, r.storage))!;
      expect(loaded.keyring.byVersion.keys, [2, 3]);
      expect(await opensUnder(loaded, r.userId, r.dk2, 2), isTrue);
      expect(await opensUnder(loaded, r.userId, r.dk3, 3), isTrue);
    });

    test('unlockWithPasskey on a browser holding v whose chain does not reach its key unlocks, keeps the held v and the trusted n', () async {
      final r = await rotatedTwice(link2: 'wrong');
      final prf = prfOf(7);
      r.api.wraps.add(
        FakeWrap(
          id: '01930000-0000-7000-8000-0000000000c1',
          kind: 'passkey',
          ref: cred,
          keyV: 3,
          wrapped: toBase64Url(
            await wrapDataKey(
              prf,
              WrapContext(kind: WrapKind.passkey, userId: r.userId, keyV: 3),
              r.dk3,
            ),
          ),
        ),
      );
      openedLinks.clear();
      final options = optionsOf(r.api, r.userId, r.storage);
      final local = await unlockWithPasskey(options, PasskeyPrf(credentialId: cred, prf: prf));
      expect(local.keyring.current, 3);
      final loaded = (await loadLocalKeys(r.userId, r.storage))!;
      expect(loaded.keyring.byVersion.keys, [1, 2, 3]);
      // the held v1 stays the phone's own, never the key the wrong link leads to
      expect(await opensUnder(loaded, r.userId, r.dk1, 1), isTrue);
      expect(await opensUnder(loaded, r.userId, r.dk2, 2), isTrue);
      expect(await opensUnder(loaded, r.userId, r.dk3, 3), isTrue);
      // link 3 opens DK(2), the wrong link 2 opens a key that is not DK(1): both zeroed
      expect(openedLinks, hasLength(2));
      expect(openedLinks.every(zeroed), isTrue);
      await expectRefreshes(options);
    });

    test(
      'unlockWithRecovery on a browser holding v whose v+1 has no link keeps v and v+1',
      () async {
        final api = FakeKeys();
        final storage = memoryKeyStorage();
        final userId = newUser();
        final options = optionsOf(api, userId, storage);
        final recoveryKey = (await setUpAccount(options))!;
        final dk1 = await openRecovery(api, userId, recoveryKey);
        final dk2 = generateDataKey();
        api.wraps.firstWhere((w) => w.kind == 'recovery')
          ..keyV = 2
          ..wrapped = toBase64Url(
            await wrapDataKey(
              parseRecoveryKey(recoveryKey),
              WrapContext(kind: WrapKind.recovery, userId: userId, keyV: 2),
              dk2,
            ),
          );
        final local = await unlockWithRecovery(options, recoveryKey);
        expect(local.keyring.current, 2);
        final loaded = (await loadLocalKeys(userId, storage))!;
        expect(loaded.keyring.byVersion.keys, [1, 2]);
        expect(await opensUnder(loaded, userId, dk1, 1), isTrue);
        expect(await opensUnder(loaded, userId, dk2, 2), isTrue);
      },
    );

    test(
      'a recovery wrap below the held current version is tampered: nothing sent, kept or deleted',
      () async {
        final r = await rotatedTwice();
        final options = optionsOf(r.api, r.userId, r.storage);
        await unlockWithRecovery(options, r.recoveryKey);
        // the server replays the v1 recovery wrap to a phone that holds v3
        r.api.wraps.firstWhere((w) => w.kind == 'recovery')
          ..keyV = 1
          ..wrapped = toBase64Url(
            await wrapDataKey(
              parseRecoveryKey(r.recoveryKey),
              WrapContext(kind: WrapKind.recovery, userId: r.userId, keyV: 1),
              r.dk1,
            ),
          );
        final before = await storedEntries();
        final puts = r.api.puts.length;
        final deletes = r.api.deletes.length;
        expect(
          await caught(() => unlockWithRecovery(options, r.recoveryKey)),
          isKeysError('tampered'),
        );
        expect(r.api.puts.length, puts);
        expect(r.api.deletes.length, deletes);
        expect(await storedEntries(), before);
        expect((await loadLocalKeys(r.userId, r.storage))?.keyring.current, 3);
      },
    );

    test(
      'unlockWithRecovery on a browser holding v walks down to its key and keeps the newer ones',
      () async {
        final r = await rotatedTwice();
        final local = await unlockWithRecovery(
          optionsOf(r.api, r.userId, r.storage),
          r.recoveryKey,
        );
        expect(local.keyring.current, 3);
        final loaded = (await loadLocalKeys(r.userId, r.storage))!;
        expect(loaded.keyring.byVersion.keys, [1, 2, 3]);
        expect(await opensUnder(loaded, r.userId, r.dk1, 1), isTrue);
        expect(await opensUnder(loaded, r.userId, r.dk2, 2), isTrue);
        expect(await opensUnder(loaded, r.userId, r.dk3, 3), isTrue);
      },
    );

    test('an unlock with a vault held here deletes this browser\'s previous device wrap, after keeping the new one', () async {
      final r = await rotatedTwice();
      final previous = await r.storage.deviceWrapId(r.userId);
      final options = optionsOf(r.api, r.userId, r.storage);
      await unlockWithRecovery(options, r.recoveryKey);
      final current = await r.storage.deviceWrapId(r.userId);
      expect(previous, isNotNull);
      expect(current, isNot(previous));
      expect(r.api.deletes, [previous]);
      expect(r.api.wraps.where((w) => w.kind == 'device').map((w) => w.id), [current]);
      // the delete came after the new wrap was sent
      final methods = r.api.calls.map((c) => c.method).toList();
      expect(methods.lastIndexOf('PUT'), lessThan(methods.indexOf('DELETE')));
      await expectRefreshes(options);
    });

    test('an unlock on a fresh browser deletes no wrap', () async {
      final r = await rotatedTwice();
      await forgetDevice(r.userId, r.storage);
      await unlockWithRecovery(optionsOf(r.api, r.userId, r.storage), r.recoveryKey);
      expect(r.api.deletes, isEmpty);
    });

    test('a refused delete of the previous device wrap does not fail the unlock', () async {
      final r = await rotatedTwice();
      r.api.failDeletes = true;
      final options = optionsOf(r.api, r.userId, r.storage);
      final local = await unlockWithRecovery(options, r.recoveryKey);
      expect(local.keyring.current, 3);
      expect(r.api.deletes, hasLength(1));
      expect((await loadLocalKeys(r.userId, r.storage))?.keyring.current, 3);
      await expectRefreshes(options);
    });

    test('enrollDevice (pairing) keeps the older versions the links reach', () async {
      final r = await rotatedTwice();
      await forgetDevice(r.userId, r.storage);
      final options = optionsOf(r.api, r.userId, r.storage);
      final local = await enrollDevice(options, r.dk3, 3);
      expect(local.keyring.current, 3);
      final loaded = (await loadLocalKeys(r.userId, r.storage))!;
      expect(loaded.keyring.byVersion.keys, [1, 2, 3]);
      expect(await opensUnder(loaded, r.userId, r.dk1, 1), isTrue);
      expect(await opensUnder(loaded, r.userId, r.dk2, 2), isTrue);
      // the caller owns the data key
      expect(zeroed(r.dk3), isFalse);
      await expectRefreshes(options);
    });

    test('enrollDevice (pairing) with a vault held here stays strict: a chain that does not reach its key is tampered', () async {
      final r = await rotatedTwice(link2: 'wrong');
      final before = await storedEntries();
      final puts = r.api.puts.length;
      expect(
        await caught(() => enrollDevice(optionsOf(r.api, r.userId, r.storage), r.dk3, 3)),
        isKeysError('tampered'),
      );
      expect(r.api.puts.length, puts);
      expect(await storedEntries(), before);
    });
  });
}
