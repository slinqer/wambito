// The phone approving a web sign-in (phone-first spec 8.1, steps 2-6) over a fake `/v2/signin`
// relay with the API's rules (apps/api/src/routes/signin.ts) that also serves `/v2/keys` from
// [FakeKeys]. The test plays the browser with real crypto, as apps/web/app/local/signin.ts does:
// its own `N`, the commitment `pairingCommitment(N.pub)`, the QR, the number
// `pairingNumber(N.pub, A.pub)` and `openFromPairing` on the sealed data key.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/keys.dart';
import 'package:wambito/local/pairing.dart' show pairingSealToDevice;
import 'package:wambito/local/relay.dart' show relayTooManyWait;
import 'package:wambito/local/signin_approval.dart';

import 'fake_keys.dart';
import 'fake_signin.dart';

class World {
  World(this.clock, this.keys, this.relay, this.userId, this.dataKey, this.options, this.browser);

  final FakeClock clock;
  final FakeKeys keys;
  final FakeSignin relay;
  final String userId;
  final Uint8List dataKey;
  final KeysOptions options;
  final Browser browser;

  String qrOf(SigninRow row) => 'wambito://signin?id=${row.id}&key=${browser.key}';
  bool get sealPosted => relay.log.any((l) => l.endsWith('/seal'));
}

/// This phone's account with a device wrap at key version 2, and a browser whose reveal is honest.
Future<World> world() async {
  final clock = FakeClock();
  final keys = FakeKeys();
  final relay = FakeSignin(clock, keys);
  final storage = memoryKeyStorage();
  final userId = newUser();
  final dk = generateDataKey();
  await seedDevice(
    api: keys,
    storage: storage,
    userId: userId,
    held: {2: Uint8List.fromList(dk)},
    current: 2,
    deviceDk: dk,
    deviceV: 2,
  );
  keys.calls.clear();
  openedDevice.clear();
  ephemerals.clear();
  final browser = Browser(await generateDeviceKeyPair());
  relay.reveal = (_) => browser.key;
  return World(
    clock,
    keys,
    relay,
    userId,
    dk,
    KeysOptions(userId: userId, dio: relay.dio(), storage: storage),
    browser,
  );
}

/// Every ephemeral key `A` this phone made, to check it is zeroed.
final ephemerals = <DeviceKeyPair>[];

Future<String> signinErrorOf(Future<Object?> promise) async {
  try {
    await promise;
  } on SigninError catch (e) {
    return e.code;
  }
  throw TestFailure('expected a SigninError');
}

bool zeroedKey(DeviceKeyPair pair) => pair.privateKey.every((b) => b == 0);

void main() {
  recordOpenedKeys();

  setUp(() {
    signinGenerateDeviceKeyPair = () async {
      final pair = await generateDeviceKeyPair();
      ephemerals.add(pair);
      return pair;
    };
  });
  tearDown(() {
    signinGenerateDeviceKeyPair = generateDeviceKeyPair;
    pairingSealToDevice = sealToDevice;
  });

  test('a scanned QR: approve, the key checks, no number, seal is sent and the web side opens the data key with openFromPairing', () async {
    final w = await world();
    final row = await w.relay.open(w.browser);
    final approval = await findSigninRequest(w.options, qr: w.qrOf(row), clock: w.clock);
    expect(approval.label, 'Firefox on Mac');
    expect(approval.typed, isFalse);
    expect(approval.expiresAt, row.expiresAt.toIso8601String());
    // nothing is posted before the person said yes
    expect(w.relay.log, ['GET /v2/signin/${row.id}']);

    expect(await approval.approve(), isNull);
    expect(row.approverKey, toBase64Url(ephemerals.single.publicKey));
    await approval.seal();

    // the browser opens it as `startSignin`'s finish does: N.priv, the device context of the
    // phone's user, and the approver key it pinned
    final opened = await openFromPairing(
      w.browser.pair.privateKey,
      WrapContext(kind: WrapKind.device, userId: w.userId, keyV: row.keyV!),
      fromBase64Url(row.sealed!),
      fromBase64Url(row.approverKey!),
    );
    expect(opened, w.dataKey);
    expect(row.keyV, 2);
    // DK came from this phone's device wrap and is zeroed; so is A
    expect(openedDevice, hasLength(1));
    expect(zeroed(openedDevice[0]), isTrue);
    expect(zeroedKey(ephemerals.single), isTrue);
    expect(w.relay.log.where((l) => l.endsWith('/seal')), hasLength(1));
  });

  test('a typed code: seal before approve resolves is a StateError and sends nothing', () async {
    final w = await world();
    final row = await w.relay.open(w.browser);
    final approval = await findSigninRequest(w.options, code: ' abcd-2345 ', clock: w.clock);
    expect(approval.typed, isTrue);
    expect(w.relay.log, ['GET /v2/signin?code=ABCD2345']);
    await expectLater(approval.seal(), throwsA(isA<StateError>()));

    final approving = approval.approve();
    await expectLater(approval.seal(), throwsA(isA<StateError>()));
    final number = await approving;
    expect(w.sealPosted, isFalse);
    expect(w.keys.calls.any((c) => c.path == '/api/v2/keys'), isFalse);

    // the browser shows the same 6 digits
    final a = fromBase64Url(row.approverKey!);
    expect(number, await pairingNumber(w.browser.pair.publicKey, a));
    expect(number, matches(RegExp(r'^\d{6}$')));

    // once the number was shown, the same object seals
    await approval.seal();
    expect(w.relay.log.where((l) => l.endsWith('/seal')), hasLength(1));
    expect(zeroedKey(ephemerals.single), isTrue);
  });

  test("a revealed key that misses the commitment, or differs from the QR's, is tampered and nothing is sealed", () async {
    // typed: the server relays another key than the one behind the pinned commitment
    final w = await world();
    final row = await w.relay.open(w.browser);
    final evil = await generateDeviceKeyPair();
    w.relay.reveal = (_) => toBase64Url(evil.publicKey);
    final typed = await findSigninRequest(w.options, code: row.code, clock: w.clock);
    expect(await signinErrorOf(typed.approve()), 'tampered');
    await expectLater(typed.seal(), throwsA(anything));
    expect(w.sealPosted, isFalse);
    expect(zeroedKey(ephemerals.single), isTrue);

    // typed: the commitment changes after it was pinned (and the key matches the new one)
    final v = await world();
    final again = await v.relay.open(v.browser);
    final typed2 = await findSigninRequest(v.options, code: again.code, clock: v.clock);
    final evilCommitment = toBase64Url(await pairingCommitment(evil.publicKey));
    v.relay.onGet = (body) => body['commitment'] = evilCommitment;
    v.relay.reveal = (_) => toBase64Url(evil.publicKey);
    expect(await signinErrorOf(typed2.approve()), 'tampered');
    expect(v.sealPosted, isFalse);

    // a QR whose key is not behind the server's commitment: nothing is posted at all
    final x = await world();
    final third = await x.relay.open(x.browser);
    final forged = 'wambito://signin?id=${third.id}&key=${toBase64Url(evil.publicKey)}';
    expect(
      await signinErrorOf(findSigninRequest(x.options, qr: forged, clock: x.clock)),
      'tampered',
    );
    expect(third.approverKey, isNull);

    // a QR, and a revealed key other than the QR's
    final scanned = await findSigninRequest(x.options, qr: x.qrOf(third), clock: x.clock);
    x.relay.reveal = (_) => toBase64Url(evil.publicKey);
    expect(await signinErrorOf(scanned.approve()), 'tampered');
    expect(await signinErrorOf(scanned.seal()), 'tampered');
    expect(x.sealPosted, isFalse);
  });

  test('a second approver (409 already_set) is tampered', () async {
    final w = await world();
    final row = await w.relay.open(w.browser);
    final approval = await findSigninRequest(w.options, qr: w.qrOf(row), clock: w.clock);
    row.approverKey = toBase64Url((await generateDeviceKeyPair()).publicKey);
    expect(await signinErrorOf(approval.approve()), 'tampered');
    expect(w.sealPosted, isFalse);
    expect(zeroedKey(ephemerals.single), isTrue);
  });

  test('expiring between approve and seal throws expired and posts no seal', () async {
    final w = await world();
    // the server would still answer: only this phone's clock ends it
    w.relay.expires = false;
    final row = await w.relay.open(w.browser);
    final approval = await findSigninRequest(w.options, code: row.code, clock: w.clock);
    final number = await approval.approve();
    expect(number, isNotNull);
    // the person reads slowly
    w.clock.t = w.clock.t.add(const Duration(minutes: 2));
    expect(await signinErrorOf(approval.seal()), 'expired');
    expect(w.sealPosted, isFalse);
    expect(w.keys.calls.any((c) => c.path == '/api/v2/keys'), isFalse);
    expect(zeroedKey(ephemerals.single), isTrue);
  });

  test('cancel zeroes the ephemeral key', () async {
    final w = await world();
    final row = await w.relay.open(w.browser);
    final approval = await findSigninRequest(w.options, qr: w.qrOf(row), clock: w.clock);
    approval.cancel();
    expect(zeroedKey(ephemerals.single), isTrue);
    expect(await signinErrorOf(approval.approve()), 'cancelled');
    expect(w.relay.log.where((l) => l.startsWith('POST')), isEmpty);

    // cancelled while it waits for the browser's key
    final v = await world();
    v.relay.reveal = null;
    final waiting = await v.relay.open(v.browser);
    final other = await findSigninRequest(v.options, qr: v.qrOf(waiting), clock: v.clock);
    final approving = other.approve();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    other.cancel();
    expect(zeroedKey(ephemerals.single), isTrue);
    expect(await signinErrorOf(approving), 'cancelled');
    expect(v.sealPosted, isFalse);
  });

  test("the 2 minutes run on this phone's clock from when the request was read, never on the server's expiresAt", () async {
    // the server's clock is 10 minutes behind: its expiresAt is already past on this phone
    final w = await world();
    w.relay.serverAhead = const Duration(minutes: -10);
    final row = await w.relay.open(w.browser);
    expect(row.expiresAt.isBefore(w.clock.t), isTrue);
    final approval = await findSigninRequest(w.options, qr: w.qrOf(row), clock: w.clock);
    await approval.approve();
    await approval.seal();
    expect(row.sealed, isNotNull);

    // the server says a year: the phone still stops 2 minutes after its read
    final v = await world();
    v.relay.ttlSays = const Duration(days: 365);
    v.relay.reveal = null;
    final late = await v.relay.open(v.browser);
    v.clock.t = v.clock.t.add(const Duration(minutes: 5));
    final read = v.clock.t;
    final waiting = await findSigninRequest(v.options, code: late.code, clock: v.clock);
    expect(await signinErrorOf(waiting.approve()), 'expired');
    expect(v.clock.t.difference(read), greaterThanOrEqualTo(signinTtl));
    expect(v.clock.t.difference(read), lessThan(signinTtl + signinPoll * 2));
  });

  test(
    'a 429 without retry-after backs off before it asks again; with one, it waits that',
    () async {
      final w = await world();
      final row = await w.relay.open(w.browser);
      final approval = await findSigninRequest(w.options, qr: w.qrOf(row), clock: w.clock);
      var tooMany = 2;
      w.relay.intercept = (method, path) {
        if (method == 'GET' && tooMany > 0) {
          tooMany -= 1;
          return (429, {'code': 'too_many_requests'}, const {});
        }
        return null;
      };
      await approval.approve();
      // never at once: a wait, then a longer one
      expect(w.clock.sleeps.take(2).toList(), [relayTooManyWait, relayTooManyWait * 2]);

      final v = await world();
      final next = await v.relay.open(v.browser);
      var once = true;
      v.relay.intercept = (method, path) {
        if (method == 'POST' && path.endsWith('/approver') && once) {
          once = false;
          return (429, {'code': 'too_many_requests'}, {'retry-after': '7'});
        }
        return null;
      };
      final scanned = await findSigninRequest(v.options, qr: v.qrOf(next), clock: v.clock);
      await scanned.approve();
      expect(v.clock.sleeps.first, const Duration(seconds: 7));
      expect(v.relay.log.where((l) => l.endsWith('/approver')), hasLength(2));
    },
  );

  test('a QR or a code that cannot be one is bad_code, and so is an unknown code', () async {
    final w = await world();
    final row = await w.relay.open(w.browser);
    final key = w.browser.key;
    for (final qr in [
      'wambito://pair?id=${row.id}&key=$key',
      'https://app.wambito.com/signin?id=${row.id}&key=$key',
      'wambito://signin?id=${row.id}',
      'wambito://signin?key=$key&id=${row.id}',
      'wambito://signin?id=${row.id}&key=${key.substring(0, 40)}',
      'wambito://signin?id=not-an-id&key=$key',
      '${w.qrOf(row)}&x=1',
    ]) {
      expect(await signinErrorOf(findSigninRequest(w.options, qr: qr, clock: w.clock)), 'bad_code');
    }
    expect(
      await signinErrorOf(findSigninRequest(w.options, code: 'ABC', clock: w.clock)),
      'bad_code',
    );
    expect(w.relay.log, isEmpty);
    expect(
      await signinErrorOf(findSigninRequest(w.options, code: 'ZZZZZZZZ', clock: w.clock)),
      'bad_code',
    );
    expect(() => findSigninRequest(w.options, clock: w.clock), throwsArgumentError);
    expect(ephemerals, isEmpty);
  });

  test('the seal waits for the browser to pick it up', () async {
    final w = await world();
    w.relay.pickUp = false;
    w.relay.expires = false;
    final row = await w.relay.open(w.browser);
    final approval = await findSigninRequest(w.options, qr: w.qrOf(row), clock: w.clock);
    await approval.approve();
    final sealing = approval.seal();
    var done = false;
    unawaited(sealing.then((_) => done = true, onError: (_) {}));
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(row.sealed, isNotNull);
    expect(done, isFalse);
    row.pickedUp = true;
    await sealing;
  });

  test('a link-opened request cannot seal without the number', () async {
    final w = await world();
    final row = await w.relay.open(w.browser);
    final approval = await findSigninRequest(
      w.options,
      qr: w.qrOf(row),
      fromLink: true,
      clock: w.clock,
    );
    expect(approval.fromLink, isTrue);
    expect(approval.typed, isFalse);
    expect(approval.comparesNumber, isTrue);
    await expectLater(approval.seal(), throwsA(isA<StateError>()));
    final approving = approval.approve();
    await expectLater(approval.seal(), throwsA(isA<StateError>()));
    final number = await approving;
    expect(w.sealPosted, isFalse);
    // the browser shows the same 6 digits in its QR flow
    expect(number, await pairingNumber(w.browser.pair.publicKey, fromBase64Url(row.approverKey!)));
    await approval.seal();
    expect(row.sealed, isNotNull);

    // the QR's key is still checked
    final v = await world();
    final other = await v.relay.open(v.browser);
    final evil = await generateDeviceKeyPair();
    v.relay.reveal = (_) => toBase64Url(evil.publicKey);
    final linked = await findSigninRequest(
      v.options,
      qr: v.qrOf(other),
      fromLink: true,
      clock: v.clock,
    );
    expect(await signinErrorOf(linked.approve()), 'tampered');
    expect(v.sealPosted, isFalse);
  });

  test('a retry-after past the deadline is expired at once, with no wait', () async {
    final w = await world();
    final row = await w.relay.open(w.browser);
    final approval = await findSigninRequest(w.options, qr: w.qrOf(row), clock: w.clock);
    w.relay.intercept = (method, path) =>
        (429, {'code': 'too_many_requests'}, {'retry-after': '600'});
    expect(await signinErrorOf(approval.approve()), 'expired');
    expect(w.clock.sleeps, isEmpty);
  });

  test('once the seal is out, a pickup it cannot see is unconfirmed, not a failure', () async {
    final w = await world();
    w.relay.pickUp = false;
    w.relay.expires = false;
    final row = await w.relay.open(w.browser);
    final approval = await findSigninRequest(w.options, qr: w.qrOf(row), clock: w.clock);
    await approval.approve();
    expect(await signinErrorOf(approval.seal()), 'unconfirmed');
    expect(row.sealed, isNotNull);
  });
}
