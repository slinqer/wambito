import type { RecordBodies, RecordType } from "@wambito/core";
import { RECORD_TYPES } from "@wambito/core";
import {
  committed,
  DATA_STORES,
  KEYS,
  META,
  OUTBOX,
  type OutboxEntry,
  type OutboxPark,
  openVault,
  QUARANTINE,
  type QuarantineEntry,
  request,
  type StoredRow,
} from "./db.ts";
import type { FinanceStore, ReadOptions, StoredRecord, StoreOps, WriteOptions } from "./store.ts";

/** What the sync engine reads about a record: the plaintext and its envelope. */
export interface RawRecord<T extends RecordType = RecordType> {
  id: string;
  body: RecordBodies[T];
  deleted: boolean;
  version: number;
  keyV: number;
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

/** The BroadcastChannel a vault's stores tell each other about commits on. */
export const vaultChannelName = (userId: string) => `wambito-vault-${userId}`;

/** A `FinanceStore` over IndexedDB, plus what the sync engine and the key setup need. */
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
   * for records the server has (version above 0, not deleted) sealed under a key version below
   * `current` and with no outbox entry, until `limit` reseal entries are pending (those already
   * pending count). Returns how many it added. Notifies nobody (the engine's own write).
   */
  queueReseal(current: number, limit: number): Promise<number>;
  /**
   * The key versions the server copies of the local records (not deleted, pushed) are under, and
   * those of quarantined records (they may still be retried).
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

export async function createEncryptedStore(userId: string): Promise<EncryptedStore> {
  const db = await openVault(userId);
  const listeners = new Set<() => void>();
  const closedListeners = new Set<() => void>();
  let queue: Promise<unknown> = Promise.resolve();
  let closed = false;
  const fire = () => {
    for (const listener of [...listeners]) listener();
  };
  // Other tabs on the same vault: they post after their commits; ours refresh on it.
  const channel =
    typeof BroadcastChannel === "undefined" ? null : new BroadcastChannel(vaultChannelName(userId));
  (channel as unknown as { unref?: () => void } | null)?.unref?.();
  if (channel) channel.onmessage = () => fire();
  const notify = () => {
    fire();
    try {
      channel?.postMessage("commit");
    } catch {
      // a closed channel: nothing to tell
    }
  };
  function close() {
    if (closed) return;
    closed = true;
    db.close();
    channel?.close();
    for (const listener of [...closedListeners]) {
      try {
        listener();
      } catch {
        // a listener must not stop the others
      }
    }
  }
  // Another tab deletes (sign-out) or upgrades the vault: let it, and stop using this one.
  db.onversionchange = () => close();
  const guard = () => {
    if (closed) throw new VaultClosedError();
  };

  /** The reads and writes of one open IndexedDB transaction. */
  function ops(
    tx: IDBTransaction,
    wrote: { value: boolean },
  ): StoreOps & {
    pendingAside(): Promise<Array<{ entry: OutboxEntry; fresh: RawRecord | undefined }>>;
    restore(entry: OutboxEntry, outcome: SetAsideOutcome): Promise<void>;
  } {
    const store = (name: string) => tx.objectStore(name);
    const nextSeq = async () => {
      const n = ((await request(store(META).get("seq"))) as number | undefined) ?? 0;
      await request(store(META).put(n + 1, "seq"));
      return n + 1;
    };
    const raw = async (type: RecordType, id: string) =>
      (await request(store(type).get(id))) as StoredRow | undefined;

    async function outboxFor(
      type: RecordType,
      id: string,
      prev: StoredRow | undefined,
      deleted: boolean,
      touched: string[],
      body: unknown,
      restoring?: OutboxEntry,
    ) {
      // Restoring a set-aside change: it starts over from the fresh copy, keeping its fields.
      const existing =
        restoring ?? ((await request(store(OUTBOX).get(id))) as OutboxEntry | undefined);
      const entry: OutboxEntry = {
        id,
        type,
        baseVersion:
          existing && !restoring
            ? existing.baseVersion
            : prev && prev.version > 0
              ? prev.version
              : null,
        // The latest write decides: a put after a delete is a restore.
        deleted,
        touched: [...new Set([...(existing?.touched ?? []), ...touched])],
        seq: await nextSeq(),
        // No `park`: a new local write is tried again at once.
      };
      if (existing?.setAside && !restoring) {
        // Still waiting for the resync's download: keep the set-aside body current.
        const aside = { ...((existing.setAside.body ?? {}) as Record<string, unknown>) };
        const next = (body ?? {}) as Record<string, unknown>;
        for (const key of touched) aside[key] = next[key];
        entry.setAside = { body: aside };
      }
      await request(store(OUTBOX).put(entry));
    }

    /** Remote writes: whether `skipIfPending` / `ifSeq` say to leave the record alone. */
    async function remoteBlocked(id: string, opts: WriteOptions | undefined) {
      if (!opts?.skipIfPending && opts?.ifSeq === undefined) return false;
      const entry = (await request(store(OUTBOX).get(id))) as OutboxEntry | undefined;
      if (opts.ifSeq !== undefined) return entry?.seq !== opts.ifSeq;
      return entry !== undefined && !entry.setAside && !entry.abandoned;
    }

    /**
     * A remote write landed: an abandoned change of the id is done with, and the server's copy
     * opened, so the id's quarantine rows (older copies that did not) are too.
     */
    async function clearAbandoned(type: RecordType, id: string) {
      const entry = (await request(store(OUTBOX).get(id))) as OutboxEntry | undefined;
      if (entry?.abandoned) await request(store(OUTBOX).delete(id));
      await request(
        store(QUARANTINE).delete(IDBKeyRange.bound([type, id, -Infinity], [type, id, Infinity])),
      );
    }

    return {
      async get<T extends RecordType>(type: T, id: string, opts?: ReadOptions) {
        const row = await raw(type, id);
        if (!row || (row.deleted && !opts?.includeDeleted)) return undefined;
        return { id, body: row.body, deleted: row.deleted } as StoredRecord<T>;
      },
      async list<T extends RecordType>(type: T, opts?: ReadOptions) {
        const rows = (await request(store(type).getAll())) as StoredRow[];
        return rows
          .filter((r) => opts?.includeDeleted || !r.deleted)
          .sort((x, y) => x.n - y.n)
          .map((r) => ({ id: r.id, body: r.body, deleted: r.deleted }) as StoredRecord<T>);
      },
      async put<T extends RecordType>(
        type: T,
        id: string,
        body: RecordBodies[T],
        opts?: WriteOptions,
      ) {
        const remote = opts?.origin === "remote";
        if (remote && (await remoteBlocked(id, opts))) return;
        const prev = await raw(type, id);
        const row: StoredRow = {
          id,
          body,
          deleted: false,
          version: remote ? (opts?.version ?? prev?.version ?? 0) : (prev?.version ?? 0),
          keyV: remote ? (opts?.keyV ?? prev?.keyV ?? 1) : (prev?.keyV ?? 1),
          n: prev?.n ?? (await nextSeq()),
        };
        await request(store(type).put(row));
        wrote.value = true;
        if (!remote) await outboxFor(type, id, prev, false, changedKeys(prev?.body, body), body);
        else await clearAbandoned(type, id);
      },
      async delete(type: RecordType, id: string, opts?: WriteOptions) {
        const prev = await raw(type, id);
        const remote = opts?.origin === "remote";
        if (!prev) {
          // A tombstone of a record this browser never opened: its quarantine rows go.
          if (remote) await clearAbandoned(type, id);
          return;
        }
        if (!remote && prev.deleted) return;
        if (remote && (await remoteBlocked(id, opts))) return;
        await request(
          store(type).put({
            ...prev,
            deleted: true,
            version: remote ? (opts?.version ?? prev.version) : prev.version,
            keyV: remote ? (opts?.keyV ?? prev.keyV) : prev.keyV,
          } satisfies StoredRow),
        );
        wrote.value = true;
        if (!remote) await outboxFor(type, id, prev, true, [], prev.body);
        else await clearAbandoned(type, id);
      },
      async pendingAside() {
        const all = (await request(store(OUTBOX).getAll())) as OutboxEntry[];
        const out: Array<{ entry: OutboxEntry; fresh: RawRecord | undefined }> = [];
        for (const entry of all) {
          if (!entry.setAside) continue;
          const row = await raw(entry.type, entry.id);
          const fresh = row
            ? ({
                id: row.id,
                body: row.body,
                deleted: row.deleted,
                version: row.version,
                keyV: row.keyV,
              } as RawRecord)
            : undefined;
          out.push({ entry, fresh });
        }
        return out;
      },
      async restore(entry: OutboxEntry, outcome: SetAsideOutcome) {
        const prev = await raw(entry.type, entry.id);
        if ("drop" in outcome || ("delete" in outcome && (!prev || prev.deleted))) {
          await request(store(OUTBOX).delete(entry.id));
          return;
        }
        if ("delete" in outcome) {
          await request(store(entry.type).put({ ...prev, deleted: true } as StoredRow));
          await outboxFor(entry.type, entry.id, prev, true, [], prev?.body, entry);
        } else {
          const row: StoredRow = {
            id: entry.id,
            body: outcome.put,
            deleted: false,
            version: prev?.version ?? 0,
            keyV: prev?.keyV ?? 1,
            n: prev?.n ?? (await nextSeq()),
          };
          await request(store(entry.type).put(row));
          const touched = changedKeys(prev?.body, outcome.put);
          await outboxFor(entry.type, entry.id, prev, false, touched, outcome.put, entry);
        }
        wrote.value = true;
      },
    };
  }

  function transaction<R>(fn: (tx: StoreOps) => Promise<R>): Promise<R> {
    const run = async () => {
      guard();
      const tx = db.transaction(DATA_STORES, "readwrite");
      const finished = committed(tx);
      const wrote = { value: false };
      let result: R;
      try {
        result = await fn(ops(tx, wrote));
      } catch (error) {
        finished.catch(() => undefined);
        try {
          tx.abort();
        } catch {
          // already finished
        }
        throw error;
      }
      await finished;
      if (wrote.value) notify();
      return result;
    };
    const next = queue.then(run, run);
    queue = next.catch(() => undefined);
    return next;
  }

  /** A short transaction on a few stores, outside the queue (IndexedDB orders overlapping ones). */
  async function short<R>(
    names: string[],
    mode: IDBTransactionMode,
    fn: (tx: IDBTransaction) => Promise<R>,
  ): Promise<R> {
    guard();
    const tx = db.transaction(names, mode);
    const finished = committed(tx);
    try {
      const result = await fn(tx);
      await finished;
      return result;
    } catch (error) {
      finished.catch(() => undefined);
      try {
        tx.abort();
      } catch {
        // already finished
      }
      throw error;
    }
  }

  return {
    get: (type, id, opts) => transaction((tx) => tx.get(type, id, opts)),
    list: (type, opts) => transaction((tx) => tx.list(type, opts)),
    put: (type, id, body, opts) => transaction((tx) => tx.put(type, id, body, opts)),
    delete: (type, id, opts) => transaction((tx) => tx.delete(type, id, opts)),
    transaction,
    subscribe(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },

    async getRaw<T extends RecordType>(type: T, id: string) {
      const row = await short([type], "readonly", async (tx) => {
        return (await request(tx.objectStore(type).get(id))) as StoredRow | undefined;
      });
      if (!row) return undefined;
      return {
        id,
        body: row.body,
        deleted: row.deleted,
        version: row.version,
        keyV: row.keyV,
      } as RawRecord<T>;
    },
    async readOutbox(limit) {
      const all = await short([OUTBOX], "readonly", async (tx) => {
        return (await request(tx.objectStore(OUTBOX).getAll())) as OutboxEntry[];
      });
      return all.sort((x, y) => x.seq - y.seq).slice(0, limit);
    },
    ackOutbox: (id, version, seq, keyV) =>
      short([...RECORD_TYPES, OUTBOX], "readwrite", async (tx) => {
        const outbox = tx.objectStore(OUTBOX);
        const entry = (await request(outbox.get(id))) as OutboxEntry | undefined;
        if (!entry) return;
        const records = tx.objectStore(entry.type);
        const row = (await request(records.get(id))) as StoredRow | undefined;
        if (row) await request(records.put({ ...row, version, keyV: keyV ?? row.keyV }));
        if (entry.seq === seq) await request(outbox.delete(id));
        else await request(outbox.put({ ...entry, baseVersion: version }));
      }),
    queueReseal: (current, limit) =>
      short([...RECORD_TYPES, OUTBOX, META], "readwrite", async (tx) => {
        const outbox = tx.objectStore(OUTBOX);
        const entries = (await request(outbox.getAll())) as OutboxEntry[];
        const pending = new Set(entries.map((e) => e.id));
        let room = limit - entries.filter((e) => e.reseal).length;
        let seq = ((await request(tx.objectStore(META).get("seq"))) as number | undefined) ?? 0;
        let added = 0;
        for (const type of RECORD_TYPES) {
          if (room <= 0) break;
          for (const row of (await request(tx.objectStore(type).getAll())) as StoredRow[]) {
            if (room <= 0) break;
            if (row.deleted || row.version === 0 || row.keyV >= current || pending.has(row.id)) {
              continue;
            }
            const entry: OutboxEntry = {
              id: row.id,
              type,
              baseVersion: row.version,
              deleted: false,
              touched: [],
              seq: ++seq,
              reseal: true,
            };
            await request(outbox.put(entry));
            room -= 1;
            added += 1;
          }
        }
        if (added > 0) await request(tx.objectStore(META).put(seq, "seq"));
        return added;
      }),
    keyVersionsInUse: () =>
      short([...RECORD_TYPES, QUARANTINE], "readonly", async (tx) => {
        const versions = new Set<number>();
        for (const type of RECORD_TYPES) {
          for (const row of (await request(tx.objectStore(type).getAll())) as StoredRow[]) {
            if (!row.deleted && row.version > 0) versions.add(row.keyV);
          }
        }
        // A quarantined record may be retried under its version: keep that version's keys.
        const held = (await request(tx.objectStore(QUARANTINE).getAll())) as QuarantineEntry[];
        for (const row of held) if (row.keyV !== undefined) versions.add(row.keyV);
        return versions;
      }),
    parkOutbox: (id, seq, park) =>
      short([OUTBOX], "readwrite", async (tx) => {
        const outbox = tx.objectStore(OUTBOX);
        const entry = (await request(outbox.get(id))) as OutboxEntry | undefined;
        if (entry?.seq === seq) await request(outbox.put({ ...entry, park }));
      }),
    abandonOutbox: (id, seq, park) =>
      short([OUTBOX], "readwrite", async (tx) => {
        const outbox = tx.objectStore(OUTBOX);
        const entry = (await request(outbox.get(id))) as OutboxEntry | undefined;
        if (entry?.seq === seq) await request(outbox.put({ ...entry, park, abandoned: true }));
      }),
    async adoptServerCopy(type, id, seq, server, rebase) {
      await short([type, OUTBOX, META], "readwrite", async (tx) => {
        const outbox = tx.objectStore(OUTBOX);
        const records = tx.objectStore(type);
        const entry = (await request(outbox.get(id))) as OutboxEntry | undefined;
        if (!entry) return;
        const row = (await request(records.get(id))) as StoredRow | undefined;
        let n = row?.n;
        if (n === undefined) {
          n = (((await request(tx.objectStore(META).get("seq"))) as number | undefined) ?? 0) + 1;
          await request(tx.objectStore(META).put(n, "seq"));
        }
        const base = { id, version: server.version, keyV: server.keyV, n };
        if (entry.seq === seq) {
          await request(records.put({ ...base, body: server.body, deleted: false }));
          await request(outbox.delete(id));
        } else if (entry.deleted) {
          // Deleted since: the delete is pushed as an edit of the server's copy.
          await request(records.put({ ...base, body: server.body, deleted: true }));
          await request(outbox.put({ ...entry, baseVersion: server.version, touched: [] }));
        } else {
          const { body, touched } = rebase(row?.body);
          await request(records.put({ ...base, body, deleted: false }));
          if (touched.length === 0) await request(outbox.delete(id));
          else await request(outbox.put({ ...entry, baseVersion: server.version, touched }));
        }
      });
      notify();
    },
    getMeta: <T>(key: string) =>
      short([META], "readonly", (tx) => request(tx.objectStore(META).get(key))) as Promise<
        T | undefined
      >,
    setMeta: (key, value) =>
      short([META], "readwrite", async (tx) => {
        await request(tx.objectStore(META).put(value, key));
      }),
    quarantine: (entry) =>
      short([QUARANTINE], "readwrite", async (tx) => {
        await request(tx.objectStore(QUARANTINE).put(entry));
      }),
    quarantined: () =>
      short([QUARANTINE], "readonly", (tx) => request(tx.objectStore(QUARANTINE).getAll())),
    quarantineCount: () =>
      short([QUARANTINE], "readonly", (tx) => request(tx.objectStore(QUARANTINE).count())),
    async wipeRecords() {
      await transaction(async () => undefined);
      await short(DATA_STORES, "readwrite", async (tx) => {
        const outbox = tx.objectStore(OUTBOX);
        for (const entry of (await request(outbox.getAll())) as OutboxEntry[]) {
          if (entry.setAside) continue;
          if (entry.abandoned) {
            // Given up on: the full download brings the server's copy.
            await request(outbox.delete(entry.id));
            continue;
          }
          const row = (await request(tx.objectStore(entry.type).get(entry.id))) as
            | StoredRow
            | undefined;
          await request(outbox.put({ ...entry, setAside: { body: row?.body ?? null } }));
        }
        for (const name of [...RECORD_TYPES, QUARANTINE]) {
          await request(tx.objectStore(name).clear());
        }
        await request(tx.objectStore(META).delete("latest"));
        await request(tx.objectStore(META).delete("base"));
      });
      notify();
    },
    restoreSetAside: (resolve) =>
      transaction(async (txOps) => {
        const local = txOps as ReturnType<typeof ops>;
        // The same IndexedDB transaction: read the outbox and the fresh rows through it.
        const aside = (await local.pendingAside()).sort((x, y) => x.entry.seq - y.entry.seq);
        for (const { entry, fresh } of aside) await local.restore(entry, resolve(entry, fresh));
      }),
    getKey: <T>(name: string) =>
      short([KEYS], "readonly", (tx) => request(tx.objectStore(KEYS).get(name))) as Promise<
        T | undefined
      >,
    putKey: (name, key) =>
      short([KEYS], "readwrite", async (tx) => {
        await request(tx.objectStore(KEYS).put(key, name));
      }),
    deleteKey: (name) =>
      short([KEYS], "readwrite", async (tx) => {
        await request(tx.objectStore(KEYS).delete(name));
      }),
    keyNames: () =>
      short([KEYS], "readonly", async (tx) =>
        (await request(tx.objectStore(KEYS).getAllKeys())).map(String),
      ),
    close,
    isClosed: () => closed,
    onClosed(listener) {
      closedListeners.add(listener);
      return () => {
        closedListeners.delete(listener);
      };
    },
  };
}
