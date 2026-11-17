import { RECORD_TYPES } from "@wambito/core";

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
  /**
   * The server's copy of this tombstone has no body, as far as this device knows. Set by a remote
   * delete without a body, or by the version 2 upgrade; cleared by a remote delete with a body, an
   * acked local delete, or any put.
   */
  bodiless?: true;
  /** When it was first written: the order `list` returns. */
  n: number;
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
    const open = indexedDB.open(vaultName(userId), 2);
    open.onupgradeneeded = (event) => {
      const db = open.result;
      if (event.oldVersion >= 1) {
        // Version 2: no server tombstone held a body before, so every tombstone is bodiless.
        const tx = open.transaction as IDBTransaction;
        for (const type of RECORD_TYPES) {
          const cursorRequest = tx.objectStore(type).openCursor();
          cursorRequest.onsuccess = () => {
            const cursor = cursorRequest.result;
            if (!cursor) return;
            const row = cursor.value as StoredRow;
            if (row.deleted) cursor.update({ ...row, bodiless: true });
            cursor.continue();
          };
        }
        return;
      }
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
