import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import AxeBuilder from "@axe-core/playwright";
import { expect, type Page, request, test } from "@playwright/test";

/**
 * Helpers for app flows against the dev stack (`docker compose up`: API, Postgres, Mailpit):
 * fresh addresses, reading the sign-in email from Mailpit, and signing a new user in.
 */

const MAILPIT = process.env.MAILPIT_URL ?? "http://localhost:8025";
/** The API itself (not through the web's proxy), for set-up calls that are not under test. */
const API = process.env.E2E_API_URL ?? "http://localhost:3000";
const WEB = "http://localhost:5173";

const rand = (n: number) => Math.floor(Math.random() * n);

/**
 * The suite's "now": 21 October 2026, 15:00 UTC (afternoon in Madrid, morning in Bogotá). The
 * sample Budge file's months (September and October 2026) are read against it, so nothing depends
 * on the real date:
 * - the API runs with `E2E_NOW` set to it (docker-compose.yml; global-setup.ts checks), and
 * - a spec that reads a month pins its page with `pinClock(page)` before the first navigation.
 */
export const E2E_NOW = "2026-10-21T15:00:00Z";

/** Pins the page's clock (it still ticks from there) to the suite's "now", or to `time`. */
export function pinClock(page: Page, time: string = E2E_NOW): Promise<void> {
  return page.clock.install({ time: new Date(time) });
}

/**
 * A made-up client address (from 198.18.0.0/15, reserved for testing) for a browser context's
 * `X-Forwarded-For`. The API limits sign-in per address (3 sign-ins per 10 s, 5 codes per
 * 10 min), and every browser on this machine would otherwise be 127.0.0.1. The dev stack trusts
 * Vite's proxy (TRUSTED_PROXIES in .env), so the address the browser sends is the one counted.
 */
export function clientIp(): string {
  return `198.${18 + rand(2)}.${rand(256)}.${1 + rand(254)}`;
}

/** A new address per call, so each test is a new user with its own email throttle. */
export function freshEmail(label = "e2e"): string {
  const nonce = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
  return `${label}-${nonce}@wambito.test`;
}

interface MailSummary {
  ID: string;
  Created: string;
  Subject: string;
  To: { Address: string }[];
}

export interface SignInMail {
  id: string;
  code: string;
  /** The magic link: `${WEB_URL}/auth/verify?email=…&code=…`. */
  link: string;
  subject: string;
}

async function mailsTo(email: string): Promise<MailSummary[]> {
  const response = await fetch(`${MAILPIT}/api/v1/messages?limit=200`);
  if (!response.ok) throw new Error(`Mailpit: ${response.status}`);
  const { messages } = (await response.json()) as { messages: MailSummary[] };
  return messages.filter((m) => m.To.some((to) => to.Address.toLowerCase() === email));
}

/**
 * The newest sign-in email to `email`, waiting for it to arrive. `skip` ignores emails already
 * read (by id), so a second code is never confused with the first.
 */
export async function readSignInMail(
  email: string,
  { skip = [] as string[], timeoutMs = 15_000 } = {},
): Promise<SignInMail> {
  let found: MailSummary | undefined;
  await expect
    .poll(
      async () => {
        found = (await mailsTo(email.toLowerCase())).find((m) => !skip.includes(m.ID));
        return found !== undefined;
      },
      { timeout: timeoutMs, message: `a sign-in email to ${email}` },
    )
    .toBe(true);
  const summary = found as MailSummary;
  const response = await fetch(`${MAILPIT}/api/v1/message/${summary.ID}`);
  const { Text } = (await response.json()) as { Text: string };
  const code = /\b(\d{6})\b/.exec(summary.Subject)?.[1];
  const link = /https?:\/\/\S+\/auth\/verify\?\S+/.exec(Text)?.[0];
  if (!code || !link) throw new Error(`No code or link in "${summary.Subject}"`);
  return { id: summary.ID, code, link, subject: summary.Subject };
}

/** A client for the API itself, as a new client address. */
const apiClient = () =>
  request.newContext({
    baseURL: API,
    extraHTTPHeaders: { origin: WEB, "x-forwarded-for": clientIp() },
  });

/**
 * Asks the API for a sign-in code without going through a page, for set-up steps that are not
 * what the test checks.
 */
export async function requestCode(
  email: string,
  hints: { locale?: Lang; next?: string; client?: "android" } = {},
): Promise<void> {
  const api = await apiClient();
  const response = await api.post("/api/auth/email-otp/send-verification-otp", {
    data: { email, type: "sign-in" },
    headers: {
      ...(hints.locale ? { "x-wambito-locale": hints.locale } : {}),
      ...(hints.next ? { "x-wambito-next": hints.next } : {}),
      ...(hints.client ? { "x-wambito-client": hints.client } : {}),
    },
  });
  expect(response.status(), await response.text()).toBe(200);
  await api.dispose();
}

/** Signs in with a code through the API, using it up (as if typed elsewhere). */
export async function spendCode(email: string, code: string): Promise<void> {
  const api = await apiClient();
  const response = await api.post("/api/auth/sign-in/email-otp", { data: { email, otp: code } });
  expect(response.status(), await response.text()).toBe(200);
  await api.dispose();
}

/** The signed-in user of a page's browser context, from Better Auth's session endpoint. */
export async function sessionUser(page: Page): Promise<{ id: string; email: string } | null> {
  const response = await page.request.get("/api/auth/get-session");
  expect(response.ok()).toBe(true);
  const body = (await response.json()) as { user: { id: string; email: string } } | null;
  return body?.user ?? null;
}

/**
 * A software authenticator in the page's browser (Chrome's WebAuthn domain over CDP): creates and
 * uses passkeys without a person, verifying the user at once. Call it before the page asks for one.
 * `prf` gives its passkeys the PRF extension (`hasPrf`), which opens an encrypted account's data;
 * without it (the default, as Chromium's) a new passkey signs in only, and an encrypted account's
 * passkey offer says so before going on.
 */
export async function addVirtualAuthenticator(
  page: Page,
  { prf = false }: { prf?: boolean } = {},
): Promise<void> {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("WebAuthn.enable");
  await cdp.send("WebAuthn.addVirtualAuthenticator", {
    options: {
      protocol: "ctap2",
      transport: "internal",
      hasResidentKey: true,
      hasUserVerification: true,
      isUserVerified: true,
      hasPrf: prf,
      automaticPresenceSimulation: true,
    },
  });
}

/** The four languages of the app. */
export type Lang = "es" | "en" | "it" | "pt";

/** The sign-in screens' words the helpers click, per language (app.<lang>.json). */
const SIGN_IN_WORDS: Record<
  Lang,
  { notNow: string; email: string; sendCode: string; digit1: string }
> = {
  es: {
    notNow: "Ahora no",
    email: "Tu correo",
    sendCode: "Enviar código",
    digit1: "Dígito 1 de 6",
  },
  en: { notNow: "Not now", email: "Your email", sendCode: "Send code", digit1: "Digit 1 of 6" },
  it: {
    notNow: "Non ora",
    email: "La tua email",
    sendCode: "Invia codice",
    digit1: "Cifra 1 di 6",
  },
  pt: {
    notNow: "Agora não",
    email: "O teu email",
    sendCode: "Enviar código",
    digit1: "Dígito 1 de 6",
  },
};

/**
 * After an email sign-in Wambito offers a passkey ("¿Entrar con tu huella la próxima vez?") once per
 * user per device. Tests that are about something else say "Ahora no" and carry on: this waits
 * for whichever comes first, the offer or the page sign-in was heading to, and dismisses the offer.
 */
export async function skipPasskeyOffer(page: Page, { lang = "es" as Lang } = {}) {
  await expect(page).toHaveURL(/\/(passkey-offer|welcome|app)(\?|\/|$)/);
  if (new URL(page.url()).pathname !== "/passkey-offer") return;
  await page.getByRole("button", { name: SIGN_IN_WORDS[lang].notNow }).click();
  await expect(page).not.toHaveURL(/\/passkey-offer/);
}

/**
 * Signs a brand-new plain user in through the sign-in page; returns their email. Lands on
 * /welcome. The e2e stack runs with NEW_USERS_ENCRYPTED on, so a real sign-up would be born
 * encrypted: the user is seeded plain first (`seedPlainUser`, its categories named in `lang`), and
 * the email sign-in then finds it.
 */
export async function signUpNewUser(page: Page, { lang = "es" as Lang } = {}) {
  const email = freshEmail();
  seedPlainUser(email, lang);
  await page.goto(`/sign-in?lang=${lang}`);
  const words = SIGN_IN_WORDS[lang];
  await page.getByRole("textbox", { name: words.email }).fill(email);
  await page.getByRole("button", { name: words.sendCode }).click();
  const mail = await readSignInMail(email);
  await page.getByRole("textbox", { name: words.digit1 }).fill(mail.code);
  await skipPasskeyOffer(page, { lang });
  await expect(page).toHaveURL(/\/welcome$/);
  return email;
}

/**
 * Signs an existing user in through the sign-in page (their old emails in Mailpit are skipped, so
 * the code read is the new one). Dismisses the passkey offer; lands on the page sign-in goes to.
 */
export async function signInExisting(page: Page, email: string, { lang = "es" as Lang } = {}) {
  const old = (await mailsTo(email.toLowerCase())).map((m) => m.ID);
  await page.goto(`/sign-in?lang=${lang}`);
  const words = SIGN_IN_WORDS[lang];
  await page.getByRole("textbox", { name: words.email }).fill(email);
  await page.getByRole("button", { name: words.sendCode }).click();
  const mail = await readSignInMail(email, { skip: old });
  await page.getByRole("textbox", { name: words.digit1 }).fill(mail.code);
  await skipPasskeyOffer(page, { lang });
}

const BUDGE_SAMPLE = fileURLToPath(
  new URL("../../../packages/importers/test/fixtures/budge-sample.csv", import.meta.url),
);

interface Category {
  id: string;
  name: string;
}

/** The onboarding the e2e for it already covers, done through the API: profile, import, budget. */
export async function onboardWithSample(page: Page, timezone: string) {
  // The welcome screen saves the browser's zone once; wait for it so ours is the last word.
  await expect
    .poll(
      async () =>
        ((await (await page.request.get("/api/v1/me")).json()) as { timezone: string }).timezone,
    )
    .not.toBe("UTC");
  const me = await page.request.patch("/api/v1/me", {
    data: { currency: "EUR", timezone, locale: "es" },
  });
  expect(me.ok(), await me.text()).toBe(true);
  const preview = await page.request.post("/api/v1/imports", {
    multipart: {
      source: "budge",
      file: { name: "budge.csv", mimeType: "text/csv", buffer: readFileSync(BUDGE_SAMPLE) },
    },
  });
  expect(preview.ok(), await preview.text()).toBe(true);
  const { id } = (await preview.json()) as { id: string };
  const confirm = await page.request.post(`/api/v1/imports/${id}/confirm`);
  expect(confirm.ok(), await confirm.text()).toBe(true);
  const categories = (await (await page.request.get("/api/v1/categories")).json()) as Category[];
  const groceries = categories.find((c) => c.name === "Supermercado");
  if (!groceries) throw new Error("The sample has Supermercado");
  const budget = await page.request.put(`/api/v1/categories/${groceries.id}/budget`, {
    data: { amount: 50000, effectiveFrom: "2026-09" },
  });
  expect(budget.ok(), await budget.text()).toBe(true);
  const done = await page.request.patch("/api/v1/me", { data: { onboardingCompleted: true } });
  expect(done.ok(), await done.text()).toBe(true);
}

/** The WCAG 2.2 A and AA rules axe checks on every app screen. */
export const WCAG_TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

/**
 * Runs axe on the page once it is at rest, and fails with every violation and its nodes. At rest:
 * no finite animation or CSS transition still running (entrances, sheets, toasts, a pressed
 * button's colors), so colors are checked as they end up, not halfway. Scroll-driven animations
 * (the landing's reveals) are not waited for: they follow the scroll, not the clock, and stay
 * "running" until their element has scrolled past.
 */
export async function expectNoAxeViolations(page: Page, screen = page.url(), tags = WCAG_TAGS) {
  await page.waitForFunction(() =>
    document
      .getAnimations()
      .every(
        (a) =>
          !(a.timeline instanceof DocumentTimeline) ||
          a.playState !== "running" ||
          a.effect?.getComputedTiming().iterations === Number.POSITIVE_INFINITY,
      ),
  );
  const results = await new AxeBuilder({ page }).withTags(tags).analyze();
  expect(
    results.violations.map((v) => ({ id: v.id, nodes: v.nodes.map((n) => n.target.join(" ")) })),
    `axe on ${screen}`,
  ).toEqual([]);
}

/** The recovery key from the setup screen, then the four characters it asks back. */
export async function setUpRecoveryKey(page: Page): Promise<string> {
  await expect(
    page.getByRole("heading", { name: "Guarda tu clave de recuperación" }),
  ).toBeVisible();
  const key = (
    await page.getByRole("group", { name: "Tu clave de recuperación" }).innerText()
  ).replace(/\s+/g, "-");
  expect(key).toMatch(/^[0-9A-Z]{4}(-[0-9A-Z]{3,4})+$/);
  await page.getByRole("button", { name: "Ya la guardé" }).click();
  const plain = key.replaceAll("-", "");
  const boxes = page.getByRole("textbox", { name: /^Grupo \d+, carácter \d+$/ });
  for (const box of await boxes.all()) {
    const [, group, char] = /^Grupo (\d+), carácter (\d+)$/.exec(
      (await box.getAttribute("aria-label")) ?? "",
    ) ?? ["", "0", "0"];
    await box.fill(plain[(Number(group) - 1) * 4 + Number(char) - 1] ?? "");
  }
  await page.getByRole("button", { name: "Continuar" }).click();
  return key;
}

/** The time `seedPlainUser` adds to the running test's timeout. */
const SEED_SLACK_MS = 15_000;

/**
 * Inserts a plain user with this email, as a plain web sign-up leaves it before onboarding (email
 * verified, the default account and the suggested categories, named in `lang`), in the API
 * container (`seed:e2e-plain-user`). An existing email is left as it is.
 */
export function seedPlainUser(email: string, lang: Lang = "es"): void {
  // A few seconds in the container (tsx starting up): the test gets them on top of its timeout.
  const info = test.info();
  if (info.timeout > 0) info.setTimeout(info.timeout + SEED_SLACK_MS);
  execFileSync(
    "docker",
    [
      ...["compose", "exec", "-T", "api", "pnpm", "--silent", "--filter", "@wambito/api"],
      ...["seed:e2e-plain-user", email, lang],
    ],
    // Its stderr is kept for the error a failed seed throws.
    { stdio: ["ignore", "ignore", "pipe"] },
  );
}

/** Makes the preview account again: no records, key wraps, passkeys or finance rows. */
export function reseed() {
  execFileSync(
    "docker",
    ["compose", "exec", "-T", "api", "pnpm", "--filter", "@wambito/api", "seed:e2e-preview"],
    { stdio: "inherit" },
  );
}

/**
 * Makes the plain account the migration e2e moves to encrypted again (`migrate-e2e`,
 * migrate@wambito.test, `seed:e2e-migrate` in the API container): deleted and recreated with
 * every kind of row (an archived category, budget months, a yearly and a monthly recurrence with a
 * dismissed month, a deleted transaction, a capture and its merchant rule), in COP.
 */
export function seedMigrateUser(): void {
  const info = test.info();
  if (info.timeout > 0) info.setTimeout(info.timeout + SEED_SLACK_MS);
  execFileSync(
    "docker",
    [
      ...["compose", "exec", "-T", "api", "pnpm", "--silent", "--filter", "@wambito/api"],
      "seed:e2e-migrate",
    ],
    { stdio: ["ignore", "ignore", "pipe"] },
  );
}

/** Runs one SQL statement in the dev stack's database (as its owner); its rows, tab-separated. */
export function psql(sql: string): string {
  return execFileSync(
    "docker",
    ["compose", "exec", "-T", "postgres", "psql", "-U", "wambito", "-d", "wambito", "-tAc", sql],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
  ).trim();
}
