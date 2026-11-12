import '../core/records.dart' show Json;
import '../crypto/records.dart' show RecordType;

/// A record as the store holds it: the envelope's `id` and `deleted`, and the plaintext body.
class StoredRecord {
  const StoredRecord({required this.id, required this.body, required this.deleted});

  final String id;
  final Json body;

  /// A tombstone: the body is kept so that a restore is a plain `put`.
  final bool deleted;
}

class ReadOptions {
  const ReadOptions({this.includeDeleted = false});

  /// Also return tombstones. Default: live records only.
  final bool includeDeleted;
}

class WriteOptions {
  const WriteOptions({
    this.origin = 'local',
    this.version,
    this.keyV,
    this.skipIfPending = false,
    this.ifSeq,
  });

  /// Who is writing. `'local'` (default) is the person's own change; the encrypted store adds it
  /// to the outbox. `'remote'` is the sync engine storing what the server sent: no outbox entry.
  final String origin;

  /// Remote writes only: the server version and key version of the copy being stored.
  final int? version;
  final int? keyV;

  /// Remote writes only: skip the write when the id has a pending local change (an outbox entry
  /// that is not set aside). Checked inside the write's own transaction.
  final bool skipIfPending;

  /// Remote writes only: apply only while the id's outbox entry is the local write numbered
  /// `ifSeq`; a newer local write makes it a no-op.
  final int? ifSeq;
}

/// Reads and writes, shared by the store and by the transaction handed to `transaction(fn)`.
abstract interface class StoreOps {
  Future<StoredRecord?> get(RecordType type, String id, [ReadOptions opts]);

  /// In the order the records were first written.
  Future<List<StoredRecord>> list(RecordType type, [ReadOptions opts]);

  /// Creates or replaces the record, and revives it if it was deleted.
  Future<void> put(RecordType type, String id, Json body, [WriteOptions opts]);

  /// A no-op for an id the store does not know.
  Future<void> delete(RecordType type, String id, [WriteOptions opts]);
}

/// The person's records, keyed by type and id. Indexes (a month's transactions, say) are the
/// caller's to compute from `list`.
abstract interface class FinanceStore implements StoreOps {
  /// Runs [fn] as one atomic unit: its writes commit together when it completes, and none do if
  /// it throws. Reads inside see its own writes. Transactions never overlap.
  Future<R> transaction<R>(Future<R> Function(StoreOps tx) fn);

  /// Called after every commit (local or remote). Returns the unsubscribe function.
  void Function() subscribe(void Function() listener);
}
