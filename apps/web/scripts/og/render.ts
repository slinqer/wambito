/**
 * Renders the Open Graph images, public/og-es.png, og-en.png, og-it.png and og-pt.png (1200×630), from og.html
 * with headless Chromium (Playwright's). The copy comes from the message catalogs, so the images
 * say exactly what the landing page says.
 *
 *   pnpm --filter @wambito/web og          (all four)
 *   pnpm --filter @wambito/web og it pt    (only those)
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ALL_LOCALES = ["es", "en", "it", "pt"] as const;
/** Every language, or only the ones named (`pnpm og it pt`). */
const LOCALES = ALL_LOCALES.filter(
  (locale) => process.argv.length <= 2 || process.argv.slice(2).includes(locale),
);
const template = new URL("./og.html", import.meta.url);

function catalog(locale: string): Record<string, unknown> {
  const path = fileURLToPath(new URL(`../../app/i18n/messages/${locale}.json`, import.meta.url));
  return JSON.parse(readFileSync(path, "utf8")).landing;
}

function lookup(tree: Record<string, unknown>, key: string): string {
  const value = key.split(".").reduce<unknown>((node, part) => {
    return node && typeof node === "object" ? (node as Record<string, unknown>)[part] : undefined;
  }, tree);
  if (typeof value !== "string") throw new Error(`Missing landing.${key}`);
  return value;
}

/**
 * A catalog message as HTML: the text escaped, and its rich-text tags (`<mark>lukas</mark>`,
 * `<lead>…</lead>`, the ones the page renders with `t.rich`) as `<span class="rich-mark">` for the template to style.
 */
function richHtml(message: string): string {
  const escaped = message.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  return escaped.replace(/&lt;([a-z_]+)&gt;(.*?)&lt;\/\1&gt;/g, '<span class="rich-$1">$2</span>');
}

const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 } });
  for (const locale of LOCALES) {
    const messages = catalog(locale);
    await page.goto(template.href);
    const keys = await page
      .locator("[data-copy]")
      .evaluateAll((nodes) => nodes.map((node) => node.getAttribute("data-copy") ?? ""));
    const copy = Object.fromEntries(keys.map((key) => [key, richHtml(lookup(messages, key))]));
    await page.evaluate(
      ({ copy, locale }) => {
        document.documentElement.lang = locale;
        for (const node of document.querySelectorAll<HTMLElement>("[data-copy]")) {
          node.innerHTML = copy[node.dataset.copy ?? ""] ?? "";
        }
      },
      { copy, locale },
    );
    await page.evaluate(async () => {
      await document.fonts.ready;
      await Promise.all(["700 74px Fredoka", "800 26px Nunito"].map((f) => document.fonts.load(f)));
    });
    const out = fileURLToPath(new URL(`../../public/og-${locale}.png`, import.meta.url));
    await page.screenshot({ path: out, clip: { x: 0, y: 0, width: 1200, height: 630 } });
    console.log(`Wrote ${out}`);
  }
} finally {
  await browser.close();
}
