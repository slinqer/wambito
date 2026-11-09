import { describe, expect, it } from "vitest";
import { createApiClient } from "../api/client.ts";
import { createLocalBackend, DEMO_UNAVAILABLE } from "./backend.ts";
import { uuidv5 } from "./ids.ts";
import { createMemoryStore } from "./memory-store.ts";

const V7 = /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const NOW = new Date("2026-10-21T18:00:00Z");

function setup(options: { unavailable?: typeof DEMO_UNAVAILABLE } = {}) {
  const store = createMemoryStore();
  const backend = createLocalBackend({ store, now: () => new Date(NOW), ...options });
  const api = createApiClient({ fetch: backend.fetch, baseUrl: "http://local.test/api" });
  return { store, api };
}

async function onboard(api: ReturnType<typeof setup>["api"]) {
  await api.PATCH("/v1/me", {
    body: { currency: "COP", locale: "es", timezone: "America/Bogota", onboardingCompleted: true },
  });
  const { data: food } = await api.POST("/v1/categories", {
    body: { name: "Food", kind: "expense", icon: "fork", color: "#f90" },
  });
  return { food: food?.id as string };
}

describe("createLocalBackend over the memory store", () => {
  it("starts as a fresh account and keeps its settings as a record", async () => {
    const { api, store } = setup();
    expect((await api.GET("/v1/me")).data).toMatchObject({ onboardingCompletedAt: null });
    await onboard(api);
    const [settings] = await store.list("settings");
    expect(settings?.id).toMatch(V7);
    expect(settings?.body).toMatchObject({ currency: "COP", timezone: "America/Bogota" });
    expect((await api.GET("/v1/me")).data).toMatchObject({ currency: "COP", locale: "es" });
  });

  it("makes records with lower-case UUID v7 ids, written through the store", async () => {
    const { api, store } = setup();
    const { food } = await onboard(api);
    expect(food).toMatch(V7);
    const created = await api.POST("/v1/transactions", {
      body: { name: "Lunch", amount: -18_000_00, categoryId: food, date: "2026-10-21" },
    });
    const id = created.data?.id as string;
    expect(id).toMatch(V7);
    expect(id > food).toBe(true);
    const stored = await store.get("transaction", id);
    expect(stored?.body).toMatchObject({ s: 1, name: "Lunch", currency: "COP", source: "app" });
  });

  it("deletes to a tombstone and restores", async () => {
    const { api, store } = setup();
    const { food } = await onboard(api);
    const id = (
      await api.POST("/v1/transactions", {
        body: { name: "Lunch", amount: -1_000_00, categoryId: food, date: "2026-10-21" },
      })
    ).data?.id as string;
    await api.DELETE("/v1/transactions/{id}", { params: { path: { id } } });
    expect(await store.get("transaction", id)).toBeUndefined();
    expect((await store.get("transaction", id, { includeDeleted: true }))?.deleted).toBe(true);
    await api.POST("/v1/transactions/{id}/restore", { params: { path: { id } } });
    expect((await store.get("transaction", id))?.deleted).toBe(false);
  });

  it("names a recurrence's occurrences by UUID v5 of the rule, the month and the revision", async () => {
    const { api, store } = setup();
    const { food } = await onboard(api);
    const rule = (
      await api.POST("/v1/recurrences", {
        body: {
          name: "Rent",
          amount: -500_000_00,
          categoryId: food,
          frequency: "monthly",
          dayOfMonth: 5,
          startDate: "2026-09-05",
        },
      })
    ).data;
    const { data } = await api.GET("/v1/transactions", { params: { query: { month: "2026-10" } } });
    const occurrence = data?.items.find((t) => t.recurrenceId === rule?.id);
    expect(occurrence?.status).toBe("pending");
    expect(occurrence?.id).toBe(await uuidv5(rule?.id as string, "2026-10:0"));
    expect((await store.get("transaction", occurrence?.id as string))?.body).toMatchObject({
      occurrenceMonth: "2026-10",
      source: "recurrence",
    });
    // Reading again makes no second one.
    const again = await api.GET("/v1/transactions", { params: { query: { month: "2026-10" } } });
    expect(again.data?.items.filter((t) => t.recurrenceId === rule?.id).length).toBe(1);
  });

  async function ruleWithOctober() {
    const ctx = setup();
    const { food } = await onboard(ctx.api);
    const rule = (
      await ctx.api.POST("/v1/recurrences", {
        body: {
          name: "Rent",
          amount: -500_000_00,
          categoryId: food,
          frequency: "monthly",
          dayOfMonth: 5,
          startDate: "2026-09-05",
        },
      })
    ).data;
    const ruleId = rule?.id as string;
    const month = async (m: string) =>
      (
        (await ctx.api.GET("/v1/transactions", { params: { query: { month: m } } })).data?.items ??
        []
      ).filter((t) => t.recurrenceId === ruleId);
    return { ...ctx, food, ruleId, month };
  }

  it("bumps the rule's rev on an edit: the pending occurrences are tombstoned and come back under new ids", async () => {
    const { api, store, ruleId, month } = await ruleWithOctober();
    const [before] = await month("2026-10");
    expect((await store.get("recurrence", ruleId))?.body.rev).toBe(0);
    await api.PATCH("/v1/recurrences/{id}", {
      params: { path: { id: ruleId } },
      body: { amount: -600_000_00 },
    });
    expect((await store.get("recurrence", ruleId))?.body.rev).toBe(1);
    expect(
      (await store.get("transaction", before?.id as string, { includeDeleted: true }))?.deleted,
    ).toBe(true);
    const after = await month("2026-10");
    expect(after.length).toBe(1);
    expect(after[0]?.id).toBe(await uuidv5(ruleId, "2026-10:1"));
    expect(after[0]?.amount).toBe(-600_000_00);
  });

  it("keeps a deleted occurrence deleted across an edit", async () => {
    const { api, ruleId, month } = await ruleWithOctober();
    const [occ] = await month("2026-10");
    await api.DELETE("/v1/transactions/{id}", { params: { path: { id: occ?.id as string } } });
    expect(await month("2026-10")).toEqual([]);
    await api.PATCH("/v1/recurrences/{id}", {
      params: { path: { id: ruleId } },
      body: { amount: -600_000_00 },
    });
    expect(await month("2026-10")).toEqual([]);
  });

  it("keeps a paid occurrence and makes no second one after an edit", async () => {
    const { api, ruleId, month } = await ruleWithOctober();
    const [occ] = await month("2026-10");
    await api.PATCH("/v1/transactions/{id}", {
      params: { path: { id: occ?.id as string } },
      body: { status: "paid" },
    });
    await api.PATCH("/v1/recurrences/{id}", {
      params: { path: { id: ruleId } },
      body: { amount: -600_000_00 },
    });
    const rows = await month("2026-10");
    expect(rows.map((t) => t.id)).toEqual([occ?.id]);
  });

  it("stamps updatedAt on create and on PATCH", async () => {
    const { api, store, food } = await ruleWithOctober();
    const id = (
      await api.POST("/v1/transactions", {
        body: { name: "Lunch", amount: -1_000_00, categoryId: food, date: "2026-10-21" },
      })
    ).data?.id as string;
    expect((await store.get("transaction", id))?.body.updatedAt).toBe(NOW.toISOString());
    const patched = await api.PATCH("/v1/transactions/{id}", {
      params: { path: { id } },
      body: { name: "Dinner" },
    });
    expect(patched.data?.updatedAt).toBe(NOW.toISOString());
  });

  it("leaves the store untouched when a request is refused", async () => {
    const { api, store } = setup();
    const { food } = await onboard(api);
    const before = await store.list("transaction", { includeDeleted: true });
    await expect(
      api.POST("/v1/transactions", {
        body: {
          name: "Bad",
          amount: -1_00,
          categoryId: "01930000-0000-7000-8000-0000000000ff",
          date: "2026-10-21",
        },
      }),
    ).rejects.toMatchObject({ status: 422 });
    expect(await store.list("transaction", { includeDeleted: true })).toEqual(before);
    expect(food).toBeTruthy();
  });

  it("notifies the store's subscribers after a write, not after a read", async () => {
    const { api, store } = setup();
    let calls = 0;
    store.subscribe(() => calls++);
    await api.GET("/v1/categories");
    expect(calls).toBe(0);
    await onboard(api);
    expect(calls).toBeGreaterThan(0);
  });

  it("answers 403 demo_unavailable only for the routes it is told to", async () => {
    const open = setup();
    await expect(open.api.GET("/v1/me/export" as never)).rejects.not.toMatchObject({ status: 403 });
    const closed = setup({ unavailable: DEMO_UNAVAILABLE });
    await expect(closed.api.GET("/v1/me/export" as never)).rejects.toMatchObject({
      status: 403,
      code: "demo_unavailable",
    });
    await expect(closed.api.DELETE("/v1/me")).rejects.toMatchObject({ status: 403 });
    expect((await closed.api.GET("/v1/me")).data).toBeTruthy();
  });
});

describe("POST /v1/transactions/review", () => {
  async function toReview(
    store: ReturnType<typeof setup>["store"],
    api: ReturnType<typeof setup>["api"],
    food: string,
    name: string,
  ) {
    const id = (
      await api.POST("/v1/transactions", {
        body: { name, amount: -5_000_00, categoryId: food, date: "2026-10-21" },
      })
    ).data?.id as string;
    const found = await store.get("transaction", id);
    if (!found) throw new Error("not saved");
    await store.transaction((s) => s.put("transaction", id, { ...found.body, needsReview: true }));
    return id;
  }

  it("confirms every id at once and answers them in request order", async () => {
    const { api, store } = setup();
    const { food } = await onboard(api);
    const a = await toReview(store, api, food, "A");
    const b = await toReview(store, api, food, "B");
    const res = await api.POST("/v1/transactions/review", { body: { ids: [b, a, b] } });
    expect(res.response.status).toBe(200);
    expect(res.data?.items.map((t) => [t.id, t.needsReview])).toEqual([
      [b, false],
      [a, false],
      [b, false],
    ]);
    expect((await store.get("transaction", a))?.body.needsReview).toBe(false);
  });

  it("is all or nothing: an unknown or deleted id is 404 and nothing changes", async () => {
    const { api, store } = setup();
    const { food } = await onboard(api);
    const a = await toReview(store, api, food, "A");
    const gone = await toReview(store, api, food, "Gone");
    await api.DELETE("/v1/transactions/{id}", { params: { path: { id: gone } } });
    for (const other of [gone, "0193a000-0000-7000-8000-0000000000ff"]) {
      const err = await api
        .POST("/v1/transactions/review", { body: { ids: [a, other] } })
        .catch((e) => e);
      expect(err).toMatchObject({ status: 404, code: "not_found" });
    }
    expect((await store.get("transaction", a))?.body.needsReview).toBe(true);
  });

  it("validates like the API (1 to 50 uuids)", async () => {
    const { api } = setup();
    await onboard(api);
    const err = await api.POST("/v1/transactions/review", { body: { ids: [] } }).catch((e) => e);
    expect(err).toMatchObject({ status: 422 });
  });
});
