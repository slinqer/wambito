import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { type BrowserContext, expect, type Page, type Request, test } from "@playwright/test";

/**
 * Landing analytics with consent, on the built landing (`pnpm e2e:landing-analytics`): a
 * landing-only build with a PostHog key and the fake host `posthog.example.test`. The real
 * posthog-js runs; every request to PostHog (the fake host or any `*.posthog.com`) is answered
 * here and counted, so no test ever reaches the real PostHog. These are the proof that nothing
 * loads before consent and that a withdrawal stops capture.
 */

const CLIENT = fileURLToPath(new URL("../build/client/", import.meta.url));
const CONSENT_KEY = "wambito.consent.analytics";
const POSTHOG_HOST = /(^|\.)posthog\.example\.test$|(^|\.)posthog\.com$/;

const COPY = {
  /** The banner's name and the footer link's, in Spanish and English (the tests visit `/en`). */
  preferences: /^(Preferencias de cookies|Cookie preferences)$/,
  accept: "Sí, quiero ayudar",
  decline: "No, gracias",
  close: "Cerrar",
  browserNo: "Tu navegador pidió no ser rastreado, así que no te rastreamos.",
  currentDenied: /^(Ahora: no aceptaste\.|Right now: you declined\.)$/,
  analyticsHeading: "Analítica en wambito.com",
} as const;

/**
 * The posthog-js chunk. Vite names it after the library's entry file (`module-<hash>.js`), not
 * "posthog", so it is found by its content: the one asset that carries the library's own name.
 */
const POSTHOG_CHUNK = (() => {
  const dir = `${CLIENT}assets/`;
  const hits = readdirSync(dir).filter(
    (file) => file.endsWith(".js") && readFileSync(dir + file, "utf8").includes("posthog-js"),
  );
  if (hits.length !== 1) throw new Error(`expected one posthog-js chunk, found ${hits.join(", ")}`);
  return `/assets/${hits[0]}`;
})();

const isPosthog = (url: string) => POSTHOG_HOST.test(new URL(url).hostname);
/** The tests' own round trip through the fake host (see `settle`); never counted. */
const SENTINEL = "https://posthog.example.test/__e2e_settle";
const isChunk = (url: string) => new URL(url).pathname === POSTHOG_CHUNK;

/** Answers every PostHog request with `{}` so nothing leaves the machine. */
async function fakePosthog(context: BrowserContext) {
  await context.route(
    (url) => isPosthog(url.href),
    (route) =>
      route.fulfill({
        status: 200,
        contentType: "application/json",
        headers: { "access-control-allow-origin": "*" },
        body: "{}",
      }),
  );
}

/** Counts one page's requests: to PostHog, and for the posthog-js chunk. */
function watch(page: Page) {
  const posthog: Request[] = [];
  const chunk: Request[] = [];
  page.on("request", (request) => {
    if (request.url() === SENTINEL) return;
    if (isPosthog(request.url())) posthog.push(request);
    if (isChunk(request.url())) chunk.push(request);
  });
  return { posthog, chunk };
}

/** PostHog's remote config (the JSON one), fetched once by every `posthog.init`. */
const isConfig = (request: Request) =>
  /^\/array\/[^/]+\/config$/.test(new URL(request.url()).pathname);
/** A capture: events (`/e/`, `/i/v0/e/`, `/batch/`) or a recording (`/s/`). */
const isCapture = (request: Request) =>
  /^\/(e|i\/v0\/e|batch|s)\/?$/.test(new URL(request.url()).pathname);

const banner = (page: Page) => page.getByRole("region", { name: COPY.preferences });
const preferences = (page: Page) => page.getByRole("button", { name: COPY.preferences });

async function storedChoice(page: Page): Promise<string | null> {
  return page.evaluate((key) => {
    const raw = localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as { choice: string }).choice : null;
  }, CONSENT_KEY);
}

/**
 * PostHog's own storage left in the page: `ph_*` cookies and `ph_*`/`__ph*` keys in localStorage
 * (`keys`) and sessionStorage (`sessionKeys`).
 */
async function posthogStorage(page: Page) {
  const cookies = (await page.context().cookies())
    .map((c) => c.name)
    .filter((n) => n.startsWith("ph_"));
  const { keys, sessionKeys } = await page.evaluate(() => {
    const posthog = (k: string) =>
      (k.startsWith("ph_") || k.startsWith("__ph")) && !k.startsWith("__ph_opt_in_out_");
    return {
      keys: Object.keys(localStorage).filter(posthog),
      sessionKeys: Object.keys(sessionStorage).filter(posthog),
    };
  });
  return { cookies, keys, sessionKeys };
}

async function accept(page: Page) {
  await banner(page).getByRole("button", { name: COPY.accept }).click();
  await expect(banner(page)).toBeHidden();
  await expect.poll(() => storedChoice(page)).toBe("granted");
}

async function decline(page: Page) {
  await banner(page).getByRole("button", { name: COPY.decline }).click();
  await expect(banner(page)).toBeHidden();
  await expect.poll(() => storedChoice(page)).toBe("denied");
}

/** Hydrated with the choice `denied`: the footer link opens the banner saying so. */
async function expectDeniedHere(page: Page) {
  await preferences(page).click();
  await expect(banner(page).getByText(COPY.currentDenied)).toBeVisible();
}

/**
 * Lets everything the page has scheduled happen and be seen, without sleeping. posthog-js sends
 * events in batches on a timer, so the fake clock (installed per test) runs those timers now; then
 * a sentinel request through the same faked host makes a round trip, so any PostHog request the
 * page started before it has reached `watch`. (`networkidle` cannot do this: after a client-side
 * move it was reached long ago and returns at once.)
 */
async function settle(page: Page) {
  await page.waitForLoadState("networkidle");
  for (let round = 0; round < 2; round++) {
    await page.clock.runFor(10_000);
    await page.evaluate((url) => fetch(url).then((r) => r.text()), SENTINEL);
  }
}

test.use({ javaScriptEnabled: true });

test.beforeEach(async ({ context }) => {
  await context.clock.install();
  await fakePosthog(context);
  // posthog-js drops every event from an automated browser (`navigator.webdriver`, a headless
  // brand): look like a person's browser, so the real library captures and the counts mean it.
  await context.addInitScript(() => {
    Object.defineProperty(Navigator.prototype, "webdriver", { get: () => false });
    Object.defineProperty(Navigator.prototype, "userAgentData", { get: () => undefined });
  });
});

test("nothing before accept", async ({ page }) => {
  const seen = watch(page);
  await page.goto("/");
  await expect(banner(page)).toBeVisible();
  await settle(page);
  expect(seen.posthog).toHaveLength(0);
  expect(seen.chunk).toHaveLength(0);
  expect((await posthogStorage(page)).cookies).toEqual([]);
});

test("the open banner never covers the footer's focused links", async ({ page }) => {
  await page.goto("/");
  await expect(banner(page)).toBeVisible();
  const privacy = page
    .getByRole("contentinfo")
    .getByRole("link", { name: "Privacidad", exact: true });
  const clearOfBanner = async () => {
    const link = await privacy.boundingBox();
    const card = await banner(page).boundingBox();
    if (!link || !card) return "missing";
    return link.y + link.height <= card.y ? "clear" : "covered";
  };
  // Focused from the top of the page, it scrolls clear of the banner (WCAG 2.2 SC 2.4.11).
  await privacy.focus();
  await expect(privacy).toBeFocused();
  await expect.poll(clearOfBanner).toBe("clear");
  // Scrolled as far as the page goes, the footer still clears it.
  await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
  await expect.poll(clearOfBanner).toBe("clear");
  // Closed, the reserve goes with it.
  await banner(page).getByRole("button", { name: COPY.decline }).click();
  await expect(banner(page)).toBeHidden();
  expect(
    await page.evaluate(() => document.documentElement.style.getPropertyValue("--lk-consent-h")),
  ).toBe("");
});

test("accept starts it, and a reload keeps it on", async ({ page }) => {
  const seen = watch(page);
  await page.goto("/");
  await accept(page);
  await expect.poll(() => seen.chunk.length).toBe(1);
  await expect.poll(() => seen.posthog.filter(isCapture).length).toBeGreaterThan(0);

  const before = seen.posthog.filter(isCapture).length;
  await page.reload();
  await settle(page);
  await expect.poll(() => seen.posthog.filter(isCapture).length).toBeGreaterThan(before);
  await expect(banner(page)).toBeHidden();
});

test("decline stays off, across a reload and other pages", async ({ page }) => {
  const seen = watch(page);
  await page.goto("/");
  await decline(page);
  for (const path of [null, "/en", "/privacy"]) {
    if (path) await page.goto(path);
    else await page.reload();
    await settle(page);
    await expect(banner(page)).toBeHidden();
    await expectDeniedHere(page);
  }
  await settle(page);
  expect(seen.posthog).toHaveLength(0);
  expect(seen.chunk).toHaveLength(0);
});

test("gpc wins over a stored yes", async ({ context, page }) => {
  await context.addInitScript(
    ({ key, value }) => {
      Object.defineProperty(navigator, "globalPrivacyControl", { value: true });
      localStorage.setItem(key, value);
    },
    {
      key: CONSENT_KEY,
      value: JSON.stringify({ v: 1, choice: "granted", at: new Date().toISOString() }),
    },
  );
  const seen = watch(page);
  await page.goto("/");
  await settle(page);
  // Hydrated: the footer link opens the GPC note, not the question.
  await preferences(page).click();
  await expect(banner(page).getByText(COPY.browserNo)).toBeVisible();
  await expect(banner(page).getByRole("button", { name: COPY.accept })).toHaveCount(0);
  await banner(page).getByRole("button", { name: COPY.close }).click();
  await expect(banner(page)).toBeHidden();
  await settle(page);
  expect(seen.posthog).toHaveLength(0);
  expect(seen.chunk).toHaveLength(0);
});

test("dnt wins over a stored yes", async ({ context, page }) => {
  await context.addInitScript(
    ({ key, value }) => {
      Object.defineProperty(navigator, "doNotTrack", { value: "1" });
      localStorage.setItem(key, value);
    },
    {
      key: CONSENT_KEY,
      value: JSON.stringify({ v: 1, choice: "granted", at: new Date().toISOString() }),
    },
  );
  const seen = watch(page);
  await page.goto("/");
  await settle(page);
  // Hydrated: the footer link opens the browser note, not the question.
  await preferences(page).click();
  await expect(banner(page).getByText(COPY.browserNo)).toBeVisible();
  await expect(banner(page).getByRole("button", { name: COPY.accept })).toHaveCount(0);
  await banner(page).getByRole("button", { name: COPY.close }).click();
  await expect(banner(page)).toBeHidden();
  await settle(page);
  expect(seen.posthog).toHaveLength(0);
  expect(seen.chunk).toHaveLength(0);
});

test("withdrawing from the footer stops it and clears its storage", async ({ page }) => {
  const seen = watch(page);
  await page.goto("/");
  await accept(page);
  await expect.poll(() => seen.posthog.filter(isCapture).length).toBeGreaterThan(0);
  await expect.poll(async () => (await posthogStorage(page)).cookies.length).toBeGreaterThan(0);
  await expect.poll(async () => (await posthogStorage(page)).sessionKeys.length).toBeGreaterThan(0);

  await preferences(page).click();
  await decline(page);
  const atWithdrawal = seen.posthog.length;
  expect(await posthogStorage(page)).toEqual({ cookies: [], keys: [], sessionKeys: [] });

  // Moving around (client-side, then a full load) would send page views if capture were on.
  await page.getByRole("contentinfo").getByRole("link", { name: "English" }).click();
  await expect(page).toHaveURL(/\/en$/);
  await page.getByRole("contentinfo").getByRole("link", { name: "What's next" }).click();
  await expect(page).toHaveURL(/\/en\/roadmap$/);
  await settle(page);
  await page.goto("/privacy");
  await settle(page);
  await expectDeniedHere(page);
  expect(seen.posthog.slice(atWithdrawal).map((r) => r.url())).toEqual([]);
  expect(await posthogStorage(page)).toEqual({ cookies: [], keys: [], sessionKeys: [] });
});

test("a decline in another tab stops it in this one", async ({ context }) => {
  const a = await context.newPage();
  const seenA = watch(a);
  await a.goto("/");
  await accept(a);
  await expect.poll(() => seenA.posthog.filter(isCapture).length).toBeGreaterThan(0);

  const b = await context.newPage();
  await b.goto("/");
  await settle(b);
  await preferences(b).click();
  await decline(b);

  // Tab A heard it: its banner, opened again, says the choice is now `denied`.
  await a.bringToFront();
  await expectDeniedHere(a);
  await settle(a);
  const atDecline = seenA.posthog.length;

  // Client-side moves would each send a page view if capture were still on. The banner is still
  // open; the footer scrolls clear of it, so its own links work (the next page's footer starts
  // with the banner closed).
  await a.getByRole("contentinfo").getByRole("link", { name: "Privacidad", exact: true }).click();
  await expect(a).toHaveURL(/\/privacy$/);
  await expect(banner(a)).toBeHidden();
  await a.getByRole("contentinfo").getByRole("link", { name: "English" }).click();
  await expect(a).toHaveURL(/\/en\/privacy$/);
  await a.getByRole("contentinfo").getByRole("link", { name: "What's next" }).click();
  await expect(a).toHaveURL(/\/en\/roadmap$/);
  await settle(a);
  expect(seenA.posthog.slice(atDecline).map((r) => r.url())).toEqual([]);
});

test("one start across client-side navigation", async ({ page }) => {
  const seen = watch(page);
  await page.goto("/");
  await accept(page);
  await expect.poll(() => seen.posthog.filter(isConfig).length).toBe(1);
  await page.evaluate(() => {
    (window as Window & { sameDocument?: boolean }).sameDocument = true;
  });
  await settle(page);
  const atStart = seen.posthog.filter(isCapture).length;

  await page.getByRole("contentinfo").getByRole("link", { name: "English" }).click();
  await expect(page).toHaveURL(/\/en$/);
  await page.getByRole("contentinfo").getByRole("link", { name: "What's next" }).click();
  await expect(page).toHaveURL(/\/en\/roadmap$/);
  await settle(page);
  // With capture on, these moves are captured by the time `settle` returns: the same wait the
  // withdrawal tests use to prove that nothing is sent.
  expect(seen.posthog.filter(isCapture).length).toBeGreaterThan(atStart);

  // Still the same document (no full load), and PostHog was initialised once: one chunk load,
  // one remote-config request.
  expect(
    await page.evaluate(() => (window as Window & { sameDocument?: boolean }).sameDocument),
  ).toBe(true);
  expect(seen.chunk).toHaveLength(1);
  expect(seen.posthog.filter(isConfig)).toHaveLength(1);
});

test.describe("without JavaScript", () => {
  test.use({ javaScriptEnabled: false });

  test("the prerendered HTML has no banner", async ({ request }) => {
    const html = await (await request.get("/")).text();
    expect(html).not.toContain("lk-consent");
    expect(html).not.toContain(COPY.accept);
    expect(html).not.toContain(POSTHOG_CHUNK);
  });

  test("the privacy policy says what the analytics collect", async ({ page }) => {
    await page.goto("/privacy");
    await expect(page.getByRole("heading", { name: COPY.analyticsHeading })).toBeVisible();
  });
});
