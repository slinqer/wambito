/**
 * Renders the real app screens the landing shows inside phones, from the demo (made-up data), in
 * every language and both themes (390×844 points at 2×), each as the screen without what moves
 * and what moves alone on a transparent ground, which the landing lays over it and animates as the
 * app does:
 *
 * - insights (`/demo/insights`, the "By category" card): public/landing/insights-<locale>-<theme>.webp
 *   and the donut's ring, donut-<locale>-<theme>.webp (swept in);
 * - budgets (`/demo/categories`, home's Categories tab): budgets-<locale>-<theme>.webp and the
 *   bars' fills, budget-bars-<locale>-<theme>.webp (grown from the left);
 *
 * and app/features/landing/app-screen.gen.ts: where the ring sits on the screen (the same in every
 * shot; the script fails otherwise).
 *
 * Needs the web dev server (`pnpm --filter @wambito/web dev`, no API: the demo runs in the page),
 * or another origin with `--url`:
 *
 *   pnpm --filter @wambito/web landing-screens                 (all of them)
 *   pnpm --filter @wambito/web landing-screens es it           (only those languages)
 *   pnpm --filter @wambito/web landing-screens --url http://localhost:4173
 *
 * Run it again whenever the insights screen changes, so the landing never shows an old app.
 */
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { chromium, type Locator, type Page } from "playwright";

const ALL_LOCALES = ["es", "en", "it", "pt"] as const;
const THEMES = ["night", "day"] as const;
const WIDTH = 390;
const HEIGHT = 844;
/** The fixed date of the shots, so they change only when the app does. */
const NOW = "2026-10-21T15:00:00Z";

const args = process.argv.slice(2);
const urlFlag = args.indexOf("--url");
const origin = urlFlag >= 0 ? args[urlFlag + 1] : "http://localhost:5173";
const named = args.filter((arg, i) => arg !== "--url" && i !== urlFlag + 1);
const LOCALES = ALL_LOCALES.filter((locale) => named.length === 0 || named.includes(locale));

function cardTitle(locale: string): string {
  const path = fileURLToPath(new URL(`../app/i18n/messages/app.${locale}.json`, import.meta.url));
  return JSON.parse(readFileSync(path, "utf8")).insights.donut.title;
}

/** Playwright writes PNG or JPEG; Chromium's canvas turns it into a much smaller WebP (alpha kept). */
async function toWebp(page: Page, png: Buffer): Promise<Buffer> {
  const base64 = await page.evaluate(async (data) => {
    const image = new Image();
    image.src = `data:image/png;base64,${data}`;
    await image.decode();
    const canvas = document.createElement("canvas");
    canvas.width = image.naturalWidth;
    canvas.height = image.naturalHeight;
    canvas.getContext("2d")?.drawImage(image, 0, 0);
    return canvas.toDataURL("image/webp", 0.82).split(",")[1] ?? "";
  }, png.toString("base64"));
  return Buffer.from(base64, "base64");
}

const outDir = fileURLToPath(new URL("../public/landing/", import.meta.url));
mkdirSync(outDir, { recursive: true });
let ring: { x: number; y: number; size: number } | null = null;

/**
 * Opens a demo screen, waits for its data, drops the demo banner, leaves blank what sits above
 * `anchor` (Wambi's line, the header) and scrolls `anchor` near the top of the screen, with room
 * above it for the phone frame's notch.
 */
async function open(page: Page, path: string, anchor: Locator, ready: Locator) {
  await page.goto(`${origin}${path}`);
  await anchor.waitFor();
  await ready.first().waitFor();
  // The phone shows the app, not the demo: no "this is the demo" banner.
  await page.addStyleTag({ content: "aside.sticky { display: none !important; }" });
  await page.evaluate(() => document.fonts.ready);
  await anchor.evaluate((card) => {
    let inside: Element | null = card;
    while (inside && inside !== document.body) {
      let before = inside.previousElementSibling;
      while (before) {
        (before as HTMLElement).style.visibility = "hidden";
        before = before.previousElementSibling;
      }
      inside = inside.parentElement;
    }
    const top = card.getBoundingClientRect().top + window.scrollY;
    window.scrollTo({ top: top - 56, behavior: "instant" });
  });
  await page.waitForTimeout(400);
}

/** Shows only `selector` on a transparent ground; returns how to undo it. */
async function only(page: Page, selector: string) {
  const tag = await page.addStyleTag({
    content: `html, body { background: transparent !important; }
      body { visibility: hidden !important; }
      ${selector} { visibility: visible !important; }`,
  });
  return () => tag.evaluate((node) => (node as Element).remove());
}

/** Hides `selector`; returns how to undo it. */
async function without(page: Page, selector: string) {
  const tag = await page.addStyleTag({ content: `${selector} { visibility: hidden !important; }` });
  return () => tag.evaluate((node) => (node as Element).remove());
}

async function save(page: Page, name: string, png: Buffer) {
  writeFileSync(`${outDir}${name}.webp`, await toWebp(page, png));
  console.log(`Wrote ${name}.webp`);
}

/** Insights: the "By category" card; the donut's ring apart, swept in over it. */
async function insights(page: Page, locale: string, theme: string) {
  const title = page.getByRole("heading", { level: 2, name: cardTitle(locale) });
  // Wait for the categories themselves (a share like "53,9 %"), not just the card's title.
  await open(
    page,
    `/demo/insights?lang=${locale}`,
    page.locator("section", { has: title }).last(),
    page.getByText(/^\d+[.,]\d\s?%$/),
  );
  const DONUT = "figure[data-animated] svg";
  const box = await page.locator(DONUT).first().boundingBox();
  if (!box) throw new Error(`No donut on the ${locale} ${theme} screen`);
  const here = { x: Math.round(box.x), y: Math.round(box.y), size: Math.round(box.width) };
  if (ring && (ring.x !== here.x || ring.y !== here.y || ring.size !== here.size)) {
    throw new Error(
      `The donut moved (${JSON.stringify(here)} vs ${JSON.stringify(ring)}) in ${locale} ${theme}`,
    );
  }
  ring = here;
  let undo = await only(page, DONUT);
  await save(
    page,
    `donut-${locale}-${theme}`,
    await page.screenshot({ omitBackground: true, clip: box }),
  );
  await undo();
  // The screen without it (its centre, "Spent" and the total, stays).
  undo = await without(page, DONUT);
  await save(page, `insights-${locale}-${theme}`, await page.screenshot());
  await undo();
}

/**
 * Budgets: home's Categories tab, from "Left this month" down (every category with its bar, one
 * near its limit, one over); the bars' fills apart, on the whole screen, so the landing can grow
 * them from the left as the app does.
 */
async function budgets(page: Page, locale: string, theme: string) {
  const FILLS = ".lk-bar > span";
  await open(
    page,
    `/demo/categories?lang=${locale}`,
    page.locator("section.lk-hero"),
    page.locator(`.lk-bar.is-over > span`),
  );
  let undo = await only(page, FILLS);
  await save(
    page,
    `budget-bars-${locale}-${theme}`,
    await page.screenshot({ omitBackground: true }),
  );
  await undo();
  undo = await without(page, FILLS);
  await save(page, `budgets-${locale}-${theme}`, await page.screenshot());
  await undo();
}

const browser = await chromium.launch();
try {
  for (const theme of THEMES) {
    for (const locale of LOCALES) {
      for (const shoot of [insights, budgets]) {
        // A fresh browser per shot: the demo remembers its language for the tab.
        const context = await browser.newContext({
          viewport: { width: WIDTH, height: HEIGHT },
          deviceScaleFactor: 2,
          reducedMotion: "reduce",
          colorScheme: theme === "night" ? "dark" : "light",
        });
        await context.addInitScript((value) => {
          localStorage.setItem("wambito.theme", value);
        }, theme);
        const page = await context.newPage();
        await page.clock.install({ time: new Date(NOW) });
        await shoot(page, locale, theme);
        await context.close();
      }
    }
  }
} finally {
  await browser.close();
}

// Set inside `insights`, which TypeScript does not follow.
const placed = ring as { x: number; y: number; size: number } | null;
if (placed) {
  const pct = (value: number, of: number) => `${Math.round((value / of) * 10000) / 100}%`;
  const out = fileURLToPath(new URL("../app/features/landing/app-screen.gen.ts", import.meta.url));
  writeFileSync(
    out,
    `// Generated by \`pnpm --filter @wambito/web landing-screens\` (scripts/landing-screens.ts). Do not edit.

/** Where the donut's ring sits on the insights screenshots, as a share of the screen. */
export const DONUT_ON_SCREEN = {
  left: "${pct(placed.x, WIDTH)}",
  top: "${pct(placed.y, HEIGHT)}",
  width: "${pct(placed.size, WIDTH)}",
} as const;
`,
  );
  console.log(`Wrote ${out}`);
}
