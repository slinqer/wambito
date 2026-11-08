import type { RecordBodies, RecordType } from "@wambito/core";
import { RECORD_TYPES } from "@wambito/core";
import {
  committed,
  DATA_STORES,
  KEYS,
  META,
  OUTBOX,
  type OutboxEntry,
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

/** A `FinanceStore` over IndexedDB, plus what the sync engine and the key setup need. */
export interface EncryptedStore extends FinanceStore {
  /** The record with its server version and key version (tombstones included). */
  getRaw<T extends RecordType>(type: T, id: string): Promise<RawRecord<T> | undefined>;
  /** The pending changes, oldest first. */
  readOutbox(limit: number): Promise<OutboxEntry[]>;
  /**
   * The server accepted the change read as `seq` and gave it `version`. Records the version, and
   * clears the entry only if there was no newer local write since; otherwise the entry stays,
   * now based on `version`.
   */
  ackOutbox(id: string, version: number, seq: number): Promise<void>;
  getMeta<T = unknown>(key: string): Promise<T | undefined>;
  setMeta(key: string, value: unknown): Promise<void>;
  quarantine(entry: QuarantineEntry): Promise<void>;
  quarantineCount(): Promise<number>;
  /**
   * Forgets every record, the outbox, the quarantine and the `latest` and `base` cursors (the
   * server asked for a resync). Keys, `keyV` and `userId` stay. Notifies subscribers.
   */
  wipeRecords(): Promise<void>;
  /** The CryptoKeys and the device private key (`keys` store), by name. */
  getKey<T = unknown>(name: string): Promise<T | undefined>;
  putKey(name: string, key: unknown): Promise<void>;
  close(): void;
}

const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

/** The fields whose value differs between two bodies (all of the new body's when there is no old). */
function changedKeys(prev: unknown, next: unknown): string[] {
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
  let queue: Promise<unknown> = Promise.resolve();
  const notify = () => {
    for (const listener of [...listeners]) listener();
  };

  /** The reads and writes of one open IndexedDB transaction. */
  function ops(tx: IDBTransaction, wrote: { value: boolean }): StoreOps {
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
    ) {
      const existing = (await request(store(OUTBOX).get(id))) as OutboxEntry | undefined;
      const entry: OutboxEntry = {
        id,
        type,
        baseVersion: existing
          ? existing.baseVersion
          : prev && prev.version > 0
            ? prev.version
            : null,
        // The latest write decides: a put after a delete is a restore.
        deleted,
        touched: [...new Set([...(existing?.touched ?? []), ...touched])],
        seq: await nextSeq(),
      };
      await request(store(OUTBOX).put(entry));
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
        const prev = await raw(type, id);
        const remote = opts?.origin === "remote";
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
        if (!remote) await outboxFor(type, id, prev, false, changedKeys(prev?.body, body));
      },
      async delete(type: RecordType, id: string, opts?: WriteOptions) {
        const prev = await raw(type, id);
        if (!prev) return;
        const remote = opts?.origin === "remote";
        if (!remote && prev.deleted) return;
        await request(
          store(type).put({
            ...prev,
            deleted: true,
            version: remote ? (opts?.version ?? prev.version) : prev.version,
            keyV: remote ? (opts?.keyV ?? prev.keyV) : prev.keyV,
          } satisfies StoredRow),
        );
        wrote.value = true;
        if (!remote) await outboxFor(type, id, prev, true, []);
      },
    };
  }

  function transaction<R>(fn: (tx: StoreOps) => Promise<R>): Promise<R> {
    const run = async () => {
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
    ackOutbox: (id, version, seq) =>
      short([...RECORD_TYPES, OUTBOX], "readwrite", async (tx) => {
        const outbox = tx.objectStore(OUTBOX);
        const entry = (await request(outbox.get(id))) as OutboxEntry | undefined;
        if (!entry) return;
        const records = tx.objectStore(entry.type);
        const row = (await request(records.get(id))) as StoredRow | undefined;
        if (row) await request(records.put({ ...row, version }));
        if (entry.seq === seq) await request(outbox.delete(id));
        else await request(outbox.put({ ...entry, baseVersion: version }));
      }),
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
    quarantineCount: () =>
      short([QUARANTINE], "readonly", (tx) => request(tx.objectStore(QUARANTINE).count())),
    async wipeRecords() {
      await transaction(async () => undefined);
      await short(DATA_STORES, "readwrite", async (tx) => {
        for (const name of [...RECORD_TYPES, OUTBOX, QUARANTINE]) {
          await request(tx.objectStore(name).clear());
        }
        await request(tx.objectStore(META).delete("latest"));
        await request(tx.objectStore(META).delete("base"));
      });
      notify();
    },
    getKey: <T>(name: string) =>
      short([KEYS], "readonly", (tx) => request(tx.objectStore(KEYS).get(name))) as Promise<
        T | undefined
      >,
    putKey: (name, key) =>
      short([KEYS], "readwrite", async (tx) => {
        await request(tx.objectStore(KEYS).put(key, name));
      }),
    close: () => db.close(),
  };
}
