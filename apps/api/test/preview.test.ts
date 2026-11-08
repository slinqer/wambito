import { accounts, categories } from "@wambito/db";
import { eq } from "@wambito/db/orm";
import { afterAll, afterEach, beforeAll, describe, expect, test } from "vitest";
import { createTestApp, type TestApp } from "./harness.ts";

// The end-to-end encryption preview (stage 2a): `GET /v1/me` says which accounts keep their
// finances only as encrypted records (`E2E_PREVIEW_USER_IDS`), and sign-up seeds no finance rows
// for them (the web creates the settings and the suggested categories as records).

let t: TestApp;

beforeAll(async () => {
  t = await createTestApp({ E2E_PREVIEW_USER_IDS: ["listed-user"] });
});
afterAll(() => t?.stop());

const encryptionOf = async (headers: { authorization: string }) =>
  ((await (await t.request("GET", "/v1/me", { headers })).json()) as { encryption: string })
    .encryption;

test("an account not listed is plain", async () => {
  const plain = await t.signIn("plain@wambito.test");
  expect(await encryptionOf(plain.headers)).toBe("plain");
});

test("an account listed in E2E_PREVIEW_USER_IDS is preview", async () => {
  const someone = await t.signIn("listed@wambito.test");
  t.config.E2E_PREVIEW_USER_IDS = [someone.userId];
  try {
    expect(await encryptionOf(someone.headers)).toBe("preview");
  } finally {
    t.config.E2E_PREVIEW_USER_IDS = ["listed-user"];
  }
});

test("a plain sign-up gets its default account and the suggested categories", async () => {
  const plain = await t.signIn("seeded@wambito.test", { starterCategories: true });
  expect(
    await t.admin.select().from(accounts).where(eq(accounts.userId, plain.userId)),
  ).toHaveLength(1);
  expect(
    (await t.admin.select().from(categories).where(eq(categories.userId, plain.userId))).length,
  ).toBeGreaterThan(0);
});

test("a preview sign-up gets no finance rows", async () => {
  // The id is made during sign-up, so the list is armed to match whoever signs up next.
  const anyone = Object.assign([] as string[], { includes: () => true });
  t.config.E2E_PREVIEW_USER_IDS = anyone;
  let userId: string;
  try {
    ({ userId } = await t.signIn("fresh-preview@wambito.test", { starterCategories: true }));
  } finally {
    t.config.E2E_PREVIEW_USER_IDS = ["listed-user"];
  }
  expect(await t.admin.select().from(accounts).where(eq(accounts.userId, userId))).toEqual([]);
  expect(await t.admin.select().from(categories).where(eq(categories.userId, userId))).toEqual([]);
});

test("a preview account's profile still reads without a default account", async () => {
  const anyone = Object.assign([] as string[], { includes: () => true });
  t.config.E2E_PREVIEW_USER_IDS = anyone;
  try {
    const { headers } = await t.signIn("empty-preview@wambito.test");
    const res = await t.request("GET", "/v1/me", { headers });
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ encryption: "preview", currency: "EUR" });
  } finally {
    t.config.E2E_PREVIEW_USER_IDS = ["listed-user"];
  }
});

// A preview account uses /v2 only: every /v1 finance route answers 403 `encrypted_account`, for
// its sessions and for an assistant's token alike. The account itself (profile, assistants list,
// deletion) stays on /v1.
const FINANCE_ROUTES: [string, string][] = [
  ["GET", "/v1/transactions"],
  ["POST", "/v1/transactions"],
  ["GET", "/v1/transactions/suggestions"],
  ["POST", "/v1/transactions/batch"],
  ["POST", "/v1/transactions/batch-delete"],
  ["POST", "/v1/transactions/review"],
  ["PATCH", "/v1/transactions/0193a000-0000-7000-8000-000000000001"],
  ["DELETE", "/v1/transactions/0193a000-0000-7000-8000-000000000001"],
  ["POST", "/v1/transactions/0193a000-0000-7000-8000-000000000001/restore"],
  ["GET", "/v1/categories"],
  ["POST", "/v1/categories"],
  ["PATCH", "/v1/categories/0193a000-0000-7000-8000-000000000001"],
  ["PUT", "/v1/categories/0193a000-0000-7000-8000-000000000001/budget"],
  ["GET", "/v1/recurrences"],
  ["POST", "/v1/recurrences"],
  ["PATCH", "/v1/recurrences/0193a000-0000-7000-8000-000000000001"],
  ["DELETE", "/v1/recurrences/0193a000-0000-7000-8000-000000000001"],
  ["GET", "/v1/summary"],
  ["GET", "/v1/reports/by-category"],
  ["GET", "/v1/reports/trend"],
  ["GET", "/v1/reports/cost-of-living"],
  ["POST", "/v1/captures"],
  ["POST", "/v1/imports"],
  ["POST", "/v1/imports/0193a000-0000-7000-8000-000000000001/confirm"],
  ["DELETE", "/v1/imports/0193a000-0000-7000-8000-000000000001"],
  ["GET", "/v1/me/export"],
];

async function previewPerson(email: string) {
  const person = await t.signIn(email);
  t.config.E2E_PREVIEW_USER_IDS = ["listed-user", person.userId];
  return person;
}

describe("a preview account's /v1", () => {
  afterEach(() => {
    t.config.E2E_PREVIEW_USER_IDS = ["listed-user"];
  });

  let finance: { headers: { authorization: string }; userId: string } | undefined;
  test.each(FINANCE_ROUTES)("%s %s is 403 encrypted_account", async (method, path) => {
    finance ??= await t.signIn("v1-finance@wambito.test");
    t.config.E2E_PREVIEW_USER_IDS = ["listed-user", finance.userId];
    const { headers } = finance;
    const res = await t.request(method, path, { headers, body: method === "GET" ? undefined : {} });
    expect(res.status).toBe(403);
    expect(await res.json()).toMatchObject({ code: "encrypted_account" });
  });

  test("the account routes stay: profile, its locale, the assistants list, /v2", async () => {
    const { headers } = await previewPerson("v1-account@wambito.test");
    expect((await t.request("GET", "/v1/me", { headers })).status).toBe(200);
    const patched = await t.request("PATCH", "/v1/me", {
      headers,
      body: { locale: "en", onboardingCompleted: true },
    });
    expect(patched.status).toBe(200);
    expect((await t.request("GET", "/v1/me/assistants", { headers })).status).toBe(200);
    expect((await t.request("GET", "/v2/sync?since=0", { headers })).status).toBe(200);
    expect((await t.request("GET", "/v2/keys", { headers })).status).toBe(200);
  });

  test("PATCH /v1/me with a currency is 403: the currency lives in the records", async () => {
    const { headers } = await previewPerson("v1-currency@wambito.test");
    const res = await t.request("PATCH", "/v1/me", { headers, body: { currency: "COP" } });
    expect(res.status).toBe(403);
    expect(await res.json()).toMatchObject({ code: "encrypted_account" });
  });

  test("DELETE /v1/me still deletes the account", async () => {
    const { headers } = await previewPerson("v1-delete@wambito.test");
    expect((await t.request("DELETE", "/v1/me", { headers })).status).toBe(204);
  });

  test("an assistant's token is refused too", async () => {
    const person = await t.signIn("v1-assistant@wambito.test");
    const { accessToken } = await t.authorize("v1-assistant@wambito.test", {
      headers: person.headers,
    });
    t.config.E2E_PREVIEW_USER_IDS = ["listed-user", person.userId];
    const res = await t.request("GET", "/v1/transactions", {
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(res.status).toBe(403);
    expect(await res.json()).toMatchObject({ code: "encrypted_account" });
  });

  test("a plain account's finance routes still answer", async () => {
    const { headers } = await t.signIn("v1-plain@wambito.test");
    expect((await t.request("GET", "/v1/transactions", { headers })).status).toBe(200);
  });
});
