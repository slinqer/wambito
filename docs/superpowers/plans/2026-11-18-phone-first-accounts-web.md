# Phone-first accounts, delivery 3 (the web) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The web side of phone-first accounts: the landing's three doors, the sign-in by a QR the
phone approves (with "Keep me signed in on this browser", ticked by default), recovery-key sign-in,
"Install the app" after a web sign-up, "Protect your data" for a user without an email, the daily
"seen" call, the admin panel's new numbers, and `apps/web/AGENTS.md`. A `plain` account behaves as
today.

**Architecture:** Two new browser-side modules next to `app/local/pairing.ts`: `signin.ts` (the
new browser's half of the `/v2/signin` relay, on helpers shared with pairing through a new
`relay.ts`) and `recovery-signin.ts`. The sign-in screen gets a QR panel driven by a pure model
(`signin-model.ts`), on `/sign-in` in every build (the founder's answer 1).
Everything after the sign-in reuses the vault gate: the QR and recovery paths enroll this browser
before navigating, so `/app` finds its keys and opens. "Protect your data" lives in Settings →
Security and reads the synced `settings.recoveryKeySavedAt` the phone delivery defines.

**Tech Stack:** React Router 8 (SPA), React 19, TanStack Query, `use-intl`, `@wambito/crypto`
(WebCrypto), `@wambito/vault`, IndexedDB, `uqr`, Vitest (unit + Storybook/Chromium), Playwright.

**Spec:** `docs/superpowers/specs/2026-11-15-phone-first-accounts-design.md`, section 16 item 3
(sections 5.2, 6, 8.1–8.4, 9, 15 "Web"). Read with the API plan
`docs/superpowers/plans/2026-11-15-phone-first-accounts-api.md` (routes, fields and codes are fixed;
this plan adds no API) and the phone plan on `feat/phone-first-accounts-phone`
(`docs/superpowers/plans/2026-11-18-phone-first-accounts-phone.md`, rulings 1, 4, 15, 19 and
Task 12: the approver this browser talks to).

## Global Constraints

- **Branch and PR:** this worktree's branch, one PR against `main`. Merging deploys: only on the
  founder's yes. Never touch `apps/mobile` (the phone delivery is on its own branch).
- **The switch, on the web:** the account decides: `GET /v1/me` `encryption` (`previewProfile()`);
  every vault screen already renders only for `preview`, and a `plain` account sees today's
  screens once signed in. The signed-out pages (landing doors, `/sign-in` with its QR,
  `/create-account`) are the same in every build (founder's answers 1 and 3): before the switch
  only a `preview` account's phone can approve the QR, and the email form sits beside it.
- **API, exactly as built:**
  - `POST /v2/signin` `{ commitment, remember, label }` → 201 `{ id, code, pollSecret, expiresAt }`;
    429 `too_many_requests` (30 per 10 min per IP) / `too_many_signins` (5 open per IP), with
    `retry-after`;
  - `GET /v2/signin/{id}` with `x-wambito-poll: <pollSecret>` → `{ approverKey, ready, expiresAt }`;
  - `POST /v2/signin/{id}/reveal` `{ publicKey }` (poll header; 204; 409 `not_ready` |
    `already_set`; 422 `commitment_mismatch`);
  - `POST /v2/signin/{id}/pickup` (poll header) → 200 `{ sealed, keyV, userId }` and the session
    cookie; 409 `not_ready`; 403 `account_suspended`; 404 once taken, expired or a wrong secret;
  - `POST /v2/recovery/sign-in` `{ lookup /* 16 B */, auth /* 32 B */ }` base64url → 200
    `{ userId }` and the cookie; 401 `recovery_key_invalid`; 403 `account_suspended`; 429;
  - `PUT /v2/recovery/verifier` `{ lookupHash, authHash }` (204; 409 `recovery_required` |
    `verifier_taken`); `POST /v2/me/seen` (204) with `x-wambito-version`
    (1–64 of `[A-Za-z0-9.+_-]`);
  - `POST /v1/me/claim-email/send` and `/verify` (409 `email_taken`);
  - `GET /v1/admin/metrics` adds `dailyActive`, `cohorts`, `installsByPlatform`, `versions`;
    `guests` and `weekly[].guests` now mean "without email".
- **Exact values from the spec and the phone plan:**
  - QR text `wambito://signin?id=<id>&key=<base64url N.pub>` (43 characters of key); the code shown
    as `ABCD EFGH`; request lifetime **2 minutes**, a new one while the page is visible;
  - commitment `pairingCommitment(N.pub)`; the 6-digit number `pairingNumber(N.pub, A.pub)` (the
    order `startPairing` uses);
  - the phone seals with `sealToDevice` under `{ kind: "device", userId, keyV }` (phone ruling 15):
    the browser opens with `openFromPairing(N.priv, { kind: "device", userId, keyV }, sealed, A.pub)`;
  - `label` = `deviceLabel(navigator.userAgent)` (`"Firefox on macOS"`, else `"Web"`), 1–64 chars;
  - the box is **ticked by default**; unticked copy: "Nothing stays on this computer when you
    close the browser";
  - recovery derivation `recoveryVerifier(secret)` → `{ lookup, auth }`; hashes with
    `verifierHash`;
  - "N of 2"; the passkey step counts only with a **passkey wrap**; its no-PRF copy: "This passkey
    can sign you in but cannot open your data. Add a recovery key."
- **Copy:** every string in `app/i18n/messages/app.{es,en,it,pt}.json` (landing strings in
  `{es,en,it,pt}.json`), Wambi's voice, PT-PT; `messages.test.ts` keeps them in step. Spanish is
  the reference; the money slang rule holds.
- **Secrets:** a typed recovery key, the recovery secret, `lookup`/`auth`, the poll secret, DK, a
  PRF and the ephemeral private key are never logged, never put in storage, never in a URL; byte
  arrays are zeroed in a `finally` as `keys.ts` does. The poll secret lives in module memory only.
- **Generated files:** never hand-edit `app/api/schema.d.ts` (it already has every route used
  here), `tokens.css`, `public/landing/*`.
- **No root `CHANGELOG.md` line:** nothing here changes the API or the MCP.
- **Repo rules:** failing test first; English in code and docs; invented fixtures; money in integer
  cents. Commits `feat(web): …` (`feat(core): …` for Task 1's schema line, `chore(deploy): …` for
  `up.sh`), a lowercase sentence, staged by path, never `git add -A`, never a `Co-Authored-By`
  line. Each task updates the `apps/web/AGENTS.md` bullet it changes.
- **Commands** (repo root): `pnpm vitest run apps/web/app/<path>` (unit),
  `pnpm vitest run apps/web --project "@wambito/web (storybook)"`, `pnpm lint`, `pnpm typecheck`;
  e2e per `apps/web/AGENTS.md` (`E2E_NOW=2026-10-21T15:00:00Z docker compose up -d --build`, then
  `pnpm --filter @wambito/web e2e`; afterwards `docker compose stop`, never `down -v`).

## Rulings (where the spec leaves the choice, or the code forces one)

Each with what it costs if wrong. "Founder" marks an answer given on 2026-11-18.

1. **The QR is on `/sign-in` in every build (founder).** No build flag and no API route: the web
   cannot tell the switch, and does not need to. *Cost:* before the switch day a `plain` person
   sees a QR their phone cannot approve yet; the email form and the passkey are beside it.
2. **The web e2e runs with the API flag on (founder; API plan decision 17).** The CI `e2e` job and
   the documented local command start the stack with `NEW_USERS_ENCRYPTED=true`;
   `docker-compose.yml` passes `NEW_USERS_ENCRYPTED: ${NEW_USERS_ENCRYPTED:-false}` (the phone
   plan's ruling 19 line, byte for byte, so the two branches merge cleanly). The specs that test
   the `plain` app (home, insights, manage, paging, overflow-it-pt, settings, onboarding, a11y,
   feel's three groups, admin's target user) get their accounts from a new seed
   `seed:e2e-plain-user <email>` (a direct insert with `encryption: 'plain'`, as `seed-admin.ts`),
   then sign in by email as today: `signUpNewUser` keeps its name and signature and seeds first.
   A new onboarding spec covers the born-encrypted web sign-up. *Cost:* one `docker compose exec`
   per plain sign-up in the e2e (about a second).
3. **The landing's doors change now, for every build (founder):** hero "Create account" (primary)
   and "Try the demo"; header "Sign in". "Create account" opens `/create-account` (the email code
   form under a "Create your account" title); "Sign in" opens `/sign-in`. *Cost:* none.
4. **"Install the app" links** what exists today: the Android APK on GitHub
   (`ANDROID_APK_HREF`, `ANDROID_RELEASE_HREF`). Google Play, F-Droid and the App Store are
   constants set to `null` (`PLAY_HREF`, `FDROID_HREF`, `APP_STORE_HREF` in `landing/links.ts`) and
   their buttons show once a constant is set. *Cost:* none; one line per store when it ships.
5. **Adding an email on the web (founder):** a small claim flow (email, then the 6-digit code) over
   `/v1/me/claim-email/send|verify`. A 409 `email_taken` does **not** merge on the web: "This email
   already has a Wambito account. Open Wambito on your phone to bring this data into it."
   *Cost:* a web-only person cannot merge (rare: a user without an email reached the web by phone).
6. **The web's guest branch is retired** (as phone ruling 4): every `preview` account, with or
   without an email, gets Unlock (recovery key, passkey, "From another device") when its keys are
   elsewhere; `LockedKind` `guest`, `PairingFrom` `guest` and `SecuritySection guest` go.
   `prepareAccount({ guest })` stays. *Cost:* none known; a person who never protected sees an
   Unlock whose only working way is "From another device".
7. **`settings.recoveryKeySavedAt`** is the phone plan's field (phone ruling 1, its Task 3). This
   branch adds the **same line and the same two tests** to `packages/core/src/records.ts` in its
   own commit `feat(core): settings remember when a recovery key was saved`; whichever branch
   merges second drops that commit when it rebases. *Cost:* one trivial rebase.
8. **The 6-digit number on the web:** the browser cannot know whether the phone scanned the QR or
   typed the code, so once it has pinned the approver key and revealed, it shows the number under
   the QR in a quiet line ("If your phone shows a number, it must be 123 456"). After a scan the
   phone shows none and the line is harmless. *Cost:* one line of copy.
9. **The box sets `remember` on the request;** changing it opens a new request (the QR changes)
   after 500 ms without another change, and never once an approver is pinned. *Cost:* a fast
   toggler can meet `too_many_signins`, shown with a retry when the oldest frees (`retry-after`).
10. **Renewal:** a request in `showing` (no approver yet) is replaced at its `expiresAt` while
    `document.visibilityState === "visible"`; a hidden page stops polling and opens a new request
    when it is visible again. A request with a pinned approver is never replaced: it runs to its
    end (picked up, expired, failed). *Cost:* none.
11. **Unticked ("ephemeral") mechanics** (spec 8.2, builder's latitude): the API already makes a
    12-hour session whose cookie has no `Max-Age`. The browser marks the vault's meta
    `ephemeral: true` at enrollment; the existing sweep (`deleteStaleVaults(null)` on every
    signed-out load of the live guards) wipes it once the cookie is gone. In addition, the app
    layout's loader wipes an `ephemeral` vault whose user is not the signed-in one. A reload of
    the same tab keeps the session (the cookie lives until the browser closes). *Cost:* a signed-out
    visit to the prerendered landing alone does not wipe; the next app page does.
12. **The sign-in screen:** on a wide screen (≥ `md`) the QR panel and its box
    come first, then "Other ways to sign in" with the passkey button, "Recovery key" and the email
    form, all on the page (no hidden disclosure), so the email form keeps its labels; on a narrow
    screen (a phone, where a QR cannot be scanned by itself) the other ways come first and the QR
    panel follows under "Signing in on a computer? Scan with your phone". The QR request is opened
    only while the panel is on screen (`IntersectionObserver`). *Cost:* a long page on a phone.
13. **After a QR or recovery-key sign-in** the browser enrolls before navigating (the cookie is
    already set), then `useFinishSignIn({ method: "qr" | "recovery" })`: no passkey offer, the
    `?next=` and `?lang=` handling of today. The gate then finds its keys and opens with a full
    sync. *Cost:* none.
14. **Recovery-key sign-in unlocks with the same typed text** (phone ruling 6): parse once, derive,
    sign in, then `unlockWithRecovery({ userId, text })`, which also writes the verifier (Task 1).
    A failed unlock after a good sign-in signs out (`liveSignOut`) and shows the error. *Cost:* none.
15. **"Install the app"** is a screen of the vault gate after a first setup in this browser
    (`setup` → commit → `install` → ready), shown once per account set up here; never for a `plain`
    account (no gate), never after an unlock or a pairing. *Cost:* none.
16. **The first recovery key of a user without an email needs no check** (phone ruling 3): Protect
    step 1 calls `newRecoveryKey` with no typed key and no passkey touch; the open vault and the
    session are the proof. *Cost:* someone at an unlocked browser can make a key; they already see
    the data.
17. **The daily seen call** (spec 9: "The web calls it once per day on load"): once per local day
    per user, on the `/app` loader, for every signed-in account, `plain` too (phone ruling 13);
    stored `wambito.seen.<userId>` = `YYYY-MM-DD` (`readStored`/`writeStored`); best effort.
    `x-wambito-version` = `VITE_BUILD_ID` (set by `up.sh` to the short git commit), else `dev`
    (the only `up.sh` change).
    *Cost:* one small request a day.
18. **Admin:** the cards' "guests" read "Without email" / "With email"; the home screen adds four
    plain blocks: daily actives (90 bars, the `SignupsChart` style), cohorts (a table, week 1/4/12
    as "at least N", "—" for `null`), installs by platform, versions (a table). Spanish and
    English only (`admin.{es,en}.json`). *Cost:* none.

## Pre-flight conflict scan (done while planning)

- **`feat/phone-first-accounts-phone`:** its plan touches `packages/core/src/records.ts` and its
  test (ruling 7) and `docker-compose.yml` (its ruling 19 line, which this plan adds identically,
  ruling 2), and the CI `mobile-e2e` job (this plan edits only the `e2e` job). This plan never
  touches `apps/mobile`. No other shared file.
- **`main`:** clean at `91923a1d`; re-checked before the PR (`git fetch && git diff
  HEAD...origin/main --stat`).
- **Same names:** the phone's `signin` link host and `wambito.vault.<userId>.seenDevices` are phone
  storage; the web adds `wambito.seen.<userId>` (localStorage) and the vault meta `ephemeral`.

## Review Focus

1. **A tab left in the background past 2 minutes, then shown again:** it must never show an
   expired QR, and must open exactly one new request. Pinned in Task 3.
2. **The phone approves just as the request reaches its renewal time:** the approved request must
   finish (not be replaced). Pinned in Task 3.
3. **A recovery key typed the way people type it** (lower case, spaces, dashes, `O` for `0`): it
   signs in and the same text unlocks. Pinned in Task 4.
4. **An unticked sign-in on a shared computer:** no `Max-Age` on the cookie, and once the session
   cookie is gone, the next app page finds no `wambito-vault-*` database. Pinned in Task 5 and the
   e2e of Task 13.
5. **Another account's vault left in this browser when a QR sign-in finishes:** it is swept, and
   the new account's vault is never the one swept (enrollment runs after `deleteStaleVaults(userId)`).
   Pinned in Task 2.

---

### Task 1: The recovery verifier and `recoveryKeySavedAt` on the web

**Files:**
- Modify: `packages/core/src/records.ts`, `packages/core/src/records.test.ts` (ruling 7);
  `apps/web/app/local/keys.ts` (`putRecoveryVerifier`; `prepareAccount` commit; `unlockWithRecovery`),
  `apps/web/app/local/rotate.ts` (`newRecoveryKey` commit; `rotateKeys` with `fresh`),
  `apps/web/app/local/vault-session.ts` (`markRecoveryKeySaved`), `apps/web/AGENTS.md` (the
  `keys.ts` and `rotate.ts` paragraphs).
- Test: `apps/web/app/local/keys.test.ts`, `apps/web/app/local/rotate.test.ts`,
  `apps/web/app/local/vault-session.test.ts`.

**Interfaces:**
- Produces:
  - settings field `recoveryKeySavedAt: timestamp.nullable().default(null)` (the phone plan's exact
    line);
  - `putRecoveryVerifier(options: KeysOptions, secret: Uint8Array): Promise<void>` in `keys.ts` —
    `recoveryVerifier` + `verifierHash` of both, `PUT /v2/recovery/verifier` base64url, the raw
    outputs zeroed;
  - `prepareAccount` commit: after the recovery wrap and before the device wrap, the verifier of a
    shown key (`guest: false`); a guest's hidden key never gets one; retry-safe (the same secret);
  - `newRecoveryKey` and `rotateKeys(recovery: { fresh: true })` commit: the new key's verifier
    after the wrap (the server deleted the old one with the old wrap);
  - `unlockWithRecovery`: best effort after enrolling (a failure never fails the unlock);
  - `markRecoveryKeySaved(session: VaultSession, now: Date): Promise<void>` in `vault-session.ts` —
    one local write of the settings record with `recoveryKeySavedAt` (ISO UTC), then `sync()`.

- [ ] **Step 1: Write the failing tests.**
  - `records.test.ts`: `settings without recoveryKeySavedAt parses to null`; `a timestamp is kept`.
  - `keys.test.ts` (the existing fake `/v2`): `prepareAccount puts the verifier of the shown key after the recovery wrap and before the device wrap`
    (order of calls; the hashes equal `verifierHash` of `recoveryVerifier(secret)` for the key the
    test reads back); `a guest's commit sends no verifier`;
    `a retried commit sends the same verifier`; `unlockWithRecovery puts the verifier and still unlocks when that PUT fails`.
  - `rotate.test.ts`: `newRecoveryKey puts the new key's verifier after the wrap`;
    `a rotation with a fresh key puts its verifier; with the typed key it puts none`.
  - `vault-session.test.ts`: `markRecoveryKeySaved writes the field on the settings record and queues it`.
- [ ] **Step 2: Run** `pnpm vitest run --project @wambito/core` and
  `pnpm vitest run apps/web/app/local`. Expected: FAIL (field unknown; no verifier call).
- [ ] **Step 3: Implement** as in Interfaces.
- [ ] **Step 4: Run** the same two commands. Expected: PASS.
- [ ] **Step 5: Commit** twice: `feat(core): settings remember when a recovery key was saved`
  (the two `packages/core` files), then `feat(web): write the recovery verifier with every shown key`.

### Task 2: The browser's half of `/v2/signin`

**Files:**
- Create: `apps/web/app/local/relay.ts`, `apps/web/app/local/signin.ts`.
- Modify: `apps/web/app/local/pairing.ts` (imports `relay.ts`; behaviour unchanged),
  `apps/web/app/local/keys.ts` (`enrollDevice` takes `{ ephemeral?: boolean }`, meta `ephemeral`),
  `apps/web/AGENTS.md`.
- Test: `apps/web/app/local/signin.test.ts`; `pairing.test.ts` must pass unchanged.

**Interfaces:**
- Consumes: `enrollDevice`, `deviceLabel`, `deleteStaleVaults`, `@wambito/crypto`
  (`generateDeviceKeyPair`, `pairingCommitment`, `pairingNumber`, `openFromPairing`,
  `toBase64Url`, `fromBase64Url`).
- Produces:
  - `relay.ts`: `PairingClock`, `realClock`, `deferred<T>()`, `zeroPrivate(key)`,
    `sameBytes(a, b)`, `key32(text, onBad: () => Error)` moved from `pairing.ts` (which re-exports
    `PairingClock`);
  - `signin.ts`:
    - `type SigninErrorCode = "expired" | "tampered" | "offline" | "server" | "cancelled" | "too_many" | "suspended"`;
      `class SigninError extends Error { code; retryAfterS?: number }`;
    - `SIGNIN_POLL_MS = 1500`, `SIGNIN_TTL_MS = 2 * 60 * 1000` (this browser's own cap);
    - `startSignin(options: { remember: boolean; label: string; clock?: PairingClock; fetch?: typeof fetch }): Promise<WebSignin>`
      — makes `N`, posts `{ commitment, remember, label }` to `/api/v2/signin` with plain `fetch`
      (no `x-wambito-user`, no session), keeps `pollSecret` in the closure;
    - `interface WebSignin { id: string; code: string; qr: string; expiresAt: string; number(): Promise<string>; finish(): Promise<{ userId: string; keys: LocalKeys }>; cancel(): void }`
      — polling starts with the first `number()` or `finish()`; it pins the first `approverKey`
      (another later is `tampered`), reveals `N.pub` (409 → look again next poll), resolves
      `number()`, waits for `ready`, picks up, checks `userId` is a non-empty string, opens the
      sealed DK with `openFromPairing` against the pinned key (`tampered` on failure), calls
      `deleteStaleVaults(userId)`, then `enrollDevice({ userId }, dk, keyV, { ephemeral: !remember })`;
      DK and `N.priv` zeroed in `finally`; 404 → `expired`, 403 → `suspended`, 429 → `too_many`
      with `retry-after`, network → `offline`, else `server`.

- [ ] **Step 1: Write the failing tests** in `signin.test.ts` (a fake relay over `fetch`, a fake
  clock, real crypto; the test plays the phone with `sealToDevice` from an ephemeral `A` under
  `{ kind: "device", userId, keyV }`):
  - `the happy path: the request posts the commitment of the QR key, number() equals pairingNumber(N, A), finish() enrolls this browser for the picked-up user`;
  - `the qr is wambito://signin?id=<id>&key=<43 base64url chars> and the code is the server's`;
  - `every poll, reveal and pickup carries x-wambito-poll and no x-wambito-user`;
  - `a second approver key on a later poll is tampered, and nothing is picked up`;
  - `a sealed blob that does not open with the pinned key is tampered`;
  - `404 on a poll is expired; the clock past expiresAt is expired; cancel() is cancelled and zeroes N`;
  - `429 too_many_signins is too_many with retryAfterS from retry-after`; `403 on pickup is suspended`;
  - `unticked: the enrolled vault's meta ephemeral is true; ticked: absent`;
  - **(Review Focus 5)** `another account's vault in this browser is deleted before enrollment and the new account's vault remains`
    (an IndexedDB fake with two vaults, as `stale-vaults.test.ts`).
- [ ] **Step 2: Run** `pnpm vitest run apps/web/app/local/signin.test.ts`. Expected: FAIL.
- [ ] **Step 3: Extract `relay.ts`**, run `pnpm vitest run apps/web/app/local/pairing.test.ts`.
  Expected: PASS, unchanged.
- [ ] **Step 4: Implement `signin.ts`** and the `ephemeral` option.
- [ ] **Step 5: Run** `pnpm vitest run apps/web/app/local`. Expected: PASS.
- [ ] **Step 6: Commit** `feat(web): open a sign-in request for the phone to approve`.

### Task 3: The QR sign-in model and panel

**Files:**
- Create: `apps/web/app/features/sign-in/signin-model.ts`, `.../QrSignIn.tsx`,
  `.../QrSignIn.stories.tsx`.
- Modify: `app/i18n/messages/app.{es,en,it,pt}.json` (`sign_in.qr.*`), `apps/web/AGENTS.md`.
- Test: `apps/web/app/features/sign-in/signin-model.test.ts`; the stories (Storybook project).

**Interfaces:**
- Consumes: `startSignin`, `WebSignin`, `SigninError` (Task 2).
- Produces:
  - `type QrState = { status: "opening" } | { status: "showing"; request: WebSignin } | { status: "approved"; request: WebSignin; number: string } | { status: "finishing" } | { status: "done"; userId: string } | { status: "failed"; code: SigninErrorCode; retryAt?: number } | { status: "paused" }`;
  - `createQrSignin(deps: { start: typeof startSignin; label: string; clock: PairingClock; visible(): boolean; onVisibility(cb: () => void): () => void }): { state(): QrState; subscribe(cb): () => void; setRemember(on: boolean): void; remember(): boolean; retry(): void; stop(): void }`
    — `remember()` starts `true`; renewal per ruling 10; box per ruling 9; `failed` `expired`
    while visible renews by itself, other codes wait for `retry()`;
  - `QrSignIn({ model, onSignedIn(userId: string): void, timeZone })`: the QR (`uqr` `renderSVG`
    in an `<img>`, alt = the code), the code as `ABCD EFGH`, "Scan it with Wambito on your phone:
    Settings → Security → Sign in on the web", the box "Keep me signed in on this browser"
    (checked), the unticked line, the number line (ruling 8), "Opening your data…" while
    finishing, errors with "Try again".

- [ ] **Step 1: Write the failing tests** in `signin-model.test.ts` (a fake `start`, fake clock and
  visibility):
  - `opens one request at once with remember true and the label`;
  - `at expiresAt while visible it opens exactly one new request and cancels the old`;
  - **(Review Focus 1)** `hidden: it stops at expiry and opens nothing; visible again: exactly one new request, never the expired QR`;
  - **(Review Focus 2)** `a request whose number() resolved is never replaced at expiresAt; finish() runs to done`;
  - `unticking opens a new request with remember false after 500 ms; two toggles within 500 ms open one`;
  - `the box cannot change once a number is shown`;
  - `too_many shows failed with retryAt and retries by itself at retryAt`;
  - `stop() cancels the request and opens nothing more`.
  Stories: `Sign-in/QR` (showing, unticked, approved with number, finishing, expired, too many);
  a play test: `the box is checked by default and the code reads ABCD EFGH`.
- [ ] **Step 2: Run** `pnpm vitest run apps/web/app/features/sign-in/signin-model.test.ts`.
  Expected: FAIL.
- [ ] **Step 3: Implement** the model, the panel and the copy (four languages).
- [ ] **Step 4: Run** the unit file and
  `pnpm vitest run apps/web --project "@wambito/web (storybook)" -t "Sign-in/QR"`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(web): a qr that renews itself and keeps you signed in by default`.

### Task 4: Recovery-key sign-in (client)

**Files:**
- Create: `apps/web/app/local/recovery-signin.ts`.
- Modify: `apps/web/app/local/keys.ts` (export `parseRecoverySecret` if not already),
  `apps/web/AGENTS.md`.
- Test: `apps/web/app/local/recovery-signin.test.ts`.

**Interfaces:**
- Consumes: `parseRecoverySecret`, `unlockWithRecovery` (Task 1), `deleteStaleVaults`,
  `recoveryVerifier`.
- Produces:
  - `signInWithRecoveryKey(text: string, deps?: { fetch?: typeof fetch }): Promise<{ userId: string; keys: LocalKeys }>`
    — `bad_recovery_key` (nothing sent) for text that does not parse; posts `{ lookup, auth }`
    base64url to `/api/v2/recovery/sign-in`; 401 → `KeysError("recovery_key_invalid")`, 403 →
    `account_suspended`, 429 → `too_many_requests` with `retryAfterS`, offline → `offline`; then
    `deleteStaleVaults(userId)` and `unlockWithRecovery({ userId, text })`; the secret and the
    derived bytes zeroed in `finally`. (Add the three codes to `KeysErrorCode`.)

- [ ] **Step 1: Write the failing tests:**
  - `posts lookup (16 bytes) and auth (32 bytes) derived from the key, then unlocks with the same text`;
  - **(Review Focus 3)** `" abcd-efgh ijkl mnop qrst uvwx yz01 2345 " in lower case, with O for 0, signs in and unlocks`
    (build the messy text from a real `formatRecoveryKey`);
  - `text that cannot be a key is bad_recovery_key and sends nothing`;
  - `401 is recovery_key_invalid; 429 carries retryAfterS; 403 is account_suspended`;
  - `the derived lookup and auth buffers are zeroed after the call` (spy on `recoveryVerifier`).
- [ ] **Step 2: Run** `pnpm vitest run apps/web/app/local/recovery-signin.test.ts`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `pnpm vitest run apps/web/app/local`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(web): sign in with the recovery key`.

### Task 5: The sign-in and create-account pages

**Files:**
- Create: `apps/web/app/routes/create-account.tsx`, `apps/web/app/features/sign-in/RecoveryKeySignIn.tsx`,
  `apps/web/app/local/ephemeral.ts`.
- Modify: `apps/web/app/routes.ts` (`create-account` under the app layout),
  `app/features/sign-in/SignIn.tsx` (`mode: "sign-in" | "create"`; the QR panel and "Other ways to
  sign in" when `mode === "sign-in"`, layout per ruling 12), `app/features/sign-in/auth.ts` (`SignInAuth.signInWithRecoveryKey`,
  `startQrSignin`), `app/features/sign-in/use-finish-sign-in.ts` (`method: "email" | "passkey" | "qr" | "recovery"`;
  only `email` may offer a passkey), `app/routes/app-layout.tsx` (the loader wipes an `ephemeral`
  vault of another user, ruling 11), `app/features/sign-in/SignIn.stories.tsx`,
  copy, `apps/web/AGENTS.md`.
- Test: `apps/web/app/local/ephemeral.test.ts`,
  `apps/web/app/features/sign-in/auth.test.ts`, the sign-in stories.

**Interfaces:**
- Consumes: Tasks 2–4.
- Produces:
  - `SignIn({ auth, mode = "sign-in", qr? })` (`qr`: the model factory, faked in stories);
  - `wipeForeignEphemeralVaults(signedInUserId: string | null): Promise<void>` in `ephemeral.ts`;
  - route `/create-account` (`redirectIfSignedIn` as `/sign-in`).

- [ ] **Step 1: Write the failing tests:**
  - `ephemeral.test.ts`: `a vault marked ephemeral of another user is deleted; the signed-in user's and a non-ephemeral one stay`.
  - `auth.test.ts`: `a qr or recovery sign-in never offers a passkey` (through
    `useFinishSignIn`'s decision function, extracted as `offersPasskey(method, destination)`).
  - Stories (play tests): `Sign-in/Phone first` — `the QR panel and the email form are both on the page, the box checked`;
    `"Recovery key" opens the field and a wrong key reads the recovery_key_invalid copy`;
    `Sign-in/Create account` — `title "Create your account", no QR`;
    `Sign-in/Phone` (narrow) — `the other ways come before the QR panel`.
- [ ] **Step 2: Run** the two unit files and the sign-in stories. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `pnpm vitest run apps/web` and `pnpm typecheck`; then, with the dev stack up,
  `pnpm --filter @wambito/web e2e -- e2e/sign-in.spec.ts e2e/a11y.spec.ts`. Expected: PASS (the
  email form's labels are unchanged; axe passes on the new page). If the run meets 429
  `too_many_requests` from the QR requests, give each Playwright context its own
  `x-forwarded-for` (`clientIp()`) in the shared fixture.
- [ ] **Step 5: Commit** `feat(web): sign in with the phone, a recovery key, or email`.

### Task 6: The landing's doors

**Files:**
- Modify: `app/features/landing/links.ts` (`appLinkProps(locale, door: "sign-in" | "create", …)`,
  `CREATE_ACCOUNT_PATH = "/create-account"`), `Hero.tsx` ("Create account" primary, "Try the demo"),
  `SiteHeader.tsx` ("Sign in"), `app/i18n/messages/{es,en,it,pt}.json` (`landing.hero.cta`,
  `landing.nav.sign_in` as needed), `app/features/landing/links.test.ts`, the landing e2e specs that
  read those labels (`e2e/landing*.spec.ts`), `apps/web/AGENTS.md`.

**Interfaces:**
- Produces: `appLinkProps(locale: Locale, door: "sign-in" | "create", landingOnly?, appOrigin?)`
  (`create` → `/create-account?lang=`, `sign-in` → `/sign-in?lang=`; landing-only rules unchanged).

- [ ] **Step 1: Write the failing test** in `links.test.ts`: `create leads to /create-account?lang=es; sign-in to /sign-in?lang=es; landing-only with an app origin prefixes it; coming soon leads to GitHub for both`.
- [ ] **Step 2: Run** `pnpm vitest run apps/web/app/features/landing/links.test.ts`. Expected: FAIL.
- [ ] **Step 3: Implement**; the hero and header copy in four languages. `landing.meta` and the OG
  images are not touched (the headline and description do not change).
- [ ] **Step 4: Run** the unit file, then `pnpm --filter @wambito/web e2e:landing`,
  `e2e:landing-only`, `e2e:landing-only-app` (built suites, no API needed) and the landing part of
  `e2e` (the header fits one row at 320 px in every language). Expected: PASS.
- [ ] **Step 5: Commit** `feat(web): the landing opens on demo, create account and sign in`.

### Task 7: Unlock for every encrypted account (the guest branch goes)

**Files:**
- Modify: `app/features/vault/vault-gate.ts` (`VaultGateDeps.guest`, `LockedKind` `guest`,
  `pairing.from` `guest` go), `VaultGate.tsx`, `Locked.tsx`, `Locked.stories.tsx`,
  `app/features/settings/SecuritySection.tsx` and `Settings.tsx` (no `guest`), `Security.stories.tsx`,
  copy (`settings.security.guest_lead`, `vault.locked.guest_*` removed after a grep shows no other
  user), `apps/web/AGENTS.md` (the gate and Settings → Security paragraphs).
- Test: `apps/web/app/features/vault/vault-gate.test.ts`.

- [ ] **Step 1: Write the failing test** `an anonymous account with keys elsewhere gets Unlock, not Locked`
  (rewrite of the existing guest case; the old one is deleted on purpose).
- [ ] **Step 2: Run** `pnpm vitest run apps/web/app/features/vault`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `pnpm vitest run apps/web` (unit and storybook) and `pnpm typecheck`.
  Expected: PASS.
- [ ] **Step 5: Commit** `feat(web): every encrypted account unlocks with its key, passkey or device`.

### Task 8: "Install the app" after a web sign-up

**Files:**
- Create: `app/features/vault/InstallApp.tsx`, `InstallApp.stories.tsx`.
- Modify: `app/features/vault/vault-gate.ts` (state `install` after a committed setup),
  `VaultGate.tsx`, `app/features/landing/links.ts` (`PLAY_HREF`, `FDROID_HREF`, `APP_STORE_HREF`,
  all `null`, ruling 4), copy (`vault.install.*`), `apps/web/AGENTS.md`.
- Test: `vault-gate.test.ts`, the story.

**Interfaces:**
- Produces: `GateState` `{ status: "install" }`; `gate.installDone()` → `ready`;
  `InstallApp({ onContinue, links = STORE_LINKS })`.

- [ ] **Step 1: Write the failing tests:** `a setup committed here shows install, then ready`;
  `an unlock, a pairing or a known browser never shows install`. Story play test:
  `shows the Android download and no button for a store whose link is null`.
- [ ] **Step 2: Run** `pnpm vitest run apps/web/app/features/vault`. Expected: FAIL.
- [ ] **Step 3: Implement**: Wambi, "Wambito lives on your phone", the APK button (and the release
  page link), the store buttons whose constant is set, "Continue".
- [ ] **Step 4: Run** unit and storybook for `apps/web`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(web): offer the app after a web sign-up`.

### Task 9: "Protect your data" (recovery key and passkey)

**Files:**
- Create: `app/features/settings/protect-model.ts`, `ProtectSection.tsx`, `Protect.stories.tsx`.
- Modify: `app/features/settings/Settings.tsx` (at the top of Security, mode `local`, profile
  `isAnonymous`), `security.ts` (`SecurityApi.markRecoveryKeySaved()`, `settings()` → the settings
  record), copy (`settings.protect.*`), `apps/web/AGENTS.md`.
- Test: `app/features/settings/protect-model.test.ts`, the stories.

**Interfaces:**
- Consumes: `newRecoveryKey` (`SecurityApi`), `RecoveryKeySetup`, `addPasskey(prf)`,
  `addPasskeyWrap`, `passkeyRows`/the snapshot's wraps, `markRecoveryKeySaved` (Task 1).
- Produces:
  - `protectStatus(input: { anonymous: boolean; recoveryKeySavedAt: string | null; passkeyWrap: boolean; passkeyWithoutWrap: boolean; passkeysSupported: boolean }): { show: boolean; recoveryKey: boolean; passkey: boolean; passkeyOffered: boolean; passkeyWithoutPrf: boolean; done: number; protected: boolean } | null`
    (null when not anonymous);
  - `ProtectSection({ security, profile, onAddEmail })`: "N of 2" until a step is done, then a quiet
    list; step 1 runs ruling 16 then `markRecoveryKeySaved`; step 2 adds a passkey and its wrap,
    or shows the no-PRF copy; step 3 calls `onAddEmail` (Task 10).

- [ ] **Step 1: Write the failing tests** in `protect-model.test.ts`:
  `null for an account with an email`; `0 of 2 with nothing`; `a passkey without a wrap is not done and sets passkeyWithoutPrf`;
  `the passkey step is absent without passkey support`; `protected once either is done`.
  Stories: `Settings/Protect` — `0 of 2`, `1 of 2` (quiet list), `no PRF`; a play test:
  `"Save a recovery key" shows the key setup without asking for a current key`.
- [ ] **Step 2: Run** the unit file. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** unit and storybook for `apps/web`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(web): protect your data for an account without an email`.

### Task 10: Adding an email on the web

**Files:**
- Create: `app/features/settings/AddEmail.tsx`, `AddEmail.stories.tsx`, `add-email.ts`.
- Modify: `ProtectSection.tsx` (step 3 opens it in a `Takeover`), copy (`settings.add_email.*`),
  `apps/web/AGENTS.md`.
- Test: `app/features/settings/add-email.test.ts`.

**Interfaces:**
- Produces: `claimEmail(api): { send(email: string): Promise<void>; verify(email: string, code: string): Promise<void> }`
  over `/v1/me/claim-email/send|verify` (errors as `AuthErrorKey`s; `email_taken` its own key);
  `AddEmail({ claim, onDone })`: email, then `CodeInput`, then done (invalidates `queryKeys.me()`).

- [ ] **Step 1: Write the failing tests:** `send then verify posts the email and the code`;
  `409 email_taken maps to the phone-merge copy (ruling 5)`; `a wrong code maps to the existing code error`.
  Story play test: `email_taken reads "Open Wambito on your phone to bring this data into it"`.
- [ ] **Step 2: Run** the unit file. Expected: FAIL.
- [ ] **Step 3: Implement**, reusing `CodeInput` and the sign-in error copy.
- [ ] **Step 4: Run** unit and storybook for `apps/web`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(web): add an email to an account without one`.

### Task 11: The daily seen call and the admin numbers

**Files:**
- Create: `app/auth/seen.ts`.
- Modify: `app/routes/app.tsx` (loader calls `markSeenToday` without awaiting), `app/site/config.ts`
  (`BUILD_ID` from `VITE_BUILD_ID`, else `dev`), `deploy/personal/up.sh`
  (`VITE_BUILD_ID="$(git -C "$REPO_DIR" rev-parse --short HEAD)"` on the build line), `app/admin/HomeScreen.tsx`, `MetricCards.tsx`, new `app/admin/ActivityBlocks.tsx`,
  `Home.stories.tsx`, `app/i18n/messages/admin.{es,en}.json`, `apps/web/AGENTS.md`.
- Test: `app/auth/seen.test.ts`, the admin story.

**Interfaces:**
- Produces: `markSeenToday(userId: string, timeZone: string, deps?: { fetch?: typeof fetch; now?: () => Date }): Promise<void>`
  — once per local day (`wambito.seen.<userId>`), `POST /api/v2/me/seen` with
  `x-wambito-version: BUILD_ID`; stored only after a 204; never throws.

- [ ] **Step 1: Write the failing tests:** `the first load of a day posts once with x-wambito-version`;
  `a second load the same local day posts nothing`; `the next local day posts again (America/Bogota, across UTC midnight)`;
  `a failed post is tried again on the next load`. Admin story play test:
  `the cards say Without email / With email and the four blocks render from a seeded metrics fixture`.
- [ ] **Step 2: Run** `pnpm vitest run apps/web/app/auth/seen.test.ts`. Expected: FAIL.
- [ ] **Step 3: Implement**; the admin blocks per ruling 18.
- [ ] **Step 4: Run** unit and storybook for `apps/web`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(web): count the day the app is opened, and show it in the admin panel`
  (`up.sh` in the same commit).

### Task 12: The web e2e with the API flag on (ruling 2)

**Files:**
- Create: `apps/api/src/scripts/seed-e2e-plain-user.ts`, `apps/web/e2e/encrypted-sign-up.spec.ts`.
- Modify: `apps/api/package.json` (`seed:e2e-plain-user`), `docker-compose.yml` (the
  `NEW_USERS_ENCRYPTED` line, ruling 2), `.github/workflows/ci.yml` (`e2e` job:
  `NEW_USERS_ENCRYPTED: "true"` in its `env`), `apps/web/e2e/helpers.ts` (`signUpNewUser` seeds a
  plain user first; `seedPlainUser(email)`), the specs that need it if they bypass the helper,
  `apps/web/AGENTS.md` (Commands: `NEW_USERS_ENCRYPTED=true` on the e2e stack line; the seed),
  `apps/api/AGENTS.md` (the seed scripts line), root `AGENTS.md` (the CI `e2e` line).

**Interfaces:**
- Produces: `pnpm --filter @wambito/api seed:e2e-plain-user <email>` — inserts a user with that
  email, `emailVerified: true`, `encryption: 'plain'`, no onboarding, the default account and
  categories the plain sign-up gives (reuse the code `user.create.after` runs for a plain user);
  idempotent (an existing email is left as it is). `seedPlainUser(email: string): void` in
  `helpers.ts` (`docker compose exec -T api …`, like `reseed()`).

- [ ] **Step 1: Write the new spec** `encrypted-sign-up.spec.ts` (desktop): from the landing's
  "Create account", an email code, the recovery key (`setUpRecoveryKey`), "Install the app"
  (Task 8) with the Android button, "Continue", then the onboarding's welcome; `/v1/me` says
  `preview`.
- [ ] **Step 2: Run** the whole web e2e on a stack started with `NEW_USERS_ENCRYPTED=true`.
  Expected: FAIL (the plain specs land in the vault gate; no seed script).
- [ ] **Step 3: Implement** the seed, the helper, the compose and CI lines.
- [ ] **Step 4: Run** `pnpm vitest run apps/api` (the seed has no route; nothing else moves) and the
  whole `pnpm --filter @wambito/web e2e` on the flag-on stack. Expected: PASS.
- [ ] **Step 5: Commit** `test(web): run the web e2e with new users born encrypted`.

### Task 13: e2e — the phone approves, the recovery key, the unticked box

**Files:**
- Create: `apps/web/e2e/phone.ts` (the phone, in Node, over the API), `apps/web/e2e/signin.spec.ts`.
- Modify: `apps/web/e2e/helpers.ts` (export `apiContext(storageState?)` if needed),
  `apps/web/AGENTS.md` (Commands: the new spec).

**Interfaces:**
- Produces: `approveSignin(options: { request: APIRequestContext /* the account's session */; userId: string; code: string; recoveryKey: string }): Promise<void>`
  — `GET /v2/signin?code=` pins the commitment; `GET /v2/keys`, the recovery wrap opened with
  `parseRecoveryKey` + `unwrapDataKey` (`{ kind: "recovery", userId, keyV }`); an ephemeral `A`;
  `POST /approver`; polls `GET /v2/signin/{id}` until `publicKey`; checks it against the
  commitment; seals with `sealToDevice` (`{ kind: "device", userId, keyV }`); `POST /seal`.

- [ ] **Step 1: Write the specs** (desktop only, serial, `reseed()` in `beforeAll`, as `vault.spec.ts`):
  - `a browser signs in by the code the phone approves and sees the account's movement`:
    context B signs in `preview@wambito.test` by email, `setUpRecoveryKey`, adds a movement; context
    A opens `/sign-in`, reads the code, `approveSignin`; A lands on `/app` and shows the movement;
    the session cookie has an expiry ~60 days ahead;
  - `the recovery key signs in on a new browser`: context C, "Recovery key", the key from B in
    lower case with spaces; lands on `/app` with the movement;
  - **(Review Focus 4)** `unticked: the cookie has no expiry, and once it is gone the app leaves no vault`:
    context D unticks, is approved, lands on `/app`; the session cookie's `expires` is `-1`;
    `context.clearCookies()`; `goto("/sign-in")`; `indexedDB.databases()` lists no `wambito-vault-*`.
- [ ] **Step 2: Run** with the dev stack (pinned clock) and the seeded accounts:
  `pnpm --filter @wambito/web e2e -- e2e/signin.spec.ts`. Expected: PASS (the pieces exist; a
  failure here is a bug in Tasks 2–5, fixed there with a unit test first).
- [ ] **Step 3: Run** the whole `pnpm --filter @wambito/web e2e`. Expected: PASS.
- [ ] **Step 4: Commit** `test(web): the phone approves a web sign-in, end to end`.

### Task 14: Close-out

- [ ] **Step 1:** From the root: `pnpm lint && pnpm typecheck && pnpm test`, the generated-file
  checks CI runs for the web (`pnpm --filter @wambito/web tokens`, `api:types --file`, then
  `git diff --exit-code`), `scripts/check-old-name.sh`, the personal-name `git grep`. Expected: green,
  no diff.
- [ ] **Step 2:** Read `apps/web/AGENTS.md` once against the branch: every new module, route,
  stored key (`wambito.seen.<userId>`), meta key (`ephemeral`), flags (`NEW_USERS_ENCRYPTED` on the e2e stack,
  `VITE_BUILD_ID`) and story id is named once.
- [ ] **Step 3:** Whole-branch review (superpowers:requesting-code-review) against the spec sections
  in the header and the Review Focus list; one fix wave.
- [ ] **Step 4:** `git fetch && git diff HEAD...origin/main --stat` for new conflicts; then ask the
  founder before pushing and opening the PR (rulings and checks in its description).
