import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/keys.dart';
import 'package:wambito/local/rotate.dart';

import 'fake_keys.dart';

/// The recovery part of apps/web/app/local/rotate.test.ts (`newRecoveryKey`, `checkRecoveryKey`),
/// against the fake `/v2/keys`, plus the recovery verifier (D16) the web does not send yet.

/// Every recovery secret `newRecoveryKey` made, and every one `parseRecoveryKey` handed out.
final madeSecrets = <Uint8List>[];
final parsedSecrets = <Uint8List>[];

KeysOptions optionsOf(FakeKeys api, String userId, KeyStorage storage) =>
    KeysOptions(userId: userId, dio: api.dio(), storage: storage);

/// An account set up on this phone (keyV 1): its DK and recovery key.
class Account {
  Account(this.api, this.storage, this.userId, this.recoveryKey, this.dk);

  final FakeKeys api;
  final KeyStorage storage;
  final String userId;
  final String recoveryKey;
  final Uint8List dk;

  KeysOptions get options => optionsOf(api, userId, storage);
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

Future<Account> account() async {
  final api = FakeKeys();
  final storage = memoryKeyStorage();
  final userId = newUser();
  final options = optionsOf(api, userId, storage);
  final prepared = await prepareAccount(options, guest: false);
  await prepared.commit();
  final recoveryKey = prepared.recoveryKey!;
  final dk = await openRecovery(api, userId, recoveryKey, 1);
  api
    ..calls.clear()
    ..verifier = null;
  openedLinks.clear();
  openedDevice.clear();
  parsedSecrets.clear();
  madeSecrets.clear();
  return Account(api, storage, userId, recoveryKey, dk);
}

/// What the verifier of [recoveryKey] is, base64url, as the server stores it.
Future<({String lookupHash, String authHash})> verifierOf(String recoveryKey) async {
  final hashes = await verifierHashesOf(parseRecoveryKey(recoveryKey));
  return (lookupHash: toBase64Url(hashes.lookupHash), authHash: toBase64Url(hashes.authHash));
}

void main() {
  recordOpenedKeys();
  setUp(() {
    keysParseRecoveryKey = (text) {
      final secret = parseRecoveryKey(text);
      parsedSecrets.add(secret);
      return secret;
    };
    keysNewRecoverySecret = () {
      final secret = newRecoverySecret();
      madeSecrets.add(secret);
      return secret;
    };
  });
  tearDown(() {
    keysParseRecoveryKey = parseRecoveryKey;
    keysNewRecoverySecret = newRecoverySecret;
  });

  group('a device wrap that holds another data key at a held key version', () {
    test('newRecoveryKey refuses it as tampered, and sends nothing', () async {
      final a = await account();
      final own = a.api.wraps.firstWhere((w) => w.kind == 'device');
      own.wrapped = toBase64Url(
        await sealToDevice(
          fromBase64Url(own.publicKey!),
          WrapContext(kind: WrapKind.device, userId: a.userId, keyV: 1),
          generateDataKey(),
        ),
      );
      openedDevice.clear();
      expect(await caught(() => newRecoveryKey(a.options)), isKeysError('tampered'));
      expect(a.api.puts, isEmpty);
      expect(a.api.verifierPuts, isEmpty);
      expect(openedDevice.every(zeroed), isTrue);
    });
  });

  group('newRecoveryKey', () {
    test('newRecoveryKey replaces the recovery wrap at the current keyV (PUT, same kind) only on commit', () async {
      final a = await account();
      final prepared = await newRecoveryKey(a.options);
      expect(prepared.recoveryKey, matches(RegExp(r'^([0-9A-Z]{4}-){6}[0-9A-Z]{3}$')));
      expect(a.api.puts, isEmpty);
      // the old key still opens until commit
      expect(await openRecovery(a.api, a.userId, a.recoveryKey, 1), a.dk);

      await prepared.commit();
      expect(a.api.puts.map((p) => [p.body!['kind'], p.body!['keyV']]), [
        ['recovery', 1],
      ]);
      expect(a.api.wraps.where((w) => w.kind == 'recovery'), hasLength(1));
      expect(await openRecovery(a.api, a.userId, prepared.recoveryKey, 1), a.dk);
      expect(await caught(() => openRecovery(a.api, a.userId, a.recoveryKey, 1)), isNotNull);
      expect(madeSecrets, hasLength(1));
      expect(madeSecrets.every(zeroed), isTrue);
      expect(openedDevice.every(zeroed), isTrue);
    });

    test('the secret is zeroed before newRecoveryKey returns', () async {
      final a = await account();
      await newRecoveryKey(a.options);
      expect(madeSecrets, hasLength(1));
      expect(zeroed(madeSecrets.single), isTrue);
    });

    test(
      'forget() zeroes the verifier hashes and refuses a later commit; nothing is sent',
      () async {
        final a = await account();
        final prepared = await newRecoveryKey(a.options);
        prepared.forget();
        expect(await caught(prepared.commit), isKeysError('abandoned'));
        expect(a.api.calls.where((c) => c.method == 'PUT'), isEmpty);
        expect(a.api.verifierPuts, isEmpty);
      },
    );

    test('the verifier follows the wrap', () async {
      final a = await account();
      final prepared = await newRecoveryKey(a.options);
      expect(a.api.verifierPuts, isEmpty);
      await prepared.commit();

      final writes = a.api.calls.where((c) => c.method == 'PUT').toList();
      expect(writes.map((c) => c.path), [
        matches(RegExp(r'^/api/v2/keys/[0-9a-f-]{36}$')),
        '/api/v2/recovery/verifier',
      ]);
      final hashes = await verifierHashesOf(parseRecoveryKey(prepared.recoveryKey));
      expect(writes.last.body, {
        'lookupHash': toBase64Url(hashes.lookupHash),
        'authHash': toBase64Url(hashes.authHash),
      });
      expect(writes.last.user, a.userId);
      expect(a.api.verifier, await verifierOf(prepared.recoveryKey));
    });

    test(
      'a failed commit is retried with the same wrap id; offline throughout is offline',
      () async {
        final a = await account();
        final prepared = await newRecoveryKey(a.options);
        a.api.offline = true;
        expect(await caught(prepared.commit), isKeysError('offline'));
        a.api.offline = false;
        await prepared.commit();
        expect(a.api.puts, hasLength(1));
        expect(
          a.api.wraps.firstWhere((w) => w.kind == 'recovery').id,
          a.api.puts.single.path.split('/').last,
        );
        expect(a.api.verifier, await verifierOf(prepared.recoveryKey));
      },
    );

    test('a verifier that failed is sent again alone: the wrap is not put twice', () async {
      final a = await account();
      final prepared = await newRecoveryKey(a.options);
      a.api.failVerifier = true;
      expect(await caught(prepared.commit), isKeysError('server', 503));
      expect(a.api.puts, hasLength(1));
      a.api.failVerifier = false;
      await prepared.commit();
      expect(a.api.puts, hasLength(1));
      expect(a.api.verifierPuts, hasLength(2));
      expect(a.api.verifier, await verifierOf(prepared.recoveryKey));
      // a commit after success sends nothing
      await prepared.commit();
      expect(a.api.puts, hasLength(1));
      expect(a.api.verifierPuts, hasLength(2));
    });

    test('a double tap shares the commit in flight', () async {
      final a = await account();
      final prepared = await newRecoveryKey(a.options);
      await Future.wait([prepared.commit(), prepared.commit()]);
      expect(a.api.puts, hasLength(1));
      expect(a.api.verifierPuts, hasLength(1));
    });

    test(
      'a PUT whose answer was lost counts as saved when GET /v2/keys shows the prepared wrap',
      () async {
        final a = await account();
        final prepared = await newRecoveryKey(a.options);
        a.api.losePutAnswer = true;
        await prepared.commit();
        expect(await openRecovery(a.api, a.userId, prepared.recoveryKey, 1), a.dk);
      },
    );

    test('a lost wrap answer that landed still sends the verifier', () async {
      final a = await account();
      final prepared = await newRecoveryKey(a.options);
      a.api.losePutAnswer = true;
      await prepared.commit();
      expect(a.api.verifierPuts, hasLength(1));
      expect(a.api.verifier, await verifierOf(prepared.recoveryKey));
    });

    test('a lost wrap answer that did not land is an error, and no verifier is sent', () async {
      final a = await account();
      final prepared = await newRecoveryKey(a.options);
      a.api.intercept = (call) {
        if (call.method == 'PUT') throw StateError('network down');
        return null;
      };
      expect(await caught(prepared.commit), isNotNull);
      expect(a.api.verifierPuts, isEmpty);
    });

    test('a key version that moved is rotated_elsewhere, and nothing was kept', () async {
      final a = await account();
      final prepared = await newRecoveryKey(a.options);
      for (final w in a.api.wraps) {
        w.keyV = 2;
      }
      final before = a.api.wraps.firstWhere((w) => w.kind == 'recovery');
      final (id, wrapped) = (before.id, before.wrapped);
      expect(await caught(prepared.commit), isKeysError('rotated_elsewhere', 409));
      // refused: the account's recovery wrap is the one it was
      final after = a.api.wraps.firstWhere((w) => w.kind == 'recovery');
      expect((after.id, after.wrapped), (id, wrapped));
    });

    test('rotated_elsewhere sends no verifier', () async {
      final a = await account();
      final prepared = await newRecoveryKey(a.options);
      for (final w in a.api.wraps) {
        w.keyV = 2;
      }
      expect(await caught(prepared.commit), isKeysError('rotated_elsewhere', 409));
      expect(a.api.verifierPuts, isEmpty);
      expect(a.api.verifier, isNull);
    });
  });

  group('checkRecoveryKey', () {
    test('resolves for the account\'s recovery key, and names a wrong or malformed one; the secret is zeroed', () async {
      final a = await account();
      await checkRecoveryKey(a.options, a.recoveryKey);
      final stranger = formatRecoveryKey(newRecoverySecret());
      expect(
        await caught(() => checkRecoveryKey(a.options, stranger)),
        isKeysError('wrong_recovery_key'),
      );
      expect(
        await caught(() => checkRecoveryKey(a.options, 'nope')),
        isKeysError('bad_recovery_key'),
      );
      expect(parsedSecrets, hasLength(2));
      expect(parsedSecrets.every(zeroed), isTrue);
      expect(openedDevice, isEmpty);
      expect(a.api.puts, isEmpty);
      expect(a.api.verifierPuts, isEmpty);
    });

    test('an account without a recovery wrap is wrong_recovery_key', () async {
      final a = await account();
      a.api.wraps.removeWhere((w) => w.kind == 'recovery');
      expect(
        await caught(() => checkRecoveryKey(a.options, a.recoveryKey)),
        isKeysError('wrong_recovery_key'),
      );
    });
  });

  group('putRecoveryVerifier', () {
    test('PUTs base64url lookupHash and authHash, naming the account', () async {
      final a = await account();
      final hashes = (
        lookupHash: Uint8List(32)..fillRange(0, 32, 7),
        authHash: Uint8List(32)..fillRange(0, 32, 9),
      );
      await putRecoveryVerifier(a.options, hashes);
      final put = a.api.verifierPuts.single;
      expect(put.user, a.userId);
      expect(put.body, {
        'lookupHash': toBase64Url(hashes.lookupHash),
        'authHash': toBase64Url(hashes.authHash),
      });
    });

    test('verifierHashesOf hashes the two HKDF outputs', () async {
      final secret = Uint8List.fromList(List.generate(16, (i) => i + 1));
      final verifier = await recoveryVerifier(secret);
      final hashes = await verifierHashesOf(secret);
      expect(hashes.lookupHash, await verifierHash(verifier.lookup));
      expect(hashes.authHash, await verifierHash(verifier.auth));
      expect(hashes.lookupHash, hasLength(32));
      expect(hashes.authHash, hasLength(32));
    });

    test('verifierHashesOf zeroes the two HKDF outputs', () async {
      final derived = <RecoveryVerifier>[];
      keysRecoveryVerifier = (secret) async {
        final verifier = await recoveryVerifier(secret);
        derived.add(verifier);
        return verifier;
      };
      addTearDown(() => keysRecoveryVerifier = recoveryVerifier);
      final secret = Uint8List.fromList(List.generate(16, (i) => i + 1));
      await verifierHashesOf(secret);
      expect(derived, hasLength(1));
      expect(zeroed(derived.single.lookup), isTrue);
      expect(zeroed(derived.single.auth), isTrue);
      // the caller owns the secret
      expect(zeroed(secret), isFalse);
    });
  });
}
