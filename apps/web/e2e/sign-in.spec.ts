import { expect, type Page, test } from "@playwright/test";
import {
  addVirtualAuthenticator,
  clientIp,
  freshEmail,
  readSignInMail,
  requestCode,
  sessionUser,
  skipPasskeyOffer,
  spendCode,
} from "./helpers.ts";

/**
 * Passwordless sign-in against the dev stack: the code from the email, the magic link opened in
 * another browser (no pending state there), and a used link that offers a new code.
 *
 * Each browser gets its own client address (see `clientIp`): the API's per-address sign-in limits
 * would otherwise be shared by every test and every run.
 */

// A fixture, not a value: a new address for every test, not one per worker.
test.use({
  extraHTTPHeaders: async ({ extraHTTPHeaders }, use) =>
    use({ ...extraHTTPHeaders, "x-forwarded-for": clientIp() }),
});

test("the emailed code signs a new user in, and the magic link signs them in elsewhere", async ({
  page,
  browser,
}) => {
  const email = freshEmail("code");

  // Came from the English landing: the page speaks English, and so will the new profile.
  await page.goto("/sign-in?lang=en");
  await expect(page.getByRole("heading", { level: 1, name: "Sign in to Wambito" })).toBeVisible();
  await page.getByRole("textbox", { name: "Your email" }).fill(email);
  await page.getByRole("button", { name: "Send code" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Check your email" })).toBeVisible();

  // The email is in the language of the page that asked for it, and so is its link.
  const first = await readSignInMail(email);
  expect(first.subject).toMatch(/^Your Wambito code: \d{6}$/);
  expect(new URL(first.link).searchParams.get("lang")).toBe("en");
  const firstBox = page.getByRole("textbox", { name: "Digit 1 of 6" });
  await expect(firstBox).toBeFocused();

  // A wrong code is refused, and the boxes are ready for another try.
  await page.keyboard.type(first.code === "000000" ? "111111" : "000000");
  await expect(page.getByRole("main").getByRole("alert")).toHaveText(
    "That code isn't right. Check it and try again.",
  );
  await expect(firstBox).toBeFocused();

  await page.keyboard.type(first.code);
  // The first email sign-in offers a passkey, in the page's language, with the heading focused.
  const offer = page.getByRole("heading", {
    level: 1,
    name: "Sign in with your fingerprint next time?",
  });
  await expect(offer).toBeFocused();
  await page.getByRole("button", { name: "Not now" }).click();
  await expect(page).toHaveURL(/\/welcome$/);

  const user = await sessionUser(page);
  expect(user?.email).toBe(email);
  const me = await page.request.get("/api/v1/me");
  expect(await me.json()).toMatchObject({ email, locale: "en", onboardingCompletedAt: null });

  // Signed in: the sign-in page sends them on.
  await page.goto("/sign-in");
  await expect(page).toHaveURL(/\/welcome$/);

  // A new code for the same address (now in their profile's English), and its magic link
  // opened in another browser, which keeps the language and `next`.
  await requestCode(email, { next: "/app/insights" });
  const second = await readSignInMail(email, { skip: [first.id] });
  expect(second.subject).toMatch(/^Your Wambito code/);
  const secondLink = new URL(second.link);
  expect(secondLink.pathname).toBe("/auth/verify");
  expect(secondLink.searchParams.get("lang")).toBe("en");
  expect(secondLink.searchParams.get("next")).toBe("/app/insights");

  const elsewhere = await browser.newContext({
    extraHTTPHeaders: { "x-forwarded-for": clientIp() },
  });
  try {
    const other = await elsewhere.newPage();
    expect(await sessionUser(other)).toBeNull();
    await other.goto(second.link);
    // It asks before spending the code, and the code has already left the address bar.
    await expect(
      other.getByRole("heading", { level: 1, name: `Continue as ${email}` }),
    ).toBeVisible();
    await expect(other).toHaveURL(/\/auth\/verify\?lang=en$/);
    await expect(other.locator('meta[name="referrer"]')).toHaveAttribute("content", "no-referrer");
    await other.getByRole("button", { name: "Continue" }).click();
    // Another device, so the offer comes again (the first browser said "Not now" for itself).
    await skipPasskeyOffer(other, { lang: "en" });
    await expect(other).toHaveURL(/\/welcome$/);
    expect((await sessionUser(other))?.id).toBe(user?.id);
  } finally {
    await elsewhere.close();
  }

  // The first browser is still signed in as the same user.
  expect((await sessionUser(page))?.id).toBe(user?.id);
});

test("a used magic link says so and sends a new code", async ({ page }) => {
  const email = freshEmail("link");
  await requestCode(email);
  const mail = await readSignInMail(email);
  await spendCode(email, mail.code);

  await page.goto(mail.link);
  await page.getByRole("button", { name: "Continuar" }).click();
  await expect(page.getByRole("main").getByRole("alert")).toHaveText(
    "Este código ya no sirve: venció o ya se usó. Pide uno nuevo.",
  );
  expect(await sessionUser(page)).toBeNull();

  await page.getByRole("button", { name: "Enviar un código nuevo" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Revisa tu correo" })).toBeVisible();
  await expect(page).toHaveURL(/\/sign-in\?lang=es$/);

  const fresh = await readSignInMail(email, { skip: [mail.id] });
  await page.getByRole("textbox", { name: "Dígito 1 de 6" }).fill(fresh.code);
  await skipPasskeyOffer(page);
  await expect(page).toHaveURL(/\/welcome$/);
  expect((await sessionUser(page))?.email).toBe(email);
});

test("opening the magic link spends nothing until Continue", async ({ page, browser, request }) => {
  const email = freshEmail("scan");
  await requestCode(email, { locale: "es" });
  const mail = await readSignInMail(email);

  // A mail scanner: a plain GET, then a browser that runs the page and looks around.
  expect((await request.get(mail.link)).ok()).toBe(true);
  const scanner = await browser.newContext({
    extraHTTPHeaders: { "x-forwarded-for": clientIp() },
  });
  try {
    const scan = await scanner.newPage();
    await scan.goto(mail.link);
    await expect(scan.getByRole("button", { name: "Continuar" })).toBeVisible();
    await scan.waitForTimeout(500);
    expect(await sessionUser(scan)).toBeNull();
  } finally {
    await scanner.close();
  }

  // Its owner taps Continue later: the code still works.
  await page.goto(mail.link);
  await expect(
    page.getByRole("heading", { level: 1, name: `Continuar como ${email}` }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Continuar" }).click();
  await skipPasskeyOffer(page);
  await expect(page).toHaveURL(/\/welcome$/);
  expect((await sessionUser(page))?.email).toBe(email);
});

test("a link from a sign-in started in the Android app offers the app, and spends nothing", async ({
  browser,
}) => {
  const email = freshEmail("applink");
  await requestCode(email, { locale: "es", client: "android" });
  const mail = await readSignInMail(email);
  expect(new URL(mail.link).searchParams.get("from")).toBe("app");

  // A mail app's own browser on an Android phone.
  const phone = await browser.newContext({
    userAgent:
      "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36",
    extraHTTPHeaders: { "x-forwarded-for": clientIp() },
  });
  try {
    const page = await phone.newPage();
    await page.goto(mail.link);
    const open = page.getByRole("link", { name: "Abrir en Wambito" });
    await expect(open).toBeVisible();
    const href = (await open.getAttribute("href")) ?? "";
    const link = new URL(mail.link);
    expect(href.startsWith(`intent://${link.host}/auth/verify${link.search}#Intent;`)).toBe(true);
    expect(href).toContain("scheme=https;package=com.wambito.app;");
    await expect(page.getByRole("button", { name: "Continuar" })).toHaveCount(0);
    await page.waitForTimeout(500);
    expect(await sessionUser(page)).toBeNull();

    // "Seguir en la web" spends the code on the web, as the plain page does.
    await page.getByRole("button", { name: "Seguir en la web" }).click();
    await skipPasskeyOffer(page);
    await expect(page).toHaveURL(/\/welcome$/);
    expect((await sessionUser(page))?.email).toBe(email);
  } finally {
    await phone.close();
  }

  // The same link from the web (no marker) and a desktop browser are the plain page.
  const webEmail = freshEmail("weblink");
  await requestCode(webEmail, { locale: "es" });
  const webMail = await readSignInMail(webEmail);
  expect(new URL(webMail.link).searchParams.has("from")).toBe(false);
});

test("no fingerprint button before a passkey, then the offer creates one and the button signs in", async ({
  page,
}) => {
  // A passkey with PRF opens the data too: the offer goes on at once, with no notice.
  await addVirtualAuthenticator(page, { prf: true });
  // The software authenticator would pick its passkey from the email field's autofill by itself
  // (see the next test); here only the button is under test.
  await page.addInitScript(() => {
    PublicKeyCredential.isConditionalMediationAvailable = async () => false;
  });
  const email = freshEmail("passkey");

  // Nothing to sign in with yet: the OS would say "no sign-in available", so there is no button.
  await page.goto("/sign-in?lang=en");
  await expect(page.getByRole("button", { name: "Send code" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Sign in with fingerprint" })).toHaveCount(0);
  await expect(page.getByRole("textbox", { name: "Your email" })).toHaveAttribute(
    "autocomplete",
    "username webauthn",
  );
  await expect(
    page.getByText("First time? Sign in with your email; you can use your fingerprint afterwards."),
  ).toBeVisible();

  await page.getByRole("textbox", { name: "Your email" }).fill(email);
  await page.getByRole("button", { name: "Send code" }).click();
  const mail = await readSignInMail(email);
  await page.getByRole("textbox", { name: "Digit 1 of 6" }).fill(mail.code);

  // The offer, in plain words; creating the passkey confirms and goes on to onboarding.
  await expect(
    page.getByRole("heading", { level: 1, name: "Sign in with your fingerprint next time?" }),
  ).toBeFocused();
  await expect(page.getByText("Your email keeps working as a backup.")).toBeVisible();
  await page.getByRole("button", { name: "Create my fingerprint" }).click();
  await expect(page).toHaveURL(/\/welcome$/);
  await expect(
    page.getByText("Done: next time you'll sign in with your fingerprint."),
  ).toBeVisible();
  await expect(page.getByText(/does not let it open your data/)).toHaveCount(0);
  const user = await sessionUser(page);
  expect(user?.email).toBe(email);

  // Signed out, this browser now knows a passkey: the button is there and signs in.
  await page.context().clearCookies();
  expect(await sessionUser(page)).toBeNull();
  await page.goto("/sign-in?lang=en");
  await page.getByRole("button", { name: "Sign in with fingerprint" }).click();
  await expect(page).toHaveURL(/\/welcome$/);
  expect((await sessionUser(page))?.id).toBe(user?.id);

  // A passkey exists, so signing in by email again does not offer another one. (Another browser:
  // it has not answered the offer, and the server's passkey list is what stops it.)
  const elsewhere = await page
    .context()
    .browser()
    ?.newContext({
      extraHTTPHeaders: { "x-forwarded-for": clientIp() },
    });
  if (!elsewhere) throw new Error("no browser");
  try {
    const other = await elsewhere.newPage();
    await requestCode(email);
    const second = await readSignInMail(email, { skip: [mail.id] });
    await other.goto(second.link);
    await other.getByRole("button", { name: "Continue" }).click();
    await expect(other).toHaveURL(/\/welcome$/);
  } finally {
    await elsewhere.close();
  }
});

test("a passkey picked from the email field's autofill signs in with no button", async ({
  page,
}) => {
  // No PRF: the passkey signs in but cannot open the encrypted data, and the offer says so.
  await addVirtualAuthenticator(page);
  const email = freshEmail("autofill");
  await page.goto("/sign-in?lang=en");
  await page.getByRole("textbox", { name: "Your email" }).fill(email);
  await page.getByRole("button", { name: "Send code" }).click();
  const mail = await readSignInMail(email);
  await page.getByRole("textbox", { name: "Digit 1 of 6" }).fill(mail.code);
  await page.getByRole("button", { name: "Create my fingerprint" }).click();
  // The notice stays (not a toast) until "Continue" goes on.
  await expect(
    page.getByRole("status").filter({ hasText: "does not let it open your data" }),
  ).toBeVisible();
  await expect(page).toHaveURL(/\/passkey-offer\?next=%2Fwelcome$/);
  await page.getByRole("button", { name: "Continue" }).click();
  await expect(page).toHaveURL(/\/welcome$/);
  const user = await sessionUser(page);

  // Signed out, the sign-in page asks the browser for this site's passkeys as soon as it opens;
  // the software authenticator answers like a person picking one from the keyboard's suggestions.
  await page.context().clearCookies();
  expect(await sessionUser(page)).toBeNull();
  await page.goto("/sign-in?lang=en");
  await expect(page).toHaveURL(/\/welcome$/);
  expect((await sessionUser(page))?.id).toBe(user?.id);
});

test("Ahora no is remembered: the offer does not come back on this device", async ({ page }) => {
  const email = freshEmail("later");
  await page.goto("/sign-in?lang=es");
  await page.getByRole("textbox", { name: "Tu correo" }).fill(email);
  await page.getByRole("button", { name: "Enviar código" }).click();
  const first = await readSignInMail(email);
  await page.getByRole("textbox", { name: "Dígito 1 de 6" }).fill(first.code);
  await expect(
    page.getByRole("heading", { level: 1, name: "¿Entrar con tu huella la próxima vez?" }),
  ).toBeFocused();
  await page.getByRole("button", { name: "Ahora no" }).click();
  await expect(page).toHaveURL(/\/welcome$/);

  // Signed out and in again with a new code: straight to onboarding this time.
  await page.context().clearCookies();
  await page.goto("/sign-in?lang=es");
  await page.getByRole("textbox", { name: "Tu correo" }).fill(email);
  await page.getByRole("button", { name: "Enviar código" }).click();
  const second = await readSignInMail(email, { skip: [first.id] });
  await page.getByRole("textbox", { name: "Dígito 1 de 6" }).fill(second.code);
  await expect(page).toHaveURL(/\/welcome$/);
});

for (const language of [
  {
    lang: "it",
    heading: "Entra in Wambito",
    subject: /^Il tuo codice Wambito: \d{6}$/,
    email: "La tua email",
    send: "Invia codice",
    title: "Controlla la tua email",
    offer: "Entrare con l'impronta la prossima volta?",
    notNow: "Non ora",
  },
  {
    lang: "pt",
    heading: "Entra em Wambito",
    subject: /^O teu código Wambito: \d{6}$/,
    email: "O teu email",
    send: "Enviar código",
    title: "Verifica o teu email",
    offer: "Entrar com a impressão digital da próxima vez?",
    notNow: "Agora não",
  },
] as const) {
  test(`${language.lang}: the page, the email and the new profile speak the language of the landing`, async ({
    page,
  }) => {
    const email = freshEmail(language.lang);
    await page.goto(`/sign-in?lang=${language.lang}`);
    await expect(page.getByRole("heading", { level: 1, name: language.heading })).toBeVisible();
    await expect(page.locator("html")).toHaveAttribute("lang", language.lang);
    await page.getByRole("textbox", { name: language.email }).fill(email);
    await page.getByRole("button", { name: language.send }).click();
    await expect(page.getByRole("heading", { level: 1, name: language.title })).toBeVisible();

    const mail = await readSignInMail(email);
    expect(mail.subject).toMatch(language.subject);
    expect(new URL(mail.link).searchParams.get("lang")).toBe(language.lang);

    await page.keyboard.type(mail.code);
    await expect(page.getByRole("heading", { level: 1, name: language.offer })).toBeVisible();
    await page.getByRole("button", { name: language.notNow }).click();
    await expect(page).toHaveURL(/\/welcome$/);
    const me = await page.request.get("/api/v1/me");
    expect(await me.json()).toMatchObject({ email, locale: language.lang, currency: "EUR" });
  });
}
