import { RECORD_TYPES, type RecordBodies, type RecordType } from "@wambito/core";
import {
  changedKeys,
  type EncryptedStore,
  type OutboxEntry,
  type QuarantineEntry,
  type RawRecord,
  type SetAsideOutcome,
  VaultClosedError,
} from "./encrypted.ts";
import type { ReadOptions, StoredRecord, StoreOps, WriteOptions } from "./store.ts";

interface Row {
  body: unknown;
  deleted: boolean;
  version: number;
  keyV: number;
  /** A tombstone whose body is only a stale local copy: the server's holds none. */
  bodiless?: true;
}

/** Everything a transaction may change; rows and entries are replaced, never edited in place. */
interface State {
  records: Map<RecordType, Map<string, Row>>;
  outbox: Map<string, OutboxEntry>;
  quarantine: Map<string, QuarantineEntry>;
  meta: Map<string, unknown>;
  seq: number;
}

const clone = <T>(value: T): T => structuredClone(value);
const quarantineKey = (e: { type: string; id: string; version: number }) =>
  `${e.type}\u0000${e.id}\u0000${e.version}`;

function emptyState(): State {
  return {
    records: new Map(RECORD_TYPES.map((t) => [t, new Map<string, Row>()])),
    outbox: new Map(),
    quarantine: new Map(),
    meta: new Map(),
    seq: 0,
  };
}

function snapshot(s: State): State {
  return {
    records: new Map([...s.records].map(([t, rows]) => [t, new Map(rows)])),
    outbox: new Map(s.outbox),
    quarantine: new Map(s.quarantine),
    meta: new Map(s.meta),
    seq: s.seq,
  };
}

/**
 * The in-process `EncryptedStore` (the MCP's, per request): plain maps, no persistence, the same
 * semantics as the IndexedDB store. Operations run one at a time; a transaction that throws
 * restores the state it started from.
 */
export function createMemoryEncryptedStore(_userId: string): EncryptedStore {
  let state = emptyState();
  const keys = new Map<string, unknown>();
  const listeners = new Set<() => void>();
  const closedListeners = new Set<() => void>();
  let queue: Promise<unknown> = Promise.resolve();
  let closed = false;
  const fire = () => {
    for (const listener of [...listeners]) {
      try {
        listener();
      } catch {
        // a subscriber must not undo a commit or stop the others
      }
    }
  };
  const guard = () => {
    if (closed) throw new VaultClosedError();
  };
  /** The state a running transaction started from, taken by its first write only. */
  let saved: State | undefined;
  const dirty = () => {
    saved ??= snapshot(state);
  };

  /** Runs `fn` after every earlier operation; a throw restores what `dirty()` saved. */
  function serial<R>(fn: () => Promise<R>, afterCommit?: () => void): Promise<R> {
    const run = async () => {
      guard();
      saved = undefined;
      let result: R;
      try {
        result = await fn();
      } catch (error) {
        if (saved) state = saved;
        throw error;
      } finally {
        saved = undefined;
      }
      afterCommit?.();
      return result;
    };
    const next = queue.then(run, run);
    queue = next.catch(() => undefined);
    return next;
  }

  const table = (type: RecordType) => state.records.get(type) as Map<string, Row>;
  const nextSeq = () => ++state.seq;

  function outboxFor(
    type: RecordType,
    id: string,
    prev: Row | undefined,
    deleted: boolean,
    touched: string[],
    body: unknown,
    restoring?: OutboxEntry,
  ) {
    // Restoring a set-aside change: it starts over from the fresh copy, keeping its fields.
    const existing = restoring ?? state.outbox.get(id);
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
      seq: nextSeq(),
      // No `park`: a new local write is tried again at once.
    };
    if (existing?.setAside && !restoring) {
      // Still waiting for the resync's download: keep the set-aside body current.
      const aside = { ...((existing.setAside.body ?? {}) as Record<string, unknown>) };
      const next = (body ?? {}) as Record<string, unknown>;
      for (const key of touched) aside[key] = next[key];
      entry.setAside = { body: aside };
    }
    state.outbox.set(id, entry);
  }

  /** Remote writes: whether `skipIfPending` / `ifSeq` say to leave the record alone. */
  function remoteBlocked(id: string, opts: WriteOptions | undefined) {
    if (!opts?.skipIfPending && opts?.ifSeq === undefined) return false;
    const entry = state.outbox.get(id);
    if (opts.ifSeq !== undefined) return entry?.seq !== opts.ifSeq;
    return entry !== undefined && !entry.setAside && !entry.abandoned;
  }

  /** A remote write landed: an abandoned change is done with, and the id's quarantine rows too. */
  function clearAbandoned(type: RecordType, id: string) {
    if (state.outbox.get(id)?.abandoned) state.outbox.delete(id);
    for (const [key, row] of state.quarantine) {
      if (row.type === type && row.id === id) state.quarantine.delete(key);
    }
  }

  const rawOf = (_type: RecordType, id: string, row: Row): RawRecord => ({
    id,
    body: clone(row.body) as RawRecord["body"],
    deleted: row.deleted,
    version: row.version,
    keyV: row.keyV,
  });

  function ops(wrote: { value: boolean }): StoreOps & {
    restore(entry: OutboxEntry, outcome: SetAsideOutcome): void;
  } {
    return {
      async get<T extends RecordType>(type: T, id: string, opts?: ReadOptions) {
        const row = table(type).get(id);
        if (!row || (row.deleted && !opts?.includeDeleted)) return undefined;
        return { id, body: clone(row.body), deleted: row.deleted } as StoredRecord<T>;
      },
      async list<T extends RecordType>(type: T, opts?: ReadOptions) {
        return [...table(type)]
          .filter(([, r]) => opts?.includeDeleted || !r.deleted)
          .map(([id, r]) => ({ id, body: clone(r.body), deleted: r.deleted }) as StoredRecord<T>);
      },
      async put<T extends RecordType>(
        type: T,
        id: string,
        body: RecordBodies[T],
        opts?: WriteOptions,
      ) {
        const remote = opts?.origin === "remote";
        if (remote && remoteBlocked(id, opts)) return;
        dirty();
        const prev = table(type).get(id);
        const stored = clone(body);
        table(type).set(id, {
          body: stored,
          deleted: false,
          version: remote ? (opts?.version ?? prev?.version ?? 0) : (prev?.version ?? 0),
          keyV: remote ? (opts?.keyV ?? prev?.keyV ?? 1) : (prev?.keyV ?? 1),
        });
        wrote.value = true;
        if (!remote) outboxFor(type, id, prev, false, changedKeys(prev?.body, body), stored);
        else clearAbandoned(type, id);
      },
      async delete(type: RecordType, id: string, opts?: WriteOptions) {
        const prev = table(type).get(id);
        const remote = opts?.origin === "remote";
        const hasBody = remote && opts?.tombstoneBody !== undefined;
        if (!prev) {
          if (remote) {
            if (remoteBlocked(id, opts)) return;
            dirty();
            if (hasBody) {
              // A tombstone of a record this store never had, with its body: a tombstone row.
              table(type).set(id, {
                body: clone(opts?.tombstoneBody),
                deleted: true,
                version: opts?.version ?? 0,
                keyV: opts?.keyV ?? 1,
              });
              wrote.value = true;
            }
            // Its quarantine rows go.
            clearAbandoned(type, id);
          }
          return;
        }
        if (!remote && prev.deleted) return;
        if (remote && remoteBlocked(id, opts)) return;
        dirty();
        const { bodiless: _, ...rest } = prev;
        table(type).set(id, {
          ...rest,
          ...(hasBody ? { body: clone(opts?.tombstoneBody) } : {}),
          deleted: true,
          version: remote ? (opts?.version ?? prev.version) : prev.version,
          keyV: remote ? (opts?.keyV ?? prev.keyV) : prev.keyV,
          // A remote delete without a body keeps the stale local copy, which is not the server's.
          ...(remote && !hasBody && (!prev.deleted || prev.bodiless)
            ? { bodiless: true as const }
            : {}),
        });
        wrote.value = true;
        if (!remote) outboxFor(type, id, prev, true, [], prev.body);
        else clearAbandoned(type, id);
      },
      restore(entry, outcome) {
        dirty();
        const prev = table(entry.type).get(entry.id);
        if ("drop" in outcome || ("delete" in outcome && (!prev || prev.deleted))) {
          state.outbox.delete(entry.id);
          return;
        }
        if ("delete" in outcome) {
          table(entry.type).set(entry.id, { ...(prev as Row), deleted: true });
          outboxFor(entry.type, entry.id, prev, true, [], prev?.body, entry);
        } else {
          const body = clone(outcome.put);
          table(entry.type).set(entry.id, {
            body,
            deleted: false,
            version: prev?.version ?? 0,
            keyV: prev?.keyV ?? 1,
          });
          outboxFor(
            entry.type,
            entry.id,
            prev,
            false,
            changedKeys(prev?.body, outcome.put),
            body,
            entry,
          );
        }
        wrote.value = true;
      },
    };
  }

  function transaction<R>(fn: (tx: StoreOps) => Promise<R>): Promise<R> {
    const wrote = { value: false };
    return serial(
      () => fn(ops(wrote)),
      () => {
        if (wrote.value) fire();
      },
    );
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

    getRaw: <T extends RecordType>(type: T, id: string) =>
      serial(async () => {
        const row = table(type).get(id);
        return row ? (rawOf(type, id, row) as RawRecord<T>) : undefined;
      }),
    readOutbox: (limit) =>
      serial(async () =>
        [...state.outbox.values()]
          .sort((x, y) => x.seq - y.seq)
          .slice(0, limit)
          .map(clone),
      ),
    ackOutbox: (id, version, seq, keyV) =>
      serial(async () => {
        const entry = state.outbox.get(id);
        if (!entry) return;
        const row = table(entry.type).get(id);
        if (row) {
          // Every push from now on carries the body the tombstone has.
          const { bodiless: _, ...rest } = row;
          table(entry.type).set(id, {
            ...(row.deleted ? rest : row),
            version,
            keyV: keyV ?? row.keyV,
          });
        }
        if (entry.seq === seq) state.outbox.delete(id);
        else state.outbox.set(id, { ...entry, baseVersion: version });
      }),
    queueReseal: (current, limit) =>
      serial(async () => {
        const pending = new Set(state.outbox.keys());
        let room = limit - [...state.outbox.values()].filter((e) => e.reseal).length;
        let added = 0;
        for (const type of RECORD_TYPES) {
          if (room <= 0) break;
          for (const [id, row] of table(type)) {
            if (room <= 0) break;
            if (
              (row.deleted && row.bodiless) ||
              row.version === 0 ||
              row.keyV >= current ||
              pending.has(id)
            ) {
              continue;
            }
            state.outbox.set(id, {
              id,
              type,
              baseVersion: row.version,
              deleted: row.deleted,
              touched: [],
              seq: nextSeq(),
              reseal: true,
            });
            room -= 1;
            added += 1;
          }
        }
        return added;
      }),
    keyVersionsInUse: () =>
      serial(async () => {
        const versions = new Set<number>();
        for (const type of RECORD_TYPES) {
          for (const row of table(type).values()) {
            if (!(row.deleted && row.bodiless) && row.version > 0) versions.add(row.keyV);
          }
        }
        // A quarantined record may be retried under its version: keep that version's keys.
        for (const row of state.quarantine.values()) {
          if (row.keyV !== undefined) versions.add(row.keyV);
        }
        return versions;
      }),
    parkOutbox: (id, seq, park) =>
      serial(async () => {
        const entry = state.outbox.get(id);
        if (entry?.seq === seq) state.outbox.set(id, { ...entry, park: clone(park) });
      }),
    abandonOutbox: (id, seq, park) =>
      serial(async () => {
        const entry = state.outbox.get(id);
        if (entry?.seq === seq) {
          state.outbox.set(id, { ...entry, park: clone(park), abandoned: true });
        }
      }),
    async adoptServerCopy(type, id, seq, server, rebase) {
      await serial(async () => {
        const entry = state.outbox.get(id);
        if (!entry) return;
        const row = table(type).get(id);
        const base = { version: server.version, keyV: server.keyV };
        if (entry.seq === seq) {
          table(type).set(id, { ...base, body: clone(server.body), deleted: false });
          state.outbox.delete(id);
        } else if (entry.deleted) {
          // Deleted since: the delete is pushed as an edit of the server's copy.
          table(type).set(id, { ...base, body: clone(server.body), deleted: true });
          state.outbox.set(id, { ...entry, baseVersion: server.version, touched: [] });
        } else {
          const { body, touched } = rebase(clone(row?.body));
          table(type).set(id, { ...base, body: clone(body), deleted: false });
          if (touched.length === 0) state.outbox.delete(id);
          else state.outbox.set(id, { ...entry, baseVersion: server.version, touched });
        }
      });
      fire();
    },
    // `seq` is the write counter, as the IndexedDB store keeps it in its meta store: the sync
    // engine reads it to tell writes made during a run from changes left pending.
    getMeta: <T>(key: string) =>
      serial(async () => (key === "seq" ? state.seq : clone(state.meta.get(key))) as T | undefined),
    setMeta: (key, value) =>
      serial(async () => {
        state.meta.set(key, clone(value));
      }),
    quarantine: (entry) =>
      serial(async () => {
        state.quarantine.set(quarantineKey(entry), clone(entry));
      }),
    quarantined: () => serial(async () => [...state.quarantine.values()].map(clone)),
    quarantineCount: () => serial(async () => state.quarantine.size),
    async wipeRecords() {
      await serial(async () => {
        for (const entry of [...state.outbox.values()]) {
          if (entry.setAside) continue;
          if (entry.abandoned) {
            // Given up on: the full download brings the server's copy.
            state.outbox.delete(entry.id);
            continue;
          }
          const row = table(entry.type).get(entry.id);
          state.outbox.set(entry.id, { ...entry, setAside: { body: clone(row?.body ?? null) } });
        }
        for (const type of RECORD_TYPES) table(type).clear();
        state.quarantine.clear();
        state.meta.delete("latest");
        state.meta.delete("base");
      });
      fire();
    },
    restoreSetAside: (resolve) =>
      transaction(async (txOps) => {
        const local = txOps as ReturnType<typeof ops>;
        const aside = [...state.outbox.values()]
          .filter((e) => e.setAside)
          .sort((x, y) => x.seq - y.seq);
        for (const entry of aside) {
          const row = table(entry.type).get(entry.id);
          local.restore(
            clone(entry),
            resolve(clone(entry), row ? rawOf(entry.type, entry.id, row) : undefined),
          );
        }
      }),
    getKey: async <T>(name: string) => {
      guard();
      return keys.get(name) as T | undefined;
    },
    putKey: async (name, key) => {
      guard();
      keys.set(name, key);
    },
    deleteKey: async (name) => {
      guard();
      keys.delete(name);
    },
    keyNames: async () => {
      guard();
      return [...keys.keys()];
    },
    close() {
      if (closed) return;
      closed = true;
      for (const listener of [...closedListeners]) {
        try {
          listener();
        } catch {
          // a listener must not stop the others
        }
      }
    },
    isClosed: () => closed,
    onClosed(listener) {
      closedListeners.add(listener);
      return () => {
        closedListeners.delete(listener);
      };
    },
  };
}
