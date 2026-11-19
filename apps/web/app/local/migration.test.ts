import "fake-indexeddb/auto";
import { deriveRecordKeys, generateDataKey } from "@wambito/crypto";
import type { MigrationSource } from "@wambito/vault";
import { describe, expect, it, vi } from "vitest";
import { createEncryptedStore } from "./encrypted-store.ts";
import type { LocalKeys } from "./keys.ts";
import { liveMigrationDeps } from "./migration.ts";

// The flow never opens the vault session (its first open seeds categories) before done.
vi.mock("./vault-session.ts", () => ({
  openVaultSession: vi.fn(() => {
    throw new Error("the migration must not open the vault session");
  }),
}));

let counter = 0;
const userOf = () => `migration_user_${++counter}`;

const AT = "2026-10-03T09:30:00.000Z";
const FOOD = "01930000-0000-7000-8000-0000000000c1";
const RULE = "01930000-0000-7000-8000-0000000000f1";

const tx = (
  id: string,
  extra: Partial<MigrationSource["transactions"][number]> = {},
): MigrationSource["transactions"][number] => ({
  id,
  categoryId: FOOD,
  name: "Bakery",
  amount: -1250,
  currency: "EUR",
  date: "2026-10-03",
  status: "paid",
  note: null,
  recurrenceId: null,
  occurrenceMonth: null,
  source: "web",
  needsReview: false,
  captureSource: null,
  capturedAt: null,
  captureMerchantKey: null,
  deletedAt: null,
  createdAt: AT,
  updatedAt: AT,
  ...extra,
});

/** An invented plain account: a category, a monthly rule, a live and a deleted row. */
const SOURCE: MigrationSource = {
  profile: {
    timezone: "Europe/Madrid",
    locale: "es",
    onboardingCompletedAt: AT,
    currency: "EUR",
  },
  categories: [
    {
      id: FOOD,
      name: "Comida",
      kind: "expense",
      icon: "🍞",
      color: "#f0a000",
      sortOrder: 0,
      archivedAt: null,
      systemKey: null,
      createdAt: AT,
    },
  ],
  budgets: [],
  recurrences: [
    {
      id: RULE,
      categoryId: FOOD,
      name: "Cesta",
      amount: -4000,
      frequency: "monthly",
      dayOfMonth: 5,
      monthOfYear: null,
      startDate: "2026-08-05",
      endDate: null,
      createdAt: AT,
    },
  ],
  transactions: [
    tx("01930000-0000-7000-8000-0000000000d1"),
    tx("01930000-0000-7000-8000-0000000000d2", { deletedAt: AT }),
  ],
  merchants: [],
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

/** The API's `/v2/migration/*` and `/v2/sync`, in memory. */
function fakeApi() {
  const net = {
    /** The pushed changes, by id. */
    records: new Map<string, { type: string; deleted: boolean; body: string | null }>(),
    calls: [] as string[],
    users: [] as (string | null)[],
    refusePush: null as string | null,
    finishAnswer: null as { status: number; code: string } | null,
    offline: false,
    fetch: (async (input: RequestInfo | URL, init?: RequestInit) => {
      const request =
        input instanceof Request ? input : new Request(new URL(String(input), "http://x"), init);
      const url = new URL(request.url);
      if (net.offline) throw new TypeError("offline");
      net.calls.push(`${request.method} ${url.pathname}`);
      net.users.push(request.headers.get("x-wambito-user"));
      if (url.pathname === "/api/v2/migration/start") return json({});
      if (url.pathname === "/api/v2/migration/source") return json(SOURCE);
      if (url.pathname === "/api/v2/migration/cancel") {
        net.records.clear();
        return new Response(null, { status: 204 });
      }
      if (url.pathname === "/api/v2/migration/finish") {
        if (net.finishAnswer) return json({ code: net.finishAnswer.code }, net.finishAnswer.status);
        return json({ id: "u" });
      }
      if (url.pathname === "/api/v2/sync" && request.method === "GET") {
        return json({ records: [], next: null, latest: net.records.size });
      }
      if (url.pathname === "/api/v2/sync" && request.method === "POST") {
        if (net.refusePush) return json({ code: net.refusePush }, 409);
        const { changes } = (await request.json()) as {
          changes: { id: string; type: string; deleted: boolean; body: string | null }[];
        };
        for (const c of changes) {
          net.records.set(c.id, { type: c.type, deleted: c.deleted, body: c.body });
        }
        return json({ results: changes.map((c, i) => ({ id: c.id, version: i + 1 })) });
      }
      return json({ code: "not_found" }, 404);
    }) as typeof globalThis.fetch,
  };
  return net;
}

const keysOf = async (): Promise<LocalKeys> => ({
  keyring: {
    current: 1,
    byVersion: new Map([[1, await deriveRecordKeys(generateDataKey(), false)]]),
  },
});

function depsFor(userId: string, net: ReturnType<typeof fakeApi>) {
  return liveMigrationDeps({
    userId,
    migration: "available",
    fetch: net.fetch,
    reload: vi.fn(),
    refreshKeys: async () => (await keysOf()).keyring,
  });
}

describe("live migration deps", () => {
  it("writes the source into the vault as it is, and pushes every record with the same id", async () => {
    const userId = userOf();
    const net = fakeApi();
    const deps = depsFor(userId, net);
    await deps.start();
    const records = await deps.source();
    await deps.write(records);

    const store = await createEncryptedStore(userId);
    try {
      // Only the source's records: no starter categories, no recurring payment made.
      expect((await store.list("category")).map((c) => c.id)).toEqual([FOOD]);
      expect((await store.list("transaction")).map((t) => t.id)).toEqual([
        "01930000-0000-7000-8000-0000000000d1",
      ]);
      const deleted = await store.getRaw("transaction", "01930000-0000-7000-8000-0000000000d2");
      expect(deleted).toMatchObject({ deleted: true, body: { name: "Bakery" } });

      const progress: number[] = [];
      await deps.sync(await keysOf(), (done) => progress.push(done));
      expect(await store.readOutbox(1)).toEqual([]);
      expect(progress.at(-1)).toBe(records.length);
      expect([...net.records.keys()].sort()).toEqual(records.map((r) => r.id).sort());
      // The deleted row is a tombstone that keeps its (sealed) body.
      expect(net.records.get("01930000-0000-7000-8000-0000000000d2")).toMatchObject({
        deleted: true,
        body: expect.any(String),
      });
      // Every /v2 call names the vault's account.
      expect(new Set(net.users)).toEqual(new Set([userId]));
    } finally {
      store.close();
      deps.close();
    }
  });

  it("keeps the resume step and the key's confirmation in the vault's meta; resetAll keeps them", async () => {
    const userId = userOf();
    const net = fakeApi();
    const deps = depsFor(userId, net);
    expect(await deps.resume()).toEqual({ step: null, keySavedAt: null });
    await deps.remember("copying", "2026-11-19T10:00:00.000Z");
    await deps.write(await deps.source());
    await deps.resetAll();
    expect(await deps.resume()).toEqual({
      step: "copying",
      keySavedAt: "2026-11-19T10:00:00.000Z",
    });
    const store = await createEncryptedStore(userId);
    try {
      expect(await store.list("category")).toEqual([]);
      expect(await store.readOutbox(1)).toEqual([]);
    } finally {
      store.close();
    }
    await deps.remember(null);
    expect((await deps.resume()).step).toBeNull();
    deps.close();
  });

  it("a push refused with migration_in_progress is taken_over's code, never a loop", async () => {
    const userId = userOf();
    const net = fakeApi();
    const deps = depsFor(userId, net);
    await deps.write(await deps.source());
    net.refusePush = "migration_in_progress";
    await expect(deps.sync(await keysOf(), () => {})).rejects.toMatchObject({
      code: "migration_in_progress",
    });
    deps.close();
  });

  it("maps the API's answers to the flow's codes", async () => {
    const userId = userOf();
    const net = fakeApi();
    const deps = depsFor(userId, net);
    net.finishAnswer = { status: 409, code: "count_mismatch" };
    await expect(
      deps.finish({
        transaction: 0,
        deletedTransaction: 0,
        category: 0,
        budget: 0,
        recurrence: 0,
        merchant: 0,
      }),
    ).rejects.toMatchObject({ code: "count_mismatch" });
    net.finishAnswer = { status: 500, code: "internal_error" };
    await expect(
      deps.finish({
        transaction: 0,
        deletedTransaction: 0,
        category: 0,
        budget: 0,
        recurrence: 0,
        merchant: 0,
      }),
    ).rejects.toMatchObject({ code: "server" });
    net.offline = true;
    await expect(deps.source()).rejects.toMatchObject({ code: "offline" });
    deps.close();
  });

  it("a cancel of a move that is not running any more is no error", async () => {
    const userId = userOf();
    const net = fakeApi();
    const deps = liveMigrationDeps({
      userId,
      migration: "in_progress",
      fetch: (async (input: RequestInfo | URL, init?: RequestInit) => {
        const url = new URL(String(input instanceof Request ? input.url : input), "http://x");
        if (url.pathname === "/api/v2/migration/cancel")
          return json({ code: "not_migrating" }, 409);
        return net.fetch(input, init);
      }) as typeof globalThis.fetch,
      reload: vi.fn(),
    });
    await expect(deps.cancel()).resolves.toBeUndefined();
    deps.close();
  });
});
