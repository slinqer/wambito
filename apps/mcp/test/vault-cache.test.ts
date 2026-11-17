import { describe, expect, test } from "vitest";
import { createVaultCache, type VaultCacheEntry, type WireRecord } from "../src/vault-cache.ts";

// The MCP's per-account cache of what `/v2/sync` sent (ciphertext and the cursor): bounded by
// accounts and bytes (least recently used out), dropped after a while without a request, and the
// lock that runs one request at a time per account.

const record = (id: string, bytes = 10): WireRecord => ({
  id,
  type: "transaction",
  version: 1,
  deleted: false,
  keyV: 1,
  encV: 1,
  body: "x".repeat(bytes),
});

const entry = (...records: WireRecord[]): VaultCacheEntry => ({
  keyV: 1,
  latest: records.length,
  epoch: 1,
  records: new Map(records.map((r) => [`${r.type}:${r.id}`, r])),
});

describe("createVaultCache", () => {
  test("keeps an entry and drops it on request", () => {
    const cache = createVaultCache({ maxAccounts: 5, maxBytes: 1_000_000, idleMs: 60_000 });
    const e = entry(record("a"));
    cache.set("u1", e);
    expect(cache.get("u1")).toBe(e);
    cache.drop("u1");
    expect(cache.get("u1")).toBeUndefined();
  });

  test("past the account budget, the least recently used goes", () => {
    const cache = createVaultCache({ maxAccounts: 2, maxBytes: 1_000_000, idleMs: 60_000 });
    cache.set("u1", entry(record("a")));
    cache.set("u2", entry(record("b")));
    cache.get("u1"); // u2 is now the least recently used
    cache.set("u3", entry(record("c")));
    expect(cache.get("u2")).toBeUndefined();
    expect(cache.get("u1")).toBeDefined();
    expect(cache.get("u3")).toBeDefined();
  });

  test("past the byte budget, the least recently used go until it fits", () => {
    const cache = createVaultCache({ maxAccounts: 10, maxBytes: 2_000, idleMs: 60_000 });
    cache.set("u1", entry(record("a", 700)));
    cache.set("u2", entry(record("b", 700)));
    cache.set("u3", entry(record("c", 700)));
    expect(cache.get("u1")).toBeUndefined();
    expect(cache.get("u2")).toBeDefined();
    expect(cache.get("u3")).toBeDefined();
  });

  test("an entry larger than the whole budget is not kept", () => {
    const cache = createVaultCache({ maxAccounts: 10, maxBytes: 500, idleMs: 60_000 });
    cache.set("u1", entry(record("a", 100)));
    cache.set("u2", entry(record("b", 600)));
    expect(cache.get("u2")).toBeUndefined();
    expect(cache.get("u1")).toBeDefined();
  });

  test("an entry without a request for idleMs is dropped", () => {
    let now = 0;
    const cache = createVaultCache({
      maxAccounts: 10,
      maxBytes: 1_000_000,
      idleMs: 30 * 60_000,
      now: () => now,
    });
    cache.set("u1", entry(record("a")));
    cache.set("u2", entry(record("b")));
    now = 20 * 60_000;
    expect(cache.get("u2")).toBeDefined(); // a request: u2 stays fresh
    now = 31 * 60_000;
    expect(cache.get("u1")).toBeUndefined();
    expect(cache.get("u2")).toBeDefined();
  });

  test("the lock runs one call at a time per account, and others in parallel", async () => {
    const cache = createVaultCache({ maxAccounts: 10, maxBytes: 1_000_000, idleMs: 60_000 });
    const events: string[] = [];
    let release: () => void = () => {};
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    const first = cache.lock("u1", async () => {
      events.push("first:start");
      await gate;
      events.push("first:end");
      return 1;
    });
    const second = cache.lock("u1", async () => {
      events.push("second:start");
      return 2;
    });
    const other = cache.lock("u2", async () => {
      events.push("other");
      return 3;
    });
    expect(await other).toBe(3);
    expect(events).toEqual(["first:start", "other"]);
    release();
    expect(await Promise.all([first, second])).toEqual([1, 2]);
    expect(events).toEqual(["first:start", "other", "first:end", "second:start"]);
  });

  test("a call that throws releases the lock", async () => {
    const cache = createVaultCache({ maxAccounts: 10, maxBytes: 1_000_000, idleMs: 60_000 });
    await expect(
      cache.lock("u1", async () => {
        throw new Error("boom");
      }),
    ).rejects.toThrow("boom");
    expect(await cache.lock("u1", async () => "next")).toBe("next");
  });
});
