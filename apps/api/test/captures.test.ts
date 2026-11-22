import { accounts, categories, merchantCategories, transactions } from "@wambito/db";
import { and, eq } from "@wambito/db/orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createTestApp, type TestApp } from "./harness.ts";

let t: TestApp;
let a: { userId: string; headers: { authorization: string } };
let b: { userId: string; headers: { authorization: string } };

interface CaptureResult {
  result: "created" | "merged";
  transaction: {
    id: string;
    amount: number;
    currency: string;
    date: string;
    note: string | null;
    needsReview: boolean;
    source: string;
    captureSource: string | null;
    categoryId: string;
  };
  category: { name: string; fallback: boolean };
}

let keyCounter = 0;
const body = (extra: object = {}) => ({
  kind: "expense",
  amount: 1250,
  currency: "EUR",
  merchant: "Mercadona",
  capturedAt: "2026-11-04T15:00:00Z",
  source: "revolut",
  ...extra,
});
const capture = (
  extra: object = {},
  { user = a, key = `capture-key-${++keyCounter}` as string | null } = {},
) =>
  t.request("POST", "/v1/captures", {
    headers: { ...user.headers, ...(key ? { "idempotency-key": key } : {}) },
    body: body(extra),
  });
const json = async (res: Response) => (await res.json()) as CaptureResult;
const rows = async (user = a) =>
  (
    (await (
      await t.request("GET", "/v1/transactions?limit=200", { headers: user.headers })
    ).json()) as { items: { id: string }[] }
  ).items;
const at = (iso: string) => ({ capturedAt: iso });

beforeAll(async () => {
  t = await createTestApp();
  a = await t.signIn("a@wambito.test");
  b = await t.signIn("b@wambito.test");
});
afterAll(() => t?.stop());

describe("create", () => {
  test("creates a capture to review", async () => {
    const res = await capture({ merchant: "Create Shop" });
    expect(res.status).toBe(201);
    const out = await json(res);
    expect(out.result).toBe("created");
    expect(out.transaction).toMatchObject({
      amount: -1250,
      currency: "EUR",
      needsReview: true,
      source: "capture",
      captureSource: "revolut",
      note: null,
    });
    expect(out.category).toEqual({ name: "Otros gastos", fallback: true });
  });

  test("income lands in Otros ingresos", async () => {
    const out = await json(await capture({ kind: "income", amount: 500, merchant: "Income Co" }));
    expect(out.transaction.amount).toBe(500);
    expect(out.category).toEqual({ name: "Otros ingresos", fallback: true });
  });

  test("a merchant with no letters still saves, into the fallback", async () => {
    const res = await capture({ merchant: "***", amount: 777 });
    expect(res.status).toBe(201);
    expect((await json(res)).category).toEqual({ name: "Otros gastos", fallback: true });
  });

  test("a note keeps the original amount when the currency differs", async () => {
    const out = await json(await capture({ currency: "USD", amount: 5000, merchant: "Abroad" }));
    expect(out.transaction.note).toBe("50.00 USD");
    expect(out.transaction.needsReview).toBe(true);
    expect(out.transaction.amount).toBe(-5000);
    expect(out.transaction.currency).not.toBe("USD");
  });

  test("dates by the profile zone", async () => {
    const c = await t.signIn("zone@wambito.test");
    await t.request("PATCH", "/v1/me", {
      headers: c.headers,
      body: { timezone: "America/Bogota" },
    });
    const out = await json(await capture(at("2026-11-05T03:30:00Z"), { user: c }));
    expect(out.transaction.date).toBe("2026-11-04");
  });
});

describe("de-duplication", () => {
  test("merges within 10 minutes", async () => {
    const first = await json(await capture({ amount: 1111, ...at("2026-11-04T10:00:00Z") }));
    const before = (await rows()).length;
    const res = await capture({
      amount: 1111,
      source: "google_wallet",
      ...at("2026-11-04T10:09:00Z"),
    });
    expect(res.status).toBe(200);
    const out = await json(res);
    expect(out.result).toBe("merged");
    expect(out.transaction.id).toBe(first.transaction.id);
    expect(out.category.fallback).toBe(true);
    expect((await rows()).length).toBe(before);
  });

  test("does not merge after 10 minutes", async () => {
    const first = await json(await capture({ amount: 2222, ...at("2026-11-04T10:00:00Z") }));
    const second = await json(await capture({ amount: 2222, ...at("2026-11-04T10:11:00Z") }));
    expect(second.result).toBe("created");
    expect(second.transaction.id).not.toBe(first.transaction.id);
  });

  test("does not merge across kind", async () => {
    await capture({ amount: 3333, ...at("2026-11-04T10:00:00Z") });
    const out = await json(
      await capture({ amount: 3333, kind: "income", ...at("2026-11-04T10:01:00Z") }),
    );
    expect(out.result).toBe("created");
  });

  test("does not merge across amount or currency", async () => {
    await capture({ amount: 4444, ...at("2026-11-04T10:00:00Z") });
    expect(
      (await json(await capture({ amount: 4445, ...at("2026-11-04T10:01:00Z") }))).result,
    ).toBe("created");
    expect(
      (await json(await capture({ amount: 4444, currency: "USD", ...at("2026-11-04T10:01:00Z") })))
        .result,
    ).toBe("created");
  });

  test("merges into a confirmed capture", async () => {
    const first = await json(await capture({ amount: 5555, ...at("2026-11-04T10:00:00Z") }));
    await t.admin
      .update(transactions)
      .set({ needsReview: false })
      .where(eq(transactions.id, first.transaction.id));
    const out = await json(
      await capture({ amount: 5555, source: "google_wallet", ...at("2026-11-04T10:05:00Z") }),
    );
    expect(out.result).toBe("merged");
    expect(out.transaction.id).toBe(first.transaction.id);
  });

  test("never merges with a hand-typed transaction", async () => {
    const cat = await json(await capture({ amount: 6001, ...at("2026-11-03T10:00:00Z") }));
    await t.admin.insert(transactions).values({
      userId: a.userId,
      accountId: (await t.admin.select().from(accounts).where(eq(accounts.userId, a.userId)))[0]
        ?.id as string,
      categoryId: cat.transaction.categoryId,
      name: "by hand",
      amount: -6666,
      currency: cat.transaction.currency,
      date: "2026-11-04",
      source: "app",
      capturedAt: new Date("2026-11-04T10:00:00Z"),
    });
    const out = await json(await capture({ amount: 6666, ...at("2026-11-04T10:02:00Z") }));
    expect(out.result).toBe("created");
  });

  test("merges a foreign-currency capture", async () => {
    const first = await json(
      await capture({ currency: "USD", amount: 8800, ...at("2026-11-04T10:00:00Z") }),
    );
    const second = await json(
      await capture({
        currency: "USD",
        amount: 8800,
        source: "google_wallet",
        ...at("2026-11-04T10:04:00Z"),
      }),
    );
    expect(second.result).toBe("merged");
    expect(second.transaction.id).toBe(first.transaction.id);
  });

  test("isolates users", async () => {
    await capture({ amount: 7777, ...at("2026-11-04T10:00:00Z") });
    const out = await json(
      await capture({ amount: 7777, ...at("2026-11-04T10:01:00Z") }, { user: b }),
    );
    expect(out.result).toBe("created");
  });
});

describe("category", () => {
  test("uses the merchant memory", async () => {
    const c = await t.signIn("memory@wambito.test");
    const [cat] = await t.admin
      .insert(categories)
      .values({ userId: c.userId, name: "Super", kind: "expense", icon: "🛒", color: "#fff" })
      .returning();
    await t.admin
      .insert(merchantCategories)
      .values({ userId: c.userId, merchantKey: "mercadona", categoryId: cat?.id as string });
    const out = await json(await capture({ merchant: "MERCADONA 1234" }, { user: c }));
    expect(out.transaction.categoryId).toBe(cat?.id);
    expect(out.category).toEqual({ name: "Super", fallback: false });
  });

  test("a branch of a learned chain gets the chain's category, the longest learned name first", async () => {
    const c = await t.signIn("memory-prefix@wambito.test");
    const [chain, branch] = await t.admin
      .insert(categories)
      .values([
        { userId: c.userId, name: "Super", kind: "expense", icon: "🛒", color: "#fff" },
        { userId: c.userId, name: "Barrio", kind: "expense", icon: "🏠", color: "#fff" },
      ])
      .returning();
    await t.admin
      .insert(merchantCategories)
      .values({ userId: c.userId, merchantKey: "lidl", categoryId: chain?.id as string });
    const first = await json(
      await capture({ merchant: "LIDL CASAL RIBEIRO", ...at("2026-11-04T10:00:00Z") }, { user: c }),
    );
    expect(first.category).toEqual({ name: "Super", fallback: false });

    await t.admin
      .insert(merchantCategories)
      .values({ userId: c.userId, merchantKey: "lidl casal", categoryId: branch?.id as string });
    const second = await json(
      await capture(
        { merchant: "LIDL CASAL RIBEIRO", amount: 4321, ...at("2026-11-05T10:00:00Z") },
        { user: c },
      ),
    );
    expect(second.category).toEqual({ name: "Barrio", fallback: false });
  });

  test("an exact learned name wins over its chain", async () => {
    const c = await t.signIn("memory-exact@wambito.test");
    const [chain, exact] = await t.admin
      .insert(categories)
      .values([
        { userId: c.userId, name: "Super", kind: "expense", icon: "🛒", color: "#fff" },
        { userId: c.userId, name: "Gasolina", kind: "expense", icon: "⛽", color: "#fff" },
      ])
      .returning();
    await t.admin.insert(merchantCategories).values([
      { userId: c.userId, merchantKey: "repsol", categoryId: chain?.id as string },
      { userId: c.userId, merchantKey: "repsol estacion", categoryId: exact?.id as string },
    ]);
    const out = await json(await capture({ merchant: "REPSOL ESTACION" }, { user: c }));
    expect(out.category).toEqual({ name: "Gasolina", fallback: false });
  });

  test("a first word under 3 letters never matches by prefix", async () => {
    const c = await t.signIn("memory-short@wambito.test");
    const [cat] = await t.admin
      .insert(categories)
      .values({ userId: c.userId, name: "Bar", kind: "expense", icon: "🍺", color: "#fff" })
      .returning();
    await t.admin
      .insert(merchantCategories)
      .values({ userId: c.userId, merchantKey: "el", categoryId: cat?.id as string });
    const out = await json(await capture({ merchant: "EL CORTE INGLES" }, { user: c }));
    expect(out.category).toEqual({ name: "Otros gastos", fallback: true });
  });

  test("ignores a remembered category of the other kind", async () => {
    const c = await t.signIn("memory3@wambito.test");
    const [cat] = await t.admin
      .insert(categories)
      .values({ userId: c.userId, name: "Salary", kind: "income", icon: "💰", color: "#fff" })
      .returning();
    await t.admin
      .insert(merchantCategories)
      .values({ userId: c.userId, merchantKey: "mercadona", categoryId: cat?.id as string });
    const out = await json(await capture({}, { user: c }));
    expect(out.category).toEqual({ name: "Otros gastos", fallback: true });
  });

  test("falls back when the remembered category was archived", async () => {
    const c = await t.signIn("memory2@wambito.test");
    const [cat] = await t.admin
      .insert(categories)
      .values({
        userId: c.userId,
        name: "Old",
        kind: "expense",
        icon: "🛒",
        color: "#fff",
        archivedAt: new Date(),
      })
      .returning();
    await t.admin
      .insert(merchantCategories)
      .values({ userId: c.userId, merchantKey: "mercadona", categoryId: cat?.id as string });
    const out = await json(await capture({}, { user: c }));
    expect(out.category).toEqual({ name: "Otros gastos", fallback: true });
  });

  test("adopts an existing Otros gastos instead of a second one", async () => {
    const c = await t.signIn("adopt@wambito.test");
    const made = await t.request("POST", "/v1/categories", {
      headers: c.headers,
      body: { name: "Otros gastos", kind: "expense", icon: "x", color: "red" },
    });
    const id = ((await made.json()) as { id: string }).id;
    const out = await json(await capture({}, { user: c }));
    expect(out.transaction.categoryId).toBe(id);
    expect(out.category.fallback).toBe(true);
    const [row] = await t.admin.select().from(categories).where(eq(categories.id, id));
    expect(row?.systemKey).toBe("other");
  });

  test("creates a new fallback after archiving it", async () => {
    const c = await t.signIn("archive@wambito.test");
    const first = await json(await capture({ amount: 11 }, { user: c }));
    await t.request("PATCH", `/v1/categories/${first.transaction.categoryId}`, {
      headers: c.headers,
      body: { archived: true },
    });
    const [archived] = await t.admin
      .select()
      .from(categories)
      .where(eq(categories.id, first.transaction.categoryId));
    expect(archived?.systemKey).toBeNull();
    const second = await json(await capture({ amount: 12 }, { user: c }));
    expect(second.transaction.categoryId).not.toBe(first.transaction.categoryId);
    expect(second.category).toEqual({ name: "Otros gastos", fallback: true });
  });

  test("names the fallback in the profile language", async () => {
    const c = await t.signIn("en@wambito.test");
    await t.request("PATCH", "/v1/me", { headers: c.headers, body: { locale: "en" } });
    const out = await json(await capture({}, { user: c }));
    expect(out.category.name).toBe("Other expenses");
    const inc = await json(await capture({ kind: "income" }, { user: c }));
    expect(inc.category.name).toBe("Other income");
    const [row] = await t.admin
      .select()
      .from(categories)
      .where(and(eq(categories.userId, c.userId), eq(categories.systemKey, "other")));
    expect(row).toBeDefined();
  });
});

describe("idempotency", () => {
  test("requires an idempotency key", async () => {
    expect((await capture({}, { key: null })).status).toBe(400);
  });

  test("a retry returns the first answer", async () => {
    const c = await t.signIn("retry@wambito.test");
    const key = "retry-1";
    const first = await capture({ amount: 99 }, { user: c, key });
    const second = await capture({ amount: 99 }, { user: c, key });
    expect(first.status).toBe(201);
    expect(second.status).toBe(201);
    expect((await json(second)).transaction.id).toBe((await json(first)).transaction.id);
    expect((await rows(c)).length).toBe(1);
  });
});

describe("review", () => {
  const mkCategory = async (
    user: typeof a,
    name: string,
    kind: "expense" | "income" = "expense",
  ) => {
    const [cat] = await t.admin
      .insert(categories)
      .values({ userId: user.userId, name, kind, icon: "🛒", color: "#fff" })
      .returning();
    return cat?.id as string;
  };
  const patch = (user: typeof a, id: string, patchBody: object) =>
    t.request("PATCH", `/v1/transactions/${id}`, { headers: user.headers, body: patchBody });
  const review = (user: typeof a, ids: string[]) =>
    t.request("POST", "/v1/transactions/review", { headers: user.headers, body: { ids } });
  const memory = async (user: typeof a) =>
    t.admin.select().from(merchantCategories).where(eq(merchantCategories.userId, user.userId));

  test("confirming learns the merchant", async () => {
    const u = await t.signIn("learn@wambito.test");
    const comida = await mkCategory(u, "Comida");
    const first = await json(await capture({ merchant: "MERCADONA 12" }, { user: u }));
    const res = await patch(u, first.transaction.id, { categoryId: comida, needsReview: false });
    expect(res.status).toBe(200);
    expect(((await res.json()) as { needsReview: boolean }).needsReview).toBe(false);
    const next = await json(
      await capture({ merchant: "MERCADONA 77", ...at("2026-11-05T10:00:00Z") }, { user: u }),
    );
    expect(next.transaction.categoryId).toBe(comida);
    expect(next.category).toEqual({ name: "Comida", fallback: false });
  });

  test("renaming while confirming still teaches the notified merchant", async () => {
    const u = await t.signIn("rename@wambito.test");
    const market = await mkCategory(u, "Supermercado");
    const first = await json(await capture({ merchant: "LIDL 0042 LISBOA" }, { user: u }));
    const res = await patch(u, first.transaction.id, {
      name: "Lidl",
      categoryId: market,
      needsReview: false,
    });
    expect(res.status).toBe(200);
    expect(((await res.json()) as { name: string }).name).toBe("Lidl");
    const next = await json(
      await capture({ merchant: "LIDL 0042 LISBOA", ...at("2026-11-06T10:00:00Z") }, { user: u }),
    );
    expect(next.result).toBe("created");
    expect(next.transaction.categoryId).toBe(market);
  });

  test("a rename before the review still teaches the notified merchant", async () => {
    const u = await t.signIn("rename-review@wambito.test");
    const market = await mkCategory(u, "Supermercado");
    const first = await json(await capture({ merchant: "LIDL 0042 LISBOA" }, { user: u }));
    await patch(u, first.transaction.id, { name: "Lidl", categoryId: market });
    expect((await review(u, [first.transaction.id])).status).toBe(200);
    const [m] = await memory(u);
    expect(m?.categoryId).toBe(market);
    const next = await json(
      await capture({ merchant: "LIDL 0042 LISBOA", ...at("2026-11-06T10:00:00Z") }, { user: u }),
    );
    expect(next.transaction.categoryId).toBe(market);
  });

  test("a capture row without a notified key learns from its name", async () => {
    const u = await t.signIn("legacy-key@wambito.test");
    const market = await mkCategory(u, "Supermercado");
    const first = await json(await capture({ merchant: "Legacy Shop" }, { user: u }));
    await t.admin
      .update(transactions)
      .set({ captureMerchantKey: null })
      .where(eq(transactions.id, first.transaction.id));
    await patch(u, first.transaction.id, {
      name: "Renamed Shop",
      categoryId: market,
      needsReview: false,
    });
    const [m] = await memory(u);
    expect(m?.merchantKey).toBe("renamed shop");
  });

  test("review of a deleted capture answers 404 and changes nothing", async () => {
    const u = await t.signIn("review-deleted@wambito.test");
    const gone = await json(await capture({ amount: 51 }, { user: u }));
    await t.request("DELETE", `/v1/transactions/${gone.transaction.id}`, { headers: u.headers });
    const res = await review(u, [gone.transaction.id]);
    expect(res.status).toBe(404);
    const [row] = await t.admin
      .select()
      .from(transactions)
      .where(eq(transactions.id, gone.transaction.id));
    expect(row?.needsReview).toBe(true);
  });

  test("review of another account's capture alone answers 404", async () => {
    const u = await t.signIn("review-foreign@wambito.test");
    const theirs = await json(await capture({ amount: 52 }, { user: b }));
    expect((await review(u, [theirs.transaction.id])).status).toBe(404);
  });

  test("confirming a fallback learns nothing", async () => {
    const u = await t.signIn("fallback@wambito.test");
    const first = await json(await capture({}, { user: u }));
    await patch(u, first.transaction.id, { needsReview: false });
    expect(await memory(u)).toHaveLength(0);
  });

  test("editing without confirming learns nothing", async () => {
    const u = await t.signIn("edit@wambito.test");
    const comida = await mkCategory(u, "Comida");
    const first = await json(await capture({}, { user: u }));
    await patch(u, first.transaction.id, { categoryId: comida });
    expect(await memory(u)).toHaveLength(0);
  });

  test("a hand-typed transaction never teaches", async () => {
    const u = await t.signIn("hand@wambito.test");
    const comida = await mkCategory(u, "Comida");
    const made = await t.request("POST", "/v1/transactions", {
      headers: u.headers,
      body: { name: "Mercadona", amount: -500, categoryId: comida, date: "2026-11-04" },
    });
    const id = ((await made.json()) as { id: string }).id;
    const res = await patch(u, id, { needsReview: false });
    expect(res.status).toBe(200);
    expect(await memory(u)).toHaveLength(0);
  });

  test("confirming again does not re-learn", async () => {
    const u = await t.signIn("again@wambito.test");
    const comida = await mkCategory(u, "Comida");
    const ocio = await mkCategory(u, "Ocio");
    const first = await json(await capture({ merchant: "Again Shop" }, { user: u }));
    await patch(u, first.transaction.id, { categoryId: comida, needsReview: false });
    await patch(u, first.transaction.id, { categoryId: ocio, needsReview: false });
    const [m] = await memory(u);
    expect(m?.categoryId).toBe(comida);
  });

  test("a category of the other kind is not learned", async () => {
    const u = await t.signIn("kind@wambito.test");
    const salary = await mkCategory(u, "Salary", "income");
    const first = await json(await capture({ merchant: "Kind Shop" }, { user: u }));
    await patch(u, first.transaction.id, { categoryId: salary, needsReview: false });
    expect(await memory(u)).toHaveLength(0);
  });

  test("a merchant with nothing to remember is confirmed without error", async () => {
    const u = await t.signIn("symbols@wambito.test");
    const comida = await mkCategory(u, "Comida");
    const first = await json(await capture({ merchant: "***" }, { user: u }));
    const res = await patch(u, first.transaction.id, { categoryId: comida, needsReview: false });
    expect(res.status).toBe(200);
    expect(await memory(u)).toHaveLength(0);
  });

  test("review confirms several and learns each", async () => {
    const u = await t.signIn("bulk@wambito.test");
    const comida = await mkCategory(u, "Comida");
    const ocio = await mkCategory(u, "Ocio");
    const one = await json(await capture({ merchant: "Bulk One", amount: 100 }, { user: u }));
    const two = await json(await capture({ merchant: "Bulk Two", amount: 200 }, { user: u }));
    await patch(u, one.transaction.id, { categoryId: comida });
    await patch(u, two.transaction.id, { categoryId: ocio });
    const res = await review(u, [two.transaction.id, one.transaction.id]);
    expect(res.status).toBe(200);
    const out = (await res.json()) as { items: { id: string; needsReview: boolean }[] };
    expect(out.items.map((i) => i.id)).toEqual([two.transaction.id, one.transaction.id]);
    expect(out.items.every((i) => !i.needsReview)).toBe(true);
    const learned = Object.fromEntries((await memory(u)).map((m) => [m.merchantKey, m.categoryId]));
    expect(learned).toEqual({ "bulk one": comida, "bulk two": ocio });
  });

  test("review accepts ids that are already confirmed", async () => {
    const u = await t.signIn("done@wambito.test");
    const first = await json(await capture({}, { user: u }));
    await patch(u, first.transaction.id, { needsReview: false });
    const res = await review(u, [first.transaction.id]);
    expect(res.status).toBe(200);
  });

  test("review with an unknown or foreign id changes nothing", async () => {
    const u = await t.signIn("all-or-none@wambito.test");
    const mine = await json(await capture({ amount: 31 }, { user: u }));
    const theirs = await json(await capture({ amount: 32 }, { user: a }));
    for (const bad of [theirs.transaction.id, crypto.randomUUID()]) {
      const res = await review(u, [mine.transaction.id, bad]);
      expect(res.status).toBe(404);
      expect(res.headers.get("content-type")).toContain("problem+json");
    }
    const [row] = await t.admin
      .select()
      .from(transactions)
      .where(eq(transactions.id, mine.transaction.id));
    expect(row?.needsReview).toBe(true);
    const [other] = await t.admin
      .select()
      .from(transactions)
      .where(eq(transactions.id, theirs.transaction.id));
    expect(other?.needsReview).toBe(true);
  });

  test("lists only pending review", async () => {
    const u = await t.signIn("list@wambito.test");
    const pending = await json(await capture({ amount: 41 }, { user: u }));
    const done = await json(await capture({ amount: 42 }, { user: u }));
    await patch(u, done.transaction.id, { needsReview: false });
    const list = async (qs: string) =>
      (
        (await (
          await t.request("GET", `/v1/transactions?${qs}`, { headers: u.headers })
        ).json()) as { items: { id: string }[] }
      ).items.map((i) => i.id);
    expect(await list("needsReview=true")).toEqual([pending.transaction.id]);
    expect(await list("needsReview=false")).toEqual([done.transaction.id]);
    expect(await list("")).toHaveLength(2);
  });

  test("deleting a capture keeps the memory", async () => {
    const u = await t.signIn("keep@wambito.test");
    const comida = await mkCategory(u, "Comida");
    const first = await json(await capture({ merchant: "Keep Shop" }, { user: u }));
    await patch(u, first.transaction.id, { categoryId: comida, needsReview: false });
    await t.request("DELETE", `/v1/transactions/${first.transaction.id}`, { headers: u.headers });
    expect(await memory(u)).toHaveLength(1);
  });
});
