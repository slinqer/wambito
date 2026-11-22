import { type Browser, expect, type Page, test } from "@playwright/test";
import {
  clientIp,
  expectNoAxeViolations as expectAccessible,
  freshEmail,
  onboardWithSample,
  pinClock,
  readSignInMail,
  requestCode,
  signUpNewUser,
  WCAG_TAGS,
} from "./helpers.ts";

/**
 * Accessibility (axe) on every screen, at both viewports (the phone and desktop projects), against
 * the dev stack: the landing and roadmap in all four languages, sign-in and its magic link, the
 * passkey offer, each welcome step, every /app screen signed in (home's two tabs, the add sheet
 * open, categories and a category, recurring, insights, settings, import) and the demo.
 *
 * The prerendered landing has its own run, JavaScript off, in landing.spec.ts. axe cannot check
 * text over the hero's gradient (it reports it "incomplete"); landing.spec.ts measures it instead.
 */

test.use({
  locale: "es-ES",
  timezoneId: "Europe/Madrid",
  extraHTTPHeaders: async ({ extraHTTPHeaders }, use) =>
    use({ ...extraHTTPHeaders, "x-forwarded-for": clientIp() }),
});

const h1 = (page: Page, name: string | RegExp) => page.getByRole("heading", { level: 1, name });
const isPhone = (page: Page) => (page.viewportSize()?.width ?? 0) < 1024;

test("the landing and the roadmap, in every language", async ({ page }) => {
  // Eight pages, each with a full axe run: more than a single screen's 30s on a cold dev server.
  test.slow();
  // The landing's own run (landing.spec.ts) adds axe's best practices; so does this one.
  const tags = [...WCAG_TAGS, "best-practice"];
  for (const [path, heading] of [
    ["/", /Tus lukas/],
    ["/en", /Your money/],
    ["/roadmap", /.+/],
    ["/en/roadmap", /.+/],
    ["/it", /I tuoi soldi/],
    ["/pt", /O teu dinheiro/],
    ["/it/roadmap", /.+/],
    ["/pt/roadmap", /.+/],
  ] as const) {
    await page.goto(path);
    await expect(h1(page, heading)).toBeVisible();
    await expectAccessible(page, path, tags);
  }
});

test("the demo", async ({ page }) => {
  await pinClock(page);
  await page.goto("/demo");
  await expect(page.getByRole("complementary", { name: "Demo" })).toBeVisible();
  await expectAccessible(page, "/demo");
});

test("sign-in, its code step, the passkey offer and the magic link", async ({ page, browser }) => {
  const email = freshEmail("a11y");
  await page.goto("/sign-in");
  await expect(page.getByRole("textbox", { name: "Tu correo" })).toBeVisible();
  await expectAccessible(page, "/sign-in");

  await page.getByRole("textbox", { name: "Tu correo" }).fill(email);
  await page.getByRole("button", { name: "Enviar código" }).click();
  const first = await readSignInMail(email);
  const digit = page.getByRole("textbox", { name: "Dígito 1 de 6" });
  await expect(digit).toBeVisible();
  await expectAccessible(page, "/sign-in, the code step");

  await digit.fill(first.code);
  await expect(page).toHaveURL(/\/passkey-offer(\?|$)/);
  await expect(page.getByRole("button", { name: "Ahora no" })).toBeVisible();
  await expectAccessible(page, "/passkey-offer");

  // The emailed link, opened in a browser that is not signed in: it asks before using the code.
  await requestCode(email);
  const second = await readSignInMail(email, { skip: [first.id] });
  await withNewPage(browser, async (other) => {
    await other.goto(second.link);
    await expect(h1(other, `Continuar como ${email}`)).toBeVisible();
    await expectAccessible(other, "/auth/verify");
  });
});

async function withNewPage(browser: Browser, use: (page: Page) => Promise<void>) {
  const context = await browser.newContext({
    locale: "es-ES",
    extraHTTPHeaders: { "x-forwarded-for": clientIp() },
  });
  try {
    await use(await context.newPage());
  } finally {
    await context.close();
  }
}

test("each welcome step", async ({ page }) => {
  await pinClock(page);
  await signUpNewUser(page);
  const next = page.getByRole("button", { name: "Siguiente" });

  await expect(h1(page, "Te damos la bienvenida a Wambito")).toBeFocused();
  await expectAccessible(page, "/welcome");
  await page.getByRole("button", { name: "Configurar en 1 minuto" }).click();

  await expect(h1(page, "¿En qué moneda llevas tus cuentas?")).toBeFocused();
  await expectAccessible(page, "/welcome/currency");
  await next.click();

  await expect(h1(page, "¿Vienes de otra app?")).toBeFocused();
  await expectAccessible(page, "/welcome/import");
  await next.click();

  await expect(h1(page, "¿En qué se te va el dinero?")).toBeFocused();
  await expectAccessible(page, "/welcome/categories");
  await next.click();

  await expect(h1(page, "¿Cuánto quieres gastar al mes?")).toBeFocused();
  await expectAccessible(page, "/welcome/budgets");
});

test.describe("signed in, with the sample imported", () => {
  test.beforeEach(async ({ page }) => {
    await pinClock(page);
    await signUpNewUser(page);
    await onboardWithSample(page, "Europe/Madrid");
  });

  test("home (both tabs) and the add sheet", async ({ page }) => {
    await page.goto("/app");
    await expect(page.getByRole("region", { name: "Te quedan este mes" })).toBeVisible();
    await expect(page.getByRole("tabpanel", { name: "Movimientos" })).toBeVisible();
    await expectAccessible(page, "/app, Movimientos");

    if (isPhone(page)) {
      await page.getByRole("tab", { name: "Categorías" }).click();
      await expect(page.getByRole("tab", { name: "Categorías" })).toHaveAttribute(
        "aria-selected",
        "true",
      );
    }
    await expect(page.getByRole("tabpanel", { name: "Categorías" })).toBeVisible();
    await expectAccessible(page, "/app, Categorías");

    await page.getByRole("button", { name: "Agregar", exact: true }).click();
    await expect(page.getByRole("dialog", { name: "Nuevo gasto" })).toBeVisible();
    await expectAccessible(page, "/app, the add sheet");
  });

  test("the new-category sheet, and a category with its edit sheet", async ({ page }) => {
    await page.goto("/app");
    if (isPhone(page)) await page.getByRole("tab", { name: "Categorías" }).click();
    const panel = page.getByRole("tabpanel", { name: "Categorías" });
    await panel.getByRole("button", { name: "Nueva categoría" }).click();
    await expect(page.getByRole("dialog", { name: "Nueva categoría" })).toBeVisible();
    await expectAccessible(page, "/app, Nueva categoría");
    await page.getByRole("dialog").getByRole("button", { name: "Cerrar" }).click();
    await expect(page.getByRole("dialog")).toBeHidden();

    await panel.getByRole("button", { name: /^Supermercado/ }).click();
    await expect(h1(page, "Supermercado")).toBeVisible();
    await expectAccessible(page, "/app/categories/:id");
    await page.getByRole("button", { name: "Editar categoría" }).click();
    await expect(page.getByRole("dialog", { name: "Editar categoría" })).toBeVisible();
    await expectAccessible(page, "/app/categories/:id, Editar categoría");
  });

  test("recurring, insights, settings and import", async ({ page }) => {
    for (const [path, heading] of [
      ["/app/recurring", "Recurrentes"],
      ["/app/insights", "Análisis"],
      ["/app/settings", "Ajustes"],
      ["/app/settings/agents", "Mis agentes"],
      ["/app/settings/account", "Cuenta y seguridad"],
      ["/app/settings/preferences", "Preferencias"],
      ["/app/settings/data", "Tus datos"],
      ["/app/settings/more", "Más"],
      ["/app/import", /.+/],
    ] as const) {
      await page.goto(path);
      await expect(h1(page, heading)).toBeVisible();
      await expectAccessible(page, path);
    }
  });
});
