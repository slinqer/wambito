import "fake-indexeddb/auto";
import { SUGGESTED_CATEGORIES } from "@wambito/core";
import { deriveRecordKeys, generateDataKey } from "@wambito/crypto";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createEncryptedStore, type EncryptedStore } from "./encrypted-store.ts";
import { uuidv5 } from "./ids.ts";
import {
  forgetVault,
  openVaultSession,
  VaultOpenError,
  type VaultProfile,
} from "./vault-session.ts";

let counter = 0;
const profileOf = (): VaultProfile => ({
  id: `vault_user_${++counter}`,
  email: "ana@wambito.test",
  isAnonymous: false,
  locale: "es",
  timezone: "America/Bogota",
});

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

/** An empty `/v2/sync` that takes every push; `mode` makes it fail. */
function fakeNetwork() {
  const net = {
    mode: "ok" as "ok" | "offline" | "unauthorized",
    pushed: 0,
    live: [] as string[],
    fetch: (async (input: RequestInfo | URL, init?: RequestInit) => {
      const request =
        input instanceof Request ? input : new Request(new URL(String(input), "http://x"), init);
      const url = new URL(request.url);
      if (net.mode === "offline") throw new TypeError("offline");
      if (net.mode === "unauthorized") return json({ code: "unauthenticated" }, 401);
      if (url.pathname === "/api/v2/sync" && request.method === "GET") {
        return json({ records: [], next: null, latest: net.pushed });
      }
      if (url.pathname === "/api/v2/sync" && request.method === "POST") {
        const { changes } = (await request.json()) as { changes: { id: string }[] };
        return json({ results: changes.map((c) => ({ id: c.id, version: ++net.pushed })) });
      }
      net.live.push(`${request.method} ${url.pathname}`);
      return new Response(null, { status: 204 });
    }) as typeof globalThis.fetch,
  };
  return net;
}

const keys = async () => ({ keys: await deriveRecordKeys(generateDataKey(), false), keyV: 1 });

const vaultExists = async (userId: string) =>
  (await indexedDB.databases()).some((d) => d.name === `wambito-vault-${userId}`);

afterEach(async () => {
  await forgetVault();
});

describe("openVaultSession", () => {
  it("seeds a new account with its settings and the suggested categories, as records", async () => {
    const net = fakeNetwork();
    const profile = profileOf();
    const session = await openVaultSession({
      profile,
      keys: await keys(),
      fresh: true,
      fetch: net.fetch,
    });
    const me = await (await session.fetch("http://app/api/v1/me")).json();
    expect(me).toMatchObject({
      id: profile.id,
      email: "ana@wambito.test",
      locale: "es",
      timezone: "America/Bogota",
      currency: "EUR",
      onboardingCompletedAt: null,
      encryption: "preview",
    });
    const categories = (await (await session.fetch("http://app/api/v1/categories")).json()) as {
      name: string;
    }[];
    expect(categories.length).toBeGreaterThan(3);
    expect(categories.map((c) => c.name)).toContain("Supermercado");

    // a second open in the tab reuses it, without seeding again
    const again = await openVaultSession({
      profile,
      keys: await keys(),
      fresh: false,
      fetch: net.fetch,
    });
    expect(again).toBe(session);
  });

  it("gives the seeded records ids made from the account, so two devices seed the same ones", async () => {
    const profile = profileOf();
    let opened: EncryptedStore | undefined;
    await openVaultSession({
      profile,
      keys: await keys(),
      fresh: true,
      fetch: fakeNetwork().fetch,
      openStore: async (userId) => {
        opened = await createEncryptedStore(userId);
        return opened;
      },
    });
    const store = opened as EncryptedStore;
    const [settings] = await store.list("settings");
    const categories = await store.list("category");
    expect(settings?.body).toMatchObject({
      timezone: "America/Bogota",
      locale: "es",
      currency: "EUR",
    });
    // The ids are the same on every device for this account, and differ between accounts.
    const namespace = await uuidv5("6f1f7a4e-0c5b-5e0a-9a3e-2b1d6c8f4a10", profile.id);
    expect(settings?.id).toBe(await uuidv5(namespace, "settings"));
    expect(categories.length).toBeGreaterThan(3);
    const ids = new Set(categories.map((c) => c.id));
    expect(ids.size).toBe(categories.length);
    for (const { id, body } of categories) {
      expect(body.createdAt).toBeUndefined();
      const key = SUGGESTED_CATEGORIES.find((c) => c.names.es === body.name)?.key;
      expect(id).toBe(await uuidv5(namespace, `category:${key}`));
    }
  });

  it("refuses what a preview account cannot do yet, and sends deleting the account to the API", async () => {
    const net = fakeNetwork();
    const session = await openVaultSession({
      profile: profileOf(),
      keys: await keys(),
      fresh: true,
      fetch: net.fetch,
    });
    const exported = await session.fetch("http://app/api/v1/me/export?format=json");
    expect(exported.status).toBe(403);
    expect((await session.fetch("http://app/api/v1/imports", { method: "POST" })).status).toBe(403);
    expect((await session.fetch("http://app/api/v1/me/assistants")).status).toBe(403);
    const deleted = await session.fetch(new Request("http://app/api/v1/me", { method: "DELETE" }));
    expect(deleted.status).toBe(204);
    expect(net.live).toEqual(["DELETE /api/v1/me"]);
  });

  it("a fresh vault needs its first sync; a known one opens offline on its local data", async () => {
    const net = fakeNetwork();
    net.mode = "offline";
    const profile = profileOf();
    const failed = await openVaultSession({
      profile,
      keys: await keys(),
      fresh: true,
      fetch: net.fetch,
    }).catch((e) => e);
    expect(failed).toBeInstanceOf(VaultOpenError);
    expect(failed.code).toBe("offline");

    const session = await openVaultSession({
      profile,
      keys: await keys(),
      fresh: false,
      fetch: net.fetch,
    });
    expect((await session.fetch("http://app/api/v1/me")).status).toBe(200);
  });

  it("a 401 from the sync stops the opening and reports it", async () => {
    const net = fakeNetwork();
    net.mode = "unauthorized";
    const onUnauthorized = vi.fn();
    const failed = await openVaultSession({
      profile: profileOf(),
      keys: await keys(),
      fresh: false,
      fetch: net.fetch,
      onUnauthorized,
    }).catch((e) => e);
    expect(failed).toBeInstanceOf(VaultOpenError);
    expect(failed.code).toBe("unauthorized");
    expect(onUnauthorized).toHaveBeenCalled();
  });
});

describe("a vault closed under the session", () => {
  it("drops the session and tells onClosed (another tab deleted or upgraded the vault)", async () => {
    const net = fakeNetwork();
    const profile = profileOf();
    let store: EncryptedStore | undefined;
    const session = await openVaultSession({
      profile,
      keys: await keys(),
      fresh: true,
      fetch: net.fetch,
      openStore: async (userId) => {
        store = await createEncryptedStore(userId);
        return store;
      },
    });
    const closed = vi.fn();
    session.onClosed(closed);
    store?.close();
    expect(closed).toHaveBeenCalledTimes(1);
    // the next open makes a new session instead of handing back the dead one
    const again = await openVaultSession({
      profile,
      keys: await keys(),
      fresh: false,
      fetch: net.fetch,
    });
    expect(again).not.toBe(session);
    again.close();
  });

  it("closing the session itself does not report a close", async () => {
    const net = fakeNetwork();
    const session = await openVaultSession({
      profile: profileOf(),
      keys: await keys(),
      fresh: true,
      fetch: net.fetch,
    });
    const closed = vi.fn();
    session.onClosed(closed);
    session.close();
    expect(closed).not.toHaveBeenCalled();
  });
});

describe("forgetVault", () => {
  it("closes the session and deletes this browser's vault", async () => {
    const net = fakeNetwork();
    const profile = profileOf();
    await openVaultSession({ profile, keys: await keys(), fresh: true, fetch: net.fetch });
    expect(await vaultExists(profile.id)).toBe(true);
    await forgetVault();
    expect(await vaultExists(profile.id)).toBe(false);
    // nothing left to read
    const store = await createEncryptedStore(profile.id);
    expect(await store.list("settings")).toEqual([]);
    store.close();
  });

  it("does nothing when the tab never showed a preview account", async () => {
    await expect(forgetVault()).resolves.toBeUndefined();
  });
});
