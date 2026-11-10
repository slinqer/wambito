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
  also the sync helpers `readOutbox`, `ackOutbox` (records the pushed `keyV` too), `getMeta/setMeta`,
  `quarantine`, `wipeRecords`, `getKey/putKey/deleteKey/keyNames`, `parkOutbox`, `abandonOutbox`,
  `adoptServerCopy`, `restoreSetAside`, `queueReseal(current, limit)` (outbox entries `reseal: true`
  for pushed records under an older `keyV`), `keyVersionsInUse()`). Subscribers fire after every commit that
  wrote, whatever its origin, and for other tabs' commits too (a BroadcastChannel
  `wambito-vault-<userId>` tells the other tabs of each commit). `close()` (or another tab deleting
  or upgrading the database) closes it for good: every later op rejects with `VaultClosedError`
  (code `vault_closed`); `isClosed()`, `onClosed(cb)` → unsubscribe. `wipeRecords` keeps the outbox
  and sets pending entries aside (`restoreSetAside` puts them back after the full download,
  merging the touched fields); remote writes take `skipIfPending` / `ifSeq`.
  `sync.ts` (`createSyncEngine({ store, fetch, userId, keyring, refreshKeys, onError })` → `run()` /
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
  `session_changed`; `KeysError("session_changed")` in `keys.ts`). Key versions: a record opens
  with the keys of its own `keyV`, every change is sealed under `keyring.current`; a record under a
  newer `keyV`, or a per-change `key_version_mismatch` (pushed again once, re-sealed), calls
  `refreshKeys` once per run (still unknown: quarantine `unknown_key_version`); after each pull the
  upgrade pass re-seals records under an older `keyV` through the outbox (`reseal` entries: unchanged
  body, `baseVersion` = its version, at most 500 per run, a conflict takes the server's copy) and
  drops an old version's keys once no local record uses it; `refreshKeys` throwing `device_removed`
  stops the run and the triggers (`{ ok: false, error: "device_removed", problem: "device_removed" }`).
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
  `currentRecordKeys(local)`; the sync engine takes the keyring), `withDataKey(options, fn)`
  (DK from this browser's own device wrap: found by `deviceWrapId`, its `publicKey` must equal
  `devicePublicKey`, opened with `openFromDevice`; `fn(dk, keyV)`, DK zeroed after;
  `KeysError("device_removed")` otherwise; a 2a browser without `deviceWrapId` tries each device
  wrap and keeps the one that opens), `refreshKeys(options)` (a device wrap at a higher `keyV` is
  added to the keyring and made current, old versions kept; one at or below the current version
  changes nothing, and a held version is never overwritten), `dropKeyVersion(userId, keyV)`,
  `forgetDevice(userId)` (sign-out: `deleteVault`). The recovery secret is zeroed
  in a `finally`. A 409 `key_version_mismatch` from `/v2/keys` is `KeysError("rotated_elsewhere")`;
  `api`, `listWraps`, `putJson` and `WrapDto` are exported for `rotate.ts`.
  Passkeys: `unlockWithPasskey({ userId, credentialId, prf })` opens the passkey wrap whose `ref` is
  the credential (base64url, Better Auth's `credentialID`) and enrolls this browser
  (`KeysError("no_passkey_wrap")` when none opens); `addPasskeyWrap({ userId, credentialId, prf })`
  PUTs `kind: "passkey"`, `ref`, at the current `keyV`, DK from `withDataKey` (the touch is the
  confirmation; an existing wrap of that credential keeps its id; a credential not the account's is
  the server's 422, `KeysError("unknown_passkey")`, nothing stored). The caller zeroes the PRF.
  `prf.ts`: `prfExtension()` (`PRF_SALT`), `readPrf(clientExtensionResults)` (a copy of
  `prf.results.first` only when 32 bytes, the browser's bytes zeroed: `prf: {}` from Proton Pass /
  1Password is null),
  `evaluatePrf(credentialIds?)` (a raw `navigator.credentials.get`, random challenge, `rpId` =
  hostname, `userVerification: "required"`; nothing goes to the server; null on cancel,
  `KeysError("no_prf")`), and the one-shot stash `keepSignInPrf({ userId, credentialId, prf })` /
  `takeSignInPrf(userId)` (another account's is zeroed, null) / `clearSignInPrf` (module memory
  only, never storage; cleared by `liveSignOut`, by the `/app` and
  `/welcome` loaders of a plain account and once the vault is open). The passkey sign-in (also
  autofill, `features/sign-in/auth.ts`) and `auth/passkey.ts` `addPasskey(prf?)` ask for the
  extension with `returnWebAuthnResponse: true`; a registration that says `prf.enabled` without
  results gets one second touch (`evaluatePrf([newId])`, explained first by a toast
  `vault.passkey_second_touch`) only for an encrypted account. The passkey offer
  (`offerPrfUse`) stashes the new passkey's PRF for that user's gate, and knows the account is
  encrypted from the profile the sign-in cached (`queryKeys.me()`; no request, a reload counts as
  plain); Settings (mode `local`, `PasskeysSection` `vaultUserId`) adds the wrap
  at once.
  `rotate.ts` (two steps, like `prepareAccount`): `rotateKeys({ userId, remove, recovery: { text }
  | { fresh: true }, passkey?: { credentialId, prf } })` → `{ recoveryKey, commit() → { keyV,
  dropped } }`: the typed key must open the current recovery wrap first (`wrong_recovery_key`,
  nothing made); DK from `withDataKey`; device wraps in `remove` (`removed`), in
  `settings.revokedDevices` (`revoked`) or whose attestation fails under the old DK
  (`attestation`) are left out and reported; a new DK at `keyV + 1` wraps the recovery secret (the
  same one, or a new one shown as `recoveryKey`), every kept device (same id/ref/label, sealed to
  its public key, fresh attestation; this browser's own with its kept public key) and the touched
  passkey (same wrap id; other passkeys lose theirs); DK, the new DK, the secret and the PRF are
  zeroed before it returns. `commit()` POSTs `/v2/keys/rotate` (retry-safe; a post that ended
  `offline` or `rotated_elsewhere` counts as ours when `GET /v2/keys` shows this browser's prepared
  wrap at the new `keyV`), keeps
  `record:<v>`/`dedupe:<v>` and meta `keyV`, and adds the removed ids to `settings.revokedDevices`
  (a local write); the caller then calls the session's `reloadKeys()`. `newRecoveryKey(options)` →
  `{ recoveryKey, commit() }`: a new secret wraps DK at the current `keyV`, PUT on commit (replaces
  the recovery wrap). Also exported for Settings: `checkRecoveryKey({ userId, text })` (resolves when
  the typed key opens the current recovery wrap; `bad_` / `wrong_recovery_key`; nothing sent),
  `attested(userId, dk, wrap)` and `revokedDevices(userId)`. `pairing.ts` (stage 1b spec section 1, both roles; injected `clock`
  `{ now, sleep }` for tests, polls every 1.5 s, both stop at `expiresAt` capped at 10 minutes from this device's start (the
  request, or the approver's lookup) → `expired` and on
  `cancel()` → `cancelled`): `startPairing(options)` → `{ id, code, qr, expiresAt, number(),
  finish(), cancel() }` (the new device: an ephemeral pair `N`, separate from the device key pair,
  posts its commitment; `qr` is `wambito://pair?id=<id>&key=<base64url N.pub>`; polling pins the
  first `approverKey` and reveals `N.pub`, then `number()` resolves; `finish()` picks up, opens
  with `openFromPairing` against the pinned key and enrolls with `enrollDevice`, the opened DK
  zeroed); `findPairing({ ...options, code } | { ...options, qr })` → `{ number(), approve(),
  cancel() }` (the approving device: pins the commitment from `?code=`, or the QR key's own
  commitment after checking it against `GET /v2/pairing/{id}`, then posts its ephemeral `A.pub`;
  `number()` after a revealed key that matches the pinned commitment (and the QR key);
  `approve()` (a plain `Error("approve before number")`, nothing sent, unless `number()` resolved
  on that object) seals DK from `withDataKey` from `A` at its `keyV`, then waits for the pickup's
  404). `PairingError` codes `expired` (404 or the clock), `tampered` (any relayed value that does
  not match a pin, a 422, a second approver), `bad_code` (a code that cannot be one or finds
  nothing, a QR not exactly that string), `offline`, `server`, `cancelled`; `session_changed` and
  `rotated_elsewhere` stay `KeysError`s. `stale-vaults.ts` `deleteStaleVaults(keepUserId)`: deletes every
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
  or, later, closes the session and calls `onSessionChanged`. The engine's `refreshKeys` is
  `keys.ts` `refreshKeys` over the session's network; `device_removed` fails the opening
  (`VaultOpenError("device_removed")`) or, later, stops the sync, deletes the vault and calls
  `session.onRemoved(cb)` listeners (`VaultGate` routes them to `gate.removed()`: Unlock with the
  notice `vault.removed`, a guest's Locked). `session.reloadKeys()`
  gives the engine the keyring the vault now holds (`engine.useKeyring`, only a higher or equal
  `current`) and runs a sync; called after a rotation commits. Its `fetch` is the local backend plus `DELETE /v1/me` sent to the
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
  ready, else `Locked` with a retry of the failed step; an account with keys elsewhere first tries
  the stashed sign-in PRF (`takeSignInPrf`), and a passkey that opens nothing (stashed, or touched
  from Unlock's "Use a passkey", `gate.unlockWithPasskey()`, which offers only the account's
  passkeys from Better Auth's list, none: `no_passkey_wrap` without a touch) gets its wrap once the vault is
  unlocked by the recovery key or set up; a known browser zeroes the stash; Unlock's "From another
  device" and a guest Locked's "Approve from another device" enter `pairing` (`gate.pair()`;
  `gate.startPairing()` makes the request, again for "Start again", cancelling the previous one;
  the latest call wins: an older one answering later cancels its own request;
  its `finish()` opens the vault like a recovery unlock: pending passkey wrap, full sync; a failed
  pairing stays on its screen; `gate.leavePairing()` cancels and goes back to Unlock or Locked);
  before making or unlocking keys, when the
  open vault closes, and on `session_changed` (`gate.sessionChanged()`), it reads who is signed in
  (live `GET /v1/me`) and, when it is another account or none, reloads the app at `/app`, so
  nothing runs for the old id; Locked kinds `error`, `offline`,
  `unsupported` (no X25519: no retry) and `guest` (a guest whose account has keys elsewhere: no
  recovery key to type, so pair from another device, sign out or delete the account); a 401 from `/v2/keys` signs in again) and then `<ApiProvider mode="local">`;
  the onboarding flag is the vault's (`LocalOnboardingRoute`), not the server's. `ApiMode` is
  `live | demo | local`: demo-only behaviour checks `=== "demo"`, live-only `=== "live"`
  (import); settings shows `settings.local_off` under import, export and the assistants in
  `local`; the welcome skips its import step there. Screens in
  `app/features/vault/`: `RecoveryKeySetup` (key in groups of four, copy, `.txt`, then type four
  characters back, each named "group N, character M"; `onCancel` instead of `onSignOut` in Settings), `Unlock` (`notice: "removed"` shows `vault.removed`; `onUnlock(text) → UnlockError |
  null`, `onPasskey() → UnlockError | null` with the `no_prf` / `no_passkey_wrap` copy; no button
  where `passkeysSupported()` is false; `onPair` "From another device"), `Locked` (retry, guest delete, guest `onPair`); all three have `onSignOut` (the gate passes `useSignOut`,
  which wipes the vault); `PairNewDevice` (`start() → request`, `onBack`, `timeZone` (the profile's, for the expiry): the QR as `uqr`
  `renderSVG` in an `<img>` data URL, alt = the code, the code as `ABCD EFGH`, the expiry, the
  number once `number()` resolves, done after `finish()`; expired / offline / server offer "Start
  again", tampered only back; `cancelled` shows nothing); `ApproveDevice` (`keys: PairingOptions`,
  injected `findPairing` and `scanSupported`, `onDone`; Task 8 mounts it in Settings → Security:
  type the code, or scan where `BarcodeDetector` exists (a `getUserMedia` video, stopped on a
  `wambito://pair?` hit, on cancel and on unmount), then the number with "They match" (only once
  shown; disabled while `approve()` runs) and "They do not match" (cancels: nothing shared));
  `vault-context.ts` `VaultSessionContext` / `useVaultSession()`: the gate provides the open
  session beside `<ApiProvider mode="local">` (null elsewhere), so Settings reaches its keys.
  Settings → Security (`features/settings/`, mode `local` and not a guest, Ruling 8):
  `security.ts` `SecurityApi` (`load()` → wraps, `ownId`, `revoked`, `verified` (attestations under
  DK from `withDataKey`), `unreadable` (`quarantineCount()`); `rotate`, `checkRecoveryKey`,
  `newRecoveryKey`, `reloadKeys`, `evaluatePrf`, `addPasskeyWrap`, `pairing`), `liveSecurity(session)`
  the default, `Settings`' `security` prop (and `HomeStage`'s) for stories; react-query key
  `SECURITY_KEY`; `security-model.ts` (`deviceRows`: this browser marked and never removable,
  revoked ids left out, "Not verified" when the attestation fails; `passkeyRows`: joined to passkey
  wraps by credential id, `PasskeyItem.credentialId`); `SecuritySection.tsx` (devices, "Approve a new
  device" (`ApproveDevice` in a full-screen `Takeover`), "New recovery key" (the current key typed
  or a passkey touch, `no_prf` counts and a cancel does not, then `RecoveryKeySetup`, `commit()`
  after the four characters), "Could not read N items" only when N > 0); `RemoveDeviceSheet.tsx`
  (the recovery key typed, or "make a new one": a passkey touch, whose PRF (a copy per try, since
  `rotateKeys` zeroes it) keeps that passkey's wrap; then `commit()`, `reloadKeys()`, and what was
  dropped; `rotated_elsewhere` reloads the keys and says to try again; "make a new one" (and New
  recovery key's touch) waits for the passkey list (`PasskeyList`: disabled while loading, hidden
  with a retry when it failed; with passkeys but no WebAuthn here, only the typed key); a
  `Takeover` makes the rest of the page `inert`); `PasskeysSection` with
  `security` shows "Opens your data" / "Does not open your data" and "Turn on" (`evaluatePrf([id])`
  then `addPasskeyWrap`; `no_prf` names the recovery key and another device). Stories
  `Settings/Security`, web-only, not in parity.json; copy under `settings.security.*`.
  `uqr` is in `vitest.config.ts` `optimizeDeps.include` like every dependency a story imports; pure UI,
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
