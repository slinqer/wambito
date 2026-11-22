import { existsSync, readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import AxeBuilder from "@axe-core/playwright";
import { expect, type Page, test } from "@playwright/test";

/**
 * The landing-only release build (`pnpm e2e:landing-only`): the same prerendered landing, built
 * with VITE_LANDING_ONLY=true and a configured origin, served the way Cloudflare Pages serves it
 * (unknown paths get 404.html). Nothing in it may lead to the app, which does not exist yet.
 */

const ORIGIN = process.env.VITE_SITE_URL ?? "https://landing-only.example.test";
const GITHUB = "https://github.com/slinqer/wambito";
const CLIENT = fileURLToPath(new URL("../build/client/", import.meta.url));
/** Anything that would lead to the app: sign-in, the app itself, the welcome flow, the demo. */
const APP_PATH = /(^|\/)(sign-in|create-account|app|welcome|demo)(\/|\?|#|$)/;

const LOCALES = [
  {
    locale: "es",
    path: "/",
    cta: "Muy pronto · Síguelo en GitHub",
    navCta: "Muy pronto",
    newTab: "(se abre en una pestaña nueva)",
    soon: "Pronto",
    ways: ["App para Android", "App para iOS"],
    closingTitle: "Cuando quieras, arrancamos.",
    closingBody:
      "Wambito está en construcción, en abierto. Mira cómo avanza en GitHub y prueba la app en cuanto abra.",
    oldClosing: /Crea tu cuenta/,
    oldCtas: ["Empieza ahora", "Crear cuenta", "Entrar", "Empezar"],
    demoCta: "Demo",
    banned: [/\bjueg(o|a)\b/i],
    toggleToDay: "Cambiar a modo día",
    cookies: "Preferencias de cookies",
  },
  {
    locale: "en",
    path: "/en",
    cta: "Coming soon · Follow on GitHub",
    navCta: "Coming soon",
    newTab: "(opens in a new tab)",
    soon: "Soon",
    ways: ["Android app", "iOS app"],
    closingTitle: "Ready when you are.",
    closingBody:
      "Wambito is being built in the open. Follow its progress on GitHub and try the app as soon as it opens.",
    oldClosing: /Create your account/,
    oldCtas: ["Get started", "Create account", "Sign in", "Start"],
    demoCta: "Demo",
    banned: [/\bgames?\b/i],
    toggleToDay: "Switch to day mode",
    cookies: "Cookie preferences",
  },
] as const;

/** The roadmap pages, per language, as the landing-only release ships them. */
const ROADMAP = {
  es: {
    path: "/roadmap",
    title: "Lo que viene",
    columns: ["En construcción", "Próximo", "Más adelante", "Ya está"],
    navLink: "Lo que viene",
    toggleToDay: "Cambiar a modo día",
  },
  en: {
    path: "/en/roadmap",
    title: "What's next",
    columns: ["Being built", "Next", "Later", "Live"],
    navLink: "What's next",
    toggleToDay: "Switch to day mode",
  },
} as const;

/** The privacy policy and account deletion pages, per language, as the landing-only release ships them. */
const LEGAL = {
  es: {
    privacy: { path: "/privacy", title: "Política de privacidad", link: "Privacidad" },
    deleteAccount: { path: "/delete-account", title: "Borrar tu cuenta", link: "Borrar cuenta" },
    faqLink: "política de privacidad",
  },
  en: {
    privacy: { path: "/en/privacy", title: "Privacy policy", link: "Privacy" },
    deleteAccount: {
      path: "/en/delete-account",
      title: "Delete your account",
      link: "Delete account",
    },
    faqLink: "privacy policy",
  },
  it: {
    privacy: { path: "/it/privacy", title: "Informativa sulla privacy", link: "Privacy" },
    deleteAccount: {
      path: "/it/delete-account",
      title: "Elimina il tuo account",
      link: "Elimina account",
    },
    faqLink: "informativa sulla privacy",
  },
  pt: {
    privacy: { path: "/pt/privacy", title: "Política de privacidade", link: "Privacidade" },
    deleteAccount: {
      path: "/pt/delete-account",
      title: "Apagar a tua conta",
      link: "Apagar conta",
    },
    faqLink: "política de privacidade",
  },
} as const;
const LANDING = { es: "/", en: "/en", it: "/it", pt: "/pt" } as const;

/** Axe with the WCAG A/AA rule sets (2.0 to 2.2) plus best practices. */
async function expectNoA11yViolations(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa", "best-practice"])
    .analyze();
  expect(
    results.violations.map((v) => ({ id: v.id, nodes: v.nodes.map((n) => n.target.join(" ")) })),
  ).toEqual([]);
}

/** Every rendered element that sticks out of the viewport, and every target under 44px. */
async function expectFitsTheViewport(page: Page) {
  const overflowing = await page.evaluate(() => {
    const width = document.documentElement.clientWidth;
    return [...document.querySelectorAll(".lk-landing *")]
      .filter((el) => {
        const box = el.getBoundingClientRect();
        if (box.width === 0 && box.height === 0) return false;
        return box.left < -0.5 || box.right > width + 0.5;
      })
      .map((el) => `${el.tagName.toLowerCase()}.${el.className} "${el.textContent?.slice(0, 30)}"`);
  });
  expect(overflowing).toEqual([]);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    ),
  ).toBeLessThanOrEqual(0);
  for (const target of await page.locator("a:visible, button:visible, summary").all()) {
    const box = await target.boundingBox();
    expect(box?.height, await target.innerText()).toBeGreaterThanOrEqual(44);
    expect(box?.width, await target.innerText()).toBeGreaterThanOrEqual(44);
  }
}

/**
 * The target of a link that is meant to leave for GitHub, in a new tab, and says so to a screen
 * reader: a visually hidden hint (`newTab`) after its text.
 */
async function expectGithubLink(link: ReturnType<Page["locator"]>, newTab: string) {
  await expect(link).toHaveAttribute("href", GITHUB);
  await expect(link).toHaveAttribute("target", "_blank");
  await expect(link).toHaveAttribute("rel", "noopener");
  const hint = link.locator(".sr-only");
  await expect(hint).toHaveText(newTab);
  // Visually hidden, not display:none: it stays in the accessibility tree.
  expect((await hint.boundingBox())?.width).toBeLessThanOrEqual(1);
}

/**
 * The header at one width and theme: the wordmark on one line, the CTA and the ☾ switch on the
 * same row, and nothing sticking out of the viewport.
 */
async function expectHeaderFits(
  page: Page,
  path: string,
  width: number,
  theme: "night" | "day",
  cta: string,
) {
  await page.setViewportSize({ width, height: 800 });
  await page.addInitScript((value) => localStorage.setItem("wambito.theme", value), theme);
  await page.goto(path);
  await expect(page.locator("html")).toHaveAttribute("data-theme", theme);
  const header = page.getByRole("banner");
  const logo = header.locator(".lk-logo");
  const nav = header.getByRole("navigation");
  const link = nav.getByRole("link", { name: cta });
  // The day/night switch, last in the row (after the language switch).
  const toggle = nav.getByRole("button").last();
  await expect(nav.getByRole("button", { name: /:/ })).toBeVisible();
  await expect(logo).toBeVisible();
  await expect(link).toBeVisible();
  await expect(toggle).toBeVisible();
  const [logoBox, linkBox, toggleBox] = [
    await logo.boundingBox(),
    await link.boundingBox(),
    await toggle.boundingBox(),
  ];
  // One line of the 28px wordmark, not two.
  expect(logoBox?.height).toBeLessThan(40);
  // One row: the three share a vertical band.
  const rowTop = Math.min(logoBox?.y ?? 0, linkBox?.y ?? 0, toggleBox?.y ?? 0);
  const rowBottom = Math.max(
    (logoBox?.y ?? 0) + (logoBox?.height ?? 0),
    (linkBox?.y ?? 0) + (linkBox?.height ?? 0),
    (toggleBox?.y ?? 0) + (toggleBox?.height ?? 0),
  );
  expect(rowBottom - rowTop).toBeLessThan(80);
  // The wordmark clears the CTA, and the switch ends inside the viewport.
  expect((logoBox?.x ?? 0) + (logoBox?.width ?? 0)).toBeLessThanOrEqual(linkBox?.x ?? 0);
  expect((toggleBox?.x ?? 0) + (toggleBox?.width ?? 0)).toBeLessThanOrEqual(width);
  expect(linkBox?.height).toBeGreaterThanOrEqual(44);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    ),
  ).toBeLessThanOrEqual(0);
}

test("the tab and home-screen icons are the Wambito coin, none named after the mascot", async ({
  page,
  request,
}) => {
  await page.goto("/");
  const links = await page
    .locator("head link[rel='icon'], head link[rel='apple-touch-icon']")
    .evaluateAll((els) => els.map((el) => [el.getAttribute("rel"), el.getAttribute("href")]));
  expect(links).toEqual([
    ["icon", "/favicon.ico"],
    ["icon", "/favicon.svg"],
    ["apple-touch-icon", "/apple-touch-icon.png"],
  ]);
  const types = { ico: "image/", svg: "image/svg+xml", png: "image/png" } as const;
  for (const [, href] of links) {
    const response = await request.get(href ?? "");
    expect(response.status(), href ?? "").toBe(200);
    const ext = (href ?? "").split(".").pop() as keyof typeof types;
    expect(response.headers()["content-type"]).toContain(types[ext]);
  }
  // The landing never links a file named after the mascot module (see vite.config.ts).
  const hrefs = await page
    .locator("head link[href]")
    .evaluateAll((els) => els.map((el) => el.getAttribute("href") ?? ""));
  expect(hrefs.filter((href) => /wambi/i.test(href.split("/").pop() ?? ""))).toEqual([]);
});

for (const l of LOCALES) {
  test.describe(`landing-only (${l.locale})`, () => {
    test("the calls to action are one coming-soon link to GitHub, hero and closing", async ({
      page,
    }) => {
      await page.goto(l.path);
      const hero = page
        .locator("#hero")
        .getByRole("link", { name: `${l.cta} ${l.newTab}`, exact: true });
      await expectGithubLink(hero, l.newTab);
      await expect(hero).toHaveClass(/lk-btn-primary/);
      expect((await hero.boundingBox())?.height).toBeGreaterThanOrEqual(44);

      const closing = page
        .locator("#closing")
        .getByRole("link", { name: `${l.cta} ${l.newTab}`, exact: true });
      await expectGithubLink(closing, l.newTab);
      await expect(closing).toHaveClass(/lk-btn-primary/);

      // The demo is part of the app: with no app to open there is no demo to try either.
      await expect(page.getByRole("link", { name: l.demoCta })).toHaveCount(0);
    });

    test("the header's sign-in is a short coming-soon link to GitHub, beside the day/night switch", async ({
      page,
    }) => {
      await page.goto(l.path);
      const nav = page.getByRole("banner").getByRole("navigation");
      const link = nav.getByRole("link", { name: `${l.navCta} ${l.newTab}`, exact: true });
      await expectGithubLink(link, l.newTab);
      await expect(link).toHaveClass(/lk-btn-secondary/);
      await expect(nav.getByRole("button", { name: l.toggleToDay })).toBeVisible();
    });

    test.describe(() => {
      test.use({ javaScriptEnabled: true });

      for (const width of [320, 390, 1280]) {
        for (const theme of ["night", "day"] as const) {
          test(`the header fits at ${width}px, ${theme} theme`, async ({ page }) => {
            await expectHeaderFits(page, l.path, width, theme, l.navCta);
          });
        }
      }
    });

    test("none of the old calls to action is left", async ({ page }) => {
      await page.goto(l.path);
      for (const name of l.oldCtas) {
        await expect(page.getByRole("link", { name, exact: true })).toHaveCount(0);
      }
    });

    test("both apps are coming-soon badges with no link", async ({ page }) => {
      await page.goto(l.path);
      const card = (name: string) =>
        page
          .locator("#ways")
          .getByRole("listitem")
          .filter({ has: page.getByRole("heading", { name }) });
      const [android, ios] = l.ways;
      for (const name of [android, ios] as string[]) {
        await expect(card(name).getByText(l.soon, { exact: true })).toBeVisible();
        await expect(card(name).getByRole("link")).toHaveCount(0);
      }
    });

    test("no link leads to /sign-in, /app, /welcome or /demo", async ({ page, request }) => {
      await page.goto(l.path);
      const hrefs = await page
        .locator("a[href]")
        .evaluateAll((nodes) => nodes.map((node) => node.getAttribute("href") ?? ""));
      expect(hrefs.length).toBeGreaterThan(5);
      expect(hrefs.filter((href) => APP_PATH.test(new URL(href, "http://x").pathname))).toEqual([]);
      const html = await (await request.get(l.path)).text();
      expect(html).not.toMatch(/href="[^"]*\/(sign-in|create-account|app|welcome|demo)(["/?#])/);
    });

    test("the closing section tells the truth about the app, and keeps Wambi's spot", async ({
      page,
      request,
    }) => {
      await page.goto(l.path);
      const closing = page.locator("#closing");
      await expect(closing.getByRole("heading", { level: 2 })).toHaveText(l.closingTitle);
      await expect(closing.locator("p")).toHaveText(l.closingBody);
      expect(await closing.innerText()).not.toMatch(l.oldClosing);
      const html = (await (await request.get(l.path)).text()).replaceAll("&#x27;", "'");
      expect(html).not.toMatch(l.oldClosing);

      const spot = closing.locator("[data-wambi-spot='closing']");
      await expect(spot).toHaveAttribute("data-wambi-pose", "resting");
      await expect(spot.locator("img")).toHaveAttribute("src", "/wambi/resting.webp");
    });

    test("is called Wambito, in the text and in the share tags", async ({ page }) => {
      await page.goto(l.path);
      await expect(page).toHaveTitle(/^Wambito · /);
      await expect(page.locator('meta[property="og:site_name"]')).toHaveAttribute(
        "content",
        "Wambito",
      );
      await expect(page.locator(".lk-logo").first()).toHaveText("Wambito");
      const text = await page.locator("body").evaluate((body) => body.textContent ?? "");
      expect(text).not.toMatch(/Luk(?:itas)|\bLuk(?:as)\b/);
    });

    test("is still free, open source and not a game", async ({ page }) => {
      await page.goto(l.path);
      const text = await page.locator("body").evaluate((body) => body.textContent ?? "");
      for (const pattern of l.banned) expect(text).not.toMatch(pattern);
      await expect(page.locator("#faq a", { hasText: "GitHub" })).toHaveAttribute("href", GITHUB);
    });

    test("canonical, hreflang and Open Graph use the configured origin", async ({ page }) => {
      await page.goto(l.path);
      const head = page.locator("head");
      const self = `${ORIGIN}${l.path}`;
      await expect(head.locator('link[rel="canonical"]')).toHaveAttribute("href", self);
      await expect(head.locator('link[rel="alternate"][hreflang="es"]')).toHaveAttribute(
        "href",
        `${ORIGIN}/`,
      );
      await expect(head.locator('link[rel="alternate"][hreflang="en"]')).toHaveAttribute(
        "href",
        `${ORIGIN}/en`,
      );
      await expect(head.locator('link[rel="alternate"][hreflang="x-default"]')).toHaveAttribute(
        "href",
        `${ORIGIN}/`,
      );
      await expect(head.locator('meta[property="og:url"]')).toHaveAttribute("content", self);
      await expect(head.locator('meta[property="og:image"]')).toHaveAttribute(
        "content",
        `${ORIGIN}/og-${l.locale}.png`,
      );
    });

    test("fits the viewport and keeps every target at 44px", async ({ page }) => {
      await page.goto(l.path);
      await expectFitsTheViewport(page);
    });

    test.describe("at 320px", () => {
      test.use({ viewport: { width: 320, height: 700 } });

      test("the long coming-soon labels wrap instead of overflowing", async ({ page }) => {
        await page.goto(l.path);
        await expectFitsTheViewport(page);
      });
    });

    test.describe(() => {
      // Axe needs JavaScript: keep it on but block the app's own scripts, which leaves exactly
      // the prerendered page.
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
        await expectGithubLink(
          page.locator("#hero").getByRole("link", { name: `${l.cta} ${l.newTab}`, exact: true }),
          l.newTab,
        );
        await expectGithubLink(
          page.locator("#closing").getByRole("link", { name: `${l.cta} ${l.newTab}`, exact: true }),
          l.newTab,
        );
        expect(errors).toEqual([]);
      });

      test("has no cookie banner, no cookie preferences and no PostHog without a key", async ({
        page,
      }) => {
        const assets = `${CLIENT}assets/`;
        // The posthog-js chunk (named after the library's entry file, not "posthog").
        const posthogChunks = readdirSync(assets).filter(
          (file) =>
            file.endsWith(".js") && readFileSync(assets + file, "utf8").includes("posthog-js"),
        );
        const loaded: string[] = [];
        page.on("request", (request) => loaded.push(request.url()));
        await page.goto(l.path);
        await page.waitForLoadState("networkidle");
        // Hydrated: the theme toggle answers.
        await page.getByRole("banner").getByRole("button", { name: l.toggleToDay }).click();
        await expect(page.locator("html")).toHaveAttribute("data-theme", "day");
        await expect(page.getByRole("region", { name: l.cookies })).toHaveCount(0);
        await expect(page.getByRole("button", { name: l.cookies })).toHaveCount(0);
        await expect(page.getByText(l.cookies)).toHaveCount(0);
        expect(loaded.filter((url) => /posthog/i.test(new URL(url).hostname))).toEqual([]);
        expect(
          loaded.filter((url) => posthogChunks.some((file) => url.endsWith(`/assets/${file}`))),
        ).toEqual([]);
      });
    });
  });
}

for (const l of LOCALES) {
  const r = ROADMAP[l.locale];

  test.describe(`landing-only roadmap (${l.locale})`, () => {
    test("is prerendered, 200, with its columns and the configured origin", async ({
      page,
      request,
    }) => {
      const response = await request.get(r.path);
      expect(response.status()).toBe(200);
      expect(await response.text()).toContain(`<html lang="${l.locale}"`);
      await page.goto(r.path);
      await expect(page.getByRole("heading", { level: 1 })).toHaveText(r.title);
      await expect(page.getByRole("main").getByRole("heading", { level: 2 })).toHaveText(r.columns);
      await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
        "href",
        `${ORIGIN}${r.path}`,
      );
      await expect(page.locator('meta[property="og:url"]')).toHaveAttribute(
        "content",
        `${ORIGIN}${r.path}`,
      );
      await expect(page.locator('link[rel="alternate"][hreflang="es"]')).toHaveAttribute(
        "href",
        `${ORIGIN}/roadmap`,
      );
      await expect(page.locator('link[rel="alternate"][hreflang="en"]')).toHaveAttribute(
        "href",
        `${ORIGIN}/en/roadmap`,
      );
    });

    test("leads nowhere near the app, and is called Wambito", async ({ page, request }) => {
      await page.goto(r.path);
      const hrefs = await page
        .locator("a[href]")
        .evaluateAll((nodes) => nodes.map((node) => node.getAttribute("href") ?? ""));
      expect(hrefs.length).toBeGreaterThan(4);
      expect(hrefs.filter((href) => APP_PATH.test(new URL(href, "http://x").pathname))).toEqual([]);
      const html = await (await request.get(r.path)).text();
      expect(html).not.toMatch(/href="[^"]*\/(sign-in|create-account|app|welcome|demo)(["/?#])/);
      const text = await page.locator("body").evaluate((body) => body.textContent ?? "");
      expect(text).toContain("Wambito");
      expect(text).not.toMatch(/Luk(?:itas)|\bLuk(?:as)\b/);
      for (const pattern of l.banned) expect(text).not.toMatch(pattern);
      await expect(page).toHaveTitle(/^Wambito · /);
    });

    test("the header's coming-soon link to GitHub is the only call to action", async ({ page }) => {
      await page.goto(r.path);
      const nav = page.getByRole("banner").getByRole("navigation");
      await expectGithubLink(
        nav.getByRole("link", { name: `${l.navCta} ${l.newTab}`, exact: true }),
        l.newTab,
      );
      await expect(nav.getByRole("button", { name: r.toggleToDay })).toBeVisible();
    });

    test("the landing links to it from the footer", async ({ page }) => {
      await page.goto(l.path);
      await expect(page.locator("#whats-next")).toHaveCount(0);
      await expect(
        page.getByRole("contentinfo").getByRole("link", { name: r.navLink }),
      ).toHaveAttribute("href", r.path);
    });

    test("fits the viewport and keeps every target at 44px", async ({ page }) => {
      await page.goto(r.path);
      await expectFitsTheViewport(page);
    });

    test.describe("at 320px", () => {
      test.use({ viewport: { width: 320, height: 700 } });

      test("nothing overflows, on the roadmap and in the landing's section", async ({ page }) => {
        await page.goto(r.path);
        await expectFitsTheViewport(page);
        await page.goto(l.path);
        await expectFitsTheViewport(page);
      });
    });

    test.describe(() => {
      test.use({ javaScriptEnabled: true, colorScheme: "dark" });

      test("the prerendered page is accessible (axe, night theme)", async ({ page }) => {
        await page.route("**/assets/*.js", (route) => route.abort());
        await page.goto(r.path);
        await expect(page.locator("html")).toHaveAttribute("data-theme", "night");
        await expectNoA11yViolations(page);
      });
    });

    test.describe("with JavaScript", () => {
      test.use({ javaScriptEnabled: true });

      test("is accessible in the day theme and hydrates cleanly", async ({ page }) => {
        const errors: string[] = [];
        page.on("console", (message) => {
          if (message.type() === "error") errors.push(message.text());
        });
        page.on("pageerror", (error) => errors.push(error.message));
        await page.addInitScript(() => localStorage.setItem("wambito.theme", "day"));
        await page.goto(r.path);
        await page.waitForLoadState("networkidle");
        await expect(page.locator("html")).toHaveAttribute("data-theme", "day");
        await expectNoA11yViolations(page);
        expect(errors).toEqual([]);
      });
    });
  });
}

for (const locale of ["es", "en", "it", "pt"] as const) {
  const legal = LEGAL[locale];

  test.describe(`landing-only legal pages (${locale})`, () => {
    for (const key of ["privacy", "deleteAccount"] as const) {
      const entry = legal[key];

      test(`${entry.path} is prerendered, 200, and the footer leads to it`, async ({
        page,
        request,
      }) => {
        const response = await request.get(entry.path);
        expect(response.status()).toBe(200);
        expect(await response.text()).toContain(`<html lang="${locale}"`);

        await page.goto(LANDING[locale]);
        await page
          .getByRole("contentinfo")
          .getByRole("link", { name: entry.link, exact: true })
          .click();
        await expect(page).toHaveURL(new RegExp(`${entry.path}$`));
        await expect(page.getByRole("heading", { level: 1 })).toHaveText(entry.title);
        await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
          "href",
          `${ORIGIN}${entry.path}`,
        );
      });
    }

    test("the FAQ's privacy answer links to the policy", async ({ page }) => {
      await page.goto(LANDING[locale]);
      await expect(page.locator("#faq a", { hasText: legal.faqLink })).toHaveAttribute(
        "href",
        legal.privacy.path,
      );
    });
  });
}

test("landing-only: the language switch on the privacy policy keeps the page", async ({ page }) => {
  await page.goto("/it/privacy");
  const pt = page.getByRole("contentinfo").getByRole("link", { name: "Português" });
  await expect(pt).toHaveAttribute("href", "/pt/privacy");
  await pt.click();
  await expect(page).toHaveURL(/\/pt\/privacy$/);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(LEGAL.pt.privacy.title);
});

test.describe("landing-only build output", () => {
  test("ships only the landing, a 404 page and the static files", () => {
    expect(readdirSync(CLIENT).sort()).toEqual(
      [
        "404.html",
        "_headers",
        "apple-touch-icon.png",
        "assets",
        "automatic-capture",
        // The logo image of the sign-in email, linked from the mails themselves (public/email).
        "email",
        "en",
        // The tab and home-screen icons (docs/brand/wambito-icon.svg).
        "favicon.ico",
        "favicon.svg",
        "index.html",
        "it",
        // The app's real insights screen in the "See where it goes" phone (pnpm landing-screens).
        "landing",
        "wambi",
        "og-en.png",
        "og-es.png",
        "og-it.png",
        "og-pt.png",
        "pt",
        "robots.txt",
        "roadmap",
        "privacy",
        "delete-account",
        "sitemap.xml",
      ].sort(),
    );
    for (const language of ["en", "it", "pt"]) {
      expect(readdirSync(`${CLIENT}${language}`).sort()).toEqual([
        "automatic-capture",
        "delete-account",
        "index.html",
        "privacy",
        "roadmap",
      ]);
      expect(readdirSync(`${CLIENT}${language}/privacy`)).toEqual(["index.html"]);
      expect(readdirSync(`${CLIENT}${language}/delete-account`)).toEqual(["index.html"]);
      expect(readdirSync(`${CLIENT}${language}/roadmap`)).toEqual(["index.html"]);
      expect(readdirSync(`${CLIENT}${language}/automatic-capture`)).toEqual(["index.html"]);
    }
    expect(readdirSync(`${CLIENT}automatic-capture`)).toEqual(["index.html"]);
    expect(readdirSync(`${CLIENT}roadmap`)).toEqual(["index.html"]);
    expect(readdirSync(`${CLIENT}privacy`)).toEqual(["index.html"]);
    expect(readdirSync(`${CLIENT}delete-account`)).toEqual(["index.html"]);
    expect(existsSync(`${CLIENT}__spa-fallback.html`)).toBe(false);
  });

  test("sitemap.xml and robots.txt are generated from the origin", async ({ request }) => {
    const robots = await (await request.get("/robots.txt")).text();
    expect(robots).toContain(`Sitemap: ${ORIGIN}/sitemap.xml`);
    expect(robots).not.toContain("wambito.test");
    expect(robots).not.toContain("Disallow");
    const sitemap = await (await request.get("/sitemap.xml")).text();
    expect(sitemap).toContain(`<loc>${ORIGIN}/</loc>`);
    expect(sitemap).toContain(`<loc>${ORIGIN}/en</loc>`);
    expect(sitemap).toContain(`<loc>${ORIGIN}/roadmap</loc>`);
    expect(sitemap).toContain(`<loc>${ORIGIN}/en/roadmap</loc>`);
    for (const path of ["/it", "/pt", "/it/roadmap", "/pt/roadmap"]) {
      expect(sitemap).toContain(`<loc>${ORIGIN}${path}</loc>`);
    }
    expect(sitemap).toContain(`hreflang="en" href="${ORIGIN}/en/roadmap"`);
    expect(sitemap).not.toContain("wambito.test");
  });

  test("_headers caches assets for good, HTML briefly, and sets the security headers", () => {
    const headers = readFileSync(`${CLIENT}_headers`, "utf8");
    expect(headers).toMatch(/\/assets\/\*\s+Cache-Control: public, max-age=31536000, immutable/);
    const legalPaths = Object.values(LEGAL).flatMap((entry) => [
      entry.privacy.path,
      `${entry.privacy.path}/`,
      entry.deleteAccount.path,
      `${entry.deleteAccount.path}/`,
    ]);
    for (const path of ["/en", "/it", "/pt", "/it/roadmap", "/pt/roadmap/", ...legalPaths]) {
      expect(headers, path).toMatch(
        new RegExp(`^${path}\\n\\s+Cache-Control: public, max-age=300, must-revalidate`, "m"),
      );
    }
    expect(headers).toMatch(/X-Content-Type-Options: nosniff/);
    expect(headers).toMatch(/Referrer-Policy: strict-origin-when-cross-origin/);
    expect(headers).toMatch(/Permissions-Policy: .*camera=\(\)/);
  });

  for (const path of ["/some/unknown/page", "/sign-in", "/app", "/welcome", "/demo", "/en/nope"]) {
    test(`${path} gets the 404 page, not the app`, async ({ request, page }) => {
      const response = await request.get(path);
      expect(response.status()).toBe(404);
      expect(await response.text()).toContain("<title>");
      await page.goto(path);
      await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    });
  }

  test("the 404 page speaks the four languages and links home in each", async ({ page }) => {
    await page.goto("/nowhere");
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Esta página no existe");
    await expect(page.getByRole("heading", { level: 2 })).toHaveText([
      "This page doesn't exist",
      "Questa pagina non esiste",
      "Esta página não existe",
    ]);
    const es = page.getByRole("link", { name: "Volver al inicio" });
    await expect(es).toHaveAttribute("href", "/");
    await expect(es).toHaveClass(/lk-btn-primary/);
    await expect(page.getByRole("link", { name: "Back to home" })).toHaveAttribute("href", "/en");
    await expect(page.getByRole("link", { name: "Torna alla home" })).toHaveAttribute(
      "href",
      "/it",
    );
    await expect(page.getByRole("link", { name: "Voltar ao início" })).toHaveAttribute(
      "href",
      "/pt",
    );
    await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", "noindex");
    await expect(page.locator('link[rel="canonical"]')).toHaveCount(0);
    expect(
      await page
        .locator("a[href]")
        .evaluateAll((nodes) => nodes.map((node) => node.getAttribute("href") ?? "")),
    ).not.toContainEqual(expect.stringMatching(APP_PATH));
    // The landing look: the same stylesheet, the night theme and the logo.
    await expect(page.locator(".lk-landing")).toHaveCount(1);
    await expect(page.locator(".lk-logo").first()).toHaveText("Wambito");
    await expect(page).toHaveTitle("Wambito · 404");
    const text = await page.locator("body").evaluate((body) => body.textContent ?? "");
    expect(text).toContain("Wambito");
    expect(text).not.toMatch(/Luk(?:itas)|\bLuk(?:as)\b/);
  });

  test.describe("the 404 page with JavaScript", () => {
    test.use({ javaScriptEnabled: true });

    test("hydrates cleanly and is accessible, night and day", async ({ page }) => {
      const errors: string[] = [];
      page.on("console", (message) => {
        // The page itself is a 404 response: the browser logs that, not a fault of the page.
        const isThePage = message.location().url.endsWith("/missing");
        if (message.type() === "error" && !isThePage) errors.push(message.text());
      });
      page.on("pageerror", (error) => errors.push(error.message));
      await page.goto("/missing");
      await page.waitForLoadState("networkidle");
      await expect(page.locator("html")).toHaveAttribute("data-theme", "night");
      await expectNoA11yViolations(page);
      await page.getByRole("banner").getByRole("button", { name: "Cambiar a modo día" }).click();
      await expect(page.locator("html")).toHaveAttribute("data-theme", "day");
      await expectNoA11yViolations(page);
      expect(errors).toEqual([]);
    });
  });
});
