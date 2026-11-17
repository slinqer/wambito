/** A record as `GET /v2/sync` sends it: ciphertext and its envelope, nothing opened. */
export interface WireRecord {
  id: string;
  type: string;
  version: number;
  deleted: boolean;
  keyV: number;
  encV: number;
  body: string | null;
}

/**
 * One account's cache (spec 2026-11-16 §7): only what `/v2/sync` sent and the cursor. Entries are
 * replaced whole, never edited in place.
 */
export interface VaultCacheEntry {
  /** The key version of the assistant's wrap these records were pulled with; a new one empties it. */
  keyV: number;
  /** `/v2/sync`'s cursor: every change up to it is in `records`. */
  latest: number;
  /** By `type:id`, tombstones included (so an older copy of a deleted record never comes back). */
  records: ReadonlyMap<string, WireRecord>;
  /**
   * The lineage: it changes when the entry is emptied (a resync, a new key version), so a request
   * that began before writes nothing back into the new one.
   */
  epoch: number;
}

export interface VaultCache {
  get(userId: string): VaultCacheEntry | undefined;
  set(userId: string, entry: VaultCacheEntry): void;
  drop(userId: string): void;
  /** Runs `fn` after every earlier call for `userId` has finished: one request per account. */
  lock<T>(userId: string, fn: () => Promise<T>): Promise<T>;
}

export interface VaultCacheOptions {
  maxAccounts: number;
  maxBytes: number;
  /** An entry without a request for this long is dropped. */
  idleMs: number;
  now?: () => number;
}

/** The MCP's budget: a few hundred accounts, 64 MiB of ciphertext, 30 minutes idle. */
export const VAULT_CACHE_DEFAULTS: VaultCacheOptions = {
  maxAccounts: 500,
  maxBytes: 64 * 1024 * 1024,
  idleMs: 30 * 60_000,
};

/** About what an entry holds in memory: the ciphertext and the envelope of each record. */
function sizeOf(entry: VaultCacheEntry): number {
  let bytes = 0;
  for (const [key, record] of entry.records) {
    bytes += key.length + record.id.length + (record.body?.length ?? 0) + 64;
  }
  return bytes;
}

/**
 * The per-account ciphertext cache, in process memory: least recently used out past `maxAccounts`
 * or `maxBytes`, and dropped after `idleMs` without a request. Holds no plaintext and no key. The
 * lock lives apart from the entries: dropping an entry never releases a lock.
 */
export function createVaultCache(options: VaultCacheOptions): VaultCache {
  const now = options.now ?? Date.now;
  /** In order of last use, oldest first. */
  const entries = new Map<string, { entry: VaultCacheEntry; bytes: number; usedAt: number }>();
  let total = 0;
  const tails = new Map<string, Promise<unknown>>();

  function remove(userId: string) {
    const held = entries.get(userId);
    if (!held) return;
    total -= held.bytes;
    entries.delete(userId);
  }

  /** Drops entries idle for too long; the oldest are first, so it stops at the first fresh one. */
  function expire() {
    const cutoff = now() - options.idleMs;
    for (const [userId, held] of entries) {
      if (held.usedAt > cutoff) break;
      remove(userId);
    }
  }

  return {
    get(userId) {
      expire();
      const held = entries.get(userId);
      if (!held) return undefined;
      entries.delete(userId);
      entries.set(userId, { ...held, usedAt: now() });
      return held.entry;
    },
    set(userId, entry) {
      expire();
      remove(userId);
      const bytes = sizeOf(entry);
      if (bytes > options.maxBytes) return;
      entries.set(userId, { entry, bytes, usedAt: now() });
      total += bytes;
      for (const oldest of entries.keys()) {
        if (entries.size <= options.maxAccounts && total <= options.maxBytes) break;
        remove(oldest);
      }
    },
    drop: remove,
    async lock<T>(userId: string, fn: () => Promise<T>): Promise<T> {
      const before = tails.get(userId) ?? Promise.resolve();
      const run = before.then(fn);
      const tail = run.then(
        () => undefined,
        () => undefined,
      );
      tails.set(userId, tail);
      try {
        return await run;
      } finally {
        if (tails.get(userId) === tail) tails.delete(userId);
      }
    },
  };
}
