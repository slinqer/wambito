import { transactions } from "@wambito/db";
import { eq } from "@wambito/db/orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createTestApp, type TestApp } from "./harness.ts";

let t: TestApp;
let a: { authorization: string };
let b: { authorization: string };
let ocio: string;
let archived: string;

interface Tx {
  id: string;
  name: string;
  amount: number;
  date: string;
  status: string;
  currency: string;
  source: string;
}
interface Page {
  items: Tx[];
  nextCursor: string | null;
  totals?: { count: number; expense: number; income: number };
}

async function category(headers: typeof a, name: string) {
  const res = await t.request("POST", "/v1/categories", {
    headers,
    body: { name, kind: "expense", icon: "star", color: "purple" },
  });
  return ((await res.json()) as { id: string }).id;
}

beforeAll(async () => {
  t = await createTestApp();
  a = (await t.signIn("a@wambito.test")).headers;
  b = (await t.signIn("b@wambito.test")).headers;
  ocio = await category(a, "Ocio");
  archived = await category(a, "Old");
  await t.request("PATCH", `/v1/categories/${archived}`, { headers: a, body: { archived: true } });
});
afterAll(() => t?.stop());

const create = (body: object, headers: Record<string, string> = a) =>
  t.request("POST", "/v1/transactions", { headers, body: { categoryId: ocio, ...body } });
const page = async (query: string, headers = a) =>
  (await (await t.request("GET", `/v1/transactions${query}`, { headers })).json()) as Page;

describe("transactions", () => {
  let cinema: Tx;

  test("create copies the account currency and defaults the source", async () => {
    const res = await create({ name: "cinema", amount: -950, date: "2026-10-05" });
    expect(res.status).toBe(201);
    cinema = (await res.json()) as Tx;
    expect(cinema).toMatchObject({ currency: "EUR", source: "app", status: "paid", amount: -950 });
  });

  test("list filters by month and status", async () => {
    await create({ name: "concert", amount: -3000, date: "2026-11-02", status: "pending" });
    expect((await page("?month=2026-10")).items.map((i) => i.name)).toEqual(["cinema"]);
    expect((await page("?status=pending")).items.map((i) => i.name)).toEqual(["concert"]);
  });

  test("list filters by a date range and by text, ignoring case and accents", async () => {
    const { headers } = await t.signIn("search@wambito.test");
    const comida = await category(headers, "Comida");
    const add = (name: string, date: string, note?: string) =>
      create({ name, amount: -1000, date, categoryId: comida, ...(note ? { note } : {}) }, headers);
    await add("Almuérzo corrientazo", "2026-09-30");
    await add("Almuerzo", "2026-10-01");
    await add("Taxi", "2026-10-15", "volviendo del ALMUERZO");
    await add("Mercado 50%", "2026-10-31");
    const names = async (query: string) => (await page(query, headers)).items.map((i) => i.name);
    expect(await names("?from=2026-10-01&to=2026-10-15")).toEqual(["Taxi", "Almuerzo"]);
    expect(await names("?from=2026-10-15")).toEqual(["Mercado 50%", "Taxi"]);
    expect(await names("?q=almuerzo")).toEqual(["Taxi", "Almuerzo", "Almuérzo corrientazo"]);
    expect(await names("?q=ALMUÉR&to=2026-09-30")).toEqual(["Almuérzo corrientazo"]);
    // `%` and `_` are text, not wildcards.
    expect(await names("?q=50%25")).toEqual(["Mercado 50%"]);
    expect(await names("?q=_")).toEqual([]);
    const backwards = await t.request("GET", "/v1/transactions?from=2026-10-02&to=2026-10-01", {
      headers,
    });
    expect(backwards.status).toBe(422);
  });

  describe("movement search filters", () => {
    let h: { authorization: string };
    let catA: string;
    let catB: string;
    let catC: string;
    const names = async (query: string) => (await page(query, h)).items.map((i) => i.name);

    beforeAll(async () => {
      h = (await t.signIn("movsearch@wambito.test")).headers;
      catA = await category(h, "CatA");
      catB = await category(h, "CatB");
      catC = await category(h, "CatC");
      const add = (name: string, amount: number, date: string, categoryId: string) =>
        create({ name, amount, date, categoryId }, h);
      await add("Almuerzo", -1000, "2026-08-01", catA);
      await add("Corrientazo", -2000, "2026-09-02", catB);
      await add("Cafe", -300, "2026-09-03", catA);
      await add("Café Bogotá", -400, "2026-10-04", catB);
      await add("Almuerzo trabajo", -500, "2026-10-05", catB);
      await add("Sueldo", 9000, "2026-08-10", catA);
      await add("Sueldo extra", 1000, "2026-10-10", catB);
      await add("Gasto C", -50, "2026-10-14", catC);
      await add("Descuento 50%", -100, "2026-10-11", catB);
      await add("a_b", -100, "2026-10-12", catB);
      await add("axb", -100, "2026-10-13", catB);
      const other = (await t.signIn("movother@wambito.test")).headers;
      const otherCat = await category(other, "Otra");
      await create(
        { name: "Almuerzo ajeno", amount: -7777, date: "2026-10-01", categoryId: otherCat },
        other,
      );
      await create(
        { name: "Sueldo ajeno", amount: 7777, date: "2026-10-01", categoryId: otherCat },
        other,
      );
    });

    test("kind filters by the sign of the amount, across months, newest first", async () => {
      expect(await names("?kind=expense&q=almuerzo")).toEqual(["Almuerzo trabajo", "Almuerzo"]);
      expect(await names("?kind=income")).toEqual(["Sueldo extra", "Sueldo"]);
      expect(await names("?kind=income&q=sueldo")).toEqual(["Sueldo extra", "Sueldo"]);
      expect(await names("?kind=income&q=almuerzo")).toEqual([]);
    });

    test("several q terms match any of them", async () => {
      expect(await names("?q=almuerzo&q=corrientazo")).toEqual([
        "Almuerzo trabajo",
        "Corrientazo",
        "Almuerzo",
      ]);
    });

    test("several categories match any of them", async () => {
      const both = await names(`?category=${catA}&category=${catB}`);
      expect(both).toEqual([
        "axb",
        "a_b",
        "Descuento 50%",
        "Sueldo extra",
        "Almuerzo trabajo",
        "Café Bogotá",
        "Cafe",
        "Corrientazo",
        "Sueldo",
        "Almuerzo",
      ]);
      expect(both).not.toContain("Gasto C");
      expect(await names(`?category=${catA}`)).toEqual(["Cafe", "Sueldo", "Almuerzo"]);
    });

    test("match=any ORs text and category, match=all ANDs them", async () => {
      const any = await names(`?match=any&category=${catA}&q=almuerzo`);
      expect(any).toEqual(["Almuerzo trabajo", "Cafe", "Sueldo", "Almuerzo"]);
      expect(await names(`?match=all&category=${catA}&q=almuerzo`)).toEqual(["Almuerzo"]);
      expect(await names(`?category=${catA}&q=almuerzo`)).toEqual(["Almuerzo"]);
    });

    test("totals cover every match, on every page, and are absent unless asked", async () => {
      const first = await page("?kind=expense&q=almuerzo&q=cafe&limit=2&totals=true", h);
      expect(first.items).toHaveLength(2);
      expect(first.nextCursor).not.toBeNull();
      const totals = { count: 4, expense: 2200, income: 0 };
      expect(first.totals).toEqual(totals);
      const second = await page(
        `?kind=expense&q=almuerzo&q=cafe&limit=2&totals=true&cursor=${first.nextCursor}`,
        h,
      );
      expect(second.totals).toEqual(totals);
      const mixed = await page("?totals=true&limit=1", h);
      expect(mixed.totals).toEqual({
        count: 11,
        expense: 4550,
        income: 10000,
      });
      expect(await page("?limit=1", h)).not.toHaveProperty("totals");
      expect(await page("?limit=1&totals=false", h)).not.toHaveProperty("totals");
    });

    test("wildcards are text and a single word still finds accents", async () => {
      expect(await names("?q=50%25")).toEqual(["Descuento 50%"]);
      expect(await names("?q=a_b")).toEqual(["a_b"]);
      expect(await names("?q=cafe")).toEqual(["Café Bogotá", "Cafe"]);
    });

    test("too many terms, long terms, too many categories and bad enums are 422", async () => {
      const terms = (n: number) => Array.from({ length: n }, (_, i) => `q=t${i}`).join("&");
      const cats = Array.from({ length: 21 }, () => `category=${catA}`).join("&");
      for (const query of [
        `?${terms(11)}`,
        `?q=${"x".repeat(101)}`,
        `?${cats}`,
        "?kind=other",
        "?match=some",
      ]) {
        const res = await t.request("GET", `/v1/transactions${query}`, { headers: h });
        expect(res.status, query).toBe(422);
        expect(await res.json(), query).toMatchObject({ code: "validation_failed" });
      }
      expect((await t.request("GET", `/v1/transactions?${terms(10)}`, { headers: h })).status).toBe(
        200,
      );
    });

    test("totals past 2^31 cents are exact", async () => {
      const big = (await t.signIn("movbig@wambito.test")).headers;
      const cat = await category(big, "Big");
      const add = (amount: number, date: string) =>
        create({ name: "Big", amount, date, categoryId: cat }, big);
      await add(3_000_000_000, "2026-10-01");
      await add(2_500_000_000, "2026-10-02");
      await add(-4_000_000_000, "2026-10-03");
      await add(-1, "2026-10-04");
      expect((await page("?totals=true", big)).totals).toEqual({
        count: 4,
        expense: 4_000_000_001,
        income: 5_500_000_000,
      });
    });

    test("other users' rows never show in items or totals", async () => {
      expect(await names("?q=ajeno")).toEqual([]);
      const res = await page("?totals=true&kind=income", h);
      expect(res.totals?.income).toBe(10000);
    });

    test("a request without month makes no pending recurrence rows", async () => {
      const made = await t.request("POST", "/v1/recurrences", {
        headers: h,
        body: {
          name: "Rent",
          amount: -5000,
          categoryId: catA,
          frequency: "monthly",
          dayOfMonth: 1,
          startDate: "2026-01-01",
        },
      });
      expect(made.status).toBe(201);
      expect(await names("?q=rent")).toEqual([]);
      // Control: asking for a month does materialize the rule.
      expect(await names("?q=rent&month=2026-10")).toEqual(["Rent"]);
    });

    test("the OpenAPI document declares q and category as exploded form arrays", async () => {
      const doc = (await (await t.request("GET", "/openapi.json")).json()) as {
        paths: Record<
          string,
          { get?: { operationId?: string; parameters?: Record<string, unknown>[] } }
        >;
      };
      const params = doc.paths["/v1/transactions"]?.get?.parameters ?? [];
      for (const name of ["q", "category"]) {
        const p = params.find((x) => x.name === name) as
          | { schema: { type: string }; style?: string; explode?: boolean }
          | undefined;
        expect(p?.schema.type, name).toBe("array");
        expect(p?.style, name).toBe("form");
        expect(p?.explode, name).toBe(true);
      }
    });
  });

  test("edit, delete and restore", async () => {
    let res = await t.request("PATCH", `/v1/transactions/${cinema.id}`, {
      headers: a,
      body: { amount: -1200 },
    });
    expect(res.status).toBe(200);
    expect(((await res.json()) as Tx).amount).toBe(-1200);

    res = await t.request("DELETE", `/v1/transactions/${cinema.id}`, { headers: a });
    expect(res.status).toBe(204);
    expect((await page("?month=2026-10")).items).toEqual([]);
    res = await t.request("PATCH", `/v1/transactions/${cinema.id}`, {
      headers: a,
      body: { amount: -1 },
    });
    expect(res.status).toBe(404);

    res = await t.request("POST", `/v1/transactions/${cinema.id}/restore`, { headers: a });
    expect(res.status).toBe(200);
    expect((await page("?month=2026-10")).items.map((i) => i.id)).toEqual([cinema.id]);
  });

  test("archived or foreign categories are rejected", async () => {
    let res = await create({ name: "x", amount: -1, date: "2026-10-01", categoryId: archived });
    expect(res.status).toBe(422);
    expect(await res.json()).toMatchObject({ code: "category_not_found" });
    const foreign = await category(b, "Theirs");
    res = await create({ name: "x", amount: -1, date: "2026-10-01", categoryId: foreign });
    expect(res.status).toBe(422);
  });

  test("users cannot see or touch each other's transactions", async () => {
    expect((await page("", b)).items).toEqual([]);
    for (const [method, path] of [
      ["PATCH", `/v1/transactions/${cinema.id}`],
      ["DELETE", `/v1/transactions/${cinema.id}`],
      ["POST", `/v1/transactions/${cinema.id}/restore`],
    ] as const) {
      const res = await t.request(method, path, {
        headers: b,
        body: method === "PATCH" ? { amount: -1 } : undefined,
      });
      expect(res.status).toBe(404);
    }
  });

  test("an Idempotency-Key reused with a different body is rejected", async () => {
    const headers = { ...a, "idempotency-key": "widget-123" };
    expect(
      (await create({ name: "coffee", amount: -120, date: "2026-10-06" }, headers)).status,
    ).toBe(201);
    const replay = await create({ name: "coffee", amount: -120, date: "2026-10-06" }, headers);
    expect(replay.status).toBe(201);
    const reused = await create({ name: "coffee", amount: -999, date: "2026-10-06" }, headers);
    expect(reused.status).toBe(422);
    expect(await reused.json()).toMatchObject({ code: "idempotency_key_reused" });
    expect((await page("?month=2026-10")).items.filter((i) => i.name === "coffee")).toHaveLength(1);
  });

  test("pagination over many same-day transactions returns each exactly once", async () => {
    // One through the API; the other 119 straight into the table in one insert. Creating is not
    // what this checks, and 120 requests one by one took 20-27 s on a loaded machine.
    const first = (await (
      await create({ name: "bulk 0", amount: -1, date: "2026-12-15" })
    ).json()) as Tx;
    const [row] = await t.admin.select().from(transactions).where(eq(transactions.id, first.id));
    if (!row) throw new Error("The first bulk transaction is in the table");
    await t.admin.insert(transactions).values(
      Array.from({ length: 119 }, (_, i) => ({
        userId: row.userId,
        accountId: row.accountId,
        categoryId: row.categoryId,
        name: `bulk ${i + 1}`,
        amount: row.amount,
        currency: row.currency,
        date: row.date,
        source: row.source,
      })),
    );
    const ids: string[] = [];
    const sizes: number[] = [];
    let cursor: string | null = null;
    do {
      const query: string = `?month=2026-12&limit=50${cursor ? `&cursor=${cursor}` : ""}`;
      const p = await page(query);
      ids.push(...p.items.map((i) => i.id));
      sizes.push(p.items.length);
      cursor = p.nextCursor;
    } while (cursor);
    expect(sizes).toEqual([50, 50, 20]);
    expect(new Set(ids).size).toBe(120);
  });

  test("a malformed cursor is a validation problem, not a server error", async () => {
    const cursor = Buffer.from("notadate|0192f5a0-0000-7000-8000-000000000001").toString(
      "base64url",
    );
    const res = await t.request("GET", `/v1/transactions?cursor=${cursor}`, { headers: a });
    expect(res.status).toBe(422);
    expect(await res.json()).toMatchObject({ code: "validation_failed" });
  });
});
