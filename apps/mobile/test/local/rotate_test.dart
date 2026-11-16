import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/ids.dart';
import 'package:wambito/local/keys.dart';
import 'package:wambito/local/prf.dart';
import 'package:wambito/local/rotate.dart';
import 'package:wambito/local/sqlite_store.dart';
import 'package:wambito/local/store.dart';

import 'fake_keys.dart';

/// The rotation part of apps/web/app/local/rotate.test.ts (`rotateKeys`), against the fake
/// `/v2/keys`, plus what the phone adds: it never removes itself, its own wrap is always posted,
/// and a fresh recovery key's verifier follows the rotation (D16).

/// Every data key, recovery secret, parsed secret and unwrapped key the rotation is handed, to
/// check that it zeroes them (the web's test mocks the crypto the same way).
final dataKeys = <Uint8List>[];
final madeSecrets = <Uint8List>[];
final parsedSecrets = <Uint8List>[];
final unwrapped = <Uint8List>[];

void clearHanded() {
  for (final list in [dataKeys, madeSecrets, parsedSecrets, unwrapped, openedLinks, openedDevice]) {
    list.clear();
  }
}

bool allZeroed() => [
  dataKeys,
  madeSecrets,
  parsedSecrets,
  unwrapped,
  openedLinks,
  openedDevice,
].every((list) => list.every(zeroed));

const settingsId = '01930000-0000-7000-8000-0000000000c1';

/// A [KeyStorage] whose next `setCurrent` fails once (a keep that fails half-way).
class FaultyKeyStorage extends KeyStorage {
  FaultyKeyStorage() : super(const FlutterSecureStorage());

  bool failSetCurrent = false;

  @override
  Future<void> setCurrent(String userId, int v) {
    if (failSetCurrent) {
      failSetCurrent = false;
      throw StateError('write failed');
    }
    return super.setCurrent(userId, v);
  }
}

/// An account set up on this phone (keyV 1): its DK, recovery key, own device wrap and a vault
/// with a settings record.
class Account {
  Account(this.api, this.storage, this.store, this.userId, this.recoveryKey, this.dk, this.own);

  final FakeKeys api;
  final FaultyKeyStorage storage;
  final SqliteStore store;
  final String userId;
  final String recoveryKey;
  final Uint8List dk;
  final FakeWrap own;

  KeysOptions get options => KeysOptions(userId: userId, dio: api.dio(), storage: storage);

  Future<PreparedRotation> rotate({
    List<String> remove = const [],
    RotateRecovery? recovery,
    PasskeyPrf? passkey,
  }) => rotateKeys(
    options,
    store: store,
    remove: remove,
    recovery: recovery ?? TypedRecovery(recoveryKey),
    passkey: passkey,
  );

  FakeWrap wrapOf(String id) => api.wraps.firstWhere((w) => w.id == id);

  Future<List<Object?>?> revoked() async =>
      (await store.get(RecordType.settings, settingsId))?.body['revokedDevices'] as List?;

  /// The writes the phone sent (anything but a `GET`).
  List<FakeCall> get writes => api.calls.where((c) => c.method != 'GET').toList();
}

Future<Uint8List> openRecovery(FakeKeys api, String userId, String recoveryKey, int keyV) async {
  final wrap = api.wraps.firstWhere((w) => w.kind == 'recovery');
  expect(wrap.keyV, keyV);
  return unwrapDataKey(
    parseRecoveryKey(recoveryKey),
    WrapContext(kind: WrapKind.recovery, userId: userId, keyV: keyV),
    fromBase64Url(wrap.wrapped),
  );
}

late Directory dir;

Future<Account> account([List<String> revokedDevices = const []]) async {
  final api = FakeKeys();
  final storage = FaultyKeyStorage();
  final userId = newUser();
  final options = KeysOptions(userId: userId, dio: api.dio(), storage: storage);
  final prepared = await prepareAccount(options, guest: false);
  await prepared.commit();
  final recoveryKey = prepared.recoveryKey!;
  final dk = await openRecovery(api, userId, recoveryKey, 1);
  final own = api.wraps.firstWhere((w) => w.kind == 'device');
  final store = await SqliteStore.open(userId, directory: dir.path, factory: databaseFactoryFfi);
  // as the sync stores it: no outbox entry
  await store.put(RecordType.settings, settingsId, <String, Object?>{
    's': 1,
    'name': null,
    'currency': 'EUR',
    'locale': 'es',
    'timezone': 'Europe/Madrid',
    'onboardingCompletedAt': null,
    'revokedDevices': revokedDevices,
  }, const WriteOptions(origin: 'remote', version: 1, keyV: 1));
  api
    ..calls.clear()
    ..verifier = null;
  clearHanded();
  return Account(api, storage, store, userId, recoveryKey, dk, own);
}

/// Another device of the account, attested under [attestWith] (the account's DK by default).
Future<({String id, DeviceKeyPair pair})> addDevice(
  Account a,
  String label, [
  Uint8List? attestWith,
]) async {
  final pair = await generateDeviceKeyPair();
  final id = uuidv7();
  a.api.wraps.add(
    FakeWrap(
      id: id,
      kind: 'device',
      ref: id,
      keyV: 1,
      wrapped: toBase64Url(
        await sealToDevice(
          pair.publicKey,
          WrapContext(kind: WrapKind.device, userId: a.userId, keyV: 1),
          a.dk,
        ),
      ),
      publicKey: toBase64Url(pair.publicKey),
      attestation: toBase64Url(
        await deviceAttestation(
          attestWith ?? a.dk,
          DeviceAttestationInput(userId: a.userId, wrapId: id, publicKey: pair.publicKey),
        ),
      ),
      label: label,
    ),
  );
  clearHanded();
  return (id: id, pair: pair);
}

Future<({String id, Uint8List prf})> addPasskey(Account a, String credentialId) async {
  final prf = generateDataKey(); // 32 random bytes
  final id = uuidv7();
  a.api.wraps.add(
    FakeWrap(
      id: id,
      kind: 'passkey',
      ref: credentialId,
      keyV: 1,
      wrapped: toBase64Url(
        await wrapDataKey(
          prf,
          WrapContext(kind: WrapKind.passkey, userId: a.userId, keyV: 1),
          a.dk,
        ),
      ),
      label: 'Passkey',
    ),
  );
  clearHanded();
  return (id: id, prf: prf);
}

/// The data key a device wrap seals to [privateKey].
Future<Uint8List> openDevice(Account a, FakeWrap wrap, Uint8List privateKey) => openFromDevice(
  privateKey,
  WrapContext(kind: WrapKind.device, userId: a.userId, keyV: wrap.keyV),
  fromBase64Url(wrap.wrapped),
);

/// The verifier of [recoveryKey], base64url, as the server stores it.
Future<({String lookupHash, String authHash})> verifierOf(String recoveryKey) async {
  final hashes = await verifierHashesOf(parseRecoveryKey(recoveryKey));
  return (lookupHash: toBase64Url(hashes.lookupHash), authHash: toBase64Url(hashes.authHash));
}

void main() {
  sqfliteFfiInit();
  setUpAll(() => dir = Directory.systemTemp.createTempSync('wambito-rotate-test'));
  tearDownAll(() => dir.deleteSync(recursive: true));

  recordOpenedKeys();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    keysRotateDataKey = () {
      final dk = generateDataKey();
      dataKeys.add(dk);
      return dk;
    };
    keysNewRecoverySecret = () {
      final secret = newRecoverySecret();
      madeSecrets.add(secret);
      return secret;
    };
    keysParseRecoveryKey = (text) {
      final secret = parseRecoveryKey(text);
      parsedSecrets.add(secret);
      return secret;
    };
    keysUnwrapDataKey = (secret, c, wrapped) async {
      final key = await unwrapDataKey(secret, c, wrapped);
      unwrapped.add(key);
      return key;
    };
  });
  tearDown(() {
    keysRotateDataKey = generateDataKey;
    keysNewRecoverySecret = newRecoverySecret;
    keysParseRecoveryKey = parseRecoveryKey;
    keysUnwrapDataKey = unwrapDataKey;
  });

  group('rotateKeys', () {
    test('a typed recovery key that does not open the current recovery wrap is wrong_recovery_key, before anything is made', () async {
      final a = await account();
      final stranger = formatRecoveryKey(newRecoverySecret());
      expect(
        await caught(() => a.rotate(recovery: TypedRecovery(stranger))),
        isKeysError('wrong_recovery_key'),
      );
      expect(dataKeys, isEmpty);
      expect(openedDevice, isEmpty);
      expect(a.api.rotations, isEmpty);
    });

    test('rotation keeps the other devices, sealed to their public keys with fresh attestations under the new DK, same ids and labels', () async {
      final a = await account();
      final other = await addDevice(a, 'Firefox on Linux');
      final ownPrivate = (await a.storage.devicePrivateKey(a.userId))!;
      final ownBefore = a.own;
      final otherPublic = a.wrapOf(other.id).publicKey;
      final prepared = await a.rotate();
      expect(prepared.recoveryKey, isNull);
      final result = await prepared.commit();
      expect(result.keyV, 2);
      expect(result.dropped, isEmpty);

      final newDk = await openRecovery(a.api, a.userId, a.recoveryKey, 2);
      expect(newDk, isNot(a.dk));
      for (final (id, label, publicKey, privateKey) in [
        (ownBefore.id, ownBefore.label, ownBefore.publicKey, ownPrivate),
        (other.id, 'Firefox on Linux', otherPublic, other.pair.privateKey),
      ]) {
        final wrap = a.wrapOf(id);
        expect(wrap.kind, 'device');
        expect(wrap.ref, id);
        expect(wrap.keyV, 2);
        expect(wrap.label, label);
        expect(wrap.publicKey, publicKey);
        expect(await openDevice(a, wrap, privateKey), newDk);
        expect(
          await verifyDeviceAttestation(
            newDk,
            DeviceAttestationInput(
              userId: a.userId,
              wrapId: wrap.id,
              publicKey: fromBase64Url(wrap.publicKey!),
            ),
            fromBase64Url(wrap.attestation!),
          ),
          isTrue,
        );
      }
      expect(a.api.wraps.where((w) => w.kind == 'device'), hasLength(2));
    });

    test('the removed ids and the settings\' revokedDevices are left out, and reported', () async {
      final revoked = uuidv7();
      final a = await account([revoked]);
      final gone = await addDevice(a, 'Chrome on Android');
      final kept = await addDevice(a, 'Safari on iOS');
      // the server still lists the revoked device (an old wrap kept by a malicious server)
      final old = await addDevice(a, 'Edge on Windows');
      final oldWrap = a.wrapOf(old.id)
        ..id = revoked
        ..ref = revoked;
      oldWrap.attestation = toBase64Url(
        await deviceAttestation(
          a.dk,
          DeviceAttestationInput(userId: a.userId, wrapId: revoked, publicKey: old.pair.publicKey),
        ),
      );

      final result = await (await a.rotate(remove: [gone.id])).commit();
      expect(result.dropped, [
        DroppedWrap(id: gone.id, label: 'Chrome on Android', reason: 'removed'),
        DroppedWrap(id: revoked, label: 'Edge on Windows', reason: 'revoked'),
      ]);
      expect(a.api.wraps.where((w) => w.kind == 'device').map((w) => w.id).toSet(), {
        a.own.id,
        kept.id,
      });
    });

    test('a device wrap whose attestation fails under the old DK is left out and reported as attestation', () async {
      final a = await account();
      final forged = await addDevice(a, 'Chrome on Linux', generateDataKey());
      final result = await (await a.rotate()).commit();
      expect(result.dropped, [
        DroppedWrap(id: forged.id, label: 'Chrome on Linux', reason: 'attestation'),
      ]);
      expect(a.api.wraps.any((w) => w.id == forged.id), isFalse);
    });

    test('{ fresh: true } shows a new key and sends nothing until commit', () async {
      final a = await account();
      final before = [for (final w in a.api.wraps) w.toJson()];
      final prepared = await a.rotate(recovery: const FreshRecovery());
      expect(prepared.recoveryKey, matches(RegExp(r'^([0-9A-Z]{4}-){6}[0-9A-Z]{3}$')));
      expect(prepared.recoveryKey, isNot(a.recoveryKey));
      expect(a.api.rotations, isEmpty);
      expect(a.writes, isEmpty);
      expect([for (final w in a.api.wraps) w.toJson()], before);
      expect(await a.storage.current(a.userId), 1);

      await prepared.commit();
      expect(await openRecovery(a.api, a.userId, prepared.recoveryKey!, 2), hasLength(32));
      expect(await caught(() => openRecovery(a.api, a.userId, a.recoveryKey, 2)), isNotNull);
    });

    test('the touched passkey is re-wrapped; other passkeys lose their wrap', () async {
      final a = await account();
      final touched = await addPasskey(a, 'cred-touched');
      final other = await addPasskey(a, 'cred-other');
      final prf = Uint8List.fromList(touched.prf);
      await (await a.rotate(
        recovery: const FreshRecovery(),
        passkey: PasskeyPrf(credentialId: 'cred-touched', prf: prf),
      )).commit();
      // used up: zeroed before rotateKeys returned
      expect(zeroed(prf), isTrue);
      final passkeys = a.api.wraps.where((w) => w.kind == 'passkey').toList();
      expect(passkeys.map((w) => [w.id, w.ref, w.label]), [
        [touched.id, 'cred-touched', 'Passkey'],
      ]);
      expect(a.api.wraps.any((w) => w.id == other.id), isFalse);
      final fromPasskey = await unwrapDataKey(
        touched.prf,
        WrapContext(kind: WrapKind.passkey, userId: a.userId, keyV: 2),
        fromBase64Url(passkeys.single.wrapped),
      );
      final ownPrivate = (await a.storage.devicePrivateKey(a.userId))!;
      expect(await openDevice(a, a.wrapOf(a.own.id), ownPrivate), fromPasskey);
    });

    test('after commit the keyring has the new version and settings.revokedDevices holds the removed ids', () async {
      final earlier = uuidv7();
      final a = await account([earlier]);
      final gone = await addDevice(a, 'Chrome on Android');
      await (await a.rotate(remove: [gone.id])).commit();

      final local = await loadLocalKeys(a.userId, a.storage);
      expect(local?.keyring.current, 2);
      expect(local?.keyring.byVersion.keys.toList(), [1, 2]);
      // version 2's record keys are the new DK's
      final newDk = await openRecovery(a.api, a.userId, a.recoveryKey, 2);
      expect(await opensUnder(local!, a.userId, newDk, 2), isTrue);
      expect(await opensUnder(local, a.userId, a.dk, 1), isTrue);

      expect(await a.revoked(), [earlier, gone.id]);
      // a local write: the sync engine seals it under the keyring's current version, 2
      final outbox = await a.store.readOutbox(100);
      expect(outbox.firstWhere((e) => e.id == settingsId).touched, contains('revokedDevices'));
    });

    test('the rotation posts a link that opens to the old data key under the new one', () async {
      final a = await account();
      await (await a.rotate()).commit();
      final link = a.api.rotations.single['link'];
      expect(link, isA<String>());
      final newDk = await openRecovery(a.api, a.userId, a.recoveryKey, 2);
      expect(
        await openKeyLink(
          newDk,
          LinkContext(userId: a.userId, keyV: 2),
          fromBase64Url(link! as String),
        ),
        a.dk,
      );
    });

    test(
      'a retried commit after a lost answer posts the same link, and landed() still holds',
      () async {
        final a = await account();
        final prepared = await a.rotate();
        a.api.loseNextAnswer = true;
        expect(await caught(prepared.commit), isKeysError('offline'));
        expect(a.api.rotations.single['link'], isNotNull);
        a.api.offline = false;
        expect((await prepared.commit()).keyV, 2);
        expect(a.api.rotations, hasLength(1));
        // the retry was posted (and refused as a second rotation) with the very same link
        expect(a.api.posts, hasLength(2));
        expect(a.api.posts[1]['link'], a.api.posts[0]['link']);
        expect(await a.storage.current(a.userId), 2);
      },
    );

    test('a phone at v1 while the account is at v2 (valid link) refreshes first, rotates to v3 and holds 1, 2 and 3', () async {
      final a = await account();
      // another device rotated to v2: the same recovery key, this phone's wrap sealed to DK(2)
      final dk2 = generateDataKey();
      final secret = parseRecoveryKey(a.recoveryKey);
      for (final wrap in a.api.wraps) {
        wrap.keyV = 2;
        if (wrap.kind == 'recovery') {
          wrap.wrapped = toBase64Url(
            await wrapDataKey(
              secret,
              WrapContext(kind: WrapKind.recovery, userId: a.userId, keyV: 2),
              dk2,
            ),
          );
        }
      }
      await rotateDeviceWrap(a.api, a.userId, a.own, dk2, 2, a.dk);
      clearHanded();
      final result = await (await a.rotate()).commit();
      expect(result.keyV, 3);
      final local = await loadLocalKeys(a.userId, a.storage);
      expect(local?.keyring.current, 3);
      expect(local?.keyring.byVersion.keys.toList(), [1, 2, 3]);
      expect(await opensUnder(local!, a.userId, dk2, 2), isTrue);
      // the link posted with v3 opens to DK(2)
      final dk3 = await openRecovery(a.api, a.userId, a.recoveryKey, 3);
      final link = a.api.rotations.single['link']! as String;
      expect(
        await openKeyLink(dk3, LinkContext(userId: a.userId, keyV: 3), fromBase64Url(link)),
        dk2,
      );
      expect(await opensUnder(local, a.userId, dk3, 3), isTrue);
    });

    test('a lost answer, then a refresh that stored the new version meanwhile: the retried commit finishes', () async {
      final a = await account();
      final gone = await addDevice(a, 'Chrome on Android');
      final prepared = await a.rotate(remove: [gone.id]);
      a.api.loseNextAnswer = true;
      expect(await caught(prepared.commit), isKeysError('offline'));
      a.api.offline = false;
      // the vault's sync met the new version first: its own prepared wrap, through the valid link
      expect((await refreshKeys(a.options)).keyring.current, 2);
      final result = await prepared.commit();
      expect(result.keyV, 2);
      expect(result.dropped, [
        DroppedWrap(id: gone.id, label: 'Chrome on Android', reason: 'removed'),
      ]);
      final local = await loadLocalKeys(a.userId, a.storage);
      expect(local?.keyring.current, 2);
      expect(local?.keyring.byVersion.keys.toList(), [1, 2]);
      final newDk = await openRecovery(a.api, a.userId, a.recoveryKey, 2);
      expect(await opensUnder(local!, a.userId, newDk, 2), isTrue);
      expect(await a.revoked(), [gone.id]);
    });

    test('a keep that failed after its first key write finishes on retry', () async {
      final a = await account();
      final gone = await addDevice(a, 'Chrome on Android');
      final prepared = await a.rotate(remove: [gone.id]);
      a.storage.failSetCurrent = true;
      expect(await caught(prepared.commit), isA<StateError>());
      expect(a.api.rotations, hasLength(1));
      expect((await prepared.commit()).keyV, 2);
      expect(a.api.posts, hasLength(1));
      final local = await loadLocalKeys(a.userId, a.storage);
      expect(local?.keyring.current, 2);
      expect(local?.keyring.byVersion.keys.toList(), [1, 2]);
      expect(await a.revoked(), [gone.id]);
    });

    test(
      'a commit never overwrites a data key this phone already holds for the new version',
      () async {
        final a = await account();
        final prepared = await a.rotate();
        // dk.2 appeared meanwhile (it must never be replaced: versions only grow)
        final held = generateDataKey();
        await a.storage.writeDataKey(a.userId, 2, held);
        expect(await caught(prepared.commit), isKeysError('tampered'));
        expect(await a.storage.readDataKey(a.userId, 2), held);
        expect(await a.storage.current(a.userId), 1);
        expect(await a.revoked(), isEmpty);
        // refused for good: a retry does not try again
        expect(await caught(prepared.commit), isKeysError('tampered'));
        expect(dataKeys.every(zeroed), isTrue);
      },
    );

    test('a 409 key_version_mismatch from rotate is rotated_elsewhere and leaves the local keys untouched', () async {
      final a = await account();
      final gone = await addDevice(a, 'Chrome on Android');
      final prepared = await a.rotate(remove: [gone.id]);
      a.api.rotatedElsewhere = true;
      expect(await caught(prepared.commit), isKeysError('rotated_elsewhere', 409));
      final local = await loadLocalKeys(a.userId, a.storage);
      expect(local?.keyring.current, 1);
      expect(local?.keyring.byVersion.keys.toList(), [1]);
      expect(await a.revoked(), isEmpty);
      expect(await a.storage.readDataKey(a.userId, 2), isNull);
    });

    test(
      'a rotation whose answer was lost is recognised as ours on retry, and kept locally',
      () async {
        final a = await account();
        final gone = await addDevice(a, 'Chrome on Android');
        final prepared = await a.rotate(remove: [gone.id], recovery: const FreshRecovery());
        a.api.loseNextAnswer = true;
        expect(await caught(prepared.commit), isKeysError('offline'));
        expect(a.api.rotations, hasLength(1)); // the server did commit
        expect(await a.storage.current(a.userId), 1);

        a.api.offline = false;
        final result = await prepared.commit();
        expect(result.keyV, 2);
        expect(result.dropped, [
          DroppedWrap(id: gone.id, label: 'Chrome on Android', reason: 'removed'),
        ]);
        expect(a.api.rotations, hasLength(1));
        expect(await a.storage.current(a.userId), 2);
        expect(await a.revoked(), [gone.id]);
        // the shown key is the account's recovery key, and its verifier followed the retry
        expect(await openRecovery(a.api, a.userId, prepared.recoveryKey!, 2), hasLength(32));
        expect(a.api.verifierPuts, hasLength(1));
        expect(a.api.verifier, await verifierOf(prepared.recoveryKey!));
      },
    );

    test('a lost answer, a 409 on retry and a landed() check that cannot reach the server is offline, not rotated_elsewhere: a later commit keeps the rotation', () async {
      final a = await account();
      final gone = await addDevice(a, 'Chrome on Android');
      final prepared = await a.rotate(remove: [gone.id], recovery: const FreshRecovery());
      a.api.loseNextAnswer = true;
      expect(await caught(prepared.commit), isKeysError('offline'));
      expect(a.api.rotations, hasLength(1)); // the server did commit
      a.api.offline = false;
      // the retried post gets its 409, then the network drops before landed() can ask
      var posted = false;
      a.api.intercept = (call) {
        if (call.method == 'POST') posted = true;
        if (posted && call.method == 'GET') throw StateError('network down');
        return null;
      };
      expect(await caught(prepared.commit), isKeysError('offline'));
      expect(dataKeys.any(zeroed), isFalse); // kept for the retry
      expect(await a.storage.current(a.userId), 1);

      a.api.intercept = null;
      final result = await prepared.commit();
      expect(result.keyV, 2);
      expect(a.api.rotations, hasLength(1));
      expect(await a.storage.current(a.userId), 2);
      expect(await a.revoked(), [gone.id]);
      expect(a.api.verifier, await verifierOf(prepared.recoveryKey!));
      expect(dataKeys.every(zeroed), isTrue);
    });

    test('a 409 after another device\'s rotation (its wraps, not ours) is rotated_elsewhere, local keys untouched', () async {
      final a = await account();
      final prepared = await a.rotate();
      // another device rotated to keyV 2: its own DK, sealed to this phone's public key too
      for (final wrap in a.api.wraps) {
        wrap.keyV = 2;
      }
      await rotateDeviceWrap(a.api, a.userId, a.own, generateDataKey(), 2);

      expect(await caught(prepared.commit), isKeysError('rotated_elsewhere', 409));
      expect(a.api.rotations, isEmpty);
      final local = await loadLocalKeys(a.userId, a.storage);
      expect(local?.keyring.current, 1);
      expect(local?.keyring.byVersion.keys.toList(), [1]);
      expect(await a.storage.readDataKey(a.userId, 2), isNull);
    });

    test('DK, the new DK and the recovery secret are zeroed after commit or failure', () async {
      final a = await account();
      await (await a.rotate()).commit();
      expect(dataKeys, hasLength(1));
      expect(openedDevice, isNotEmpty);
      expect(unwrapped, isNotEmpty);
      expect(parsedSecrets, hasLength(1));
      expect(allZeroed(), isTrue);

      final b = await account();
      final fresh = await b.rotate(recovery: const FreshRecovery());
      b.api.rotatedElsewhere = true;
      await caught(fresh.commit);
      expect(madeSecrets, hasLength(1));
      expect(dataKeys, hasLength(1));
      expect(allZeroed(), isTrue);

      clearHanded();
      final stranger = formatRecoveryKey(newRecoverySecret());
      await caught(() => b.rotate(recovery: TypedRecovery(stranger)));
      expect(parsedSecrets, hasLength(1));
      expect(allZeroed(), isTrue);
    });

    test('a new DK whose rotation is never committed is zeroed once a commit is refused', () async {
      final a = await account();
      final prepared = await a.rotate();
      // made, held for commit
      expect(dataKeys, hasLength(1));
      expect(zeroed(dataKeys.single), isFalse);
      a.api.rotatedElsewhere = true;
      await caught(prepared.commit);
      expect(zeroed(dataKeys.single), isTrue);
      // refused for good: nothing is posted again
      expect(await caught(prepared.commit), isKeysError('rotated_elsewhere', 409));
      expect(a.api.posts, hasLength(1));
    });

    test('forget() zeroes the held new DK and refuses a later commit; nothing is posted', () async {
      final a = await account();
      final prepared = await a.rotate(recovery: const FreshRecovery());
      expect(zeroed(dataKeys.single), isFalse);
      prepared.forget();
      expect(zeroed(dataKeys.single), isTrue);
      expect(await caught(prepared.commit), isKeysError('abandoned'));
      expect(a.api.posts, isEmpty);
    });

    test('forget() after a commit failed past the POST changes nothing: the retry finishes and writes revokedDevices', () async {
      final a = await account();
      final gone = await addDevice(a, 'Chrome on Android');
      final prepared = await a.rotate(remove: [gone.id]);
      a.storage.failSetCurrent = true;
      expect(await caught(prepared.commit), isA<StateError>());
      expect(a.api.rotations, hasLength(1));
      prepared.forget();
      expect(zeroed(dataKeys.single), isFalse);
      expect((await prepared.commit()).keyV, 2);
      expect(a.api.posts, hasLength(1));
      expect(await a.revoked(), [gone.id]);
    });

    test('forget() after a lost answer (offline) changes nothing: a retry still lands', () async {
      final a = await account();
      final prepared = await a.rotate(recovery: const FreshRecovery());
      a.api.loseNextAnswer = true;
      expect(await caught(prepared.commit), isKeysError('offline'));
      a.api.offline = false;
      prepared.forget();
      expect(zeroed(dataKeys.single), isFalse);
      expect((await prepared.commit()).keyV, 2);
    });

    test(
      'refused says when a commit is refused for good: rotated_elsewhere and tampered, not offline',
      () async {
        final a = await account();
        final offline = await a.rotate();
        expect(offline.refused, isFalse);
        a.api.offline = true;
        expect(await caught(offline.commit), isKeysError('offline'));
        expect(offline.refused, isFalse);
        a.api.offline = false;
        a.api.rotatedElsewhere = true;
        expect(await caught(offline.commit), isKeysError('rotated_elsewhere', 409));
        expect(offline.refused, isTrue);

        final b = await account();
        final tampered = await b.rotate();
        await b.storage.writeDataKey(b.userId, 2, generateDataKey());
        expect(await caught(tampered.commit), isKeysError('tampered'));
        expect(tampered.refused, isTrue);
      },
    );

    test('forget() after the commit is done changes nothing', () async {
      final a = await account();
      final prepared = await a.rotate();
      final result = await prepared.commit();
      prepared.forget();
      expect((await prepared.commit()).keyV, result.keyV);
    });

    test('this phone cannot remove itself', () async {
      final a = await account();
      await addDevice(a, 'Chrome on Android');
      expect(await caught(() => a.rotate(remove: [a.own.id])), isA<ArgumentError>());
      expect(a.writes, isEmpty);
      expect(dataKeys, isEmpty);
      expect(allZeroed(), isTrue);
    });

    test('this phone missing from the server\'s list is device_removed, nothing sent', () async {
      final a = await account();
      await addDevice(a, 'Chrome on Android');
      a.api.wraps.removeWhere((w) => w.id == a.own.id);
      expect(await caught(() => a.rotate()), isKeysError('device_removed'));
      expect(a.writes, isEmpty);
      expect(dataKeys, isEmpty);
      expect(await a.storage.current(a.userId), 1);
      expect(allZeroed(), isTrue);
    });

    test('this phone\'s wrap is always in the posted body', () async {
      final a = await account();
      final gone = await addDevice(a, 'Chrome on Android');
      final one = await addDevice(a, 'Firefox on Linux');
      final two = await addDevice(a, 'Safari on iOS');
      await (await a.rotate(remove: [gone.id])).commit();
      final posted = [
        for (final w in a.api.posts.single['wraps']! as List) (w as Map).cast<String, Object?>(),
      ];
      final devices = posted.where((w) => w['kind'] == 'device').map((w) => w['id']).toSet();
      expect(devices, {a.own.id, one.id, two.id});
      final own = posted.firstWhere((w) => w['id'] == a.own.id);
      expect(own['publicKey'], a.own.publicKey);
      expect(own['keyV'], 2);
      expect(posted.where((w) => w['kind'] == 'recovery'), hasLength(1));
    });

    test(
      'a fresh rotation sends the new key\'s verifier after the rotate; a typed one sends none',
      () async {
        final a = await account();
        final fresh = await a.rotate(recovery: const FreshRecovery());
        expect(a.api.verifierPuts, isEmpty);
        await fresh.commit();
        expect(a.writes.map((c) => '${c.method} ${c.path}'), [
          'POST /api/v2/keys/rotate',
          'PUT /api/v2/recovery/verifier',
        ]);
        expect(a.writes.last.user, a.userId);
        expect(a.api.verifier, await verifierOf(fresh.recoveryKey!));

        final b = await account();
        await (await b.rotate()).commit();
        expect(b.api.rotations, hasLength(1));
        expect(b.api.verifierPuts, isEmpty);
      },
    );

    test('a verifier that failed is sent again alone: the rotation is not posted twice', () async {
      final a = await account();
      final prepared = await a.rotate(recovery: const FreshRecovery());
      a.api.failVerifier = true;
      expect(await caught(prepared.commit), isKeysError('server', 503));
      expect(a.api.posts, hasLength(1));
      // the rotation is kept on this phone already
      expect(await a.storage.current(a.userId), 2);
      a.api.failVerifier = false;
      await prepared.commit();
      expect(a.api.posts, hasLength(1));
      expect(a.api.verifierPuts, hasLength(2));
      expect(a.api.verifier, await verifierOf(prepared.recoveryKey!));
      // a commit after success sends nothing
      await prepared.commit();
      expect(a.api.posts, hasLength(1));
      expect(a.api.verifierPuts, hasLength(2));
    });

    test('a double tap shares the commit in flight', () async {
      final a = await account();
      final prepared = await a.rotate(recovery: const FreshRecovery());
      await Future.wait([prepared.commit(), prepared.commit()]);
      expect(a.api.posts, hasLength(1));
      expect(a.api.verifierPuts, hasLength(1));
    });
  });

  group('a device wrap that holds another data key at a held key version', () {
    test(
      'rotateKeys refuses it as tampered: nothing is made or sent, and the opened DK is zeroed',
      () async {
        final a = await account();
        await addDevice(a, 'Phone');
        a.own.wrapped = toBase64Url(
          await sealToDevice(
            fromBase64Url(a.own.publicKey!),
            WrapContext(kind: WrapKind.device, userId: a.userId, keyV: 1),
            generateDataKey(),
          ),
        );
        clearHanded();
        expect(await caught(() => a.rotate()), isKeysError('tampered'));
        expect(a.api.rotations, isEmpty);
        expect(a.writes, isEmpty);
        expect(dataKeys, isEmpty);
        expect(openedDevice, isNotEmpty);
        expect(allZeroed(), isTrue);
        expect(await a.storage.current(a.userId), 1);
      },
    );
  });

  group('attested', () {
    test(
      'a wrap without a public key or attestation, or a malformed one, is not attested',
      () async {
        final a = await account();
        final d = await addDevice(a, 'Phone');
        final wrap = a.wrapOf(d.id);
        WrapDto dto({String? publicKey, String? attestation}) => WrapDto(
          id: wrap.id,
          kind: 'device',
          keyV: 1,
          wrapped: wrap.wrapped,
          publicKey: publicKey,
          attestation: attestation,
        );
        expect(
          await attested(
            a.userId,
            a.dk,
            dto(publicKey: wrap.publicKey, attestation: wrap.attestation),
          ),
          isTrue,
        );
        expect(await attested(a.userId, a.dk, dto(attestation: wrap.attestation)), isFalse);
        expect(await attested(a.userId, a.dk, dto(publicKey: wrap.publicKey)), isFalse);
        expect(
          await attested(
            a.userId,
            a.dk,
            dto(publicKey: 'not base64!', attestation: wrap.attestation),
          ),
          isFalse,
        );
        expect(
          await attested(
            a.userId,
            generateDataKey(),
            dto(publicKey: wrap.publicKey, attestation: wrap.attestation),
          ),
          isFalse,
        );
      },
    );
  });

  group('revokedDevices', () {
    test('reads the settings record, and is empty without one', () async {
      final revoked = uuidv7();
      final a = await account([revoked]);
      expect(await revokedDevices(a.store), [revoked]);
      final empty = await SqliteStore.open(
        newUser(),
        directory: dir.path,
        factory: databaseFactoryFfi,
      );
      expect(await revokedDevices(empty), isEmpty);
    });
  });

  group('keepRotated without a settings record', () {
    test('a vault with no settings yet keeps the keys and writes no settings', () async {
      final a = await account();
      final gone = await addDevice(a, 'Chrome on Android');
      final emptyStore = await SqliteStore.open(
        newUser(),
        directory: dir.path,
        factory: databaseFactoryFfi,
      );
      final prepared = await rotateKeys(
        a.options,
        store: emptyStore,
        remove: [gone.id],
        recovery: TypedRecovery(a.recoveryKey),
      );
      await prepared.commit();
      expect(await a.storage.current(a.userId), 2);
      expect(await emptyStore.list(RecordType.settings), isEmpty);
    });
  });
}
