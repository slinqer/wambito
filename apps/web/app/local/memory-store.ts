import type {
  FinanceStore,
  ReadOptions,
  RecordBodies,
  RecordType,
  StoredRecord,
  StoreOps,
  WriteOptions,
} from "./store.ts";

type Entry = { body: unknown; deleted: boolean };
type Table = Map<string, Entry>;
/** A transaction's pending changes. */
type Overlay = Map<RecordType, Map<string, Entry>>;

const clone = <T>(value: T): T => structuredClone(value);

/**
 * The demo's state behind `FinanceStore`: plain maps, no persistence, no outbox. Async like the
 * real one. A transaction stages its writes in an overlay and merges it on success.
 */
export function createMemoryStore(): FinanceStore {
  const tables = new Map<RecordType, Table>();
  const listeners = new Set<() => void>();
  let queue: Promise<unknown> = Promise.resolve();

  const table = (type: RecordType): Table => {
    let t = tables.get(type);
    if (!t) tables.set(type, (t = new Map()));
    return t;
  };

  function ops(overlay: Overlay): StoreOps {
    const staged = (type: RecordType) => {
      let o = overlay.get(type);
      if (!o) overlay.set(type, (o = new Map()));
      return o;
    };
    const lookup = (type: RecordType, id: string): Entry | undefined => {
      const o = overlay.get(type);
      if (o?.has(id)) return o.get(id);
      return table(type).get(id);
    };
    return {
      async get<T extends RecordType>(type: T, id: string, opts?: ReadOptions) {
        const entry = lookup(type, id);
        if (!entry || (entry.deleted && !opts?.includeDeleted)) return undefined;
        return { id, body: clone(entry.body), deleted: entry.deleted } as StoredRecord<T>;
      },
      async list<T extends RecordType>(type: T, opts?: ReadOptions) {
        const o = overlay.get(type);
        const out: StoredRecord<T>[] = [];
        const add = (id: string, entry: Entry | undefined) => {
          if (!entry || (entry.deleted && !opts?.includeDeleted)) return;
          out.push({ id, body: clone(entry.body), deleted: entry.deleted } as StoredRecord<T>);
        };
        for (const [id, base] of table(type)) add(id, o?.has(id) ? o.get(id) : base);
        if (o) for (const [id, entry] of o) if (!table(type).has(id)) add(id, entry);
        return out;
      },
      async put<T extends RecordType>(
        type: T,
        id: string,
        body: RecordBodies[T],
        _opts?: WriteOptions,
      ) {
        staged(type).set(id, { body: clone(body), deleted: false });
      },
      async delete(type: RecordType, id: string, _opts?: WriteOptions) {
        const entry = lookup(type, id);
        if (!entry) return;
        staged(type).set(id, { body: entry.body, deleted: true });
      },
    };
  }

  function commit(overlay: Overlay): boolean {
    let changed = false;
    for (const [type, changes] of overlay) {
      const t = table(type);
      for (const [id, entry] of changes) {
        changed = true;
        t.set(id, entry);
      }
    }
    return changed;
  }

  function transaction<R>(fn: (tx: StoreOps) => Promise<R>): Promise<R> {
    const run = async () => {
      const overlay: Overlay = new Map();
      const result = await fn(ops(overlay));
      if (commit(overlay)) for (const listener of [...listeners]) listener();
      return result;
    };
    const next = queue.then(run, run);
    queue = next.catch(() => undefined);
    return next;
  }

  // Each bare operation is a transaction of its own, so it queues and notifies like one.
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
  };
}
