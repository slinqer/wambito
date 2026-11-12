import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/records.dart' show Json;
import '../crypto/records.dart' show RecordType;
import 'db.dart';
import 'store.dart';

export 'db.dart'
    show OutboxEntry, OutboxPark, QuarantineEntry, RawRecord, SetAside, deleteVault, vaultFileName;

/// Thrown by every operation once the store is closed. The session must reopen or sign out.
class VaultClosedError implements Exception {
  const VaultClosedError();

  final String code = 'vault_closed';

  @override
  String toString() => 'VaultClosedError: The vault is closed';
}

/// What `restoreSetAside` does with one set-aside change.
sealed class SetAsideOutcome {
  const SetAsideOutcome();
}

/// Write [body] as a local write: the outbox entry pushes it as an edit of the fresh copy.
class SetAsidePut extends SetAsideOutcome {
  const SetAsidePut(this.body);
  final Json body;
}

/// Delete the record as a local write.
class SetAsideDelete extends SetAsideOutcome {
  const SetAsideDelete();
}

/// Forget the change.
class SetAsideDrop extends SetAsideOutcome {
  const SetAsideDrop();
}

/// The server's copy of a record, for `adoptServerCopy`.
class ServerCopy {
  const ServerCopy({required this.version, required this.keyV, required this.body});

  final int version;
  final int keyV;
  final Json body;
}

/// What the person's later edits keep on top of the server's copy.
typedef Rebased = ({Json body, List<String> touched});

bool _same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

/// The fields whose value differs between two bodies (all of the new body's when there is no old).
List<String> changedKeys(Json? prev, Json? next) {
  final a = prev ?? const <String, Object?>{};
  final b = next ?? const <String, Object?>{};
  return [
    for (final key in {...a.keys, ...b.keys})
      if (prev == null || !_same(a[key], b[key])) key,
  ];
}

Json _decode(Object? text) => (jsonDecode(text! as String) as Map).cast<String, Object?>();

class _Row {
  _Row(Map<String, Object?> r)
    : id = r['id']! as String,
      seq = r['seq']! as int,
      body = r['body']! as String,
      deleted = r['deleted'] == 1,
      version = r['version']! as int,
      keyV = r['key_v']! as int;

  final String id;
  final int seq;
  final String body;
  final bool deleted;
  final int version;
  final int keyV;

  Json get json => _decode(body);
}

OutboxEntry _entryOf(Map<String, Object?> r) {
  final aside = r['set_aside'] as String?;
  final park = r['park'] as String?;
  return OutboxEntry(
    id: r['id']! as String,
    type: RecordType.values.byName(r['type']! as String),
    baseVersion: r['base_version'] as int?,
    deleted: r['deleted'] == 1,
    touched: (jsonDecode(r['touched']! as String) as List).cast<String>(),
    seq: r['seq']! as int,
    park: park == null ? null : OutboxPark.fromJson(_decode(park)),
    abandoned: r['abandoned'] == 1,
    setAside: aside == null
        ? null
        : SetAside(((jsonDecode(aside) as Map)['body'] as Map?)?.cast<String, Object?>()),
    reseal: r['reseal'] == 1,
  );
}

Map<String, Object?> _outboxValues(OutboxEntry e) => {
  'id': e.id,
  'type': e.type.name,
  'base_version': e.baseVersion,
  'deleted': e.deleted ? 1 : 0,
  'touched': jsonEncode(e.touched),
  'seq': e.seq,
  'park': e.park == null ? null : jsonEncode(e.park!.toJson()),
  'abandoned': e.abandoned ? 1 : 0,
  'set_aside': e.setAside == null ? null : jsonEncode({'body': e.setAside!.body}),
  'reseal': e.reseal ? 1 : 0,
};

Map<String, Object?> _recordValues(
  RecordType type,
  String id,
  Json body, {
  required bool deleted,
  required int version,
  required int keyV,
  required int seq,
}) {
  final date = body['date'];
  final category = body['categoryId'];
  final amount = body['amount'];
  return {
    'id': id,
    'seq': seq,
    'body': jsonEncode(body),
    'deleted': deleted ? 1 : 0,
    'version': version,
    'key_v': keyV,
    if (type == RecordType.transaction) ...{
      'date': date is String ? date : null,
      'category_id': category is String ? category : null,
      'amount': amount is int ? amount : null,
    },
  };
}

Future<int> _nextSeq(DatabaseExecutor db) async {
  final n = ((await _meta(db, 'seq')) as int?) ?? 0;
  await _setMeta(db, 'seq', n + 1);
  return n + 1;
}

Future<Object?> _meta(DatabaseExecutor db, String key) async {
  final rows = await db.query(metaTable, where: 'key = ?', whereArgs: [key]);
  if (rows.isEmpty) return null;
  return jsonDecode(rows.first['value']! as String);
}

Future<void> _setMeta(DatabaseExecutor db, String key, Object? value) => db.insert(metaTable, {
  'key': key,
  'value': jsonEncode(value),
}, conflictAlgorithm: ConflictAlgorithm.replace);

Future<_Row?> _row(DatabaseExecutor db, RecordType type, String id) async {
  final rows = await db.query(quoted(recordTable(type)), where: 'id = ?', whereArgs: [id]);
  return rows.isEmpty ? null : _Row(rows.first);
}

Future<OutboxEntry?> _outboxEntry(DatabaseExecutor db, String id) async {
  final rows = await db.query(outboxTable, where: 'id = ?', whereArgs: [id]);
  return rows.isEmpty ? null : _entryOf(rows.first);
}

Future<void> _putOutbox(DatabaseExecutor db, OutboxEntry e) =>
    db.insert(outboxTable, _outboxValues(e), conflictAlgorithm: ConflictAlgorithm.replace);

Future<void> _deleteOutbox(DatabaseExecutor db, String id) =>
    db.delete(outboxTable, where: 'id = ?', whereArgs: [id]);

/// A [FinanceStore] over SQLite (the phone's encrypted vault), plus what the sync engine needs:
/// the Dart twin of `apps/web/app/local/encrypted-store.ts`. A local write updates the record and
/// the outbox in one SQLite transaction; `origin: 'remote'` writes (sync) take `version` and `keyV`
/// and add no outbox entry. Subscribers fire after every commit that wrote.
///
/// Every operation runs on one in-process queue, so SQLite transactions never overlap (sqflite
/// transactions must not await foreign async work): do not call the store from inside the
/// function handed to [transaction]; use the [StoreOps] it gets.
///
/// Not ported from the web's store: the BroadcastChannel across tabs and `versionchange` (the phone
/// has one process), `migrateLegacyKeys` and the `keys` store (the keys live in secure storage).
class SqliteStore implements FinanceStore {
  SqliteStore._(this._db);

  /// Opens the vault of [userId]. [directory] and [factory] are for tests; the app leaves them out.
  static Future<SqliteStore> open(
    String userId, {
    String? directory,
    DatabaseFactory? factory,
  }) async => SqliteStore._(await openVault(userId, directory: directory, factory: factory));

  final Database _db;
  final Set<void Function()> _listeners = {};
  final Set<void Function()> _closedListeners = {};
  Future<void> _queue = Future<void>.value();
  Future<void>? _closing;
  bool _closed = false;

  bool get isClosed => _closed;

  void _guard() {
    if (_closed) throw const VaultClosedError();
  }

  Future<R> _enqueue<R>(Future<R> Function() job) {
    final next = _queue.then((_) {
      _guard();
      return job();
    });
    _queue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  void _fire() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// A read-write unit: the SQLite transaction commits when [fn] completes, rolls back if it
  /// throws, and subscribers hear of it after the commit when it wrote.
  Future<R> _write<R>(Future<R> Function(_Ops ops) fn) => _enqueue(() async {
    final wrote = _Wrote();
    final result = await _db.transaction((txn) => fn(_Ops(txn, wrote)));
    if (wrote.value) _fire();
    return result;
  });

  @override
  Future<StoredRecord?> get(RecordType type, String id, [ReadOptions opts = const ReadOptions()]) =>
      _write((o) => o.get(type, id, opts));

  @override
  Future<List<StoredRecord>> list(RecordType type, [ReadOptions opts = const ReadOptions()]) =>
      _write((o) => o.list(type, opts));

  @override
  Future<void> put(
    RecordType type,
    String id,
    Json body, [
    WriteOptions opts = const WriteOptions(),
  ]) => _write((o) => o.put(type, id, body, opts));

  @override
  Future<void> delete(RecordType type, String id, [WriteOptions opts = const WriteOptions()]) =>
      _write((o) => o.delete(type, id, opts));

  @override
  Future<R> transaction<R>(Future<R> Function(StoreOps tx) fn) => _write(fn);

  @override
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// The record with its server version and key version (tombstones included).
  Future<RawRecord?> rawRecord(RecordType type, String id) => _enqueue(() async {
    final row = await _row(_db, type, id);
    if (row == null) return null;
    return RawRecord(
      id: id,
      body: row.json,
      deleted: row.deleted,
      version: row.version,
      keyV: row.keyV,
    );
  });

  /// The pending changes, oldest first.
  Future<List<OutboxEntry>> readOutbox(int limit) => _enqueue(() async {
    final rows = await _db.query(outboxTable, orderBy: 'seq', limit: limit);
    return rows.map(_entryOf).toList();
  });

  /// The server accepted the change read as [seq] and gave it [version] (sealed under [keyV], when
  /// given). Records them, and clears the entry only if there was no newer local write since;
  /// otherwise the entry stays, now based on [version].
  Future<void> ackOutbox(String id, int version, int seq, [int? keyV]) => _enqueue(
    () => _db.transaction((txn) async {
      final entry = await _outboxEntry(txn, id);
      if (entry == null) return;
      final row = await _row(txn, entry.type, id);
      if (row != null) {
        await txn.update(
          quoted(recordTable(entry.type)),
          {'version': version, 'key_v': keyV ?? row.keyV},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      if (entry.seq == seq) {
        await _deleteOutbox(txn, id);
      } else {
        await _putOutbox(txn, entry.copyWith(baseVersion: version));
      }
    }),
  );

  /// The upgrade pass: adds a `reseal` outbox entry (no body change, based on the record's version)
  /// for pushed, live records sealed under a key version below [current] and with no outbox entry,
  /// until [limit] reseal entries are pending. Returns how many it added. Notifies nobody.
  Future<int> queueReseal(int current, int limit) => _enqueue(
    () => _db.transaction((txn) async {
      final entries = (await txn.query(outboxTable)).map(_entryOf).toList();
      final pending = {for (final e in entries) e.id};
      var room = limit - entries.where((e) => e.reseal).length;
      var seq = ((await _meta(txn, 'seq')) as int?) ?? 0;
      var added = 0;
      for (final type in RecordType.values) {
        if (room <= 0) break;
        final rows = await txn.query(quoted(recordTable(type)), orderBy: 'seq');
        for (final r in rows.map(_Row.new)) {
          if (room <= 0) break;
          if (r.deleted || r.version == 0 || r.keyV >= current || pending.contains(r.id)) {
            continue;
          }
          await _putOutbox(
            txn,
            OutboxEntry(
              id: r.id,
              type: type,
              baseVersion: r.version,
              deleted: false,
              touched: const [],
              seq: ++seq,
              reseal: true,
            ),
          );
          room -= 1;
          added += 1;
        }
      }
      if (added > 0) await _setMeta(txn, 'seq', seq);
      return added;
    }),
  );

  /// The key versions the server copies of the local records (live, pushed) are under, and those
  /// of quarantined records (they may still be retried).
  Future<Set<int>> keyVersionsInUse() => _enqueue(() async {
    final versions = <int>{};
    for (final type in RecordType.values) {
      final rows = await _db.query(
        quoted(recordTable(type)),
        columns: ['key_v'],
        where: 'deleted = 0 AND version > 0',
      );
      for (final r in rows) {
        versions.add(r['key_v']! as int);
      }
    }
    final held = await _db.query(quarantineTable, columns: ['key_v'], where: 'key_v IS NOT NULL');
    for (final r in held) {
      versions.add(r['key_v']! as int);
    }
    return versions;
  });

  /// The engine gives up on the change read as [seq] for now: stores [park] on it. A no-op when a
  /// newer local write replaced it.
  Future<void> parkOutbox(String id, int seq, OutboxPark park) => _enqueue(
    () => _db.transaction((txn) async {
      final entry = await _outboxEntry(txn, id);
      if (entry?.seq == seq) await _putOutbox(txn, entry!.copyWith(park: park));
    }),
  );

  /// The engine gives up on the change read as [seq] for good: stores [park] and `abandoned`, so
  /// it is never pushed again and remote writes of the id go through (and remove the entry).
  Future<void> abandonOutbox(String id, int seq, OutboxPark park) => _enqueue(
    () => _db.transaction((txn) async {
      final entry = await _outboxEntry(txn, id);
      if (entry?.seq == seq) {
        await _putOutbox(txn, entry!.copyWith(park: park, abandoned: true));
      }
    }),
  );

  /// A create (pushed as [seq]) lost to the server's copy of the same id. Without a newer local
  /// write, the server's copy replaces the record and the entry goes. With one, the server's copy
  /// becomes the base and `rebase(localBody)` says what to keep: the body and the fields changed
  /// after the create (`touched`; none: the entry goes). One commit; notifies subscribers.
  Future<void> adoptServerCopy(
    RecordType type,
    String id,
    int seq,
    ServerCopy server,
    Rebased Function(Json? local) rebase,
  ) => _enqueue(() async {
    await _db.transaction((txn) async {
      final entry = await _outboxEntry(txn, id);
      if (entry == null) return;
      final row = await _row(txn, type, id);
      final n = row?.seq ?? await _nextSeq(txn);
      Future<void> store(Json body, bool deleted) => txn.insert(
        quoted(recordTable(type)),
        _recordValues(
          type,
          id,
          body,
          deleted: deleted,
          version: server.version,
          keyV: server.keyV,
          seq: n,
        ),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (entry.seq == seq) {
        await store(server.body, false);
        await _deleteOutbox(txn, id);
      } else if (entry.deleted) {
        // Deleted since: the delete is pushed as an edit of the server's copy.
        await store(server.body, true);
        await _putOutbox(txn, entry.copyWith(baseVersion: server.version, touched: const []));
      } else {
        final rebased = rebase(row?.json);
        await store(rebased.body, false);
        if (rebased.touched.isEmpty) {
          await _deleteOutbox(txn, id);
        } else {
          await _putOutbox(
            txn,
            entry.copyWith(baseVersion: server.version, touched: rebased.touched),
          );
        }
      }
    });
    _fire();
  });

  Future<Object?> getMeta(String key) => _enqueue(() => _meta(_db, key));

  Future<void> setMeta(String key, Object? value) => _enqueue(() => _setMeta(_db, key, value));

  /// Keeps a record that could not be opened; a later remote write of the id clears its rows.
  Future<void> quarantine(QuarantineEntry e) => _enqueue(
    () => _db.insert(quarantineTable, {
      'type': e.type.name,
      'id': e.id,
      'version': e.version,
      'reason': e.reason,
      'key_v': e.keyV,
    }, conflictAlgorithm: ConflictAlgorithm.replace),
  );

  /// Every quarantine row (the sync retries the `unknown_key_version` ones after a refresh).
  Future<List<QuarantineEntry>> quarantined() => _enqueue(() async {
    final rows = await _db.query(quarantineTable);
    return [
      for (final r in rows)
        QuarantineEntry(
          id: r['id']! as String,
          type: RecordType.values.byName(r['type']! as String),
          version: r['version']! as int,
          reason: r['reason']! as String,
          keyV: r['key_v'] as int?,
        ),
    ];
  });

  Future<int> quarantineCount() => _enqueue(
    () async => Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM $quarantineTable'))!,
  );

  /// The server asked for a resync: forgets every record, the quarantine and the `latest` and
  /// `base` cursors. `keyV`, `userId` and the outbox stay; in the same commit every outbox entry
  /// is set aside with its current body (`setAside`), so no pending change is lost if the download
  /// fails. Notifies subscribers.
  Future<void> wipeRecords() => _enqueue(() async {
    await _db.transaction((txn) async {
      for (final entry in (await txn.query(outboxTable)).map(_entryOf)) {
        if (entry.setAside != null) continue;
        if (entry.abandoned) {
          // Given up on: the full download brings the server's copy.
          await _deleteOutbox(txn, entry.id);
          continue;
        }
        final row = await _row(txn, entry.type, entry.id);
        await _putOutbox(txn, entry.copyWith(setAside: SetAside(row?.json)));
      }
      for (final type in RecordType.values) {
        await txn.delete(quoted(recordTable(type)));
      }
      await txn.delete(quarantineTable);
      await txn.delete(metaTable, where: 'key IN (?, ?)', whereArgs: ['latest', 'base']);
    });
    _fire();
  });

  /// After the full download: for each set-aside change, [resolve] (synchronous) gets the entry
  /// and the fresh record (if any) and says what to write. All of it in one commit; the entries
  /// come back as ordinary pending changes based on the fresh version, or are removed.
  Future<void> restoreSetAside(
    SetAsideOutcome Function(OutboxEntry entry, RawRecord? fresh) resolve,
  ) => _write((ops) async {
    final aside = await ops.pendingAside()
      ..sort((x, y) => x.entry.seq.compareTo(y.entry.seq));
    for (final item in aside) {
      await ops.restore(item.entry, resolve(item.entry, item.fresh));
    }
  });

  /// Closes the database; every later operation rejects with [VaultClosedError]. Completes when
  /// the file is released (queued work first).
  Future<void> close() {
    if (_closed) return _closing!;
    _closed = true;
    for (final listener in List.of(_closedListeners)) {
      try {
        listener();
      } catch (_) {
        // a listener must not stop the others
      }
    }
    final closing = _queue.then((_) => _db.close());
    _queue = closing.then<void>((_) {}, onError: (Object _) {});
    return _closing = closing;
  }

  /// Called once when the store closes. Returns the unsubscribe function.
  void Function() onClosed(void Function() listener) {
    _closedListeners.add(listener);
    return () => _closedListeners.remove(listener);
  }
}

class _Wrote {
  bool value = false;
}

class _Aside {
  _Aside(this.entry, this.fresh);
  final OutboxEntry entry;
  final RawRecord? fresh;
}

/// The reads and writes of one open SQLite transaction.
class _Ops implements StoreOps {
  _Ops(this._txn, this._wrote);

  final Transaction _txn;
  final _Wrote _wrote;

  @override
  Future<StoredRecord?> get(
    RecordType type,
    String id, [
    ReadOptions opts = const ReadOptions(),
  ]) async {
    final row = await _row(_txn, type, id);
    if (row == null || (row.deleted && !opts.includeDeleted)) return null;
    return StoredRecord(id: id, body: row.json, deleted: row.deleted);
  }

  @override
  Future<List<StoredRecord>> list(RecordType type, [ReadOptions opts = const ReadOptions()]) async {
    final rows = await _txn.query(
      quoted(recordTable(type)),
      where: opts.includeDeleted ? null : 'deleted = 0',
      orderBy: 'seq',
    );
    return [
      for (final r in rows.map(_Row.new)) StoredRecord(id: r.id, body: r.json, deleted: r.deleted),
    ];
  }

  /// Remote writes: whether `skipIfPending` / `ifSeq` say to leave the record alone.
  Future<bool> _remoteBlocked(String id, WriteOptions opts) async {
    if (!opts.skipIfPending && opts.ifSeq == null) return false;
    final entry = await _outboxEntry(_txn, id);
    if (opts.ifSeq != null) return entry?.seq != opts.ifSeq;
    return entry != null && entry.setAside == null && !entry.abandoned;
  }

  /// A remote write landed: an abandoned change of the id is done with, and the server's copy
  /// opened, so the id's quarantine rows (older copies that did not) are too.
  Future<void> _clearAbandoned(RecordType type, String id) async {
    final entry = await _outboxEntry(_txn, id);
    if (entry != null && entry.abandoned) await _deleteOutbox(_txn, id);
    await _txn.delete(quarantineTable, where: 'type = ? AND id = ?', whereArgs: [type.name, id]);
  }

  Future<void> _outboxFor(
    RecordType type,
    String id,
    _Row? prev,
    bool deleted,
    List<String> touched,
    Json? body, [
    OutboxEntry? restoring,
  ]) async {
    // Restoring a set-aside change: it starts over from the fresh copy, keeping its fields.
    final existing = restoring ?? await _outboxEntry(_txn, id);
    final base = existing != null && restoring == null
        ? existing.baseVersion
        : (prev != null && prev.version > 0 ? prev.version : null);
    var entry = OutboxEntry(
      id: id,
      type: type,
      baseVersion: base,
      // The latest write decides: a put after a delete is a restore.
      deleted: deleted,
      touched: {...?existing?.touched, ...touched}.toList(),
      seq: await _nextSeq(_txn),
      // No `park`: a new local write is tried again at once.
    );
    final aside = existing?.setAside;
    if (aside != null && restoring == null) {
      // Still waiting for the resync's download: keep the set-aside body current.
      final kept = {...?aside.body};
      final next = body ?? const <String, Object?>{};
      for (final key in touched) {
        kept[key] = next[key];
      }
      entry = entry.copyWith(setAside: SetAside(kept));
    }
    await _putOutbox(_txn, entry);
  }

  @override
  Future<void> put(
    RecordType type,
    String id,
    Json body, [
    WriteOptions opts = const WriteOptions(),
  ]) async {
    final remote = opts.origin == 'remote';
    if (remote && await _remoteBlocked(id, opts)) return;
    final prev = await _row(_txn, type, id);
    await _txn.insert(
      quoted(recordTable(type)),
      _recordValues(
        type,
        id,
        body,
        deleted: false,
        version: remote ? (opts.version ?? prev?.version ?? 0) : (prev?.version ?? 0),
        keyV: remote ? (opts.keyV ?? prev?.keyV ?? 1) : (prev?.keyV ?? 1),
        seq: prev?.seq ?? await _nextSeq(_txn),
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _wrote.value = true;
    if (remote) {
      await _clearAbandoned(type, id);
    } else {
      await _outboxFor(type, id, prev, false, changedKeys(prev?.json, body), body);
    }
  }

  @override
  Future<void> delete(
    RecordType type,
    String id, [
    WriteOptions opts = const WriteOptions(),
  ]) async {
    final prev = await _row(_txn, type, id);
    final remote = opts.origin == 'remote';
    if (prev == null) {
      // A tombstone of a record this phone never opened: its quarantine rows go.
      if (remote) await _clearAbandoned(type, id);
      return;
    }
    if (!remote && prev.deleted) return;
    if (remote && await _remoteBlocked(id, opts)) return;
    await _txn.update(
      quoted(recordTable(type)),
      {
        'deleted': 1,
        'version': remote ? (opts.version ?? prev.version) : prev.version,
        'key_v': remote ? (opts.keyV ?? prev.keyV) : prev.keyV,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _wrote.value = true;
    if (remote) {
      await _clearAbandoned(type, id);
    } else {
      await _outboxFor(type, id, prev, true, const [], prev.json);
    }
  }

  Future<List<_Aside>> pendingAside() async {
    final out = <_Aside>[];
    for (final entry in (await _txn.query(outboxTable)).map(_entryOf)) {
      if (entry.setAside == null) continue;
      final row = await _row(_txn, entry.type, entry.id);
      out.add(
        _Aside(
          entry,
          row == null
              ? null
              : RawRecord(
                  id: row.id,
                  body: row.json,
                  deleted: row.deleted,
                  version: row.version,
                  keyV: row.keyV,
                ),
        ),
      );
    }
    return out;
  }

  Future<void> restore(OutboxEntry entry, SetAsideOutcome outcome) async {
    final prev = await _row(_txn, entry.type, entry.id);
    final table = quoted(recordTable(entry.type));
    switch (outcome) {
      case SetAsideDrop():
      case SetAsideDelete() when prev == null || prev.deleted:
        await _deleteOutbox(_txn, entry.id);
        return;
      case SetAsideDelete():
        await _txn.update(table, {'deleted': 1}, where: 'id = ?', whereArgs: [entry.id]);
        await _outboxFor(entry.type, entry.id, prev, true, const [], prev?.json, entry);
      case SetAsidePut(:final body):
        await _txn.insert(
          table,
          _recordValues(
            entry.type,
            entry.id,
            body,
            deleted: false,
            version: prev?.version ?? 0,
            keyV: prev?.keyV ?? 1,
            seq: prev?.seq ?? await _nextSeq(_txn),
          ),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _outboxFor(
          entry.type,
          entry.id,
          prev,
          false,
          changedKeys(prev?.json, body),
          body,
          entry,
        );
    }
    _wrote.value = true;
  }
}
