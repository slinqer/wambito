import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../core/records.dart' show Json, parseRecord;
import '../crypto/crypto.dart';
import 'keys.dart' show Keyring, KeysError;
import 'sqlite_store.dart';
import 'store.dart' show WriteOptions;

/// The sync engine: the Dart twin of `apps/web/app/local/sync.ts`. It pushes the outbox to
/// `POST /v2/sync`, pulls `GET /v2/sync`, and keeps the vault equal to the server (spec
/// 2026-11-08 end-to-end-encryption section 6, stage 1b addendum section 3, stage 3 section 4.3).
/// It never logs or reports plaintext, only ids, types and counts.
///
/// Decisions worth knowing (the same as sync.ts; read its header for the long form):
///
/// - A run pushes first, then pulls.
/// - A pulled record whose id has a pending outbox entry is not applied (the cursor still moves
///   past it), checked again inside the apply transaction (`skipIfPending`). The push's conflict
///   path merges field by field: the fields the person touched keep their value, the others take
///   the server's. Conflict writes use `ifSeq`: a newer local write wins over the merge.
/// - A conflict on a create (deterministic ids only) takes the server's copy plus the fields the
///   person changed after the create.
/// - A local delete beats a concurrent server edit; a server delete beats a local edit
///   (`serverDeleted`). `not_found` and `id_taken` drop the entry (`dropped`).
/// - A change that keeps failing is parked (1 min back-off, doubling, at most 6 hours) and never
///   stops the pull; on its fifth failure it is abandoned (`dropped`). A whole batch refused with
///   413/422 is bisected; any other 4xx but 401 parks the batch. Offline, 401, 429 and 5xx stop.
/// - Every call sends `x-wambito-user`. `409 session_changed` stops the run and the triggers.
/// - `410 resync_required`: the pending changes are set aside in the wipe's own commit, the full
///   download runs with `base=0`, then the set-aside changes are written again (touched fields
///   only) onto the fresh copies.
/// - Commits made by the engine never trigger a run. A local write while a run is in flight gets a
///   follow-up pass (only for outbox writes newer than the pass's start) and, through
///   [SyncEngine.afterLocalWrite], one more debounced run.
/// - Key versions: a record opens with the keys of its own `keyV`; every change is sealed under the
///   current version. A newer version refreshes the keys (once per needed version per run); one
///   still unknown is quarantined as `unknown_key_version` and retried when the current version
///   grows, and on the engine's first pull. `key_version_mismatch` refreshes and seals again once,
///   else parks. `device_removed` and `tampered` (problem `key_unverified`) stop the run and the
///   triggers. The upgrade pass re-seals records under an older `keyV` through `reseal` outbox
///   entries (at most 500 pending), and an old version's key is dropped once nothing uses it.
///
/// Phone differences: one run per account in the process (a Dart lock in place of the Web Lock);
/// the triggers are app start, return to the foreground ([AppLifecycleListener]), a minute while in
/// the foreground, a local write ([SyncEngine.afterLocalWrite], wired to the local backend's
/// interceptor) and pull-to-refresh ([SyncEngine.run]). The keys live in secure storage, so an
/// unused old version is dropped through [SyncEngineOptions.dropKeyVersion].

/// The record format version this client reads and writes.
const _encV = 1;
const _pushBatch = 500;

/// Stay under the server's 4 MiB request limit.
const _pushBytes = 3 * 1024 * 1024;
const _pullLimit = 1000;

/// The most reseal entries pending at once: one upgrade pass re-encrypts at most this many.
const resealLimit = 500;

/// How many times one id may conflict inside one run before it is parked.
const _maxConflicts = 3;

/// The failure on which a parked change is given up on (`abandoned`).
const _maxAttempts = 5;

/// Every outbox entry (JS `Number.MAX_SAFE_INTEGER`).
const _all = 9007199254740991;

/// A parked change's back-off in ms: 1 min, doubling, at most 6 hours.
int _parkDelay(int attempts) {
  const max = 6 * 3600000;
  if (attempts > 20) return max;
  final delay = 60000 * (1 << (attempts - 1));
  return delay < max ? delay : max;
}

/// The codes of `SyncProblemCode` in sync.ts, in lowerCamelCase; [wire] is the TypeScript string.
enum SyncProblemCode {
  offline('offline'),
  server('server'),
  unauthorized('unauthorized'),
  rejected('rejected'),
  dropped('dropped'),
  serverDeleted('server_deleted'),
  quarantined('quarantined'),
  conflictUnreadable('conflict_unreadable'),

  /// Changes the engine gave up on for now (see [SyncResult.parked]).
  parked('parked'),

  /// The store was closed (sign-out, or the session closed it).
  closed('closed'),

  /// The signed-in account is not the vault's (409 `session_changed`): the engine stops.
  sessionChanged('session_changed'),

  /// This phone's device wrap is gone (removed from the account): the engine stops.
  deviceRemoved('device_removed'),

  /// A newer key version's links do not lead back to the held key (`tampered`): the engine stops.
  keyUnverified('key_unverified');

  const SyncProblemCode(this.wire);

  final String wire;
}

/// Something the UI may want to tell the person. Ids and counts only.
@immutable
class SyncProblem {
  const SyncProblem(this.code, {this.ids, this.count, this.status});

  final SyncProblemCode code;
  final List<String>? ids;
  final int? count;
  final int? status;

  @override
  bool operator ==(Object other) =>
      other is SyncProblem &&
      other.code == code &&
      other.count == count &&
      other.status == status &&
      _sameList(other.ids, ids);

  @override
  int get hashCode => Object.hash(code, count, status, ids == null ? null : Object.hashAll(ids!));

  @override
  String toString() =>
      'SyncProblem(${code.wire}${ids == null ? '' : ', ids: $ids'}'
      '${count == null ? '' : ', count: $count'}${status == null ? '' : ', status: $status'})';
}

bool _sameList(List<String>? a, List<String>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class SyncResult {
  SyncResult({
    this.ok = true,
    this.pushed = 0,
    this.pulled = 0,
    this.merged = 0,
    List<String>? serverDeleted,
    List<String>? dropped,
    this.quarantined = 0,
    List<String>? parked,
    this.resynced = false,
    this.error,
    this.problem,
  }) : serverDeleted = serverDeleted ?? [],
       dropped = dropped ?? [],
       parked = parked ?? [];

  /// False when the run stopped early (offline, server error): retry later.
  bool ok;
  int pushed;
  int pulled;
  int merged;

  /// Ids of records the server had deleted while the person had unsent edits.
  final List<String> serverDeleted;

  /// Ids of changes dropped (`not_found`, `id_taken`, or given up on after 5 failures).
  final List<String> dropped;
  int quarantined;

  /// Ids of changes parked in this run (they back off; a local edit retries them at once).
  final List<String> parked;
  bool resynced;
  SyncProblemCode? error;

  /// [SyncProblemCode.deviceRemoved]: this phone was removed from the account, the session deletes
  /// the vault. [SyncProblemCode.keyUnverified]: a new key version did not verify, the session
  /// keeps the vault and asks to unlock again.
  SyncProblemCode? problem;

  @override
  String toString() =>
      'SyncResult(ok: $ok, pushed: $pushed, pulled: $pulled, merged: $merged, '
      'serverDeleted: $serverDeleted, dropped: $dropped, quarantined: $quarantined, '
      'parked: $parked, resynced: $resynced, error: ${error?.wire}, problem: ${problem?.wire})';
}

class SyncEngineOptions {
  const SyncEngineOptions({
    required this.store,
    required this.dio,
    required this.userId,
    required this.keyring,
    required this.refreshKeys,
    this.dropKeyVersion,
    this.now,
    this.onError,
    this.debounce = const Duration(seconds: 1),
    this.interval = const Duration(minutes: 1),
    this.watchResume,
    this.isForeground,
  });

  final SqliteStore store;

  /// The network (base `<server>/api`), without the local interceptor.
  final Dio dio;

  /// The account's exact id (it is part of every record's associated data).
  final String userId;

  /// The record keys this phone holds, by key version; changes are sealed under `current`.
  final Keyring keyring;

  /// Fetches this phone's device wrap again and returns the keyring with any newer version
  /// (`keys.dart` `refreshKeys`). Throws `KeysError('device_removed')` when the wrap is gone,
  /// `KeysError('tampered')` when a newer version does not lead back to the held key.
  final Future<Keyring> Function() refreshKeys;

  /// Forgets an old key version's data key (secure storage) once no local record uses it.
  final Future<void> Function(int keyV)? dropKeyVersion;

  /// Epoch milliseconds.
  final int Function()? now;
  final void Function(SyncProblem problem)? onError;

  /// [SyncEngine.start] only: the wait after a local write, and the foreground timer.
  final Duration debounce;
  final Duration interval;

  /// [SyncEngine.start] only: calls the callback when the app comes back to the foreground and
  /// returns the unsubscribe. Default: an [AppLifecycleListener]. For tests.
  final void Function() Function(void Function() onResume)? watchResume;

  /// [SyncEngine.start] only: whether the timer may run now. Default: the app is resumed.
  final bool Function()? isForeground;
}

abstract interface class SyncEngine {
  /// One push-then-pull cycle. Calls made while one runs share it (and force one more pass).
  Future<SyncResult> run();

  /// Starts the triggers (now, return to the foreground, a minute in the foreground, local
  /// writes). Returns stop.
  void Function() start();

  /// Stops the triggers [start] set up.
  void stop();

  /// A local write committed (the local backend's interceptor calls it): a debounced run, or one
  /// more once the run in flight ends. Nothing before [start] or after [stop].
  void afterLocalWrite();

  /// Takes a keyring loaded again from storage (after a rotation committed on this phone). Key
  /// versions only grow: one whose `current` is lower than the engine's is ignored.
  void useKeyring(Keyring next);
}

/// A server record as `/v2/sync` sends it.
class _Wire {
  _Wire.fromJson(Map<Object?, Object?> j)
    : id = j['id']! as String,
      type = j['type']! as String,
      version = j['version']! as int,
      deleted = j['deleted'] == true,
      keyV = j['keyV']! as int,
      encV = j['encV']! as int,
      body = j['body'] as String?;

  final String id;
  final String type;
  final int version;
  final bool deleted;
  final int keyV;
  final int encV;
  final String? body;

  RecordType? get recordType => RecordType.values.asNameMap()[type];
}

/// Thrown to stop a run; [code] says why.
class _Stop implements Exception {
  const _Stop(this.code, [this.status]);

  final SyncProblemCode code;
  final int? status;
}

class _ResyncRequired implements Exception {
  const _ResyncRequired();
}

/// Internal: park this change; [lastError] is the park's `lastError`.
class _Skip implements Exception {
  const _Skip(this.lastError);

  final String lastError;
}

/// Internal: push this change again in the same run (a reseal the person edited meanwhile).
class _Retry implements Exception {
  const _Retry();
}

/// JSON with sorted keys, to compare two bodies whatever their key order.
String _canonical(Object? value) {
  if (value is List) return '[${value.map(_canonical).join(',')}]';
  if (value is Map) {
    final keys = value.keys.map((k) => '$k').toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${_canonical(value[k])}').join(',')}}';
  }
  return jsonEncode(value);
}

/// Fields in [touched] keep the local value; every other field takes the server's.
Json _mergeBodies(Json? local, Json? server, List<String> touched) {
  final l = local ?? const <String, Object?>{};
  final s = server ?? const <String, Object?>{};
  final out = <String, Object?>{};
  for (final key in {...l.keys, ...s.keys}) {
    final from = touched.contains(key) ? l : s;
    if (from.containsKey(key)) out[key] = from[key];
  }
  return out;
}

/// The opened body of a server record, or why it cannot be used.
typedef _Opened = ({Json? body, String? reason});

/// Runs of one account, one at a time in this process (sync.ts takes a Web Lock across tabs).
final Map<String, Completer<void>> _locks = {};

/// Runs [fn] once no other run of [userId] holds the lock. A run whose [store] is closed (sign-out,
/// a removal) lets the next one go at once: it can write nothing more, and a new session of the same
/// account must not wait for its network.
Future<R> _locked<R>(String userId, SqliteStore store, Future<R> Function() fn) async {
  final previous = _locks[userId];
  final mine = Completer<void>();
  _locks[userId] = mine;
  void release() {
    if (!mine.isCompleted) mine.complete();
  }

  final unsubscribe = store.onClosed(release);
  if (store.isClosed) release();
  try {
    if (previous != null) await previous.future;
    return await fn();
  } finally {
    unsubscribe();
    release();
    if (identical(_locks[userId], mine)) _locks.remove(userId);
  }
}

SyncEngine createSyncEngine(SyncEngineOptions options) => _Engine(options);

class _Engine implements SyncEngine {
  _Engine(this.o) : _keyring = o.keyring;

  final SyncEngineOptions o;
  Keyring _keyring;

  SqliteStore get store => o.store;
  String get userId => o.userId;
  int now() => o.now?.call() ?? DateTime.now().millisecondsSinceEpoch;

  void report(SyncProblem problem) {
    try {
      o.onError?.call(problem);
    } on Object {
      // a listener must not break the sync
    }
  }

  Future<Object?> call(
    String path, {
    String method = 'GET',
    Object? data,
    Map<String, Object?>? query,
  }) async {
    final Response<Object?> response;
    try {
      response = await o.dio.request<Object?>(
        path,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {'x-wambito-user': userId},
          contentType: data == null ? null : Headers.jsonContentType,
          validateStatus: (_) => true,
        ),
      );
    } on DioException {
      throw const _Stop(SyncProblemCode.offline);
    }
    final status = response.statusCode ?? 0;
    final body = _decode(response.data);
    if (status == 409 && _problemCode(body) == 'session_changed') {
      throw const _Stop(SyncProblemCode.sessionChanged, 409);
    }
    if (status == 410) throw const _ResyncRequired();
    if (status == 401) throw const _Stop(SyncProblemCode.unauthorized, 401);
    if (status == 429 || status >= 500) throw _Stop(SyncProblemCode.server, status);
    if (status < 200 || status > 299) throw _Stop(SyncProblemCode.rejected, status);
    return body;
  }

  RecordContext ctx(RecordType type, String id, int v) =>
      RecordContext(userId: userId, type: type, id: id, keyV: v);

  // ---- key refreshes ---------------------------------------------------------------------------

  /// Key refreshes in this run: one per distinct version needed above what the last refresh
  /// reached (a rotation may commit between two of them), never twice for the same version.
  Future<void>? _refreshing;
  int _refreshedTo = 0;
  final Set<int> _refreshedFor = {};

  /// The keyring's current version grew: records quarantined as `unknown_key_version` retry. Also
  /// on the first pull of the engine.
  bool _retryUnknown = true;

  Future<void> refresh(int needed) {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    if (needed <= _refreshedTo || _refreshedFor.contains(needed)) return Future.value();
    _refreshedFor.add(needed);
    final future = () async {
      final before = _keyring.current;
      try {
        _keyring = await o.refreshKeys();
      } on Object catch (error) {
        throw _keysStop(error);
      } finally {
        _refreshing = null;
      }
      _refreshedTo = _keyring.current;
      if (_keyring.current > before) _retryUnknown = true;
    }();
    return _refreshing = future;
  }

  /// A new run may refresh again.
  void resetRefreshes() {
    _refreshing = null;
    _refreshedTo = 0;
    _refreshedFor.clear();
  }

  /// The keys of version [v]; a version above the current one refreshes the keyring first.
  Future<RecordKeys?> keysFor(int v) async {
    if (!_keyring.byVersion.containsKey(v) && v > _keyring.current) await refresh(v);
    return _keyring.byVersion[v];
  }

  ({int keyV, RecordKeys keys}) sealingKeys() {
    final keys = _keyring.byVersion[_keyring.current];
    if (keys == null) throw StateError('no record keys for key version ${_keyring.current}');
    return (keyV: _keyring.current, keys: keys);
  }

  /// Opens and validates a server record: the body, or why it cannot be used.
  Future<_Opened> openWire(_Wire rec) async {
    final type = rec.recordType;
    if (type == null) return (body: null, reason: 'unknown_type');
    if (rec.encV != _encV) return (body: null, reason: 'unsupported_enc_v');
    final body = rec.body;
    if (body == null) return (body: null, reason: 'missing_body');
    final keys = await keysFor(rec.keyV);
    if (keys == null) return (body: null, reason: 'unknown_key_version');
    Object? json;
    try {
      json = await openRecord(keys, ctx(type, rec.id, rec.keyV), fromBase64Url(body));
    } on Object {
      return (body: null, reason: 'cannot_open');
    }
    final parsed = parseRecord(type, json);
    if (!parsed.ok) return (body: null, reason: 'invalid');
    return (body: parsed.value, reason: null);
  }

  Future<void> quarantine(_Wire rec, String reason, RecordType type) => store.quarantine(
    QuarantineEntry(id: rec.id, type: type, version: rec.version, reason: reason, keyV: rec.keyV),
  );

  // ---- push ------------------------------------------------------------------------------------

  Future<_Prepared?> prepare(OutboxEntry entry) async {
    final row = await store.rawRecord(entry.type, entry.id);
    if (row == null) {
      // Nothing local to send (should not happen): clear the entry.
      await store.ackOutbox(entry.id, 0, entry.seq);
      return null;
    }
    final deleted = entry.deleted || row.deleted;
    final (:keyV, :keys) = sealingKeys();
    final sealed = deleted
        ? null
        : toBase64Url(await sealRecord(keys, ctx(entry.type, entry.id, keyV), row.body));
    return _Prepared(
      entry: entry,
      body: row.body,
      keyV: keyV,
      size: (sealed?.length ?? 0) + 200,
      change: {
        'id': entry.id,
        'type': entry.type.name,
        'baseVersion': row.version > 0 ? row.version : null,
        'deleted': deleted,
        'keyV': keyV,
        'encV': _encV,
        'body': sealed,
      },
    );
  }

  WriteOptions _remote(_Wire server, OutboxEntry entry) =>
      WriteOptions(origin: 'remote', version: server.version, keyV: server.keyV, ifSeq: entry.seq);

  Future<void> handleConflict(_Prepared p, _Wire server, SyncResult result) async {
    final entry = p.entry;
    final created = p.change['baseVersion'] == null;
    final type = entry.type;
    final row = await store.rawRecord(type, entry.id);
    final remote = _remote(server, entry);
    if (server.deleted) {
      await store.delete(type, entry.id, remote);
      await store.ackOutbox(entry.id, server.version, entry.seq);
      if (!entry.deleted && !entry.reseal) {
        result.serverDeleted.add(entry.id);
        report(SyncProblem(SyncProblemCode.serverDeleted, ids: [entry.id]));
      }
      return;
    }
    if (entry.deleted && !created) {
      // The person's delete wins: keep the server's copy as the base and push the delete again.
      await store.transaction((tx) async {
        await tx.put(type, entry.id, row?.body ?? <String, Object?>{}, remote);
        await tx.delete(type, entry.id, remote);
      });
      result.merged += 1;
      return;
    }
    final opened = await openWire(server);
    final serverBody = opened.body;
    if (serverBody == null) {
      await quarantine(server, opened.reason!, type);
      result.quarantined += 1;
      report(SyncProblem(SyncProblemCode.conflictUnreadable, ids: [entry.id]));
      throw const _Skip('conflict_unreadable');
    }
    if (entry.reseal) {
      // Nothing of ours to keep: the server's copy wins (another device re-sealed or edited it).
      final outbox = await store.readOutbox(_all);
      if (outbox.where((e) => e.id == entry.id).firstOrNull?.seq != entry.seq) {
        // The person edited it since: an ordinary edit now, pushed (and merged) again.
        throw const _Retry();
      }
      await store.put(type, entry.id, serverBody, remote);
      await store.ackOutbox(entry.id, server.version, entry.seq, server.keyV);
      result.merged += 1;
      return;
    }
    if (created) {
      // Two devices created the same deterministic id: the server's copy wins, plus whatever the
      // person changed after the create (a write made while it was in flight).
      await store.adoptServerCopy(
        type,
        entry.id,
        entry.seq,
        ServerCopy(version: server.version, keyV: server.keyV, body: serverBody),
        (local) {
          final touched = changedKeys(p.body, local);
          final rebased = parseRecord(type, _mergeBodies(local, serverBody, touched));
          return rebased.ok
              ? (body: rebased.value!, touched: touched)
              : (body: serverBody, touched: const <String>[]);
        },
      );
      result.merged += 1;
      return;
    }
    final merged = _mergeBodies(row?.body, serverBody, entry.touched);
    final parsed = parseRecord(type, merged);
    // A merge of two valid bodies that is not valid itself: the server's copy is the safe side.
    final next = parsed.ok ? parsed.value! : serverBody;
    await store.put(type, entry.id, next, remote);
    if (_canonical(next) == _canonical(serverBody)) {
      // Nothing of ours differs from the server's copy (two devices made the same record).
      await store.ackOutbox(entry.id, server.version, entry.seq);
    }
    result.merged += 1;
  }

  /// Gives up on [entry] for now; it backs off and is reported. On its fifth failure, for good: it
  /// is abandoned, and [server] (the conflict's copy, when there is one) replaces it at once.
  Future<void> park(OutboxEntry entry, String lastError, SyncResult result, [_Wire? server]) async {
    final attempts = (entry.park?.attempts ?? 0) + 1;
    final park = OutboxPark(
      attempts: attempts,
      lastError: lastError,
      until: now() + _parkDelay(attempts),
    );
    if (attempts < _maxAttempts) {
      await store.parkOutbox(entry.id, entry.seq, park);
      result.parked.add(entry.id);
      return;
    }
    await store.abandonOutbox(entry.id, entry.seq, park);
    result.dropped.add(entry.id);
    if (server == null) return;
    final remote = _remote(server, entry);
    if (server.deleted) {
      await store.delete(entry.type, entry.id, remote);
      return;
    }
    final opened = await openWire(server);
    if (opened.body != null) await store.put(entry.type, entry.id, opened.body!, remote);
  }

  Future<void> push(SyncResult result) async {
    final conflicts = <String, int>{};
    final mismatches = <String, int>{};

    /// The seq of each entry this run is done with: it is sent again only after a newer write.
    final handled = <String, int>{};
    bool due(OutboxEntry e) =>
        e.setAside == null &&
        !e.abandoned &&
        (e.park == null || e.park!.until <= now()) &&
        handled[e.id] != e.seq;

    Future<void> settle(_Prepared p, Map<Object?, Object?>? r) async {
      final entry = p.entry;
      handled[entry.id] = entry.seq;
      if (r == null) {
        await park(entry, 'no_result', result);
      } else if (r['version'] is int) {
        await store.ackOutbox(entry.id, r['version']! as int, entry.seq, p.keyV);
        result.pushed += 1;
      } else if (r['conflict'] is Map) {
        final conflict = _Wire.fromJson(r['conflict']! as Map);
        final count = (conflicts[entry.id] ?? 0) + 1;
        conflicts[entry.id] = count;
        if (count > _maxConflicts) {
          await park(entry, 'conflict_limit', result, conflict);
          return;
        }
        try {
          await handleConflict(p, conflict, result);
          // Still pending after the merge: push it again on the server's version.
          handled.remove(entry.id);
        } on _Retry {
          handled.remove(entry.id);
        } on _Skip catch (skip) {
          await park(entry, skip.lastError, result);
        }
      } else if (r['error'] == 'key_version_mismatch') {
        // The account rotated: seal it again under the new version, once.
        final keyV = (r['keyV'] as int?) ?? 0;
        final count = (mismatches[entry.id] ?? 0) + 1;
        mismatches[entry.id] = count;
        if (count == 1 && keyV > _keyring.current) await refresh(keyV);
        // A refresh that went past the refused version (rotated again) seals under that one.
        if (count == 1 &&
            _keyring.current >= keyV &&
            _keyring.byVersion.containsKey(_keyring.current)) {
          handled.remove(entry.id);
        } else {
          await park(entry, 'key_version_mismatch', result);
        }
      } else {
        // id_taken / not_found: the server will never take this change.
        final row = await store.rawRecord(entry.type, entry.id);
        await store.ackOutbox(entry.id, row?.version ?? 0, entry.seq);
        // A reseal is not the person's change: nothing of theirs was lost.
        if (!entry.reseal) result.dropped.add(entry.id);
      }
    }

    /// Sends a batch; a refused one is bisected (413/422) or parked whole (other 4xx).
    Future<void> send(List<_Prepared> batch) async {
      final Object? response;
      try {
        response = await call(
          '/v2/sync',
          method: 'POST',
          data: {
            'changes': [for (final p in batch) p.change],
          },
        );
      } on _Stop catch (error) {
        if (error.code != SyncProblemCode.rejected) rethrow;
        final code = 'rejected_${error.status}';
        if ((error.status == 413 || error.status == 422) && batch.length > 1) {
          final half = (batch.length + 1) ~/ 2;
          await send(batch.sublist(0, half));
          await send(batch.sublist(half));
          return;
        }
        for (final p in batch) {
          handled[p.entry.id] = p.entry.seq;
          await park(p.entry, code, result);
        }
        return;
      }
      final results = response is Map && response['results'] is List
          ? (response['results']! as List)
          : const [];
      final byId = <Object?, Map<Object?, Object?>>{
        for (final r in results)
          if (r is Map) r['id']: r,
      };
      for (final p in batch) {
        await settle(p, byId[p.entry.id]);
      }
    }

    for (;;) {
      final pending = (await store.readOutbox(_all)).where(due).toList();
      if (pending.isEmpty) return;
      final batch = <_Prepared>[];
      var bytes = 0;
      for (final entry in pending) {
        if (batch.length >= _pushBatch) break;
        final prepared = await prepare(entry);
        if (prepared == null) continue;
        if (batch.isNotEmpty && bytes + prepared.size > _pushBytes) break;
        bytes += prepared.size;
        batch.add(prepared);
      }
      if (batch.isEmpty) continue;
      await send(batch);
    }
  }

  // ---- pull ------------------------------------------------------------------------------------

  Future<void> pull(SyncResult result) async {
    final since0 = ((await store.getMeta('latest')) as int?) ?? 0;
    final base = ((await store.getMeta('base')) as int?) ?? since0;
    final latest = await pullPages(result, since0, base);
    await store.setMeta('latest', latest);
    await store.setMeta('base', latest);
    if (_retryUnknown) await retryQuarantined(result, latest);
    // A resync's set-aside changes, once a whole download has landed.
    final outbox = await store.readOutbox(_all);
    if (outbox.any((e) => e.setAside != null)) await restoreSetAside(result);
  }

  /// The keyring grew (a refresh, or a rotation here): records quarantined earlier as
  /// `unknown_key_version` under a version it now holds are pulled again from the oldest one's
  /// version (base = `latest`, so no resync), applying only those ids.
  Future<void> retryQuarantined(SyncResult result, int latest) async {
    _retryUnknown = false;
    final rows = (await store.quarantined())
        .where(
          (q) =>
              q.reason == 'unknown_key_version' && (q.keyV == null || q.keyV! <= _keyring.current),
        )
        .toList();
    if (rows.isEmpty) return;
    final only = {for (final q in rows) '${q.type.name}:${q.id}'};
    final oldest = rows.map((q) => q.version).reduce((a, b) => a < b ? a : b);
    await pullPages(result, oldest - 1 < 0 ? 0 : oldest - 1, latest, only);
  }

  /// Pulls and applies the pages from [from]; returns the server's `latest`. With [only], applies
  /// just those `type:id`s (a quarantine retry).
  Future<int> pullPages(SyncResult result, int from, int base, [Set<String>? only]) async {
    var since = from;
    var latest = from;
    for (;;) {
      final page = await call(
        '/v2/sync',
        query: {'since': '$since', 'base': '$base', 'limit': '$_pullLimit'},
      );
      if (page is! Map || page['records'] is! List || page['latest'] is! int) {
        throw const _Stop(SyncProblemCode.server, 200);
      }
      final pending = {
        for (final e in await store.readOutbox(_all))
          if (e.setAside == null && !e.abandoned) e.id,
      };
      final apply = <({_Wire rec, RecordType type, Json? body})>[];
      var quarantined = 0;
      for (final raw in page['records']! as List) {
        final rec = _Wire.fromJson(raw as Map);
        if (only != null && !only.contains('${rec.type}:${rec.id}')) continue;
        if (pending.contains(rec.id)) continue; // the push's conflict path merges it
        final type = rec.recordType;
        if (type == null) {
          // Kept with no known type: the quarantine table needs one, so it is counted only.
          quarantined += 1;
        } else if (rec.deleted) {
          apply.add((rec: rec, type: type, body: null));
        } else {
          final opened = await openWire(rec);
          if (opened.body != null) {
            apply.add((rec: rec, type: type, body: opened.body));
          } else {
            await quarantine(rec, opened.reason!, type);
            quarantined += 1;
          }
        }
      }
      if (apply.isNotEmpty) {
        await store.transaction((tx) async {
          for (final (:rec, :type, :body) in apply) {
            // Checked again here: the person may have written it since `pending` was read.
            final remote = WriteOptions(
              origin: 'remote',
              version: rec.version,
              keyV: rec.keyV,
              skipIfPending: true,
            );
            if (body == null) {
              await tx.delete(type, rec.id, remote);
            } else {
              await tx.put(type, rec.id, body, remote);
            }
          }
        });
      }
      result.pulled += apply.length;
      result.quarantined += quarantined;
      if (quarantined > 0) report(SyncProblem(SyncProblemCode.quarantined, count: quarantined));
      latest = page['latest']! as int;
      final next = page['next'];
      if (next is! int) break;
      since = next;
    }
    return latest;
  }

  // ---- key versions ----------------------------------------------------------------------------

  /// After the pull: records under an older key version are sealed again under the current one
  /// (through the outbox, at most [resealLimit] pending), and an old version no local record uses
  /// any more is forgotten.
  Future<void> upgrade(SyncResult result) async {
    final current = _keyring.current;
    if (!_keyring.byVersion.keys.any((v) => v < current)) return;
    if (await store.queueReseal(current, resealLimit) > 0) await push(result);
    final inUse = await store.keyVersionsInUse();
    final unused = [
      for (final v in _keyring.byVersion.keys)
        if (v < current && !inUse.contains(v)) v,
    ];
    if (unused.isEmpty) return;
    for (final v in unused) {
      await o.dropKeyVersion?.call(v);
    }
    _keyring = Keyring(
      current: _keyring.current,
      byVersion: {
        for (final e in _keyring.byVersion.entries)
          if (!unused.contains(e.key)) e.key: e.value,
      },
    );
  }

  /// The server purged tombstones we may have missed: download everything again.
  Future<void> resync(SyncResult result) async {
    // Sets the pending changes aside in the same commit, so a failed download loses nothing.
    await store.wipeRecords();
    result.resynced = true;
    await pull(result);
  }

  /// Writes the set-aside changes again onto the fresh copies: only their touched fields.
  Future<void> restoreSetAside(SyncResult result) async {
    final serverDeleted = <String>[];
    await store.restoreSetAside((entry, fresh) {
      final live = fresh != null && !fresh.deleted ? fresh : null;
      if (entry.deleted) return live != null ? const SetAsideDelete() : const SetAsideDrop();
      final aside = entry.setAside?.body;
      if (aside == null) return const SetAsideDrop();
      if (entry.baseVersion == null) {
        // Never pushed: a create, unless the server has the id (a deterministic id): theirs wins.
        return fresh != null ? const SetAsideDrop() : SetAsidePut(aside);
      }
      if (live == null) {
        // The server deleted it: the deletion wins, and the person is told.
        serverDeleted.add(entry.id);
        return const SetAsideDrop();
      }
      final parsed = parseRecord(entry.type, _mergeBodies(aside, live.body, entry.touched));
      return parsed.ok ? SetAsidePut(parsed.value!) : const SetAsideDrop();
    });
    if (serverDeleted.isNotEmpty) {
      result.serverDeleted.addAll(serverDeleted);
      report(SyncProblem(SyncProblemCode.serverDeleted, ids: serverDeleted));
    }
  }

  // ---- run -------------------------------------------------------------------------------------

  Future<SyncResult> once() async {
    final result = SyncResult();
    try {
      await push(result);
      try {
        await pull(result);
      } on _ResyncRequired {
        await resync(result);
      }
      await upgrade(result);
      await store.setMeta('lastSync', now());
    } on _ResyncRequired {
      // A 410 on the push path cannot happen; treat it as a server problem.
      result
        ..ok = false
        ..error = SyncProblemCode.server;
    } on _Stop catch (stop) {
      result
        ..ok = false
        ..error = stop.code;
      if (stop.code == SyncProblemCode.deviceRemoved ||
          stop.code == SyncProblemCode.keyUnverified) {
        result.problem = stop.code;
      }
      report(SyncProblem(stop.code, status: stop.status));
    } on Object catch (error) {
      if (error is! VaultClosedError && !store.isClosed) rethrow;
      result
        ..ok = false
        ..error = SyncProblemCode.closed;
      report(const SyncProblem(SyncProblemCode.closed));
    }
    if (result.dropped.isNotEmpty) {
      report(SyncProblem(SyncProblemCode.dropped, ids: List.of(result.dropped)));
    }
    if (result.parked.isNotEmpty) {
      report(SyncProblem(SyncProblemCode.parked, ids: result.parked.toSet().toList()));
    }
    return result;
  }

  Future<SyncResult>? _current;
  bool _again = false;

  /// True while a run is in flight: its own commits must not schedule another.
  bool _running = false;

  /// One run's passes as one result: counts added, ids joined, `ok`/`error` of the last.
  SyncResult combine(SyncResult? a, SyncResult b) {
    if (a == null) return b;
    return SyncResult(
      ok: b.ok,
      pushed: a.pushed + b.pushed,
      pulled: a.pulled + b.pulled,
      merged: a.merged + b.merged,
      quarantined: a.quarantined + b.quarantined,
      serverDeleted: [...a.serverDeleted, ...b.serverDeleted],
      dropped: [...a.dropped, ...b.dropped],
      parked: [...a.parked, ...b.parked],
      resynced: a.resynced || b.resynced,
      error: b.error,
      problem: b.problem,
    );
  }

  /// The store's write counter: outbox entries above it were written after this point.
  Future<int> mark() async {
    try {
      return ((await store.getMeta('seq')) as int?) ?? 0;
    } on Object {
      return _all; // closed: `once` reports it
    }
  }

  @override
  Future<SyncResult> run() {
    final inFlight = _current;
    if (inFlight != null) {
      _again = true;
      return inFlight;
    }
    final future = () async {
      _running = true;
      try {
        return await _locked(userId, store, () async {
          // Key refreshes are counted per run, across its passes.
          resetRefreshes();
          SyncResult? last;
          do {
            _again = false;
            final start = await mark();
            last = combine(last, await once());
            // Only what the person wrote during the run gets one more pass: a change left
            // pending (parked, set aside, waiting) waits for the next trigger.
            if (last.ok && !_again) {
              final outbox = await store.readOutbox(_all);
              // The upgrade pass's own entries are not the person's: they wait for the next run.
              if (outbox.any((e) => e.seq > start && !e.reseal)) _again = true;
            }
          } while (_again && last.ok);
          return last;
        });
      } finally {
        _running = false;
        _current = null;
        _afterRun();
      }
    }();
    _current = future;
    return future;
  }

  // ---- triggers --------------------------------------------------------------------------------

  _Triggers? _triggers;

  @override
  void Function() start() {
    _triggers?.stop();
    final triggers = _triggers = _Triggers(this);
    triggers.begin();
    return triggers.stop;
  }

  @override
  void stop() => _triggers?.stop();

  @override
  void afterLocalWrite() => _triggers?.localWrite();

  void _afterRun() => _triggers?.runEnded();

  @override
  void useKeyring(Keyring next) {
    if (next.current < _keyring.current || !next.byVersion.containsKey(next.current)) return;
    if (next.current > _keyring.current) _retryUnknown = true;
    _keyring = next;
  }
}

class _Prepared {
  const _Prepared({
    required this.entry,
    required this.body,
    required this.keyV,
    required this.size,
    required this.change,
  });

  final OutboxEntry entry;

  /// The plaintext sent (a create conflict keeps only what changed after it).
  final Json body;
  final int keyV;
  final int size;
  final Map<String, Object?> change;
}

/// The triggers of one [SyncEngine.start].
class _Triggers {
  _Triggers(this.engine);

  final _Engine engine;
  bool stopped = false;
  int failures = 0;
  Timer? debounce;
  Timer? retry;
  Timer? interval;
  void Function()? unwatch;

  /// A local write landed while a run was in flight: one more run once it ends.
  bool wroteDuringRun = false;

  SyncEngineOptions get o => engine.o;

  bool foreground() {
    final custom = o.isForeground;
    if (custom != null) return custom();
    try {
      final state = WidgetsBinding.instance.lifecycleState;
      return state == null || state == AppLifecycleState.resumed;
    } on Object {
      return true;
    }
  }

  void begin() {
    final watch = o.watchResume ?? _watchLifecycle;
    unwatch = watch(trigger);
    interval = Timer.periodic(o.interval, (_) {
      if (foreground()) trigger();
    });
    trigger();
  }

  void trigger() {
    if (stopped) return;
    engine.run().then(
      (result) {
        if (stopped) return;
        retry?.cancel();
        if (result.ok) {
          failures = 0;
        } else if (result.error == SyncProblemCode.sessionChanged ||
            result.error == SyncProblemCode.deviceRemoved ||
            result.error == SyncProblemCode.keyUnverified) {
          // Someone else's session, this phone removed, or a key it cannot verify: never again.
          stop();
        } else if (result.error != SyncProblemCode.closed) {
          failures += 1;
          final ms = 2000 * (1 << (failures - 1 > 10 ? 10 : failures - 1));
          retry = Timer(Duration(milliseconds: ms < 300000 ? ms : 300000), trigger);
        }
      },
      onError: (Object _) {
        // a bug in the engine must not stop the timers; the next trigger tries again
      },
    );
  }

  void localWrite() {
    if (stopped) return;
    if (engine._running) {
      wroteDuringRun = true;
      return;
    }
    schedule();
  }

  void schedule() {
    debounce?.cancel();
    debounce = Timer(o.debounce, trigger);
  }

  void runEnded() {
    if (!wroteDuringRun) return;
    wroteDuringRun = false;
    if (!stopped) schedule();
  }

  void stop() {
    if (stopped) return;
    stopped = true;
    debounce?.cancel();
    retry?.cancel();
    interval?.cancel();
    unwatch?.call();
    unwatch = null;
  }
}

/// Return to the foreground, through [AppLifecycleListener]; nothing without a Flutter binding.
void Function() _watchLifecycle(void Function() onResume) {
  try {
    final listener = AppLifecycleListener(onResume: onResume);
    return listener.dispose;
  } on Object {
    return () {};
  }
}

Object? _decode(Object? data) {
  if (data is String && data.isNotEmpty) {
    try {
      return jsonDecode(data);
    } on FormatException {
      return data;
    }
  }
  return data;
}

/// The problem's `code`, if the body has one.
String? _problemCode(Object? body) =>
    body is Map && body['code'] is String ? body['code']! as String : null;

/// A failed key refresh as the run's stop.
_Stop _keysStop(Object error) {
  if (error is _Stop) return error;
  if (error is KeysError) {
    return switch (error.code) {
      'device_removed' => const _Stop(SyncProblemCode.deviceRemoved),
      'tampered' => const _Stop(SyncProblemCode.keyUnverified),
      'session_changed' => const _Stop(SyncProblemCode.sessionChanged, 409),
      'offline' => const _Stop(SyncProblemCode.offline),
      _ => _Stop(SyncProblemCode.server, error.status),
    };
  }
  if (error is VaultClosedError) throw error;
  return const _Stop(SyncProblemCode.server);
}
