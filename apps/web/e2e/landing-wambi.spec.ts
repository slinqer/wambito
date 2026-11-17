import { existsSync, readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { gzipSync } from "node:zlib";
import { expect, type Page, test } from "@playwright/test";

/**
 * Wambi on the built landing page, with JavaScript on: he stands still on his one spot, the
 * closing, and nothing mounts over the page (no traveling Wambi rolling in, following the
 * scroll or hopping when tapped). Also the JavaScript budget of `/`.
 */

test.use({ javaScriptEnabled: true });
test.describe.configure({ timeout: 60_000 });

const BUILD = fileURLToPath(new URL("../build/", import.meta.url));
const CLIENT = `${BUILD}client/`;
const BUDGET_GZIP = 300 * 1024;
/** A string every three.js build carries (its renderer's class name survives minification). */
const THREE_SIGNATURE = "WebGLRenderer";

/** Collects console errors and page errors for the whole test. */
function collectErrors(page: Page): string[] {
  const errors: string[] = [];
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });
  page.on("pageerror", (error) => errors.push(error.message));
  return errors;
}

test.describe("still Wambi", () => {
  test("stands still on his spot once the page is idle, and ignores the pointer", async ({
    page,
  }) => {
    const errors = collectErrors(page);
    await page.goto("/");
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(1500);
    await expect(page.locator("[data-wambi-traveler]")).toHaveCount(0);
    await expect(page.locator("html")).not.toHaveAttribute("data-wambi-live", /.+/);
    for (const spot of ["closing"]) {
      const wambi = page.locator(`[data-wambi-spot='${spot}'] > *`);
      await wambi.scrollIntoViewIfNeeded();
      await expect(wambi).toBeVisible();
      expect(await wambi.evaluate((el) => el.getAnimations({ subtree: true }).length)).toBe(0);
    }
    // A click on him changes nothing: no animation starts, nothing navigates.
    const resting = page.locator("[data-wambi-spot='closing']");
    await resting.scrollIntoViewIfNeeded();
    await resting.click({ force: true });
    expect(await resting.evaluate((el) => el.getAnimations({ subtree: true }).length)).toBe(0);
    await expect(page).toHaveURL(/\/$/);
    expect(errors).toEqual([]);
  });
});

interface ManifestChunk {
  file: string;
  src?: string;
  isEntry?: boolean;
  imports?: string[];
  dynamicImports?: string[];
}

test.describe("JavaScript budget", () => {
  test("the initial JavaScript of / stays under 300 KB gzipped, with no three.js anywhere", async ({
    request,
  }, testInfo) => {
    // Vite's manifest is moved out of what ships (react-router.config.ts).
    expect(existsSync(`${CLIENT}.vite`)).toBe(false);
    const manifest = JSON.parse(readFileSync(`${BUILD}vite-manifest.json`, "utf8")) as Record<
      string,
      ManifestChunk
    >;
    const byFile = new Map(Object.entries(manifest).map(([key, chunk]) => [chunk.file, key]));

    // What the prerendered page loads: its module scripts and modulepreloads, plus everything
    // they import statically (never their dynamic imports: those load on demand).
    const html = await (await request.get("/")).text();
    const urls = [
      ...html.matchAll(/<(?:script|link)[^>]+(?:src|href)="\/(assets\/[^"]+\.js)"/g),
      ...html.matchAll(/import\(?\s*"\/(assets\/[^"]+\.js)"/g),
      ...html.matchAll(/from\s*"\/(assets\/[^"]+\.js)"/g),
    ].map((m) => m[1] as string);
    expect(urls.length).toBeGreaterThan(0);

    const initial = new Set<string>();
    const visit = (key: string) => {
      const chunk = manifest[key];
      if (!chunk || initial.has(chunk.file)) return;
      initial.add(chunk.file);
      for (const next of chunk.imports ?? []) visit(next);
    };
    for (const url of urls) {
      const key = byFile.get(url);
      // React Router's route manifest (assets/manifest-*.js) is written after Vite's: count it as is.
      if (key) visit(key);
      else initial.add(url);
    }
    expect([...initial].some((file) => manifest[byFile.get(file) ?? ""]?.isEntry)).toBe(true);

    // The 3D experiment is never built into the site: no chunk at all carries three.js.
    const chunks = readdirSync(`${CLIENT}assets`).filter((file) => file.endsWith(".js"));
    const withThree = chunks.filter((file) =>
      readFileSync(`${CLIENT}assets/${file}`, "utf8").includes(THREE_SIGNATURE),
    );
    expect(withThree).toEqual([]);
    for (const chunk of Object.values(manifest)) {
      expect(chunk.src ?? "").not.toMatch(/node_modules\/(three|@react-three)\/|\/experimental\//);
    }

    const inline = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)]
      .map((m) => m[1] ?? "")
      .join("\n");
    const gzip = (text: string | Buffer) => gzipSync(text, { level: 9 }).length;
    const initialBytes =
      [...initial].reduce((sum, file) => sum + gzip(readFileSync(`${CLIENT}${file}`)), 0) +
      gzip(inline);
    testInfo.annotations.push({
      type: "js-budget",
      description: `initial ${(initialBytes / 1024).toFixed(1)} KB gz (${initial.size} files); ${chunks.length} chunks, none with three.js`,
    });
    console.log(testInfo.annotations.at(-1)?.description);
    expect(initialBytes).toBeLessThan(BUDGET_GZIP);
  });
});
