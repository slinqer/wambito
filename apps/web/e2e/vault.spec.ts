import { execFileSync } from "node:child_process";
import {
  type Browser,
  type BrowserContext,
  type CDPSession,
  expect,
  type Page,
  test,
} from "@playwright/test";
import { clientIp, pinClock, signInExisting } from "./helpers.ts";

/**
 * An encrypted preview account (stage 2a) against the dev stack, signed in as the seeded
 * `preview-e2e` (preview@wambito.test; the stack's E2E_PREVIEW_USER_IDS lists it by default). Its
 * finances live as encrypted records in the browser's IndexedDB and sync through /v2/sync:
 * - a first browser sets up the recovery key, adds a movement and finds it again after a reload;
 * - a second browser opens the vault with the recovery key and sees the movement;
 * - an edit made offline in the first reaches the second once back online;
 * - signing out leaves no `wambito-vault-*` database behind.
 * The spec resets the account first (`seed:e2e-preview` in the api container: the user is made
 * again, so no records, key wraps or finance rows are left from an earlier run).
 */

const EMAIL = "preview@wambito.test";
const USER_ID = "preview-e2e";
const NAME = "cena vault";

test.describe.configure({ mode: "serial" });
test.use({ actionTimeout: 10_000 });
// One preview account for the whole suite (its sign-in codes and its vault would cross between the
// projects running at once), so it runs on the desktop project only: the whole file is skipped on
// the phone, and its beforeAll (the reseed) returns there, so it never resets the account under
// the desktop run.
test.skip(({ isMobile }) => isMobile, "one preview account per run, desktop only");

const vaultDatabases = (page: Page) =>
  page.evaluate(async () =>
    (await indexedDB.databases())
      .map((d) => d.name ?? "")
      .filter((n) => n.startsWith("wambito-vault-")),
  );

/** The recovery key from the setup screen, then the four characters it asks back. */
async function setUpRecoveryKey(page: Page): Promise<string> {
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

/** Makes the preview account again: no records, key wraps, passkeys or finance rows. */
function reseed() {
  execFileSync(
    "docker",
    ["compose", "exec", "-T", "api", "pnpm", "--filter", "@wambito/api", "seed:e2e-preview"],
    { stdio: "inherit" },
  );
}

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

/** Adds an expense of `digits` (cents typed on the keypad) named `name`, in Supermercado. */
async function addMovement(page: Page, name: string, digits: string[]) {
  await page.getByRole("button", { name: "Agregar", exact: true }).click();
  const sheet = page.getByRole("dialog", { name: "Nuevo gasto" });
  const keypad = sheet.getByRole("group", { name: "Teclado numérico" });
  for (const digit of digits) {
    await keypad.getByRole("button", { name: digit, exact: true }).click();
  }
  await sheet.getByRole("textbox", { name: "Nombre (opcional)" }).fill(name);
  await sheet
    .getByRole("group", { name: "Categoría" })
    .getByRole("button", { name: "Supermercado" })
    .click();
  await sheet.getByRole("button", { name: "Guardar" }).click();
  await expect(sheet).toBeHidden();
  await expect(page.getByText(name, { exact: true })).toBeVisible();
}

/**
 * The first browser of a fresh account: signs in, sets up the recovery key, skips onboarding and
 * adds the movement `NAME` (42). Returns the recovery key.
 */
async function firstBrowser(opened: Opened): Promise<string> {
  await signInExisting(opened.page, EMAIL);
  const key = await setUpRecoveryKey(opened.page);
  await opened.page.getByRole("button", { name: "Entrar directo" }).click();
  await expect(opened.page).toHaveURL(/\/app$/);
  await addMovement(opened.page, NAME, ["4", "2"]);
  return key;
}

/** Another browser opens the vault with the recovery key and sees `NAME`. */
async function unlockWithKey(opened: Opened, key: string) {
  await signInExisting(opened.page, EMAIL);
  await expect(opened.page.getByRole("heading", { name: "Abre tus datos aquí" })).toBeVisible();
  await opened.page.getByRole("textbox", { name: "Clave de recuperación" }).fill(key);
  await opened.page.getByRole("button", { name: "Abrir mis datos" }).click();
  await expect(opened.page).toHaveURL(/\/app$/);
  await expect(opened.page.getByText(NAME, { exact: true })).toBeVisible();
}

/** The sync's triggers (back online, focus): a push and a pull soon after. */
const nudgeSync = (page: Page) =>
  page.evaluate(() => {
    window.dispatchEvent(new Event("online"));
    window.dispatchEvent(new Event("focus"));
  });

/** Settings → Security of an open vault. */
async function openSecurity(page: Page) {
  await page.goto("/app/settings");
  await expect(page.getByRole("heading", { name: "Seguridad" })).toBeVisible();
}

/**
 * A software authenticator whose passkeys give the WebAuthn PRF (`hmac-secret`), on Chrome's
 * WebAuthn domain over CDP; returns the session and its id, to read or add credentials.
 */
async function prfAuthenticator(page: Page): Promise<{ cdp: CDPSession; authenticatorId: string }> {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("WebAuthn.enable");
  const { authenticatorId } = await cdp.send("WebAuthn.addVirtualAuthenticator", {
    options: {
      protocol: "ctap2",
      transport: "internal",
      hasResidentKey: true,
      hasUserVerification: true,
      isUserVerified: true,
      hasPrf: true,
      automaticPresenceSimulation: true,
    },
  });
  return { cdp, authenticatorId };
}

/** What the vault's IndexedDB keeps as its key version (`meta.keyV`), and its record key names. */
const vaultKeys = (page: Page) =>
  page.evaluate(async (name) => {
    const db = await new Promise<IDBDatabase>((resolve, reject) => {
      const open = indexedDB.open(name);
      open.onsuccess = () => resolve(open.result);
      open.onerror = () => reject(open.error);
    });
    const read = <T>(store: string, op: (s: IDBObjectStore) => IDBRequest<T>) =>
      new Promise<T>((resolve, reject) => {
        const request = op(db.transaction(store, "readonly").objectStore(store));
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
    const keyV = await read("meta", (s) => s.get("keyV"));
    const names = await read("keys", (s) => s.getAllKeys());
    db.close();
    return { keyV, names: names.map(String).sort() };
  }, `wambito-vault-${USER_ID}`);

test("a recovery key, a second browser, an offline edit and a clean sign-out", async ({
  browser,
}) => {
  test.setTimeout(90_000);

  const open = async () => {
    const context = await browser.newContext({
      locale: "es-ES",
      timezoneId: "Europe/Madrid",
      viewport: { width: 1280, height: 800 },
      extraHTTPHeaders: { "x-forwarded-for": clientIp() },
    });
    const page = await context.newPage();
    await pinClock(page);
    return { context, page };
  };

  // -- first browser: recovery key, onboarding, a movement, a reload ---------------------------
  const first = await open();
  await signInExisting(first.page, EMAIL);
  const key = await setUpRecoveryKey(first.page);
  await first.page.getByRole("button", { name: "Entrar directo" }).click();
  await expect(first.page).toHaveURL(/\/app$/);
  expect(await vaultDatabases(first.page)).toEqual([`wambito-vault-${USER_ID}`]);

  await first.page.getByRole("button", { name: "Agregar", exact: true }).click();
  const sheet = first.page.getByRole("dialog", { name: "Nuevo gasto" });
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
  await expect(first.page.getByText(NAME, { exact: true })).toBeVisible();

  await first.page.reload();
  await expect(first.page.getByText(NAME, { exact: true })).toBeVisible();

  // -- second browser: unlock with the recovery key, same movement -----------------------------
  const second = await open();
  await signInExisting(second.page, EMAIL);
  await expect(second.page.getByRole("heading", { name: "Abre tus datos aquí" })).toBeVisible();
  await second.page.getByRole("textbox", { name: "Clave de recuperación" }).fill(key);
  await second.page.getByRole("button", { name: "Abrir mis datos" }).click();
  await expect(second.page).toHaveURL(/\/app$/);
  await expect(second.page.getByText(NAME, { exact: true })).toBeVisible();

  // -- an edit made offline reaches the second browser once the first is back online -----------
  await first.context.setOffline(true);
  await first.page.getByRole("button", { name: new RegExp(`^${NAME} `) }).click();
  const edit = first.page.getByRole("dialog", { name: "Editar movimiento" });
  await edit.getByRole("textbox", { name: "Nombre (opcional)" }).fill(`${NAME} editada`);
  await edit.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(edit).toBeHidden();
  await expect(first.page.getByText(`${NAME} editada`, { exact: true })).toBeVisible();
  await first.context.setOffline(false);
  // The first browser pushes on its next trigger (back online, focus); the second pulls on reload.
  await first.page.evaluate(() => {
    window.dispatchEvent(new Event("online"));
    window.dispatchEvent(new Event("focus"));
  });
  await expect(async () => {
    await second.page.reload();
    await expect(second.page.getByText(`${NAME} editada`, { exact: true })).toBeVisible({
      timeout: 2_000,
    });
  }).toPass({ timeout: 30_000 });

  // -- sign out leaves nothing of the vault in the browser -------------------------------------
  await first.page.getByRole("button", { name: "Tu cuenta" }).click();
  await first.page.getByRole("button", { name: "Cerrar sesión" }).click();
  await expect(first.page).toHaveURL(/\/(sign-in)?(\?|$)/);
  await expect.poll(() => vaultDatabases(first.page)).toEqual([]);

  await first.context.close();
  await second.context.close();
});

test("a second browser unlocks by pairing", async ({ browser }) => {
  test.setTimeout(120_000);
  reseed();

  const first = await openBrowser(browser);
  await firstBrowser(first);

  // -- the new browser asks: Unlock → "From another device" shows the code ---------------------
  const second = await openBrowser(browser);
  await signInExisting(second.page, EMAIL);
  await expect(second.page.getByRole("heading", { name: "Abre tus datos aquí" })).toBeVisible();
  await second.page.getByRole("button", { name: "Desde otro dispositivo" }).click();
  await expect(
    second.page.getByRole("heading", { name: "Abre tus datos desde otro dispositivo" }),
  ).toBeVisible();
  const shown = second.page.getByText(/^[0-9A-Z]{4} [0-9A-Z]{4}$/);
  await expect(shown).toBeVisible();
  const code = (await shown.innerText()).trim();

  // -- the first approves: Settings → Security → "Approve a new device", the code ---------------
  await openSecurity(first.page);
  await first.page.getByRole("button", { name: "Aprobar un dispositivo nuevo" }).click();
  const approve = first.page.getByRole("dialog", { name: "Aprobar un dispositivo nuevo" });
  await approve.getByRole("textbox", { name: "Código del dispositivo nuevo" }).fill(code);
  await approve.getByRole("button", { name: "Continuar" }).click();

  // -- both show the same number; the first confirms -------------------------------------------
  const number = /^\d{3} \d{3}$/;
  await expect(approve.getByText(number)).toBeVisible({ timeout: 20_000 });
  await expect(second.page.getByText(number)).toBeVisible({ timeout: 20_000 });
  const onFirst = await approve.getByText(number).innerText();
  expect(await second.page.getByText(number).innerText()).toBe(onFirst);
  await approve.getByRole("button", { name: "Coinciden", exact: true }).click();
  await expect(approve.getByRole("heading", { name: "Listo" })).toBeVisible();

  // -- the new browser opens on the first one's movements --------------------------------------
  await expect(second.page).toHaveURL(/\/app$/, { timeout: 20_000 });
  await expect(second.page.getByText(NAME, { exact: true })).toBeVisible();
  expect(await vaultDatabases(second.page)).toEqual([`wambito-vault-${USER_ID}`]);

  await first.context.close();
  await second.context.close();
});

test("a passkey unlocks with PRF", async ({ browser }) => {
  test.setTimeout(120_000);
  reseed();

  // -- the first browser adds a passkey through Settings; its row says it opens the data --------
  const first = await openBrowser(browser);
  await firstBrowser(first);
  const authenticator = await prfAuthenticator(first.page);
  await openSecurity(first.page);
  await first.page.getByRole("button", { name: "Agregar una huella" }).click();
  await expect(first.page.getByText("Listo: ya puedes entrar con tu huella.")).toBeVisible();
  const row = first.page.getByRole("listitem").filter({ hasText: "Creada el" });
  await expect(row).toHaveCount(1);
  await expect(row.getByText("Abre tus datos", { exact: true })).toBeVisible();
  await expect(row.getByText("No abre tus datos")).toHaveCount(0);

  // -- a browser without the vault signs in with that passkey and lands on the movements -------
  // The brief's second browser would hold a copy of the credential (`WebAuthn.getCredentials`,
  // then `addCredential`), but CDP's `Credential` carries no PRF secret: Chromium's copy answers
  // without PRF (`no_prf` on Unlock's "Use a passkey", seen on this Chromium). So the same
  // browser, signed out (which wipes its vault), stands in for a new one: same authenticator,
  // nothing of the data left in IndexedDB.
  // Sign-out lands on the sign-in page, which asks the browser for this site's passkeys as it
  // opens (autofill): the authenticator answers no one (no presence) until the wiped vault has
  // been checked. Then "Entrar con huella" (this browser registered a passkey) and a touch, with
  // the PRF that opens the passkey's wrap.
  await authenticator.cdp.send("WebAuthn.setAutomaticPresenceSimulation", {
    authenticatorId: authenticator.authenticatorId,
    enabled: false,
  });
  await first.page.goto("/app");
  await first.page.getByRole("button", { name: "Tu cuenta" }).click();
  await first.page.getByRole("button", { name: "Cerrar sesión" }).click();
  await expect(first.page).toHaveURL(/\/sign-in(\?|$)/);
  await expect.poll(() => vaultDatabases(first.page)).toEqual([]);
  await authenticator.cdp.send("WebAuthn.setAutomaticPresenceSimulation", {
    authenticatorId: authenticator.authenticatorId,
    enabled: true,
  });
  await first.page.getByRole("button", { name: "Entrar con huella" }).click();
  await expect(first.page).toHaveURL(/\/app$/, { timeout: 20_000 });
  await expect(first.page.getByText(NAME, { exact: true })).toBeVisible();
  await expect(first.page.getByRole("heading", { name: "Abre tus datos aquí" })).toHaveCount(0);
  expect(await vaultDatabases(first.page)).toEqual([`wambito-vault-${USER_ID}`]);

  await first.context.close();
});

test("a conflict merges field by field", async ({ browser }) => {
  test.setTimeout(120_000);
  reseed();

  const first = await openBrowser(browser);
  const key = await firstBrowser(first);
  const second = await openBrowser(browser);
  await unlockWithKey(second, key);

  const editSheet = (page: Page) => page.getByRole("dialog", { name: "Editar movimiento" });
  const openEdit = async (page: Page) => {
    await page.getByRole("button", { name: new RegExp(`^${NAME} `) }).click();
    await expect(editSheet(page)).toBeVisible();
    return editSheet(page);
  };

  // -- both offline: the first changes the note, the second the amount -------------------------
  await first.context.setOffline(true);
  await second.context.setOffline(true);

  const a = await openEdit(first.page);
  await a.getByRole("button", { name: /^Más opciones/ }).click();
  await a.getByRole("textbox", { name: "Nota (opcional)" }).fill("nota de A");
  await a.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(a).toBeHidden();

  const b = await openEdit(second.page);
  const keypad = b.getByRole("group", { name: "Teclado numérico" });
  for (let i = 0; i < 2; i++) {
    await keypad.getByRole("button", { name: "Borrar dígito" }).click();
  }
  for (const digit of ["7", "5"]) {
    await keypad.getByRole("button", { name: digit, exact: true }).click();
  }
  await expect(b.getByTestId("amount")).toContainText("75");
  await b.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(b).toBeHidden();

  // -- both back online: the first pushes, the second's push meets it and merges --------------
  await first.context.setOffline(false);
  await nudgeSync(first.page);
  await second.context.setOffline(false);
  await nudgeSync(second.page);

  // Each pulls on reload; the row shows B's amount, the sheet A's note (in "Más opciones", read
  // closed: the field is there, hidden).
  for (const { page } of [first, second, first]) {
    await expect(async () => {
      await page.reload();
      await expect(page.getByRole("button", { name: `${NAME} −75,00 € Supermercado` })).toBeVisible(
        { timeout: 2_000 },
      );
      // Left open: the next reload closes it.
      const sheet = await openEdit(page);
      await expect(
        sheet.getByRole("textbox", { name: "Nota (opcional)", includeHidden: true }),
      ).toHaveValue("nota de A", { timeout: 2_000 });
    }).toPass({ timeout: 30_000 });
  }

  await first.context.close();
  await second.context.close();
});

test("a removed browser locks", async ({ browser }) => {
  test.setTimeout(120_000);
  reseed();

  const first = await openBrowser(browser);
  const key = await firstBrowser(first);
  const second = await openBrowser(browser);
  await unlockWithKey(second, key);
  expect((await vaultKeys(first.page)).keyV).toBe(1);

  // -- the first removes the second, with the recovery key typed --------------------------------
  await openSecurity(first.page);
  const devices = first.page.getByRole("button", { name: /^Quitar / });
  await expect(devices).toHaveCount(1);
  await devices.click();
  const sheet = first.page.getByRole("dialog", { name: /^¿Quitar / });
  await sheet.getByRole("textbox", { name: "Clave de recuperación" }).fill(key);
  await sheet.getByRole("button", { name: "Sí, quitarlo" }).click();
  await expect(first.page.getByRole("dialog", { name: "Listo" })).toBeVisible({
    timeout: 20_000,
  });
  await expect(first.page.getByText(/ya no puede abrir tus datos\.$/)).toBeVisible();

  // -- the second, on its next sync, is locked out with the notice; nothing of the vault stays --
  await expect(async () => {
    await nudgeSync(second.page);
    await expect(
      second.page.getByRole("status").filter({ hasText: "Este navegador se eliminó de tu cuenta" }),
    ).toBeVisible({ timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
  await expect(second.page.getByRole("heading", { name: "Abre tus datos aquí" })).toBeVisible();
  await expect.poll(() => vaultDatabases(second.page)).toEqual([]);

  // -- the first still opens its movements after a reload, now at key version 2 ---------------
  await first.page.goto("/app");
  await first.page.reload();
  await expect(first.page.getByText(NAME, { exact: true })).toBeVisible();
  const after = await vaultKeys(first.page);
  expect(after.keyV).toBe(2);
  expect(after.names).toContain("record:2");

  await first.context.close();
  await second.context.close();
});
