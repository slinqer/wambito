import { execFileSync } from "node:child_process";
import { expect, type Page, test } from "@playwright/test";
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
  const boxes = page.getByRole("textbox", { name: /^Carácter \d+$/ });
  for (const box of await boxes.all()) {
    const n = Number(/(\d+)$/.exec((await box.getAttribute("aria-label")) ?? "")?.[1]);
    await box.fill(plain[n - 1] ?? "");
  }
  await page.getByRole("button", { name: "Continuar" }).click();
  return key;
}

test.beforeAll(async () => {
  execFileSync(
    "docker",
    ["compose", "exec", "-T", "api", "pnpm", "--filter", "@wambito/api", "seed:e2e-preview"],
    { stdio: "inherit" },
  );
});

test("a recovery key, a second browser, an offline edit and a clean sign-out", async ({
  browser,
}, testInfo) => {
  // One preview account for the whole suite (its sign-in codes and its vault would cross between
  // the two projects running at once), so this runs at one size only.
  test.setTimeout(90_000);
  test.skip(testInfo.project.name !== "desktop", "one preview account per run (see above)");

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
