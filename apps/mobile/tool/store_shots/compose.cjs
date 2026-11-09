#!/usr/bin/env node
// The store listing images from the raw screenshots (tool/store_shots/run.sh) and Wambi's art:
// each phone screenshot is framed on the brand's night plum with a headline in the listing's
// language and Wambi beside it (1080×1920, 9:16), and the feature graphic (1024×500) is Wambi and the
// wordmark, no other text, the same in every locale. Rendered with the web app's Playwright Chromium
// and the brand fonts (Fredoka, Nunito), then written as JPEG (Play and F-Droid take it; a PNG of a
// 3D-rendered Wambi is several times bigger).
//
//   node apps/mobile/tool/store_shots/compose.cjs [--only <listing>]
//
// Reads apps/mobile/build/store_shots/<device locale>/*.png and docs/brand/wambi-store-*.webp; writes
// apps/mobile/fastlane/metadata/android/<listing>/images/{phoneScreenshots/*.jpg,featureGraphic.jpg}.
// Needs `magick` (ImageMagick) for the JPEG step.

const fs = require("node:fs");
const path = require("node:path");
const { createRequire } = require("node:module");
const { spawnSync } = require("node:child_process");

const ROOT = path.resolve(__dirname, "../../../..");
const MOBILE = path.join(ROOT, "apps/mobile");
const META = path.join(MOBILE, "fastlane/metadata/android");
const RAW = path.join(MOBILE, "build/store_shots");
const BRAND = path.join(ROOT, "docs/brand");
const webRequire = createRequire(path.join(ROOT, "apps/web/package.json"));

/** Listing folder → the device locale its screenshots were taken in (its currency). */
const LISTINGS = {
  "es-419": "es-CO",
  "es-ES": "es-ES",
  "en-US": "en-US",
  "it-IT": "it-IT",
  "pt-PT": "pt-PT",
};

/** The screens, in listing order: raw screenshot, Wambi's pose, and the words per language. */
const SCREENS = [
  { shot: "1_home", wambi: "home" },
  { shot: "3_capture", wambi: "voice" },
  { shot: "4_review", wambi: "review" },
  { shot: "2_add", wambi: "add" },
  { shot: "5_budgets", wambi: "budget" },
  { shot: "6_insights", wambi: "insights" },
];

/** [headline, line under it] per screen, in SCREENS order. */
const WORDS = {
  "es-419": [
    ["Tu mes, claro de un vistazo", "Cuánto llevas, qué viene y qué te queda"],
    ["Dilo o escríbelo", "«15 mil en almuerzo y 3 lukas en uber»: listo"],
    ["Tus gastos se anotan solos", "Lee las notificaciones de tu banco, en tu teléfono"],
    ["Anota un gasto en segundos", "Monto, categoría y ya"],
    ["Presupuestos que se entienden", "Mira cuánto te queda en cada categoría"],
    ["Mira en qué se te va la plata", "Tu mes por categoría, sin hojas de cálculo"],
  ],
  "es-ES": [
    ["Tu mes, claro de un vistazo", "Cuánto llevas, qué viene y qué te queda"],
    ["Dilo o escríbelo", "«12 euros en el súper y 3 en el metro»: listo"],
    ["Tus gastos se anotan solos", "Lee las notificaciones de tu banco, en tu teléfono"],
    ["Apunta un gasto en segundos", "Importe, categoría y listo"],
    ["Presupuestos que se entienden", "Mira cuánto te queda en cada categoría"],
    ["Mira en qué se va tu dinero", "Tu mes por categoría, sin hojas de cálculo"],
  ],
  "en-US": [
    ["Your month, clear at a glance", "What you've spent, what's due, what's left"],
    ["Say it or type it", "“15 on lunch and 3 on the bus”: done"],
    ["Expenses that log themselves", "Reads your bank's notifications, on your phone"],
    ["Log an expense in seconds", "Amount, category, done"],
    ["Budgets that make sense", "See what's left in every category"],
    ["See where your money goes", "Your month by category, no spreadsheets"],
  ],
  "it-IT": [
    ["Il tuo mese, chiaro a colpo d'occhio", "Quanto hai speso, cosa arriva, cosa resta"],
    ["Dillo o scrivilo", "«12 euro di spesa e 3 di autobus»: fatto"],
    ["Le spese si annotano da sole", "Legge le notifiche della tua banca, sul telefono"],
    ["Annota una spesa in pochi secondi", "Importo, categoria e basta"],
    ["Budget che si capiscono", "Guarda quanto resta in ogni categoria"],
    ["Scopri dove vanno i tuoi soldi", "Il tuo mese per categoria, senza fogli di calcolo"],
  ],
  "pt-PT": [
    ["O teu mês, claro num relance", "Quanto gastaste, o que vem e o que sobra"],
    ["Di-lo ou escreve-o", "«12 euros no supermercado e 3 no metro»: feito"],
    ["As despesas registam-se sozinhas", "Lê as notificações do teu banco, no telemóvel"],
    ["Regista uma despesa em segundos", "Valor, categoria e pronto"],
    ["Orçamentos que se percebem", "Vê quanto sobra em cada categoria"],
    ["Vê para onde vai o teu dinheiro", "O teu mês por categoria, sem folhas de cálculo"],
  ],
};

const dataUrl = (file, type) => `data:${type};base64,${fs.readFileSync(file).toString("base64")}`;
const font = (pkg, file) =>
  dataUrl(
    path.join(path.dirname(webRequire.resolve(`${pkg}/package.json`)), "files", file),
    "font/woff2",
  );
const FONTS = `
@font-face { font-family: Fredoka; font-weight: 700; src: url(${font("@fontsource/fredoka", "fredoka-latin-700-normal.woff2")}); }
@font-face { font-family: Nunito; font-weight: 700; src: url(${font("@fontsource/nunito", "nunito-latin-700-normal.woff2")}); }
`;

/** Night plum, as the landing's hero: a soft violet glow over a deep plum. */
const BACKGROUND = `radial-gradient(120% 70% at 20% 0%, #3d2470 0%, #24133f 55%, #170c29 100%)`;

const sparkles = (spots) =>
  spots
    .map(
      ([x, y, s, c]) =>
        `<svg style="position:absolute;left:${x}px;top:${y}px;width:${s}px;height:${s}px" viewBox="0 0 24 24"><path fill="${c}" d="M12 0c1 6.5 5.5 11 12 12-6.5 1-11 5.5-12 12-1-6.5-5.5-11-12-12C6.5 11 11 6.5 12 0Z"/></svg>`,
    )
    .join("");

function screenshotHtml({ headline, line, shot, wambi, flip }) {
  return `<!doctype html><html><head><style>${FONTS}
  * { margin: 0; box-sizing: border-box; }
  body { width: 1080px; height: 1920px; overflow: hidden; position: relative; background: ${BACKGROUND}; }
  h1 { position: absolute; top: 110px; left: 80px; right: 80px; text-align: center; font: 700 82px/1.08 Fredoka;
       color: #fff6d6; letter-spacing: -0.5px; text-wrap: balance; }
  p { position: absolute; top: 330px; left: 110px; right: 110px; text-align: center; font: 700 40px/1.3 Nunito;
      color: #c9b8ff; text-wrap: balance; }
  .phone { position: absolute; left: 50%; top: 520px; width: 660px; height: 1467px; margin-left: -330px;
           border-radius: 74px; background: #0b0614; padding: 18px;
           box-shadow: 0 40px 90px rgba(0,0,0,.55), 0 0 0 3px #4a3a6e inset; }
  .phone img { width: 624px; height: 1387px; border-radius: 58px; display: block; object-fit: cover; object-position: top; }
  .wambi { position: absolute; bottom: -10px; ${flip ? "right: -30px" : "left: -30px"}; width: 330px; height: 330px;
           filter: drop-shadow(0 24px 30px rgba(0,0,0,.45)); }
  .glow { position: absolute; bottom: -120px; ${flip ? "right" : "left"}: -120px; width: 620px; height: 620px;
          background: radial-gradient(circle, rgba(250,196,23,.28), rgba(250,196,23,0) 65%); }
  </style></head><body>
  ${sparkles([
    [90, 470, 34, "#fac417"],
    [960, 250, 28, "#fac417"],
    [980, 640, 22, "#7ef0c0"],
    [60, 980, 20, "#ff8fd8"],
  ])}
  <h1>${headline}</h1><p>${line}</p>
  <div class="glow"></div>
  <div class="phone"><img src="${dataUrl(shot, "image/png")}"></div>
  <img class="wambi" src="${dataUrl(wambi, "image/webp")}">
  </body></html>`;
}

function featureHtml({ wambi, logo }) {
  return `<!doctype html><html><head><style>
  * { margin: 0; }
  body { width: 1024px; height: 500px; overflow: hidden; position: relative; background: ${BACKGROUND}; }
  .wambi { position: absolute; left: 70px; top: 30px; width: 440px; height: 440px; filter: drop-shadow(0 20px 26px rgba(0,0,0,.45)); }
  .glow { position: absolute; left: -40px; top: -80px; width: 660px; height: 660px;
          background: radial-gradient(circle, rgba(250,196,23,.25), rgba(250,196,23,0) 62%); }
  .logo { position: absolute; left: 500px; top: 175px; width: 450px; }
  </style></head><body>
  ${sparkles([
    [40, 50, 26, "#fac417"],
    [560, 70, 20, "#fac417"],
    [960, 60, 28, "#fac417"],
    [930, 420, 22, "#7ef0c0"],
  ])}
  <div class="glow"></div>
  <img class="wambi" src="${dataUrl(wambi, "image/webp")}">
  <img class="logo" src="data:image/svg+xml;base64,${Buffer.from(logo).toString("base64")}">
  </body></html>`;
}

/** The dark logo without its own backdrop, so the wordmark sits on the night plum. */
function logoOnNight() {
  const svg = fs.readFileSync(path.join(BRAND, "wambito-logo-dark.svg"), "utf8");
  const backdrop = /<rect width="\d+" height="\d+" fill="#[0-9A-Fa-f]{6}"\/>/;
  if (!backdrop.test(svg))
    throw new Error("wambito-logo-dark.svg: no backdrop to drop; check the feature graphic");
  return svg.replace(backdrop, "");
}

function toJpeg(png, jpg) {
  const r = spawnSync(
    "magick",
    [png, "-strip", "-sampling-factor", "4:2:0", "-quality", "86", "-interlace", "JPEG", jpg],
    {
      stdio: "inherit",
    },
  );
  if (r.status !== 0) throw new Error(`magick failed on ${png}`);
  fs.rmSync(png);
}

async function main() {
  const only = process.argv.includes("--only")
    ? process.argv[process.argv.indexOf("--only") + 1]
    : null;
  const { chromium } = webRequire("playwright");
  const browser = await chromium.launch();
  const wambiArt = (pose) => path.join(BRAND, `wambi-store-${pose}.webp`);
  try {
    for (const [listing, device] of Object.entries(LISTINGS)) {
      if (only && only !== listing) continue;
      const images = path.join(META, listing, "images");
      const shotsDir = path.join(images, "phoneScreenshots");
      fs.rmSync(shotsDir, { recursive: true, force: true });
      fs.mkdirSync(shotsDir, { recursive: true });

      const page = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
      for (const [i, screen] of SCREENS.entries()) {
        const shot = path.join(RAW, device, `${screen.shot}.png`);
        if (!fs.existsSync(shot))
          throw new Error(`no raw screenshot ${shot}: run tool/store_shots/run.sh ${device}`);
        const [headline, line] = WORDS[listing][i];
        await page.setContent(
          screenshotHtml({
            headline,
            line,
            shot,
            wambi: wambiArt(screen.wambi),
            flip: i % 2 === 1,
          }),
        );
        await page.evaluate(() => document.fonts.ready);
        const png = path.join(shotsDir, `${i + 1}_${screen.shot.replace(/^\d_/, "")}.png`);
        await page.screenshot({ path: png });
        toJpeg(png, png.replace(/\.png$/, ".jpg"));
      }
      await page.close();

      const feature = await browser.newPage({ viewport: { width: 1024, height: 500 } });
      await feature.setContent(featureHtml({ wambi: wambiArt("feature"), logo: logoOnNight() }));
      const png = path.join(images, "featureGraphic.png");
      await feature.screenshot({ path: png });
      toJpeg(png, path.join(images, "featureGraphic.jpg"));
      await feature.close();
      console.log(`${listing}: ${SCREENS.length} screenshots and the feature graphic`);
    }
  } finally {
    await browser.close();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
