import { expect, test } from "@playwright/test";
import {
  addVirtualAuthenticator,
  clientIp,
  readSignInMail,
  sessionUser,
  signUpNewUser,
  skipPasskeyOffer,
} from "./helpers.ts";

/**
 * The admin panel (spec docs/superpowers/specs/2026-11-04-admin-panel-design.md) against the dev
 * stack, signed in as the seeded admin (`dev-admin`, admin@wambito.test:
 * `docker compose exec -T api pnpm --filter @wambito/api seed:admin`; the stack's ADMIN_USER_IDS
 * lists it). The admin adds a passkey in settings with a software authenticator, confirms with it
 * on /admin, finds a fresh user by email and suspends them. Someone who is not an admin gets the
 * ordinary not-found page.
 */

const ADMIN_EMAIL = "admin@wambito.test";

test.use({
  locale: "es-ES",
  timezoneId: "Europe/Madrid",
  extraHTTPHeaders: async ({ extraHTTPHeaders }, use) =>
    use({ ...extraHTTPHeaders, "x-forwarded-for": clientIp() }),
});

/** The ids of the emails already in Mailpit for `email`, so a new code is never an old one. */
async function mailIds(email: string): Promise<string[]> {
  const response = await fetch(
    `${process.env.MAILPIT_URL ?? "http://localhost:8025"}/api/v1/messages?limit=200`,
  );
  const { messages } = (await response.json()) as {
    messages: { ID: string; To: { Address: string }[] }[];
  };
  return messages.filter((m) => m.To.some((to) => to.Address === email)).map((m) => m.ID);
}

test("the admin confirms with a passkey, finds a user by email and suspends them", async ({
  page,
  browser,
}, testInfo) => {
  // One admin account for the whole suite: its sign-in codes would cross between the two
  // projects running at once (a new code replaces the last), and its email allows 5 codes per
  // 15 minutes (the seed clears that count). So the admin's flow runs at one size only.
  test.skip(testInfo.project.name !== "desktop", "one admin sign-in per run (see above)");

  // A fresh user, in a browser of their own.
  const theirs = await browser.newContext({
    locale: "es-ES",
    extraHTTPHeaders: { "x-forwarded-for": clientIp() },
  });
  const them = await theirs.newPage();
  const email = await signUpNewUser(them);
  expect((await sessionUser(them))?.email).toBe(email);

  // The admin signs in by email; the panel needs a passkey, added in settings.
  await addVirtualAuthenticator(page);
  const seen = await mailIds(ADMIN_EMAIL);
  await page.goto("/sign-in?lang=es");
  await page.getByRole("textbox", { name: "Tu correo" }).fill(ADMIN_EMAIL);
  await page.getByRole("button", { name: "Enviar código" }).click();
  const mail = await readSignInMail(ADMIN_EMAIL, { skip: seen });
  await page.getByRole("textbox", { name: "Dígito 1 de 6" }).fill(mail.code);
  await skipPasskeyOffer(page);
  await expect(page).toHaveURL(/\/app$/);

  await page.goto("/app/settings");
  const keys = page.getByRole("region", { name: "Entrar con tu huella" });
  await keys.getByRole("button", { name: "Agregar una huella" }).click();
  await expect(page.getByRole("status")).toContainText("Listo: ya puedes entrar con tu huella.");

  // The panel asks for the passkey, then shows the counts.
  await page.goto("/admin");
  await expect(page.getByRole("heading", { name: "Confirma que eres tú" })).toBeFocused();
  await page.getByRole("button", { name: "Confirmar con tu passkey" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Administración" })).toBeVisible();
  for (const card of [
    "Cuentas",
    "Con correo",
    "Sin correo",
    "Activas en 30 días",
    "Altas en 7 días",
  ])
    await expect(page.getByRole("group", { name: card, exact: true })).toBeVisible();

  // Look-up by email opens the account.
  await page.getByRole("textbox", { name: "Correo o id de la cuenta" }).fill(email);
  await page.getByRole("button", { name: "Buscar" }).click();
  await expect(page).toHaveURL(/\/admin\/users\/[^/]+$/);
  await expect(page.getByRole("heading", { level: 1, name: email })).toBeVisible();

  // Suspend, with a reason.
  const reason = "Abuse report from the e2e suite";
  await page.getByRole("button", { name: "Suspender", exact: true }).click();
  const sheet = page.getByRole("dialog", { name: "Suspender la cuenta" });
  await sheet.getByRole("textbox", { name: "Motivo" }).fill(reason);
  await sheet.getByRole("button", { name: "Suspender la cuenta" }).click();
  await expect(sheet).toBeHidden();
  await expect(page.getByText(/^Suspendida desde el /)).toBeVisible();
  await expect(page.getByRole("button", { name: "Reactivar", exact: true })).toBeVisible();
  const audit = page.getByRole("list", { name: "Registro de esta cuenta" });
  await expect(
    audit
      .getByRole("listitem")
      .filter({ hasText: "Cuenta suspendida" })
      .filter({ hasText: reason }),
  ).toHaveCount(1);

  // Their session is gone.
  expect(await sessionUser(them)).toBeNull();
  await theirs.close();
});

test("someone who is not an admin opening /admin gets the not-found page", async ({ page }) => {
  await signUpNewUser(page);
  await page.goto("/admin");
  await expect(page).toHaveURL(/\/admin$/);
  await expect(page.getByRole("heading", { name: "Esta página no existe" }).first()).toBeVisible();
  await expect(page.getByRole("button", { name: "Confirmar con tu passkey" })).toHaveCount(0);
  await expect(page.getByRole("heading", { name: "Administración" })).toHaveCount(0);
});
