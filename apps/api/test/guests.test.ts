import { accounts, user } from "@wambito/db";
import { eq } from "@wambito/db/orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createTestApp, type TestApp } from "./harness.ts";

type Guest = { userId: string; headers: { authorization: string } };

/** Guest sign-up as the app does it: no body beyond `{}`, the device's zone and language in headers. */
async function signUpGuest(t: TestApp, headers: Record<string, string> = {}) {
  return t.request("POST", "/auth/sign-in/anonymous", { body: {}, headers });
}

async function guest(t: TestApp, headers: Record<string, string> = {}): Promise<Guest> {
  const res = await signUpGuest(t, headers);
  if (res.status !== 200)
    throw new Error(`guest sign-up failed: ${res.status} ${await res.text()}`);
  const token = res.headers.get("set-auth-token");
  const json = (await res.json()) as { user: { id: string } };
  return { userId: json.user.id, headers: { authorization: `Bearer ${token}` } };
}

async function me(t: TestApp, headers: { authorization: string }) {
  const res = await t.request("GET", "/v1/me", { headers });
  expect(res.status).toBe(200);
  return (await res.json()) as {
    id: string;
    isAnonymous: boolean;
    timezone: string;
    locale: string;
    currency: string;
  };
}

describe("guest sign-up, open (with an allowlist set)", () => {
  let t: TestApp;
  beforeAll(async () => {
    t = await createTestApp({ SIGN_IN_ALLOWLIST: ["founder@wambito.test"] });
  });
  afterAll(() => t?.stop());

  test("a guest signs up without an email, even with an allowlist set", async () => {
    const res = await signUpGuest(t);
    expect(res.status).toBe(200);
    const token = res.headers.get("set-auth-token");
    expect(token).toBeTruthy();
    const { user: created } = (await res.json()) as { user: { id: string } };
    const headers = { authorization: `Bearer ${token}` };

    const profile = await me(t, headers);
    expect(profile).toMatchObject({ id: created.id, isAnonymous: true });

    // The default account exists, and it is empty.
    const rows = await t.admin.select().from(accounts).where(eq(accounts.userId, created.id));
    expect(rows).toHaveLength(1);
    expect(rows[0]?.isDefault).toBe(true);
    const list = await t.request("GET", "/v1/transactions", { headers });
    expect(list.status).toBe(200);
    expect(((await list.json()) as { items: unknown[] }).items).toEqual([]);

    // No email was sent, and the placeholder address never resolves.
    expect(t.mailer.sent).toHaveLength(0);
    const [stored] = await t.admin.select().from(user).where(eq(user.id, created.id));
    expect(stored?.email).toMatch(/@guest\.wambito\.invalid$/);
  });

  test("an email user is not anonymous", async () => {
    const founder = await t.signIn("founder@wambito.test");
    expect((await me(t, founder.headers)).isAnonymous).toBe(false);
  });
});

describe("guest sign-up, turned off", () => {
  let t: TestApp;
  beforeAll(async () => {
    t = await createTestApp({ GUEST_SIGNUP: false });
  });
  afterAll(() => t?.stop());

  test("guest sign-up is refused when GUEST_SIGNUP is false", async () => {
    const res = await signUpGuest(t);
    expect(res.status).toBe(403);
    expect(await res.json()).toMatchObject({ code: "guest_signup_disabled" });
    expect(await t.admin.select().from(user)).toHaveLength(0);
  });

  test("email sign-in still works", async () => {
    const a = await t.signIn("a@wambito.test");
    expect((await me(t, a.headers)).isAnonymous).toBe(false);
  });
});

describe("guests", () => {
  let t: TestApp;
  beforeAll(async () => {
    t = await createTestApp();
  });
  afterAll(() => t?.stop());

  test("a guest's account currency follows the device", async () => {
    const cases: [timezone: string, currency: string][] = [
      ["America/Bogota", "COP"],
      ["Europe/Lisbon", "EUR"],
      ["America/New_York", "USD"],
    ];
    for (const [timezone, currency] of cases) {
      const g = await guest(t, { "x-wambito-timezone": timezone, "x-wambito-locale": "en" });
      expect(await me(t, g.headers)).toMatchObject({ timezone, locale: "en", currency });
    }
  });

  test("x-wambito-locale sets the locale; without it, Spanish", async () => {
    const es = await guest(t, { "x-wambito-timezone": "America/Bogota", "x-wambito-locale": "es" });
    expect((await me(t, es.headers)).locale).toBe("es");
    const none = await guest(t, { "x-wambito-timezone": "America/Bogota" });
    expect((await me(t, none.headers)).locale).toBe("es");
  });

  test("a region in x-wambito-locale counts, as on the web: es-CO in New York → COP", async () => {
    const g = await guest(t, {
      "x-wambito-timezone": "America/New_York",
      "x-wambito-locale": "es-CO",
    });
    expect(await me(t, g.headers)).toMatchObject({ locale: "es", currency: "COP" });
  });

  test("Italian and Portuguese guests get EUR, wherever their phone is", async () => {
    const cases: [
      locale: string,
      timezone: string,
      expected: { locale: string; currency: string },
    ][] = [
      ["it-IT", "Europe/Rome", { locale: "it", currency: "EUR" }],
      ["it", "America/New_York", { locale: "it", currency: "EUR" }],
      ["pt-PT", "Europe/Lisbon", { locale: "pt", currency: "EUR" }],
      ["pt", "America/New_York", { locale: "pt", currency: "EUR" }],
      // Brazil has no supported currency of its own: the region rule applies as before.
      ["pt-BR", "America/Sao_Paulo", { locale: "pt", currency: "USD" }],
      // Colombia still wins.
      ["it-IT", "America/Bogota", { locale: "it", currency: "COP" }],
    ];
    for (const [locale, timezone, expected] of cases) {
      const g = await guest(t, { "x-wambito-timezone": timezone, "x-wambito-locale": locale });
      expect(await me(t, g.headers)).toMatchObject(expected);
    }
  });

  test("the profile's language can be set to it or pt, and stays", async () => {
    const g = await guest(t, { "x-wambito-timezone": "Europe/Rome", "x-wambito-locale": "es" });
    for (const locale of ["it", "pt"]) {
      const res = await t.request("PATCH", "/v1/me", { headers: g.headers, body: { locale } });
      expect(res.status).toBe(200);
      expect((await me(t, g.headers)).locale).toBe(locale);
    }
    const bad = await t.request("PATCH", "/v1/me", { headers: g.headers, body: { locale: "fr" } });
    expect(bad.status).toBe(422);
  });

  test("a zone that isn't an IANA name is ignored: UTC, and USD", async () => {
    for (const timezone of ["+05:00", "Not/AZone", "Europe/Lisbon; drop table", ""]) {
      const g = await guest(t, { "x-wambito-timezone": timezone });
      expect(await me(t, g.headers)).toMatchObject({ timezone: "UTC", currency: "USD" });
    }
  });

  test("a zone is stored in its canonical spelling, and the currency follows it", async () => {
    const cases: [sent: string, stored: string, currency: string][] = [
      ["america/bogota", "America/Bogota", "COP"],
      ["EUROPE/LISBON", "Europe/Lisbon", "EUR"],
      ["US/Eastern", "America/New_York", "USD"],
    ];
    for (const [sent, timezone, currency] of cases) {
      const g = await guest(t, { "x-wambito-timezone": sent });
      expect(await me(t, g.headers)).toMatchObject({ timezone, currency });
    }
  });

  test("RLS: a guest never sees another guest's rows", async () => {
    const a = await guest(t, { "x-wambito-timezone": "America/Bogota" });
    const b = await guest(t, { "x-wambito-timezone": "America/Bogota" });
    const cat = await t.request("POST", "/v1/categories", {
      headers: a.headers,
      body: { name: "Mercado", kind: "expense", icon: "cart", color: "orange" },
    });
    expect(cat.status).toBe(201);
    const { id: categoryId } = (await cat.json()) as { id: string };
    const created = await t.request("POST", "/v1/transactions", {
      headers: a.headers,
      body: { categoryId, name: "Arroz", amount: -500000, date: "2026-10-02" },
    });
    expect(created.status).toBe(201);
    const { id: transactionId } = (await created.json()) as { id: string };

    const list = await t.request("GET", "/v1/transactions", { headers: b.headers });
    expect(((await list.json()) as { items: unknown[] }).items).toEqual([]);
    // B has only its own starter categories, never A's "Mercado".
    const cats = await t.request("GET", "/v1/categories", { headers: b.headers });
    const theirCats = (await cats.json()) as { id: string; name: string }[];
    expect(theirCats).toHaveLength(8);
    expect(theirCats.map((c) => c.id)).not.toContain(categoryId);
    const theirs = await t.request("PATCH", `/v1/transactions/${transactionId}`, {
      headers: b.headers,
      body: { name: "Mine now" },
    });
    expect(theirs.status).toBe(404);

    // A still sees its own.
    const own = await t.request("GET", "/v1/transactions", { headers: a.headers });
    expect(((await own.json()) as { items: unknown[] }).items).toHaveLength(1);
  });

  test("a guest who then signs in with an email keeps the guest account and its rows", async () => {
    const g = await guest(t, { "x-wambito-timezone": "America/Bogota" });
    const cat = await t.request("POST", "/v1/categories", {
      headers: g.headers,
      body: { name: "Mercado", kind: "expense", icon: "cart", color: "orange" },
    });
    expect(cat.status).toBe(201);

    // Signing in with the guest's session still attached must not delete the guest user.
    const sent = await t.request("POST", "/auth/email-otp/send-verification-otp", {
      headers: g.headers,
      body: { email: "owner@wambito.test", type: "sign-in" },
    });
    expect(sent.status).toBe(200);
    const mail = t.mailer.lastTo("owner@wambito.test");
    const code = /(\d{6})$/.exec(mail?.subject ?? "")?.[1];
    const signedIn = await t.request("POST", "/auth/sign-in/email-otp", {
      headers: g.headers,
      body: { email: "owner@wambito.test", otp: code },
    });
    expect(signedIn.status).toBe(200);
    // The email user is a second user, not the guest.
    const { user: emailUser } = (await signedIn.json()) as { user: { id: string } };
    expect(emailUser.id).not.toBe(g.userId);

    const [still] = await t.admin.select().from(user).where(eq(user.id, g.userId));
    expect(still).toBeDefined();
    expect((await me(t, g.headers)).isAnonymous).toBe(true);
    // The guest's rows survive: its default account and its category.
    const guestAccounts = await t.admin
      .select()
      .from(accounts)
      .where(eq(accounts.userId, g.userId));
    expect(guestAccounts).toHaveLength(1);
    const cats = await t.request("GET", "/v1/categories", { headers: g.headers });
    expect(((await cats.json()) as { name: string }[]).map((c) => c.name)).toContain("Mercado");
  });

  test("a placeholder address can't ask for a sign-in code", async () => {
    const g = await guest(t);
    const [stored] = await t.admin.select().from(user).where(eq(user.id, g.userId));
    const sentBefore = t.mailer.sent.length;
    const res = await t.request("POST", "/auth/email-otp/send-verification-otp", {
      body: { email: stored?.email, type: "sign-in" },
    });
    expect(res.status).toBe(403);
    expect(await res.json()).toMatchObject({ code: "sign_in_not_allowed" });
    expect(t.mailer.sent).toHaveLength(sentBefore);
  });
});

describe("encrypted guests (NEW_USERS_ENCRYPTED on)", () => {
  let t: TestApp;
  beforeAll(async () => {
    t = await createTestApp({ NEW_USERS_ENCRYPTED: true });
  });
  afterAll(() => t?.stop());

  test("an encrypted guest that signs in with an existing email keeps its own user", async () => {
    const existing = await t.signIn("existing@wambito.test");
    const g = await guest(t, { "x-wambito-client": "android" });

    // Better Auth's anonymous plugin would delete the guest here (disableDeleteAnonymousUser).
    const sent = await t.request("POST", "/auth/email-otp/send-verification-otp", {
      headers: g.headers,
      body: { email: "existing@wambito.test", type: "sign-in" },
    });
    expect(sent.status).toBe(200);
    const code = /(\d{6})$/.exec(t.mailer.lastTo("existing@wambito.test")?.subject ?? "")?.[1];
    const signedIn = await t.request("POST", "/auth/sign-in/email-otp", {
      headers: g.headers,
      body: { email: "existing@wambito.test", otp: code },
    });
    expect(signedIn.status).toBe(200);
    expect(((await signedIn.json()) as { user: { id: string } }).user.id).toBe(existing.userId);

    const [still] = await t.admin.select().from(user).where(eq(user.id, g.userId));
    expect(still).toMatchObject({ isAnonymous: true, encryption: "encrypted" });
  });
});

describe("app sign-ups by email (x-wambito-timezone on the creating request)", () => {
  let t: TestApp;
  beforeAll(async () => {
    t = await createTestApp();
  });
  afterAll(() => t?.stop());

  /** Email sign-up as the app does it: both steps carry the device's zone and language. */
  async function signUpByEmail(email: string, headers: Record<string, string>) {
    const sent = await t.request("POST", "/auth/email-otp/send-verification-otp", {
      headers,
      body: { email, type: "sign-in" },
    });
    expect(sent.status).toBe(200);
    const code = /(\d{6})$/.exec(t.mailer.lastTo(email)?.subject ?? "")?.[1];
    const res = await t.request("POST", "/auth/sign-in/email-otp", {
      headers,
      body: { email, otp: code },
    });
    expect(res.status).toBe(200);
    return { authorization: `Bearer ${res.headers.get("set-auth-token")}` };
  }

  test("a new email user from the app gets the device's zone, language and currency", async () => {
    const headers = await signUpByEmail("bogota@wambito.test", {
      "x-wambito-timezone": "America/Bogota",
      "x-wambito-locale": "en-US",
    });
    expect(await me(t, headers)).toMatchObject({
      isAnonymous: false,
      timezone: "America/Bogota",
      locale: "en",
      currency: "COP",
    });
  });

  async function categoryNames(headers: { authorization: string }) {
    const res = await t.request("GET", "/v1/categories", { headers });
    expect(res.status).toBe(200);
    const rows = (await res.json()) as { name: string; kind: string; icon: string }[];
    return rows.map((c) => c.name);
  }

  test("a new account starts with the eight suggested categories, in the sign-up's language", async () => {
    const web = await signUpByEmail("starter-it@wambito.test", { "x-wambito-locale": "it" });
    expect(await categoryNames(web)).toEqual([
      "Supermercato",
      "Ristorante",
      "Casa",
      "Trasporti",
      "Tempo libero",
      "Abbonamenti",
      "Salute",
      "Stipendio",
    ]);
    const phone = await guest(t, {
      "x-wambito-timezone": "Europe/Lisbon",
      "x-wambito-locale": "pt-PT",
    });
    expect(await categoryNames(phone.headers)).toEqual([
      "Supermercado",
      "Restaurante",
      "Casa",
      "Transportes",
      "Lazer",
      "Subscrições",
      "Saúde",
      "Salário",
    ]);
  });

  test("without a hint the browser's language names them, else Spanish", async () => {
    const browser = await signUpByEmail("starter-en@wambito.test", {
      "accept-language": "en-GB,en;q=0.9",
    });
    expect((await categoryNames(browser))[0]).toBe("Groceries");
    const none = await signUpByEmail("starter-es@wambito.test", {});
    expect((await categoryNames(none))[0]).toBe("Supermercado");
  });

  test("signing in again, or claiming an email as a guest, adds none", async () => {
    await signUpByEmail("again@wambito.test", {});
    const again = await signUpByEmail("again@wambito.test", {});
    expect(await categoryNames(again)).toHaveLength(8);
    const g = await guest(t, { "x-wambito-timezone": "America/Bogota" });
    const claimed = await t.request("POST", "/auth/email-otp/send-verification-otp", {
      headers: g.headers,
      body: { email: "claimer@wambito.test", type: "sign-in" },
    });
    expect(claimed.status).toBe(200);
    expect(await categoryNames(g.headers)).toHaveLength(8);
  });

  test("a new email user from the web (no x-wambito-timezone) keeps UTC, Spanish and EUR", async () => {
    const headers = await signUpByEmail("web@wambito.test", { "x-wambito-locale": "en" });
    expect(await me(t, headers)).toMatchObject({
      isAnonymous: false,
      timezone: "UTC",
      locale: "es",
      currency: "EUR",
    });
  });
});
