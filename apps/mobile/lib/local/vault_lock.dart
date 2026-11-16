import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'db.dart' show defaultVaultDirectory, vaultFileName;

/// The lock file of one account's vault: `wambito-vault-<id>.db-lock`, next to the vault file. It
/// holds a lease so that only one Flutter engine (the app, the headless sync worker, the headless
/// capture) syncs the vault at a time.
String vaultLockFileName(String userId) => '${vaultFileName(userId)}-lock';

/// A lease on the vault of one account: [release] gives it up.
abstract interface class VaultLease {
  Future<void> release();

  /// Whether the lease is still ours: true when the lock file holds this lease's token and the
  /// lease is live (it is then extended by the ttl); false once it expired or was taken over. A run
  /// that gets false must stop writing: another engine may hold the vault now.
  Future<bool> renew();
}

/// How long a lock file that is empty or unreadable counts as being written (its holder created
/// the file and has not written its content yet) before it counts as abandoned.
const _unwrittenGrace = Duration(seconds: 5);

/// A lease this close to its expiry is no longer deleted by its holder.
const _releaseMargin = Duration(seconds: 1);

final _random = Random.secure();

String _token() =>
    List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

class _Lease implements VaultLease {
  _Lease(this._path, this._token, this._holder, this._ttl, this._clock);

  final String _path;
  final String _token;
  final String _holder;
  final Duration _ttl;
  final DateTime Function() _clock;
  bool _released = false;

  @override
  Future<bool> renew() async {
    if (_released) return false;
    try {
      final content = _read(File(_path));
      if (content?.token != _token) return false;
      if (content!.expiresAt - _releaseMargin.inMilliseconds <= _clock().millisecondsSinceEpoch) {
        return false;
      }
      // A new file moved over ours (atomic): a reader never sees it half written. Only the holder
      // touches a live lease, so nobody else is writing this path.
      final next = File('$_path.$_token-renew');
      next.writeAsStringSync(
        jsonEncode({
          'holder': _holder,
          'token': _token,
          'expiresAt': _clock().add(_ttl).millisecondsSinceEpoch,
        }),
        flush: true,
      );
      next.renameSync(_path);
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      final file = File(_path);
      // Only the file that is still ours, and only while the lease is live: from its expiry on a
      // taker may replace it at any moment, so an expired lease is left for the takers (the one
      // rule that keeps a takeover from ever removing a live lease).
      final content = _read(file);
      if (content?.token != _token) return;
      if (content!.expiresAt - _releaseMargin.inMilliseconds <= _clock().millisecondsSinceEpoch) {
        return;
      }
      await file.delete();
    } on Object {
      // Gone already: nothing to give up.
    }
  }
}

class _Content {
  const _Content(this.token, this.expiresAt);

  final String token;
  final int expiresAt;
}

_Content? _read(File file) {
  try {
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map) return null;
    final token = json['token'];
    final expiresAt = json['expiresAt'];
    if (token is! String || expiresAt is! int) return null;
    return _Content(token, expiresAt);
  } on Object {
    return null;
  }
}

/// Tries once to take the lease of [userId]'s vault for [holder]. Null when another holder has it
/// and it has not expired (or a taker is just replacing an expired one: ask again). Works across
/// engines and OS processes, not only isolates, with two atomic file operations:
/// - the lock file is made with an exclusive create (`O_CREAT | O_EXCL`), which the file system
///   grants to exactly one caller; it holds `{holder, token, expiresAt}`;
/// - an expired lease is taken over by an exclusive create of a claim file named after the expired
///   lease's token: exactly one taker gets it. Only the claim's winner removes the lock file (by an
///   atomic `rename` to a unique name) and makes the new one with the same exclusive create, then
///   drops its claim. A holder never touches its own lease once it has expired (see
///   [VaultLease.release]), so between a taker reading the expired lease and its removal the file can
///   only be changed by that claim's winner: no second taker can remove a live lease by mistake.
/// [directory] is the vault folder (tests; the app leaves it out); [now] is for tests.
Future<VaultLease?> tryLease(
  String userId, {
  required String holder,
  String? directory,
  Duration ttl = const Duration(minutes: 10),
  DateTime Function()? now,
}) async {
  final dir = directory ?? await defaultVaultDirectory();
  Directory(dir).createSync(recursive: true);
  final path = p.join(dir, vaultLockFileName(userId));
  final clock = now ?? DateTime.now;
  final file = File(path);
  final mine = _token();
  DateTime expiry() => clock().add(ttl);
  for (var attempt = 0; attempt < 3; attempt++) {
    if (_create(file, holder, mine, expiry())) return _Lease(path, mine, holder, ttl, clock);
    final seen = _read(file);
    final stat = _stat(file);
    if (stat == null) continue; // released between the create and the read: try again
    if (seen == null) {
      // Empty or unreadable: being written by its creator, or abandoned.
      if (clock().difference(stat.modified) < _unwrittenGrace) return null;
    } else if (seen.expiresAt > clock().millisecondsSinceEpoch) {
      return null;
    }
    // Expired. One taker wins the claim on this expired lease; the others ask again later. A claim
    // left by a dead claimant is never deleted by path (two takers could each delete the other's
    // fresh claim): a taker that finds it stale claims on top of it, named after the stale claim's
    // own token, so exactly one taker recovers it; that winner deletes the stale claims only after
    // it has replaced the lock.
    final stale = <File>[];
    var claim = File('$path.claim-${seen?.token ?? 'unwritten'}');
    while (!_create(claim, holder, mine, expiry())) {
      final claimStat = _stat(claim);
      final theirs = _read(claim);
      if (claimStat == null ||
          theirs == null ||
          clock().difference(claimStat.modified) <= _claimGrace ||
          stale.length >= 3) {
        return null;
      }
      stale.add(claim);
      claim = File('${claim.path}.${theirs.token}');
    }
    try {
      final still = _read(file);
      final unchanged = seen == null ? still == null : still?.token == seen.token;
      // A claimant delayed past the grace may have been recovered meanwhile: only a claim that is
      // still ours may act.
      if (_read(claim)?.token != mine) return null;
      if (_stat(file) != null && unchanged) {
        final away = '$path.${_token()}';
        file.renameSync(away);
        _drop(File(away));
      }
      if (_create(file, holder, mine, expiry())) {
        return _Lease(path, mine, holder, ttl, clock);
      }
    } on FileSystemException {
      // Another caller changed the file under us: ask again later.
    } finally {
      _drop(claim);
      // After the lock was replaced, so a new claim on the old token finds another token.
      stale.forEach(_drop);
    }
    return null;
  }
  return null;
}

/// A claim older than this belongs to a taker that is gone.
const _claimGrace = Duration(seconds: 30);

FileStat? _stat(File file) {
  final stat = file.statSync();
  return stat.type == FileSystemEntityType.notFound ? null : stat;
}

void _drop(File file) {
  try {
    file.deleteSync();
  } on Object {
    // A leftover with a unique name: the sweep of stale vaults never matches it, nothing reads it.
  }
}

/// The exclusive create: false when the file exists.
bool _create(File file, String holder, String token, DateTime expiresAt) {
  try {
    file.createSync(exclusive: true);
  } on FileSystemException {
    return false;
  }
  file.writeAsStringSync(
    jsonEncode({'holder': holder, 'token': token, 'expiresAt': expiresAt.millisecondsSinceEpoch}),
    flush: true,
  );
  return true;
}

/// [tryLease] again and again until it gets the lease or [wait] passes (null then).
Future<VaultLease?> waitLease(
  String userId, {
  required String holder,
  Duration wait = const Duration(seconds: 30),
  String? directory,
}) async {
  final watch = Stopwatch()..start();
  while (true) {
    final lease = await tryLease(userId, holder: holder, directory: directory);
    if (lease != null) return lease;
    if (watch.elapsed >= wait) return null;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}
