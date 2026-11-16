import { accounts, verification, withUser } from "@wambito/db";
import { eq, like } from "@wambito/db/orm";
import { afterAll, afterEach, beforeAll, describe, expect, test, vi } from "vitest";
import { CODE_TTL_SECONDS, guestDefaults } from "../src/auth.ts";
import { codeFrom, createTestApp, type TestApp } from "./harness.ts";

let t: TestApp;
beforeAll(async () => {
  t = await createTestApp();
});
afterAll(() => t?.stop());
afterEach(() => {
  vi.useRealTimers();
});

const sendCode = (email: string, headers: Record<string, string> = {}) =>
  t.request("POST", "/auth/email-otp/send-verification-otp", {
    body: { email, type: "sign-in" },
    headers,
  });
const signInWith = (email: string, otp: string) =>
  t.request("POST", "/auth/sign-in/email-otp", { body: { email, otp } });

describe("email code + magic link", () => {
  test("one email carries the code and a magic link with the same code", async () => {
    expect((await sendCode("a@wambito.test")).status).toBe(200);
    const mail = t.mailer.lastTo("a@wambito.test");
    expect(mail).toBeDefined();
    const code = codeFrom(mail?.subject ?? "");
    expect(mail?.text).toContain(
      `http://localhost:5173/auth/verify?email=a%40wambito.test&code=${code}`,
    );
    expect(mail?.subject).toBe(`Tu código de Wambito: ${code}`);
  });

  test("the email names the product Wambito, in the text and in the html", async () => {
    await sendCode("name@wambito.test");
    const mail = t.mailer.lastTo("name@wambito.test");
    expect(mail?.text).toContain("¡Hola! Este es tu código para entrar");
    expect(mail?.html).toContain("¡Hola! Este es tu código para entrar");
    expect(`${mail?.subject}\n${mail?.text}\n${mail?.html}`).not.toMatch(/\bLukas\b/);
  });

  test("the email states the real expiry and loads Wambito from the web host", async () => {
    await sendCode("expiry@wambito.test");
    const mail = t.mailer.lastTo("expiry@wambito.test");
    expect(mail?.text).toContain(`vencen en ${CODE_TTL_SECONDS / 60} minutos.`);
    expect(mail?.html).toContain('src="http://localhost:5173/email/wambi.png"');
  });

  test("the passkey relying party is named Wambito, and its id stays the web host", async () => {
    const { headers } = await t.signIn("rp@wambito.test");
    const res = await t.request("GET", "/auth/passkey/generate-register-options", { headers });
    expect(res.status).toBe(200);
    const options = (await res.json()) as { rp: { name: string; id: string } };
    expect(options.rp).toEqual({ name: "Wambito", id: "localhost" });
  });

  test("a new passkey is offered ES256 first and never Ed25519", async () => {
    // Proton Pass creates Ed25519 keys when offered them first, then cannot sign with them
    // (AuthenticatorError 38, CTAP2_ERR_UNSUPPORTED_ALGORITHM).
    const { headers } = await t.signIn("alg@wambito.test");
    const res = await t.request("GET", "/auth/passkey/generate-register-options", { headers });
    expect(res.status).toBe(200);
    // The challenge cookie still comes along: verify-registration needs it.
    expect(res.headers.get("set-cookie")).toContain("better-auth-passkey");
    const options = (await res.json()) as {
      challenge: string;
      pubKeyCredParams: { alg: number; type: string }[];
    };
    expect(options.challenge).toBeTruthy();
    expect(options.pubKeyCredParams).toEqual([
      { alg: -7, type: "public-key" },
      { alg: -257, type: "public-key" },
    ]);
  });

  test("signing in returns a bearer token that opens protected routes", async () => {
    await sendCode("b@wambito.test");
    const code = codeFrom(t.mailer.lastTo("b@wambito.test")?.subject ?? "");
    const res = await signInWith("b@wambito.test", code);
    expect(res.status).toBe(200);
    const token = res.headers.get("set-auth-token");
    expect(token).toBeTruthy();
    const me = await t.request("GET", "/v1/me", { headers: { authorization: `Bearer ${token}` } });
    expect(me.status).toBe(200);
    expect(await me.json()).toMatchObject({ email: "b@wambito.test" });
  });

  test("codes are not stored in plain text", async () => {
    await sendCode("hash@wambito.test");
    const code = codeFrom(t.mailer.lastTo("hash@wambito.test")?.subject ?? "");
    const rows = await t.admin
      .select()
      .from(verification)
      .where(like(verification.identifier, "%hash@wambito.test%"));
    expect(rows.length).toBeGreaterThan(0);
    for (const row of rows) expect(row.value).not.toContain(code);
    expect((await signInWith("hash@wambito.test", code)).status).toBe(200);
  });

  test("a code works only once", async () => {
    await sendCode("c@wambito.test");
    const code = codeFrom(t.mailer.lastTo("c@wambito.test")?.subject ?? "");
    expect((await signInWith("c@wambito.test", code)).status).toBe(200);
    expect((await signInWith("c@wambito.test", code)).status).not.toBe(200);
  });

  test("a code expires after 10 minutes", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-10-20T10:00:00Z"));
    await sendCode("d@wambito.test");
    const code = codeFrom(t.mailer.lastTo("d@wambito.test")?.subject ?? "");
    vi.setSystemTime(new Date("2026-10-20T10:10:01Z"));
    expect((await signInWith("d@wambito.test", code)).status).not.toBe(200);
  });

  test("three wrong attempts burn the code", async () => {
    await sendCode("e@wambito.test");
    const code = codeFrom(t.mailer.lastTo("e@wambito.test")?.subject ?? "");
    const wrong = code === "000000" ? "111111" : "000000";
    for (let i = 0; i < 3; i++) await signInWith("e@wambito.test", wrong);
    expect((await signInWith("e@wambito.test", code)).status).not.toBe(200);
  });

  test("a sixth code to the same email within 15 minutes is throttled", async () => {
    for (let i = 0; i < 5; i++) expect((await sendCode("f@wambito.test")).status).toBe(200);
    expect((await sendCode("f@wambito.test")).status).toBe(429);
  });

  test("codes from one IP are rate limited", async () => {
    const ip = { "x-forwarded-for": "192.168.77.1" };
    const statuses: number[] = [];
    for (let i = 0; i < 6; i++) statuses.push((await sendCode(`ip${i}@wambito.test`, ip)).status);
    expect(statuses.slice(0, 5)).toEqual([200, 200, 200, 200, 200]);
    expect(statuses[5]).toBe(429);
  });

  test("spoofed leftmost X-Forwarded-For entries do not dodge the per-IP limit", async () => {
    const statuses: number[] = [];
    for (let i = 0; i < 6; i++) {
      const xff = { "x-forwarded-for": `${i}.${i}.${i}.${i}, 203.0.113.9, 10.0.0.1` };
      statuses.push((await sendCode(`spoof${i}@wambito.test`, xff)).status);
    }
    expect(statuses[5]).toBe(429);
  });

  test("a new address gets the email in the language of the page that asked for it", async () => {
    await sendCode("lang-en@wambito.test", { "x-wambito-locale": "en" });
    const mail = t.mailer.lastTo("lang-en@wambito.test");
    expect(mail?.subject).toMatch(/^Your Wambito code: \d{6}$/);
    expect(mail?.text).toContain("&lang=en");
  });

  test.each([
    ["en-US", "Your Wambito code", "en"],
    ["en_US", "Your Wambito code", "en"],
    ["EN-gb", "Your Wambito code", "en"],
    ["es-CO", "Tu código de Wambito", "es"],
    ["es_419", "Tu código de Wambito", "es"],
    ["it-IT", "Il tuo codice Wambito", "it"],
    ["pt-PT", "O teu código Wambito", "pt"],
    ["pt-BR", "O teu código Wambito", "pt"],
  ])(
    "a phone's language tag %j picks the email's language (the app sends the full tag)",
    async (tag, subject, lang) => {
      const email = `tag-${tag.toLowerCase().replace(/[^a-z0-9]/g, "")}@wambito.test`;
      // The opposite language in Accept-Language: the app's hint must win over it.
      const accept =
        lang === "en" || lang === "it" || lang === "pt" ? "es-CO,es;q=0.9" : "en-US,en;q=0.9";
      await sendCode(email, { "x-wambito-locale": tag, "accept-language": accept });
      const mail = t.mailer.lastTo(email);
      expect(mail?.subject.startsWith(subject)).toBe(true);
      expect(mail?.text).toContain(`&lang=${lang}`);
    },
  );

  test("a tag in another language, or no tag, falls back to Accept-Language", async () => {
    await sendCode("tag-fr@wambito.test", { "x-wambito-locale": "fr-FR", "accept-language": "en" });
    expect(t.mailer.lastTo("tag-fr@wambito.test")?.subject).toMatch(/^Your Wambito code/);
    await sendCode("tag-junk@wambito.test", { "x-wambito-locale": "-_-", "accept-language": "en" });
    expect(t.mailer.lastTo("tag-junk@wambito.test")?.subject).toMatch(/^Your Wambito code/);
  });

  test("with no hint, a new address gets the browser's language (Accept-Language)", async () => {
    await sendCode("accept-en@wambito.test", { "accept-language": "en-GB,en;q=0.9,es;q=0.5" });
    expect(t.mailer.lastTo("accept-en@wambito.test")?.subject).toMatch(/^Your Wambito code/);
    await sendCode("accept-es@wambito.test", { "accept-language": "es-CO,es;q=0.9,en;q=0.8" });
    expect(t.mailer.lastTo("accept-es@wambito.test")?.subject).toMatch(/^Tu código de Wambito/);
    await sendCode("accept-fr@wambito.test", { "accept-language": "fr-FR,fr;q=0.9" });
    expect(t.mailer.lastTo("accept-fr@wambito.test")?.subject).toMatch(/^Tu código de Wambito/);
  });

  test("an existing user's profile language wins over the hint", async () => {
    const { headers } = await t.signIn("profile-es@wambito.test");
    await t.request("PATCH", "/v1/me", { headers, body: { locale: "es" } });
    await sendCode("profile-es@wambito.test", {
      "x-wambito-locale": "en",
      "accept-language": "en",
    });
    const mail = t.mailer.lastTo("profile-es@wambito.test");
    expect(mail?.subject).toMatch(/^Tu código de Wambito/);
    expect(mail?.text).toContain("&lang=es");
  });

  test("the magic link carries a same-origin next, and never an off-site one", async () => {
    await sendCode("next@wambito.test", { "x-wambito-next": "/app/insights?month=2026-10" });
    const link = /http\S+/.exec(t.mailer.lastTo("next@wambito.test")?.text ?? "")?.[0] ?? "";
    expect(new URL(link).searchParams.get("next")).toBe("/app/insights?month=2026-10");
    for (const next of ["https://evil.example", "//evil.example", "/\\evil.example", "app"]) {
      await sendCode("next-bad@wambito.test", { "x-wambito-next": next });
      const bad = /http\S+/.exec(t.mailer.lastTo("next-bad@wambito.test")?.text ?? "")?.[0] ?? "";
      expect(new URL(bad).searchParams.has("next"), next).toBe(false);
    }
  });

  test("the magic link brings an assistant's long consent URL back", async () => {
    // A signed authorization request: state, PKCE challenge, resource and signature run past 700.
    const consent = `/oauth/consent?state=${"s".repeat(256)}&code_challenge=${"c".repeat(128)}&sig=${"g".repeat(400)}`;
    await sendCode("next-consent@wambito.test", { "x-wambito-next": consent });
    const link =
      /http\S+/.exec(t.mailer.lastTo("next-consent@wambito.test")?.text ?? "")?.[0] ?? "";
    expect(new URL(link).searchParams.get("next")).toBe(consent);
    // A path the Android app does not open: the code must reach the assistant's own browser window.
    expect(new URL(link).pathname).toBe("/oauth/verify");
    expect(t.mailer.lastTo("next-consent@wambito.test")?.subject).toMatch(/asistente|assistant/);
    await sendCode("next-huge@wambito.test", { "x-wambito-next": `/app?q=${"x".repeat(5000)}` });
    const huge = /http\S+/.exec(t.mailer.lastTo("next-huge@wambito.test")?.text ?? "")?.[0] ?? "";
    expect(new URL(huge).searchParams.has("next")).toBe(false);
    expect(new URL(huge).pathname).toBe("/auth/verify");
  });

  test("the link carries from=app only when the app started the sign-in", async () => {
    await sendCode("from-app@wambito.test", { "x-wambito-client": "android" });
    const app = /http\S+/.exec(t.mailer.lastTo("from-app@wambito.test")?.text ?? "")?.[0] ?? "";
    expect(new URL(app).searchParams.get("from")).toBe("app");
    expect(new URL(app).pathname).toBe("/auth/verify");

    // The iOS app marks its sign-ins the same way.
    await sendCode("from-ios@wambito.test", { "x-wambito-client": "ios" });
    const ios = /http\S+/.exec(t.mailer.lastTo("from-ios@wambito.test")?.text ?? "")?.[0] ?? "";
    expect(new URL(ios).searchParams.get("from")).toBe("app");

    // The web sends no marker, and anything but the app's own value is not the app.
    await sendCode("from-web@wambito.test");
    const web = /http\S+/.exec(t.mailer.lastTo("from-web@wambito.test")?.text ?? "")?.[0] ?? "";
    expect(new URL(web).searchParams.has("from")).toBe(false);
    for (const value of ["web", "", "android evil", "ios evil"]) {
      await sendCode("from-other@wambito.test", { "x-wambito-client": value });
      const other =
        /http\S+/.exec(t.mailer.lastTo("from-other@wambito.test")?.text ?? "")?.[0] ?? "";
      expect(new URL(other).searchParams.has("from"), value).toBe(false);
    }
    // A timezone alone (the widget's and the notices' requests send it too) is not the marker.
    await sendCode("from-tz@wambito.test", { "x-wambito-timezone": "Europe/Lisbon" });
    const tz = /http\S+/.exec(t.mailer.lastTo("from-tz@wambito.test")?.text ?? "")?.[0] ?? "";
    expect(new URL(tz).searchParams.has("from")).toBe(false);
  });

  test("a new user gets one default account", async () => {
    const { userId } = await t.signIn("g@wambito.test");
    const rows = await withUser(t.db, userId, (tx) =>
      tx.select().from(accounts).where(eq(accounts.userId, userId)),
    );
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ name: "Main", currency: "EUR", isDefault: true });
  });
});

test("the OAuth authorization server metadata advertises the finance scopes", async () => {
  const res = await t.request("GET", "/.well-known/oauth-authorization-server");
  expect(res.status).toBe(200);
  const metadata = (await res.json()) as {
    scopes_supported: string[];
    registration_endpoint?: string;
  };
  expect(metadata.scopes_supported).toEqual(
    expect.arrayContaining(["finance:read", "finance:write"]),
  );
  expect(metadata.registration_endpoint).toBeDefined();
});

test("a guest's defaults read an underscore tag (en_US) like a hyphenated one", () => {
  const read = (tag: string) => guestDefaults(new Headers({ "x-wambito-locale": tag }));
  expect(read("en_US")).toMatchObject({ locale: "en", region: "US" });
  expect(read("es_CO")).toMatchObject({ locale: "es", region: "CO" });
  expect(read("en-US")).toMatchObject({ locale: "en", region: "US" });
});

test("a tag maps to a locale: it-* is Italian, pt-* (Brazil too) is Portuguese, the rest Spanish or the fallback", () => {
  const read = (tag: string) => guestDefaults(new Headers({ "x-wambito-locale": tag }));
  expect(read("it-IT")).toMatchObject({ locale: "it", region: "IT" });
  expect(read("it")).toMatchObject({ locale: "it" });
  expect(read("it_CH")).toMatchObject({ locale: "it", region: "CH" });
  expect(read("pt-PT")).toMatchObject({ locale: "pt", region: "PT" });
  expect(read("pt-BR")).toMatchObject({ locale: "pt", region: "BR" });
  expect(read("pt")).toMatchObject({ locale: "pt" });
  expect(read("fr-FR").locale).toBe("es");
  const accept = (value: string) => guestDefaults(new Headers({ "accept-language": value }));
  expect(accept("it-IT,it;q=0.9,en;q=0.5").locale).toBe("it");
  expect(accept("pt-PT,pt;q=0.9").locale).toBe("pt");
  expect(accept("fr").locale).toBe("es");
});

describe("sign-in email language for it and pt", () => {
  test.each([
    ["it-IT", "it"],
    ["it", "it"],
    ["pt-PT", "pt"],
    ["pt-BR", "pt"],
    ["pt", "pt"],
  ])("a phone's tag %j puts lang=%s on the link", async (tag, lang) => {
    const email = `lang-${tag.toLowerCase().replace(/[^a-z0-9]/g, "")}@wambito.test`;
    await sendCode(email, { "x-wambito-locale": tag, "accept-language": "en-US,en;q=0.9" });
    expect(t.mailer.lastTo(email)?.text).toContain(`&lang=${lang}`);
  });
});
