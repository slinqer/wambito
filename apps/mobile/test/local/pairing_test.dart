// Port of apps/web/app/local/pairing.test.ts: the 12 cases, same names, over a fake `/v2/pairing`
// relay (the rules of apps/api/src/services/pairing.ts) that also serves `/v2/keys` from
// [FakeKeys]. Tamper hooks stand in for a malicious server.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/keys.dart';
import 'package:wambito/local/pairing.dart';

import 'fake_keys.dart';

const ttl = Duration(minutes: 10);

class Row {
  Row({required this.id, required this.code, required this.commitment, required this.expiresAt});

  final String id;
  String code;
  final String commitment;
  String? approverKey;
  String? publicKey;
  String? sealed;
  int? keyV;
  DateTime expiresAt;
}

/// `normalizePairingCode` of `apps/api/src/services/pairing.ts`.
String normalize(String input) => input
    .toUpperCase()
    .replaceAll(RegExp(r'[-\s]'), '')
    .replaceAll(RegExp('[IL]'), '1')
    .replaceAll('O', '0');

class FakeClock implements PairingClock {
  DateTime t = DateTime.utc(2026, 11, 10, 12);
  final sleeps = <Duration>[];

  @override
  DateTime now() => t;

  @override
  Future<void> sleep(Duration d) async {
    sleeps.add(d);
    t = t.add(d);
    await Future<void>.delayed(Duration.zero);
  }
}

/// The `/v2/pairing` relay; anything else goes to [keys].
class FakeRelay implements HttpClientAdapter {
  FakeRelay(this.clock, this.keys);

  final FakeClock clock;
  final FakeKeys keys;
  final rows = <String, Row>{};
  final log = <String>[];

  /// The relay never expires rows: only the clients' own clocks stop them.
  bool ignoreExpiry = false;

  /// How long the relay says a new request lives (a hostile relay may say much longer).
  Duration ttlSays = ttl;
  void Function(Map<String, Object?> body, Row row)? onGet;
  void Function(Map<String, Object?> body)? onPickup;

  /// Sees each pairing request first: an answer replaces the relay's.
  (int, Object?)? Function(String method, String path)? intercept;

  Dio dio() => Dio(BaseOptions(baseUrl: 'http://x/api'))..httpClientAdapter = this;

  Row? _live(String id) {
    final row = rows[id];
    if (row == null || (!ignoreExpiry && !row.expiresAt.isAfter(clock.t))) return null;
    return row;
  }

  ResponseBody _json(Object? body, [int status = 200]) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  ResponseBody _problem(int status, String code) => _json({'code': code}, status);

  ResponseBody _empty(int status) => ResponseBody.fromString('', status);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst(RegExp('^/api'), '');
    if (!path.startsWith('/v2/pairing')) return keys.fetch(options, requestStream, cancelFuture);
    final method = options.method.toUpperCase();
    expect(options.headers['x-wambito-user'], isNotNull);
    log.add('$method ${options.uri.path}${options.uri.hasQuery ? '?${options.uri.query}' : ''}');
    final data = options.data;
    final body = data is Map
        ? data.cast<String, Object?>()
        : data is String && data.isNotEmpty
        ? (jsonDecode(data) as Map).cast<String, Object?>()
        : null;
    final hooked = intercept?.call(method, path);
    if (hooked != null) return _json(hooked.$2, hooked.$1);

    if (path == '/v2/pairing' && method == 'POST') {
      final id = newUuid();
      final row = Row(
        id: id,
        code: pairingCode(),
        commitment: body!['commitment']! as String,
        expiresAt: clock.t.add(ttlSays),
      );
      rows[id] = row;
      return _json({'id': id, 'code': row.code, 'expiresAt': row.expiresAt.toIso8601String()}, 201);
    }
    if (path == '/v2/pairing' && method == 'GET') {
      final code = normalize(options.uri.queryParameters['code'] ?? '');
      final row = rows.values
          .where((r) => r.code == code && r.approverKey == null && _live(r.id) != null)
          .firstOrNull;
      if (row == null) return _problem(404, 'not_found');
      return _json({
        'id': row.id,
        'commitment': row.commitment,
        'expiresAt': row.expiresAt.toIso8601String(),
      });
    }
    final match = RegExp(r'^/v2/pairing/([0-9a-f-]{36})(?:/(\w+))?$').firstMatch(path);
    if (match == null) return _empty(404);
    final row = _live(match.group(1)!);
    if (row == null) return _problem(404, 'not_found');
    final action = match.group(2);
    if (action == null && method == 'GET') {
      final out = <String, Object?>{
        'commitment': row.commitment,
        'approverKey': row.approverKey,
        'publicKey': row.publicKey,
        'sealed': row.sealed,
        'keyV': row.keyV,
        'expiresAt': row.expiresAt.toIso8601String(),
      };
      onGet?.call(out, row);
      return _json(out);
    }
    if (action == 'approver' && method == 'POST') {
      if (row.approverKey != null) return _problem(409, 'already_set');
      row.approverKey = body!['publicKey']! as String;
      return _empty(204);
    }
    if (action == 'reveal' && method == 'POST') {
      if (row.approverKey == null) return _problem(409, 'not_ready');
      if (row.publicKey != null) return _problem(409, 'already_set');
      final key = body!['publicKey']! as String;
      final hash = toBase64Url(await pairingCommitment(fromBase64Url(key)));
      if (hash != row.commitment) return _problem(422, 'commitment_mismatch');
      row.publicKey = key;
      return _empty(204);
    }
    if (action == 'seal' && method == 'POST') {
      if (row.sealed != null) return _problem(409, 'already_sealed');
      if (row.approverKey == null || row.publicKey == null) return _problem(409, 'not_ready');
      final blob = fromBase64Url(body!['sealed']! as String);
      if (toBase64Url(blob.sublist(0, 32)) != row.approverKey) {
        return _problem(422, 'approver_mismatch');
      }
      final current = keys.wraps.map((w) => w.keyV).fold(0, (a, b) => a > b ? a : b);
      if (body['keyV'] != current) return _problem(409, 'key_version_mismatch');
      row.sealed = body['sealed']! as String;
      row.keyV = body['keyV']! as int;
      return _empty(204);
    }
    if (action == 'pickup' && method == 'POST') {
      if (row.sealed == null || row.keyV == null) return _problem(409, 'not_ready');
      rows.remove(row.id);
      final out = <String, Object?>{'sealed': row.sealed, 'keyV': row.keyV};
      onPickup?.call(out);
      return _json(out);
    }
    return _empty(404);
  }

  @override
  void close({bool force = false}) {}
}

String newUuid() {
  final b = generateDataKey().sublist(0, 16);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// What the crypto was asked for, to check the seal's context and the zeroing.
final openedPairing = <Uint8List>[];
final seals = <({WrapContext ctx, bool ephemeral, Uint8List dataKey})>[];

class World {
  World(this.clock, this.keys, this.relay, this.userId, this.dataKey, this.options);

  final FakeClock clock;
  final FakeKeys keys;
  final FakeRelay relay;
  final String userId;
  final Uint8List dataKey;
  final KeysOptions options;
}

/// An account whose approving phone holds a device wrap at key version 2, a shared fake clock
/// whose `sleep` moves time on, and the options of both devices.
Future<World> world() async {
  final clock = FakeClock();
  final keys = FakeKeys();
  final relay = FakeRelay(clock, keys);
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
  openedPairing.clear();
  seals.clear();
  return World(
    clock,
    keys,
    relay,
    userId,
    dk,
    KeysOptions(userId: userId, dio: relay.dio(), storage: storage),
  );
}

Future<String> pairingErrorOf(Future<Object?> promise) async {
  try {
    await promise;
  } on PairingError catch (e) {
    return e.code;
  }
  throw TestFailure('expected a PairingError');
}

/// Lets a promise fail on its own without anyone listening.
void quiet(Future<Object?> promise) => unawaited(promise.then((_) {}, onError: (_) {}));

Future<void> ticks(int n) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  recordOpenedKeys();

  setUp(() {
    pairingOpenFromPairing = (privateKey, ctx, sealed, approverKey) async {
      final out = await openFromPairing(privateKey, ctx, sealed, approverKey);
      openedPairing.add(out);
      return out;
    };
    pairingSealToDevice = (publicKey, ctx, dataKey, {ephemeral}) async {
      seals.add((ctx: ctx, ephemeral: ephemeral != null, dataKey: dataKey));
      return sealToDevice(publicKey, ctx, dataKey, ephemeral: ephemeral);
    };
  });
  tearDown(() {
    pairingOpenFromPairing = openFromPairing;
    pairingSealToDevice = sealToDevice;
  });

  group('pairing', () {
    test('the happy path', () async {
      final w = await world();
      final fresh = await startPairing(w.options, clock: w.clock);
      expect(fresh.code, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{8}$')));
      expect(fresh.qr, matches(RegExp('^wambito://pair\\?id=${fresh.id}&key=[A-Za-z0-9_-]{43}\$')));
      // the QR's key is the one behind the commitment
      final qrKey = fromBase64Url(fresh.qr.split('&key=')[1]);
      expect(toBase64Url(await pairingCommitment(qrKey)), w.relay.rows[fresh.id]!.commitment);

      final approver = await findPairing(w.options, code: fresh.code, clock: w.clock);
      final numbers = await Future.wait([fresh.number(), approver.number()]);
      expect(numbers[0], matches(RegExp(r'^\d{6}$')));
      expect(numbers[0], numbers[1]);

      final results = await Future.wait<Object?>([fresh.finish(), approver.approve()]);
      final keyring = (results[0]! as LocalKeys).keyring;
      expect(keyring.current, 2);
      final record = RecordContext(userId: w.userId, type: RecordType.category, id: rec, keyV: 2);
      final sealed = await sealRecord(await deriveRecordKeys(w.dataKey), record, {'s': 1});
      expect(await openRecord(keyring.byVersion[2]!, record, sealed), {'s': 1});
      expect(w.relay.rows, isEmpty);

      // the new device registered its own attested device wrap (addendum step 8)
      final enrolled = w.keys.wraps.last;
      expect(enrolled.kind, 'device');
      expect(enrolled.keyV, 2);
      expect(enrolled.publicKey, isNot(fresh.qr.split('&key=')[1]));
      expect(
        await verifyDeviceAttestation(
          w.dataKey,
          DeviceAttestationInput(
            userId: w.userId,
            wrapId: enrolled.id,
            publicKey: fromBase64Url(enrolled.publicKey!),
          ),
          fromBase64Url(enrolled.attestation!),
        ),
        isTrue,
      );
      // the DK the new device opened is zeroed once it enrolled
      expect(openedPairing, hasLength(1));
      expect(zeroed(openedPairing[0]), isTrue);
      // every poll waits 1.5 s
      expect(w.clock.sleeps, isNotEmpty);
      expect(w.clock.sleeps.toSet(), {pairingPoll});
    });

    test('the approver pins the commitment from ?code=', () async {
      final w = await world();
      final fresh = await startPairing(w.options, clock: w.clock);
      final approver = await findPairing(w.options, code: fresh.code, clock: w.clock);
      // the server now shows another commitment and a revealed key that matches it
      final evil = await generateDeviceKeyPair();
      final evilKey = toBase64Url(evil.publicKey);
      final evilCommitment = toBase64Url(await pairingCommitment(evil.publicKey));
      w.relay.onGet = (body, _) {
        body['commitment'] = evilCommitment;
        if (body['publicKey'] != null) body['publicKey'] = evilKey;
      };
      final approverNumber = approver.number();
      quiet(fresh.number());
      expect(await pairingErrorOf(approverNumber), 'tampered');
      // number() never resolved: approve() refuses and sends nothing
      await expectLater(
        approver.approve(),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'approve before number')),
      );
      expect(w.relay.log.any((l) => l.endsWith('/seal')), isFalse);
      fresh.cancel();
    });

    test('the new device pins the first approverKey', () async {
      final w = await world();
      final fresh = await startPairing(w.options, clock: w.clock);
      final approver = await findPairing(w.options, code: fresh.code, clock: w.clock);
      final evil = toBase64Url((await generateDeviceKeyPair()).publicKey);
      var seen = 0;
      w.relay.onGet = (body, _) {
        if (body['approverKey'] != null && ++seen > 1) body['approverKey'] = evil;
      };
      await fresh.number();
      expect(await pairingErrorOf(fresh.finish()), 'tampered');
      final reveals = w.relay.log.where((l) => l.endsWith('/reveal'));
      // only the pinned key was answered with a reveal; none followed the other key
      expect(reveals, hasLength(1));
      expect(w.relay.log.any((l) => l.endsWith('/pickup')), isFalse);
      approver.cancel();
    });

    test('a later approverKey seen before the reveal is tampered and no reveal is sent', () async {
      final w = await world();
      final evil = toBase64Url((await generateDeviceKeyPair()).publicKey);
      // the reveal fails once (409 not_ready from the server); the retry follows the next poll
      var first = true;
      w.relay.intercept = (method, path) {
        if (path.endsWith('/reveal') && first) {
          first = false;
          w.relay.onGet = (body, _) {
            if (body['approverKey'] != null) body['approverKey'] = evil;
          };
          return (409, {'code': 'not_ready'});
        }
        return null;
      };
      final again = await startPairing(w.options, clock: w.clock);
      final other = await findPairing(w.options, code: again.code, clock: w.clock);
      expect(await pairingErrorOf(again.number()), 'tampered');
      // the one reveal that was sent is the intercepted one, which the relay never saw
      expect(w.relay.log.where((l) => l.endsWith('${again.id}/reveal')), hasLength(1));
      expect(w.relay.rows[again.id]!.publicKey, isNull);
      other.cancel();
    });

    test('a QR whose key is not the revealed key is tampered', () async {
      final w = await world();
      final fresh = await startPairing(w.options, clock: w.clock);
      final other = toBase64Url((await generateDeviceKeyPair()).publicKey);
      final qr = 'wambito://pair?id=${fresh.id}&key=$other';
      expect(await pairingErrorOf(findPairing(w.options, qr: qr, clock: w.clock)), 'tampered');
      // nothing was posted for a request the QR does not match
      expect(w.relay.rows[fresh.id]!.approverKey, isNull);

      // the real QR works, and the approver still checks the revealed key against it
      final approver = await findPairing(w.options, qr: fresh.qr, clock: w.clock);
      w.relay.onGet = (body, _) {
        if (body['publicKey'] != null) body['publicKey'] = other;
      };
      quiet(fresh.number());
      expect(await pairingErrorOf(approver.number()), 'tampered');
      fresh.cancel();
    });

    test('a sealed blob from another ephemeral key does not open', () async {
      final w = await world();
      final fresh = await startPairing(w.options, clock: w.clock);
      final approver = await findPairing(w.options, code: fresh.code, clock: w.clock);
      await Future.wait([fresh.number(), approver.number()]);
      final newKey = fromBase64Url(w.relay.rows[fresh.id]!.publicKey!);
      // the server hands over the right DK, sealed under a key that is not the pinned approver key
      final forged = toBase64Url(
        await sealToDevice(
          newKey,
          WrapContext(kind: WrapKind.device, userId: w.userId, keyV: 2),
          w.dataKey,
        ),
      );
      w.relay.onPickup = (body) => body['sealed'] = forged;
      final finished = fresh.finish();
      quiet(approver.approve());
      expect(await pairingErrorOf(finished), 'tampered');
      expect(w.keys.wraps.where((x) => x.kind == 'device'), hasLength(1));
    });

    test('a code is normalised', () async {
      final w = await world();
      final fresh = await startPairing(w.options, clock: w.clock);
      w.relay.rows[fresh.id]!.code = 'ABCDEFGH';
      final approver = await findPairing(w.options, code: ' abcd efgh ', clock: w.clock);
      expect(w.relay.log, contains('GET /api/v2/pairing?code=ABCDEFGH'));
      approver.cancel();

      // a code that cannot be one is refused before any request; so is an unknown code
      final before = w.relay.log.length;
      expect(
        await pairingErrorOf(findPairing(w.options, code: 'ABCD-EFGU', clock: w.clock)),
        'bad_code',
      );
      expect(await pairingErrorOf(findPairing(w.options, code: 'ABC', clock: w.clock)), 'bad_code');
      expect(w.relay.log.length, before);
      expect(
        await pairingErrorOf(findPairing(w.options, code: 'ZZZZZZZZ', clock: w.clock)),
        'bad_code',
      );

      // a QR that is not exactly `wambito://pair?id=<id>&key=<key>` is refused too
      final key = fresh.qr.split('&key=')[1];
      for (final qr in [
        'https://wambito.com/pair?id=${fresh.id}&key=$key',
        'wambito://pair?id=${fresh.id}',
        'wambito://pair?key=$key&id=${fresh.id}',
        'wambito://pair?id=${fresh.id}&key=${key.substring(0, 40)}',
        'wambito://pair?id=not-an-id&key=$key',
        '${fresh.qr}&x=1',
      ]) {
        expect(await pairingErrorOf(findPairing(w.options, qr: qr, clock: w.clock)), 'bad_code');
      }
      fresh.cancel();
    });

    test('404 or expiresAt passing is expired on both sides', () async {
      // the row goes (404)
      final w = await world();
      final fresh = await startPairing(w.options, clock: w.clock);
      final approver = await findPairing(w.options, code: fresh.code, clock: w.clock);
      w.relay.rows.clear();
      expect(await pairingErrorOf(fresh.number()), 'expired');
      expect(await pairingErrorOf(fresh.finish()), 'expired');
      expect(await pairingErrorOf(approver.number()), 'expired');
      await expectLater(approver.approve(), throwsA(isA<StateError>()));

      // the clock passes expiresAt while the server still answers: both stop by themselves
      final v = await world();
      v.relay.ignoreExpiry = true;
      final lonely = await startPairing(v.options, clock: v.clock);
      expect(await pairingErrorOf(lonely.number()), 'expired');
      final polls = v.relay.log.where((l) => l == 'GET /api/v2/pairing/${lonely.id}').length;
      expect(polls, greaterThan(100));
      expect(polls, lessThanOrEqualTo(ttl.inMilliseconds ~/ 1500 + 1));

      final late = await startPairing(v.options, clock: v.clock);
      final waiting = await findPairing(v.options, code: late.code, clock: v.clock);
      // the new device never reveals: the approver waits until expiresAt
      expect(await pairingErrorOf(waiting.number()), 'expired');
      late.cancel();
    });

    test(
      "approve() takes DK from this phone's device wrap, seals with keyV, and zeroes DK",
      () async {
        final w = await world();
        final fresh = await startPairing(w.options, clock: w.clock);
        final approver = await findPairing(w.options, code: fresh.code, clock: w.clock);
        await Future.wait([fresh.number(), approver.number()]);
        final pinned = w.relay.rows[fresh.id]!.approverKey;
        final sealedAt = <String>[];
        w.relay.onGet = (body, _) {
          if (body['sealed'] != null) sealedAt.add(body['sealed']! as String);
        };
        await Future.wait<Object?>([fresh.finish(), approver.approve()]);

        // the approver's seal (the new device's own wrap is sealed inside enrollDevice)
        expect(seals, hasLength(1));
        final seal = seals[0];
        expect(seal.ctx.kind, WrapKind.device);
        expect(seal.ctx.userId, w.userId);
        expect(seal.ctx.keyV, 2);
        expect(seal.ephemeral, isTrue);
        // the sealed blob starts with the approver key the server stored
        expect(toBase64Url(fromBase64Url(sealedAt[0]).sublist(0, 32)), pinned);
        // DK came from this phone's device wrap and is zeroed after the seal
        expect(openedDevice, hasLength(1));
        expect(identical(openedDevice[0], seal.dataKey), isTrue);
        expect(zeroed(openedDevice[0]), isTrue);
        expect(w.relay.log, contains('POST /api/v2/pairing/${fresh.id}/seal'));
      },
    );

    test('cancel() stops polling', () async {
      final w = await world();
      w.relay.ignoreExpiry = true;
      final fresh = await startPairing(w.options, clock: w.clock);
      final number = fresh.number();
      await ticks(5);
      fresh.cancel();
      expect(await pairingErrorOf(number), 'cancelled');
      // a request already on its way when it was cancelled still lands (Dio's call is not aborted);
      // its answer is never acted on, and nothing is sent after it
      await ticks(5);
      final after = w.relay.log.length;
      await ticks(20);
      expect(w.relay.log.length, after);
      expect(await pairingErrorOf(fresh.finish()), 'cancelled');

      final again = await startPairing(w.options, clock: w.clock);
      final approver = await findPairing(w.options, code: again.code, clock: w.clock);
      final waiting = approver.number();
      await ticks(5);
      approver.cancel();
      expect(await pairingErrorOf(waiting), 'cancelled');
      await ticks(5);
      final then = w.relay.log.length;
      await ticks(20);
      expect(w.relay.log.length, then);
      await expectLater(approver.approve(), throwsA(isA<StateError>()));
      again.cancel();
    });

    test('approve() before number() rejects and no seal request is made', () async {
      final w = await world();
      final fresh = await startPairing(w.options, clock: w.clock);
      final approver = await findPairing(w.options, code: fresh.code, clock: w.clock);
      // the new device reveals; the approver's number is ready but was never asked for
      await fresh.number();
      await expectLater(
        approver.approve(),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'approve before number')),
      );
      await expectLater(approver.approve(), throwsA(isNot(isA<PairingError>())));
      await ticks(10);
      expect(w.relay.log.any((l) => l.endsWith('/seal')), isFalse);
      expect(w.keys.calls.any((c) => c.method == 'GET' && c.path == '/api/v2/keys'), isFalse);
      expect(openedDevice, isEmpty);

      // once the number was shown, the same object approves
      await approver.number();
      await Future.wait<Object?>([fresh.finish(), approver.approve()]);
      expect(w.relay.rows, isEmpty);
    });

    test(
      'a relay whose expiresAt is far in the future still ends both sides after 10 minutes',
      () async {
        final w = await world();
        w.relay.ttlSays = const Duration(days: 365);
        final start = w.clock.t;
        final fresh = await startPairing(w.options, clock: w.clock);
        expect(await pairingErrorOf(fresh.number()), 'expired');
        expect(w.clock.t.difference(start), greaterThanOrEqualTo(ttl));
        expect(w.clock.t.difference(start), lessThan(ttl + pairingPoll * 2));

        final late = await startPairing(w.options, clock: w.clock);
        final lookup = w.clock.t;
        final approver = await findPairing(w.options, code: late.code, clock: w.clock);
        // the new device never reveals: the approver stops 10 minutes after its lookup
        expect(await pairingErrorOf(approver.number()), 'expired');
        expect(w.clock.t.difference(lookup), greaterThanOrEqualTo(ttl));
        expect(w.clock.t.difference(lookup), lessThan(ttl + pairingPoll * 2));
        late.cancel();
      },
    );
  });

  test('normalizePairingCode forgives case, dashes, spaces and look-alikes', () {
    expect(normalizePairingCode(' abcd-efgh '), 'ABCDEFGH');
    expect(normalizePairingCode('ILO1'), '1101');
    expect(normalizePairingCode('olil'), '0111');
  });
}
