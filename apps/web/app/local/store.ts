import type { RecordBodies, RecordType } from "@wambito/core";

export type { RecordBodies, RecordType };

/** A record as the store holds it: the envelope's `id` and `deleted`, and the plaintext body. */
export interface StoredRecord<T extends RecordType> {
  id: string;
  body: RecordBodies[T];
  /** A tombstone: the body is kept so that a restore is a plain `put`. */
  deleted: boolean;
}

export interface ReadOptions {
  /** Also return tombstones. Default: live records only. */
  includeDeleted?: boolean;
}

export interface WriteOptions {
  /**
   * Who is writing. `"local"` (default) is the person's own change; the encrypted store adds it to
   * the outbox. `"remote"` is the sync engine storing what the server sent: no outbox entry.
   */
  origin?: "local" | "remote";
  /** Remote writes only: the server version and key version of the copy being stored. */
  version?: number;
  keyV?: number;
}

/** Reads and writes, shared by the store and by the transaction handed to `transaction(fn)`. */
export interface StoreOps {
  get<T extends RecordType>(
    type: T,
    id: string,
    opts?: ReadOptions,
  ): Promise<StoredRecord<T> | undefined>;
  /** In the order the records were first written. */
  list<T extends RecordType>(type: T, opts?: ReadOptions): Promise<StoredRecord<T>[]>;
  /** Creates or replaces the record, and revives it if it was deleted. */
  put<T extends RecordType>(
    type: T,
    id: string,
    body: RecordBodies[T],
    opts?: WriteOptions,
  ): Promise<void>;
  /** A no-op for an id the store does not know. */
  delete(type: RecordType, id: string, opts?: WriteOptions): Promise<void>;
}

/**
 * The person's records, keyed by type and id. Everything is async because the encrypted store sits
 * on IndexedDB. Indexes (a month's transactions, say) are the caller's to compute from `list`.
 */
export interface FinanceStore extends StoreOps {
  /**
   * Runs `fn` as one atomic unit: its writes commit together when it resolves, and none do if it
   * throws. Reads inside see its own writes. Transactions never overlap. Do not await anything
   * foreign inside `fn` (an IndexedDB transaction closes when idle).
   */
  transaction<R>(fn: (tx: StoreOps) => Promise<R>): Promise<R>;
  /** Called after every commit (local or remote). Returns the unsubscribe function. */
  subscribe(listener: () => void): () => void;
}
