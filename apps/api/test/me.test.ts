import { readFileSync } from "node:fs";
import { sql } from "@wambito/db/orm";
import { afterAll, beforeAll, expect, test } from "vitest";
import { createTestApp, type TestApp } from "./harness.ts";

let t: TestApp;
let a: { userId: string; headers: { authorization: string } };
let b: { userId: string; headers: { authorization: string } };

async function seed(headers: { authorization: string }, name: string) {
  const res = await t.request("POST", "/v1/categories", {
    headers,
    body: { name, kind: "expense", icon: "cart", color: "orange" },
  });
  const { id } = (await res.json()) as { id: string };
  await t.request("POST", "/v1/transactions", {
    headers,
    body: { categoryId: id, name: `${name} purchase`, amount: -3070, date: "2026-10-02" },
  });
}

beforeAll(async () => {
  t = await createTestApp();
  a = await t.signIn("a@wambito.test");
  b = await t.signIn("b@wambito.test");
  await seed(a.headers, "Supermercado");
  await seed(b.headers, "Other");
});
afterAll(() => t?.stop());

test("profile can be read and updated", async () => {
  const res = await t.request("PATCH", "/v1/me", {
    headers: a.headers,
    body: { timezone: "America/Bogota", locale: "en" },
  });
  expect(res.status).toBe(200);
  const me = await (await t.request("GET", "/v1/me", { headers: a.headers })).json();
  expect(me).toEqual({
    id: a.userId,
    email: "a@wambito.test",
    timezone: "America/Bogota",
    locale: "en",
    // `a` has a movement (seeded above): reading the profile stamped the welcome as done.
    onboardingCompletedAt: expect.any(String),
    currency: "EUR",
    isAnonymous: false,
    encryption: "plain",
  });
});

type Me = { onboardingCompletedAt: string | null };
const readMe = async (headers: { authorization: string }) =>
  (await (await t.request("GET", "/v1/me", { headers })).json()) as Me;

test("an account that already has a movement is stamped as onboarded when its profile is read", async () => {
  // An account that predates the welcome (the app's, made before it existed): it has data, and
  // no `onboardingCompletedAt`. Reading it stamps it, so neither client sends it to the welcome.
  const old = await t.signIn("old@wambito.test");
  await seed(old.headers, "Casa");
  const before = Date.now();
  const me = await readMe(old.headers);
  expect(me.onboardingCompletedAt).not.toBeNull();
  expect(Date.parse(me.onboardingCompletedAt as string)).toBeGreaterThanOrEqual(before - 1000);
  // Once: later reads keep the first time.
  expect((await readMe(old.headers)).onboardingCompletedAt).toBe(me.onboardingCompletedAt);
});

test("an empty account is not stamped: it is the one the welcome is for", async () => {
  const fresh = await t.signIn("fresh@wambito.test");
  expect((await readMe(fresh.headers)).onboardingCompletedAt).toBeNull();
  // Categories alone are not movements.
  await t.request("POST", "/v1/categories", {
    headers: fresh.headers,
    body: { name: "Solo categoría", kind: "expense", icon: "cart", color: "orange" },
  });
  expect((await readMe(fresh.headers)).onboardingCompletedAt).toBeNull();
});

test("an account that is already stamped is left as it is", async () => {
  const done = await t.signIn("done@wambito.test");
  const patched = (await (
    await t.request("PATCH", "/v1/me", {
      headers: done.headers,
      body: { onboardingCompleted: true },
    })
  ).json()) as Me;
  await seed(done.headers, "Después");
  expect((await readMe(done.headers)).onboardingCompletedAt).toBe(patched.onboardingCompletedAt);
});

const BUDGE_CSV = readFileSync(
  new URL("../../../packages/importers/test/fixtures/budge-sample.csv", import.meta.url),
  "utf8",
);

/** What the welcome's import step does: upload a Budge export and confirm it. */
async function importInWelcome(headers: { authorization: string }) {
  const form = new FormData();
  form.append("source", "budge");
  form.append("file", new File([BUDGE_CSV], "budge.csv", { type: "text/csv" }));
  const preview = await t.request("POST", "/v1/imports", { headers, body: form });
  expect(preview.status).toBeLessThan(300);
  const { id } = (await preview.json()) as { id: string };
  const confirm = await t.request("POST", `/v1/imports/${id}/confirm`, { headers });
  expect(confirm.status).toBe(200);
}

test("an account that imports during its welcome is not stamped; a manual movement stamps it", async () => {
  // The welcome's import step comes before categories and budgets: the account has rows by then,
  // but it is still in its welcome, and a restart must resume it.
  const welcoming = await t.signIn("welcoming@wambito.test");
  await importInWelcome(welcoming.headers);
  expect((await readMe(welcoming.headers)).onboardingCompletedAt).toBeNull();
  // A PATCH answers with the same profile: it does not stamp either.
  const patched = await t.request("PATCH", "/v1/me", {
    headers: welcoming.headers,
    body: { timezone: "America/Bogota" },
  });
  expect(((await patched.json()) as Me).onboardingCompletedAt).toBeNull();
  // A movement the welcome cannot have made (by hand, or captured) does.
  await seed(welcoming.headers, "Mascotas");
  expect((await readMe(welcoming.headers)).onboardingCompletedAt).not.toBeNull();
});

test("a movement of another account does not stamp this one", async () => {
  const other = await t.signIn("other@wambito.test");
  expect((await readMe(other.headers)).onboardingCompletedAt).toBeNull();
});

test("the currency can be chosen while the account has no transactions", async () => {
  const c = await t.signIn("c@wambito.test");
  const res = await t.request("PATCH", "/v1/me", { headers: c.headers, body: { currency: "COP" } });
  expect(res.status).toBe(200);
  expect(((await res.json()) as { currency: string }).currency).toBe("COP");
  const me = (await (await t.request("GET", "/v1/me", { headers: c.headers })).json()) as {
    currency: string;
  };
  expect(me.currency).toBe("COP");

  // The account's currency is what new transactions are stored in.
  const cat = (await (
    await t.request("POST", "/v1/categories", {
      headers: c.headers,
      body: { name: "Comida", kind: "expense", icon: "cart", color: "orange" },
    })
  ).json()) as { id: string };
  const created = await t.request("POST", "/v1/transactions", {
    headers: c.headers,
    body: { categoryId: cat.id, name: "Almuerzo", amount: -5000000, date: "2026-10-02" },
  });
  expect(((await created.json()) as { currency: string }).currency).toBe("COP");
});

test("the currency is locked once the account has transactions", async () => {
  const before = (await (await t.request("GET", "/v1/me", { headers: a.headers })).json()) as {
    timezone: string;
  };
  const res = await t.request("PATCH", "/v1/me", {
    headers: a.headers,
    body: { currency: "COP", timezone: "Europe/Madrid" },
  });
  expect(res.status).toBe(409);
  expect(((await res.json()) as { code: string }).code).toBe("currency_locked");
  const me = (await (await t.request("GET", "/v1/me", { headers: a.headers })).json()) as {
    currency: string;
  };
  expect(me.currency).toBe("EUR");

  // The rejected request changed nothing else either.
  const after = (await (await t.request("GET", "/v1/me", { headers: a.headers })).json()) as {
    timezone: string;
  };
  expect(after.timezone).toBe(before.timezone);

  // Setting the value it already has is not a change.
  const same = await t.request("PATCH", "/v1/me", {
    headers: a.headers,
    body: { currency: "EUR" },
  });
  expect(same.status).toBe(200);
});

test("a soft-deleted transaction still locks the currency", async () => {
  const d = await t.signIn("d@wambito.test");
  const cat = (await (
    await t.request("POST", "/v1/categories", {
      headers: d.headers,
      body: { name: "Comida", kind: "expense", icon: "cart", color: "orange" },
    })
  ).json()) as { id: string };
  const tx = (await (
    await t.request("POST", "/v1/transactions", {
      headers: d.headers,
      body: { categoryId: cat.id, name: "Almuerzo", amount: -1000, date: "2026-10-02" },
    })
  ).json()) as { id: string };
  await t.request("DELETE", `/v1/transactions/${tx.id}`, { headers: d.headers });
  const res = await t.request("PATCH", "/v1/me", { headers: d.headers, body: { currency: "USD" } });
  expect(res.status).toBe(409);
});

test("a recurrence locks the currency, even before any transaction", async () => {
  // A recurrence would later materialize its old-currency amount in the new currency.
  const r = await t.signIn("recurrence-lock@wambito.test");
  const cat = (await (
    await t.request("POST", "/v1/categories", {
      headers: r.headers,
      body: { name: "Arriendo", kind: "expense", icon: "🏠", color: "#8b5cff" },
    })
  ).json()) as { id: string };
  const created = await t.request("POST", "/v1/recurrences", {
    headers: r.headers,
    body: {
      name: "Arriendo",
      amount: -150_000_000,
      categoryId: cat.id,
      frequency: "monthly",
      dayOfMonth: 5,
      startDate: "2099-01-01",
    },
  });
  expect(created.status).toBe(201);
  const res = await t.request("PATCH", "/v1/me", { headers: r.headers, body: { currency: "COP" } });
  expect(res.status).toBe(409);
  expect(((await res.json()) as { code: string }).code).toBe("currency_locked");
  const me = (await (await t.request("GET", "/v1/me", { headers: r.headers })).json()) as {
    currency: string;
  };
  expect(me.currency).toBe("EUR");

  // Once the recurrence is gone (and nothing was materialized), the currency is free again.
  const { id } = (await created.json()) as { id: string };
  await t.request("DELETE", `/v1/recurrences/${id}`, { headers: r.headers });
  const freed = await t.request("PATCH", "/v1/me", {
    headers: r.headers,
    body: { currency: "COP" },
  });
  expect(freed.status).toBe(200);
});

test("unsupported currencies are rejected", async () => {
  const e = await t.signIn("e@wambito.test");
  // COP, USD and EUR only at launch (spec §2.4): the other Latin American currencies wait.
  for (const currency of ["JPY", "MXN", "ARS", "CLP", "PEN", "cop", "", 5]) {
    const res = await t.request("PATCH", "/v1/me", { headers: e.headers, body: { currency } });
    expect(res.status, String(currency)).toBe(422);
  }
});

test("onboarding completion is recorded once", async () => {
  const first = await t.request("PATCH", "/v1/me", {
    headers: b.headers,
    body: { onboardingCompleted: true },
  });
  expect(first.status).toBe(200);
  const { onboardingCompletedAt } = (await first.json()) as { onboardingCompletedAt: string };
  expect(new Date(onboardingCompletedAt).toISOString()).toBe(onboardingCompletedAt);

  const second = await t.request("PATCH", "/v1/me", {
    headers: b.headers,
    body: { onboardingCompleted: true },
  });
  expect(((await second.json()) as { onboardingCompletedAt: string }).onboardingCompletedAt).toBe(
    onboardingCompletedAt,
  );
});

test("onboarding cannot be un-completed", async () => {
  const res = await t.request("PATCH", "/v1/me", {
    headers: a.headers,
    body: { onboardingCompleted: false },
  });
  expect(res.status).toBe(422);
  expect(((await res.json()) as { code?: string; type?: string }).code).toBe("validation_failed");
});

test("invalid time zones are rejected", async () => {
  const res = await t.request("PATCH", "/v1/me", {
    headers: a.headers,
    body: { timezone: "Mars/Base" },
  });
  expect(res.status).toBe(422);
});

test("JSON export contains only the user's data", async () => {
  const res = await t.request("GET", "/v1/me/export", { headers: a.headers });
  expect(res.status).toBe(200);
  expect(res.headers.get("content-disposition")).toMatch(
    /^attachment; filename="wambito-export-\d{4}-\d{2}-\d{2}\.json"$/,
  );
  const data = (await res.json()) as {
    user: { email: string };
    categories: { name: string }[];
    transactions: { name: string }[];
  };
  expect(data.user.email).toBe("a@wambito.test");
  expect(data.categories.map((c) => c.name)).toEqual(["Supermercado"]);
  expect(data.transactions.map((x) => x.name)).toEqual(["Supermercado purchase"]);
});

test("CSV export uses decimal amounts", async () => {
  const res = await t.request("GET", "/v1/me/export?format=csv", { headers: a.headers });
  expect(res.headers.get("content-type")).toContain("text/csv");
  const [head, row] = (await res.text()).trim().split("\n");
  expect(head).toBe("date,name,amount,currency,category,status,note");
  expect(row).toBe("2026-10-02,Supermercado purchase,-30.70,EUR,Supermercado,paid,");
});

test("deleting the account removes everything and ends the session", async () => {
  const res = await t.request("DELETE", "/v1/me", { headers: a.headers });
  expect(res.status).toBe(204);
  expect((await t.request("GET", "/v1/me", { headers: a.headers })).status).toBe(401);
  const tables = [
    "accounts",
    "categories",
    "category_budgets",
    "recurrences",
    "imports",
    "transactions",
    "idempotency_keys",
    "session",
  ];
  for (const table of tables) {
    const rows = await t.admin.execute(
      sql.raw(`select count(*)::int as n from "${table}" where user_id = '${a.userId}'`),
    );
    expect([table, (rows[0] as { n: number }).n]).toEqual([table, 0]);
  }
  const theirs = (await (
    await t.request("GET", "/v1/transactions", { headers: b.headers })
  ).json()) as { items: unknown[] };
  expect(theirs.items).toHaveLength(1);
});
