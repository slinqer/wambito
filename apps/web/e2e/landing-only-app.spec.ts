import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import AxeBuilder from "@axe-core/playwright";
import { expect, type Page, test } from "@playwright/test";

/**
 * The landing-only release built with VITE_APP_URL (`pnpm e2e:landing-only-app`): the same
 * prerendered landing, but the app is live on its own origin, so every call to action opens its
 * sign-in there and nothing says "coming soon". The build without VITE_APP_URL is covered by
 * landing-only.spec.ts.
 */

const SITE = process.env.VITE_SITE_URL ?? "https://landing-only.example.test";
const APP = process.env.VITE_APP_URL ?? "https://app.example.test";
/** The Android download: the arm64 APK of the mobile release. */
const ANDROID_APK_HREF =
  "https://github.com/slinqer/wambito/releases/download/mobile-v1.0.5/wambito-1.0.5-arm64-v8a.apk";

const CLIENT = fileURLToPath(new URL("../build/client/", import.meta.url));

const LOCALES = [
  {
    locale: "es",
    path: "/",
    cta: "Crear cuenta",
    demoCta: "Demo",
    navCta: "Entrar",
    soon: "Pronto",
    androidTitle: "App para Android",
    androidCta: "Desde GitHub",
    others: ["App para iOS"],
    closingBody:
      "Wambito nació en 2026 con la frustración de no saber cuánto gastaba en cafés al mes.",
    comingSoon: [/Muy pronto/, /Síguelo en GitHub/, /en construcción/],
    banned: [/\bjueg(o|a)\b/i],
  },
  {
    locale: "en",
    path: "/en",
    cta: "Create account",
    demoCta: "Demo",
    navCta: "Sign in",
    soon: "Soon",
    androidTitle: "Android app",
    androidCta: "From GitHub",
    others: ["iOS app"],
    closingBody:
      "Wambito was born in 2026 out of the frustration of not knowing how much I spent on coffee each month.",
    comingSoon: [/Coming soon/, /Follow on GitHub/, /being built in the open/],
    banned: [/\bgames?\b/i],
  },
] as const;

const ROADMAP_PATH = { es: "/roadmap", en: "/en/roadmap" } as const;

async function expectNoA11yViolations(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa", "best-practice"])
    .analyze();
  expect(
    results.violations.map((v) => ({ id: v.id, nodes: v.nodes.map((n) => n.target.join(" ")) })),
  ).toEqual([]);
}

/** A link to a door of the live app, in the page's language, in the same tab. */
async function expectAppLink(
  link: ReturnType<Page["locator"]>,
  locale: string,
  door: "sign-in" | "create-account",
) {
  await expect(link).toHaveAttribute("href", `${APP}/${door}?lang=${locale}`);
  await expect(link).not.toHaveAttribute("target", /.+/);
  await expect(link.locator(".sr-only")).toHaveCount(0);
  expect((await link.boundingBox())?.height).toBeGreaterThanOrEqual(44);
}

for (const l of LOCALES) {
  test.describe(`landing-only with the app (${l.locale})`, () => {
    test("the hero's \"Demo\" opens the demo on the app's origin", async ({ page }) => {
      await page.goto(l.path);
      const demo = page.locator("#hero").getByRole("link", { name: l.demoCta, exact: true });
      await expect(demo).toHaveAttribute("href", `${APP}/demo?lang=${l.locale}`);
      await expect(demo).not.toHaveAttribute("target", /.+/);
      await expect(demo).toHaveClass(/lk-btn-secondary/);
      expect((await demo.boundingBox())?.height).toBeGreaterThanOrEqual(44);
      // Only the hero offers it, and nothing links to a /demo on the landing's own origin.
      const hrefs = await page
        .locator("a[href]")
        .evaluateAll((nodes) => nodes.map((node) => node.getAttribute("href") ?? ""));
      expect(hrefs.filter((href) => /\/demo(\?|$)/.test(href))).toEqual([
        `${APP}/demo?lang=${l.locale}`,
      ]);
    });

    test("the hero and closing calls to action open the app's create-account page", async ({
      page,
    }) => {
      await page.goto(l.path);
      for (const section of ["#hero", "#closing"]) {
        const link = page.locator(section).getByRole("link", { name: l.cta, exact: true });
        await expectAppLink(link, l.locale, "create-account");
        await expect(link).toHaveClass(/lk-btn-primary/);
        await expect(link).not.toHaveClass(/is-soon/);
      }
    });

    test("the header's sign-in opens the app, beside the day/night switch", async ({ page }) => {
      await page.goto(l.path);
      const nav = page.getByRole("banner").getByRole("navigation");
      const link = nav.getByRole("link", { name: l.navCta, exact: true });
      await expectAppLink(link, l.locale, "sign-in");
      await expect(link).toHaveClass(/lk-btn-secondary/);
      // The language switch, then the day/night switch.
      await expect(nav.getByRole("button")).toHaveCount(2);
      await expect(nav.getByRole("button").last()).toBeVisible();
    });

    test("Android downloads the APK; iOS stays soon; no web or agent card", async ({ page }) => {
      await page.goto(l.path);
      const ways = page.locator("#ways").getByRole("listitem");
      await expect(ways).toHaveCount(2);
      for (const name of l.others) {
        const card = ways.filter({ has: page.getByRole("heading", { name }) });
        await expect(card.getByText(l.soon, { exact: true })).toBeVisible();
        await expect(card.getByRole("link")).toHaveCount(0);
      }
      const android = ways.filter({ has: page.getByRole("heading", { name: l.androidTitle }) });
      await expect(android.getByRole("link", { name: l.androidCta, exact: true })).toHaveAttribute(
        "href",
        ANDROID_APK_HREF,
      );
      // Its one "soon" is Google Play's: the GitHub download is live.
      await expect(android.getByText(l.soon, { exact: true })).toHaveCount(1);
      await expect(android.locator(".lk-landing-store")).toHaveText(`Google Play${l.soon}`);
    });

    test("nothing still says coming soon, and no link points at GitHub's 'follow' CTA", async ({
      page,
      request,
    }) => {
      await page.goto(l.path);
      const text = await page.locator("body").evaluate((body) => body.textContent ?? "");
      const html = (await (await request.get(l.path)).text()).replaceAll("&#x27;", "'");
      for (const pattern of l.comingSoon) {
        expect(text).not.toMatch(pattern);
        expect(html).not.toMatch(pattern);
      }
      for (const pattern of l.banned) expect(text).not.toMatch(pattern);
      expect(text).not.toMatch(/Luk(?:itas)|\bLuk(?:as)\b/);
    });

    test("every link to a door leaves for the app origin; none is relative", async ({ page }) => {
      await page.goto(l.path);
      const hrefs = await page
        .locator("a[href]")
        .evaluateAll((nodes) => nodes.map((node) => node.getAttribute("href") ?? ""));
      const toApp = hrefs.filter((href) =>
        /(^|\/)(sign-in|create-account|app|welcome)(\/|\?|#|$)/.test(href),
      );
      // Hero, the agent's "connect" and closing create an account; the header signs in.
      expect(toApp.sort()).toEqual(
        [
          ...Array(3).fill(`${APP}/create-account?lang=${l.locale}`),
          `${APP}/sign-in?lang=${l.locale}`,
        ].sort(),
      );
    });

    test("the closing section is honest: anyone can create an account", async ({ page }) => {
      await page.goto(l.path);
      await expect(page.locator("#closing").locator("p")).toHaveText(l.closingBody);
    });

    test("the site's own URLs still use the site origin, not the app's", async ({ page }) => {
      await page.goto(l.path);
      await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
        "href",
        `${SITE}${l.path}`,
      );
      expect(readFileSync(`${CLIENT}sitemap.xml`, "utf8")).not.toContain(APP);
      expect(readFileSync(`${CLIENT}robots.txt`, "utf8")).not.toContain(APP);
    });

    test("the roadmap's header opens the app too", async ({ page }) => {
      await page.goto(ROADMAP_PATH[l.locale]);
      const nav = page.getByRole("banner").getByRole("navigation");
      await expectAppLink(
        nav.getByRole("link", { name: l.navCta, exact: true }),
        l.locale,
        "sign-in",
      );
    });

    test.describe(() => {
      test.use({ javaScriptEnabled: true });

      for (const width of [320, 390, 1280]) {
        test(`the header fits at ${width}px`, async ({ page }) => {
          await page.setViewportSize({ width, height: 800 });
          await page.goto(l.path);
          const header = page.getByRole("banner");
          const logo = header.locator(".lk-logo");
          const link = header.getByRole("navigation").getByRole("link", { name: l.navCta });
          // The day/night switch, last in the row (after the language switch).
          const toggle = header.getByRole("navigation").getByRole("button").last();
          const [logoBox, linkBox, toggleBox] = [
            await logo.boundingBox(),
            await link.boundingBox(),
            await toggle.boundingBox(),
          ];
          expect(logoBox?.height).toBeLessThan(40);
          expect((logoBox?.x ?? 0) + (logoBox?.width ?? 0)).toBeLessThanOrEqual(linkBox?.x ?? 0);
          expect((toggleBox?.x ?? 0) + (toggleBox?.width ?? 0)).toBeLessThanOrEqual(width);
          expect(
            await page.evaluate(
              () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
            ),
          ).toBeLessThanOrEqual(0);
        });
      }
    });

    test.describe(() => {
      test.use({ javaScriptEnabled: true, colorScheme: "dark" });

      test("the prerendered page is accessible (axe, night theme)", async ({ page }) => {
        await page.route("**/assets/*.js", (route) => route.abort());
        await page.goto(l.path);
        await expect(page.locator("html")).toHaveAttribute("data-theme", "night");
        await expectNoA11yViolations(page);
      });
    });

    test.describe("with JavaScript", () => {
      test.use({ javaScriptEnabled: true });

      test("is accessible in the day theme and keeps its links after hydrating", async ({
        page,
      }) => {
        const errors: string[] = [];
        page.on("console", (message) => {
          if (message.type() === "error") errors.push(message.text());
        });
        page.on("pageerror", (error) => errors.push(error.message));
        await page.addInitScript(() => localStorage.setItem("wambito.theme", "day"));
        await page.goto(l.path);
        await page.waitForLoadState("networkidle");
        await expect(page.locator("html")).toHaveAttribute("data-theme", "day");
        await expectNoA11yViolations(page);
        for (const section of ["#hero", "#closing"]) {
          const link = page.locator(section).getByRole("link", { name: l.cta, exact: true });
          await expect(link).toHaveAttribute("href", `${APP}/create-account?lang=${l.locale}`);
        }
        expect(errors).toEqual([]);
      });
    });
  });
}
