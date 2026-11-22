import { expect, type Locator, type Page, test } from "@playwright/test";
import { expectNoAxeViolations } from "./helpers.ts";

/**
 * The demo without an account (spec §2.6b), against `pnpm dev` alone: no API, no database. From
 * the landing's "Demo" a visitor lands in Valentina's invented month, adds an
 * expense, sees what is left drop, and a reload puts everything back. Not one request leaves for
 * `/api/` on the way (no session check either): the demo's backend lives in the page.
 */

const LANG = {
  es: {
    landing: "/",
    cta: "Demo",
    banner: "Estás en el demo: los datos son inventados y se borran al recargar.",
    createAccount: "Crear mi cuenta",
    left: "Te quedan este mes",
    add: "Agregar",
    sheet: "Nuevo gasto",
    keypad: "Teclado numérico",
    // COP has no decimals: 5.000 pesos.
    keys: ["5", "0", "0", "0"],
    // Pesos come with the lukas hint.
    hint: "5 lukas",
    // What the hero's figure loses, in its own digits ("$638.100" → 638100).
    drop: 5_000,
    categoryGroup: "Categoría",
    category: "Mercado",
    save: "Guardar",
    saved: "Gasto en Mercado: $5.000",
    insights: "Análisis",
    categories: "Categorías",
    recurring: "Recurrentes",
    settings: "Ajustes",
    account: "Tu cuenta",
    home: "Inicio",
    off: "En el demo esto no está disponible. Crea tu cuenta para usarlo.",
    viewing: "Estás viendo el demo de Valentina.",
    exportRow: "Descargar tus datos",
    deleteAccount: "Eliminar tu cuenta",
    importRow: "Importar movimientos",
  },
  en: {
    landing: "/en",
    cta: "Demo",
    banner: "You're in the demo: the data is made up and goes away when you reload.",
    createAccount: "Create my account",
    left: "Left this month",
    add: "Add",
    sheet: "New expense",
    keypad: "Keypad",
    keys: ["5"],
    hint: null,
    // 5.00 € in hundredths ("€245.96" → 24596).
    drop: 500,
    categoryGroup: "Category",
    category: "Groceries",
    save: "Save",
    saved: "Expense in Groceries: €5.00",
    insights: "Insights",
    categories: "Categories",
    recurring: "Recurring",
    settings: "Settings",
    account: "Your account",
    home: "Home",
    off: "Not available in the demo. Create your account to use it.",
    viewing: "You're viewing Valentina's demo.",
    exportRow: "Download your data",
    deleteAccount: "Delete your account",
    importRow: "Import transactions",
  },
} as const;

type Lang = (typeof LANG)[keyof typeof LANG];

const isPhone = (page: Page) => (page.viewportSize()?.width ?? 0) < 1024;

/** Every request to the API, from the start of the test. */
function watchApi(page: Page): string[] {
  const seen: string[] = [];
  page.on("request", (request) => {
    if (new URL(request.url()).pathname.startsWith("/api/")) seen.push(request.url());
  });
  return seen;
}

/** The hero's figure (what assistive technology reads, not the count-up), as its digits. */
async function heroDigits(hero: Locator): Promise<number> {
  const text = (await hero.locator(".lk-hero-amount .sr-only").textContent()) ?? "";
  return Number(text.replace(/\D/g, ""));
}

/** No link on the screen leads into the signed-in app (its guard would send the visitor to sign-in). */
async function expectLinksStayInDemo(page: Page) {
  const hrefs = await page
    .locator("a[href]")
    .evaluateAll((nodes) => nodes.map((node) => node.getAttribute("href") ?? ""));
  expect(hrefs.filter((href) => /^\/app(\/|$|\?)/.test(href))).toEqual([]);
  expect(hrefs.some((href) => href.startsWith("/demo"))).toBe(true);
}

async function enterFromLanding(page: Page, l: Lang) {
  await page.goto(l.landing);
  await page.locator("#hero").getByRole("link", { name: l.cta, exact: true }).click();
  await expect(page).toHaveURL(/\/demo\?lang=(es|en)$/);
  const banner = page.getByRole("complementary", { name: "Demo" });
  await expect(banner).toContainText(l.banner);
  return banner;
}

async function addExpense(page: Page, l: Lang) {
  await page.getByRole("button", { name: l.add, exact: true }).click();
  const sheet = page.getByRole("dialog", { name: l.sheet });
  const keypad = sheet.getByRole("group", { name: l.keypad });
  for (const key of l.keys) await keypad.getByRole("button", { name: key, exact: true }).click();
  if (l.hint) await expect(sheet).toContainText(l.hint);
  await sheet
    .getByRole("group", { name: l.categoryGroup })
    .getByRole("button", { name: l.category })
    .click();
  await sheet.getByRole("button", { name: l.save, exact: true }).click();
  await expect(sheet).toBeHidden();
}

/**
 * Opens a section from the sidebar (wide screens) or from home's avatar menu (phones, where the
 * bottom bar has only Inicio and Análisis).
 */
async function openSection(page: Page, l: Lang, name: string) {
  if (!isPhone(page)) {
    await page.getByRole("navigation").getByRole("link", { name }).click();
    return;
  }
  if (!/\/demo$/.test(new URL(page.url()).pathname)) {
    await page.getByRole("navigation").getByRole("link", { name: l.home }).click();
  }
  await page.getByRole("button", { name: l.account }).click();
  await page.getByRole("banner").getByRole("link", { name }).click();
}

test.beforeEach(async ({ page }) => {
  // The demo lays Valentina's months over the page's clock: pin it, mid-afternoon on 21 October.
  await page.clock.setFixedTime(new Date("2026-10-21T18:00:00Z"));
});

test("es: try it from the landing, add 5.000, and a reload puts the seed back", async ({
  page,
}) => {
  const l = LANG.es;
  const api = watchApi(page);
  const banner = await enterFromLanding(page, l);
  await expect(banner.getByRole("link", { name: l.createAccount })).toHaveAttribute(
    "href",
    "/sign-in?lang=es",
  );

  const hero = page.getByRole("region", { name: l.left });
  await expect(hero.locator(".lk-hero-amount .sr-only")).toHaveText(/^\$[\d.]+$/);
  const seeded = await heroDigits(hero);
  expect(seeded).toBeGreaterThan(0);
  await expectNoAxeViolations(page);

  await addExpense(page, l);
  await expect(page.getByRole("status")).toContainText(l.saved);
  await expect.poll(() => heroDigits(hero)).toBe(seeded - l.drop);

  await page.reload();
  await expect(page.getByRole("complementary", { name: "Demo" })).toContainText(l.banner);
  await expect.poll(() => heroDigits(page.getByRole("region", { name: l.left }))).toBe(seeded);

  expect(api).toEqual([]);
});

test("es: every demo screen keeps its links in /demo, and settings turns off what can't work", async ({
  page,
}) => {
  const l = LANG.es;
  const api = watchApi(page);
  await page.goto("/demo?lang=es");
  await expect(page.getByRole("region", { name: l.left })).toBeVisible();
  await expect(page).toHaveTitle("Demo · Inicio · Wambito");
  await expectLinksStayInDemo(page);

  // Insights from the bottom bar or the sidebar.
  await page.getByRole("navigation").getByRole("link", { name: l.insights }).click();
  await expect(page).toHaveURL(/\/demo\/insights$/);
  await expect(page.getByRole("heading", { name: l.insights, level: 1 })).toBeVisible();
  await expect(page.getByRole("complementary", { name: "Demo" })).toBeVisible();
  await expect(page).toHaveTitle("Demo · Análisis · Wambito");
  await expectLinksStayInDemo(page);

  // Categories are managed in home's Categorías tab; from it, one category's detail.
  await openSection(page, l, l.categories);
  await expect(page).toHaveURL(/\/demo$/);
  await expect(page.getByRole("tabpanel", { name: l.categories })).toBeVisible();
  const restaurants = page
    .getByRole("tabpanel", { name: l.categories })
    .getByRole("button", { name: /Restaurantes/ });
  await expect(restaurants).toBeVisible();
  await expectLinksStayInDemo(page);
  await restaurants.click();
  await expect(page).toHaveURL(/\/demo\/categories\/[0-9a-f-]+/);
  await expect(page.getByRole("heading", { name: "Restaurantes", level: 1 })).toBeVisible();
  await expectLinksStayInDemo(page);

  // The recurring ones: rent, Spotify and the salary.
  await openSection(page, l, l.recurring);
  await expect(page).toHaveURL(/\/demo\/recurring$/);
  await expect(page.getByText("Spotify").first()).toBeVisible();
  await expectLinksStayInDemo(page);

  // Settings: no sign-in to speak of; export, delete, passkeys and import are off, with the note.
  await openSection(page, l, l.settings);
  await expect(page).toHaveURL(/\/demo\/settings$/);
  await expect(page).toHaveTitle("Demo · Ajustes · Wambito");
  await expect(page.getByText(l.viewing)).toBeVisible();
  await expect(page.getByText(/Entraste como/)).toHaveCount(0);
  await expectLinksStayInDemo(page);
  await expectNoAxeViolations(page);
  // The demo's menu is the app's, under /demo: each category has its own page there.
  const menu = page.getByRole("navigation", { name: l.settings }).getByRole("link");
  await expect(menu).toHaveCount(5);
  await menu.nth(3).click();
  await expect(page).toHaveURL(/\/demo\/settings\/data$/);
  // Both rows are drawn but do nothing in the demo (the note says why).
  await expect(page.getByText(l.exportRow, { exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: new RegExp(`^${l.exportRow}`) })).toHaveCount(0);
  await expect(page.getByText(l.importRow, { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: new RegExp(`^${l.importRow}`) })).toHaveCount(0);
  await expect(page.getByText(l.off)).toHaveCount(1);
  await expectLinksStayInDemo(page);
  await page.goBack();
  await expect(page).toHaveURL(/\/demo\/settings$/);
  await menu.nth(1).click();
  await expect(page).toHaveURL(/\/demo\/settings\/account$/);
  // the row has no action in the demo (a note says why)
  await expect(page.getByRole("button", { name: l.deleteAccount })).toHaveCount(0);
  await expect(page.getByText(l.deleteAccount, { exact: true })).toBeVisible();
  await expect(page.getByText(l.off)).toHaveCount(2);
  await expectLinksStayInDemo(page);
  await expectNoAxeViolations(page);
  await page.goBack();
  await expect(page).toHaveURL(/\/demo\/settings$/);

  // Back home from settings.
  await page.getByRole("navigation").getByRole("link", { name: l.home }).click();
  await expect(page).toHaveURL(/\/demo$/);

  expect(api).toEqual([]);
});

test("es: the avatar menu is drawn over the home's tabs, all of it", async ({ page }) => {
  test.skip(!isPhone(page), "the menu sits over the tabs at phone width");
  const l = LANG.es;
  await page.goto("/demo?lang=es");
  await page.getByRole("button", { name: l.account }).click();
  // Every item of the menu is what a tap at its middle reaches: nothing (the sticky tabs, once)
  // is painted over its lower part.
  const covered = await page.evaluate(() => {
    const menu = document.querySelector(".lk-menu");
    if (!menu) return ["no menu"];
    return [...menu.querySelectorAll("a, button")].flatMap((item) => {
      const box = item.getBoundingClientRect();
      const top = document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2);
      return top && menu.contains(top) ? [] : [item.textContent?.trim() ?? "?"];
    });
  });
  expect(covered).toEqual([]);
});

test("en: reloading a deep link keeps the demo in English and in euros", async ({ page }) => {
  const l = LANG.en;
  const api = watchApi(page);
  await page.goto("/demo?lang=en");
  await expect(page.getByRole("region", { name: l.left })).toBeVisible();
  await expect(page).toHaveTitle("Demo · Home · Wambito");
  await page.getByRole("navigation").getByRole("link", { name: l.insights }).click();
  await expect(page).toHaveURL(/\/demo\/insights$/);

  // No ?lang in the URL any more: the tab remembers it.
  await page.reload();
  await expect(page.getByRole("heading", { name: l.insights, level: 1 })).toBeVisible();
  await expect(page).toHaveTitle("Demo · Insights · Wambito");
  await expect(page.getByRole("complementary", { name: "Demo" })).toContainText(l.banner);
  await expect(page.getByText(/€[\d,]+\.\d\d/).first()).toBeVisible();

  expect(api).toEqual([]);
});

test("en: try it from the English landing in euros, and add 5.00 €", async ({ page }) => {
  const l = LANG.en;
  const api = watchApi(page);
  const banner = await enterFromLanding(page, l);
  await expect(banner.getByRole("link", { name: l.createAccount })).toHaveAttribute(
    "href",
    "/sign-in?lang=en",
  );
  const hero = page.getByRole("region", { name: l.left });
  await expect(hero.locator(".lk-hero-amount .sr-only")).toHaveText(/^€[\d,]+\.\d\d$/);
  const seeded = await heroDigits(hero);
  expect(seeded).toBeGreaterThan(0);

  await addExpense(page, l);
  await expect(page.getByRole("status")).toContainText(l.saved);
  await expect.poll(() => heroDigits(hero)).toBe(seeded - l.drop);
  await expectNoAxeViolations(page);

  expect(api).toEqual([]);
});
