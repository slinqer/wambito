import { accounts, categories } from "@wambito/db";
import { eq } from "@wambito/db/orm";
import { afterAll, beforeAll, expect, test } from "vitest";
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
