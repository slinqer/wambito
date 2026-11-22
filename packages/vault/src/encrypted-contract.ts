import { describe, expect, it, vi } from "vitest";
import { type EncryptedStore, VaultClosedError } from "./encrypted.ts";
import type { RecordBodies } from "./store.ts";

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

/** What every `EncryptedStore` must do; the IndexedDB and the in-memory store both run it. */
export function encryptedStoreContract(
  name: string,
  make: () => EncryptedStore | Promise<EncryptedStore>,
) {
  describe(`${name}: the outbox`, () => {
    it("adds an entry with every key on create, in the same commit as the record", async () => {
      const store = await make();
      await store.put("category", "a", category("A"));
      const [entry] = await store.readOutbox(10);
      expect(entry).toMatchObject({ id: "a", type: "category", baseVersion: null, deleted: false });
      expect([...(entry?.touched ?? [])].sort()).toEqual(Object.keys(category("A")).sort());
    });

    it("merges later writes: union of touched fields, one entry per id, base kept", async () => {
      const store = await make();
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
      const store = await make();
      await store.put("category", "a", category("A"));
      await store.delete("category", "a");
      expect((await store.readOutbox(10))[0]?.deleted).toBe(true);
      const dead = await store.get("category", "a", { includeDeleted: true });
      if (dead) await store.put("category", "a", dead.body);
      expect((await store.readOutbox(10))[0]?.deleted).toBe(false);
    });

    it("rolls the outbox back with a failed transaction", async () => {
      const store = await make();
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
      const store = await make();
      await store.put("category", "b", category("B"));
      await store.put("category", "a", category("A"));
      await store.put("category", "b", category("B2"));
      expect((await store.readOutbox(10)).map((e) => e.id)).toEqual(["a", "b"]);
      expect((await store.readOutbox(1)).map((e) => e.id)).toEqual(["a"]);
    });

    it("acks only the write that was read: a newer write keeps its entry, based on the version", async () => {
      const store = await make();
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

  describe(`${name}: remote writes`, () => {
    it("store the version and key version, add no outbox entry, and notify", async () => {
      const store = await make();
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
      const store = await make();
      await store.put("category", "a", category("A"), { origin: "remote", version: 7, keyV: 1 });
      await store.put("category", "a", category("A2"));
      expect(await store.readOutbox(10)).toMatchObject([
        { baseVersion: 7, touched: ["name"], deleted: false },
      ]);
    });
  });

  describe(`${name}: meta, quarantine, wipe`, () => {
    it("keeps meta values", async () => {
      const store = await make();
      expect(await store.getMeta("latest")).toBeUndefined();
      await store.setMeta("latest", 42);
      expect(await store.getMeta("latest")).toBe(42);
    });

    it("deletes a meta value", async () => {
      const store = await make();
      await store.setMeta("ephemeral", true);
      await store.deleteMeta("ephemeral");
      expect(await store.getMeta("ephemeral")).toBeUndefined();
      // deleting an absent value is no error
      await store.deleteMeta("ephemeral");
    });

    it("counts quarantined records, one per version, and never overwrites", async () => {
      const store = await make();
      await store.quarantine({ id: "a", type: "category", version: 1, reason: "bad" });
      await store.quarantine({ id: "a", type: "category", version: 2, reason: "bad again" });
      await store.quarantine({ id: "a", type: "category", version: 2, reason: "bad again" });
      expect(await store.quarantineCount()).toBe(2);
    });

    it("a remote put or delete of a record clears its quarantine rows; a local write does not", async () => {
      const store = await make();
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
      const store = await make();
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

    it("resetAll leaves no record, no outbox entry and no cursor, and keeps keyV and deviceWrapId", async () => {
      const store = await make();
      const listener = vi.fn();
      await store.put("category", "a", category("A"));
      await store.put("category", "b", category("B"), { origin: "remote", version: 3, keyV: 1 });
      await store.delete("category", "b");
      await store.put("merchant", "m", {
        s: 1,
        merchantKey: "cafe",
        categoryId: CAT,
      });
      await store.quarantine({ id: "q", type: "merchant", version: 1, reason: "x" });
      // An entry already set aside by an earlier resync goes too.
      await store.wipeRecords();
      await store.put("category", "c", category("C"));
      await store.setMeta("latest", 5);
      await store.setMeta("base", 4);
      await store.setMeta("keyV", 2);
      await store.setMeta("deviceWrapId", "wrap-1");
      await store.setMeta("userId", "u");
      await store.putKey("k", "kept");
      store.subscribe(listener);
      await store.resetAll();
      for (const type of ["category", "merchant", "transaction", "settings"] as const) {
        expect(await store.list(type, { includeDeleted: true })).toEqual([]);
      }
      expect(await store.getRaw("category", "b")).toBeUndefined();
      expect(await store.readOutbox(100)).toEqual([]);
      expect(await store.quarantineCount()).toBe(0);
      expect(await store.getMeta("latest")).toBeUndefined();
      expect(await store.getMeta("base")).toBeUndefined();
      expect(await store.getMeta("keyV")).toBe(2);
      expect(await store.getMeta("deviceWrapId")).toBe("wrap-1");
      expect(await store.getMeta("userId")).toBe("u");
      expect(await store.getKey("k")).toBe("kept");
      expect(listener).toHaveBeenCalledTimes(1);
      // A write after the reset is an ordinary create again.
      await store.put("category", "a", category("A2"));
      expect(await store.readOutbox(10)).toMatchObject([
        { id: "a", baseVersion: null, deleted: false },
      ]);
    });

    it("keeps a set-aside body up to date with writes made before it is restored", async () => {
      const store = await make();
      await store.put("category", "a", category("A"), { origin: "remote", version: 3, keyV: 1 });
      await store.put("category", "a", category("A", "#111"));
      await store.wipeRecords();
      await store.put("category", "a", category("A2", "#111"));
      const [entry] = await store.readOutbox(10);
      expect(entry?.setAside?.body).toMatchObject({ name: "A2", color: "#111" });
      expect([...(entry?.touched ?? [])]).toEqual(expect.arrayContaining(["color", "name"]));
    });

    it("restores set-aside changes in one commit, as the resolver decides", async () => {
      const store = await make();
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

  describe(`${name}: pending ids and parked changes`, () => {
    it("a remote write with skipIfPending leaves a record with a pending change alone", async () => {
      const store = await make();
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
      const store = await make();
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
      const store = await make();
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

  describe(`${name}: re-sealing under a new key version`, () => {
    it("queues the pushed records under an older keyV, up to the limit, and a local write makes one an edit", async () => {
      const store = await make();
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

  describe(`${name}: a remote tombstone with a body`, () => {
    const remote = (version: number, keyV: number) =>
      ({ origin: "remote", version, keyV }) as const;

    it("a remote delete with tombstoneBody creates a tombstone for an unknown id", async () => {
      const store = await make();
      const listener = vi.fn();
      store.subscribe(listener);
      await store.delete("category", "z", { ...remote(6, 3), tombstoneBody: category("Gone") });
      expect(await store.get("category", "z")).toBeUndefined();
      expect(await store.get("category", "z", { includeDeleted: true })).toMatchObject({
        deleted: true,
        body: { name: "Gone" },
      });
      expect(await store.getRaw("category", "z")).toMatchObject({
        deleted: true,
        version: 6,
        keyV: 3,
      });
      expect(await store.readOutbox(10)).toEqual([]);
      expect(listener).toHaveBeenCalledTimes(1);
    });

    it("a remote delete without tombstoneBody still writes nothing for an unknown id", async () => {
      const store = await make();
      await store.delete("category", "z", remote(6, 3));
      expect(await store.getRaw("category", "z")).toBeUndefined();
    });

    it("a remote delete with tombstoneBody replaces the local tombstone's body", async () => {
      const store = await make();
      await store.put("category", "a", category("Old"), remote(1, 1));
      await store.delete("category", "a", { ...remote(2, 2), tombstoneBody: category("Server") });
      expect(await store.getRaw("category", "a")).toMatchObject({
        deleted: true,
        version: 2,
        keyV: 2,
        body: { name: "Server" },
      });
      expect(await store.readOutbox(10)).toEqual([]);
    });

    it("a remote delete with tombstoneBody and skipIfPending leaves a pending local change alone", async () => {
      const store = await make();
      await store.put("category", "a", category("Local"));
      await store.delete("category", "a", {
        ...remote(4, 1),
        skipIfPending: true,
        tombstoneBody: category("Server"),
      });
      await store.delete("category", "b", {
        ...remote(4, 1),
        skipIfPending: true,
        tombstoneBody: category("Server B"),
      });
      expect(await store.getRaw("category", "a")).toMatchObject({
        version: 0,
        deleted: false,
        body: { name: "Local" },
      });
      expect(await store.getRaw("category", "b")).toMatchObject({ deleted: true, version: 4 });
    });

    it("a local delete ignores tombstoneBody", async () => {
      const store = await make();
      await store.put("category", "a", category("Mine"));
      await store.delete("category", "a", { tombstoneBody: category("Other") });
      expect(await store.getRaw("category", "a")).toMatchObject({ body: { name: "Mine" } });
    });

    it("keyVersionsInUse counts a pushed tombstone with a body", async () => {
      const store = await make();
      await store.delete("category", "z", { ...remote(3, 4), tombstoneBody: category("Gone") });
      expect(await store.keyVersionsInUse()).toEqual(new Set([4]));
    });

    it("keyVersionsInUse does not count a pushed tombstone without a body", async () => {
      const store = await make();
      await store.put("category", "a", category("A"), remote(1, 1));
      await store.delete("category", "a", remote(2, 7));
      expect(await store.keyVersionsInUse()).toEqual(new Set());
    });

    it("queueReseal queues a pushed tombstone with a body under an older key, and its entry is a delete", async () => {
      const store = await make();
      await store.delete("category", "z", { ...remote(3, 1), tombstoneBody: category("Gone") });
      await store.put("category", "y", category("Y"), remote(1, 1));
      await store.delete("category", "y", remote(2, 1)); // no body: nothing to re-seal
      expect(await store.queueReseal(2, 5)).toBe(1);
      const entries = await store.readOutbox(10);
      expect(entries.map((e) => [e.id, e.reseal, e.baseVersion, e.deleted])).toEqual([
        ["z", true, 3, true],
      ]);
      expect(await store.get("category", "z", { includeDeleted: true })).toMatchObject({
        deleted: true,
      });
      // Acked under the current key: it is no longer queued.
      await store.ackOutbox("z", 4, entries[0]?.seq ?? 0, 2);
      expect(await store.queueReseal(2, 5)).toBe(0);
    });

    it("an acked delete of a tombstone the server held without a body counts its key", async () => {
      const store = await make();
      await store.put("category", "a", category("A"), remote(1, 1));
      await store.delete("category", "a", remote(2, 3)); // the server's tombstone has no body
      expect(await store.keyVersionsInUse()).toEqual(new Set());
      // The person's delete wins: put, then a local delete, pushed with the body.
      await store.put("category", "a", category("Mine"));
      await store.delete("category", "a");
      const [entry] = await store.readOutbox(10);
      await store.ackOutbox("a", 3, entry?.seq ?? 0, 4, true);
      expect(await store.keyVersionsInUse()).toEqual(new Set([4]));
    });

    it("an ack keeps a tombstone bodiless unless the push carried a body", async () => {
      const store = await make();
      for (const id of ["a", "b"]) {
        await store.put("category", id, category("Old"), remote(1, 1));
        // A pending edit, then the server's tombstone without a body over it.
        await store.put("category", id, category("Mine"));
        await store.delete("category", id, remote(2, 1));
        expect((await store.getRaw("category", id))?.bodiless).toBe(true);
      }
      const entries = await store.readOutbox(10);
      const seq = (id: string) => entries.find((e) => e.id === id)?.seq ?? 0;
      await store.ackOutbox("a", 3, seq("a"), 2);
      await store.ackOutbox("b", 3, seq("b"), 3, false);
      for (const id of ["a", "b"]) {
        expect(await store.getRaw("category", id)).toMatchObject({ version: 3, bodiless: true });
      }
      expect(await store.keyVersionsInUse()).toEqual(new Set());
      expect(await store.queueReseal(5, 10)).toBe(0);
      expect(await store.readOutbox(10)).toEqual([]);

      // A push that carried the body: the server's tombstone holds it now.
      await store.put("category", "c", category("Old"), remote(4, 1));
      await store.put("category", "c", category("Mine"));
      await store.delete("category", "c", remote(5, 1));
      const [c] = await store.readOutbox(10);
      await store.ackOutbox("c", 6, c?.seq ?? 0, 4, true);
      expect((await store.getRaw("category", "c"))?.bodiless).toBeUndefined();
      expect(await store.keyVersionsInUse()).toEqual(new Set([4]));
    });

    it("a remote delete with tombstoneBody and ifSeq does nothing after a newer local write", async () => {
      const store = await make();
      await store.put("category", "a", category("Old"), remote(1, 1));
      await store.put("category", "a", category("Local"));
      const [read] = await store.readOutbox(1);
      await store.put("category", "a", category("Newer"));
      await store.delete("category", "a", {
        ...remote(2, 1),
        ifSeq: read?.seq ?? 0,
        tombstoneBody: category("Server"),
      });
      expect(await store.getRaw("category", "a")).toMatchObject({
        deleted: false,
        version: 1,
        body: { name: "Newer" },
      });
      expect((await store.readOutbox(1))[0]?.seq).toBeGreaterThan(read?.seq ?? 0);
    });

    it("queueReseal shares its limit between records and tombstones", async () => {
      const store = await make();
      await store.put("category", "a", category("A"), remote(1, 1));
      await store.delete("category", "z", { ...remote(3, 1), tombstoneBody: category("Gone") });
      expect(await store.queueReseal(2, 1)).toBe(1);
      expect(await store.queueReseal(2, 1)).toBe(0);
    });
  });

  describe(`${name}: keys and closing`, () => {
    it("keeps keys by name, lists and deletes them", async () => {
      const store = await make();
      await store.putKey("record:1", "r");
      await store.putKey("device", "d");
      expect(await store.getKey("record:1")).toBe("r");
      expect((await store.keyNames()).sort()).toEqual(["device", "record:1"]);
      await store.deleteKey("record:1");
      expect(await store.getKey("record:1")).toBeUndefined();
      expect(await store.keyNames()).toEqual(["device"]);
    });

    it("close() tells the listener once, then every operation rejects with VaultClosedError", async () => {
      const store = await make();
      const closed = vi.fn();
      store.onClosed(closed);
      await store.put("category", "a", category("A"));
      expect(store.isClosed()).toBe(false);
      store.close();
      store.close();
      expect(closed).toHaveBeenCalledTimes(1);
      expect(store.isClosed()).toBe(true);
      await expect(store.list("category")).rejects.toBeInstanceOf(VaultClosedError);
      await expect(store.readOutbox(1)).rejects.toBeInstanceOf(VaultClosedError);
    });
  });
}
