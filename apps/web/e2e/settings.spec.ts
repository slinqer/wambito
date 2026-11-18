import { expect, type Page, test } from "@playwright/test";
import {
  addVirtualAuthenticator,
  clientIp,
  onboardWithSample,
  pinClock,
  readSignInMail,
  seedPlainUser,
  sessionUser,
  signUpNewUser,
  skipPasskeyOffer,
} from "./helpers.ts";

/**
 * Settings (spec §2.7) against the dev stack: a new user who imported the sample Budge file
 * switches to English, switches to the day theme, and deletes their account; signing in again
 * with the same email starts a brand-new account.
 */

test.use({
  locale: "es-ES",
  timezoneId: "Europe/Madrid",
  extraHTTPHeaders: async ({ extraHTTPHeaders }, use) =>
    use({ ...extraHTTPHeaders, "x-forwarded-for": clientIp() }),
});

const isPhone = (page: Page) => (page.viewportSize()?.width ?? 0) < 1024;

/** Ajustes lives in the avatar menu on phones and in the sidebar on wide screens. */
async function openSettings(page: Page) {
  await page.goto("/app");
  if (isPhone(page)) {
    await page.getByRole("button", { name: "Tu cuenta" }).click();
    await page.locator(".lk-menu").getByRole("link", { name: "Ajustes" }).click();
  } else {
    await page
      .getByRole("navigation", { name: "Navegación principal" })
      .getByRole("link", { name: "Ajustes" })
      .click();
  }
  await expect(page).toHaveURL(/\/app\/settings$/);
  await expect(page.getByRole("heading", { level: 1, name: "Ajustes" })).toBeVisible();
}

let email: string;

test.beforeEach(async ({ page }) => {
  await pinClock(page);
  email = await signUpNewUser(page);
  await onboardWithSample(page, "Europe/Madrid");
});

test("switching to English re-renders at once, and home speaks it after a reload", async ({
  page,
}) => {
  await openSettings(page);
  await page.getByRole("radio", { name: "English" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Settings" })).toBeVisible();
  await expect(page.locator("html")).toHaveAttribute("lang", "en");
  await expect
    .poll(
      async () =>
        ((await (await page.request.get("/api/v1/me")).json()) as { locale: string }).locale,
    )
    .toBe("en");

  await page.getByRole("link", { name: "Back to home" }).click();
  await expect(page.getByRole("region", { name: "Left this month" })).toBeVisible();
  await page.reload();
  await expect(page.getByRole("region", { name: "Left this month" })).toBeVisible();
});

test("the language picker lists the four languages, and Italian and Portuguese re-render at once", async ({
  page,
}) => {
  await openSettings(page);
  for (const name of ["Español", "English", "Italiano", "Português"]) {
    await expect(page.getByRole("radio", { name })).toBeVisible();
  }
  await page.getByRole("radio", { name: "Italiano" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Impostazioni" })).toBeVisible();
  await expect(page.locator("html")).toHaveAttribute("lang", "it");
  await page.getByRole("radio", { name: "Português" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Definições" })).toBeVisible();
  await expect(page.locator("html")).toHaveAttribute("lang", "pt");
  await expect
    .poll(
      async () =>
        ((await (await page.request.get("/api/v1/me")).json()) as { locale: string }).locale,
    )
    .toBe("pt");
});

test("the day theme applies at once and stays after a reload", async ({ page }) => {
  await openSettings(page);
  await expect(page.locator("html")).toHaveAttribute("data-theme", "night");
  await page.getByRole("radio", { name: "Día" }).click();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "day");
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "day");
  await expect(page.getByRole("radio", { name: "Día" })).toBeChecked();
});

test("deleting the account signs out to the landing; the same email then starts afresh", async ({
  page,
}) => {
  const before = await sessionUser(page);
  expect(before?.email).toBe(email);
  const firstMail = await readSignInMail(email);

  await openSettings(page);
  await page.getByRole("button", { name: "Eliminar mi cuenta" }).click();
  const sheet = page.getByRole("dialog", { name: "¿Eliminar tu cuenta?" });
  const confirm = sheet.getByRole("button", { name: "Sí, eliminar mi cuenta" });
  await expect(confirm).toBeDisabled();
  await sheet
    .getByRole("textbox", { name: "Escribe tu correo para confirmar" })
    .fill(`  ${email.toUpperCase()} `);
  await confirm.click();

  await expect(page).toHaveURL(/\/$/);
  expect(await sessionUser(page)).toBeNull();

  // The stack makes new users encrypted: the same email starts afresh as a plain user again.
  seedPlainUser(email);
  await page.goto("/sign-in?lang=es");
  await page.getByRole("textbox", { name: "Tu correo" }).fill(email);
  await page.getByRole("button", { name: "Enviar código" }).click();
  const mail = await readSignInMail(email, { skip: [firstMail.id] });
  await page.getByRole("textbox", { name: "Dígito 1 de 6" }).fill(mail.code);
  await skipPasskeyOffer(page);
  await expect(page).toHaveURL(/\/welcome$/);
  const after = await sessionUser(page);
  expect(after?.email).toBe(email);
  expect(after?.id).not.toBe(before?.id);
  const transactions = (await (await page.request.get("/api/v1/transactions?limit=1")).json()) as {
    items: unknown[];
  };
  expect(transactions.items).toHaveLength(0);
});

test("a passkey added from settings is listed, and deleting it empties the list", async ({
  page,
}) => {
  await addVirtualAuthenticator(page);
  await openSettings(page);
  const keys = page.getByRole("region", { name: "Entrar con tu huella" });
  await expect(keys).toContainText("Aún no tienes ninguna");
  await keys.getByRole("button", { name: "Agregar una huella" }).click();
  await expect(page.getByRole("status")).toContainText("Listo: ya puedes entrar con tu huella.");
  await expect(keys.getByRole("listitem")).toHaveCount(1);
  // Dated by the server's clock (the page's is pinned).
  await expect(keys.getByRole("listitem")).toContainText(/Creada el \d{1,2} \w{3} \d{4}/);

  await keys.getByRole("button", { name: /^Eliminar / }).click();
  await page
    .getByRole("dialog", { name: "¿Eliminar esta huella?" })
    .getByRole("button", { name: "Sí, eliminar" })
    .click();
  await expect(keys.getByRole("listitem")).toHaveCount(0);
  await expect(keys).toContainText("Aún no tienes ninguna");
  // With no passkey left, the sign-in screen no longer offers the fingerprint here.
  expect(await page.evaluate(() => localStorage.getItem("wambito.passkey.used"))).toBe("0");
});

test("the export downloads the server's CSV and JSON under their own names", async ({ page }) => {
  await openSettings(page);
  const data = page.getByRole("region", { name: "Tus datos" });
  const [csv] = await Promise.all([
    page.waitForEvent("download"),
    data.getByRole("button", { name: "Descargar CSV" }).click(),
  ]);
  expect(csv.suggestedFilename()).toMatch(/^wambito-export-\d{4}-\d{2}-\d{2}\.csv$/);
  const text = await (await csv.createReadStream()).toArray();
  expect(Buffer.concat(text).toString("utf8")).toMatch(/^date,name,amount,currency,category/);

  const [json] = await Promise.all([
    page.waitForEvent("download"),
    data.getByRole("button", { name: "Descargar JSON" }).click(),
  ]);
  expect(json.suggestedFilename()).toMatch(/^wambito-export-\d{4}-\d{2}-\d{2}\.json$/);
  const body = JSON.parse(
    Buffer.concat(await (await json.createReadStream()).toArray()).toString("utf8"),
  ) as {
    user: { email: string };
    transactions: unknown[];
  };
  expect(body.user.email).toBe(email);
  expect(body.transactions.length).toBeGreaterThan(0);
  await expect(page).toHaveURL(/\/app\/settings$/);
});
