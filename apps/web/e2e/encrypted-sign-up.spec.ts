import { expect, test } from "@playwright/test";
import {
  clientIp,
  freshEmail,
  pinClock,
  readSignInMail,
  setUpRecoveryKey,
  skipPasskeyOffer,
} from "./helpers.ts";

/**
 * A new person signs up on the web with the API's NEW_USERS_ENCRYPTED on (the e2e stack's
 * setting), so the account is born encrypted: the landing's closing "Crear cuenta", an email code, the
 * recovery key, "Install the app" (Android, then continue in the browser) and the onboarding's
 * welcome. `GET /v1/me` reports the account as `preview`. The plain-app specs seed plain users
 * instead (`signUpNewUser`, `seed:e2e-plain-user`).
 */

test.use({
  locale: "es-ES",
  timezoneId: "Europe/Madrid",
  extraHTTPHeaders: { "x-forwarded-for": clientIp() },
});
test.skip(({ isMobile }) => isMobile, "one born-encrypted sign-up per run, desktop only");

test("a web sign-up is born encrypted: recovery key, the app, then the welcome", async ({
  page,
}) => {
  await pinClock(page);
  const email = freshEmail("born");

  await page.goto("/");
  await page.locator("#closing").getByRole("link", { name: "Crear cuenta" }).click();
  await expect(page).toHaveURL(/\/create-account(\?|$)/);
  await expect(page.getByRole("heading", { name: "Crea tu cuenta" })).toBeVisible();
  await page.getByRole("textbox", { name: "Tu correo" }).fill(email);
  await page.getByRole("button", { name: "Enviar código" }).click();
  const mail = await readSignInMail(email);
  await page.getByRole("textbox", { name: "Dígito 1 de 6" }).fill(mail.code);
  await skipPasskeyOffer(page);

  await setUpRecoveryKey(page);

  await expect(page.getByRole("heading", { name: "Wambito vive en tu teléfono" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Descargar para Android" })).toHaveAttribute(
    "href",
    /\.apk$/,
  );
  await page.getByRole("button", { name: "Continuar en el navegador" }).click();

  await expect(
    page.getByRole("heading", { level: 1, name: "Te damos la bienvenida a Wambito" }),
  ).toBeVisible();
  await expect(page).toHaveURL(/\/welcome$/);

  const me = await page.request.get("/api/v1/me");
  expect(me.ok(), await me.text()).toBe(true);
  expect(await me.json()).toMatchObject({ email, encryption: "preview" });
});
