import { addMonths, type MonthSummary, monthOf, type TransactionDto, todayIn } from "@wambito/core";
import { describe, expect, it } from "vitest";
import { type ApiClient, createApiClient } from "../api/client.ts";
import type { ApiProblem } from "../api/errors.ts";
import type { Locale } from "../i18n/format.ts";
import { createDemoBackend } from "./demo-backend.ts";
import { DEMO_SEED } from "./demo-data.ts";

/** Mid-afternoon in Bogotá and Lisbon on 21 October 2026. */
const OCT_21 = new Date("2026-10-21T18:00:00Z");

const clock = (at: Date) => () => new Date(at);

function demo(locale: Locale = "es", at: Date = OCT_21) {
  const backend = createDemoBackend(DEMO_SEED[locale], clock(at));
  const api = createApiClient({
    fetch: backend.fetch,
    baseUrl: "http://demo.test/api",
    onUnauthorized: () => {
      throw new Error("the demo is always signed in");
    },
  });
  return { backend, api };
}

async function summary(api: ApiClient, month?: string): Promise<MonthSummary> {
  const { data } = await api.GET("/v1/summary", { params: { query: month ? { month } : {} } });
  return data as MonthSummary;
}

async function list(api: ApiClient, month: string): Promise<TransactionDto[]> {
  const { data } = await api.GET("/v1/transactions", { params: { query: { month, limit: 200 } } });
  return data?.items ?? [];
}

async function firstExpenseCategory(api: ApiClient): Promise<string> {
  const { data } = await api.GET("/v1/categories");
  const category = data?.find((c) => c.kind === "expense");
  if (!category) throw new Error("the seed has expense categories");
  return category.id;
}

/** Everything the screens read, for comparing two backends. */
async function snapshot(api: ApiClient, current: string) {
  const months = [addMonths(current, -2), addMonths(current, -1), current, addMonths(current, 1)];
  const perMonth = [];
  for (const month of months) {
    perMonth.push({ summary: await summary(api, month), items: await list(api, month) });
  }
  return {
    me: (await api.GET("/v1/me")).data,
    categories: (
      await api.GET("/v1/categories", { params: { query: { includeArchived: "true" } } })
    ).data,
    recurrences: (await api.GET("/v1/recurrences")).data,
    months: perMonth,
    trend: (
      await api.GET("/v1/reports/trend", {
        params: { query: { from: addMonths(current, -5), to: current } },
      })
    ).data,
    living: (await api.GET("/v1/reports/cost-of-living", { params: { query: { months: 2 } } }))
      .data,
    suggestions: (await api.GET("/v1/transactions/suggestions", { params: { query: { q: "" } } }))
      .data,
  };
}

describe("the demo's invented user", () => {
  it("is Valentina in pesos and Bogotá in Spanish, in euros and Lisbon in English", async () => {
    const es = (await demo("es").api.GET("/v1/me")).data;
    expect(es).toMatchObject({
      email: "valentina@demo.wambito.test",
      locale: "es",
      timezone: "America/Bogota",
      currency: "COP",
    });
    expect(es?.onboardingCompletedAt).not.toBeNull();
    const en = (await demo("en").api.GET("/v1/me")).data;
    expect(en).toMatchObject({
      email: "valentina@demo.wambito.test",
      locale: "en",
      timezone: "Europe/Lisbon",
      currency: "EUR",
    });
    expect(DEMO_SEED.es.profile.name).toBe("Valentina (demo)");
  });

  it("speaks Italian and Portuguese, in euros, in their own cities", async () => {
    const { api: it } = demo("it");
    const { api: pt } = demo("pt");
    expect((await it.GET("/v1/me")).data).toMatchObject({
      locale: "it",
      timezone: "Europe/Rome",
      currency: "EUR",
    });
    expect((await pt.GET("/v1/me")).data).toMatchObject({
      locale: "pt",
      timezone: "Europe/Lisbon",
      currency: "EUR",
    });
    const names = async (api: typeof it) =>
      new Set(((await list(api, "2026-10")) ?? []).map((t) => t.name));
    expect(await names(it)).toContain("Caffè e cornetto");
    expect(await names(pt)).toContain("Café e pastel de nata");
    // Not the Spanish seed: no pesos, no Colombian purchases.
    expect(await names(it)).not.toContain("Tinto y pandebono");
    expect(await names(pt)).not.toContain("Tinto y pandebono");
  });

  it("has 8 spending categories and a salary, with budgets, and rent, Spotify and salary recurring", async () => {
    const names = {
      es: ["Arriendo", "Spotify", "Salario"],
      en: ["Rent", "Spotify", "Salary"],
      it: ["Affitto", "Spotify", "Stipendio"],
      pt: ["Renda", "Spotify", "Salário"],
    } as const;
    for (const locale of ["es", "en", "it", "pt"] as const) {
      const { api } = demo(locale);
      const categories = (await api.GET("/v1/categories")).data ?? [];
      expect(categories.filter((c) => c.kind === "expense")).toHaveLength(8);
      expect(categories.filter((c) => c.kind === "income")).toHaveLength(1);
      expect(categories.filter((c) => c.currentBudget !== null).length).toBeGreaterThan(0);
      const recurrences = (await api.GET("/v1/recurrences")).data ?? [];
      expect(recurrences.map((r) => r.name)).toEqual(names[locale]);
    }
  });

  it("spends on a Colombian scale in Spanish: rent around 1.800.000, a coffee around 8.000", async () => {
    const { api } = demo("es");
    const items = await list(api, "2026-10");
    const rent = items.find((t) => t.name === "Arriendo");
    expect(rent?.amount).toBe(-1_800_000_00);
    const coffees = items.filter((t) => t.amount > -20_000_00 && t.amount <= -5_000_00);
    expect(coffees.length).toBeGreaterThan(3);
    expect(items.every((t) => t.currency === "COP")).toBe(true);
  });

  it("has the last 3 months of transactions, and none after today", async () => {
    const { api } = demo();
    for (const month of ["2026-08", "2026-09", "2026-10"]) {
      expect((await list(api, month)).length).toBeGreaterThan(10);
    }
    expect(await list(api, "2026-07")).toEqual([]);
    const paid = (await list(api, "2026-10")).filter((t) => t.status === "paid");
    expect(paid.every((t) => t.date <= "2026-10-21")).toBe(true);
  });
});

describe("GET /api/v1/summary", () => {
  it("has a category over its budget and one near it this month, whatever the day", async () => {
    for (const locale of ["es", "en", "it", "pt"] as const) {
      for (const at of ["2026-10-01T15:00:00Z", OCT_21.toISOString(), "2026-12-31T15:00:00Z"]) {
        const { api } = demo(locale, new Date(at));
        const s = await summary(api);
        expect(s.month).toBe(monthOf(todayIn(DEMO_SEED[locale].profile.timezone, new Date(at))));
        expect(s.categories.filter((c) => c.state === "over").length).toBeGreaterThanOrEqual(1);
        expect(s.categories.filter((c) => c.state === "near").length).toBeGreaterThanOrEqual(1);
        // Something is left to spend: home's "Te quedan" is not zero.
        expect(s.remaining).toBeGreaterThan(0);
      }
    }
  });
});

describe("writes", () => {
  it("POST /api/v1/transactions raises the month's spending by its amount", async () => {
    const { api } = demo();
    const before = await summary(api, "2026-10");
    const categoryId = await firstExpenseCategory(api);
    const created = await api.POST("/v1/transactions", {
      body: { name: "Empanadas", amount: -5_000_00, categoryId, date: "2026-10-21" },
    });
    expect(created.response.status).toBe(201);
    expect(created.data).toMatchObject({ name: "Empanadas", currency: "COP", status: "paid" });
    const after = await summary(api, "2026-10");
    expect(after.spent).toBe(before.spent + 5_000_00);
    expect(after.remaining).toBe(before.remaining - 5_000_00);
  });

  it("DELETE then POST …/restore brings the same transaction back", async () => {
    const { api } = demo();
    const first = (await list(api, "2026-10")).find((t) => t.amount < 0 && t.status === "paid");
    if (!first) throw new Error("the seed has paid expenses this month");
    const before = await summary(api, "2026-10");

    const deleted = await api.DELETE("/v1/transactions/{id}", {
      params: { path: { id: first.id } },
    });
    expect(deleted.response.status).toBe(204);
    expect((await list(api, "2026-10")).some((t) => t.id === first.id)).toBe(false);
    expect((await summary(api, "2026-10")).spent).not.toBe(before.spent);

    const restored = await api.POST("/v1/transactions/{id}/restore", {
      params: { path: { id: first.id } },
    });
    expect(restored.data).toEqual(first);
    expect(await list(api, "2026-10")).toContainEqual(first);
    expect(await summary(api, "2026-10")).toEqual(before);
  });

  it("answers an invalid body with 422 validation_failed, as the API does", async () => {
    const { api } = demo();
    const categoryId = await firstExpenseCategory(api);
    const attempt = api.POST("/v1/transactions", {
      body: { name: "", amount: 0, categoryId, date: "2026-13-01" },
    });
    await expect(attempt).rejects.toMatchObject({ status: 422, code: "validation_failed" });
    const problem = (await attempt.catch((error: unknown) => error)) as ApiProblem;
    expect(problem.errors.map((e) => e.path)).toEqual(
      expect.arrayContaining(["name", "amount", "date"]),
    );
  });

  it("answers an unknown or archived category with 422 category_not_found", async () => {
    const { api } = demo();
    await expect(
      api.POST("/v1/transactions", {
        body: {
          name: "Taxi",
          amount: -1_000,
          categoryId: "11111111-1111-4111-8111-111111111111",
          date: "2026-10-21",
        },
      }),
    ).rejects.toMatchObject({ status: 422, code: "category_not_found" });
  });

  it("keeps the currency once there are transactions: 409 currency_locked", async () => {
    const { api } = demo();
    await expect(api.PATCH("/v1/me", { body: { currency: "EUR" } })).rejects.toMatchObject({
      status: 409,
      code: "currency_locked",
    });
    const me = await api.PATCH("/v1/me", { body: { locale: "en" } });
    expect(me.data).toMatchObject({ locale: "en", currency: "COP" });
  });

  it("reset() goes back to the seed", async () => {
    const { api, backend } = demo();
    const seeded = await snapshot(api, "2026-10");
    const categoryId = await firstExpenseCategory(api);
    await api.POST("/v1/transactions", {
      body: { name: "Empanadas", amount: -5_000_00, categoryId, date: "2026-10-21" },
    });
    await api.PATCH("/v1/me", { body: { locale: "en" } });
    expect(await snapshot(api, "2026-10")).not.toEqual(seeded);
    backend.reset();
    expect(await snapshot(api, "2026-10")).toEqual(seeded);
  });

  it("is deterministic: two backends from the same seed and clock answer the same", async () => {
    for (const locale of ["es", "en", "it", "pt"] as const) {
      const one = demo(locale);
      const two = demo(locale);
      expect(await snapshot(two.api, "2026-10")).toEqual(await snapshot(one.api, "2026-10"));
    }
  });
});

/** The seed's category id for a name (es). */
async function categoryId(api: ApiClient, name: string): Promise<string> {
  const { data } = await api.GET("/v1/categories", {
    params: { query: { includeArchived: "true" } },
  });
  const found = data?.find((c) => c.name === name);
  if (!found) throw new Error(`No category ${name}`);
  return found.id;
}

/** Totals per category of a by-category report, keyed by name. */
const byName = (items: { name: string; total: number }[]) =>
  Object.fromEntries(items.map((i) => [i.name, i.total]));

describe("GET /api/v1/transactions pages like the API", () => {
  it("walks a month by cursor: every row once, newest first, the last page says it is the last", async () => {
    const { api } = demo();
    const all = await list(api, "2026-10");
    expect(all.length).toBeGreaterThan(7);
    const seen: TransactionDto[] = [];
    let cursor: string | undefined;
    let pages = 0;
    do {
      const { data } = await api.GET("/v1/transactions", {
        params: { query: { month: "2026-10", limit: 3, ...(cursor ? { cursor } : {}) } },
      });
      if (!data) throw new Error("a page");
      expect(data.items.length).toBeLessThanOrEqual(3);
      seen.push(...data.items);
      cursor = data.nextCursor ?? undefined;
      pages += 1;
    } while (cursor);
    expect(pages).toBe(Math.ceil(all.length / 3));
    expect(seen.map((t) => t.id)).toEqual(all.map((t) => t.id));
  });

  it("pages one category's rows the same way", async () => {
    const { api } = demo();
    const category = await firstExpenseCategory(api);
    const { data: first } = await api.GET("/v1/transactions", {
      params: { query: { month: "2026-10", category: [category], limit: 1 } },
    });
    expect(first?.items).toHaveLength(1);
    expect(first?.items[0]?.categoryId).toBe(category);
    expect(first?.nextCursor).toEqual(expect.any(String));
  });
});

describe("recurrences materialize on read, as the API's materializeRecurrences", () => {
  it("answers the needsReview filter: the demo has nothing detected to review", async () => {
    const { api } = demo();
    const { data } = await api.GET("/v1/transactions", {
      params: { query: { month: "2026-10", needsReview: "true" } },
    });
    expect(data?.items).toEqual([]);
  });

  it("adds the month's pending salary once, and paying it moves it to the paid totals", async () => {
    const { api } = demo();
    // A report is a read too: before any screen opened October, it already sees the salary.
    const before = await api.GET("/v1/reports/trend", {
      params: { query: { from: "2026-10", to: "2026-10" } },
    });
    expect(before.data?.months[0]?.income).toBe(5_200_000_00);

    const items = await list(api, "2026-10");
    const salary = items.filter((t) => t.name === "Salario");
    expect(salary).toHaveLength(1);
    expect(salary[0]).toMatchObject({
      date: "2026-10-28",
      amount: 5_200_000_00,
      status: "pending",
      source: "recurrence",
    });
    expect(salary[0]?.recurrenceId).not.toBeNull();
    // Reading again adds nothing.
    expect((await list(api, "2026-10")).filter((t) => t.name === "Salario")).toHaveLength(1);
    // The summary counts pending rows, like the API's: the salary is October's income already.
    expect((await summary(api, "2026-10")).income).toBe(5_200_000_00);

    const paidIncome = async () =>
      (
        await api.GET("/v1/reports/by-category", {
          params: { query: { from: "2026-10", to: "2026-10", kind: "income", status: "paid" } },
        })
      ).data?.total;
    expect(await paidIncome()).toBe(0);
    const paid = await api.PATCH("/v1/transactions/{id}", {
      params: { path: { id: salary[0]?.id as string } },
      body: { status: "paid" },
    });
    expect(paid.data?.status).toBe("paid");
    expect(await paidIncome()).toBe(5_200_000_00);
    expect((await summary(api, "2026-10")).income).toBe(5_200_000_00);
    expect((await list(api, "2026-10")).filter((t) => t.name === "Salario")).toHaveLength(1);
  });

  it("fills next month with rent, Spotify and salary as pending, but not the month after", async () => {
    const { api } = demo();
    const november = await list(api, "2026-11");
    expect(november.map((t) => [t.name, t.date, t.status]).sort()).toEqual([
      ["Arriendo", "2026-11-01", "pending"],
      ["Salario", "2026-11-28", "pending"],
      ["Spotify", "2026-11-12", "pending"],
    ]);
    expect(await list(api, "2026-12")).toEqual([]);
  });

  it("never brings back an occurrence that was deleted", async () => {
    const { api } = demo();
    const salary = (await list(api, "2026-10")).find((t) => t.name === "Salario");
    await api.DELETE("/v1/transactions/{id}", { params: { path: { id: salary?.id as string } } });
    expect((await list(api, "2026-10")).some((t) => t.name === "Salario")).toBe(false);
    expect((await summary(api, "2026-10")).income).toBe(0);
  });
});

describe("reports, against the seed worked out by hand (es, 21 October 2026)", () => {
  it("by-category: October's spending, rent first, with shares to 4 decimals", async () => {
    const { api } = demo();
    const { data } = await api.GET("/v1/reports/by-category", {
      params: { query: { from: "2026-10", to: "2026-10" } },
    });
    expect(data?.total).toBe(3_341_900_00);
    expect(data?.items.map((i) => i.name)).toEqual([
      "Arriendo",
      "Mercado",
      "Restaurantes",
      "Servicios",
      "Transporte",
      "Ocio",
      "Café",
      "Salud",
    ]);
    expect(byName(data?.items ?? [])).toEqual({
      Arriendo: 1_800_000_00,
      Mercado: 610_000_00,
      Restaurantes: 342_000_00,
      Servicios: 214_000_00,
      Transporte: 148_000_00,
      Ocio: 96_900_00,
      Café: 86_000_00,
      Salud: 45_000_00,
    });
    expect(data?.items[0]?.share).toBe(0.5386);
    expect(data?.items.find((i) => i.name === "Café")?.share).toBe(0.0257);
  });

  it("trend: income, spending and budget per month, August to October", async () => {
    const { api } = demo();
    const { data } = await api.GET("/v1/reports/trend", {
      params: { query: { from: "2026-07", to: "2026-10" } },
    });
    expect(data?.months).toEqual([
      { month: "2026-07", income: 0, expenses: 0, budget: 0 },
      { month: "2026-08", income: 5_200_000_00, expenses: 3_209_200_00, budget: 3_980_000_00 },
      { month: "2026-09", income: 5_200_000_00, expenses: 3_422_900_00, budget: 3_980_000_00 },
      // October's salary is due on the 28th: pending, and a report counts it like the home
      // screen does (reports materialize the months they read, as the API's do).
      { month: "2026-10", income: 5_200_000_00, expenses: 3_341_900_00, budget: 3_980_000_00 },
    ]);
  });

  it("trend: a month gives the same figures alone or inside a longer range", async () => {
    const { api } = demo();
    const one = await api.GET("/v1/reports/trend", {
      params: { query: { from: "2026-10", to: "2026-10" } },
    });
    const three = await api.GET("/v1/reports/trend", {
      params: { query: { from: "2026-08", to: "2026-10" } },
    });
    expect(one.data?.months[0]).toEqual(three.data?.months[2]);
    expect(one.data?.months[0]?.income).toBe(5_200_000_00);
  });

  it("cost of living: August and September averaged, rent and Spotify's category fixed", async () => {
    const { api } = demo();
    const { data } = await api.GET("/v1/reports/cost-of-living", {
      params: { query: { months: 2 } },
    });
    expect(data).toMatchObject({
      months: 2,
      total: 3_316_050_00,
      fixed: 1_908_900_00,
      variable: 1_407_150_00,
    });
    const names = new Map(
      ((await api.GET("/v1/categories")).data ?? []).map((c) => [c.id, c.name]),
    );
    expect(
      Object.fromEntries(
        (data?.categories ?? []).map((c) => [names.get(c.categoryId), [c.average, c.type]]),
      ),
    ).toEqual({
      Arriendo: [1_800_000_00, "fixed"],
      Mercado: [619_200_00, "variable"],
      Restaurantes: [265_050_00, "variable"],
      Servicios: [216_250_00, "variable"],
      Transporte: [155_400_00, "variable"],
      Ocio: [108_900_00, "fixed"],
      Café: [86_000_00, "variable"],
      Salud: [65_250_00, "variable"],
    });
  });

  it("rejects a range that ends before it starts, or longer than 36 months", async () => {
    const { api } = demo();
    await expect(
      api.GET("/v1/reports/trend", { params: { query: { from: "2026-10", to: "2026-09" } } }),
    ).rejects.toMatchObject({ status: 422, code: "validation_failed" });
    await expect(
      api.GET("/v1/reports/trend", { params: { query: { from: "2023-01", to: "2026-10" } } }),
    ).rejects.toMatchObject({ status: 422, code: "range_too_large" });
  });
});

describe("a new category with a budget", () => {
  it("is created, gets its budget from this month on, and counts in the summary", async () => {
    const { api } = demo();
    const before = await summary(api, "2026-10");
    const created = await api.POST("/v1/categories", {
      body: { name: "Mascotas", kind: "expense", icon: "🐶", color: "#2ec4b6" },
    });
    expect(created.response.status).toBe(201);
    expect(created.data).toMatchObject({ name: "Mascotas", archived: false, currentBudget: null });
    const id = created.data?.id as string;

    const budgeted = await api.PUT("/v1/categories/{id}/budget", {
      params: { path: { id } },
      body: { amount: 200_000_00, effectiveFrom: "2026-10" },
    });
    expect(budgeted.data?.currentBudget).toBe(200_000_00);
    expect((await api.GET("/v1/categories")).data?.find((c) => c.id === id)?.currentBudget).toBe(
      200_000_00,
    );

    const after = await summary(api, "2026-10");
    expect(after.budgetTotal).toBe(before.budgetTotal + 200_000_00);
    expect(after.remaining).toBe(before.remaining + 200_000_00);
    expect(after.categories.find((c) => c.categoryId === id)).toMatchObject({
      budget: 200_000_00,
      spent: 0,
      state: "ok",
    });
    // From October on: September's budget is unchanged.
    expect((await summary(api, "2026-09")).budgetTotal).toBe(3_980_000_00);

    // Spending in it moves its own row.
    await api.POST("/v1/transactions", {
      body: { name: "Concentrado", amount: -170_000_00, categoryId: id, date: "2026-10-21" },
    });
    expect(
      (await summary(api, "2026-10")).categories.find((c) => c.categoryId === id),
    ).toMatchObject({ spent: 170_000_00, state: "near" });
  });

  it("refuses a name already taken (409) and a budget on an income category (422)", async () => {
    const { api } = demo();
    await expect(
      api.POST("/v1/categories", {
        body: { name: "café", kind: "expense", icon: "☕", color: "#ffb547" },
      }),
    ).rejects.toMatchObject({ status: 409, code: "category_name_taken" });
    await expect(
      api.PUT("/v1/categories/{id}/budget", {
        params: { path: { id: await categoryId(api, "Salario") } },
        body: { amount: 100_00, effectiveFrom: "2026-10" },
      }),
    ).rejects.toMatchObject({ status: 422, code: "budget_category_not_expense" });
  });
});

describe("GET /api/v1/transactions searches like the API", () => {
  type Page = {
    items: TransactionDto[];
    totals?: { count: number; expense: number; income: number };
  };
  async function search(api: ApiClient, query: Record<string, unknown>): Promise<Page> {
    const { data, error } = await api.GET("/v1/transactions", {
      params: { query: { limit: 200, ...query } as never },
    });
    if (!data) throw new Error(`search failed: ${JSON.stringify(error)}`);
    return data;
  }

  it("q folds accents and case: cafe finds Café", async () => {
    const { api } = demo();
    const { items } = await search(api, { q: ["cafe"] });
    expect(items.length).toBeGreaterThan(0);
    expect(items.some((t) => t.name === "Café")).toBe(true);
    for (const t of items) expect(`${t.name} ${t.note ?? ""}`.toLowerCase()).toMatch(/caf/);
  });

  it("several q terms find a movement that has any of them", async () => {
    const { api } = demo();
    const a = await search(api, { q: ["cafe"] });
    const b = await search(api, { q: ["taxi"] });
    const both = await search(api, { q: ["cafe", "taxi"] });
    expect(b.items.length).toBeGreaterThan(0);
    expect(both.items.length).toBe(new Set([...a.items, ...b.items].map((t) => t.id)).size);
  });

  it("kind keeps spending or income only", async () => {
    const { api } = demo();
    const income = await search(api, { kind: "income" });
    const expense = await search(api, { kind: "expense" });
    expect(income.items.length).toBeGreaterThan(0);
    expect(income.items.every((t) => t.amount > 0)).toBe(true);
    expect(expense.items.every((t) => t.amount < 0)).toBe(true);
  });

  it("category takes a list", async () => {
    const { api } = demo();
    const { data } = await api.GET("/v1/categories");
    const [c1, c2] = (data ?? []).filter((c) => c.kind === "expense");
    const ids = [c1?.id, c2?.id] as string[];
    const { items } = await search(api, { category: ids });
    expect(items.length).toBeGreaterThan(0);
    expect(items.every((t) => ids.includes(t.categoryId))).toBe(true);
    expect(new Set(items.map((t) => t.categoryId)).size).toBe(2);
  });

  it("match=any joins terms and categories; all intersects them", async () => {
    const { api } = demo();
    const { data } = await api.GET("/v1/categories");
    const transport = (data ?? []).find((c) => c.kind === "expense");
    const q = await search(api, { q: ["cafe"] });
    const c = await search(api, { category: [transport?.id] });
    const any = await search(api, { q: ["cafe"], category: [transport?.id], match: "any" });
    const all = await search(api, { q: ["cafe"], category: [transport?.id] });
    expect(any.items.length).toBe(new Set([...q.items, ...c.items].map((t) => t.id)).size);
    expect(all.items.length).toBeLessThanOrEqual(any.items.length);
  });

  it("totals cover every match, not the page", async () => {
    const { api } = demo();
    const full = await search(api, { kind: "expense", totals: "true" });
    const paged = await search(api, { kind: "expense", totals: "true", limit: 2 });
    expect(paged.items).toHaveLength(2);
    expect(paged.totals).toEqual(full.totals);
    expect(full.totals?.count).toBe(full.items.length);
    expect(full.totals?.expense).toBe(-full.items.reduce((s, t) => s + t.amount, 0));
    expect(full.totals?.income).toBe(0);
    expect((await search(api, {})).totals).toBeUndefined();
  });

  it("rejects too many terms or categories, a long term, a bad kind or match with 422", async () => {
    const { api } = demo();
    const id = "00000000-0000-4000-8000-000000000001";
    const bad = [
      { q: Array.from({ length: 11 }, (_, i) => `t${i}`) },
      { q: ["x".repeat(101)] },
      { category: Array.from({ length: 21 }, () => id) },
      { category: ["nope"] },
      { kind: "other" },
      { match: "some" },
    ];
    for (const query of bad) {
      await expect(
        api.GET("/v1/transactions", { params: { query: query as never } }),
      ).rejects.toMatchObject({ status: 422 });
    }
  });
});
