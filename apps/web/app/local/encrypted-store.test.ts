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
import { createEncryptedStore, VaultClosedError } from "./encrypted-store.ts";
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

  it("a remote put or delete of a record clears its quarantine rows; a local write does not", async () => {
    const store = await fresh();
    const remote = { origin: "remote", version: 3, keyV: 2 } as const;
    await store.quarantine({ id: "a", type: "category", version: 1, reason: "x", keyV: 2 });
    await store.quarantine({ id: "a", type: "category", version: 2, reason: "x", keyV: 2 });
    await store.quarantine({ id: "b", type: "category", version: 1, reason: "x", keyV: 2 });
    await store.quarantine({ id: "c", type: "category", version: 1, reason: "x", keyV: 2 });
    await store.quarantine({ id: "a", type: "merchant", version: 1, reason: "x", keyV: 2 });
    await store.put("category", "c", category("C"));
    expect(await store.quarantineCount()).toBe(5);
    await store.put("category", "a", category("A"), remote);
    expect(await store.quarantineCount()).toBe(3);
    // a tombstone of a record this browser never had
    await store.delete("category", "b", remote);
    expect(await store.quarantineCount()).toBe(2);
    expect((await store.quarantined()).map((q) => `${q.type}:${q.id}`).sort()).toEqual([
      "category:c",
      "merchant:a",
    ]);
  });

  it("wipes records, quarantine and the cursors, but not the keys, userId or outbox", async () => {
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
    expect(await store.quarantineCount()).toBe(0);
    expect(await store.getMeta("latest")).toBeUndefined();
    expect(await store.getMeta("base")).toBeUndefined();
    expect(await store.getMeta("keyV")).toBe(1);
    expect(await store.getMeta("userId")).toBe("u");
    expect(await store.getKey("k")).toBe("kept");
    expect(listener).toHaveBeenCalledTimes(1);
    // The pending change is set aside with its body, in the same commit as the wipe.
    expect(await store.readOutbox(10)).toMatchObject([
      { id: "a", setAside: { body: category("A") } },
    ]);
  });

  it("keeps a set-aside body up to date with writes made before it is restored", async () => {
    const store = await fresh();
    await store.put("category", "a", category("A"), { origin: "remote", version: 3, keyV: 1 });
    await store.put("category", "a", category("A", "#111"));
    await store.wipeRecords();
    await store.put("category", "a", category("A2", "#111"));
    const [entry] = await store.readOutbox(10);
    expect(entry?.setAside?.body).toMatchObject({ name: "A2", color: "#111" });
    expect([...(entry?.touched ?? [])]).toEqual(expect.arrayContaining(["color", "name"]));
  });

  it("restores set-aside changes in one commit, as the resolver decides", async () => {
    const store = await fresh();
    await store.put("category", "a", category("A", "#111"));
    await store.put("category", "b", category("B"));
    await store.put("category", "c", category("C"));
    await store.wipeRecords();
    await store.put("category", "a", category("Server A"), {
      origin: "remote",
      version: 9,
      keyV: 1,
    });
    await store.put("category", "b", category("Server B"), {
      origin: "remote",
      version: 10,
      keyV: 1,
    });
    const listener = vi.fn();
    store.subscribe(listener);
    const seen: Array<[string, number | undefined]> = [];
    await store.restoreSetAside((entry, fresh) => {
      seen.push([entry.id, fresh?.version]);
      if (entry.id === "a") return { put: { ...category("Server A"), color: "#111" } };
      if (entry.id === "b") return { delete: true };
      return { drop: true };
    });
    expect(seen.sort()).toEqual([
      ["a", 9],
      ["b", 10],
      ["c", undefined],
    ]);
    expect(listener).toHaveBeenCalledTimes(1);
    const outbox = await store.readOutbox(10);
    expect(outbox.map((e) => [e.id, e.baseVersion, e.deleted, e.setAside])).toEqual([
      ["a", 9, false, undefined],
      ["b", 10, true, undefined],
    ]);
    expect((await store.get("category", "a"))?.body).toMatchObject({
      name: "Server A",
      color: "#111",
    });
    expect(await store.get("category", "b")).toBeUndefined();
    expect(await store.get("category", "c")).toBeUndefined();
  });
});

describe("pending ids and parked changes", () => {
  it("a remote write with skipIfPending leaves a record with a pending change alone", async () => {
    const store = await fresh();
    await store.put("category", "a", category("Local"));
    await store.transaction(async (tx) => {
      const remote = { origin: "remote", version: 4, keyV: 1, skipIfPending: true } as const;
      await tx.put("category", "a", category("Server"), remote);
      await tx.put("category", "b", category("Server B"), remote);
      await tx.delete("category", "a", remote);
    });
    expect(await store.getRaw("category", "a")).toMatchObject({
      version: 0,
      deleted: false,
      body: { name: "Local" },
    });
    expect((await store.getRaw("category", "b"))?.version).toBe(4);
  });

  it("a remote write with ifSeq applies only while the outbox entry is that write", async () => {
    const store = await fresh();
    await store.put("category", "a", category("Local"));
    const [read] = await store.readOutbox(1);
    const seq = read?.seq ?? 0;
    await store.put("category", "a", category("Merged"), {
      origin: "remote",
      version: 2,
      ifSeq: seq,
    });
    expect(await store.getRaw("category", "a")).toMatchObject({
      version: 2,
      body: { name: "Merged" },
    });
    await store.put("category", "a", category("Newer"));
    await store.put("category", "a", category("Stale"), {
      origin: "remote",
      version: 3,
      ifSeq: seq,
    });
    expect(await store.getRaw("category", "a")).toMatchObject({
      version: 2,
      body: { name: "Newer" },
    });
  });

  it("parks only the write that was read, and a later local write clears the park", async () => {
    const store = await fresh();
    await store.put("category", "a", category("A"));
    const [read] = await store.readOutbox(1);
    const park = { attempts: 1, lastError: "rejected_422", until: 1000 };
    await store.parkOutbox("a", read?.seq ?? 0, park);
    expect((await store.readOutbox(1))[0]?.park).toEqual(park);
    await store.put("category", "a", category("A2"));
    expect((await store.readOutbox(1))[0]?.park).toBeUndefined();
    await store.parkOutbox("a", read?.seq ?? 0, park);
    expect((await store.readOutbox(1))[0]?.park).toBeUndefined();
  });
});

describe("other tabs", () => {
  it("notifies a store open on the same vault in another tab after a commit", async () => {
    const userId = `tabs-${++counter}`;
    const one = await createEncryptedStore(userId);
    const two = await createEncryptedStore(userId);
    const listener = vi.fn();
    two.subscribe(listener);
    await one.put("category", "a", category("A"));
    await vi.waitFor(() => expect(listener).toHaveBeenCalledTimes(1));
    expect((await two.get("category", "a"))?.body.name).toBe("A");
    one.close();
    two.close();
  });

  it("closes when another tab deletes the vault, then rejects with VaultClosedError", async () => {
    const userId = `closing-${++counter}`;
    const store = await createEncryptedStore(userId);
    const closed = vi.fn();
    store.onClosed(closed);
    await store.put("category", "a", category("A"));
    await deleteVault(userId);
    expect(closed).toHaveBeenCalledTimes(1);
    expect(store.isClosed()).toBe(true);
    await expect(store.list("category")).rejects.toBeInstanceOf(VaultClosedError);
    await expect(store.readOutbox(1)).rejects.toBeInstanceOf(VaultClosedError);
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

describe("re-sealing under a new key version", () => {
  it("queues the pushed records under an older keyV, up to the limit, and a local write makes one an edit", async () => {
    const store = await fresh();
    const remote = (version: number, keyV: number) =>
      ({ origin: "remote", version, keyV }) as const;
    await store.put("category", "a", category("A"), remote(1, 1));
    await store.put("category", "b", category("B"), remote(2, 1));
    await store.put("category", "c", category("C"), remote(3, 2));
    await store.put("category", "d", category("D")); // never pushed: nothing to re-seal
    await store.put("category", "e", category("E"), remote(4, 1));
    await store.delete("category", "e", remote(5, 1)); // a tombstone has no body
    expect(await store.keyVersionsInUse()).toEqual(new Set([1, 2]));
    // a quarantined record may still be retried under its key version
    await store.quarantine({ id: "q", type: "category", version: 9, reason: "x", keyV: 5 });
    expect(await store.keyVersionsInUse()).toEqual(new Set([1, 2, 5]));
    expect(await store.queueReseal(2, 1)).toBe(1);
    expect(await store.queueReseal(2, 1)).toBe(0); // one pending already fills the limit
    expect(await store.queueReseal(2, 5)).toBe(1);
    const reseals = (await store.readOutbox(10)).filter((e) => e.reseal);
    expect(reseals.map((e) => [e.id, e.baseVersion, e.touched]).sort()).toEqual([
      ["a", 1, []],
      ["b", 2, []],
    ]);
    // Acked under keyV 2: the record is under 2 now.
    await store.ackOutbox("a", 6, reseals.find((e) => e.id === "a")?.seq ?? 0, 2);
    expect(await store.getRaw("category", "a")).toMatchObject({ version: 6, keyV: 2 });
    // The person edits b before its re-seal went: an ordinary edit, based on the same version.
    await store.put("category", "b", category("B2"));
    const [b] = (await store.readOutbox(10)).filter((e) => e.id === "b");
    expect(b).toMatchObject({ baseVersion: 2, touched: ["name"] });
    expect(b?.reseal).toBeUndefined();
  });
});
