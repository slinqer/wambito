# docs

Human docs. Live docs are kept current; `superpowers/` is history.

## Map

- `docs/design/system/`: the design system. `docs/design/system/project/tokens.json` is the source
  of all tokens (regenerate: root `AGENTS.md`). `docs/design/system/project/README.md` is the
  brand book; `docs/design/system/project/components/` per-component guidelines and previews.
- `docs/brand/`: raster brand art, files `wambi-*`; the app icon and logo as vectors fitted to the
  chosen concept, `wambito-icon.svg` (master, 1024), `-foreground`/`-monochrome` (Android adaptive,
  108 dp), `wambito-logo.svg` and `-logo-dark.svg` (wordmark as outlines), `wambito-icon-preview.png`.
  `docs/brand/tools/gen-icon.cjs` holds the one geometry and writes all of them plus the icon PNGs
  (`mipmap-*`, F-Droid `icon.png`, web `favicon.ico`/`apple-touch-icon.png`) and
  `drawable/ic_launcher_{foreground,monochrome}.xml`; never hand-edit those (usage in its header).
  `docs/brand/tools/gen-email-images.cjs` writes the emails' `apps/web/public/email/*` (Wambi,
  the wordmark day/night, the fonts) from the landing's sprite and Fredoka; a changed image needs
  a new name (Gmail's proxy caches by URL).
  Colours: tokens `brand-plum`, `brand-gold`.
  Scenes `wambi-capture-step{1..5}.webp` are Codex-generated (`codex exec` image generation) from
  `wambi-pointing.webp` and checked by eye as one set on night and day; masters 1024 px. The apps
  ship byte-identical 512 px copies (`magick … -resize 512x512 -quality 90 -define
  webp:alpha-quality=100`) in `apps/web/public/wambi` and `apps/mobile/assets/wambi`. Make a new
  scene the same way and add it only if on-model (same face, gold, purple limbs, pink sneakers; no
  text, letters, numbers or logos).
  `docs/brand/e2e/wambi-e2e-step{1..5}.webp`: the end-to-end encryption scenes (same Codex method,
  1024 px masters), used by the root `README.md`; `docs/brand/e2e/README.md` lists each scene and a
  Spanish caption for the apps.
- `docs/deploy/`: `personal.md` (private install, short; the runbook is
  `deploy/personal/README.md`), `landing.md` (Cloudflare landing), `api.md` (client addresses,
  rate limits).
- `docs/admin.md`: the admin panel: who is an admin (`ADMIN_USER_IDS`, `ADMIN_ALLOWED_IPS`), Ley 1581
  deadlines and procedures, the dry run.
- `docs/mobile/`: `setup.md` (toolchain, JDK 17, emulator, tests), `release.md` (signing, APK
  build; the founder copies its commands), `parity.md` (web/app visual parity ledger), `fdroid.md`
  (how Wambito is built on F-Droid), `play.md` (Google Play: account, Play App Signing, the Console
  forms' answers, each release).

## History: `docs/superpowers/` (read only when needed, never edit after the fact)

- `specs/`: designs; `plans/`: implementation plans; `reports/`: rulings and spikes. The root
  `AGENTS.md` names which spec explains what. They keep the names they were written with.

## Rules

- `docs/mobile/release.md` keeps the signing key's alias (see root `AGENTS.md`), and the old key
  folder only in the steps that move it; `docs/mobile/setup.md` names the old AVD only to delete it.
