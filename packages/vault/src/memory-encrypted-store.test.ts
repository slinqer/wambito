import { expect, test } from "vitest";
import { encryptedStoreContract } from "./encrypted-contract.ts";
import { createMemoryEncryptedStore } from "./memory-encrypted-store.ts";
import { storeContract } from "./store-contract.ts";

storeContract("memory encrypted store", () => createMemoryEncryptedStore("u1"));
encryptedStoreContract("memory encrypted store", () => createMemoryEncryptedStore("u1"));

test("a subscriber that throws does not undo the transaction's writes", async () => {
  const store = createMemoryEncryptedStore("u1");
  const seen: string[] = [];
  store.subscribe(() => {
    throw new Error("bad subscriber");
  });
  store.subscribe(() => seen.push("ok"));
  const body = {
    s: 1,
    name: "A",
    kind: "expense",
    icon: "x",
    color: "#fff",
    sortOrder: 0,
    archivedAt: null,
    systemKey: null,
  } as const;
  await store.transaction((tx) => tx.put("category", "a", body));
  expect((await store.get("category", "a"))?.body.name).toBe("A");
  expect(await store.readOutbox(10)).toHaveLength(1);
  expect(seen).toEqual(["ok"]);
});
