# Landing Analytics with Consent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PostHog (EU) page views, clicks and session recordings on wambito.com's public pages, loaded only after the visitor clicks Accept, with a Wambito-styled banner and an honest privacy policy.

**Architecture:** A pure consent model decides `ask | granted | denied` from `localStorage`, GPC/DNT and the date. A small loader imports `posthog-js` dynamically only once the choice is `granted`, and tears it down on withdrawal. The banner and the "Cookie preferences" link live in the public `Footer`, so `/app` and `/demo` never get them. Everything is off when the build has no `VITE_POSTHOG_KEY`.

**Tech Stack:** React Router 8 (prerendered landing), use-intl site catalogs (es/en/it/pt), `posthog-js`, Vitest (node unit + Storybook browser project), Playwright on the built site, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-19-landing-analytics-consent-design.md`

## Global Constraints

- Nothing from PostHog (script chunk, cookie, request) before Accept; never with GPC (`navigator.globalPrivacyControl === true`) or DNT (`navigator.doNotTrack === "1"`), which beat a stored "granted".
- Stored key `wambito.consent.analytics`, value `{ "v": 1, "choice": "granted" | "denied", "at": "<ISO date>" }`; expires after 6 months (182 days); `v` below the current version asks again.
- Host default `https://eu.i.posthog.com`; switches `VITE_POSTHOG_KEY`, `VITE_POSTHOG_HOST`. No key: no banner, no link, no PostHog code in the page.
- Init: `person_profiles: "identified_only"`, `respect_dnt: true`, `capture_pageview: "history_change"`, `persistence: "localStorage+cookie"`, `cross_subdomain_cookie: false`, `session_recording: { maskAllInputs: true, maskTextSelector: "[data-ph-mask]" }`. Never call `identify`.
- Accept and Decline are the same `PressButton` variant and size, in one row, Decline first. The banner is a labelled `role="region"`, not a modal, and renders after hydration only.
- Public pages only (Footer users: landing, roadmap, legal, automatic capture; the 404 page has no Footer and stays without analytics). Never `/app`, `/demo`, sign-in, OAuth consent or admin.
- Copy in es/en/it/pt through the site catalogs (`app/i18n/messages/{es,en,it,pt}.json`); repo text in English. Never a personal name in the repo.
- Commits: `feat(web): …` style, stage by path, no `Co-Authored-By` line.
- Work on the branch `worktree-feat-landing-analytics` (cut from `main`) in its worktree. Bring the spec and this plan into the first commit.

## Review Focus

- `localStorage` throws or is missing (Safari private mode, blocked storage): the page must not crash, the banner shows, and Accept loads PostHog for that page view only. Test in Task 1 (`readStoredConsent` with a throwing storage) and Task 3 (story with a throwing storage).
- A corrupt or foreign stored value (`"yes"`, `{}`, `{ "v": 1, "choice": "maybe" }`, a bad date): treated as `ask`, never `granted`. Test in Task 1.
- GPC turned on after an earlier Accept: no load on the next visit, and the link shows the GPC note. Test in Task 1 and Task 5.
- Two tabs: Decline (or withdraw) in one tab stops capture in the other through the `storage` event. Test in Task 2 (`watchConsent`) and Task 5.
- Client navigation (language switch, footer links) after Accept: PostHog starts once, not once per page. Test in Task 2 (`startAnalytics` idempotent) and Task 5 (one `/decide`/init-style request burst only).

---

### Task 1: The consent model

**Files:**
- Create: `apps/web/app/features/analytics/consent.ts`
- Test: `apps/web/app/features/analytics/consent.test.ts`

**Interfaces:**
- Produces:
  - `CONSENT_KEY = "wambito.consent.analytics"`, `CONSENT_VERSION = 1`, `CONSENT_MAX_AGE_DAYS = 182`
  - `type ConsentChoice = "granted" | "denied"`; `type ConsentState = "ask" | ConsentChoice`
  - `type BrowserSignals = { globalPrivacyControl?: boolean; doNotTrack?: string | null }`
  - `browserSaysNo(signals: BrowserSignals): boolean`
  - `consentState(stored: string | null, signals: BrowserSignals, now: Date): ConsentState`
  - `encodeChoice(choice: ConsentChoice, now: Date): string`
  - `readStoredConsent(storage: Pick<Storage, "getItem"> | undefined): string | null` (catches and returns `null`)
  - `writeStoredConsent(storage: Pick<Storage, "setItem"> | undefined, value: string): boolean` (catches and returns `false`)

- [ ] **Step 1: Write the failing tests** in `consent.test.ts` (Vitest, `describe("consentState")`), with `now = new Date("2026-11-19T12:00:00Z")`:
  - `null` → `"ask"`; `encodeChoice("granted", now)` → `"granted"`; `encodeChoice("denied", now)` → `"denied"`
  - granted stored 181 days before `now` → `"granted"`; 183 days before → `"ask"`
  - `{ v: 0, choice: "granted", at }` → `"ask"`
  - `"yes"`, `"{}"`, `{ v: 1, choice: "maybe", at }`, `{ v: 1, choice: "granted", at: "not a date" }`, `"{"` → `"ask"`
  - `{ globalPrivacyControl: true }` with granted stored → `"denied"`; `{ doNotTrack: "1" }` with `null` stored → `"denied"`; `{ doNotTrack: "0" }` → follows the stored value
  - `readStoredConsent({ getItem() { throw new Error("blocked") } })` → `null`; `readStoredConsent(undefined)` → `null`
  - `writeStoredConsent({ setItem() { throw new Error("quota") } }, "x")` → `false`
  - `JSON.parse(encodeChoice("denied", now))` equals `{ v: 1, choice: "denied", at: "2026-11-19T12:00:00.000Z" }`

- [ ] **Step 2: Run them to see them fail**

Run: `pnpm --filter @wambito/web exec vitest run --project unit app/features/analytics/consent.test.ts`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement `consent.ts`** with the signatures above. Pure: no `window`, no React. `consentState` checks `browserSaysNo` first.

- [ ] **Step 4: Run them again**

Same command. Expected: PASS.

- [ ] **Step 5: Commit** (with the spec and this plan)

```bash
git add apps/web/app/features/analytics/consent.ts apps/web/app/features/analytics/consent.test.ts docs/superpowers/specs/2026-11-19-landing-analytics-consent-design.md docs/superpowers/plans/2026-11-19-landing-analytics-consent.md
git commit -m "feat(web): a consent model for landing analytics"
```

### Task 2: The build switch and the PostHog loader

**Files:**
- Create: `apps/web/app/features/analytics/config.ts`, `apps/web/app/features/analytics/posthog.ts`
- Modify: `apps/web/package.json` (add `posthog-js`, an exact version at least two weeks old), `pnpm-lock.yaml`, `apps/web/vitest.config.ts` (add `"posthog-js"` to `optimizeDeps.include`), `apps/web/.env.example` if it lists `VITE_*` switches
- Test: `apps/web/app/features/analytics/posthog.test.ts`, `apps/web/app/features/analytics/config.test.ts`

**Interfaces:**
- Consumes: `CONSENT_KEY`, `consentState`, `BrowserSignals` (Task 1)
- Produces:
  - `type AnalyticsConfig = { key: string; host: string }`
  - `analyticsConfig(env: { VITE_POSTHOG_KEY?: string; VITE_POSTHOG_HOST?: string } = import.meta.env): AnalyticsConfig | null` (blank key → `null`; host defaults to `https://eu.i.posthog.com`, trailing slash dropped)
  - `posthogOptions(config: AnalyticsConfig): Partial<PostHogConfig>`, the init options from Global Constraints plus `api_host: config.host`
  - `startAnalytics(config: AnalyticsConfig, load?: () => Promise<PostHogLike>): Promise<void>`: dynamic `import("posthog-js")` by default; starts at most once per page (a second call is a no-op)
  - `stopAnalytics(env?: { document: Document; localStorage?: Storage }): void`: if started, `opt_out_capturing()`, `stopSessionRecording()`, `reset()`; always `clearPosthogStorage`
  - `clearPosthogStorage(document: Pick<Document, "cookie">, storage: Storage | undefined): void`: expires every `ph_*` cookie (path `/`, this host only) and removes every `ph_*` / `__ph*` key; never throws
  - `watchConsent(onDenied: () => void, win?: Window): () => void`: a `storage` listener on `CONSENT_KEY`; when the new value's state is not `granted`, it calls `onDenied`; returns the unsubscribe

- [ ] **Step 1: Write the failing tests**
  - `config.test.ts`: `{}` → `null`; `{ VITE_POSTHOG_KEY: " " }` → `null`; `{ VITE_POSTHOG_KEY: "phc_test" }` → `{ key: "phc_test", host: "https://eu.i.posthog.com" }`; `VITE_POSTHOG_HOST: "https://eu.i.posthog.com/"` → host without the slash.
  - `posthog.test.ts`:
    - `posthogOptions({ key: "k", host: "https://h.test" })` matches `{ api_host: "https://h.test", person_profiles: "identified_only", respect_dnt: true, capture_pageview: "history_change", persistence: "localStorage+cookie", cross_subdomain_cookie: false, session_recording: { maskAllInputs: true, maskTextSelector: "[data-ph-mask]" } }`
    - `startAnalytics` called twice with a fake `load` → `load` called once and `init("k", …)` called once
    - `stopAnalytics` after start → fake's `opt_out_capturing`, `stopSessionRecording`, `reset` each called once
    - `clearPosthogStorage` on a fake document whose `cookie` is `"ph_phc_x_posthog=1; theme=dark"` and a memory storage holding `ph_phc_x_posthog`, `__ph_opt_in_out_phc_x` and `wambito.consent.analytics` → writes an expired `ph_phc_x_posthog` cookie, leaves `theme`, removes both PostHog keys, keeps the consent key
    - `watchConsent`: dispatching a `StorageEvent` with key `wambito.consent.analytics` and a denied value calls `onDenied`; another key does not; after unsubscribe nothing is called

- [ ] **Step 2: Run them to see them fail**

Run: `pnpm --filter @wambito/web exec vitest run --project unit app/features/analytics`
Expected: FAIL on the new files.

- [ ] **Step 3: Add the dependency** (`pnpm --filter @wambito/web add posthog-js@<exact>`), **then implement `config.ts` and `posthog.ts`** with the signatures above. Type `PostHogLike` as the subset of the PostHog instance used here. Import `posthog-js` types with `import type` only, so the static graph never pulls the library in.

- [ ] **Step 4: Run the tests and the typecheck**

Run: `pnpm --filter @wambito/web exec vitest run --project unit app/features/analytics && pnpm --filter @wambito/web typecheck`
Expected: PASS, no type errors.

- [ ] **Step 5: Commit**

```bash
git add apps/web/app/features/analytics apps/web/package.json apps/web/vitest.config.ts pnpm-lock.yaml
git commit -m "feat(web): load posthog only after consent, and tear it down on withdrawal"
```

### Task 3: The banner, the footer link and their copy

**Files:**
- Create: `apps/web/app/features/analytics/ConsentBanner.tsx`, `apps/web/app/features/analytics/use-analytics-consent.ts`, `apps/web/app/features/analytics/ConsentBanner.stories.tsx`
- Modify: `apps/web/app/features/landing/Footer.tsx`, `apps/web/app/features/landing/landing.css`, `apps/web/app/i18n/messages/{es,en,it,pt}.json` (new `landing.consent.*`, `landing.footer.cookies`), `apps/web/app/features/landing/AgentDemo.tsx` and `MoneyHeadline.tsx` (add `data-ph-mask` to the shown amounts)

**Interfaces:**
- Consumes: Tasks 1–2 (`analyticsConfig`, `consentState`, `readStoredConsent`, `writeStoredConsent`, `encodeChoice`, `browserSaysNo`, `startAnalytics`, `stopAnalytics`, `watchConsent`)
- Produces:
  - `useAnalyticsConsent(config: AnalyticsConfig | null, deps?: { storage?: Storage; signals?: BrowserSignals; now?: () => Date; start?: typeof startAnalytics; stop?: typeof stopAnalytics })` → `{ ready: boolean; state: ConsentState; browserSaysNo: boolean; open: boolean; reopen(): void; choose(choice: ConsentChoice): void }`. `ready` stays `false` until the first effect, so the server render and the first client render show nothing. On `granted` it calls `start(config)`; going to `denied` calls `stop()`; it subscribes with `watchConsent`. A failed write still applies the choice for this page.
  - `ConsentBanner({ consent }: { consent: ReturnType<typeof useAnalyticsConsent> })` renders nothing unless `consent.ready && consent.open`
  - In `Footer`: `const consent = useAnalyticsConsent(analyticsConfig())`, the banner, and a `<button className="lk-landing-link">` "Cookie preferences" beside Privacy calling `consent.reopen()`, only when the config is not `null`

Copy (es, exact; en/it/pt translated in the same tone and checked against the existing `legal.privacy` wording):

```json
"consent": {
  "label": "Preferencias de cookies",
  "title": "¿Nos dejas ver cómo usas esta página?",
  "body": "Con PostHog vemos qué lees y dónde haces clic, y grabamos la visita sin lo que escribes. Solo en wambito.com, nunca en la app ni con tus finanzas. Más en la <privacy>política de privacidad</privacy>.",
  "decline": "No, gracias",
  "accept": "Sí, acepto",
  "current_granted": "Ahora: aceptaste.",
  "current_denied": "Ahora: no aceptaste.",
  "browser_no": "Tu navegador pidió no ser rastreado, así que no te rastreamos.",
  "close": "Cerrar"
}
```
and `"footer": { …, "cookies": "Preferencias de cookies" }`.

- [ ] **Step 1: Write the stories with play functions** (`ConsentBanner.stories.tsx`, which the Storybook Vitest project runs as tests). Each story injects a memory storage, fake `start`/`stop` spies (`fn()`) and signals:
  - `Ask`: the region labelled "Preferencias de cookies" is visible; both buttons have the same `className` and the same bounding-box height; Decline comes before Accept in DOM order.
  - `AcceptStores`: click "Sí, acepto" → storage holds a `granted` value, `start` called once, the banner is gone.
  - `DeclineStores`: click "No, gracias" → storage holds `denied`, `start` never called.
  - `Reopen`: from `granted`, click the footer "Preferencias de cookies" → banner shows "Ahora: aceptaste."; click "No, gracias" → `stop` called once.
  - `BrowserSaysNo`: `signals = { globalPrivacyControl: true }` → no banner on load; the footer link opens the `browser_no` note with only a "Cerrar" button; `start` never called.
  - `BlockedStorage`: a storage whose methods throw → the banner shows; Accept calls `start` once and does not throw.
  - `Dark`: `Ask` under the dark theme (the a11y addon checks contrast).
  - `NoKey`: `config = null` → neither banner nor footer link.

- [ ] **Step 2: Run them to see them fail**

Run: `pnpm --filter @wambito/web exec vitest run --project storybook app/features/analytics`
Expected: FAIL, components missing.

- [ ] **Step 3: Implement the hook, the banner, the footer change, the styles and the copy in four languages.** Styles in `landing.css` as `.lk-consent*`: fixed to the bottom with `var(--space-4)` margins, max width like `.lk-landing-wrap`, landing tokens for surface, ink and border, Fredoka title, Nunito body, both themes, buttons in one row that wraps on phones. Buttons: `PressButton variant="secondary"` for both.

- [ ] **Step 4: Run the stories, the catalog test and the old landing stories**

Run: `pnpm --filter @wambito/web exec vitest run --project storybook app/features/analytics app/features/landing && pnpm --filter @wambito/web exec vitest run --project unit app/i18n`
Expected: PASS (the catalog parity test sees the new keys in all four languages).

- [ ] **Step 5: Commit**

```bash
git add apps/web/app/features/analytics apps/web/app/features/landing/Footer.tsx apps/web/app/features/landing/landing.css apps/web/app/features/landing/AgentDemo.tsx apps/web/app/features/landing/MoneyHeadline.tsx apps/web/app/i18n/messages/es.json apps/web/app/i18n/messages/en.json apps/web/app/i18n/messages/it.json apps/web/app/i18n/messages/pt.json
git commit -m "feat(web): a cookie banner and preferences link on the public pages"
```

### Task 4: The privacy policy

A refinement of the spec, my call: the analytics wording appears only in builds with a key. A self-hosted or keyless build has no analytics, so it keeps today's "no analytics" promise, which stays true. This also means the real retention numbers only need to be right before the key is set (Task 6).

**Files:**
- Modify: `apps/web/app/features/legal/legal.ts`, `apps/web/app/features/legal/LegalPage.tsx`, `apps/web/app/i18n/messages/{es,en,it,pt}.json` (`legal.privacy.*`)
- Test: `apps/web/app/features/legal/legal.test.ts`

**Interfaces:**
- Consumes: `analyticsConfig` (Task 2)
- Produces:
  - `ANALYTICS_RETENTION = { eventsMonths: number; recordingsDays: number }` in `legal.ts`, filled from the PostHog project in Task 6 and interpolated into the copy
  - `privacySections(withAnalytics: boolean): readonly PrivacySection[]`: without analytics, today's `PRIVACY_SECTIONS`; with it, `analytics` after `storage` and `not_done_with_analytics` in place of `not_done`
  - `LegalPage` uses `privacySections(analyticsConfig() !== null)`

Copy: `legal.privacy.sections.analytics` (`title`: "Analítica en wambito.com") and `not_done_with_analytics` per the spec section "The privacy policy". It names PostHog Inc. (US) processing on EU servers under its DPA with standard contractual clauses, says no IP is kept, the retention as `{eventsMonths}` months and `{recordingsDays}` days, the withdraw link, deletion by `<email>privacy@wambito.com</email>`, and that GPC/DNT is respected. `version` moves to the release date in all four languages.

- [ ] **Step 1: Write the failing tests** in `legal.test.ts`: `privacySections(false)` equals today's list; `privacySections(true)` has `analytics` right after `storage`, has `not_done_with_analytics` and not `not_done`; every section in `privacySections(true)` has a `title` and `body` in es/en/it/pt; the es `analytics.body` rendered with `ANALYTICS_RETENTION` contains `"PostHog"`, `"privacy@wambito.com"` and both numbers.

- [ ] **Step 2: Run them to see them fail**

Run: `pnpm --filter @wambito/web exec vitest run --project unit app/features/legal`
Expected: FAIL.

- [ ] **Step 3: Implement it and write the copy** in four languages.

- [ ] **Step 4: Run the tests and the legal stories**

Run: `pnpm --filter @wambito/web exec vitest run --project unit app/features/legal && pnpm --filter @wambito/web exec vitest run --project storybook app/features/legal`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/web/app/features/legal apps/web/app/i18n/messages/es.json apps/web/app/i18n/messages/en.json apps/web/app/i18n/messages/it.json apps/web/app/i18n/messages/pt.json
git commit -m "feat(web): say in the privacy policy what landing analytics collect"
```

### Task 5: End to end on the built landing

**Files:**
- Create: `apps/web/e2e/landing-analytics.spec.ts`
- Modify: `apps/web/playwright.built.config.ts` (mode `E2E_LANDING_ONLY=analytics` → `/landing-analytics\.spec\.ts$/`), `apps/web/package.json` (script `e2e:landing-analytics`: `VITE_POSTHOG_KEY=phc_e2e VITE_POSTHOG_HOST=https://posthog.example.test VITE_APP_URL=https://app.example.test VITE_SITE_URL=https://landing-only.example.test tsx scripts/build-landing.ts && E2E_LANDING_ONLY=analytics … playwright test -c playwright.built.config.ts`), `apps/web/e2e/landing-only.spec.ts` (assert no banner and no "Cookie preferences" without a key), `.github/workflows/ci.yml` (the `e2e` job runs `e2e:landing-analytics` after `e2e:landing-only-app`)

- [ ] **Step 1: Write the spec** with JavaScript on (`test.use({ javaScriptEnabled: true })`), a `page.route("https://posthog.example.test/**")` that records every request and answers `200 {}`, and a check of the `posthog-js` chunk requests (`/assets/*posthog*`). Tests:
  - `nothing before accept`: load `/`, wait for the banner, assert 0 PostHog requests, no `ph_*` cookie and no PostHog chunk loaded.
  - `accept starts it`: click "Sí, acepto" → at least 1 request to the host and the chunk loaded; reload → no banner, requests resume.
  - `decline stays off`: click "No, gracias", reload, go to `/en` and `/privacy` → 0 requests, no banner.
  - `gpc wins`: `context.addInitScript(() => Object.defineProperty(navigator, "globalPrivacyControl", { value: true }))` with a stored granted value → no banner, 0 requests; the footer link shows the GPC note.
  - `withdraw stops it`: accept, then the footer "Preferencias de cookies" → "No, gracias" → no `ph_*` cookie or storage key left; clicking around afterwards sends 0 new requests.
  - `other tab`: accept in tab A, decline in tab B (same context) → tab A sends 0 new requests after the decline.
  - `one start across navigation`: accept on `/`, follow the footer link to `/en`, then to `/roadmap` → `posthog.init` ran once (count via `page.exposeFunction` on a stub, or one config request burst).
  - `no banner in html`: fetch `/` with JavaScript off → the HTML has no consent region.
  - `privacy policy names posthog`: `/privacy` has the "Analítica en wambito.com" heading.

- [ ] **Step 2: Run it (it fails only where Tasks 1–4 have a gap; fix there, not in the spec)**

Run: `pnpm --filter @wambito/web e2e:landing-analytics && pnpm --filter @wambito/web e2e:landing-only`
Expected: PASS both.

- [ ] **Step 3: Commit**

```bash
git add apps/web/e2e/landing-analytics.spec.ts apps/web/e2e/landing-only.spec.ts apps/web/playwright.built.config.ts apps/web/package.json .github/workflows/ci.yml
git commit -m "test(web): end-to-end checks that landing analytics wait for consent"
```

### Task 6: Docs, the CI variable and the go-live checklist

**Files:**
- Modify: `.github/workflows/ci.yml` (`deploy-landing` build step env: `VITE_POSTHOG_KEY: ${{ vars.POSTHOG_KEY }}`; an unset variable is an empty string, so the build stays keyless), `docs/deploy/landing.md` (new section "Analytics (PostHog)"), `apps/web/AGENTS.md` (the `features/analytics` entry and the switches)

- [ ] **Step 1: Write `docs/deploy/landing.md` "Analytics (PostHog)"**: the switches; that a keyless build has no banner and keeps the old policy; and the founder's go-live checklist, in order:
  1. Create a PostHog account and a project in the **EU** region.
  2. Project settings: "Discard client IP data" on; authorized domains / recording domains limited to `https://wambito.com`; session recording on with input masking.
  3. Accept PostHog's DPA (in the organization's settings, as Slinqer S.A.S.).
  4. Read the real retention for events and recordings for the plan; put them in `ANALYTICS_RETENTION` (`apps/web/app/features/legal/legal.ts`) in a PR and merge it.
  5. Set the repository variable `POSTHOG_KEY` (Settings → Secrets and variables → Actions → Variables) to the project's public key; the next merge to `main` turns analytics on.
  6. To turn it off: delete the variable and merge anything (or rerun `deploy-landing`).
- [ ] **Step 2: Update `apps/web/AGENTS.md`** with the `app/features/analytics/` line (consent model, loader, banner in `Footer`, `VITE_POSTHOG_KEY`/`VITE_POSTHOG_HOST`, keyless = off) and the `e2e:landing-analytics` script.
- [ ] **Step 3: Run the whole check**

Run (repo root): `pnpm lint && pnpm typecheck && pnpm --filter @wambito/web test`
Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml docs/deploy/landing.md apps/web/AGENTS.md
git commit -m "docs: how to turn landing analytics on, and wire the posthog key in ci"
```

- [ ] **Step 5: Open the PR.** Say that nothing changes for visitors until `POSTHOG_KEY` is set, link the go-live checklist, and say that the Figma screens map is unchanged because the banner is not a screen or a route.
