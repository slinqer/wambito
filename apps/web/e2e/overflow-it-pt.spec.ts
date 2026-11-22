import { expect, type Page, test } from "@playwright/test";
import {
  clientIp,
  freshEmail,
  type Lang,
  onboardWithSample,
  pinClock,
  readSignInMail,
  setUpRecoveryKey,
  signUpNewUser,
  skipPasskeyOffer,
} from "./helpers.ts";

/**
 * Italian and European Portuguese run 10-25% longer than Spanish (spec §3): on a 360 px phone the
 * home and Settings screens (the menu and every category page, an encrypted account's account
 * page too), the bottom bar, the tabs and the avatar menu must not scroll
 * sideways, and none of their labels is clipped by its box.
 */

test.use({
  viewport: { width: 360, height: 740 },
  timezoneId: "Europe/Madrid",
  extraHTTPHeaders: async ({ extraHTTPHeaders }, use) =>
    use({ ...extraHTTPHeaders, "x-forwarded-for": clientIp() }),
});

const WORDS: Record<
  "it" | "pt",
  {
    locale: string;
    hero: string;
    tab: string;
    menu: string;
    account: string;
    settings: string;
    language: string;
    languageName: string;
    accountRow: string;
    back: string;
    devices: string;
  }
> = {
  it: {
    locale: "it-IT",
    hero: "Ti restano questo mese",
    tab: "Movimenti",
    account: "Il tuo account",
    menu: "Ricorrenti",
    settings: "Impostazioni",
    language: "Lingua",
    languageName: "Italiano",
    accountRow: "Account e sicurezza",
    back: "Torna a Impostazioni",
    devices: "I tuoi dispositivi",
  },
  pt: {
    locale: "pt-PT",
    hero: "Restam-te este mês",
    tab: "Movimentos",
    account: "A tua conta",
    menu: "Recorrentes",
    settings: "Definições",
    language: "Idioma",
    languageName: "Português",
    accountRow: "Conta e segurança",
    back: "Voltar a Definições",
    devices: "Os teus dispositivos",
  },
};

/** Nothing on the page is wider than the phone, and no label is cut off inside its own box. */
async function expectNoHorizontalOverflow(page: Page, where: string) {
  const report = await page.evaluate(() => {
    const root = document.documentElement;
    const clipped: string[] = [];
    // Labels that clip their own text: a box whose content is wider than the box, where the box
    // hides it (overflow hidden or text-overflow ellipsis). Boxes that scroll on purpose (a
    // horizontal carousel, `overflow-x: auto`) are not clipping.
    for (const el of document.querySelectorAll<HTMLElement>(
      ".lk-tabbar *, [role=tablist] *, .lk-menu *, button, a, h1, h2, h3, label",
    )) {
      const style = getComputedStyle(el);
      const hides =
        style.textOverflow === "ellipsis" ||
        style.overflowX === "hidden" ||
        style.overflowX === "clip";
      if (hides && el.scrollWidth > el.clientWidth + 1 && el.clientWidth > 4) {
        clipped.push(`${el.tagName.toLowerCase()}.${el.className}: ${el.textContent?.trim()}`);
      }
    }
    return {
      scroll: root.scrollWidth,
      client: root.clientWidth,
      bodyScroll: document.body.scrollWidth,
      clipped,
    };
  });
  expect(report.scroll, `${where}: the page scrolls sideways`).toBeLessThanOrEqual(report.client);
  expect(report.bodyScroll, `${where}: the body is wider than the phone`).toBeLessThanOrEqual(
    report.client,
  );
  expect(report.clipped, `${where}: a label is clipped`).toEqual([]);
}

for (const lang of ["it", "pt"] as const satisfies readonly Lang[]) {
  const words = WORDS[lang];
  test.describe(`${lang} on a 360 px phone`, () => {
    test.use({ locale: words.locale });

    test.beforeEach(async ({ page }, info) => {
      test.skip(info.project.name !== "phone", "one phone-sized run is enough");
      await pinClock(page);
      await signUpNewUser(page, { lang });
      await onboardWithSample(page, "Europe/Madrid");
      const me = await page.request.patch("/api/v1/me", { data: { locale: lang } });
      expect(me.ok(), await me.text()).toBe(true);
    });

    test("home, its tabs, its bottom bar and the avatar menu do not overflow", async ({ page }) => {
      await page.goto("/app");
      await expect(page.locator("html")).toHaveAttribute("lang", lang);
      await expect(page.getByRole("region", { name: words.hero })).toBeVisible();
      await expectNoHorizontalOverflow(page, `${lang} home`);

      await page.getByRole("tab", { name: words.tab }).click();
      await expect(page.getByRole("tabpanel", { name: words.tab })).toBeVisible();
      await expectNoHorizontalOverflow(page, `${lang} movements`);

      await page.getByRole("button", { name: words.account }).click();
      await expect(page.locator(".lk-menu").getByRole("link", { name: words.menu })).toBeVisible();
      await expect(
        page.locator(".lk-menu").getByRole("link", { name: words.settings }),
      ).toBeVisible();
      await expectNoHorizontalOverflow(page, `${lang} avatar menu`);
    });

    test("settings does not overflow", async ({ page }) => {
      await page.goto("/app");
      await page.getByRole("button", { name: words.account }).click();
      await page.locator(".lk-menu").getByRole("link", { name: words.settings }).click();
      await expect(page).toHaveURL(/\/app\/settings$/);
      await expect(page.getByRole("heading", { level: 1, name: words.settings })).toBeVisible();
      await expectNoHorizontalOverflow(page, `${lang} settings`);
      await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
      await expectNoHorizontalOverflow(page, `${lang} settings, its foot`);
    });

    test("every category page does not overflow", async ({ page }) => {
      for (const category of ["agents", "account", "preferences", "data", "more"]) {
        await page.goto(`/app/settings/${category}`);
        await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
        await expect(page.locator(".lk-group").first()).toBeVisible();
        await expectNoHorizontalOverflow(page, `${lang} settings ${category}`);
      }
    });

    test("an encrypted account's account page does not overflow", async ({ browser }) => {
      test.setTimeout(90_000);
      // Its own context: the plain user of beforeEach stays in the page fixture.
      const context = await browser.newContext({
        viewport: { width: 360, height: 740 },
        locale: words.locale,
        timezoneId: "Europe/Madrid",
        extraHTTPHeaders: { "x-forwarded-for": clientIp() },
      });
      const page = await context.newPage();
      await pinClock(page);
      // A web sign-up on the e2e stack is born encrypted (NEW_USERS_ENCRYPTED).
      const email = freshEmail(`overflow-${lang}`);
      await page.goto("/create-account?lang=es");
      await page.getByRole("textbox", { name: "Tu correo" }).fill(email);
      await page.getByRole("button", { name: "Enviar código" }).click();
      const mail = await readSignInMail(email);
      await page.getByRole("textbox", { name: "Dígito 1 de 6" }).fill(mail.code);
      await skipPasskeyOffer(page);
      await setUpRecoveryKey(page);
      await page.getByRole("button", { name: "Continuar en el navegador" }).click();
      await page.getByRole("button", { name: "Entrar directo" }).click();
      await expect(page).toHaveURL(/\/app$/);

      // The language from Preferencias, then Cuenta y seguridad through the menu (in-app links:
      // a page load would leave the pinned clock's sheets off-screen).
      await page.goto("/app/settings/preferences");
      await page.getByRole("button", { name: /^Idioma/ }).click();
      await page
        .getByRole("dialog", { name: "Idioma" })
        .getByRole("radio", { name: words.languageName })
        .click();
      await expect(page.locator("html")).toHaveAttribute("lang", lang);
      await page.getByRole("link", { name: words.back }).click();
      await page
        .getByRole("navigation", { name: words.settings })
        .getByRole("link", { name: new RegExp(`^${words.accountRow}`) })
        .click();
      await expect(page).toHaveURL(/\/app\/settings\/account$/);
      await expect(page.getByRole("group", { name: words.devices })).toBeVisible();
      await expectNoHorizontalOverflow(page, `${lang} settings account, encrypted`);
      await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
      await expectNoHorizontalOverflow(page, `${lang} settings account, encrypted, its foot`);
      await context.close();
    });
  });
}
