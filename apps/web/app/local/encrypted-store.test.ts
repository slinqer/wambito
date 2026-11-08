import "fake-indexeddb/auto";
import {
  deriveRecordKeys,
  generateDataKey,
  generateDeviceKeyPair,
  openRecord,
  sealRecord,
} from "@wambito/crypto";
import { describe, expect, it, vi } from "vitest";
import { deleteVault, vaultName } from "./db.ts";
import { createEncryptedStore } from "./encrypted-store.ts";
import type { RecordBodies } from "./store.ts";
import { storeContract } from "./store-contract.ts";

let counter = 0;
const fresh = () => createEncryptedStore(`user-${++counter}`);

storeContract("encrypted store", fresh);

const CAT = "01930000-0000-7000-8000-00000000000a";
const category = (name: string, color = "#fff"): RecordBodies["category"] => ({
  s: 1,
  name,
  kind: "expense",
  icon: "x",
  color,
  sortOrder: 0,
  archivedAt: null,
  systemKey: null,
});

describe("the outbox", () => {
  it("adds an entry with every key on create, in the same commit as the record", async () => {
    const store = await fresh();
    await store.put("category", "a", category("A"));
    const [entry] = await store.readOutbox(10);
    expect(entry).toMatchObject({ id: "a", type: "category", baseVersion: null, deleted: false });
    expect([...(entry?.touched ?? [])].sort()).toEqual(Object.keys(category("A")).sort());
  });

  it("merges later writes: union of touched fields, one entry per id, base kept", async () => {
    const store = await fresh();
    await store.put("category", "a", category("A"));
    await store.ackOutbox("a", 3, (await store.readOutbox(1))[0]?.seq ?? 0);
    expect(await store.readOutbox(10)).toEqual([]);
    await store.put("category", "a", category("A2"));
    await store.put("category", "a", { ...category("A2"), color: "#000" });
    const entries = await store.readOutbox(10);
    expect(entries.length).toBe(1);
    expect(entries[0]).toMatchObject({ baseVersion: 3, deleted: false });
    expect([...(entries[0]?.touched ?? [])].sort()).toEqual(["color", "name"]);
  });

  it("a delete marks the entry deleted; a restore before the push clears it again", async () => {
    const store = await fresh();
    await store.put("category", "a", category("A"));
    await store.delete("category", "a");
    expect((await store.readOutbox(10))[0]?.deleted).toBe(true);
    const dead = await store.get("category", "a", { includeDeleted: true });
    if (dead) await store.put("category", "a", dead.body);
    expect((await store.readOutbox(10))[0]?.deleted).toBe(false);
  });

  it("rolls the outbox back with a failed transaction", async () => {
    const store = await fresh();
    await expect(
      store.transaction(async (tx) => {
        await tx.put("category", "a", category("A"));
        throw new Error("boom");
      }),
    ).rejects.toThrow("boom");
    expect(await store.readOutbox(10)).toEqual([]);
    expect(await store.list("category")).toEqual([]);
  });

  it("limits and orders readOutbox by write order", async () => {
    const store = await fresh();
    await store.put("category", "b", category("B"));
    await store.put("category", "a", category("A"));
    await store.put("category", "b", category("B2"));
    expect((await store.readOutbox(10)).map((e) => e.id)).toEqual(["a", "b"]);
    expect((await store.readOutbox(1)).map((e) => e.id)).toEqual(["a"]);
  });

  it("acks only the write that was read: a newer write keeps its entry, based on the version", async () => {
    const store = await fresh();
    await store.put("category", "a", category("A"));
    const [read] = await store.readOutbox(10);
    await store.put("category", "a", category("A2"));
    await store.ackOutbox("a", 1, read?.seq ?? 0);
    expect((await store.getRaw("category", "a"))?.version).toBe(1);
    const [left] = await store.readOutbox(10);
    expect(left).toMatchObject({ id: "a", baseVersion: 1 });
    await store.ackOutbox("a", 2, left?.seq ?? 0);
    expect(await store.readOutbox(10)).toEqual([]);
    expect((await store.getRaw("category", "a"))?.version).toBe(2);
  });
});

describe("remote writes", () => {
  it("store the version and key version, add no outbox entry, and notify", async () => {
    const store = await fresh();
    const listener = vi.fn();
    store.subscribe(listener);
    await store.put("category", "a", category("A"), { origin: "remote", version: 7, keyV: 2 });
    expect(await store.readOutbox(10)).toEqual([]);
    expect(await store.getRaw("category", "a")).toMatchObject({
      version: 7,
      keyV: 2,
      deleted: false,
    });
    await store.delete("category", "a", { origin: "remote", version: 8, keyV: 2 });
    expect(await store.readOutbox(10)).toEqual([]);
    expect(await store.getRaw("category", "a")).toMatchObject({ version: 8, deleted: true });
    expect(listener).toHaveBeenCalledTimes(2);
  });

  it("a local edit of a synced record is based on its server version", async () => {
    const store = await fresh();
    await store.put("category", "a", category("A"), { origin: "remote", version: 7, keyV: 1 });
    await store.put("category", "a", category("A2"));
    expect(await store.readOutbox(10)).toMatchObject([
      { baseVersion: 7, touched: ["name"], deleted: false },
    ]);
  });
});

describe("meta, quarantine, wipe", () => {
  it("keeps meta values", async () => {
    const store = await fresh();
    expect(await store.getMeta("latest")).toBeUndefined();
    await store.setMeta("latest", 42);
    expect(await store.getMeta("latest")).toBe(42);
  });

  it("counts quarantined records, one per version, and never overwrites", async () => {
    const store = await fresh();
    await store.quarantine({ id: "a", type: "category", version: 1, reason: "bad" });
    await store.quarantine({ id: "a", type: "category", version: 2, reason: "bad again" });
    await store.quarantine({ id: "a", type: "category", version: 2, reason: "bad again" });
    expect(await store.quarantineCount()).toBe(2);
  });

  it("wipes records, outbox, quarantine and the cursors, but not the keys or userId", async () => {
    const store = await fresh();
    const listener = vi.fn();
    await store.put("category", "a", category("A"));
    await store.quarantine({ id: "q", type: "merchant", version: 1, reason: "x" });
    await store.setMeta("latest", 5);
    await store.setMeta("base", 4);
    await store.setMeta("keyV", 1);
    await store.setMeta("userId", "u");
    await store.putKey("k", "kept");
    store.subscribe(listener);
    await store.wipeRecords();
    expect(await store.list("category", { includeDeleted: true })).toEqual([]);
    expect(await store.readOutbox(10)).toEqual([]);
    expect(await store.quarantineCount()).toBe(0);
    expect(await store.getMeta("latest")).toBeUndefined();
    expect(await store.getMeta("base")).toBeUndefined();
    expect(await store.getMeta("keyV")).toBe(1);
    expect(await store.getMeta("userId")).toBe("u");
    expect(await store.getKey("k")).toBe("kept");
    expect(listener).toHaveBeenCalledTimes(1);
  });
});

describe("keys and the vault", () => {
  it("stores non-extractable record keys that still open what they sealed, and the device key", async () => {
    const store = await fresh();
    const keys = await deriveRecordKeys(generateDataKey());
    await store.putKey("record", keys.record);
    await store.putKey("dedupe", keys.dedupe);
    const device = await generateDeviceKeyPair();
    await store.putKey("device", device.privateKey);
    const record = await store.getKey<CryptoKey>("record");
    expect(record?.extractable).toBe(false);
    const ctx = { userId: "u", type: "category", id: CAT, keyV: 1 } as const;
    const sealed = await sealRecord(keys, ctx, { hi: 1 });
    expect(
      await openRecord({ record: record as CryptoKey, dedupe: keys.dedupe }, ctx, sealed),
    ).toEqual({
      hi: 1,
    });
    expect(await store.getKey("device")).toBeTruthy();
  });

  it("deleteVault removes the database, keys and records", async () => {
    const userId = `gone-${++counter}`;
    const store = await createEncryptedStore(userId);
    await store.put("category", "a", category("A"));
    await store.putKey("k", "v");
    store.close();
    await deleteVault(userId);
    const names = (await indexedDB.databases()).map((d) => d.name);
    expect(names).not.toContain(vaultName(userId));
    const again = await createEncryptedStore(userId);
    expect(await again.list("category")).toEqual([]);
    expect(await again.getKey("k")).toBeUndefined();
  });
});
