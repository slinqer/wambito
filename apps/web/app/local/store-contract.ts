import { describe, expect, it, vi } from "vitest";
import type { FinanceStore, RecordBodies } from "./store.ts";

const CAT = "01930000-0000-7000-8000-00000000000a";
const category = (name: string): RecordBodies["category"] => ({
  s: 1,
  name,
  kind: "expense",
  icon: "x",
  color: "#fff",
  sortOrder: 0,
  archivedAt: null,
  systemKey: null,
});
const merchant = (key: string): RecordBodies["merchant"] => ({
  s: 1,
  merchantKey: key,
  categoryId: CAT,
});

/** What every `FinanceStore` must do; the memory and the encrypted store both run it. */
export function storeContract(name: string, make: () => FinanceStore | Promise<FinanceStore>) {
  describe(`${name}: the FinanceStore contract`, () => {
    it("puts, gets and lists per type, in first-written order", async () => {
      const store = await make();
      await store.put("category", "b", category("B"));
      await store.put("category", "a", category("A"));
      await store.put("merchant", "m", merchant("cafe"));
      expect((await store.get("category", "a"))?.body.name).toBe("A");
      expect((await store.list("category")).map((r) => r.id)).toEqual(["b", "a"]);
      expect((await store.list("merchant")).length).toBe(1);
      expect(await store.get("category", "zzz")).toBeUndefined();
    });

    it("replaces on put, keeping the position", async () => {
      const store = await make();
      await store.put("category", "a", category("A"));
      await store.put("category", "b", category("B"));
      await store.put("category", "a", category("A2"));
      expect((await store.list("category")).map((r) => r.body.name)).toEqual(["A2", "B"]);
    });

    it("does not share objects with the caller", async () => {
      const store = await make();
      const body = category("A");
      await store.put("category", "a", body);
      body.name = "changed";
      const read = await store.get("category", "a");
      expect(read?.body.name).toBe("A");
      if (read) read.body.name = "changed too";
      expect((await store.get("category", "a"))?.body.name).toBe("A");
    });

    it("deletes to a tombstone that only includeDeleted shows, and a put revives it", async () => {
      const store = await make();
      await store.put("category", "a", category("A"));
      await store.delete("category", "a");
      expect(await store.get("category", "a")).toBeUndefined();
      expect(await store.list("category")).toEqual([]);
      expect((await store.get("category", "a", { includeDeleted: true }))?.deleted).toBe(true);
      expect((await store.list("category", { includeDeleted: true })).length).toBe(1);
      const dead = await store.get("category", "a", { includeDeleted: true });
      if (dead) await store.put("category", "a", dead.body);
      expect((await store.get("category", "a"))?.deleted).toBe(false);
    });

    it("ignores deleting an unknown id", async () => {
      const store = await make();
      await store.delete("category", "nope");
      expect(await store.list("category", { includeDeleted: true })).toEqual([]);
    });

    it("commits a transaction's writes together and lets it read its own writes", async () => {
      const store = await make();
      await store.put("category", "a", category("A"));
      const seen = await store.transaction(async (tx) => {
        await tx.put("category", "b", category("B"));
        await tx.delete("category", "a");
        return (await tx.list("category")).map((r) => r.id);
      });
      expect(seen).toEqual(["b"]);
      expect((await store.list("category")).map((r) => r.id)).toEqual(["b"]);
    });

    it("rolls a failed transaction back", async () => {
      const store = await make();
      await store.put("category", "a", category("A"));
      await expect(
        store.transaction(async (tx) => {
          await tx.put("category", "b", category("B"));
          await tx.delete("category", "a");
          throw new Error("boom");
        }),
      ).rejects.toThrow("boom");
      expect((await store.list("category")).map((r) => r.id)).toEqual(["a"]);
    });

    it("runs transactions one after the other", async () => {
      const store = await make();
      await store.put("merchant", "m", merchant("0"));
      const bump = () =>
        store.transaction(async (tx) => {
          const current = Number((await tx.get("merchant", "m"))?.body.merchantKey);
          await Promise.resolve();
          await tx.put("merchant", "m", merchant(String(current + 1)));
        });
      await Promise.all([bump(), bump(), bump()]);
      expect((await store.get("merchant", "m"))?.body.merchantKey).toBe("3");
    });

    it("notifies subscribers once per commit, not for a rollback, until unsubscribed", async () => {
      const store = await make();
      const listener = vi.fn();
      const off = store.subscribe(listener);
      await store.put("category", "a", category("A"));
      expect(listener).toHaveBeenCalledTimes(1);
      await store.transaction(async (tx) => {
        await tx.put("category", "b", category("B"));
        await tx.put("category", "c", category("C"));
      });
      expect(listener).toHaveBeenCalledTimes(2);
      await store.transaction(async (tx) => {
        await tx.put("category", "d", category("D"));
        await tx.get("category", "d");
      });
      await expect(
        store.transaction(async (tx) => {
          await tx.put("category", "e", category("E"));
          throw new Error("no");
        }),
      ).rejects.toThrow();
      expect(listener).toHaveBeenCalledTimes(3);
      off();
      await store.put("category", "f", category("F"));
      expect(listener).toHaveBeenCalledTimes(3);
    });

    it("does not notify for a transaction that only reads", async () => {
      const store = await make();
      const listener = vi.fn();
      store.subscribe(listener);
      await store.transaction(async (tx) => tx.list("category"));
      expect(listener).not.toHaveBeenCalled();
    });
  });
}
