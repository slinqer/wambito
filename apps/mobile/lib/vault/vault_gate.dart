import 'dart:async';

import '../local/keys_error.dart';
import '../local/prf.dart';
import '../local/vault_session.dart' show VaultOpenError;

/// The vault gate's state machine: what a preview account sees before the app. The Dart twin of
/// apps/web/app/features/vault/vault-gate.ts, without pairing (stage 3b). No Flutter and no
/// storage here; every effect comes in as a dependency ([VaultGateDeps]), so the tests drive it
/// with fakes.
///
///     checking ─ keys on this phone ────────────────────────────────▶ opening ─▶ ready
///        │                                                               ▲
///        ├─ account without wraps ─▶ setup (key shown) ─ confirm ─▶ committing
///        │     (a guest commits at once, nothing to show)                │
///        └─ account with wraps ─┬▶ unlock ─ recovery key or passkey ───┘
///                                └─ the sign-in's passkey PRF opens a wrap ─▶ opening
///
/// Passkeys: a passkey sign-in's PRF, when the app keeps one ([VaultGateDeps.takeSignInPrf]), is
/// tried first on an account with keys elsewhere; when it opens nothing, Unlock shows, and once the
/// vault is unlocked by other means (the recovery key, a new account's setup) the gate adds the
/// wrap for that credential. Unlock's "Use a passkey" touches a passkey for its PRF
/// ([VaultGateDeps.evaluatePrf]); one without a wrap is kept the same way. A known phone zeroes
/// the stash. Every PRF is zeroed once used.
///
/// A phone removed from the account by another device ([removed], from the session's `onRemoved`:
/// its vault is already deleted) shows Unlock with the `removed` notice; a guest, which has no
/// recovery key to type, its Locked.
///
/// A phone that could not verify a new key version ([unverified], from the session's
/// `onUnverified`, or an opening that fails with `key_unverified`) shows Unlock with the
/// `unverified` notice, a guest its Locked. Its vault is still here, unsent changes included.
///
/// Any failure outside Unlock's own errors lands on Locked, whose retry repeats the step that
/// failed: a failed commit commits again (the same wraps, the same ids), anything else starts over.
/// A commit that lost the race to another setup (`already_set_up`) drops its keys and shows Unlock
/// (a guest: Locked). Two locked kinds have no retry: `unsupported` and `guest`.
///
/// Another account may be signed in by now (a sign-in elsewhere in the app). Before making or
/// unlocking keys, and when the open vault closes or its sync says `session_changed`, the gate asks
/// who is signed in; another account (or none) reloads the app for them, so nothing runs for the
/// old id. The server refuses a `/v2` call for another account (409) as the last guard.
///
/// Phone differences: `K` and `S` (the keys and the session) are type parameters as in the TS, so
/// the tests use fakes; the app's gate is a `VaultGate<LocalKeys, VaultSession>`. Errors carry their
/// code as [KeysError], [VaultOpenError] or [GateError].

/// Why the vault is locked; `unsupported` and `guest` have no retry.
enum LockedKind { error, offline, unsupported, guest }

sealed class VaultGateState<S> {
  const VaultGateState();

  /// The TS `status`: `checking`, `setup`, `committing`, `unlock`, `opening`, `ready`, `locked`.
  String get status;
}

final class Checking<S> extends VaultGateState<S> {
  const Checking();

  @override
  String get status => 'checking';

  @override
  bool operator ==(Object other) => other is Checking;

  @override
  int get hashCode => status.hashCode;

  @override
  String toString() => 'Checking()';
}

final class Setup<S> extends VaultGateState<S> {
  const Setup(this.recoveryKey);

  final String recoveryKey;

  @override
  String get status => 'setup';

  @override
  bool operator ==(Object other) => other is Setup && other.recoveryKey == recoveryKey;

  @override
  int get hashCode => Object.hash(status, recoveryKey);

  @override
  String toString() => 'Setup(<key>)';
}

final class Committing<S> extends VaultGateState<S> {
  const Committing();

  @override
  String get status => 'committing';

  @override
  bool operator ==(Object other) => other is Committing;

  @override
  int get hashCode => status.hashCode;

  @override
  String toString() => 'Committing()';
}

final class Unlock<S> extends VaultGateState<S> {
  const Unlock({this.notice});

  /// This phone was removed from the account (its vault is gone).
  static const removed = 'removed';

  /// A new key version did not verify (its vault is kept).
  static const unverified = 'unverified';

  /// [removed], [unverified] or null.
  final String? notice;

  @override
  String get status => 'unlock';

  @override
  bool operator ==(Object other) => other is Unlock && other.notice == notice;

  @override
  int get hashCode => Object.hash(status, notice);

  @override
  String toString() => 'Unlock(notice: $notice)';
}

final class Opening<S> extends VaultGateState<S> {
  const Opening();

  @override
  String get status => 'opening';

  @override
  bool operator ==(Object other) => other is Opening;

  @override
  int get hashCode => status.hashCode;

  @override
  String toString() => 'Opening()';
}

final class Ready<S> extends VaultGateState<S> {
  const Ready(this.session);

  final S session;

  @override
  String get status => 'ready';

  @override
  bool operator ==(Object other) => other is Ready && other.session == session;

  @override
  int get hashCode => Object.hash(status, session);

  @override
  String toString() => 'Ready($session)';
}

final class Locked<S> extends VaultGateState<S> {
  const Locked(this.kind, this.retrying);

  final LockedKind kind;
  final bool retrying;

  @override
  String get status => 'locked';

  @override
  bool operator ==(Object other) =>
      other is Locked && other.kind == kind && other.retrying == retrying;

  @override
  int get hashCode => Object.hash(status, kind, retrying);

  @override
  String toString() => 'Locked($kind, retrying: $retrying)';
}

/// A failure the gate (or its wiring) makes itself, by code.
class GateError implements Exception {
  const GateError(this.code);

  final String code;

  @override
  String toString() => 'GateError($code)';
}

/// A prepared new account: the key to show (null for a guest) and the commit that sends it.
class GatePrepared<K> {
  const GatePrepared({required this.recoveryKey, required this.commit});

  final String? recoveryKey;
  final Future<K> Function() commit;
}

class VaultGateDeps<K, S> {
  const VaultGateDeps({
    required this.loadLocalKeys,
    required this.prepareAccount,
    required this.unlockWithRecovery,
    required this.open,
    this.guest = false,
    this.userId,
    this.sessionUserId,
    this.reload,
    this.takeSignInPrf,
    this.unlockWithPasskey,
    this.addPasskeyWrap,
    this.evaluatePrf,
    this.accountPasskeyIds,
  });

  /// The keys this phone kept, or null.
  final Future<K?> Function() loadLocalKeys;

  /// Throws a `already_set_up` error when the account has wraps.
  final Future<GatePrepared<K>> Function() prepareAccount;

  /// Throws an error with an Unlock code when the key is refused.
  final Future<K> Function(String text) unlockWithRecovery;

  /// Opens the store, runs the sync and returns the session. `fresh`: the keys were just made or
  /// unlocked, so the first full sync must succeed (a known phone opens on its local data).
  final Future<S> Function(K keys, bool fresh) open;

  /// A guest: never shown a recovery key, so an account with keys elsewhere is `Locked(guest)`.
  final bool guest;

  /// The account this gate is for.
  final String? userId;

  /// Who is signed in now (null: no one); throws when it cannot tell (offline).
  final Future<String?> Function()? sessionUserId;

  /// Loads the app again for whoever is signed in now.
  final void Function()? reload;

  /// The sign-in's (or registration's) passkey PRF, once, when it is this account's; else null.
  final PasskeyPrf? Function()? takeSignInPrf;

  /// Opens the passkey wrap of that credential; throws `no_passkey_wrap` when none.
  final Future<K> Function(PasskeyPrf passkey)? unlockWithPasskey;

  /// Adds the wrap for that passkey, from this phone's device wrap (once unlocked).
  final Future<void> Function(PasskeyPrf passkey)? addPasskeyWrap;

  /// Touches a passkey (one of `credentialIds` when given) for its PRF: null when cancelled,
  /// `no_prf` without one.
  final Future<PasskeyPrf?> Function(List<String>? credentialIds)? evaluatePrf;

  /// The account's passkey credential ids, so Unlock offers only those; throws when unknown.
  final Future<List<String>> Function()? accountPasskeyIds;
}

/// The codes Unlock shows; anything else is `server`.
const unlockErrors = [
  'bad_recovery_key',
  'wrong_recovery_key',
  'no_prf',
  'no_passkey_wrap',
  'offline',
  'server',
];

/// The code an error carries, if any.
String? gateErrorCode(Object? error) => switch (error) {
  KeysError(:final code) => code,
  VaultOpenError(:final code) => code.wire,
  GateError(:final code) => code,
  _ => null,
};

LockedKind _lockedKind(Object? error) => switch (gateErrorCode(error)) {
  'offline' => LockedKind.offline,
  'unsupported_browser' => LockedKind.unsupported,
  _ => LockedKind.error,
};

/// Kinds a retry cannot fix.
const _final = [LockedKind.unsupported, LockedKind.guest];

String _unlockError(Object? error) {
  final code = gateErrorCode(error);
  return code != null && unlockErrors.contains(code) ? code : 'server';
}

void _zero(PasskeyPrf passkey) => passkey.prf.fillRange(0, passkey.prf.length, 0);

/// The result of trying a passkey: the keys, or why not.
typedef _Tried<K> = ({K? keys, Object? error});

class VaultGate<K, S> {
  VaultGate(this._deps) {
    _again = _check;
  }

  final VaultGateDeps<K, S> _deps;
  VaultGateState<S> _state = const Checking();
  final Set<void Function()> _listeners = {};
  bool _started = false;
  GatePrepared<K>? _prepared;
  late Future<void> Function() _again;

  /// A passkey without a wrap yet: its wrap is added once the vault is unlocked by other means.
  PasskeyPrf? _pendingPasskey;

  VaultGateState<S> get state => _state;

  /// Calls [listener] after every change of [state]. Returns the unsubscribe.
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _set(VaultGateState<S> next) {
    _state = next;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void _keepPending(PasskeyPrf? passkey) {
    final pending = _pendingPasskey;
    if (pending != null && !identical(pending, passkey)) _zero(pending);
    _pendingPasskey = passkey;
  }

  /// Adds the pending passkey's wrap (a failure only leaves it without one), then zeroes it.
  Future<void> _wrapPending() async {
    final passkey = _pendingPasskey;
    _pendingPasskey = null;
    if (passkey == null) return;
    try {
      await _deps.addPasskeyWrap?.call(passkey);
    } on Object {
      // The passkey simply does not unlock yet; Settings can turn it on later.
    } finally {
      _zero(passkey);
    }
  }

  /// Tries a passkey's PRF on its wrap; on failure keeps it for after another unlock.
  Future<_Tried<K>> _tryPasskey(PasskeyPrf passkey) async {
    final unlock = _deps.unlockWithPasskey;
    if (unlock == null) {
      _keepPending(passkey);
      return (keys: null, error: const GateError('no_passkey_wrap'));
    }
    try {
      final keys = await unlock(passkey);
      _zero(passkey);
      return (keys: keys, error: null);
    } on Object catch (error) {
      if (gateErrorCode(error) == 'no_passkey_wrap') {
        _keepPending(passkey);
      } else {
        _zero(passkey);
      }
      return (keys: null, error: error);
    }
  }

  /// The account has keys made elsewhere: Unlock, or Locked for a guest (nothing to type).
  void _hasKeysElsewhere() {
    _prepared = null;
    if (_deps.guest) {
      // Nothing to unlock with first: a guest has no recovery key to type.
      _keepPending(null);
      _set(const Locked(LockedKind.guest, false));
    } else {
      _set(const Unlock());
    }
  }

  /// Removed (its vault is gone) or unverified (its vault is kept): Unlock with the notice, a
  /// guest's Locked.
  void _showNotice(String notice) {
    _prepared = null;
    if (_deps.guest) {
      _set(const Locked(LockedKind.guest, false));
    } else {
      _set(Unlock(notice: notice));
    }
  }

  /// Shows Locked; its retry runs [step].
  void _lock(Object? error, Future<void> Function() step) {
    _again = step;
    _set(Locked(_lockedKind(error), false));
  }

  /// Whether this gate's account is still the signed-in one. When not, reloads the app (the gate
  /// stays on checking until it goes). Unknown (offline, say): true, the server guards.
  Future<bool> _sameSession() async {
    final sessionUserId = _deps.sessionUserId;
    if (sessionUserId == null || _deps.userId == null) return true;
    String? current;
    try {
      current = await sessionUserId();
    } on Object {
      return true;
    }
    if (current == _deps.userId) return true;
    _set(const Checking());
    _deps.reload?.call();
    return false;
  }

  /// A call was refused with `session_changed`: reload for the new account, else lock (no loop).
  Future<void> _changed(Object? error, Future<void> Function() step) async {
    if (await _sameSession()) _lock(error, step);
  }

  Future<void> _open(K keys, bool fresh) async {
    _set(const Opening());
    try {
      final session = await _deps.open(keys, fresh);
      _keepPending(null);
      _set(Ready(session));
    } on Object catch (error) {
      // The keys are kept now: a retry starts over and finds them.
      switch (gateErrorCode(error)) {
        case 'session_changed':
          await _changed(error, _check);
        case 'device_removed':
          // Removed while the app was closed: the session deleted the vault, so say so.
          _keepPending(null);
          _showNotice(Unlock.removed);
        case 'key_unverified':
          // A new key version did not verify: the vault is kept, an unlock opens it again.
          _keepPending(null);
          _showNotice(Unlock.unverified);
        default:
          _lock(error, _check);
      }
    }
  }

  /// Checks again after the open vault went away: first, is it still the same account?
  Future<void> _recheck() async {
    _set(const Checking());
    if (await _sameSession()) await _check();
  }

  Future<void> _check() async {
    _set(const Checking());
    K? keys;
    try {
      keys = await _deps.loadLocalKeys();
    } on Object catch (error) {
      _lock(error, _check);
      return;
    }
    final stashed = _deps.takeSignInPrf?.call();
    if (keys != null) {
      if (stashed != null) _zero(stashed);
      return _open(keys, false);
    }
    if (stashed != null) _keepPending(stashed);
    // Never make keys for an account that is no longer the signed-in one (nor keep its PRF).
    if (!await _sameSession()) {
      _keepPending(null);
      return;
    }
    final GatePrepared<K> prepared;
    try {
      prepared = await _deps.prepareAccount();
    } on Object catch (error) {
      final code = gateErrorCode(error);
      if (code == 'already_set_up') {
        final passkey = _pendingPasskey;
        if (passkey != null) {
          _pendingPasskey = null;
          final tried = await _tryPasskey(passkey);
          final keys = tried.keys;
          if (tried.error == null && keys != null) return _open(keys, true);
          if (gateErrorCode(tried.error) == 'session_changed') {
            return _changed(tried.error, _check);
          }
        }
        _hasKeysElsewhere();
      } else if (code == 'session_changed') {
        await _changed(error, _check);
      } else {
        _lock(error, _check);
      }
      return;
    }
    _prepared = prepared;
    final recoveryKey = prepared.recoveryKey;
    if (recoveryKey == null) return _commit();
    _set(Setup(recoveryKey));
  }

  Future<void> _commit() async {
    final current = _prepared;
    if (current == null) return _check();
    _set(const Committing());
    final K keys;
    try {
      keys = await current.commit();
    } on Object catch (error) {
      // Another phone or browser set the account up first: its data key wins, this one is dropped.
      switch (gateErrorCode(error)) {
        case 'already_set_up':
          _hasKeysElsewhere();
        case 'session_changed':
          await _changed(error, _commit);
        default:
          _lock(error, _commit);
      }
      return;
    }
    _prepared = null;
    await _wrapPending();
    return _open(keys, true);
  }

  /// Runs the first check. Once; later calls do nothing.
  void start() {
    if (_started) return;
    _started = true;
    unawaited(_check());
  }

  /// The person typed four characters back on the setup screen.
  Future<void> confirmSetup() => _state is Setup ? _commit() : Future.value();

  /// The Unlock screen's submit: null when it worked, else why not (the screen shows it).
  Future<String?> unlock(String text) async {
    if (_state is! Unlock) return null;
    if (!await _sameSession()) return null;
    final K keys;
    try {
      keys = await _deps.unlockWithRecovery(text);
    } on Object catch (error) {
      switch (gateErrorCode(error)) {
        case 'session_changed':
          await _changed(error, _check);
          return null;
        case 'unsupported_browser':
          _lock(error, _check);
          return null;
      }
      return _unlockError(error);
    }
    await _wrapPending();
    await _open(keys, true);
    return null;
  }

  /// Unlock's "Use a passkey": null when it worked or was cancelled, else why not.
  Future<String?> unlockWithPasskey() async {
    final evaluatePrf = _deps.evaluatePrf;
    if (_state is! Unlock || evaluatePrf == null) return null;
    if (!await _sameSession()) return null;
    // Only this account's passkeys (another account's would open nothing, and must never get a
    // wrap of this data key); an unreadable list leaves the choice open, and the server refuses a
    // wrap for a credential not this account's.
    List<String>? ids;
    try {
      ids = await _deps.accountPasskeyIds?.call();
    } on Object {
      ids = null;
    }
    if (ids != null && ids.isEmpty) return 'no_passkey_wrap';
    final PasskeyPrf? passkey;
    try {
      passkey = await evaluatePrf(ids);
    } on Object catch (error) {
      return _unlockError(error);
    }
    if (passkey == null) return null;
    final tried = await _tryPasskey(passkey);
    final keys = tried.keys;
    if (tried.error == null && keys != null) {
      _keepPending(null);
      await _open(keys, true);
      return null;
    }
    switch (gateErrorCode(tried.error)) {
      case 'session_changed':
        await _changed(tried.error, _check);
        return null;
      case 'unsupported_browser':
        _lock(tried.error, _check);
        return null;
    }
    return _unlockError(tried.error);
  }

  /// Locked's retry.
  void retry() {
    final state = _state;
    if (state is! Locked<S> || state.retrying || _final.contains(state.kind)) return;
    _set(Locked(state.kind, true));
    unawaited(_again());
  }

  /// The open vault closed under the app: check again (reopen, or Unlock).
  void closed() {
    if (_state is Ready) unawaited(_recheck());
  }

  /// The sync said another account is signed in (409 `session_changed`): reload or lock.
  void sessionChanged() {
    if (_state is Ready) unawaited(_changed(const GateError('session_changed'), _recheck));
  }

  /// This phone was removed from the account (`VaultSession.onRemoved`: its device wrap is gone and
  /// the vault was deleted): Unlock with the `removed` notice; a guest's Locked.
  void removed() {
    if (_state is! Ready) return;
    _showNotice(Unlock.removed);
  }

  /// A new key version did not verify (`VaultSession.onUnverified`: the sync stopped, the vault is
  /// kept): Unlock with the `unverified` notice; a guest's Locked.
  void unverified() {
    if (_state is! Ready) return;
    _showNotice(Unlock.unverified);
  }
}
