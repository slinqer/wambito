import { RECORD_TYPES, type RecordType } from "@wambito/core";

/**
 * A small promise wrapper over IndexedDB for the encrypted vault. No dependency. Everything the
 * vault keeps for one account lives in the database `wambito-vault-<userId>`.
 */

export const OUTBOX = "outbox";
export const META = "meta";
export const QUARANTINE = "quarantine";
export const KEYS = "keys";

/** A record as the database holds it: the plaintext body and the sync envelope. */
export interface StoredRow {
  id: string;
  body: unknown;
  deleted: boolean;
  /** The server's version; 0 until the record has been pushed. */
  version: number;
  /** The key version the server copy was sealed under. */
  keyV: number;
  /** When it was first written: the order `list` returns. */
  n: number;
}

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

export const vaultName = (userId: string) => `wambito-vault-${userId}`;

/** Every object store that holds data, for a transaction that spans the vault. */
export const DATA_STORES: string[] = [...RECORD_TYPES, OUTBOX, META, QUARANTINE];

export function request<T>(r: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
}

/** Resolves when the transaction commits, rejects if it aborts. */
export function committed(tx: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onabort = () => reject(tx.error ?? new Error("The transaction was aborted"));
    tx.onerror = () => reject(tx.error);
  });
}

export function openVault(userId: string): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const open = indexedDB.open(vaultName(userId), 1);
    open.onupgradeneeded = () => {
      const db = open.result;
      for (const type of RECORD_TYPES) db.createObjectStore(type, { keyPath: "id" });
      db.createObjectStore(OUTBOX, { keyPath: "id" });
      db.createObjectStore(META);
      db.createObjectStore(QUARANTINE, { keyPath: ["type", "id", "version"] });
      db.createObjectStore(KEYS);
    };
    open.onsuccess = () => resolve(open.result);
    open.onerror = () => reject(open.error);
    open.onblocked = () =>
      reject(new Error("The vault is open in another tab that will not close"));
  });
}

/** Signing out: removes the database, the keys in it included. */
export function deleteVault(userId: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const del = indexedDB.deleteDatabase(vaultName(userId));
    del.onsuccess = () => resolve();
    del.onerror = () => reject(del.error);
    del.onblocked = () => reject(new Error("The vault is open in another tab that will not close"));
  });
}
