#!/usr/bin/env node
// The Wambito icon family from one fitted geometry (docs/brand/wambito-icon.svg is the master).
//
// The geometry below was fitted to the chosen concept (concept 1 of the ChatGPT exploration) by
// minimising the pixel difference against it; the colours are the medians of its flat areas.
// Change a number here, then regenerate everything with (repo root, needs Chromium from the web
// app's Playwright, and opentype.js for the wordmark):
//
//   npm i --no-save --prefix /tmp/wambito-icon opentype.js@1.3.4
//   NODE_PATH=/tmp/wambito-icon/node_modules node docs/brand/tools/gen-icon.cjs
//
// It writes the SVGs in docs/brand, the Android adaptive icon (vector drawables) and legacy
// mipmaps, the F-Droid icon, the web favicon.svg/.ico and apple-touch-icon, the iOS app icon set
// (apps/mobile/ios, the 1024 light, dark and tinted images its Contents.json lists), and the review sheet
// docs/brand/wambito-icon-preview.png (quantised with ImageMagick when `magick` is installed).
// `--svg-only` skips the PNGs. The module also exports the builders (used by the fitting script).

const fs = require("node:fs");
const path = require("node:path");
const { createRequire } = require("node:module");
const { spawnSync } = require("node:child_process");

const ROOT = path.resolve(__dirname, "../../..");
const BRAND = path.join(ROOT, "docs/brand");
const RES = path.join(ROOT, "apps/mobile/android/app/src/main/res");
const PUBLIC = path.join(ROOT, "apps/web/public");
const IOS_ICONS = path.join(ROOT, "apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset");

/** Sampled from the concept (medians of its flat areas). Plum and gold come from tokens.json. */
const TOKENS = JSON.parse(
  fs.readFileSync(path.join(ROOT, "docs/design/system/project/tokens.json"), "utf8"),
).color.tokens;
const token = (name) => TOKENS.find((t) => t.name === name).value.day.toUpperCase();
const COLORS = {
  plum: token("brand-plum"), // #422145: the tile and every feature
  gold: token("brand-gold"), // #FAC417: the coin
  white: "#FEFEFE", // the eye whites and shines, as sampled
  blush: "#F38691", // the cheeks; no UI token is this pink
};

/** The logo's wordmark: the gold → candy gradient of tokens.json (day and night). */
const WORDMARK = {
  day: { from: "#FFD23F", to: "#E0408F" },
  night: { from: "#FFE66D", to: "#FF8FD8", bg: "#15122B" },
};

/** Fitted geometry, in a 1024 × 1024 tile. */
const P = {
  tileR: 211.4,
  coin: { cx: 506.3, cy: 516.3, r: 435.8 },
  ring: { cx: 505.4, cy: 513.7, r: 364.1, w: 24 },
  browL: { x0: 296.6, y0: 343.8, cx: 339.5, cy: 323.1, x1: 401.5, y1: 311.3, w: 47 },
  browR: { x0: 636.2, y0: 285.6, cx: 685.6, cy: 290, x1: 731.3, y1: 304.1, w: 48.8 },
  eyeL: { cx: 370.6, cy: 498.5, rx: 111.4, ry: 112.3, rot: 1.3 },
  eyeR: { cx: 677.8, cy: 481.4, rx: 99.6, ry: 109.1, rot: -4.3 },
  pupilL: { cx: 412.2, cy: 493.3, rx: 74.8, ry: 79.4, rot: -0.7 },
  pupilR: { cx: 714.1, cy: 467.3, rx: 73.1, ry: 78.9, rot: 0.4 },
  shineL: { cx: 435.9, cy: 457.9, r: 24.8 },
  shineR: { cx: 736.2, cy: 433.2, r: 24.5 },
  blushL: { cx: 281.4, cy: 653, w: 127, h: 85.7, r: 43.3, rot: 0 },
  blushR: { cx: 737.5, cy: 643.1, w: 126.4, h: 86.8, r: 42.5, rot: -1.1 },
  mouth: {
    lx: 450.3,
    ly: 632.1,
    rx: 598.3,
    ry: 629.5,
    tx: 520.8,
    ty: 644.7,
    c1x: 587.4,
    c1y: 715,
    c2x: 464.2,
    c2y: 721.2,
    sw: 7.9,
  },
};

const n = (v) => {
  const s = (Math.round(v * 100) / 100).toString();
  return s === "-0" ? "0" : s;
};

function roundedSquare(size, r) {
  return (
    `M${n(r)} 0H${n(size - r)}A${n(r)} ${n(r)} 0 0 1 ${size} ${n(r)}V${n(size - r)}` +
    `A${n(r)} ${n(r)} 0 0 1 ${n(size - r)} ${size}H${n(r)}A${n(r)} ${n(r)} 0 0 1 0 ${n(size - r)}` +
    `V${n(r)}A${n(r)} ${n(r)} 0 0 1 ${n(r)} 0Z`
  );
}

/** An ellipse as two arcs (vector drawables have no <ellipse>), rotated by rot degrees. */
function ellipse({ cx, cy, rx, ry, rot = 0 }) {
  const a = (rot * Math.PI) / 180;
  const dx = rx * Math.cos(a);
  const dy = rx * Math.sin(a);
  return (
    `M${n(cx - dx)} ${n(cy - dy)}A${n(rx)} ${n(ry)} ${n(rot)} 1 0 ${n(cx + dx)} ${n(cy + dy)}` +
    `A${n(rx)} ${n(ry)} ${n(rot)} 1 0 ${n(cx - dx)} ${n(cy - dy)}Z`
  );
}

const circle = ({ cx, cy, r }) => ellipse({ cx, cy, rx: r, ry: r });

/** A rounded rectangle (the blush pills), rotated by rot degrees about its centre. */
function pill({ cx, cy, w, h, r, rot = 0 }) {
  const rr = Math.min(r, w / 2, h / 2);
  const a = (rot * Math.PI) / 180;
  const t = (x, y) =>
    `${n(cx + x * Math.cos(a) - y * Math.sin(a))} ${n(cy + x * Math.sin(a) + y * Math.cos(a))}`;
  const hw = w / 2;
  const hh = h / 2;
  const arc = (x, y) => `A${n(rr)} ${n(rr)} ${n(rot)} 0 1 ${t(x, y)}`;
  return (
    `M${t(-hw + rr, -hh)}L${t(hw - rr, -hh)}${arc(hw, -hh + rr)}L${t(hw, hh - rr)}` +
    `${arc(hw - rr, hh)}L${t(-hw + rr, hh)}${arc(-hw, hh - rr)}L${t(-hw, -hh + rr)}` +
    `${arc(-hw + rr, -hh)}Z`
  );
}

const browLine = (b) => `M${n(b.x0)} ${n(b.y0)}Q${n(b.cx)} ${n(b.cy)} ${n(b.x1)} ${n(b.y1)}`;

/** A brow's outline (for the one-shape monochrome): the curve offset both ways, round ends. */
function browOutline(b, steps = 24) {
  const pt = (t) => [
    (1 - t) ** 2 * b.x0 + 2 * (1 - t) * t * b.cx + t * t * b.x1,
    (1 - t) ** 2 * b.y0 + 2 * (1 - t) * t * b.cy + t * t * b.y1,
  ];
  const tan = (t) => {
    const x = 2 * (1 - t) * (b.cx - b.x0) + 2 * t * (b.x1 - b.cx);
    const y = 2 * (1 - t) * (b.cy - b.y0) + 2 * t * (b.y1 - b.cy);
    const l = Math.hypot(x, y);
    return [x / l, y / l];
  };
  const h = b.w / 2;
  const left = [];
  const right = [];
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const [x, y] = pt(t);
    const [tx, ty] = tan(t);
    left.push([x + ty * h, y - tx * h]);
    right.push([x - ty * h, y + tx * h]);
  }
  const s = (p) => `${n(p[0])} ${n(p[1])}`;
  const cap = (p) => `A${n(h)} ${n(h)} 0 0 1 ${s(p)}`;
  return (
    `M${s(left[0])}${left
      .slice(1)
      .map((p) => `L${s(p)}`)
      .join("")}` +
    `${cap(right[steps])}${right
      .slice(0, steps)
      .reverse()
      .map((p) => `L${s(p)}`)
      .join("")}` +
    `${cap(left[0])}Z`
  );
}

function mouth(m) {
  return (
    `M${n(m.lx)} ${n(m.ly)}Q${n(m.tx)} ${n(m.ty)} ${n(m.rx)} ${n(m.ry)}` +
    `C${n(m.c1x)} ${n(m.c1y)} ${n(m.c2x)} ${n(m.c2y)} ${n(m.lx)} ${n(m.ly)}Z`
  );
}

/**
 * The coin and face as layers, painted in order: {fill | stroke, d, width?, evenOdd?, join?}.
 * Brows are round-capped strokes; the mouth is a fill with a thin round-joined stroke.
 */
function layers(p = P, c = COLORS) {
  const ring = [
    circle({ cx: p.ring.cx, cy: p.ring.cy, r: p.ring.r + p.ring.w / 2 }),
    circle({ cx: p.ring.cx, cy: p.ring.cy, r: p.ring.r - p.ring.w / 2 }),
  ].join("");
  return [
    { fill: c.gold, d: circle(p.coin) },
    { fill: c.plum, d: ring, evenOdd: true },
    {
      stroke: c.plum,
      d: browLine(p.browL) + browLine(p.browR),
      width: p.browL.w,
      widthR: p.browR.w,
    },
    { fill: c.white, d: ellipse(p.eyeL) + ellipse(p.eyeR) },
    { fill: c.plum, d: ellipse(p.pupilL) + ellipse(p.pupilR) },
    { fill: c.white, d: circle(p.shineL) + circle(p.shineR) },
    { fill: c.blush, d: pill(p.blushL) + pill(p.blushR) },
    { fill: c.plum, stroke: c.plum, d: mouth(p.mouth), width: p.mouth.sw, join: true },
  ];
}

/** Brows may differ in width: split that layer in two when they do. */
function expand(ls, p = P) {
  return ls.flatMap((l) =>
    l.widthR !== undefined && l.widthR !== l.width
      ? [
          { stroke: l.stroke, d: browLine(p.browL), width: p.browL.w },
          { stroke: l.stroke, d: browLine(p.browR), width: p.browR.w },
        ]
      : [l],
  );
}

function svgPaths(p = P, c = COLORS, indent = "  ") {
  return expand(layers(p, c), p)
    .map((l) => {
      const a = [];
      a.push(`fill="${l.fill ?? "none"}"`);
      if (l.evenOdd) a.push('fill-rule="evenodd"');
      if (l.stroke) {
        a.push(`stroke="${l.stroke}" stroke-width="${n(l.width)}"`);
        a.push(l.join ? 'stroke-linejoin="round"' : 'stroke-linecap="round"');
      }
      return `${indent}<path ${a.join(" ")} d="${l.d}"/>\n`;
    })
    .join("");
}

/** The master icon: the tile (rounded, or square for apple-touch-icon) and the coin. */
function iconSvg(p = P, { square = false } = {}) {
  const tile = square
    ? `  <rect width="1024" height="1024" fill="${COLORS.plum}"/>\n`
    : `  <path fill="${COLORS.plum}" d="${roundedSquare(1024, p.tileR)}"/>\n`;
  return svg(1024, 1024, "Wambito", tile + svgPaths(p));
}

function svg(w, h, title, body) {
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}">\n` +
    `<title>${title}</title>\n${body}</svg>\n`
  );
}

// Android adaptive icon: a 108 dp canvas = 1536 units, its 72 dp viewport = the master's 1024.
const FG = 1536;
const SAFE_R = 338; // the 66 dp safe circle, in master units (66 / 72 × 1024 / 2)

/** How far the face reaches from the coin's centre: the furthest point of every feature. */
function faceReach(p = P) {
  const pts = [];
  const add = (x, y) => pts.push(Math.hypot(x - p.coin.cx, y - p.coin.cy));
  for (const b of [p.browL, p.browR])
    for (const [x, y] of [
      [b.x0, b.y0],
      [b.x1, b.y1],
    ])
      add(x, y);
  const browPad = Math.max(p.browL.w, p.browR.w) / 2;
  const reach = [Math.max(...pts) + browPad];
  for (const e of [p.eyeL, p.eyeR, p.blushL, p.blushR]) {
    const rx = e.rx ?? e.w / 2;
    const ry = e.ry ?? e.h / 2;
    for (let a = 0; a < 360; a += 5) {
      const t = (a * Math.PI) / 180;
      reach.push(
        Math.hypot(e.cx + rx * Math.cos(t) - p.coin.cx, e.cy + ry * Math.sin(t) - p.coin.cy),
      );
    }
  }
  const m = p.mouth;
  for (const [x, y] of [
    [m.lx, m.ly],
    [m.rx, m.ry],
    [(m.c1x + m.c2x) / 2, (m.c1y + m.c2y) / 2],
  ]) {
    reach.push(Math.hypot(x - p.coin.cx, y - p.coin.cy) + m.sw / 2);
  }
  return Math.max(...reach);
}

/** The coin moved to the canvas centre and, only if the face leaves the safe circle, scaled down. */
function adaptiveTransform(p = P) {
  const s = Math.min(1, SAFE_R / faceReach(p));
  const tx = FG / 2 - s * p.coin.cx;
  const ty = FG / 2 - s * p.coin.cy;
  return { s, tx, ty };
}

/** One even-odd shape for themed icons: the coin solid, the ring, brows, pupils and mouth cut
 * out, the shines left solid inside the pupils. */
function monoPath(p = P) {
  return [
    circle(p.coin),
    circle({ cx: p.ring.cx, cy: p.ring.cy, r: p.ring.r + p.ring.w / 2 }),
    circle({ cx: p.ring.cx, cy: p.ring.cy, r: p.ring.r - p.ring.w / 2 }),
    browOutline(p.browL),
    browOutline(p.browR),
    ellipse(p.pupilL),
    ellipse(p.pupilR),
    circle(p.shineL),
    circle(p.shineR),
    mouth(p.mouth),
  ].join("");
}

function vectorDrawable(paths, { s, tx, ty }) {
  const body = paths
    .map((l) => {
      const a = [];
      if (l.fill) a.push(`android:fillColor="${l.fill}"`);
      if (l.evenOdd) a.push('android:fillType="evenOdd"');
      if (l.stroke) {
        a.push(`android:strokeColor="${l.stroke}"`, `android:strokeWidth="${n(l.width)}"`);
        a.push(l.join ? 'android:strokeLineJoin="round"' : 'android:strokeLineCap="round"');
      }
      a.push(`android:pathData="${l.d}"`);
      return `        <path\n            ${a.join("\n            ")} />\n`;
    })
    .join("");
  return (
    '<?xml version="1.0" encoding="utf-8"?>\n' +
    "<!-- Generated by docs/brand/tools/gen-icon.cjs: 108 dp canvas, 72 dp viewport inside. -->\n" +
    '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n' +
    '    android:width="108dp"\n    android:height="108dp"\n' +
    `    android:viewportWidth="${FG}"\n    android:viewportHeight="${FG}">\n` +
    `    <group\n        android:scaleX="${n(s)}"\n        android:scaleY="${n(s)}"\n` +
    `        android:translateX="${n(tx)}"\n        android:translateY="${n(ty)}">\n` +
    `${body}    </group>\n</vector>\n`
  );
}

function logoSvg(variant) {
  // opentype.js turns "Wambito" in Fredoka Bold (the logo style of tokens.json: 700) into a path.
  const opentype = require("opentype.js");
  const woff = path.join(
    path.dirname(
      createRequire(path.join(ROOT, "apps/web/package.json")).resolve(
        "@fontsource/fredoka/700.css",
      ),
    ),
    "files/fredoka-latin-700-normal.woff",
  );
  const font = opentype.loadSync(woff);
  const glyphs = font.getPath("Wambito", 0, 0, 600, { kerning: true });
  const box = glyphs.getBoundingBox();
  const gap = 104;
  const tx = 1024 + gap - box.x1;
  const ty = 512 - (box.y1 + box.y2) / 2;
  const width = Math.ceil(1024 + gap + (box.x2 - box.x1));
  const g = WORDMARK[variant];
  const pad = g.bg ? 96 : 0;
  const vw = width + 2 * pad;
  const vh = 1024 + 2 * pad;
  let body =
    '  <defs>\n    <linearGradient id="wordmark" gradientUnits="userSpaceOnUse" ' +
    `x1="${n(box.x1)}" y1="0" x2="${n(box.x2)}" y2="0">\n` +
    `      <stop offset="0" stop-color="${g.from}"/>\n      <stop offset="1" stop-color="${g.to}"/>\n` +
    "    </linearGradient>\n  </defs>\n";
  if (g.bg) body += `  <rect width="${vw}" height="${vh}" fill="${g.bg}"/>\n`;
  body += `  <g transform="translate(${pad} ${pad})">\n`;
  body += `    <path fill="${COLORS.plum}" d="${roundedSquare(1024, P.tileR)}"/>\n`;
  body += svgPaths(P, COLORS, "    ");
  body += `    <path fill="url(#wordmark)" transform="translate(${n(tx)} ${n(ty)})" d="${glyphs.toPathData(1)}"/>\n`;
  body += "  </g>\n";
  return svg(vw, vh, "Wambito", body);
}

/** A PNG-in-ICO file: the header, one directory entry per image, then the PNGs. */
function ico(pngs) {
  const head = Buffer.alloc(6 + 16 * pngs.length);
  head.writeUInt16LE(0, 0);
  head.writeUInt16LE(1, 2);
  head.writeUInt16LE(pngs.length, 4);
  let offset = head.length;
  pngs.forEach(({ size, data }, i) => {
    const e = 6 + 16 * i;
    head.writeUInt8(size >= 256 ? 0 : size, e);
    head.writeUInt8(size >= 256 ? 0 : size, e + 1);
    head.writeUInt16LE(1, e + 4);
    head.writeUInt16LE(32, e + 6);
    head.writeUInt32LE(data.length, e + 8);
    head.writeUInt32LE(offset, e + 12);
    offset += data.length;
  });
  return Buffer.concat([head, ...pngs.map((p) => p.data)]);
}

async function renderPngs(files) {
  const { chromium } = createRequire(path.join(ROOT, "apps/web/package.json"))("playwright");
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  const shot = async (svgText, size, bg) => {
    const url = `data:image/svg+xml;base64,${Buffer.from(svgText).toString("base64")}`;
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(
      `<body style="margin:0;background:${bg ?? "transparent"}"><img src="${url}" style="display:block;width:${size}px;height:${size}px"></body>`,
    );
    await page.waitForFunction(() => document.images[0].complete);
    return page.screenshot({
      omitBackground: !bg,
      clip: { x: 0, y: 0, width: size, height: size },
    });
  };
  const icon = files.icon;
  const densities = { mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 };
  for (const [d, px] of Object.entries(densities)) {
    fs.writeFileSync(path.join(RES, `mipmap-${d}/ic_launcher.png`), await shot(icon, px));
  }
  fs.writeFileSync(
    path.join(ROOT, "apps/mobile/fastlane/metadata/android/en-US/images/icon.png"),
    await shot(icon, 512),
  );
  // Solid, no transparency: iOS rounds the corners itself.
  const touch = path.join(PUBLIC, "apple-touch-icon.png");
  fs.writeFileSync(touch, await shot(iconSvg(P, { square: true }), 180, COLORS.plum));
  // The iOS app icon set, one image per entry of Contents.json (single size, 1024): the light
  // icon solid plum without alpha (iOS rounds the corners); the dark one is the coin alone on
  // transparency (iOS lays its dark background under it); the tinted one is the monochrome
  // silhouette in white on transparency (iOS tints its luminance).
  const iosFiles = [];
  for (const img of JSON.parse(fs.readFileSync(path.join(IOS_ICONS, "Contents.json"), "utf8"))
    .images) {
    const px = Math.round(Number.parseFloat(img.size) * Number.parseInt(img.scale ?? "1", 10));
    const look = img.appearances?.find((a) => a.appearance === "luminosity")?.value ?? "light";
    const file = path.join(IOS_ICONS, img.filename);
    if (look === "dark") {
      fs.writeFileSync(file, await shot(svg(1024, 1024, "Wambito dark", svgPaths(P)), px));
    } else if (look === "tinted") {
      const mono = `  <path fill="#FFFFFF" fill-rule="evenodd" d="${monoPath()}"/>\n`;
      fs.writeFileSync(file, await shot(svg(1024, 1024, "Wambito tinted", mono), px));
    } else {
      fs.writeFileSync(file, await shot(iconSvg(P, { square: true }), px, COLORS.plum));
      iosFiles.push(file);
    }
  }
  const sizes = [16, 32, 48];
  const pngs = [];
  for (const size of sizes) pngs.push({ size, data: await shot(icon, size) });
  fs.writeFileSync(path.join(PUBLIC, "favicon.ico"), ico(pngs));

  const sheet = path.join(BRAND, "wambito-icon-preview.png");
  await page.setViewportSize({ width: 2200, height: 800 });
  await page.setContent(previewHtml(files.foreground, files.monochrome));
  await page.waitForLoadState("networkidle");
  await page.screenshot({ path: sheet, fullPage: true });
  await browser.close();
  const magick = spawnSync("magick", [sheet, "-colors", "256", `PNG8:${sheet}`]);
  if (magick.status !== 0) console.warn("magick not found: the preview sheet is not quantised");
  // Chromium screenshots carry alpha; strip it from the apple-touch icon when magick is around.
  spawnSync("magick", [
    touch,
    "-background",
    COLORS.plum,
    "-alpha",
    "remove",
    "-alpha",
    "off",
    `PNG24:${touch}`,
  ]);
  for (const file of iosFiles) {
    const flat = spawnSync("magick", [
      file,
      "-background",
      COLORS.plum,
      "-alpha",
      "remove",
      "-alpha",
      "off",
      `PNG24:${file}`,
    ]);
    if (flat.error || flat.status !== 0) {
      console.warn(`magick failed: ${path.basename(file)} may still carry alpha`);
    }
  }
}

/** The review sheet: each size masked as square, circle and squircle, light and dark, plus the
 * monochrome tinted as Android 13 themes it. */
function previewHtml(fg, mono) {
  const u = (s) => `data:image/svg+xml;base64,${Buffer.from(s).toString("base64")}`;
  const squircle = Buffer.from(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path d="M50 0C10 0 0 10 0 50s10 50 50 50 50-10 50-50S90 0 50 0z"/></svg>',
  ).toString("base64");
  const sizes = [512, 192, 96, 48, 32, 16];
  const shapes = [
    ["square", "border-radius:8%"],
    ["circle", "border-radius:50%"],
    ["squircle", `-webkit-mask:url(data:image/svg+xml;base64,${squircle}) center/100% 100%`],
  ];
  const tile = (px, style) =>
    `<div style="width:${px}px;height:${px}px;background:${COLORS.plum};overflow:hidden;position:relative;${style}"><img src="${u(fg)}" style="position:absolute;left:-25%;top:-25%;width:150%;height:150%"></div>`;
  const monoTile = (px, [bg, ink]) =>
    `<div style="width:${px}px;height:${px}px;border-radius:50%;background:${bg};overflow:hidden;position:relative"><div style="position:absolute;inset:-25%;background:${ink};-webkit-mask:url(${u(mono)}) center/100% 100% no-repeat"></div></div>`;
  const panel = (name, wall, text, tint) => {
    let rows = "";
    for (const [label, style] of shapes) {
      rows += `<h3>${label}</h3><div class="row">${sizes.map((px) => `<div class="cell">${tile(px, style)}<span>${px}</span></div>`).join("")}</div>`;
    }
    rows += `<h3>monochrome (themed)</h3><div class="row">${sizes.map((px) => `<div class="cell">${monoTile(px, tint)}<span>${px}</span></div>`).join("")}</div>`;
    return `<section style="background:${wall};color:${text}"><h2>${name}</h2>${rows}</section>`;
  };
  return `<!doctype html><html><head><meta charset="utf-8"><style>
body{margin:0;font:600 22px/1.2 -apple-system,Helvetica,sans-serif;display:flex}
section{padding:40px;width:1100px}h2{margin:0 0 10px;font-size:34px}h3{margin:28px 0 12px;font-size:20px;opacity:.7}
.row{display:flex;align-items:flex-end;gap:28px}.cell{display:flex;flex-direction:column;align-items:center;gap:8px}span{font-size:16px;opacity:.6}
</style></head><body>
${panel("Light wallpaper", "linear-gradient(160deg,#f4efe6,#dcd6f0)", "#221a47", ["#d7e3ff", "#0b2a5c"])}
${panel("Dark wallpaper", "linear-gradient(160deg,#1c1b22,#2d2a3d)", "#f3f0ff", ["#24324a", "#cfe0ff"])}
</body></html>`;
}

async function main() {
  const icon = iconSvg();
  const t = adaptiveTransform();
  const group = `  <g transform="translate(${n(t.tx)} ${n(t.ty)}) scale(${n(t.s)})">\n`;
  const foreground = svg(
    FG,
    FG,
    "Wambito icon foreground (adaptive, 108 dp)",
    `${group}${svgPaths(P, COLORS, "    ")}  </g>\n`,
  );
  const monochrome = svg(
    FG,
    FG,
    "Wambito icon monochrome (themed icon, 108 dp)",
    `${group}    <path fill="#000000" fill-rule="evenodd" d="${monoPath()}"/>\n  </g>\n`,
  );
  const write = (file, text) => fs.writeFileSync(file, text);
  write(path.join(BRAND, "wambito-icon.svg"), icon);
  write(path.join(PUBLIC, "favicon.svg"), icon);
  write(path.join(BRAND, "wambito-icon-foreground.svg"), foreground);
  write(path.join(BRAND, "wambito-icon-monochrome.svg"), monochrome);
  write(path.join(RES, "drawable/ic_launcher_foreground.xml"), vectorDrawable(expand(layers()), t));
  write(
    path.join(RES, "drawable/ic_launcher_monochrome.xml"),
    vectorDrawable([{ fill: "#FF000000", d: monoPath(), evenOdd: true }], t),
  );
  write(path.join(BRAND, "wambito-logo.svg"), logoSvg("day"));
  write(path.join(BRAND, "wambito-logo-dark.svg"), logoSvg("night"));
  console.log(`adaptive: scale ${n(t.s)}, face reach ${n(faceReach())} of ${SAFE_R}`);
  if (!process.argv.includes("--svg-only")) await renderPngs({ icon, foreground, monochrome });
}

module.exports = { P, COLORS, iconSvg, svgPaths, faceReach };
if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
