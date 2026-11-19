#!/usr/bin/env node
// The root README's banner (docs/brand/wambi-banner.png, 2560 x 800), from the landing's own
// sources: Wambi waving (a frame of apps/web/public/wambi/wave.webp), the wordmark as `.lk-logo`
// draws it (Fredoka 700, the gold → candy gradient of tokens.json, night colours), the tagline and
// the promise in Nunito. Run from the repo root (needs Chromium from the web app's Playwright):
//
//   node docs/brand/tools/gen-banner.cjs

const fs = require("node:fs");
const path = require("node:path");
const { createRequire } = require("node:module");

const ROOT = path.resolve(__dirname, "../../..");
const WEB = path.join(ROOT, "apps/web");
const OUT = path.join(ROOT, "docs/brand/wambi-banner.png");
const webRequire = createRequire(path.join(WEB, "package.json"));

const TOKENS = JSON.parse(
  fs.readFileSync(path.join(ROOT, "docs/design/system/project/tokens.json"), "utf8"),
).color.tokens;
const night = (name) => TOKENS.find((t) => t.name === name).value.night;

/** CSS size of the banner; the PNG is SCALE times that. */
const WIDTH = 1280;
const HEIGHT = 400;
const SCALE = 2;
const WAVE = { size: 330, sprite: "public/wambi/wave.webp", columns: 4, rows: 2, frame: 2 };

const fontData = (pkg, file) =>
  fs
    .readFileSync(path.join(path.dirname(webRequire.resolve(`${pkg}/package.json`)), "files", file))
    .toString("base64");

const sparkle = (x, y, size, color) =>
  `<svg style="position:absolute;left:${x}px;top:${y}px" width="${size}" height="${size}" viewBox="0 0 24 24"><path fill="${color}" d="M12 0c.9 6.4 4.6 10.6 12 12-7.4 1.4-11.1 5.6-12 12-.9-6.4-4.6-10.6-12-12C7.4 10.6 11.1 6.4 12 0z"/></svg>`;

async function main() {
  const fredoka = fontData("@fontsource/fredoka", "fredoka-latin-700-normal.woff2");
  const nunito6 = fontData("@fontsource/nunito", "nunito-latin-600-normal.woff2");
  const nunito7 = fontData("@fontsource/nunito", "nunito-latin-700-normal.woff2");
  const sprite = fs.readFileSync(path.join(WEB, WAVE.sprite)).toString("base64");
  const col = WAVE.frame % WAVE.columns;
  const row = Math.floor(WAVE.frame / WAVE.columns);

  const html = `<html><head><style>
@font-face{font-family:Fredoka;font-weight:700;src:url(data:font/woff2;base64,${fredoka}) format("woff2")}
@font-face{font-family:Nunito;font-weight:600;src:url(data:font/woff2;base64,${nunito6}) format("woff2")}
@font-face{font-family:Nunito;font-weight:700;src:url(data:font/woff2;base64,${nunito7}) format("woff2")}
body{margin:0;background:transparent}
#b{position:relative;width:${WIDTH}px;height:${HEIGHT}px;border-radius:28px;overflow:hidden;
background:radial-gradient(circle at 18% 30%,${night("bg-glow")} 0,transparent 55%),${night("bg")}}
#w{position:absolute;left:70px;top:${(HEIGHT - WAVE.size) / 2}px;width:${WAVE.size}px;height:${WAVE.size}px;
background:url(data:image/webp;base64,${sprite}) no-repeat;background-size:${WAVE.columns * 100}% ${WAVE.rows * 100}%;
background-position:${(col / (WAVE.columns - 1)) * 100}% ${(row / (WAVE.rows - 1)) * 100}%}
#t{position:absolute;left:465px;top:78px}
.mark{display:block;font-family:Fredoka;font-weight:700;font-size:150px;line-height:1.05;letter-spacing:-1px}
#shadow{position:absolute;left:0;top:7px;color:${night("brand-edge")}}
#mark{position:relative;background:linear-gradient(90deg,${night("gold")},${night("candy")});-webkit-background-clip:text;background-clip:text;color:transparent}
#tag{margin-top:8px;font-family:Nunito;font-weight:700;font-size:40px;color:${night("good")}}
#sub{margin-top:6px;font-family:Nunito;font-weight:600;font-size:26px;color:${night("ink-muted")}}
</style></head><body><div id="b">
${sparkle(48, 46, 22, night("gold"))}${sparkle(420, 62, 16, night("gold"))}${sparkle(1185, 56, 22, night("gold"))}${sparkle(1112, 330, 16, night("good"))}
<div id="w"></div>
<div id="t"><div style="position:relative"><span class="mark" id="shadow">Wambito</span><span class="mark" id="mark">Wambito</span></div>
<div id="tag">Tus lukas, por fin claras.</div>
<div id="sub">Gratis para siempre · Código abierto</div></div>
</div></body></html>`;

  const { chromium } = webRequire("playwright");
  const browser = await chromium.launch();
  const page = await browser.newPage({
    deviceScaleFactor: SCALE,
    viewport: { width: WIDTH, height: HEIGHT },
  });
  await page.setContent(html);
  await page.evaluate(() => document.fonts.ready);
  await page.locator("#b").screenshot({ path: OUT, omitBackground: true });
  await browser.close();
  console.log(`${path.relative(ROOT, OUT)}: ${WIDTH * SCALE} x ${HEIGHT * SCALE} px`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
