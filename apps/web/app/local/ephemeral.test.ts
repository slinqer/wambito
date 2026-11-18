import "fake-indexeddb/auto";
import { describe, expect, it } from "vitest";
import { META, openVault, vaultName } from "./db.ts";
import { wipeForeignEphemeralVaults } from "./ephemeral.ts";

/** A vault for `userId`, its meta `ephemeral` set when asked (as `enrollDevice` does). */
async function makeVault(userId: string, ephemeral: boolean) {
  const db = await openVault(userId);
  if (ephemeral) {
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(META, "readwrite");
      tx.objectStore(META).put(true, "ephemeral");
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  }
  db.close();
}

const names = async () =>
  (await indexedDB.databases())
    .map((d) => d.name ?? "")
    .filter((name) => name.startsWith(vaultName("")))
    .sort();

const clear = async () => {
  for (const name of await names()) {
    await new Promise<void>((resolve) => {
      const del = indexedDB.deleteDatabase(name);
      del.onsuccess = () => resolve();
      del.onerror = () => resolve();
    });
  }
};

describe("wipeForeignEphemeralVaults", () => {
  it("a vault marked ephemeral of another user is deleted; the signed-in user's and a non-ephemeral one stay", async () => {
    await clear();
    await makeVault("ana", true);
    await makeVault("bea", true);
    await makeVault("cid", false);
    await wipeForeignEphemeralVaults("bea");
    expect(await names()).toEqual([vaultName("bea"), vaultName("cid")]);
  });

  it("signed out: every ephemeral vault goes, the others stay", async () => {
    await clear();
    await makeVault("ana", true);
    await makeVault("cid", false);
    await wipeForeignEphemeralVaults(null);
    expect(await names()).toEqual([vaultName("cid")]);
  });

  it("never throws, and does nothing where the browser cannot list databases", async () => {
    await clear();
    await makeVault("ana", true);
    await wipeForeignEphemeralVaults("bea", { databases: undefined });
    expect(await names()).toEqual([vaultName("ana")]);
    await expect(
      wipeForeignEphemeralVaults("bea", {
        databases: async () => {
          throw new Error("denied");
        },
      }),
    ).resolves.toBeUndefined();
  });
});
