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
  transaction per request), `ids.ts` (UUID v7 and v5), `db.ts` (promise wrapper over IndexedDB:
  database `wambito-vault-<userId>`, one store per record type plus `outbox`, `meta`,
  `quarantine`, `keys`; `deleteVault`), `encrypted-store.ts` (`createEncryptedStore(userId)`: a
  `FinanceStore` over `db.ts`; local writes update the record and the outbox in one IndexedDB
  transaction, `origin: "remote"` writes (sync) take `{ version, keyV }` and add no outbox entry;
  also the sync helpers `readOutbox`, `ackOutbox`, `getMeta/setMeta`, `quarantine`, `wipeRecords`,
  `getKey/putKey/deleteKey/keyNames`, `parkOutbox`, `abandonOutbox`, `adoptServerCopy`, `restoreSetAside`). Subscribers fire after every commit that
  wrote, whatever its origin, and for other tabs' commits too (a BroadcastChannel
  `wambito-vault-<userId>` tells the other tabs of each commit). `close()` (or another tab deleting
  or upgrading the database) closes it for good: every later op rejects with `VaultClosedError`
  (code `vault_closed`); `isClosed()`, `onClosed(cb)` → unsubscribe. `wipeRecords` keeps the outbox
  and sets pending entries aside (`restoreSetAside` puts them back after the full download,
  merging the touched fields); remote writes take `skipIfPending` / `ifSeq`.
  `sync.ts` (`createSyncEngine({ store, fetch, userId, keys, keyV, onError })` → `run()` /
  `start()`: push the outbox, then pull `/v2/sync`; field-by-field conflict merge, quarantine,
  `410` resync that keeps pending edits (set aside, then re-applied); the design notes are at the
  top of the file; tests run against a fake `/v2` in `sync.test.ts`). A run holds a Web Lock
  `wambito-sync-<userId>` (one sync per user across tabs). A failing outbox entry is parked
  (back-off 1 min doubling to 6 h; a local write to it clears the park) and never blocks the pull
  of other ids; its own id stays blocked while it retries, and on the fifth failure it is given up
  on (`abandoned`, reported in `dropped`): never pushed again, pulls apply the id again (the
  conflict's copy at once, else the next server edit or a resync) and the entry goes once the
  server's copy lands; a local write retries it;
  a whole-batch 413/422 is bisected, other 4xx park the batch and the pull still runs; a create
  conflict takes the server copy (plus the fields the person changed after the create, if they
  wrote while it was in flight). Results carry `parked` (ids; problem `parked`) and a closed
  store ends a run with `{ ok: false, error: "closed" }` (problem `closed`). Every `/v2` call
  (`sync.ts`, `keys.ts`) sends `x-wambito-user: <vault's user id>`; a 409 `session_changed` (the
  cookie is now another account's) stops the run and `start()`'s triggers (problem
  `session_changed`; `KeysError("session_changed")` in `keys.ts`).
  `keys.ts` (no React; injected `fetch`, `/api`): `prepareAccount({ userId, guest })` → `{
  recoveryKey, commit() }` (DK + recovery secret + device key pair, all in memory; nothing is sent
  until `commit()`, which the setup screen calls only after the four characters are typed back:
  PUT the recovery wrap first, then the attested device wrap (label `deviceLabel(userAgent)` from
  `device-label.ts`: `"Firefox on macOS"`, else `"Web"`), then keep only the non-extractable
  record/dedupe keys (`record:<v>`, `dedupe:<v>`) and the device private key (`device`) in the
  vault's `keys` store, plus meta `keyV` (current), `deviceWrapId` and `devicePublicKey`;
  retry-safe, the same ids on a retry, DK zeroed after success; `recoveryKey` is `null` for a
  guest, whose recovery secret is never shown and who commits at once; `KeysError("already_set_up")`
  when the account has wraps, and from `commit()` when another setup won the race: the recovery
  wrap goes with `If-None-Match: *`, so the server keeps one data key; the losing DK is zeroed;
  `KeysError("unsupported_browser")` before anything is sent when WebCrypto lacks X25519, whose
  noble fallback would keep a raw private key: the web never stores one), `unlockWithRecovery({ userId, text })` (`bad_recovery_key` /
  `wrong_recovery_key`; enrolls this device, the caller then runs a full sync), `enrollDevice(options,
  dataKey, keyV)` (the same enroll for pairing; the caller zeroes DK), `loadLocalKeys(userId)` →
  `{ keyring: { current, byVersion: Map<keyV, RecordKeys> } }` (`null` = locked or no keys for
  `current`; a 2a vault's `record`/`dedupe` load as version `keyV` and are renamed;
  `currentRecordKeys(local)`; the sync engine still takes one version), `withDataKey(options, fn)`
  (DK from this browser's own device wrap: found by `deviceWrapId`, its `publicKey` must equal
  `devicePublicKey`, opened with `openFromDevice`; `fn(dk, keyV)`, DK zeroed after;
  `KeysError("device_removed")` otherwise; a 2a browser without `deviceWrapId` tries each device
  wrap and keeps the one that opens), `refreshKeys(options)` (adds the device wrap's `keyV` to the
  keyring and makes it current, keeps the old versions), `dropKeyVersion(userId, keyV)`,
  `forgetDevice(userId)` (sign-out: `deleteVault`). The recovery secret is zeroed
  in a `finally`. `stale-vaults.ts` `deleteStaleVaults(keepUserId)`: deletes every
  `wambito-vault-*` database but the signed-in person's (all when null; `indexedDB.databases()`,
  nothing where the browser lacks it), on sign-in (`useFinishSignIn`) and on every signed-out load
  of the live guards (`GuardDeps.onSignedOut` in `auth/session.ts`): a vault outlives a session that
  ended outside the sign-out.
  `vault-session.ts`: a preview account's open vault, one per tab, shared by `/welcome` and
  `/app`: `openVaultSession({ profile, keys, fresh })` opens the store, runs a full sync (must
  succeed when `fresh`; a known browser opens offline), seeds an empty account (settings record
  from the server profile, currency EUR, and the suggested categories, through the local backend),
  then `start()`s the engine; it seeds only after a complete first sync with no set-aside changes
  waiting. A 409 `session_changed` fails the opening (`VaultOpenError`, even for a known browser)
  or, later, closes the session and calls `onSessionChanged`. Its `fetch` is the local backend plus `DELETE /v1/me` sent to the
  API; `LOCAL_UNAVAILABLE` (export, imports, assistants) answers 403. `forgetVault()` stops the
  sync, closes the store and deletes the vault (sign-out via `liveSignOut`, and a 401 from sync).
  If the store closes under it (another tab), the session stops its sync, drops itself and calls
  `onClosed`; the gate then checks again (`gate.closed()`: reopen with kept keys, else Unlock).
  The local backend also serves `POST /v1/transactions/review` (all or nothing, 404 on an unknown
  or deleted id; no merchant memory). The server refuses a preview account's `/v1` finance routes
  (403 `encrypted_account`): only `GET`/`PATCH /v1/me` (locale on sign-in) and `DELETE /v1/me` go
  live.
  Preview switch: `auth/encryption.ts` `previewProfile()` reads `GET /v1/me` `encryption` in the
  `/app` and `/welcome` loaders; for `preview` they render `features/vault/VaultGate.tsx`
  (state machine `vault-gate.ts`, unit-tested with fakes: checking → setup | unlock | open →
  ready, else `Locked` with a retry of the failed step; before making or unlocking keys, when the
  open vault closes, and on `session_changed` (`gate.sessionChanged()`), it reads who is signed in
  (live `GET /v1/me`) and, when it is another account or none, reloads the app at `/app`, so
  nothing runs for the old id; Locked kinds `error`, `offline`,
  `unsupported` (no X25519: no retry) and `guest` (a guest whose account has keys elsewhere: no
  recovery key to type, so sign-out or delete the account); a 401 from `/v2/keys` signs in again) and then `<ApiProvider mode="local">`;
  the onboarding flag is the vault's (`LocalOnboardingRoute`), not the server's. `ApiMode` is
  `live | demo | local`: demo-only behaviour checks `=== "demo"`, live-only `=== "live"`
  (import); settings shows `settings.local_off` under import, export and the assistants in
  `local`; the welcome skips its import step there. Screens in
  `app/features/vault/`: `RecoveryKeySetup` (key in groups of four, copy, `.txt`, then type four
  characters back, each named "group N, character M"), `Unlock` (`onUnlock(text) → UnlockError |
  null`), `Locked` (retry, guest delete); all three have `onSignOut` (the gate passes `useSignOut`,
  which wipes the vault); pure UI,
  callbacks as props; stories `Vault/*`, web-only, not in parity.json; copy under `vault.*`. A
  recurrence's occurrences have ids `uuidv5(ruleId, "<month>:<rev>")`; editing or archiving a rule
  bumps its `rev`.
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
  Exception: `app/local/` talks to IndexedDB directly (`db.ts`), because the vault needs
  transactions and CryptoKeys; nothing else in the app touches IndexedDB.
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
- e2e accounts seeded in the API container: `docker compose exec -T api pnpm --filter @wambito/api
  seed:admin` (`dev-admin`, admin spec) and `seed:e2e-preview` (`preview-e2e`,
  preview@wambito.test, the encrypted-preview account; `E2E_PREVIEW_USER_IDS` defaults to it in
  `docker-compose.yml`). `vault.spec.ts` runs `seed:e2e-preview` itself in `beforeAll`, which
  deletes and recreates the user (no records, key wraps or finance rows), so it needs the stack up
  and `docker` on the PATH; it runs on the desktop project only (one shared account; the file is skipped on the phone and
  its `beforeAll` returns there). CI seeds it
  too.

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
