import "fake-indexeddb/auto";
import { createLocalBackend, IDEMPOTENCY_NAMESPACE, uuidv5 } from "@wambito/vault";
import { describe, expect, it } from "vitest";
import { createApiClient } from "../api/client.ts";
import { createEncryptedStore } from "./encrypted-store.ts";

// The local backend over the real IndexedDB store: one IndexedDB transaction per request, which
// commits by itself as soon as a request waits on anything but IndexedDB (fake-indexeddb, like
// Firefox, enforces it). Computing an occurrence's id must not leave the transaction.

const NOW = new Date("2026-10-21T18:00:00Z");
let counter = 0;

async function setup(options: { idsFromIdempotencyKey?: { userId: string } } = {}) {
  const store = await createEncryptedStore(`backend-idb-${++counter}`);
  const backend = createLocalBackend({ store, now: () => new Date(NOW), ...options });
  const api = createApiClient({ fetch: backend.fetch, baseUrl: "http://local.test/api" });
  await api.PATCH("/v1/me", {
    body: { currency: "COP", locale: "es", timezone: "America/Bogota", onboardingCompleted: true },
  });
  const { data: food } = await api.POST("/v1/categories", {
    body: { name: "Food", kind: "expense", icon: "fork", color: "#f90" },
  });
  return { store, backend, api, food: food?.id as string };
}

async function withRule() {
  const ctx = await setup();
  const rule = await ctx.api.POST("/v1/recurrences", {
    body: {
      name: "Rent",
      amount: -500_000_00,
      categoryId: ctx.food,
      frequency: "monthly",
      dayOfMonth: 5,
      startDate: "2026-09-05",
    },
  });
  expect(rule.error).toBeUndefined();
  return { ...ctx, ruleId: rule.data?.id as string };
}

describe("createLocalBackend over the IndexedDB store", () => {
  it("answers a month's summary that materializes a recurrence's occurrence", async () => {
    const { api, store, ruleId } = await withRule();
    const summary = await api.GET("/v1/summary", { params: { query: { month: "2026-11" } } });
    expect(summary.error).toBeUndefined();
    expect(summary.response.status).toBe(200);
    const id = await uuidv5(ruleId, "2026-11:0");
    expect((await store.get("transaction", id))?.body).toMatchObject({
      recurrenceId: ruleId,
      occurrenceMonth: "2026-11",
      status: "pending",
    });
    store.close();
  });

  it("moves the occurrences to new ids when a rule is edited", async () => {
    const { api, store, ruleId } = await withRule();
    await api.GET("/v1/transactions", { params: { query: { month: "2026-10" } } });
    const edited = await api.PATCH("/v1/recurrences/{id}", {
      params: { path: { id: ruleId } },
      body: { amount: -600_000_00 },
    });
    expect(edited.error).toBeUndefined();
    const { data } = await api.GET("/v1/transactions", { params: { query: { month: "2026-10" } } });
    const occurrences = (data?.items ?? []).filter((t) => t.recurrenceId === ruleId);
    expect(occurrences.map((t) => t.id)).toEqual([await uuidv5(ruleId, "2026-10:1")]);
    store.close();
  });

  it("derives a batch's ids from its Idempotency-Key inside the transaction", async () => {
    const userId = "01930000-0000-7000-8000-0000000000aa";
    const { backend, store, food } = await setup({ idsFromIdempotencyKey: { userId } });
    const response = await backend.fetch("http://local.test/api/v1/transactions/batch", {
      method: "POST",
      headers: { "content-type": "application/json", "idempotency-key": "k-1" },
      body: JSON.stringify({
        items: [
          { name: "Lunch", amount: -18_000_00, categoryId: food, date: "2026-10-21" },
          { name: "Bus", amount: -3_000_00, categoryId: food, date: "2026-10-21" },
        ],
      }),
    });
    expect(response.status).toBe(201);
    const id = await uuidv5(IDEMPOTENCY_NAMESPACE, `${userId}/k-1/1`);
    expect((await store.get("transaction", id))?.body.name).toBe("Bus");
    store.close();
  });
});
