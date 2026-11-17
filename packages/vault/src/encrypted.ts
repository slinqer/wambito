import type { RecordBodies, RecordType } from "@wambito/core";
import type { FinanceStore } from "./store.ts";

/** A local change waiting to be pushed: one entry per record id. */
export interface OutboxEntry {
  id: string;
  type: RecordType;
  /** The server version the change is based on; `null` for a record the server has never seen. */
  baseVersion: number | null;
  deleted: boolean;
  /** Body fields changed since the last push (the union over merged writes). */
  touched: string[];
  /** Bumped by every local write: the engine acks only the write it read. */
  seq: number;
  /**
   * Set by the engine when this write keeps failing (rejected, unreadable conflict, no result):
   * it is not pushed again before `until`. Any local write of the id clears it.
   */
  park?: OutboxPark;
  /**
   * Set when the engine gave up on this write (refused 5 times): it is never pushed again and no
   * longer stops pulls from writing the record; the server's copy replaces it, and the entry goes
   * once that copy is applied. Any local write of the id clears it (and tries again).
   */
  abandoned?: true;
  /**
   * Set by a resync's wipe, in the same commit: the local body at that moment (`null` when there
   * was no row). The change is not pushed while set aside; after the full download it is written
   * again onto the fresh server copy (only the `touched` fields), and this is cleared.
   */
  setAside?: { body: unknown };
  /**
   * Added by the sync engine's upgrade pass, never by a local write: the record's unchanged body,
   * to be sealed again under the current key version (`baseVersion` = its version). A conflict
   * takes the server's copy. A local write of the id turns it into an ordinary edit.
   */
  reseal?: true;
}

export interface OutboxPark {
  attempts: number;
  /** A short code (`rejected_422`, `conflict_unreadable`, ...), never a body. */
  lastError: string;
  /** Epoch ms before which the engine does not push it again. */
  until: number;
}

/** A record that failed to open or validate: counted, never shown, never overwritten. */
export interface QuarantineEntry {
  id: string;
  type: RecordType;
  version: number;
  reason: string;
  /** The key version it was sealed under (absent on rows from before stage 2b's fixes). */
  keyV?: number;
}

/** What the sync engine reads about a record: the plaintext and its envelope. */
export interface RawRecord<T extends RecordType = RecordType> {
  id: string;
  body: RecordBodies[T];
  deleted: boolean;
  version: number;
  keyV: number;
  /**
   * A tombstone whose server copy has no body as far as this device knows (the local body is a
   * stale copy): a server body arriving for it replaces it.
   */
  bodiless?: true;
}

/**
 * Thrown by every operation once the store is closed: by `close()`, or because another tab
 * deleted or upgraded the vault (`versionchange`). The session must reopen or sign out.
 */
export class VaultClosedError extends Error {
  readonly code = "vault_closed";
  constructor() {
    super("The vault is closed");
    this.name = "VaultClosedError";
  }
}

/** What `restoreSetAside` does with one set-aside change. */
export type SetAsideOutcome =
  /** Write `put` as a local write: the outbox entry pushes it as an edit of the fresh copy. */
  | { put: unknown }
  /** Delete the record as a local write. */
  | { delete: true }
  /** Forget the change. */
  | { drop: true };

/** A `FinanceStore` with the outbox, quarantine, meta and keys, what the sync engine and the key setup need. */
export interface EncryptedStore extends FinanceStore {
  /** The record with its server version and key version (tombstones included). */
  getRaw<T extends RecordType>(type: T, id: string): Promise<RawRecord<T> | undefined>;
  /** The pending changes, oldest first. */
  readOutbox(limit: number): Promise<OutboxEntry[]>;
  /**
   * The server accepted the change read as `seq` and gave it `version` (sealed under `keyV`, when
   * given). Records them, and clears the entry only if there was no newer local write since;
   * otherwise the entry stays, now based on `version`.
   */
  ackOutbox(id: string, version: number, seq: number, keyV?: number): Promise<void>;
  /**
   * The upgrade pass: adds a `reseal` outbox entry (no body change, based on the record's version)
   * for records the server has (version above 0) sealed under a key version below `current` and
   * with no outbox entry, until `limit` reseal entries are pending (those already pending count).
   * Tombstones that hold a body (a remote delete with `tombstoneBody`, or a local delete) count as
   * records; the push sends their entry as a delete. Returns how many it added. Notifies nobody
   * (the engine's own write).
   */
  queueReseal(current: number, limit: number): Promise<number>;
  /**
   * The key versions the server copies of the local records (pushed; a tombstone only when it holds
   * a body) are under, and those of quarantined records (they may still be retried).
   */
  keyVersionsInUse(): Promise<Set<number>>;
  /**
   * The engine gives up on the change read as `seq` for now: stores `park` on it. A no-op when a
   * newer local write replaced it (that write is pushed normally).
   */
  parkOutbox(id: string, seq: number, park: OutboxPark): Promise<void>;
  /**
   * The engine gives up on the change read as `seq` for good: stores `park` and `abandoned`, so it
   * is never pushed again and remote writes of the id go through (and remove the entry). A no-op
   * when a newer local write replaced it.
   */
  abandonOutbox(id: string, seq: number, park: OutboxPark): Promise<void>;
  /**
   * A create (pushed as `seq`) lost to the server's copy of the same id. Without a newer local
   * write, the server's copy replaces the record and the entry goes. With one, the server's copy
   * becomes the base and `rebase(localBody)` says what to keep: the body and the fields the person
   * changed after the create (`touched`; none: the entry goes). One commit; notifies subscribers.
   */
  adoptServerCopy(
    type: RecordType,
    id: string,
    seq: number,
    server: { version: number; keyV: number; body: unknown },
    rebase: (local: unknown) => { body: unknown; touched: string[] },
  ): Promise<void>;
  getMeta<T = unknown>(key: string): Promise<T | undefined>;
  setMeta(key: string, value: unknown): Promise<void>;
  /** Keeps a record that could not be opened; a later remote write of the id clears its rows. */
  quarantine(entry: QuarantineEntry): Promise<void>;
  /** Every quarantine row (the sync retries the `unknown_key_version` ones after a refresh). */
  quarantined(): Promise<QuarantineEntry[]>;
  quarantineCount(): Promise<number>;
  /**
   * The server asked for a resync: forgets every record, the quarantine and the `latest` and
   * `base` cursors. Keys, `keyV`, `userId` and the outbox stay; in the same commit every outbox
   * entry is set aside with its current body (`setAside`), so no pending change (another tab's
   * included) is lost if the download fails. Notifies subscribers.
   */
  wipeRecords(): Promise<void>;
  /**
   * After the full download: for each set-aside change, `resolve` (synchronous) gets the entry and
   * the fresh record (if any) and says what to write. All of it in one commit; the entries come
   * back as ordinary pending changes based on the fresh version, or are removed.
   */
  restoreSetAside(
    resolve: (entry: OutboxEntry, fresh: RawRecord | undefined) => SetAsideOutcome,
  ): Promise<void>;
  /** The CryptoKeys and the device private key (`keys` store), by name. */
  getKey<T = unknown>(name: string): Promise<T | undefined>;
  putKey(name: string, key: unknown): Promise<void>;
  deleteKey(name: string): Promise<void>;
  /** The names in the `keys` store (`record:<v>`, `dedupe:<v>`, `device`). */
  keyNames(): Promise<string[]>;
  /** Closes the database; every later operation rejects with `VaultClosedError`. */
  close(): void;
  isClosed(): boolean;
  /** Called once when the store closes (`close()` or another tab's `versionchange`). */
  onClosed(listener: () => void): () => void;
}

const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

/** The fields whose value differs between two bodies (all of the new body's when there is no old). */
export function changedKeys(prev: unknown, next: unknown): string[] {
  const a = (prev ?? {}) as Record<string, unknown>;
  const b = (next ?? {}) as Record<string, unknown>;
  const out: string[] = [];
  for (const key of new Set([...Object.keys(a), ...Object.keys(b)])) {
    if (!prev || !same(a[key], b[key])) out.push(key);
  }
  return out;
}
