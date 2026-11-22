import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../crypto/crypto.dart' as crypto;
import '../crypto/crypto.dart'
    show DeviceKeyPair, WrapContext, WrapKind, fromBase64Url, toBase64Url;
import 'keys.dart';
import 'pairing.dart' show normalizePairingCode, sealForApprover;
import 'relay.dart';
import 'relay_clock.dart';

/// This phone approving a web sign-in (phone-first spec 8.1, steps 2-6): the phone's half of
/// apps/web/app/local/signin.ts. The browser holds `N` and shows the QR
/// `wambito://signin?id=<id>&key=<base64url N.pub>` and an 8-character code. The phone finds the
/// request by either (`GET /v2/signin/{id}` or `GET /v2/signin?code=`, with its session), pins the
/// `commitment` (`SHA-256("wambito/v1/pairing-commit" || N.pub)`, `pairingCommitment`; after a scan
/// it must be the QR key's), shows the browser's `label`, and only on "Approve" posts its ephemeral
/// `A.pub` (`/approver`, once: a 409 is someone else's, `tampered`). It then polls until the
/// browser revealed `N.pub`, checks it against the pinned commitment and the QR's key, shows
/// `pairingNumber(N.pub, A.pub)` only after a typed code, and seals DK from `A` to `N` under
/// `WrapContext(device, userId, keyV)` exactly as pairing does (ruling 15; the browser opens it with
/// `openFromPairing`), then waits for the browser's pickup (the relay's 404).
///
/// The 2 minutes (spec 8.1) run on this phone's clock from when it read the request, never on the
/// server's `expiresAt` (another clock: one ahead would end every request at once; the web's own
/// trap); the server's end comes back as a 404. A 429 waits for its `retry-after`, else backs off,
/// and never asks again at once. `A`'s private key and DK are zeroed on every way out; nothing
/// secret is ever logged: no key, no code, no number.

/// Why an approval ended: `bad_code` (a code that cannot be one or finds nothing, or a QR not
/// exactly `wambito://signin?id=<id>&key=<key>`), `expired` (a 404, or the 2 minutes passed on
/// this phone's clock), `tampered` (a relayed value that does not match what this phone pinned, a
/// second approver, a 422), `offline`, `server`, `cancelled` (after [SigninApproval.cancel]), and
/// `unconfirmed` (the seal was posted but its pickup could not be seen).
class SigninError implements Exception {
  const SigninError(this.code);

  final String code;

  @override
  String toString() => 'SigninError($code)';
}

/// A 404: the relay no longer has the request (picked up, or expired there).
class _Gone extends SigninError {
  const _Gone() : super('expired');
}

const signinPoll = Duration(milliseconds: 1500);

/// A request lives 2 minutes (spec 8.1): the most this phone waits from its read, whatever the
/// relay says.
const signinTtl = Duration(minutes: 2);

/// Test seam of the ephemeral key `A` (to check it is zeroed). Production code never changes it.
@visibleForTesting
Future<DeviceKeyPair> Function() signinGenerateDeviceKeyPair = crypto.generateDeviceKeyPair;

final _qr = RegExp(
  r'^wambito://signin\?id=([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})&key=([A-Za-z0-9_-]{43})$',
);

/// Whether [text] is exactly a web sign-in's QR, `wambito://signin?id=<uuid>&key=<base64url 32 B>`.
bool isSigninQr(String text) => _qr.hasMatch(text);

const _tampered = SigninError('tampered');

Uint8List _key32(String text) => key32(text, onBad: () => _tampered);

void _zero(Uint8List key) => key.fillRange(0, key.length, 0);

/// A web sign-in request this phone found, as the approval screen sees it.
class SigninApproval {
  SigninApproval._({
    required this.label,
    required this.expiresAt,
    required this.typed,
    required this.fromLink,
    required this._approve,
    required this._seal,
    required this._cancel,
  });

  /// What the browser calls itself ("Firefox on Mac"), as the server relays it.
  final String label;

  /// The server's end, on its clock: shown at most, never counted on.
  final String expiresAt;

  /// Found by a typed code (no QR key): the number must be compared before the seal.
  final bool typed;

  /// A QR that came in a link (`wambito://signin?…` opened by any app or page), not from the
  /// in-app scanner: unauthenticated intent (ruling P18). Its key is still checked, and the number
  /// must be compared before the seal, as after a typed code.
  final bool fromLink;

  /// Whether the 6 digits must be compared before [seal]: a typed code or a link.
  bool get comparesNumber => typed || fromLink;

  final Future<String?> Function() _approve;
  final Future<void> Function() _seal;
  final void Function() _cancel;

  /// "Approve": posts `A.pub`, waits for the browser's key and checks it. The 6 digits when
  /// [comparesNumber]; null after a QR from the in-app scanner (its key, read off the browser's
  /// screen, already authenticates the browser).
  Future<String?> approve() => _approve();

  /// Seals the data key to the browser and waits for its pickup. When [comparesNumber], a
  /// [StateError] that sends nothing until [approve] returned (the person compared the number);
  /// after a scanned QR, it approves first when that was not done. Once the seal was posted, a
  /// pickup that cannot be seen (offline, the 2 minutes) is `unconfirmed`, not a failure.
  Future<void> seal() => _seal();

  /// Stops the request and zeroes `A`. Nothing more is sent.
  void cancel() => _cancel();
}

/// Finds the request by its typed [code] or its scanned [qr] (exactly one) and pins its commitment
/// (a QR's key must hash to it). `bad_code` for a code that cannot be one or finds nothing (404) and
/// for a QR not exactly `wambito://signin?id=<uuid>&key=<base64url 32 bytes>`. Nothing is posted.
/// [fromLink]: the [qr] came in a link, not from the in-app scanner ([SigninApproval.fromLink]).
Future<SigninApproval> findSigninRequest(
  KeysOptions options, {
  String? code,
  String? qr,
  bool fromLink = false,
  PairingClock? clock,
}) async {
  if ((code == null) == (qr == null)) throw ArgumentError('exactly one of code and qr');
  final net = RelayClient(
    options,
    clock ?? const RealPairingClock(),
    ttl: signinTtl,
    error: SigninError.new,
    gone: _Gone.new,
    backOffTooMany: true,
  );

  final String id;
  final Uint8List commitment;
  final Map<String, Object?> found;
  Uint8List? qrKey;
  if (qr != null) {
    final match = _qr.firstMatch(qr);
    if (match == null) throw const SigninError('bad_code');
    id = match.group(1)!;
    try {
      qrKey = fromBase64Url(match.group(2)!);
    } on Object {
      throw const SigninError('bad_code');
    }
    if (qrKey.length != 32) throw const SigninError('bad_code');
    found = await net.get('/v2/signin/$id');
    commitment = await crypto.pairingCommitment(qrKey);
    // the QR authenticates the browser: the relay's commitment must be its key's
    if (found['commitment'] != toBase64Url(commitment)) throw _tampered;
    // a browser key before anyone approved is not one this phone answered
    if (found['publicKey'] != null) throw _tampered;
  } else {
    final typed = normalizePairingCode(code!);
    if (!relayCodePattern.hasMatch(typed)) throw const SigninError('bad_code');
    try {
      found = await net.get('/v2/signin?code=${Uri.encodeQueryComponent(typed)}');
    } on SigninError catch (error) {
      if (error.code == 'expired') throw const SigninError('bad_code');
      rethrow;
    }
    final foundId = found['id'];
    final foundCommitment = found['commitment'];
    if (foundId is! String || foundCommitment is! String) throw const SigninError('server');
    id = foundId;
    // pinned now, before A.pub goes out; never read again
    commitment = _key32(foundCommitment);
  }
  final label = found['label'];
  final expiresAt = found['expiresAt'];
  if (label is! String || expiresAt is! String) throw const SigninError('server');
  // the 2 minutes count from this read, on this phone's clock
  net.restart();

  final pair = await signinGenerateDeviceKeyPair();
  final approverKey = toBase64Url(pair.publicKey);
  final isTyped = qrKey == null;
  // a typed code or a link: the number is the person's check before the seal
  final compares = isTyped || fromLink;
  Future<Uint8List>? approving;
  Uint8List? browserKey;

  void forget() {
    net.cancelled = true;
    _zero(pair.privateKey);
  }

  Future<Uint8List> approve() => approving ??= (() async {
    try {
      // a second approver key is not ours: someone else answered this request
      await net.post(
        '/v2/signin/$id/approver',
        {'publicKey': approverKey},
        conflict: 'tampered',
        json: false,
      );
      return await net.poll<Uint8List>('/v2/signin/$id', (state) async {
        if (state['commitment'] != toBase64Url(commitment)) throw _tampered;
        final revealed = state['publicKey'];
        if (revealed == null) return null;
        if (revealed is! String) throw _tampered;
        final key = _key32(revealed);
        if (!sameBytes(await crypto.pairingCommitment(key), commitment)) throw _tampered;
        if (qrKey != null && !sameBytes(key, qrKey)) throw _tampered;
        return key;
      }, every: signinPoll);
    } on Object {
      _zero(pair.privateKey);
      rethrow;
    }
  })();

  Future<void> seal(Uint8List newKey) async {
    try {
      net.check();
      await withDataKey(options, (dataKey, keyV) async {
        final sealed = await sealForApprover(
          newKey,
          WrapContext(kind: WrapKind.device, userId: options.userId, keyV: keyV),
          dataKey,
          ephemeral: pair,
        );
        net.check();
        await net.post('/v2/signin/$id/seal', {
          'sealed': toBase64Url(sealed),
          'keyV': keyV,
        }, json: false);
      });
    } finally {
      _zero(pair.privateKey);
    }
    // done when the browser picked it up: the relay forgets the request (404). The seal is out:
    // anything else from here is a pickup this phone could not see, not a failure.
    try {
      await net.poll<bool>('/v2/signin/$id', (_) async => null, every: signinPoll);
    } on _Gone {
      return;
    } on SigninError catch (error) {
      if (error.code == 'cancelled') rethrow;
      throw const SigninError('unconfirmed');
    } on KeysError {
      throw const SigninError('unconfirmed');
    }
  }

  Future<void>? sealing;

  return SigninApproval._(
    label: label,
    expiresAt: expiresAt,
    typed: isTyped,
    fromLink: fromLink && !isTyped,
    approve: () async {
      final key = await approve();
      final number = compares ? await crypto.pairingNumber(key, pair.publicKey) : null;
      // set once the number is in hand: from here the person can compare it
      browserKey = key;
      return number;
    },
    seal: () {
      // after a typed code the number is the only check of a relayed `N`, and after a link the
      // only check that the browser is the person's: never seal before they could compare it
      if (compares && browserKey == null) return Future.error(StateError('seal before approve'));
      return sealing ??= (() async => seal(browserKey ?? await approve()))();
    },
    cancel: forget,
  );
}
