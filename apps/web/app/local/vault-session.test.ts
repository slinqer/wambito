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
    mode: "ok" as "ok" | "offline" | "unauthorized" | "session_changed",
    pushed: 0,
    /** The `keyV` of every pushed change, in order. */
    pushedKeyV: [] as number[],
    /** Records the pull hands out (e.g. one under a key version this browser never got). */
    records: [] as unknown[],
    live: [] as string[],
    fetch: (async (input: RequestInfo | URL, init?: RequestInit) => {
      const request =
        input instanceof Request ? input : new Request(new URL(String(input), "http://x"), init);
      const url = new URL(request.url);
      if (net.mode === "offline") throw new TypeError("offline");
      if (net.mode === "unauthorized") return json({ code: "unauthenticated" }, 401);
      if (net.mode === "session_changed" && url.pathname.startsWith("/api/v2/")) {
        return json({ code: "session_changed" }, 409);
      }
      if (url.pathname === "/api/v2/sync" && request.method === "GET") {
        return json({ records: net.records, next: null, latest: net.pushed + net.records.length });
      }
      if (url.pathname === "/api/v2/sync" && request.method === "POST") {
        const { changes } = (await request.json()) as { changes: { id: string; keyV: number }[] };
        net.pushedKeyV.push(...changes.map((c) => c.keyV));
        return json({ results: changes.map((c) => ({ id: c.id, version: ++net.pushed })) });
      }
      net.live.push(`${request.method} ${url.pathname}`);
      return new Response(null, { status: 204 });
    }) as typeof globalThis.fetch,
  };
  return net;
}

const keys = async () => ({
  keyring: {
    current: 1,
    byVersion: new Map([[1, await deriveRecordKeys(generateDataKey(), false)]]),
  },
});

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

describe("seeding", () => {
  it("does not seed when the first sync failed (a known browser offline)", async () => {
    const net = fakeNetwork();
    net.mode = "offline";
    const profile = profileOf();
    let store: EncryptedStore | undefined;
    const session = await openVaultSession({
      profile,
      keys: await keys(),
      fresh: false,
      fetch: net.fetch,
      openStore: async (userId) => {
        store = await createEncryptedStore(userId);
        return store;
      },
    });
    expect(await store?.list("settings")).toEqual([]);
    expect(await store?.list("category")).toEqual([]);
    session.close();
  });

  it("does not seed over changes a failed resync set aside", async () => {
    const net = fakeNetwork();
    net.mode = "offline";
    const profile = profileOf();
    const store = await createEncryptedStore(profile.id);
    await store.put("category", "01930000-0000-7000-8000-0000000000aa", {
      s: 1,
      name: "Mine",
      kind: "expense",
      icon: "x",
      color: "#fff",
      sortOrder: 0,
      archivedAt: null,
      systemKey: null,
    });
    await store.wipeRecords();
    const session = await openVaultSession({
      profile,
      keys: await keys(),
      fresh: false,
      fetch: net.fetch,
      openStore: async () => store,
    });
    expect(await store.list("settings")).toEqual([]);
    expect((await store.readOutbox(10)).map((e) => e.setAside !== undefined)).toEqual([true]);
    session.close();
  });
});

describe("another account signed in", () => {
  it("names the vault's account on every sync call", async () => {
    const net = fakeNetwork();
    const profile = profileOf();
    const seen: Array<string | null> = [];
    const fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(String(input), "http://x");
      if (url.pathname.startsWith("/api/v2/")) {
        seen.push(new Headers(init?.headers).get("x-wambito-user"));
      }
      return net.fetch(input, init);
    }) as typeof globalThis.fetch;
    const session = await openVaultSession({ profile, keys: await keys(), fresh: true, fetch });
    expect(seen.length).toBeGreaterThan(0);
    expect(seen.every((v) => v === profile.id)).toBe(true);
    session.close();
  });

  it("a 409 session_changed on opening fails it, even for a known browser", async () => {
    const net = fakeNetwork();
    net.mode = "session_changed";
    const failed = await openVaultSession({
      profile: profileOf(),
      keys: await keys(),
      fresh: false,
      fetch: net.fetch,
    }).catch((e) => e);
    expect(failed).toBeInstanceOf(VaultOpenError);
    expect(failed.code).toBe("session_changed");
  });

  it("a 409 session_changed later closes the session and tells onSessionChanged", async () => {
    const net = fakeNetwork();
    const onSessionChanged = vi.fn();
    let store: EncryptedStore | undefined;
    const session = await openVaultSession({
      profile: profileOf(),
      keys: await keys(),
      fresh: true,
      fetch: net.fetch,
      onSessionChanged,
      openStore: async (userId) => {
        store = await createEncryptedStore(userId);
        return store;
      },
    });
    const closed = vi.fn();
    session.onClosed(closed);
    net.mode = "session_changed";
    // A local write triggers the next sync.
    const [first] = (await store?.list("category")) ?? [];
    if (first) await store?.put("category", first.id, { ...first.body, name: "Edited" });
    await vi.waitFor(() => expect(onSessionChanged).toHaveBeenCalledTimes(1), { timeout: 3000 });
    expect(store?.isClosed()).toBe(true);
    expect(closed).not.toHaveBeenCalled();
    // the session is gone: the next open makes a new one
    net.mode = "ok";
    const again = await openVaultSession({
      profile: profileOf(),
      keys: await keys(),
      fresh: true,
      fetch: net.fetch,
    });
    expect(again).not.toBe(session);
    again.close();
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

describe("this browser removed from the account", () => {
  // No device wrap of this browser is left: `refreshKeys` (over `keys.ts`) says `device_removed`.
  const rotated = {
    id: "01930000-0000-7000-8000-0000000000ff",
    type: "category",
    version: 1,
    deleted: false,
    keyV: 2,
    encV: 1,
    body: "AAAA",
  };

  it("stops the sync, deletes the vault and calls onRemoved", async () => {
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
    const removed = vi.fn();
    const closed = vi.fn();
    session.onRemoved(removed);
    session.onClosed(closed);
    net.records = [rotated];
    const [first] = (await store?.list("category")) ?? [];
    if (first) await store?.put("category", first.id, { ...first.body, name: "Edited" });
    await vi.waitFor(() => expect(removed).toHaveBeenCalledTimes(1), { timeout: 3000 });
    expect(store?.isClosed()).toBe(true);
    expect(await vaultExists(profile.id)).toBe(false);
    expect(closed).not.toHaveBeenCalled();
    // the session is gone: the next open makes a new one
    net.records = [];
    const again = await openVaultSession({
      profile,
      keys: await keys(),
      fresh: true,
      fetch: net.fetch,
    });
    expect(again).not.toBe(session);
    again.close();
  });

  it("fails the opening with device_removed and deletes the vault", async () => {
    const net = fakeNetwork();
    net.records = [rotated];
    const profile = profileOf();
    const failed = await openVaultSession({
      profile,
      keys: await keys(),
      fresh: false,
      fetch: net.fetch,
    }).catch((e) => e);
    expect(failed).toBeInstanceOf(VaultOpenError);
    expect(failed.code).toBe("device_removed");
    expect(await vaultExists(profile.id)).toBe(false);
  });
});

describe("reloadKeys", () => {
  it("gives the running sync the keyring the vault now holds (a rotation), then syncs", async () => {
    const net = fakeNetwork();
    const profile = profileOf();
    let store: EncryptedStore | undefined;
    const first = await keys();
    const session = await openVaultSession({
      profile,
      keys: first,
      fresh: true,
      fetch: net.fetch,
      openStore: async (userId) => {
        store = await createEncryptedStore(userId);
        return store;
      },
    });
    // a rotation committed in this browser: version 2's keys are in the vault, and current
    const v1 = first.keyring.byVersion.get(1) as Awaited<ReturnType<typeof deriveRecordKeys>>;
    const v2 = await deriveRecordKeys(generateDataKey(), false);
    await store?.putKey("record:1", v1.record);
    await store?.putKey("dedupe:1", v1.dedupe);
    await store?.putKey("record:2", v2.record);
    await store?.putKey("dedupe:2", v2.dedupe);
    await store?.setMeta("keyV", 2);
    const pulls = net.pushed;

    await session.reloadKeys();
    const [category] = (await store?.list("category")) ?? [];
    if (!category) throw new Error("no seeded category");
    await store?.put("category", category.id, { ...category.body, name: "Edited" });
    await vi.waitFor(() => expect(net.pushedKeyV.slice(pulls)).toContain(2), { timeout: 4000 });
    const after = net.pushedKeyV.slice(net.pushedKeyV.indexOf(2));
    expect(after.every((v) => v === 2)).toBe(true);
    session.close();
  });
});
