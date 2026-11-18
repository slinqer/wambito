import 'dart:convert';
import 'dart:typed_data';

import '../crypto/crypto.dart' show fromBase64Url;
import 'keys.dart';
import 'relay_clock.dart';

/// What the two phone relays share (`pairing.dart`, a new device paired from an unlocked one;
/// `signin_approval.dart`, a signed-out browser signed in by this phone): the client over [api]
/// with its errors read as the relay's own, the poll, the deadline on this phone's clock, and
/// reading a relayed 32-byte key. Twin of apps/web/app/local/relay.ts. It imports [PairingClock]
/// from `relay_clock.dart`, never `pairing.dart`.

/// A relay's 8-character code once normalised (`normalizePairingCode`): Crockford base 32.
final relayCodePattern = RegExp(r'^[0-9A-HJKMNP-TV-Z]{8}$');

bool sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 32 bytes from base64url; for anything else the server relays, [onBad]'s error is thrown (a
/// [FormatException] without one).
Uint8List key32(String text, {Exception Function()? onBad}) {
  Exception bad() => onBad?.call() ?? const FormatException('not a 32-byte key');
  final Uint8List bytes;
  try {
    bytes = fromBase64Url(text);
  } on Object {
    throw bad();
  }
  if (bytes.length != 32) throw bad();
  return bytes;
}

/// A 409 the caller reads as "look again at the next poll".
const relayRetry = Object();

/// The first wait after a 429 that says nothing of when to come back; doubled on each 429 after
/// it, up to [relayTooManyMaxWait]. Never zero: asking again at once only hammers the server.
const relayTooManyWait = Duration(seconds: 5);
const relayTooManyMaxWait = Duration(seconds: 30);

/// The relay for one request: [api] (the `x-wambito-user` header, `session_changed`) with its
/// errors read as the relay's, made by `error`: offline -> `offline`, 404 -> `gone` (`expired`
/// without one), 422 -> `tampered`, a 409 -> the caller's code (or a retry), the rest `server`.
/// [KeysError]s that are not about the relay (`session_changed`, `rotated_elsewhere`) go through
/// unchanged. Every call first checks the cancel flag and the clock against the deadline ([ttl] on
/// this phone's clock from its start or [restart], or an earlier `expiresAt` through
/// [setDeadline]), and the flag again once the answer is in: a cancelled request never acts on
/// what it was told. With [backOffTooMany], a 429 waits (its `retry-after`, else a growing
/// back-off, never nothing) and asks again while the deadline allows; without, it is `server`.
class RelayClient {
  RelayClient(
    KeysOptions options,
    this._clock, {
    required this.ttl,
    required Exception Function(String code) error,
    Exception Function()? gone,
    this.backOffTooMany = false,
  }) : _call = api(options),
       _error = error,
       _gone = gone ?? (() => error('expired')) {
    restart();
  }

  final KeysApi _call;
  final PairingClock _clock;
  final Duration ttl;
  final Exception Function(String code) _error;
  final Exception Function() _gone;
  final bool backOffTooMany;

  // this device's own cap: a relay cannot stretch a request past [ttl] from its start
  late DateTime _cap;
  late DateTime _deadline;
  bool cancelled = false;

  /// Counts [ttl] again from now, on this phone's clock.
  void restart() {
    _cap = _clock.now().add(ttl);
    _deadline = _cap;
  }

  void check() {
    if (cancelled) throw _error('cancelled');
    if (!_clock.now().isBefore(_deadline)) throw _error('expired');
  }

  /// An earlier end the relay announced; never later than this phone's own cap.
  void setDeadline(String expiresAt) {
    final at = DateTime.tryParse(expiresAt);
    _deadline = at == null || at.isAfter(_cap) ? _cap : at;
  }

  /// The answer's JSON, or null for a 409 when [conflict] is [relayRetry].
  Future<Map<String, Object?>?> send(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
    Object conflict = 'server',
    bool json = true,
  }) async {
    var wait = relayTooManyWait;
    for (;;) {
      check();
      try {
        final response = await _call(path, method: method, data: body);
        if (cancelled) throw _error('cancelled');
        return json ? _object(response.data) : const {};
      } on KeysError catch (error) {
        if (cancelled) throw _error('cancelled');
        if (error.code == 'offline') throw _error('offline');
        if (error.code != 'server') rethrow;
        if (error.status == 404) throw _gone();
        if (error.status == 422) throw _error('tampered');
        if (error.status == 409) {
          if (identical(conflict, relayRetry)) return null;
          throw _error(conflict as String);
        }
        if (error.status == 429 && backOffTooMany) {
          final said = error.retryAfter;
          if (said != null) {
            await _clock.sleep(Duration(seconds: said));
          } else {
            await _clock.sleep(wait);
            final next = wait * 2;
            wait = next > relayTooManyMaxWait ? relayTooManyMaxWait : next;
          }
          continue;
        }
        throw _error('server');
      }
    }
  }

  Future<Map<String, Object?>> get(String path) async => (await send(path))!;

  Future<Map<String, Object?>?> post(
    String path,
    Map<String, Object?>? body, {
    Object conflict = 'server',
    bool json = true,
  }) => send(path, method: 'POST', body: body, conflict: conflict, json: json);

  /// Reads [path] every [every] until [step] answers non-null with the decoded body, checking the
  /// deadline and the cancel flag in between.
  Future<T> poll<T>(
    String path,
    Future<T?> Function(Map<String, Object?> body) step, {
    Duration every = const Duration(milliseconds: 1500),
  }) async {
    for (;;) {
      final done = await step(await get(path));
      if (done != null) return done;
      check();
      await _clock.sleep(every);
    }
  }

  Map<String, Object?> _object(Object? data) {
    try {
      final json = data is String ? jsonDecode(data) : data;
      if (json is Map) return json.cast<String, Object?>();
    } on Object {
      // not an object
    }
    throw _error('server');
  }
}
