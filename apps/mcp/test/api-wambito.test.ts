import { ToolError } from "@wambito/ai-assistant-tools";
import { afterAll, beforeAll, expect, test } from "vitest";
import { createTestApp, type TestApp } from "../../api/test/harness.ts";
import { apiWambito } from "../src/api-wambito.ts";

// The real API (and a real database), reached in-process with an assistant's real access token.
let t: TestApp;
let wambito: ReturnType<typeof apiWambito>;
let categoryId: string;
beforeAll(async () => {
  t = await createTestApp();
  const { headers } = await t.signIn("mcp@wambito.test");
  const res = await t.request("POST", "/v1/categories", {
    headers,
    body: { name: "Comida", kind: "expense", icon: "food", color: "orange" },
  });
  categoryId = ((await res.json()) as { id: string }).id;
  const { accessToken } = await t.authorize("mcp@wambito.test", { headers });
  const fetchApi = (async (input: string | URL | Request, init?: RequestInit) =>
    t.app.request(input instanceof Request ? input : String(input), init)) as typeof fetch;
  wambito = apiWambito(t.config.API_URL, accessToken, fetchApi);
});
afterAll(() => t?.stop());

const item = { name: "Almuerzo", amount: -1800000, date: "2026-10-30" };

test("the profile and categories come from the API", async () => {
  expect(await wambito.profile()).toMatchObject({
    locale: expect.any(String),
    currency: expect.any(String),
  });
  expect((await wambito.listCategories()).map((c) => c.name)).toEqual(["Comida"]);
});

test("add, list, delete and restore round-trip, saved as mcp", async () => {
  const saved = await wambito.addTransactions(
    [{ ...item, categoryId, status: "paid", source: "mcp" }],
    "key-1",
  );
  expect(saved.replayed).toBe(false);
  expect(saved.items[0]).toMatchObject({ name: "Almuerzo", source: "mcp" });
  const id = saved.items[0]?.id ?? "";
  expect(
    (await wambito.listTransactions({ q: ["almu"], limit: 10 })).items.map((i) => i.id),
  ).toEqual([id]);
  await wambito.deleteTransactions([id]);
  expect((await wambito.listTransactions({ month: "2026-10", limit: 10 })).items).toEqual([]);
  await wambito.restoreTransaction(id);
  expect((await wambito.listTransactions({ month: "2026-10", limit: 10 })).items).toHaveLength(1);
});

test("the same batch with the same key is a replay and saves nothing", async () => {
  const batch = [
    { ...item, name: "Taxi", categoryId, status: "paid" as const, source: "mcp" as const },
  ];
  await wambito.addTransactions(batch, "key-2");
  const again = await wambito.addTransactions(batch, "key-2");
  expect(again.replayed).toBe(true);
  expect((await wambito.listTransactions({ q: ["taxi"], limit: 10 })).items).toHaveLength(1);
});

test("an API problem becomes a ToolError with its code", async () => {
  const error = await wambito
    .updateTransaction("00000000-0000-4000-8000-000000000000", { name: "x" })
    .catch((e: unknown) => e);
  expect(error).toBeInstanceOf(ToolError);
  expect((error as ToolError).code).toBe("not_found");
});

test("list_transactions sends repeated words and categories, kind, match and totals", async () => {
  const urls: URL[] = [];
  const spy = (async (input: string | URL | Request, init?: RequestInit) => {
    const request = input instanceof Request ? input : new Request(String(input), init);
    urls.push(new URL(request.url));
    return Response.json({
      items: [],
      nextCursor: null,
      totals: { count: 0, expense: 0, income: 0 },
    });
  }) as typeof fetch;
  const probe = apiWambito("http://api.test", "token", spy);
  const other = "00000000-0000-4000-8000-000000000002";
  const result = await probe.listTransactions({
    from: "2026-01-01",
    to: "2026-02-01",
    categoryIds: [categoryId, other],
    kind: "expense",
    match: "any",
    status: "paid",
    needsReview: true,
    q: ["almuerzo", "corrientazo"],
    limit: 25,
    totals: true,
  });
  expect(result.totals).toEqual({ count: 0, expense: 0, income: 0 });
  const params = urls[0]?.searchParams;
  expect(params?.getAll("q")).toEqual(["almuerzo", "corrientazo"]);
  expect(params?.getAll("category")).toEqual([categoryId, other]);
  expect(params?.has("categoryId")).toBe(false);
  expect(Object.fromEntries(params ?? [])).toMatchObject({
    from: "2026-01-01",
    to: "2026-02-01",
    kind: "expense",
    match: "any",
    status: "paid",
    needsReview: "true",
    totals: "true",
    limit: "25",
  });
});

test("the category filter reaches the API and finds the movement", async () => {
  const items = await wambito.listTransactions({ categoryIds: [categoryId], limit: 10 });
  expect(items.items.length).toBeGreaterThan(0);
  const none = await wambito.listTransactions({
    categoryIds: ["00000000-0000-4000-8000-000000000009"],
    limit: 10,
  });
  expect(none.items).toEqual([]);
});
