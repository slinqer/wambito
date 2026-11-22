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

/** One category's page from the menu: its row, then its own URL and heading. */
async function openCategory(page: Page, row: RegExp, slug: string, heading: string) {
  await page.getByRole("navigation", { name: "Ajustes" }).getByRole("link", { name: row }).click();
  await expect(page).toHaveURL(new RegExp(`/app/settings/${slug}$`));
  await expect(page.getByRole("heading", { level: 1, name: heading })).toBeVisible();
}

/** Idioma or Tema: the row opens its choice sheet; the pick closes it. */
async function choose(page: Page, row: RegExp, sheet: string, choice: string) {
  await page.getByRole("button", { name: row }).click();
  const dialog = page.getByRole("dialog", { name: sheet });
  await dialog.getByRole("radio", { name: choice }).click();
  await expect(dialog).toHaveCount(0);
}

let email: string;

test.beforeEach(async ({ page }) => {
  await pinClock(page);
  email = await signUpNewUser(page);
  await onboardWithSample(page, "Europe/Madrid");
});

test("settings opens on the menu of five categories, each with its line", async ({ page }) => {
  await openSettings(page);
  const menu = page.getByRole("navigation", { name: "Ajustes" });
  const rows = [
    ["Mis agentes", "ChatGPT · Claude · Lumo+ · Grok"],
    ["Cuenta y seguridad", "Passkeys, dispositivos, clave"],
    ["Preferencias", "Español · Noche · EUR"],
    ["Tus datos", "Importar, exportar"],
    ["Más", "Comentarios"],
  ] as const;
  await expect(menu.getByRole("link")).toHaveCount(rows.length);
  for (const [title, line] of rows) {
    await expect(menu.getByRole("link", { name: `${title} ${line}` })).toBeVisible();
  }
  // The cards live in their categories, not on the menu.
  await expect(page.getByRole("radio", { name: "English" })).toHaveCount(0);
});

test("each category opens on its own URL and back returns to the menu", async ({ page }) => {
  await openSettings(page);
  const pages = [
    [/^Mis agentes/, "agents", "Mis agentes"],
    [/^Cuenta y seguridad/, "account", "Cuenta y seguridad"],
    [/^Preferencias/, "preferences", "Preferencias"],
    [/^Tus datos/, "data", "Tus datos"],
    [/^Más/, "more", "Más"],
  ] as const;
  for (const [row, slug, heading] of pages) {
    await openCategory(page, row, slug, heading);
    await page.getByRole("link", { name: "Volver a Ajustes" }).click();
    await expect(page).toHaveURL(/\/app\/settings$/);
    await expect(page.getByRole("heading", { level: 1, name: "Ajustes" })).toBeVisible();
  }
  // An address that is no category says so.
  await page.goto("/app/settings/nope");
  await expect(
    page.getByRole("heading", { level: 1, name: "No encontramos esa sección" }),
  ).toBeVisible();
});

test("a reload on /app/settings/preferences stays there", async ({ page }) => {
  await openSettings(page);
  await openCategory(page, /^Preferencias/, "preferences", "Preferencias");
  await page.reload();
  await expect(page).toHaveURL(/\/app\/settings\/preferences$/);
  await expect(page.getByRole("heading", { level: 1, name: "Preferencias" })).toBeVisible();
  await expect(page.getByRole("button", { name: /^Idioma/ })).toContainText("Español");
});

test("switching to English re-renders at once, and home speaks it after a reload", async ({
  page,
}) => {
  await openSettings(page);
  await openCategory(page, /^Preferencias/, "preferences", "Preferencias");
  await choose(page, /^Idioma/, "Idioma", "English");
  await expect(page.getByRole("heading", { level: 1, name: "Preferences" })).toBeVisible();
  await expect(page.locator("html")).toHaveAttribute("lang", "en");
  await expect
    .poll(
      async () =>
        ((await (await page.request.get("/api/v1/me")).json()) as { locale: string }).locale,
    )
    .toBe("en");

  await page.getByRole("link", { name: "Back to Settings" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Settings" })).toBeVisible();
  await page.getByRole("link", { name: "Back to home" }).click();
  await expect(page.getByRole("region", { name: "Left this month" })).toBeVisible();
  await page.reload();
  await expect(page.getByRole("region", { name: "Left this month" })).toBeVisible();
});

test("the language picker lists the four languages, and Italian and Portuguese re-render at once", async ({
  page,
}) => {
  await openSettings(page);
  await openCategory(page, /^Preferencias/, "preferences", "Preferencias");
  await page.getByRole("button", { name: /^Idioma/ }).click();
  const languages = page.getByRole("dialog", { name: "Idioma" });
  for (const name of ["Español", "English", "Italiano", "Português"]) {
    await expect(languages.getByRole("radio", { name })).toBeVisible();
  }
  await languages.getByRole("radio", { name: "Italiano" }).click();
  await expect(languages).toHaveCount(0);
  await expect(page.getByRole("heading", { level: 1, name: "Preferenze" })).toBeVisible();
  await expect(page.locator("html")).toHaveAttribute("lang", "it");
  await choose(page, /^Lingua/, "Lingua", "Português");
  await expect(page.getByRole("heading", { level: 1, name: "Preferências" })).toBeVisible();
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
  await openCategory(page, /^Preferencias/, "preferences", "Preferencias");
  await expect(page.locator("html")).toHaveAttribute("data-theme", "night");
  await choose(page, /^Tema/, "Tema", "Día");
  await expect(page.locator("html")).toHaveAttribute("data-theme", "day");
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "day");
  await expect(page.getByRole("button", { name: /^Tema/ })).toContainText("Día");
});

test("deleting the account signs out to the landing; the same email then starts afresh", async ({
  page,
}) => {
  const before = await sessionUser(page);
  expect(before?.email).toBe(email);
  const firstMail = await readSignInMail(email);

  await openSettings(page);
  await openCategory(page, /^Cuenta y seguridad/, "account", "Cuenta y seguridad");
  await page.getByRole("button", { name: /^Eliminar tu cuenta/ }).click();
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
  await openCategory(page, /^Cuenta y seguridad/, "account", "Cuenta y seguridad");
  const keys = page.getByRole("group", { name: "Entrar con tu huella" });
  await expect(keys).toContainText("Aún no tienes ninguna");
  await keys.getByRole("button", { name: "Agregar una huella" }).click();
  await expect(page.getByRole("status")).toContainText("Listo: ya puedes entrar con tu huella.");
  const trash = keys.getByRole("button", { name: /^Eliminar / });
  await expect(trash).toHaveCount(1);
  // Dated by the server's clock (the page's is pinned).
  await expect(keys).toContainText(/Desde el \d{1,2} \w{3} \d{4}/);

  await trash.click();
  await page
    .getByRole("dialog", { name: "¿Eliminar esta huella?" })
    .getByRole("button", { name: "Sí, eliminar" })
    .click();
  await expect(trash).toHaveCount(0);
  await expect(keys).toContainText("Aún no tienes ninguna");
  // With no passkey left, the sign-in screen no longer offers the fingerprint here.
  expect(await page.evaluate(() => localStorage.getItem("wambito.passkey.used"))).toBe("0");
});

test("the export downloads the server's CSV and JSON under their own names", async ({ page }) => {
  await openSettings(page);
  await openCategory(page, /^Tus datos/, "data", "Tus datos");
  await page.getByRole("button", { name: /^Descargar tus datos/ }).click();
  const data = page.getByRole("dialog", { name: "Descarga tus datos" });
  const [csv] = await Promise.all([
    page.waitForEvent("download"),
    data.getByRole("button", { name: "Descargar CSV" }).click(),
  ]);
  expect(csv.suggestedFilename()).toMatch(/^wambito-export-\d{4}-\d{2}-\d{2}\.csv$/);
  const text = await (await csv.createReadStream()).toArray();
  expect(Buffer.concat(text).toString("utf8")).toMatch(/^date,name,amount,currency,category/);

  // A download closes the sheet: open it again for the JSON.
  await expect(data).toHaveCount(0);
  await page.getByRole("button", { name: /^Descargar tus datos/ }).click();
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
  await expect(page).toHaveURL(/\/app\/settings\/data$/);
});
