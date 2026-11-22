import { randomUUID } from "node:crypto";
import { accounts, categories, user } from "@wambito/db";
import { eq } from "@wambito/db/orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { codeFrom, createTestApp, type TestApp } from "./harness.ts";

// The switch (spec 2026-11-15, section 11): with NEW_USERS_ENCRYPTED on, a user born from now on is
// `encrypted`; users born before, or with it off, are `plain`.

type Auth = { userId: string; headers: { authorization: string } };

async function guest(t: TestApp, headers: Record<string, string> = {}): Promise<Auth> {
  const res = await t.request("POST", "/auth/sign-in/anonymous", { body: {}, headers });
  if (res.status !== 200) throw new Error(`guest failed: ${res.status} ${await res.text()}`);
  const json = (await res.json()) as { user: { id: string } };
  return {
    userId: json.user.id,
    headers: { authorization: `Bearer ${res.headers.get("set-auth-token")}` },
  };
}

/** The email-code sign-in with extra headers (a new email makes a new user). */
async function emailUser(
  t: TestApp,
  email: string,
  headers: Record<string, string> = {},
): Promise<Auth> {
  await t.request("POST", "/auth/email-otp/send-verification-otp", {
    body: { email, type: "sign-in" },
    headers,
  });
  const mail = t.mailer.lastTo(email);
  if (!mail) throw new Error("no sign-in mail");
  const res = await t.request("POST", "/auth/sign-in/email-otp", {
    body: { email, otp: codeFrom(mail.subject) },
    headers,
  });
  if (res.status !== 200) throw new Error(`sign-in failed: ${res.status} ${await res.text()}`);
  const json = (await res.json()) as { user: { id: string } };
  return {
    userId: json.user.id,
    headers: { authorization: `Bearer ${res.headers.get("set-auth-token")}` },
  };
}

const meOf = async (t: TestApp, headers: { authorization: string }) =>
  (await (await t.request("GET", "/v1/me", { headers })).json()) as { encryption: string };

const stored = async (t: TestApp, id: string) =>
  (await t.admin.select().from(user).where(eq(user.id, id)))[0];

const rowsOf = async (t: TestApp, id: string) => ({
  accounts: await t.admin.select().from(accounts).where(eq(accounts.userId, id)),
  categories: await t.admin.select().from(categories).where(eq(categories.userId, id)),
});

describe("flag off", () => {
  let t: TestApp;
  beforeAll(async () => {
    t = await createTestApp({});
  });
  afterAll(() => t?.stop());

  test("flag off: a new guest and a new email user are plain, /v1/me says plain, and get the default account and categories", async () => {
    const g = await guest(t);
    const e = await emailUser(t, "off@wambito.test");
    for (const who of [g, e]) {
      expect((await stored(t, who.userId))?.encryption).toBe("plain");
      expect((await meOf(t, who.headers)).encryption).toBe("plain");
      const rows = await rowsOf(t, who.userId);
      expect(rows.accounts).toHaveLength(1);
      expect(rows.categories.length).toBeGreaterThan(0);
    }
  });

  test("platform: x-wambito-client android → android, ios → ios, none or other → web", async () => {
    const cases: [Record<string, string>, string][] = [
      [{ "x-wambito-client": "android" }, "android"],
      [{ "x-wambito-client": "ios" }, "ios"],
      [{ "x-wambito-client": " IOS " }, "ios"],
      [{}, "web"],
      [{ "x-wambito-client": "windows" }, "web"],
    ];
    for (const [headers, platform] of cases) {
      const g = await guest(t, headers);
      expect((await stored(t, g.userId))?.platform, JSON.stringify(headers)).toBe(platform);
    }
    const e = await emailUser(t, "ios-email@wambito.test", { "x-wambito-client": "ios" });
    expect((await stored(t, e.userId))?.platform).toBe("ios");
  });
});

describe("flag on", () => {
  let t: TestApp;
  beforeAll(async () => {
    t = await createTestApp({ NEW_USERS_ENCRYPTED: true });
  });
  afterAll(() => t?.stop());

  test("flag on: a new guest is encrypted, /v1/me says preview, and has no accounts or categories rows", async () => {
    const g = await guest(t);
    expect((await stored(t, g.userId))?.encryption).toBe("encrypted");
    expect((await meOf(t, g.headers)).encryption).toBe("preview");
    const rows = await rowsOf(t, g.userId);
    expect(rows.accounts).toHaveLength(0);
    expect(rows.categories).toHaveLength(0);
  });

  test("flag on: a new email user is encrypted and its /v1 finance routes answer 426 update_required", async () => {
    const e = await emailUser(t, "on@wambito.test");
    expect((await stored(t, e.userId))?.encryption).toBe("encrypted");
    const res = await t.request("GET", "/v1/transactions", { headers: e.headers });
    expect(res.status).toBe(426);
    expect(((await res.json()) as { code?: string; type?: string }).code).toBe("update_required");
  });

  test("flag on: a user created before the flag stays plain", async () => {
    const id = randomUUID();
    await t.admin.insert(user).values({
      id,
      name: "Old",
      email: "old@wambito.test",
      emailVerified: true,
    });
    await t.admin
      .insert(accounts)
      .values({ userId: id, name: "Main", currency: "EUR", isDefault: true });
    const signed = await emailUser(t, "old@wambito.test");
    expect(signed.userId).toBe(id);
    expect((await meOf(t, signed.headers)).encryption).toBe("plain");
  });
});
