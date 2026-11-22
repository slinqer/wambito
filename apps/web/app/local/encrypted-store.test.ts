import "fake-indexeddb/auto";
import {
  deriveRecordKeys,
  generateDataKey,
  generateDeviceKeyPair,
  openRecord,
  sealRecord,
} from "@wambito/crypto";
import { type RecordBodies, VaultClosedError } from "@wambito/vault";
import { encryptedStoreContract, storeContract } from "@wambito/vault/contract";
import { describe, expect, it, vi } from "vitest";
import { deleteVault, vaultName } from "./db.ts";
import { createEncryptedStore } from "./encrypted-store.ts";

let counter = 0;
const fresh = () => createEncryptedStore(`user-${++counter}`);

storeContract("IndexedDB store", fresh);
encryptedStoreContract("IndexedDB store", fresh);

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

describe("the version 2 upgrade", () => {
  it("marks every tombstone of a version 1 vault as without a server body", async () => {
    const userId = `upgrade-${++counter}`;
    const { RECORD_TYPES } = await import("@wambito/core");
    const old = await new Promise<IDBDatabase>((resolve, reject) => {
      const open = indexedDB.open(vaultName(userId), 1);
      open.onupgradeneeded = () => {
        const db = open.result;
        for (const type of RECORD_TYPES) db.createObjectStore(type, { keyPath: "id" });
        db.createObjectStore("outbox", { keyPath: "id" });
        db.createObjectStore("meta");
        db.createObjectStore("quarantine", { keyPath: ["type", "id", "version"] });
        db.createObjectStore("keys");
      };
      open.onsuccess = () => resolve(open.result);
      open.onerror = () => reject(open.error);
    });
    const tx = old.transaction("category", "readwrite");
    const rows = tx.objectStore("category");
    const row = (id: string, deleted: boolean) => ({
      id,
      body: category(id),
      deleted,
      version: 2,
      keyV: 1,
      n: 1,
    });
    rows.put(row("live", false));
    rows.put(row("dead", true));
    await new Promise((resolve) => {
      tx.oncomplete = resolve;
    });
    old.close();
    const store = await createEncryptedStore(userId);
    expect((await store.getRaw("category", "live"))?.deleted).toBe(false);
    expect(await store.keyVersionsInUse()).toEqual(new Set([1])); // the live one only
    expect(await store.queueReseal(2, 10)).toBe(1);
    expect((await store.readOutbox(10)).map((e) => e.id)).toEqual(["live"]);
  });
});
