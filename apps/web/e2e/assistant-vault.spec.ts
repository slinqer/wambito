import { createHash, randomBytes } from "node:crypto";
import { type Browser, type BrowserContext, expect, type Page, test } from "@playwright/test";
import { clientIp, pinClock, reseed, setUpRecoveryKey, signInExisting } from "./helpers.ts";

/**
 * An AI assistant connects to the seeded encrypted preview account (`preview-e2e`,
 * preview@wambito.test) through the real consent page (stage 4 design, section 5):
 * - with the vault open in the browser, Allow needs no key;
 * - in a browser without the vault, the recovery key opens it, only to connect the assistant.
 * Either way the assistant's refresh token ends with `.` and the 43-character secret `S`, and the
 * connection shows in `GET /v1/me/assistants` until it is revoked. The spec resets the account
 * first (`seed:e2e-preview`), so it needs the stack up and `docker` on the PATH.
 */

const EMAIL = "preview@wambito.test";
const API = process.env.E2E_API_URL ?? "http://localhost:3000";
const REDIRECT = "https://claude.ai/api/mcp/auth_callback";
const MCP_URL = "http://localhost:3001/mcp";

test.describe.configure({ mode: "serial" });
test.use({ actionTimeout: 10_000 });
// One preview account for the whole suite: desktop project only (see vault.spec.ts).
test.skip(({ isMobile }) => isMobile, "one preview account per run, desktop only");

test.beforeAll(async ({ browser: _ }, testInfo) => {
  if (testInfo.project.name !== "desktop") return;
  reseed();
});

interface Opened {
  context: BrowserContext;
  page: Page;
}

/** A new browser (its own cookies, storage and IndexedDB), in Spanish, from Madrid. */
async function openBrowser(browser: Browser): Promise<Opened> {
  const context = await browser.newContext({
    locale: "es-ES",
    timezoneId: "Europe/Madrid",
    viewport: { width: 1280, height: 800 },
    extraHTTPHeaders: { "x-forwarded-for": clientIp() },
  });
  const page = await context.newPage();
  await pinClock(page);
  return { context, page };
}

/** The first browser of a fresh account: signs in and sets up the vault. Returns its key. */
async function firstBrowser(opened: Opened): Promise<string> {
  await signInExisting(opened.page, EMAIL);
  const key = await setUpRecoveryKey(opened.page);
  await opened.page.getByRole("button", { name: "Entrar directo" }).click();
  await expect(opened.page).toHaveURL(/\/app$/);
  return key;
}

interface Pending {
  authorize: string;
  verifier: string;
  clientId: string;
}

/**
 * What an assistant does before it sends the person to the browser: registers itself (dynamic
 * client registration) and builds the authorize URL (PKCE S256, `resource` = the MCP).
 */
async function startConnecting(): Promise<Pending> {
  const registered = await fetch(`${API}/api/auth/oauth2/register`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-forwarded-for": clientIp() },
    body: JSON.stringify({
      client_name: "Claude",
      client_uri: "https://claude.ai",
      redirect_uris: [REDIRECT],
      token_endpoint_auth_method: "none",
      grant_types: ["authorization_code", "refresh_token"],
      response_types: ["code"],
    }),
  });
  expect(registered.status, await registered.clone().text()).toBe(201);
  const { client_id: clientId } = (await registered.json()) as { client_id: string };
  const verifier = randomBytes(32).toString("base64url");
  const query = new URLSearchParams({
    response_type: "code",
    client_id: clientId,
    redirect_uri: REDIRECT,
    scope: "finance:read finance:write offline_access",
    resource: MCP_URL,
    state: "e2e",
    code_challenge: createHash("sha256").update(verifier).digest("base64url"),
    code_challenge_method: "S256",
    prompt: "consent",
  });
  return { authorize: `/api/auth/oauth2/authorize?${query}`, verifier, clientId };
}

/**
 * Opens the authorize URL in the person's browser and holds the redirect back to the assistant
 * (an external site, answered empty here); returns the code it carries.
 */
async function openConsent(page: Page, pending: Pending) {
  await page.route("https://claude.ai/**", (route) => route.fulfill({ status: 200, body: "" }));
  await page.goto(pending.authorize);
  await expect(page).toHaveURL(/\/oauth\/consent\?/);
  await expect(
    page.getByRole("heading", { name: "Claude quiere acceder a tus finanzas" }),
  ).toBeVisible();
  await expect(page.getByText("Mientras esté conectado, Wambito abre tus datos")).toBeVisible();
}

async function codeAfterRedirect(page: Page): Promise<string> {
  await page.waitForURL((url) => url.origin === "https://claude.ai");
  const back = new URL(page.url());
  expect(back.searchParams.get("state")).toBe("e2e");
  const code = back.searchParams.get("code");
  expect(code).toBeTruthy();
  return code ?? "";
}

/** The assistant's second half: the code for tokens. Returns the refresh token. */
async function refreshTokenFor(pending: Pending, code: string): Promise<string> {
  const response = await fetch(`${API}/api/auth/oauth2/token`, {
    method: "POST",
    headers: {
      "content-type": "application/x-www-form-urlencoded",
      "x-forwarded-for": clientIp(),
    },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: REDIRECT,
      client_id: pending.clientId,
      code_verifier: pending.verifier,
      resource: MCP_URL,
    }),
  });
  expect(response.status, await response.clone().text()).toBe(200);
  const tokens = (await response.json()) as { refresh_token?: string };
  expect(tokens.refresh_token).toBeTruthy();
  return tokens.refresh_token ?? "";
}

/** An encrypted account's refresh token: the usual token, then `.` and `S` (43 base64url chars). */
const CARRIES_SECRET = /\.[A-Za-z0-9_-]{43}$/;

async function expectListed(page: Page) {
  const list = await page.request.get("/api/v1/me/assistants");
  expect(list.status()).toBe(200);
  const body = (await list.json()) as { items: { name: string }[] };
  expect(body.items.map((a) => a.name)).toContain("Claude");
}

test("with the vault open, Allow connects without asking for a key", async ({ browser }) => {
  test.setTimeout(90_000);
  reseed();
  const opened = await openBrowser(browser);
  await firstBrowser(opened);
  const { page } = opened;

  const pending = await startConnecting();
  await openConsent(page, pending);
  await page.getByRole("button", { name: "Permitir" }).click();

  const code = await codeAfterRedirect(page);
  await expectListed(page);
  expect(await refreshTokenFor(pending, code)).toMatch(CARRIES_SECRET);

  await opened.context.close();
});

test("in a browser without the vault, the recovery key connects it", async ({ browser }) => {
  test.setTimeout(120_000);
  reseed();
  const first = await openBrowser(browser);
  const key = await firstBrowser(first);

  // A second browser signs in and is at the unlock screen, with no vault of its own.
  const second = await openBrowser(browser);
  await signInExisting(second.page, EMAIL);
  await expect(second.page.getByRole("heading", { name: "Abre tus datos aquí" })).toBeVisible();

  const pending = await startConnecting();
  await openConsent(second.page, pending);
  await second.page.getByRole("button", { name: "Permitir" }).click();
  await expect(
    second.page.getByRole("heading", { name: "Abre tus datos para conectarlo" }),
  ).toBeVisible();
  await second.page.getByRole("textbox", { name: "Clave de recuperación" }).fill(key);
  await second.page.getByRole("button", { name: "Abrir mis datos" }).click();

  const code = await codeAfterRedirect(second.page);
  await expectListed(second.page);
  expect(await refreshTokenFor(pending, code)).toMatch(CARRIES_SECRET);
  // Nothing was kept: this browser still has no vault.
  expect(
    await second.page.evaluate(async () => (await indexedDB.databases()).map((d) => d.name ?? "")),
  ).not.toContain("wambito-vault-preview-e2e");

  await first.context.close();
  await second.context.close();
});
