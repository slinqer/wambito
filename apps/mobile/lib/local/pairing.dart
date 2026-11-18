import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../crypto/crypto.dart' as crypto;
import '../crypto/crypto.dart'
    show DeviceKeyPair, WrapContext, WrapKind, fromBase64Url, toBase64Url;
import 'keys.dart';
import 'relay.dart';
import 'relay_clock.dart';

export 'relay_clock.dart' show PairingClock;

/// Pairing a new phone from an unlocked device: the twin of apps/web/app/local/pairing.ts (stage
/// 1b spec section 1, steps 1-8). The server only relays: the new device's commitment to its
/// ephemeral key `N`, the approver's ephemeral key `A`, the revealed `N.pub` and DK sealed from `A`
/// to `N`. Pinning (`packages/crypto/AGENTS.md`): the approving device keeps the `commitment` it
/// read before posting `A.pub` and never takes it again; the new device keeps the first
/// `approverKey` it sees and aborts if a later poll shows another. Both show
/// `pairingNumber(N.pub, A.pub)`, QR or not. Both poll every 1.5 s and stop at `expiresAt`
/// (`expired`) or on `cancel()` (`cancelled`). DK and the opened DK are zeroed in a `finally`; the
/// ephemeral private keys are zeroed on every way out. Nothing secret is ever logged: no key, no
/// code, no number.

/// Why a pairing ended. Twin of `PairingErrorCode`: `expired` (404 from the relay, or `expiresAt`
/// passed on this device's clock), `tampered` (a value the server relayed does not match what this
/// device pinned or computed), `bad_code` (a typed code that cannot be one or finds nothing, or a
/// QR not `wambito://pair?id=...&key=...`), `offline`, `server`, `cancelled`.
class PairingError implements Exception {
  const PairingError(this.code);

  final String code;

  @override
  String toString() => 'PairingError($code)';
}

/// A 404: the relay no longer has the request (picked up, or expired there).
class _Gone extends PairingError {
  const _Gone() : super('expired');
}

const pairingPoll = Duration(milliseconds: 1500);

/// A request lives 10 minutes (spec 7.3): the most either device waits, whatever the relay says.
const pairingTtl = Duration(minutes: 10);

/// Test seams of the web's mocks of `openFromPairing` and `sealToDevice` (to check what the
/// approver seals and that the opened DK is zeroed). Production code never changes them; the seal
/// is also the web sign-in approver's (`signin_approval.dart`, ruling 15), so it is not
/// `@visibleForTesting`.
@visibleForTesting
Future<Uint8List> Function(
  Uint8List privateKey,
  WrapContext ctx,
  Uint8List sealed,
  Uint8List approverKey,
)
pairingOpenFromPairing = crypto.openFromPairing;
Future<Uint8List> Function(
  Uint8List publicKey,
  WrapContext ctx,
  Uint8List dataKey, {
  DeviceKeyPair? ephemeral,
})
pairingSealToDevice = crypto.sealToDevice;

/// A request on the new phone, as the screen and the gate see it.
class NewDevicePairing {
  NewDevicePairing._({
    required this.id,
    required this.code,
    required this.qr,
    required this.expiresAt,
    required this._number,
    required this._finish,
    required this._cancel,
  });

  final String id;

  /// 8 Crockford characters, to type on the approving device.
  final String code;

  /// `wambito://pair?id=<id>&key=<base64url N.pub>`
  final String qr;
  final String expiresAt;
  final Future<String> Function() _number;
  final Future<LocalKeys> Function() _finish;
  final void Function() _cancel;

  /// The 6 digits, once this device revealed its key (after it pinned the approver key).
  Future<String> number() => _number();

  /// Picks up the sealed DK, opens it and enrolls this phone with an attested device wrap.
  Future<LocalKeys> finish() => _finish();

  void cancel() => _cancel();
}

/// The approving device's side of a pairing.
class ApproverPairing {
  ApproverPairing._({required this._number, required this._approve, required this._cancel});

  final Future<String> Function() _number;
  final Future<void> Function() _approve;
  final void Function() _cancel;

  /// The 6 digits, once the new device revealed a key that matches the pinned commitment.
  Future<String> number() => _number();

  /// Throws a plain [StateError] ('approve before number'), sending nothing, unless [number] has
  /// resolved on this object. The person confirmed the numbers match: seals DK (from this phone's
  /// device wrap) to the revealed key from `A`, then waits for the new device to pick it up (the
  /// relay answers 404).
  Future<void> approve() => _approve();

  void cancel() => _cancel();
}

class _State {
  const _State({
    required this.commitment,
    required this.approverKey,
    required this.publicKey,
    required this.sealed,
    required this.expiresAt,
  });

  final String commitment;
  final String? approverKey;
  final String? publicKey;
  final String? sealed;
  final String expiresAt;
}

final _qr = RegExp(
  r'^wambito://pair\?id=([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})&key=([A-Za-z0-9_-]{43})$',
);

/// The server's reading of a typed code: upper case, no dashes or spaces, I/L as 1, O as 0.
String normalizePairingCode(String input) => input
    .toUpperCase()
    .replaceAll(RegExp(r'[-\s]'), '')
    .replaceAll(RegExp('[IL]'), '1')
    .replaceAll('O', '0');

void _zero(Uint8List key) => key.fillRange(0, key.length, 0);

/// 32 bytes from base64url, or `tampered` for anything else the server relays.
Uint8List _key32(String text) => key32(text, onBad: () => const PairingError('tampered'));

_State _stateOf(Map<String, Object?> json) {
  final commitment = json['commitment'];
  final expiresAt = json['expiresAt'];
  if (commitment is! String || expiresAt is! String) throw const PairingError('server');
  final approverKey = json['approverKey'];
  final publicKey = json['publicKey'];
  final sealed = json['sealed'];
  if ((approverKey != null && approverKey is! String) ||
      (publicKey != null && publicKey is! String) ||
      (sealed != null && sealed is! String)) {
    throw const PairingError('server');
  }
  return _State(
    commitment: commitment,
    approverKey: approverKey as String?,
    publicKey: publicKey as String?,
    sealed: sealed as String?,
    expiresAt: expiresAt,
  );
}

/// The relay for one pairing (`relay.dart`): its errors are [PairingError]s, a 404 [_Gone]; the
/// deadline is the relay's `expiresAt`, capped at 10 minutes from when this device started.
RelayClient _relay(KeysOptions options, PairingClock clock) =>
    RelayClient(options, clock, ttl: pairingTtl, error: PairingError.new, gone: _Gone.new);

/// Polls request [id], each answer read as its [_State].
Future<T> _poll<T>(RelayClient net, String id, Future<T?> Function(_State state) step) =>
    net.poll('/v2/pairing/$id', (body) => step(_stateOf(body)), every: pairingPoll);

/// A one-shot promise whose rejection never goes unhandled (callers still see it).
Completer<T> _deferred<T>() {
  final completer = Completer<T>();
  completer.future.ignore();
  return completer;
}

/// The new device (steps 1, 4, 7, 8): makes `N`, posts its commitment and returns the code and the
/// QR. Polling starts with the first [NewDevicePairing.number] or [NewDevicePairing.finish].
Future<NewDevicePairing> startPairing(KeysOptions options, {PairingClock? clock}) async {
  final time = clock ?? const RealPairingClock();
  final net = _relay(options, time);
  final pair = await crypto.generateDeviceKeyPair();
  final newKey = toBase64Url(pair.publicKey);
  final Map<String, Object?> started;
  try {
    final commitment = toBase64Url(await crypto.pairingCommitment(pair.publicKey));
    started = (await net.post('/v2/pairing', {'commitment': commitment}))!;
  } on Object {
    _zero(pair.privateKey);
    rethrow;
  }
  final id = started['id'];
  final code = started['code'];
  final expiresAt = started['expiresAt'];
  if (id is! String || code is! String || expiresAt is! String) {
    _zero(pair.privateKey);
    throw const PairingError('server');
  }
  net.setDeadline(expiresAt);

  final number = _deferred<String>();
  final ready = _deferred<Uint8List>();
  var running = false;
  Future<LocalKeys>? finishing;

  Future<void> run() async {
    String? pinned;
    var revealed = false;
    try {
      await _poll<bool>(net, id, (state) async {
        final approver = state.approverKey;
        if (approver == null) {
          if (pinned != null) throw const PairingError('tampered');
          return null;
        }
        // the first approver key seen is the one: any other later is the server's
        if (pinned == null) {
          _key32(approver);
          pinned = approver;
        } else if (approver != pinned) {
          throw const PairingError('tampered');
        }
        if (!revealed) {
          if (state.publicKey != null) {
            // our own reveal whose answer was lost, or someone else's key
            if (state.publicKey != newKey) throw const PairingError('tampered');
          } else {
            // 409 `not_ready`/`already_set`: look again at the next poll
            final sent = await net.post(
              '/v2/pairing/$id/reveal',
              {'publicKey': newKey},
              conflict: relayRetry,
              json: false,
            );
            if (sent == null) return null;
          }
          revealed = true;
          number.complete(await crypto.pairingNumber(pair.publicKey, _key32(pinned!)));
        } else if (state.publicKey != null && state.publicKey != newKey) {
          throw const PairingError('tampered');
        }
        return state.sealed != null ? true : null;
      });
      ready.complete(_key32(pinned!));
    } on Object catch (error) {
      if (!number.isCompleted) number.completeError(error);
      if (!ready.isCompleted) ready.completeError(error);
      _zero(pair.privateKey);
    }
  }

  void ensureRunning() {
    if (running) return;
    running = true;
    unawaited(run());
  }

  Future<LocalKeys> finish() async {
    ensureRunning();
    final approverKey = await ready.future;
    try {
      final picked = (await net.post('/v2/pairing/$id/pickup', null))!;
      final pickedSealed = picked['sealed'];
      final pickedKeyV = picked['keyV'];
      if (pickedSealed is! String || pickedKeyV is! int) throw const PairingError('server');
      final Uint8List sealed;
      try {
        sealed = fromBase64Url(pickedSealed);
      } on Object {
        throw const PairingError('tampered');
      }
      final Uint8List dataKey;
      try {
        dataKey = await pairingOpenFromPairing(
          pair.privateKey,
          WrapContext(kind: WrapKind.device, userId: options.userId, keyV: pickedKeyV),
          sealed,
          approverKey,
        );
      } on Object {
        throw const PairingError('tampered');
      }
      try {
        net.check();
        return await enrollDevice(options, dataKey, pickedKeyV);
      } finally {
        _zero(dataKey);
      }
    } finally {
      _zero(pair.privateKey);
    }
  }

  return NewDevicePairing._(
    id: id,
    code: code,
    qr: 'wambito://pair?id=$id&key=$newKey',
    expiresAt: expiresAt,
    number: () {
      ensureRunning();
      return number.future;
    },
    finish: () => finishing ??= finish(),
    cancel: () {
      net.cancelled = true;
      const error = PairingError('cancelled');
      if (!number.isCompleted) number.completeError(error);
      if (!ready.isCompleted) ready.completeError(error);
      _zero(pair.privateKey);
    },
  );
}

/// The approving device (steps 2, 3, 5, 6): finds the request by its typed [code] or its [qr] (one
/// of them), pins the commitment (checked against the QR's key for a scan), makes `A` and posts
/// `A.pub`. `bad_code` for a code that cannot be one or finds nothing (404) and for a QR not
/// exactly `wambito://pair?id=<id>&key=<key>`.
Future<ApproverPairing> findPairing(
  KeysOptions options, {
  String? code,
  String? qr,
  PairingClock? clock,
}) async {
  if ((code == null) == (qr == null)) throw ArgumentError('exactly one of code and qr');
  final time = clock ?? const RealPairingClock();
  final net = _relay(options, time);

  final String id;
  final Uint8List commitment;
  Uint8List? qrKey;
  if (qr != null) {
    final match = _qr.firstMatch(qr);
    if (match == null) throw const PairingError('bad_code');
    id = match.group(1)!;
    try {
      qrKey = fromBase64Url(match.group(2)!);
    } on Object {
      throw const PairingError('bad_code');
    }
    if (qrKey.length != 32) throw const PairingError('bad_code');
    final state = _stateOf(await net.get('/v2/pairing/$id'));
    commitment = await crypto.pairingCommitment(qrKey);
    // the QR authenticates the new device: the relay's commitment must be its key's
    if (state.commitment != toBase64Url(commitment)) throw const PairingError('tampered');
    if (state.approverKey != null) throw const PairingError('tampered');
    net.setDeadline(state.expiresAt);
  } else {
    final typed = normalizePairingCode(code!);
    if (!relayCodePattern.hasMatch(typed)) throw const PairingError('bad_code');
    final Map<String, Object?> found;
    try {
      found = await net.get('/v2/pairing?code=${Uri.encodeQueryComponent(typed)}');
    } on PairingError catch (error) {
      if (error.code == 'expired') throw const PairingError('bad_code');
      rethrow;
    }
    final foundId = found['id'];
    final foundCommitment = found['commitment'];
    final foundExpires = found['expiresAt'];
    if (foundId is! String || foundCommitment is! String || foundExpires is! String) {
      throw const PairingError('server');
    }
    id = foundId;
    // pinned now, before A.pub goes out; never read again
    commitment = _key32(foundCommitment);
    net.setDeadline(foundExpires);
  }

  final pair = await crypto.generateDeviceKeyPair();
  final approverKey = toBase64Url(pair.publicKey);
  try {
    // a second approver key is not ours: someone else answered this request
    await net.post(
      '/v2/pairing/$id/approver',
      {'publicKey': approverKey},
      conflict: 'tampered',
      json: false,
    );
  } on Object {
    _zero(pair.privateKey);
    rethrow;
  }

  Future<({String number, Uint8List newKey})>? numbering;
  Future<void>? approving;
  // Set once `number()` resolved on this object: the person has been shown the number.
  var shown = false;

  Future<({String number, Uint8List newKey})> reveal() => numbering ??= (() async {
    try {
      final newKey = await _poll<Uint8List>(net, id, (state) async {
        if (state.approverKey != approverKey) throw const PairingError('tampered');
        final revealed = state.publicKey;
        if (revealed == null) return null;
        final key = _key32(revealed);
        if (!sameBytes(await crypto.pairingCommitment(key), commitment)) {
          throw const PairingError('tampered');
        }
        if (qrKey != null && !sameBytes(key, qrKey)) throw const PairingError('tampered');
        return key;
      });
      return (number: await crypto.pairingNumber(newKey, pair.publicKey), newKey: newKey);
    } on Object {
      _zero(pair.privateKey);
      rethrow;
    }
  })();

  Future<void> approve() async {
    final (:newKey, number: _) = await reveal();
    try {
      net.check();
      await withDataKey(options, (dataKey, keyV) async {
        final sealed = await pairingSealToDevice(
          newKey,
          WrapContext(kind: WrapKind.device, userId: options.userId, keyV: keyV),
          dataKey,
          ephemeral: pair,
        );
        await net.post('/v2/pairing/$id/seal', {
          'sealed': toBase64Url(sealed),
          'keyV': keyV,
        }, json: false);
      });
    } finally {
      _zero(pair.privateKey);
    }
    // done when the new device picked it up: the relay forgets the request (404)
    try {
      await _poll<bool>(net, id, (_) async => null);
    } on _Gone {
      return;
    }
  }

  return ApproverPairing._(
    number: () async {
      final revealed = await reveal();
      shown = true;
      return revealed.number;
    },
    approve: () {
      // the number comparison is the only check of a relayed `N` after a typed code: never seal
      // before the person could compare it
      if (!shown) return Future.error(StateError('approve before number'));
      return approving ??= approve();
    },
    cancel: () {
      net.cancelled = true;
      _zero(pair.privateKey);
    },
  );
}
