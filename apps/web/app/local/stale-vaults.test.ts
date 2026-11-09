import "fake-indexeddb/auto";
import { describe, expect, it } from "vitest";
import { vaultName } from "./db.ts";
import { deleteStaleVaults } from "./stale-vaults.ts";

const makeDb = (name: string) =>
  new Promise<void>((resolve, reject) => {
    const open = indexedDB.open(name);
    open.onsuccess = () => {
      open.result.close();
      resolve();
    };
    open.onerror = () => reject(open.error);
  });

const names = async () => (await indexedDB.databases()).map((d) => d.name).sort();

describe("deleteStaleVaults", () => {
  it("signed out: deletes every vault, and only vaults", async () => {
    await makeDb(vaultName("ana"));
    await makeDb(vaultName("bea"));
    await makeDb("something-else");
    await deleteStaleVaults(null);
    expect(await names()).toEqual(["something-else"]);
  });

  it("signed in: keeps the signed-in person's vault, deletes the others", async () => {
    await makeDb(vaultName("ana"));
    await makeDb(vaultName("bea"));
    await deleteStaleVaults("bea");
    expect(await names()).toEqual(["something-else", vaultName("bea")].sort());
  });

  it("does nothing, without failing, where the browser cannot list databases", async () => {
    await makeDb(vaultName("cid"));
    await deleteStaleVaults(null, { databases: undefined });
    expect(await names()).toContain(vaultName("cid"));
  });

  it("never throws: a failed listing or delete is left for the next time", async () => {
    await expect(
      deleteStaleVaults(null, {
        databases: async () => {
          throw new Error("denied");
        },
      }),
    ).resolves.toBeUndefined();
  });
});
