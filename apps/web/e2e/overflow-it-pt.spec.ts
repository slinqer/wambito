import { expect, type Page, test } from "@playwright/test";
import { clientIp, type Lang, onboardWithSample, pinClock, signUpNewUser } from "./helpers.ts";

/**
 * Italian and European Portuguese run 10-25% longer than Spanish (spec §3): on a 360 px phone the
 * home and Settings screens, the bottom bar, the tabs and the avatar menu must not scroll
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
  { locale: string; hero: string; tab: string; menu: string; account: string; settings: string }
> = {
  it: {
    locale: "it-IT",
    hero: "Ti restano questo mese",
    tab: "Movimenti",
    account: "Il tuo account",
    menu: "Ricorrenti",
    settings: "Impostazioni",
  },
  pt: {
    locale: "pt-PT",
    hero: "Restam-te este mês",
    tab: "Movimentos",
    account: "A tua conta",
    menu: "Recorrentes",
    settings: "Definições",
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

    test("preferences, data and more do not overflow", async ({ page }) => {
      for (const category of ["preferences", "data", "more"]) {
        await page.goto(`/app/settings/${category}`);
        await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
        await expect(page.locator(".lk-group").first()).toBeVisible();
        await expectNoHorizontalOverflow(page, `${lang} settings ${category}`);
      }
    });
  });
}
