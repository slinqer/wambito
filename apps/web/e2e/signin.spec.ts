import { type Browser, type BrowserContext, expect, type Page, test } from "@playwright/test";
import {
  clientIp,
  E2E_NOW,
  freshEmail,
  pinClock,
  readSignInMail,
  sessionUser,
  setUpRecoveryKey,
  skipPasskeyOffer,
} from "./helpers.ts";
import { approveSignin } from "./phone.ts";

/**
 * The web sign-in by the phone (spec 2026-11-15 section 8) and by a recovery key, against the dev
 * stack with NEW_USERS_ENCRYPTED on. Node plays the phone (`phone.ts`: the real crypto over the
 * API, with the session of browser B, where the account was born):
 * - browser A opens `/sign-in`, the phone approves its code, A lands on `/app` with the movement
 *   and a 60-day cookie;
 * - browser C signs in with the recovery key typed in lower case with spaces;
 * - browser D unticks "keep me signed in": its cookie ends with the browser, and once it is gone
 *   the next page leaves no `wambito-vault-*` database (Review Focus 4).
 * The account is a fresh web sign-up (born encrypted), not the shared `preview-e2e`, so this file
 * never meets `vault.spec.ts`'s reseeds. Serial (the tests share B and its key), desktop only (the
 * QR panel comes first on a wide screen).
 */

const NAME = "cena qr";
const DAY_S = 24 * 60 * 60;

test.describe.configure({ mode: "serial" });
test.use({ actionTimeout: 10_000 });
test.skip(({ isMobile }) => isMobile, "one born-encrypted account per run, desktop only");

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

const vaultDatabases = (page: Page) =>
  page.evaluate(async () =>
    (await indexedDB.databases())
      .map((d) => d.name ?? "")
      .filter((n) => n.startsWith("wambito-vault-")),
  );

/**
 * The vault's meta `ephemeral` (set by an unticked sign-in's enroll), read from its IndexedDB
 * (`app/local/db.ts`: store `meta`). Opened without a version and never created: an upgrade is
 * aborted, as `app/local/ephemeral.ts` does; a missing database is an error.
 */
const ephemeralMark = (page: Page, userId: string) =>
  page.evaluate(
    (name) =>
      new Promise<unknown>((resolve, reject) => {
        const open = indexedDB.open(name);
        open.onupgradeneeded = () => open.transaction?.abort();
        open.onerror = () => reject(new Error(`no database ${name}`));
        open.onsuccess = () => {
          const db = open.result;
          const get = db.transaction("meta", "readonly").objectStore("meta").get("ephemeral");
          get.onsuccess = () => {
            db.close();
            resolve(get.result);
          };
          get.onerror = () => {
            db.close();
            reject(get.error);
          };
        };
      }),
    `wambito-vault-${userId}`,
  );

const sessionCookie = async (context: BrowserContext) => {
  const cookie = (await context.cookies()).find((c) => c.name.endsWith("session_token"));
  if (!cookie) throw new Error("no session cookie");
  return cookie;
};

/** The QR panel's code (`ABCD EFGH`). */
const qrCode = (page: Page) =>
  page.getByRole("region", { name: "Entra con tu celular" }).getByText(/^[0-9A-Z]{4} [0-9A-Z]{4}$/);

/** The account's phone: browser B, its user id and recovery key. */
let phone: { opened: Opened; userId: string; recoveryKey: string } | undefined;

const approve = async (code: string, beforeSeal?: (number: string) => Promise<void>) => {
  if (!phone) throw new Error("the first test makes the account");
  return approveSignin({
    request: phone.opened.context.request,
    userId: phone.userId,
    code,
    recoveryKey: phone.recoveryKey,
    ...(beforeSeal ? { beforeSeal } : {}),
  });
};

test.afterAll(async () => {
  await phone?.opened.context.close();
});

test("a browser signs in by the code the phone approves and sees the account's movement", async ({
  browser,
}) => {
  test.setTimeout(120_000);

  // -- B: a web sign-up (born encrypted), the recovery key, a movement -------------------------
  const b = await openBrowser(browser);
  const email = freshEmail("qr");
  await b.page.goto("/create-account");
  await b.page.getByRole("textbox", { name: "Tu correo" }).fill(email);
  await b.page.getByRole("button", { name: "Enviar código" }).click();
  const mail = await readSignInMail(email);
  await b.page.getByRole("textbox", { name: "Dígito 1 de 6" }).fill(mail.code);
  await skipPasskeyOffer(b.page);
  const recoveryKey = await setUpRecoveryKey(b.page);
  await b.page.getByRole("button", { name: "Continuar en el navegador" }).click();
  await b.page.getByRole("button", { name: "Entrar directo" }).click();
  await expect(b.page).toHaveURL(/\/app$/);

  await b.page.getByRole("button", { name: "Agregar", exact: true }).click();
  const sheet = b.page.getByRole("dialog", { name: "Nuevo gasto" });
  const keypad = sheet.getByRole("group", { name: "Teclado numérico" });
  for (const digit of ["4", "2"]) {
    await keypad.getByRole("button", { name: digit, exact: true }).click();
  }
  await sheet.getByRole("textbox", { name: "Nombre (opcional)" }).fill(NAME);
  await sheet
    .getByRole("group", { name: "Categoría" })
    .getByRole("button", { name: "Supermercado" })
    .click();
  await sheet.getByRole("button", { name: "Guardar" }).click();
  await expect(sheet).toBeHidden();
  await expect(b.page.getByText(NAME, { exact: true })).toBeVisible();
  const user = await sessionUser(b.page);
  if (!user) throw new Error("B is signed in");
  phone = { opened: b, userId: user.id, recoveryKey };

  // -- A: /sign-in shows the code, the phone approves it ---------------------------------------
  const a = await openBrowser(browser);
  await a.page.goto("/sign-in");
  await expect(
    a.page.getByRole("checkbox", { name: "Mantener la sesión abierta en este navegador" }),
  ).toBeChecked();
  const code = (await qrCode(a.page).innerText()).trim();
  // The number line (ruling 8) shows the phone's 6 digits: both sides order the keys alike.
  const shown = await approve(code, async (number) => {
    await expect(
      a.page.getByText(
        `Si tu celular muestra un número, debe ser ${number.slice(0, 3)} ${number.slice(3)}`,
      ),
    ).toBeVisible({ timeout: 20_000 });
  });
  expect(shown).toMatch(/^\d{6}$/);

  await expect(a.page).toHaveURL(/\/app$/, { timeout: 30_000 });
  await expect(a.page.getByText(NAME, { exact: true })).toBeVisible();
  expect(await vaultDatabases(a.page)).toEqual([`wambito-vault-${user.id}`]);
  // Ticked: a vault the person keeps, never marked for the sweep.
  expect(await ephemeralMark(a.page, user.id)).toBeUndefined();

  // The box was ticked: a session of about 60 days (the API's clock is pinned to E2E_NOW, and
  // the browser may count from either).
  const { expires } = await sessionCookie(a.context);
  const from = [Date.parse(E2E_NOW) / 1000, Date.now() / 1000];
  expect(
    from.some((now) => Math.abs(expires - now - 60 * DAY_S) < DAY_S),
    `expires ${new Date(expires * 1000).toISOString()}`,
  ).toBe(true);

  await a.context.close();
});

test("the recovery key signs in on a new browser", async ({ browser }) => {
  test.setTimeout(90_000);
  if (!phone) throw new Error("the first test makes the account");

  const c = await openBrowser(browser);
  await c.page.goto("/sign-in");
  // The recovery key waits under "Más opciones"; opening it shows the field directly.
  await c.page.getByRole("button", { name: "Más opciones" }).click();
  // Typed the way people type it: lower case, spaces for the dashes.
  await c.page
    .getByRole("textbox", { name: "Tu clave de recuperación" })
    .fill(phone.recoveryKey.replaceAll("-", " ").toLowerCase());
  await c.page.getByRole("button", { name: "Entrar con la clave" }).click();

  await expect(c.page).toHaveURL(/\/app$/, { timeout: 30_000 });
  await expect(c.page.getByText(NAME, { exact: true })).toBeVisible();
  expect(await vaultDatabases(c.page)).toEqual([`wambito-vault-${phone.userId}`]);

  await c.context.close();
});

test("unticked: the cookie has no expiry, and once it is gone the app leaves no vault", async ({
  browser,
}) => {
  test.setTimeout(90_000);
  if (!phone) throw new Error("the first test makes the account");

  const d = await openBrowser(browser);
  await d.page.goto("/sign-in");
  const first = (await qrCode(d.page).innerText()).trim();
  await d.page
    .getByRole("checkbox", { name: "Mantener la sesión abierta en este navegador" })
    .uncheck();
  await expect(
    d.page.getByText("No queda nada en este computador cuando cierres el navegador"),
  ).toBeVisible();
  // Unticking opens a new request: the phone approves that one.
  let code = first;
  await expect
    .poll(
      async () => {
        code = (
          await qrCode(d.page)
            .innerText({ timeout: 2_000 })
            .catch(() => first)
        ).trim();
        return code;
      },
      { timeout: 15_000 },
    )
    .not.toBe(first);
  await approve(code);

  await expect(d.page).toHaveURL(/\/app$/, { timeout: 30_000 });
  await expect(d.page.getByText(NAME, { exact: true })).toBeVisible();
  expect(await vaultDatabases(d.page)).toEqual([`wambito-vault-${phone.userId}`]);
  // Unticked: the vault is marked, so a sweep may take it.
  expect(await ephemeralMark(d.page, phone.userId)).toBe(true);
  // A session cookie: it ends with the browser.
  expect((await sessionCookie(d.context)).expires).toBe(-1);

  // The browser closed (its session cookies gone): the next page sweeps the ephemeral vault.
  await d.context.clearCookies();
  await d.page.goto("/sign-in");
  await expect(qrCode(d.page)).toBeVisible();
  await expect.poll(() => vaultDatabases(d.page), { timeout: 15_000 }).toEqual([]);

  await d.context.close();
});
