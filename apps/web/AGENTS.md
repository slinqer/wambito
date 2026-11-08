# apps/web (`@wambito/web`)

React Router 8 (framework mode, SPA + prerender): the public landing, roadmap, privacy policy and
account deletion page (prerendered, es/en/it/pt; `app/features/legal/`), the signed-in app
(`/app/*`), sign-in, onboarding (`/welcome`), OAuth consent for assistants, and a fake-backend demo
(`/demo/*`).

## Entry points

- `app/root.tsx` (document; theme bootstrap script first in `<head>`), `app/routes.ts` (route
  table; landing-only builds drop the app layout), `react-router.config.ts` (prerender list,
  build dir `WAMBITO_BUILD_DIR` or `build`), `vite.config.ts` (mascot chunk named `mascot-*`).
- `app/routes/*` thin route modules; `app/features/<feature>/` screens, models, stories;
  `app/ui/` shared components; `app/wambi/` the mascot (`app/wambi/experimental/` 3D, never on
  the landing); `app/api/` OpenAPI client; `app/auth/` session and passkeys; `app/demo/` (the seed over a memory store);
  `app/local/` the local backend: `FinanceStore` (`store.ts`, contract tests in `store-contract.ts`),
  `memory-store.ts`, `backend.ts` (`createLocalBackend`: the `/v1` routes over a store, one store
  transaction per request), `ids.ts` (UUID v7 and v5);
  `app/feedback/` sounds, vibration, `Celebration`; `app/theme/`; `app/site/` origins/build env;
  `app/admin/` the admin panel (`/admin/*`, layout `routes/admin.tsx`): `useAdmin`/`adminFetch`
  (a 401 `admin_verification_required` waits for the passkey, then retries), `AdminGate` (the layout's gate), `VerifyScreen`, `HomeScreen` (metrics, audit, look-up),
  `AccountScreen` + `ActionSheet` (`/admin/users/:id`: the account and its actions; a sheet's
  fields live in the component, so a reason survives re-verification). Stories `Admin/*`,
  web-only, not in parity.json.
- `/automatic-capture` (+ `/en|it|pt/automatic-capture`; `routes.ts`, prerendered like the privacy
  pages; paths in `app/site/paths.ts`: `AUTOMATIC_CAPTURE_PATH`, SitePage `automaticCapture`): how
  automatic capture works. `app/features/capture/`: `CaptureSteps.tsx` (`CAPTURE_STEPS`,
  `CaptureStepView`, `CaptureSteps`), `CaptureDemos.tsx` (`MainPicture` with `income`,
  `ChipsDemo`, `NoticeDemo`, `LearnDemo`), `CapturePage.tsx`, `capture.css`; scenes
  `public/wambi/capture-step1..5.webp`. The landing card is the fifth `#how` item
  (`features/landing/HowItWorks.tsx`). Copy under `landing.capture.*`; `messages.test.ts` forbids
  naming a language in it. `Capture/Step` and `Capture/MainPicture` (night) are parity stories in
  `apps/mobile/test/parity/parity.json`; `Capture/Steps` is web-only (the Flutter twin is
  `apps/mobile/lib/capture_auto/`).
- `/confirm-email?token=…` (`routes/confirm-email.tsx`, `features/confirm-email/`, under the app
  layout, public): the page of an admin-started email change. It posts the token only when the
  person taps the button (a mail scanner opening the link spends nothing), then sends them to
  sign-in (every session was closed). Copy in `confirm_email.*` in all four languages; story
  `ConfirmEmail`, web-only, not in parity.json.
- Storage: only `readStored/writeStored/removeStored` in `app/lib/stored.ts` (keys
  `wambito.<name>`, `sessionArea()` for session data).
- i18n: `app/i18n/messages/{es,en,it,pt}.json` public pages, `app.{es,en,it,pt}.json` the rest.
  `messages.test.ts` enforces parity, ICU, PT-PT, no slang in it/pt, no old names. The admin
  panel: `admin.{es,en}.json` only (namespace `admin`, `AdminMessages`; it/pt read en); codes only
  `/v1/admin/*` answers are `ADMIN_ONLY_CODES` there, with text in `admin.errors.*`.

## Talks to

- API at `/api` on the same origin (Vite proxies it in dev). Types: `app/api/schema.d.ts`
  (generated; commands for it and `tokens.css`: root `AGENTS.md`).

## Commands (repo root)

- Dev: `pnpm --filter @wambito/web dev` (needs the root stack: `docker compose up -d`).
- Unit + Storybook tests: `pnpm vitest run apps/web`; one project
  `--project "@wambito/web (unit)"` or `"@wambito/web (storybook)"` (Chromium).
- Storybook: `pnpm --filter @wambito/web storybook` (:6006). OG images: `pnpm --filter @wambito/web og`.
- e2e: `E2E_NOW=2026-10-21T15:00:00Z docker compose up -d --build` (value from
  `e2e/helpers.ts`), then `pnpm --filter @wambito/web e2e` | `e2e:landing` | `e2e:landing-only` |
  `e2e:landing-only-app`. Afterwards `docker compose stop` (never `down -v`).

## Landing builds

- Normal `build/` (landing + app). `VITE_LANDING_ONLY=true` via `scripts/build-landing.ts`
  (`build:landing`): landing + 404 for the Worker. `VITE_APP_URL` points the CTA at the app origin;
  `VITE_SITE_URL` sets canonical/sitemap (default `https://wambito.test`). The VPS builds with
  `WAMBITO_BUILD_DIR=build-personal`.

## Traps

- Money slang (see root `AGENTS.md`) is in the Spanish copy.
  `app/features/landing/money-words.ts` / `MoneyHeadline.tsx` hold money words per language: edit
  with care.
- The landing header must fit one row at 320px in every language (e2e checks it).
- Landing HTML must not link files named after the mascot module (hence `mascot-*`).
- Storybook story titles are the parity ids in `apps/mobile/test/parity/parity.json`.
- Built e2e suites run without JavaScript by default; the dev e2e fails in global-setup without
  the pinned `E2E_NOW` in the API.
