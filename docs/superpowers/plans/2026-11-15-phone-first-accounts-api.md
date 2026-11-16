# Phone-first accounts, delivery 1 (the API) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The server side of phone-first accounts, all behind `NEW_USERS_ENCRYPTED` (off by
default): users born `encrypted`, recovery-key sign-in, the `/v2/signin` web relay, 25-month phone
sessions, install and active counts with no IP stored, the 12/24-month cleanup, distinguishable
401s and the admin numbers. Nothing changes for a user created while the flag is off.

**Architecture:** New columns on Better Auth's `user` and `session` (declared as `additionalFields`,
regenerated with `auth:generate`), five new tables in `packages/db`, and new route families in
`apps/api`. Sessions created outside Better Auth's own endpoints (recovery sign-in, the QR pickup)
go through one server-only Better Auth endpoint, so the session hooks and Better Auth's cookie code
run as for any sign-in. `/v2/signin` shares the pairing relay's checks through a new
`services/relay.ts`; the tables and routes stay apart.

**Tech Stack:** Hono + `@hono/zod-openapi`, Better Auth 1.7.11 (`anonymous`, `bearer`, internal
adapter), Drizzle + drizzle-kit, Postgres testcontainers, Vitest, WebCrypto (`@wambito/crypto`),
Dart `cryptography` for the port.

**Spec:** `docs/superpowers/specs/2026-11-15-phone-first-accounts-design.md`, section 16 item 1
(sections 6, 7.2's builder note, 8.1, 8.2, 9, 10 and 11). Read it with
`docs/superpowers/specs/2026-11-08-e2e-stage-1b-design.md` section 1 (the relay checks).

## Global Constraints

- **Branch and PR:** one branch from `main`, one PR. Merging to `main` deploys: merge only on the
  founder's yes.
- **The switch:** `NEW_USERS_ENCRYPTED` defaults to off. With it off a new user is `plain`, and every
  existing test stays green unchanged except the ones this plan rewrites on purpose (each named in
  its task). The new cleanup tiers, the 25-month sessions and the 401 codes apply only to
  `encrypted` users (spec §11).
- **Exact values from the spec:**
  - HKDF-SHA256, empty salt: `wambito/v1/recovery/lookup` → 16 bytes, `wambito/v1/recovery/auth` →
    32 bytes; `lookup_hash` and `auth_hash` are SHA-256 of those bytes;
  - sign-in request lifetime **2 minutes**; at most **5** open requests per IP; code 8 characters
    (`pairingCode`);
  - commitment `SHA-256("wambito/v1/pairing-commit" || N.pub)` (`pairingCommitment`);
  - session lifetimes: standard **60 days** sliding, renewed at most once a day (today's
    `auth.ts`); phone session of an encrypted user without an email **25 months**; unticked web
    session **12 hours**, cookie without `Max-Age`;
  - cleanup of encrypted users without an email: no verifier and no passkey wrap, idle
    **12 months**; otherwise idle **24 months**; `plain` guests stay on **60 days**;
  - `ended_sessions` rows purged after **90 days**;
  - error codes: 401 `recovery_key_invalid`, `device_removed`, `user_deleted`, `unauthenticated`;
    409 `already_set`; 403 for assistant tokens on every `/v2/signin` route.
- **Months in code:** 12 months = 365 days, 24 months = 730 days, 25 months = 760 days (longer than
  the 730-day cleanup, as the spec requires).
- **No IP stored:** not on sessions, not in the database's rate-limit rows; IPs live only in
  process memory (spec §9).
- **Headers** are read only through `clientHeader` (`src/http/client-headers.ts`); new names
  `version` (`x-wambito-version`) and `poll` (`x-wambito-poll`).
- **Opaque bytes** (commitments, keys, sealed blobs, verifier hashes) are never logged or read.
- **Repo rules:** tests first; English; fixtures invented; money untouched; never read a `.env`.
  Commits `feat(api): …` / `feat(crypto): …`, a lowercase sentence, staged by path, never a
  `Co-Authored-By` line.
- **Every task that changes a route, a response or a schema**, in the same commit:
  - adds its lines under `## Unreleased` in the root `CHANGELOG.md` (Added / Changed);
  - regenerates `apps/web/app/api/schema.d.ts` (`pnpm --filter @wambito/web api:types --file`),
    `apps/mcp/src/api/schema.d.ts` (`pnpm --filter @wambito/mcp api:types`) and
    `apps/mobile/lib/api/gen` (`apps/mobile/scripts/gen-api.sh`), never by hand;
  - updates the bullet of `apps/api/AGENTS.md` (and `packages/db/AGENTS.md` for a migration) that
    describes what it changed.
- **Schema changes:** `user`/`session` columns are Better Auth `additionalFields` in `src/auth.ts`,
  then `pnpm --filter @wambito/api auth:generate` rewrites `packages/db/src/schema/auth.ts`; other
  tables go in `packages/db/src/schema/domain.ts`; then
  `pnpm --filter @wambito/db generate --name <name>` writes the next `drizzle/00NN_<name>.sql`
  (0013 onward). Data statements go in a `--custom` migration.
- **Commands:** `pnpm vitest run apps/api/test/<file>` (Docker running, or `WAMBITO_TEST_DB=local`);
  `pnpm vitest run --project @wambito/crypto`; Dart from `apps/mobile` with
  `export PATH="$HOME/development/flutter/bin:$PATH"`: `flutter test test/crypto`.

## Decisions (where the spec leaves the choice, or the code forces one)

1. `ended_sessions.session_hash` is SHA-256 of the session **token**, not its id: a 401 only has the
   token (bearer, or the cookie value before its `.signature`).
2. `deleted_users` rows are kept (one 32-byte hash, no other data); the spec purges only
   `ended_sessions`. A phone may return long after its user was deleted.
3. Hashes (`lookup_hash`, `auth_hash`, `poll_hash`, `session_hash`, `user_hash`) are `bytea` of
   32 bytes, checked by a CHECK, as the other end-to-end tables store bytes.
4. `recovery_verifiers`, `signin_requests`, `activity_daily`, `ended_sessions` and `deleted_users`
   have no row-level security: each is read before the user is known (or has no user), like
   `session` and `passkey`. Every statement filters on the user id, the lookup hash or the request
   id. `packages/db/AGENTS.md` says so.
5. Rate limits move to memory: Better Auth's `rateLimit.storage` becomes `"memory"`, and our own
   per-IP limits use `src/http/ip-limit.ts`. A migration empties `rate_limit` and nulls
   `session.ip_address`. Better Auth's `disableIpTracking` is **not** used: it also turns off its
   per-IP rate limits (`rate-limiter/index.mjs`); the session hook drops the IP instead.
6. The open-request count per IP (max 5) is kept in memory, never on the row.
7. Session lifetime lives on the session row: `session.lifetime` `standard` | `long` | `short`.
   A `long` session is never inside Better Auth's refresh window (it starts 59 days before the
   expiry), so `requireUser` slides it itself, at most once a day, and stamps activity (the "two
   clocks" rule). A `short` session gets Better Auth's signed `dont_remember` cookie, so it is never
   refreshed and its cookie never gets a `Max-Age`.
8. Sessions made by our routes go through a server-only Better Auth endpoint
   (`metadata: { SERVER_ONLY: true }`, which `better-call`'s router skips), called with
   `auth.api.createServerSession({ body, headers, returnHeaders: true })`; the route copies its
   `set-cookie` and `set-auth-token` headers.
9. `disableDeleteAnonymousUser: true` is already set (`auth.ts`); this plan only pins it with a test.
   The claim's 409 `email_taken` already exists; also pinned.
10. A recovery wrap `PUT` that replaces a stored recovery wrap with different `wrapped` bytes deletes
    the verifier in the same transaction ("verifier deleted with the wrap"); a retry of the same
    PUT and a rotation keep it.
11. `PUT /v2/recovery/verifier` needs a recovery wrap (409 `recovery_required`); a `lookup_hash`
    already used by another user is 409 `verifier_taken`.
12. `user.platform` is `android` or `ios` when `x-wambito-client` says so, else `web`; `null` for
    users made before this delivery. The `activity_daily.platform` of a seen call is the same
    reading of that call's header.
13. `user.last_seen_day` is text `YYYY-MM-DD` (a Better Auth `string` field: `auth:generate` owns the
    table); `activity_daily.day` and `cohort_week` are SQL `date`; `cohort_week` is the Monday (UTC)
    of the user's `created_at`.
14. Cohort retention for week N is the cohort's highest daily active count during days
    `7N … 7N+6` after its cohort week: the aggregate keeps no per-user rows, so distinct weekly
    users cannot be counted; the panel shows it as "at least".
15. Admin metrics are additive: `guests` and `weekly[].guests` keep their names and mean "without
    email" (the panel's labels change in the web delivery); new fields carry the new numbers.
16. `GUEST_SIGNUP` keeps its name (spec §10, builder's call).
17. The flag stays off in the root `docker-compose.yml` and CI in this delivery: turning it on there
    makes every web e2e sign-up `encrypted`; it is turned on with the web delivery, which updates
    those specs. `.env.example` documents it.
18. Rate-limit numbers: recovery sign-in 10 per 10 minutes per IP; opening sign-in requests 30 per
    10 minutes per IP (a visible page renews one every 2 minutes); the email-change confirm keeps
    `CONFIRM_LIMIT` (10 per 10 minutes).

## Review Focus

1. **A long phone session used every day without `/v2/me/seen`** (the F-Droid build that skips it):
   Better Auth never refreshes a 25-month session, so without our slide neither clock moves and
   the cleanup deletes a person who uses the app daily. Expected: kept. Pinned in Task 4.
2. **Two pickups of the same sealed sign-in request at once** (a double click, a retried fetch):
   exactly one gets a session; the other gets 404. Pinned in Task 6.
3. **A replaced recovery key:** after the person makes a new key, the old key must not sign in
   (it would land in an account it cannot open); a rotation must not break the current key's
   sign-in. Pinned in Task 5.
4. **The day boundary in the person's time zone:** two seen calls in one local day that straddle
   UTC midnight count once; moving the phone to a zone where "today" is earlier neither counts
   again nor moves `last_seen_day` back. Pinned in Task 7.
5. **An unticked web sign-in, used after 13 hours, or refreshed by a request:** it must be a 401,
   and no response may ever give its cookie a `Max-Age`. Pinned in Task 6.

---

### Task 1: Recovery verifier derivation (`packages/crypto` and the Dart port)

**Files:**
- Modify: `packages/crypto/src/recovery.ts`, `packages/crypto/src/index.ts`,
  `packages/crypto/scripts/gen-vectors.ts`, `packages/crypto/test-vectors.json` (regenerated),
  `packages/crypto/AGENTS.md`;
  `apps/mobile/lib/crypto/keys.dart`, `apps/mobile/lib/crypto/recovery.dart`,
  `apps/mobile/lib/crypto/crypto.dart`.
- Test: `packages/crypto/test/recovery.test.ts`, `packages/crypto/test/vectors.test.ts`,
  `apps/mobile/test/crypto/recovery_test.dart`, `apps/mobile/test/crypto/vectors_test.dart`.

**Interfaces:**
- Produces (TS, `@wambito/crypto`):
  - `RECOVERY_LOOKUP_INFO = "wambito/v1/recovery/lookup"`, `RECOVERY_AUTH_INFO = "wambito/v1/recovery/auth"`;
  - `interface RecoveryVerifier { lookup: Uint8Array /* 16 */; auth: Uint8Array /* 32 */ }`;
  - `recoveryVerifier(secret: Uint8Array): Promise<RecoveryVerifier>` (16-byte secret, else
    `CryptoError("bad_input")`);
  - `verifierHash(bytes: Uint8Array): Promise<Uint8Array>` (SHA-256).
- Produces (Dart, `lib/crypto`): `Future<Uint8List> hkdfBytes(Uint8List secret, String info, int length)`
  in `keys.dart` (32-zero-byte salt, slinqer/wambito#65; `hkdfKey` uses the same salt constant);
  `class RecoveryVerifier { final Uint8List lookup; final Uint8List auth; }`,
  `Future<RecoveryVerifier> recoveryVerifier(Uint8List secret)`,
  `Future<Uint8List> verifierHash(Uint8List bytes)` in `recovery.dart`.
- Vectors: new section `recoveryVerifiers: [{ secret, lookup, auth, lookupHash, authHash }]`
  (base64url) over the four secrets of the `recovery` section; one new `rejects` entry
  `{ name: "recovery verifier of a 15-byte secret", op: "recoveryVerifier", secret, code: "bad_input" }`.

- [ ] **Step 1: Write the failing TS tests.** In `recovery.test.ts`:
  `recoveryVerifier gives 16 and 32 bytes, deterministic, and neither equals the recovery wrap key`
  (lengths 16 and 32; two calls equal; `auth` differs from HKDF info `wambito/v1/wrap/recovery`
  output and `lookup` differs from the first 16 bytes of `auth`); `a secret that is not 16 bytes is
  bad_input`. In `vectors.test.ts`: `recoveryVerifiers: lookup, auth and both hashes are exact`, and
  the shape test asserts `vectors.recoveryVerifiers.length === 4`.
- [ ] **Step 2: Run** `pnpm vitest run --project @wambito/crypto`. Expected: FAIL (`recoveryVerifier`
  not exported; `recoveryVerifiers` undefined).
- [ ] **Step 3: Implement** `recoveryVerifier` and `verifierHash` in `src/recovery.ts` with
  `subtle.deriveBits` (HKDF, empty salt, the two infos; 128 and 256 bits) and `subtle.digest`;
  export them; extend `gen-vectors.ts`; run `pnpm --filter @wambito/crypto vectors`.
- [ ] **Step 4: Run** `pnpm vitest run --project @wambito/crypto` and
  `pnpm --filter @wambito/crypto vectors && git diff --exit-code packages/crypto/test-vectors.json`
  (a second run is clean). Expected: PASS, no diff.
- [ ] **Step 5: Write the failing Dart tests.** `recovery_test.dart` ports the two TS cases;
  `vectors_test.dart` adds `recoveryVerifiers: lookup, auth and both hashes are exact` and handles
  the `recoveryVerifier` reject op; the shape test expects 4 entries.
- [ ] **Step 6: Run** `flutter test test/crypto`. Expected: FAIL (no `recoveryVerifier`).
- [ ] **Step 7: Implement** `hkdfBytes` (refactor `hkdfKey` onto the shared `_zeroSalt`),
  `recoveryVerifier`, `verifierHash`; export from `crypto.dart`.
- [ ] **Step 8: Run** `flutter test test/crypto` and `flutter analyze`. Expected: PASS, no issues.
- [ ] **Step 9: Update `packages/crypto/AGENTS.md`** (`src/recovery.ts` bullet: the two infos and
  the hashes) **and commit.**
  ```bash
  git add packages/crypto/src/recovery.ts packages/crypto/src/index.ts packages/crypto/scripts/gen-vectors.ts packages/crypto/test-vectors.json packages/crypto/test/recovery.test.ts packages/crypto/test/vectors.test.ts packages/crypto/AGENTS.md apps/mobile/lib/crypto/keys.dart apps/mobile/lib/crypto/recovery.dart apps/mobile/lib/crypto/crypto.dart apps/mobile/test/crypto/recovery_test.dart apps/mobile/test/crypto/vectors_test.dart
  git commit -m "feat(crypto): recovery key lookup and auth derivation"
  ```

### Task 2: The switch: `NEW_USERS_ENCRYPTED`, `user.encryption`, `user.platform`

**Files:**
- Modify: `apps/api/src/config.ts`, `apps/api/src/auth.ts` (user `additionalFields`, `user.create`
  hooks), `apps/api/src/http/preview.ts`, `apps/api/src/routes/me.ts`,
  `apps/api/src/http/client-headers.ts`, `packages/db/src/schema/auth.ts` (generated),
  `.env.example`, `apps/api/test/harness.ts` (`TEST_CONFIG.NEW_USERS_ENCRYPTED: false`).
- Create: `apps/api/src/services/encryption.ts`, migration `packages/db/drizzle/0013_user_encryption.sql`
  (+ meta).
- Test: `apps/api/test/switch.test.ts`, `apps/api/test/config.test.ts`.

**Interfaces:**
- Produces:
  - `config.NEW_USERS_ENCRYPTED: boolean` (default `false`; `"true"`/`"false"`, blank = default, the
    `GUEST_SIGNUP` parsing);
  - `type Encryption = "plain" | "encrypted"` and
    `accountEncryption(db: Db, userId: string): Promise<Encryption>` in `services/encryption.ts`;
  - `isPreviewAccount(config: Pick<Config, "E2E_PREVIEW_USER_IDS">, user: { id: string; encryption: Encryption }): boolean`
    (allowlist **or** `encrypted`) — replaces the `(config, userId)` signature at its four callers;
  - `user.encryption` text not null default `'plain'`, CHECK in (`plain`, `encrypted`);
    `user.platform` text null, CHECK in (`android`, `ios`, `web`); Drizzle fields `encryption`,
    `platform`;
  - `platformOf(headers: Headers | undefined): "android" | "ios" | "web"` and `CLIENT_IOS = "ios"`
    in `auth.ts`.

- [ ] **Step 1: Write the failing tests** in `switch.test.ts`, two apps (`createTestApp({})` and
  `createTestApp({ NEW_USERS_ENCRYPTED: true })`):
  - `flag off: a new guest and a new email user are plain, /v1/me says plain, and get the default account and categories`;
  - `flag on: a new guest is encrypted, /v1/me says preview, and has no accounts or categories rows`;
  - `flag on: a new email user is encrypted and its /v1 finance routes answer 403 encrypted_account`;
  - `flag on: a user created before the flag stays plain` (insert through `t.admin` with no
    `encryption`, read `/v1/me` → `plain`);
  - `platform: x-wambito-client android → android, ios → ios, none or other → web`.
  In `config.test.ts`: `NEW_USERS_ENCRYPTED defaults to false, reads "true", refuses "yes"`.
- [ ] **Step 2: Run** `pnpm vitest run apps/api/test/switch.test.ts apps/api/test/config.test.ts`.
  Expected: FAIL (unknown config key; `encryption` column missing).
- [ ] **Step 3: Implement.** Config key; `additionalFields.encryption` (`input: false`,
  `defaultValue: "plain"`) and `platform` (`input: false`, `required: false`); `user.create.before`
  sets `encryption` from the flag and `platform` from `platformOf`; `user.create.after` reads
  `created.encryption` for `isPreviewAccount`; `previewOnlyV2` and `routes/me.ts` read
  `accountEncryption`. Run `auth:generate`, then `pnpm --filter @wambito/db generate --name user_encryption`
  and add the two CHECKs to the generated SQL. `.env.example`: a commented `# NEW_USERS_ENCRYPTED=false`
  with one line on what it does.
- [ ] **Step 4: Run** `pnpm vitest run apps/api` (the whole API suite: `preview.test.ts` and
  `guests.test.ts` must pass unchanged) and `pnpm typecheck`. Expected: PASS.
- [ ] **Step 5: CHANGELOG** (Added: `NEW_USERS_ENCRYPTED`; `GET /v1/me` `encryption: "preview"`
  also for users created while it is on), AGENTS bullet ("End-to-end encryption preview"),
  `packages/db/AGENTS.md` (0013), regenerate the clients. **Commit:**
  ```bash
  git add apps/api/src/config.ts apps/api/src/auth.ts apps/api/src/http/preview.ts apps/api/src/routes/me.ts apps/api/src/http/client-headers.ts apps/api/src/services/encryption.ts apps/api/test/switch.test.ts apps/api/test/config.test.ts apps/api/test/harness.ts packages/db/src/schema/auth.ts packages/db/drizzle .env.example CHANGELOG.md apps/api/AGENTS.md packages/db/AGENTS.md apps/web/app/api/schema.d.ts apps/mcp/src/api/schema.d.ts apps/mobile/lib/api/gen
  git commit -m "feat(api): users born encrypted behind new_users_encrypted"
  ```

### Task 3: No IP stored (sessions and rate limits)

**Files:**
- Modify: `apps/api/src/auth.ts` (`rateLimit.storage: "memory"`; `session.create.before` drops
  `ipAddress`), `apps/api/src/routes/email-change.ts` (its DB limiter → `IpWindowLimit`),
  `apps/api/test/email-change.test.ts` (the `t.admin.delete(rateLimit)` reset becomes a fresh app or
  the limiter's reset).
- Create: `apps/api/src/http/ip-limit.ts`, custom migration
  `packages/db/drizzle/0014_forget_ips.sql` (`DELETE FROM "rate_limit"; UPDATE "session" SET "ip_address" = NULL;`).
- Test: `apps/api/test/no-ip.test.ts`, `apps/api/test/ip-limit.test.ts`.

**Interfaces:**
- Produces (`src/http/ip-limit.ts`, in-memory, one instance per app):
  - `class IpWindowLimit { constructor(limit: { max: number; windowMs: number }); hit(ip: string | null, now: number): boolean }`
    — counts one request, returns true when over the limit; a null IP shares one bucket (today's rule);
  - `class IpOpenCount { constructor(max: number); tryOpen(ip: string | null, id: string, expiresAt: number, now: number): boolean; close(id: string): void }`
    — false when the IP already holds `max` unexpired ids.

- [ ] **Step 1: Write the failing tests.** `no-ip.test.ts`:
  - `a session created by email sign-in or guest sign-up, and then refreshed, stores no ip_address`
    (`session.ipAddress` is null or `""` for every row; assert `expect(row.ipAddress ?? "").toBe("")`);
  - `after sign-ins from several addresses the rate_limit table holds no row`;
  - `Better Auth still rate-limits per address: 31 guest sign-ups from one IP in a minute, the 31st is 429`
    (fixed `x-forwarded-for: 198.51.100.7, 10.0.0.1`; today's `max: 30`, `window: 60`);
  - `the email-change confirm still answers 429 on the 11th try from one address`.
  `ip-limit.test.ts`: window opens, counts, resets after `windowMs`; `IpOpenCount` refuses the 6th
  open, accepts again once one expires or is closed.
- [ ] **Step 2: Run** `pnpm vitest run apps/api/test/no-ip.test.ts apps/api/test/ip-limit.test.ts`.
  Expected: FAIL (`ip_address` stored; `rate_limit` rows present; no `ip-limit.ts`).
- [ ] **Step 3: Implement** `ip-limit.ts`; the auth changes; email-change on `IpWindowLimit`
  (`CONFIRM_LIMIT` unchanged, still `retry-after`); the custom migration
  (`pnpm --filter @wambito/db generate --custom --name forget_ips`).
- [ ] **Step 4: Run** `pnpm vitest run apps/api`. Expected: PASS. Confirm with
  `git grep -n "ipAddress\|ip_address" apps/api/src apps/web/app apps/mobile/lib -- ':!*schema.d.ts' ':!apps/mobile/lib/api/gen'`
  that nothing reads the session's IP (spec §9 asks the plan to check: only `auth.ts`'s
  `advanced.ipAddress` header settings appear).
- [ ] **Step 5: CHANGELOG** (Changed: sessions store no IP address; rate limits are kept in memory),
  `apps/api/AGENTS.md` (the email-change bullet, the Traps line on rate limits),
  `packages/db/AGENTS.md` (0014). **Commit:**
  ```bash
  git add apps/api/src/auth.ts apps/api/src/http/ip-limit.ts apps/api/src/routes/email-change.ts apps/api/test/no-ip.test.ts apps/api/test/ip-limit.test.ts apps/api/test/email-change.test.ts packages/db/drizzle CHANGELOG.md apps/api/AGENTS.md packages/db/AGENTS.md
  git commit -m "feat(api): store no ip address on sessions or rate limits"
  ```

### Task 4: Two clocks and session lifetimes

**Files:**
- Modify: `apps/api/src/services/guest-cleanup.ts` (`stampGuestActivity` → `stampActivity`, every
  user), `apps/api/src/auth.ts` (session `additionalFields.lifetime`; `session.create.before` sets
  `lifetime` and `expiresAt`; export the lifetime constants), `apps/api/src/http/session.ts`
  (slide `long` sessions), `apps/api/src/routes/me.ts` (claim → back to standard),
  `packages/db/src/schema/auth.ts` (generated), `apps/api/test/guest-cleanup.test.ts` (the test
  `an email user is never stamped` becomes `an email user is stamped too`: spec §9, now every user).
- Create: `apps/api/src/services/sessions.ts`, migration `0015_session_lifetime.sql`.
- Test: `apps/api/test/session-lifetime.test.ts`, `apps/api/test/claim-email.test.ts`,
  `apps/api/test/guests.test.ts`.

**Interfaces:**
- Consumes: `accountEncryption`, `platformOf` (Task 2).
- Produces:
  - `session.lifetime` text not null default `'standard'`, CHECK in (`standard`, `long`, `short`);
  - in `auth.ts`: `SESSION_SECONDS = 60 * 24 * 60 * 60`, `LONG_SESSION_SECONDS = 760 * 24 * 60 * 60`,
    `SHORT_SESSION_SECONDS = 12 * 60 * 60`;
  - in `services/sessions.ts`:
    - `type SessionLifetime = "standard" | "long" | "short"`;
    - `lifetimeFor(user: { encryption: Encryption; isAnonymous: boolean }, client: "android" | "ios" | "web"): SessionLifetime`
      — `long` iff `encrypted`, anonymous and a phone client; else `standard`;
    - `slideLongSession(db: Db, sessionId: string, userId: string, now: Date): Promise<void>` —
      one `update session set updated_at = now, expires_at = now + 760 days where id = … and lifetime = 'long' and updated_at < now - 1 day`,
      and `stampActivity` when it moved;
    - `endLongSessions(db: Db, userId: string, now: Date): Promise<void>` — `lifetime = 'standard'`,
      `expires_at = least(expires_at, now + 60 days)` for the user's `long` sessions;
  - `stampActivity(db: Db, userId: string, at: Date): Promise<void>` (the old body without
    `and is_anonymous`); every caller renamed.

- [ ] **Step 1: Write the failing tests.** `session-lifetime.test.ts` on
  `createTestApp({ NEW_USERS_ENCRYPTED: true })` plus one flag-off app:
  - `an encrypted guest signing up from the phone (x-wambito-client: android) gets a 760-day long session`;
  - `the same from ios too; from no client header (web) a 60-day standard one`;
  - `an email user's phone session stays 60 days`; `a plain guest's phone session stays 60 days (flag off)`;
  - **(Review Focus 1)** `a long session used daily is slid once a day and keeps the user from the cleanup`:
    set the session's `updated_at` and `last_active_at` to 400 days ago and `expires_at` 360 days
    ahead; `GET /v1/me` → 200; then `updated_at` ≈ now, `expires_at` ≈ now + 760 days,
    `user.last_active_at` ≈ now; a second request the same day changes neither;
  - `a background request (x-wambito-background: 1) never slides a long session`.
  `claim-email.test.ts` (flag-on app):
  - `an encrypted guest claims an email in place: same id, encryption stays encrypted, /v1/me preview`;
  - `claiming brings the phone's long session back to 60 days` (`lifetime` `standard`,
    `expires_at` ≤ now + 60 days);
  - `an email that already has an account answers 409 email_taken and the guest is unchanged` (pin
    for the merge; flag on).
  `guests.test.ts`: `an encrypted guest that signs in with an existing email keeps its own user`
  (sign up anonymous, then email OTP sign-in with the guest's bearer: the anonymous `user` row still
  exists — pins `disableDeleteAnonymousUser`).
- [ ] **Step 2: Run** `pnpm vitest run apps/api/test/session-lifetime.test.ts apps/api/test/claim-email.test.ts apps/api/test/guests.test.ts apps/api/test/guest-cleanup.test.ts`.
  Expected: FAIL (no `lifetime` column; sessions are 60 days; the rewritten stamp test fails).
- [ ] **Step 3: Implement.** `additionalFields.lifetime` (`input: false`, default `standard`);
  `session.create.before`: keep a given `lifetime` (Task 5's endpoint passes one), else read the
  user (`encryption`, `isAnonymous`) and `platformOf(ctx headers)` and call `lifetimeFor`; set
  `expiresAt` = now + `LONG_SESSION_SECONDS` or `SHORT_SESSION_SECONDS` for those two; leave
  `standard` to Better Auth. `requireUser` calls `slideLongSession` for a session grant whose
  `result.session.lifetime === "long"` and that is not a background request. The claim's verify
  calls `endLongSessions` after the update. Run `auth:generate`, `generate --name session_lifetime`,
  add the CHECK.
- [ ] **Step 4: Run** `pnpm vitest run apps/api`. Expected: PASS.
- [ ] **Step 5: CHANGELOG** (Changed: an encrypted user without an email gets a 25-month session on
  the phone, back to 60 days when an email is added; every user's activity is stamped), AGENTS
  (`src/auth.ts` sessions, the client-headers paragraph), `packages/db/AGENTS.md` (0015).
  **Commit:**
  ```bash
  git add apps/api/src/services/guest-cleanup.ts apps/api/src/services/sessions.ts apps/api/src/auth.ts apps/api/src/http/session.ts apps/api/src/routes/me.ts apps/api/test/session-lifetime.test.ts apps/api/test/claim-email.test.ts apps/api/test/guests.test.ts apps/api/test/guest-cleanup.test.ts packages/db/src/schema/auth.ts packages/db/drizzle CHANGELOG.md apps/api/AGENTS.md packages/db/AGENTS.md
  git commit -m "feat(api): 25-month phone sessions and activity for every user"
  ```

### Task 5: Recovery verifier and recovery-key sign-in

**Files:**
- Create: `apps/api/src/auth-sessions.ts` (the server-only endpoint plugin),
  `apps/api/src/http/sign-in-response.ts`, `apps/api/src/services/recovery.ts`,
  `apps/api/src/routes/recovery.ts`, migration `0016_recovery_verifiers.sql`.
- Modify: `apps/api/src/auth.ts` (add the plugin), `apps/api/src/app.ts` (public sign-in route
  before `requireUser`; verifier route after), `apps/api/src/services/keys.ts` (`putKeyWrap`
  deletes the verifier on a replaced recovery wrap), `apps/api/src/http/schemas.ts`,
  `packages/db/src/schema/domain.ts`.
- Test: `apps/api/test/recovery.test.ts`.

**Interfaces:**
- Consumes: `recoveryVerifier`, `verifierHash` (Task 1, in tests); `lifetimeFor`, `SessionLifetime`
  (Task 4); `IpWindowLimit` (Task 3); `clientIp` (`http/client-ip.ts`).
- Produces:
  - table `recovery_verifiers` (`user_id` text pk → `user.id` on delete cascade, `lookup_hash`
    bytea unique, `auth_hash` bytea, both CHECK length 32, `created_at` timestamptz default now);
    Drizzle `recoveryVerifiers`;
  - plugin `wambitoSessions()` with endpoint `createServerSession` (`POST /wambito/server-session`,
    `metadata: { SERVER_ONLY: true }`, body `{ userId: string; lifetime: SessionLifetime }`): creates
    the session through `ctx.context.internalAdapter.createSession(userId, lifetime === "short", { lifetime }, true)`
    and calls Better Auth's `setSessionCookie(ctx, { session, user }, lifetime === "short")`;
  - `signInAs(auth: Auth, c: Context, userId: string, lifetime: SessionLifetime): Promise<void>` in
    `http/sign-in-response.ts`: calls the endpoint with the request's headers and
    `returnHeaders: true`, copies every `set-cookie` and the `set-auth-token` header onto `c`;
  - `putVerifier(db: Db, userId: string, lookupHash: Uint8Array, authHash: Uint8Array): Promise<void>`
    and `findVerifiedUser(db: Db, lookup: Uint8Array, auth: Uint8Array): Promise<string | null>`
    (hashes both, `timingSafeEqual` on `auth_hash`) in `services/recovery.ts`;
  - routes: `PUT /v2/recovery/verifier` (`putRecoveryVerifier`, body `{ lookupHash, authHash }`,
    base64url of 32 bytes, 204); `POST /v2/recovery/sign-in` (`recoverySignIn`, body
    `{ lookup /* 16 bytes */, auth /* 32 bytes */ }`, 200 `{ userId }` plus the session headers);
  - `RECOVERY_SIGNIN_LIMIT = { max: 10, windowMs: 10 * 60 * 1000 }`.

- [ ] **Step 1: Write the failing tests** in `recovery.test.ts` (flag-on app, real
  `recoveryVerifier` from `@wambito/crypto`):
  - `a verifier is stored, and the key signs in: 200 { userId }, a set-auth-token that opens GET /v2/keys, and a cookie that opens GET /v1/me`;
  - `wrong auth and unknown lookup give the same 401 recovery_key_invalid, byte for byte`;
  - `the 11th sign-in from one address in 10 minutes is 429 with retry-after`;
  - `from the phone (x-wambito-client: android) an encrypted user without email gets a long session; from the web a standard one`;
  - `a suspended account gets 403 account_suspended and no session`;
  - `PUT /v2/recovery/verifier without a recovery wrap is 409 recovery_required`;
  - `a second PUT replaces the verifier: the old key no longer signs in`;
  - `a lookup hash another user holds is 409 verifier_taken`;
  - **(Review Focus 3)** `replacing the recovery wrap with new bytes deletes the verifier; a retry of the same PUT and a rotation keep it`;
  - `deleting the user deletes its verifier` (cascade);
  - `an assistant token gets 403 on PUT /v2/recovery/verifier`.
- [ ] **Step 2: Run** `pnpm vitest run apps/api/test/recovery.test.ts`. Expected: FAIL (404 on the
  routes).
- [ ] **Step 3: Implement** the table (`generate --name recovery_verifiers`, no RLS, decision 4),
  the plugin and `signInAs`, the service, the routes and the `putKeyWrap` rule (decision 10). The
  sign-in route checks the limit first, then `findVerifiedUser`, then
  `signInAs(auth, c, userId, lifetimeFor(user, platformOf(headers)))`.
- [ ] **Step 4: Run** `pnpm vitest run apps/api`. Expected: PASS.
- [ ] **Step 5: CHANGELOG** (Added: the two routes, their errors; Changed: replacing the recovery
  wrap deletes the verifier), AGENTS (a `/v2/recovery` bullet, the server-only endpoint),
  `packages/db/AGENTS.md` (0016, no RLS), regenerate the clients. **Commit:**
  ```bash
  git add apps/api/src/auth-sessions.ts apps/api/src/http/sign-in-response.ts apps/api/src/services/recovery.ts apps/api/src/routes/recovery.ts apps/api/src/auth.ts apps/api/src/app.ts apps/api/src/services/keys.ts apps/api/src/http/schemas.ts apps/api/test/recovery.test.ts packages/db/src/schema/domain.ts packages/db/drizzle CHANGELOG.md apps/api/AGENTS.md packages/db/AGENTS.md apps/web/app/api/schema.d.ts apps/mcp/src/api/schema.d.ts apps/mobile/lib/api/gen
  git commit -m "feat(api): recovery key sign-in"
  ```

### Task 6: The `/v2/signin` web sign-in relay

**Files:**
- Create: `apps/api/src/services/relay.ts`, `apps/api/src/services/signin.ts`,
  `apps/api/src/routes/signin.ts`, migration `0017_signin_requests.sql`.
- Modify: `apps/api/src/services/pairing.ts` (uses `relay.ts`; behaviour unchanged),
  `apps/api/src/services/sync.ts` (`scheduleTombstonePurge` also runs `purgeExpiredSignins`),
  `apps/api/src/app.ts` (mount `signinRoutes(deps, auth)` before `app.use("/v2/*", requireUser)`),
  `apps/api/src/http/schemas.ts`, `apps/api/src/http/client-headers.ts` (`poll`),
  `packages/db/src/schema/domain.ts`.
- Test: `apps/api/test/signin.test.ts`; `apps/api/test/pairing.test.ts` must pass unchanged.

**Interfaces:**
- Consumes: `signInAs` (Task 5), `IpWindowLimit`, `IpOpenCount` (Task 3), `currentKeyV`
  (`services/keys.ts`), `pairingCode`, `pairingCommitment` (`@wambito/crypto`), `requireUser`.
- Produces:
  - `services/relay.ts` (pure, shared with pairing):
    - `interface RelayRow { commitment: Buffer; approverKey: Buffer | null; publicKey: Buffer | null; sealed: Buffer | null; keyV: number | null }`;
    - `assertCanSetApprover(row: RelayRow): void` (409 `already_set`);
    - `assertCanReveal(row: RelayRow, keyHash: Buffer): void` (409 `not_ready` / `already_set`, 422
      `commitment_mismatch`);
    - `assertCanSeal(row: RelayRow, blob: Buffer, keyV: number, current: number | null): void`
      (409 `already_sealed` / `not_ready` / `key_version_mismatch`, 422 `approver_mismatch`);
    - `normalizeRelayCode(input: string): string` (`normalizePairingCode` re-exports it);
  - table `signin_requests`: `id` uuid pk, `code` text unique, `commitment` bytea(32), `poll_hash`
    bytea(32), `label` text (1–64), `remember` boolean, `user_id` text null → `user.id` on delete
    cascade, `approver_key`, `public_key` (32 each), `key_v` smallint, `sealed` bytea,
    `expires_at` timestamptz; no RLS; Drizzle `signinRequests`;
  - `SIGNIN_TTL_MS = 2 * 60 * 1000`, `MAX_OPEN_SIGNINS_PER_IP = 5`,
    `SIGNIN_OPEN_LIMIT = { max: 30, windowMs: 10 * 60 * 1000 }`;
  - service (all take `now: Date`): `startSignin(db, { commitment, remember, label }, now): Promise<{ id; code; pollSecret; expiresAt }>`
    (32 random bytes, base64url, stored as SHA-256); `findSignin(db, code, now)`;
    `viewSignin(db, userId, id, now)`; `setSigninApprover(db, userId, id, publicKey, now)` (binds
    `user_id`); `pollSignin(db, id, pollSecret, now): Promise<{ approverKey: string | null; ready: boolean; expiresAt: string }>`;
    `revealSignin(db, id, pollSecret, publicKey, now)`; `sealSignin(db, userId, id, sealed, keyV, now)`;
    `takeSignin(db, id, pollSecret, now): Promise<{ sealed: string; keyV: number; userId: string; remember: boolean }>`
    (`delete … returning`, sealed only, 409 `not_ready` otherwise); `purgeExpiredSignins(db, now): Promise<number>`;
  - routes (`operationId`): `POST /v2/signin` (`startSignin`, 201); `GET /v2/signin?code=`
    (`findSignin`, session); `GET /v2/signin/{id}` (with `x-wambito-poll`: `pollSignin`; else session:
    `getSignin` → `{ id, commitment, label, expiresAt, publicKey }`); `POST /v2/signin/{id}/approver`
    (session, 204); `POST /v2/signin/{id}/reveal` (poll, 204); `POST /v2/signin/{id}/seal` (session,
    the bound user only, 204); `POST /v2/signin/{id}/pickup` (poll, 200 `{ sealed, keyV, userId }`
    and the session headers via `signInAs(…, remember ? "standard" : "short")`);
  - a router middleware: a request whose `authorization` is a bearer JWT (three dot-separated parts)
    gets 403 `insufficient_scope` on every `/v2/signin` route; the session routes run `requireUser`
    themselves and refuse an OAuth grant the same way.

- [ ] **Step 1: Write the failing tests** in `signin.test.ts` (flag-on app, pinned clock
  `now: () => clock`, real crypto as `pairing.test.ts` does: the phone seals with `sealToDevice`,
  the web opens with `openFromPairing`):
  - `the happy path: open, find by code, approve, poll sees the approver key, reveal, seal, pickup returns { sealed, keyV, userId } of the phone's user and a cookie that opens GET /v1/me as that user`;
  - `the row is gone after pickup: a second pickup is 404`;
  - `poll, reveal and pickup without x-wambito-poll, or with a wrong one, are 404`;
  - `the poll secret is stored hashed: no column of the row equals its bytes`;
  - `a request expires at 2 minutes: at 1:59 it is found, at 2:00 every route is 404`;
  - `approver bound once: a second approver call, from the same or another user, is 409 already_set`;
  - `after approval, GET /v2/signin/{id} and seal from another user are 404`;
  - `find by code is 404 once an approver is set`;
  - `out of order: reveal before approver 409 not_ready; seal before reveal 409 not_ready; pickup before seal 409 not_ready; reveal with a key that misses the commitment 422 commitment_mismatch; seal not starting with the approver key 422 approver_mismatch; seal at the wrong keyV 409 key_version_mismatch`;
  - `assistant tokens get 403 on every /v2/signin route` (all seven method/path pairs);
  - `the 6th open request from one IP is 429 too_many_signins; one expiring frees a slot`;
  - `the 31st open in 10 minutes from one IP is 429 too_many_requests`;
  - `ticked: the cookie has Max-Age 5184000 and the session lifetime standard; unticked: no Max-Age, a dont_remember cookie, lifetime short, expires_at = now + 12 h`;
  - **(Review Focus 5)** `an unticked session is 401 after 13 hours, and no response to it ever sets Max-Age` (move `expires_at`
    and `updated_at` back; call `GET /v1/me` before that and check its `set-cookie` headers);
  - **(Review Focus 2)** `two pickups at once: exactly one 200 and one 404, one session row`;
  - `a pickup for a suspended user is 403 account_suspended and creates no session`;
  - `purgeExpiredSignins deletes only expired rows`.
- [ ] **Step 2: Run** `pnpm vitest run apps/api/test/signin.test.ts`. Expected: FAIL (404 everywhere).
- [ ] **Step 3: Extract `services/relay.ts`** from `services/pairing.ts`, then run
  `pnpm vitest run apps/api/test/pairing.test.ts`. Expected: PASS, unchanged.
- [ ] **Step 4: Implement** the table (`generate --name signin_requests`), the service, the routes
  and the purge hook. `startSignin` retries a code collision (as `startPairing`), first deleting an
  expired row holding the code; the IP checks (`SIGNIN_OPEN_LIMIT`, then `IpOpenCount`) run before
  the insert, and `takeSignin` closes the id in `IpOpenCount`.
- [ ] **Step 5: Run** `pnpm vitest run apps/api`. Expected: PASS.
- [ ] **Step 6: CHANGELOG** (Added: the seven routes, their errors, the poll header, the 2-minute
  lifetime, the remember box's two session kinds), AGENTS (a `/v2/signin` bullet next to
  `/v2/pairing`; `/v2/pairing` names `relay.ts`), `packages/db/AGENTS.md` (0017), regenerate the
  clients. **Commit:**
  ```bash
  git add apps/api/src/services/relay.ts apps/api/src/services/signin.ts apps/api/src/routes/signin.ts apps/api/src/services/pairing.ts apps/api/src/services/sync.ts apps/api/src/app.ts apps/api/src/http/schemas.ts apps/api/src/http/client-headers.ts apps/api/test/signin.test.ts packages/db/src/schema/domain.ts packages/db/drizzle CHANGELOG.md apps/api/AGENTS.md packages/db/AGENTS.md apps/web/app/api/schema.d.ts apps/mcp/src/api/schema.d.ts apps/mobile/lib/api/gen
  git commit -m "feat(api): sign in on the web through the phone"
  ```

### Task 7: `/v2/me/seen` and `activity_daily`

**Files:**
- Create: `apps/api/src/services/activity.ts`, `apps/api/src/routes/activity.ts`, migration
  `0018_activity_daily.sql`.
- Modify: `apps/api/src/auth.ts` (user `additionalFields.appVersion`, `lastSeenDay`, both
  `returned: false`), `apps/api/src/app.ts`, `apps/api/src/http/client-headers.ts` (`version`),
  `packages/db/src/schema/auth.ts` (generated), `packages/db/src/schema/domain.ts`.
- Test: `apps/api/test/seen.test.ts`.

**Interfaces:**
- Consumes: `platformOf` (Task 2), `stampActivity` (Task 4), `userToday`/`nowOf`
  (`services/time.ts`).
- Produces:
  - `user.app_version` text null, `user.last_seen_day` text null (`YYYY-MM-DD`);
  - table `activity_daily` (`day` date, `platform` text, `app_version` text not null default `''`,
    `cohort_week` date, `has_email` boolean, `count` integer not null; pk over the first five);
    Drizzle `activityDaily`;
  - `markSeen(db: Db, input: { userId: string; today: string; platform: "android" | "ios" | "web"; appVersion: string | null; now: Date }): Promise<boolean>`
    — one statement: moves `last_seen_day` only when it is null or earlier than `today`, and in the
    same statement upserts `count = count + 1` on the row keyed by (`today`, platform, version or
    `''`, the user's cohort Monday, `not is_anonymous`); sets `app_version` when given; returns
    whether it counted; `stampActivity` always;
  - `POST /v2/me/seen` (`markSeen`, 204): `today` from `userToday(deps, c.get("user"))`, platform
    from `platformOf`, version from `x-wambito-version` (trimmed, at most 64 characters, else
    ignored); a background request (`x-wambito-background: 1`) is a 204 that changes nothing;
    assistants 403 (not in `ASSISTANT_PATHS`).

- [ ] **Step 1: Write the failing tests** in `seen.test.ts` (pinned clock):
  - `the first call of a day counts one in activity_daily with platform, version, cohort week and has_email`;
  - `a second call the same day counts nothing more`;
  - `the next local day counts again, in the same row's day + 1`;
  - **(Review Focus 4)** `a user in America/Bogota calling at 23:30 and 00:30 UTC on the same local day counts once`, and
    `moving the user to a zone where today is earlier neither counts nor moves last_seen_day back`;
  - `x-wambito-version sets user.app_version; a 65-character value is ignored`;
  - `a background request changes nothing: no row, last_seen_day unchanged`;
  - `seen moves user.last_active_at`;
  - `an assistant token gets 403`;
  - `activity_daily has no user id column` (read `information_schema.columns`).
- [ ] **Step 2: Run** `pnpm vitest run apps/api/test/seen.test.ts`. Expected: FAIL (404).
- [ ] **Step 3: Implement** the fields (`auth:generate`), the table (`generate --name activity_daily`,
  no RLS), the service and the route.
- [ ] **Step 4: Run** `pnpm vitest run apps/api`. Expected: PASS.
- [ ] **Step 5: CHANGELOG** (Added: `POST /v2/me/seen`, `x-wambito-version`, `x-wambito-client: ios`),
  AGENTS (client headers line: `version`, `client: ios`; a `/v2/me/seen` bullet; "background work
  never calls it"), `packages/db/AGENTS.md` (0018), regenerate the clients. **Commit:**
  ```bash
  git add apps/api/src/services/activity.ts apps/api/src/routes/activity.ts apps/api/src/auth.ts apps/api/src/app.ts apps/api/src/http/client-headers.ts apps/api/test/seen.test.ts packages/db/src/schema/auth.ts packages/db/src/schema/domain.ts packages/db/drizzle CHANGELOG.md apps/api/AGENTS.md packages/db/AGENTS.md apps/web/app/api/schema.d.ts apps/mcp/src/api/schema.d.ts apps/mobile/lib/api/gen
  git commit -m "feat(api): count active days without per-user history"
  ```

### Task 8: The 12/24-month cleanup of encrypted users

**Files:**
- Modify: `apps/api/src/services/guest-cleanup.ts` (plain cleanup filters `encryption = 'plain'`;
  new tiers; `scheduleGuestCleanup` runs both, then `purgeEndedSessions`), `apps/api/src/server.ts`
  (comment only), `packages/db/src/schema/domain.ts`.
- Create: `apps/api/src/services/ended.ts`, migration `0019_ended_sessions.sql` (both tables).
- Test: `apps/api/test/guest-cleanup.test.ts`, `apps/api/test/encrypted-cleanup.test.ts`.

**Interfaces:**
- Produces:
  - tables `ended_sessions` (`session_hash` bytea(32) pk, `reason` text CHECK = `device_removed`,
    `ended_at` timestamptz default now) and `deleted_users` (`user_hash` bytea(32) pk, `deleted_at`
    timestamptz default now); no RLS; Drizzle `endedSessions`, `deletedUsers`;
  - in `services/ended.ts`: `sha256(text: string): Buffer`; `recordEndedSessions(tx: Tx, tokens: string[]): Promise<void>`;
    `recordDeletedUsers(tx: Tx, userIds: string[]): Promise<void>`;
    `purgeEndedSessions(db: Db, now: Date): Promise<number>` (`ENDED_SESSION_DAYS = 90`);
  - in `guest-cleanup.ts`: `UNPROTECTED_IDLE_DAYS = 365`, `PROTECTED_IDLE_DAYS = 730`,
    `cleanupInactiveEncrypted(db: Db, now: Date): Promise<number>` — candidates are `encrypted`,
    anonymous users whose latest activity (the existing `lastActive` expression) is before
    now − 365 days, walked by id cursor in batches of `GUEST_CLEANUP_BATCH` under
    `GUEST_CLEANUP_LOCK`; a candidate with a `recovery_verifiers` row or a `passkey` key wrap (read
    through `withUser`: `key_wraps` has forced RLS) is kept unless idle before now − 730 days; the
    delete and `recordDeletedUsers` share one transaction.

- [ ] **Step 1: Write the failing tests.** `encrypted-cleanup.test.ts` (flag-on app; users made
  through the API, idle times set through `t.admin` as `guest-cleanup.test.ts`'s `lastActive`):
  - `no verifier, no passkey wrap: kept at 364 days idle, deleted at 366`;
  - `with a verifier: kept at 729 days, deleted at 731`; `with a passkey wrap only: the same`;
  - `a hidden recovery wrap without a verifier counts as unprotected` (deleted at 366);
  - `an encrypted user with an email is never deleted, however old`;
  - `an encrypted guest idle 61 days is not touched by the 60-day plain cleanup`;
  - `each deleted user's SHA-256 id hash is in deleted_users`;
  - `purgeEndedSessions deletes rows older than 90 days only`.
  `guest-cleanup.test.ts`: `a plain guest is still deleted at 61 days with the flag on` (insert a
  plain guest through `t.admin`).
- [ ] **Step 2: Run** `pnpm vitest run apps/api/test/encrypted-cleanup.test.ts apps/api/test/guest-cleanup.test.ts`.
  Expected: FAIL.
- [ ] **Step 3: Implement** the tables (`generate --name ended_sessions`), `ended.ts`, the tiers and
  the schedule (one log line per tier).
- [ ] **Step 4: Run** `pnpm vitest run apps/api`. Expected: PASS.
- [ ] **Step 5: CHANGELOG** (Changed: encrypted users without an email are deleted after 12 or
  24 idle months; the 60-day cleanup is for plain guests only), AGENTS (cleanup paragraph),
  `packages/db/AGENTS.md` (0019). **Commit:**
  ```bash
  git add apps/api/src/services/guest-cleanup.ts apps/api/src/services/ended.ts apps/api/src/server.ts apps/api/test/encrypted-cleanup.test.ts apps/api/test/guest-cleanup.test.ts packages/db/src/schema/domain.ts packages/db/drizzle CHANGELOG.md apps/api/AGENTS.md packages/db/AGENTS.md
  git commit -m "feat(api): delete idle encrypted users after 12 or 24 months"
  ```

### Task 9: Distinguishable 401s (`device_removed`, `user_deleted`)

**Files:**
- Modify: `apps/api/src/services/keys.ts` (`endSessions` records the ended tokens),
  `apps/api/src/http/session.ts` (the 401 code), `apps/api/src/http/problem.ts` only if the 401
  needs a new helper.
- Test: `apps/api/test/unauthenticated.test.ts`.

**Interfaces:**
- Consumes: `recordEndedSessions`, `sha256`, `deletedUsers`, `endedSessions` (Task 8); `grant`
  (`env.ts`).
- Produces:
  - `presentedSessionToken(headers: Headers, cookieName: string): string | null` in
    `http/session.ts` — the bearer value when it is not a JWT, else the session cookie
    (URL-decoded), cut at the first `.` (the signature);
  - `missingSessionCode(db: Db, headers: Headers, cookieName: string): Promise<"device_removed" | "user_deleted" | "unauthenticated">`
    — `device_removed` when the token's hash is in `ended_sessions`, else `user_deleted` when
    `x-wambito-user`'s hash is in `deleted_users`, else `unauthenticated`;
  - `requireUser` throws `ApiError(401, code, …)` with that code; the cookie name is
    `(await auth.$context).authCookies.sessionToken.name`.

- [ ] **Step 1: Write the failing tests** in `unauthenticated.test.ts` (flag-on app):
  - `a removed device's bearer gets 401 device_removed` (two device wraps with two sessions;
    `DELETE /v2/keys/{id}` of one);
  - `a device left out of a rotation gets 401 device_removed`;
  - `a removed browser's cookie gets 401 device_removed` (cookie session, signature stripped);
  - `after the cleanup deleted the user, a request with x-wambito-user gets 401 user_deleted`;
  - `without x-wambito-user it is 401 unauthenticated`; `a signed-out or unknown token is 401 unauthenticated`;
  - `an ended_sessions row older than 90 days, once purged, answers unauthenticated`;
  - `the caller's own session is never recorded as ended` (the device that removes another keeps
    working).
- [ ] **Step 2: Run** `pnpm vitest run apps/api/test/unauthenticated.test.ts`. Expected: FAIL
  (every case is `unauthenticated`).
- [ ] **Step 3: Implement.** `endSessions` selects the tokens of the sessions it ends and calls
  `recordEndedSessions` in the same transaction; `requireUser` calls `missingSessionCode` before its
  401.
- [ ] **Step 4: Run** `pnpm vitest run apps/api`. Expected: PASS (`keys.test.ts`, `expected-user.test.ts`
  unchanged).
- [ ] **Step 5: CHANGELOG** (Added: 401 `device_removed` and `user_deleted`; `x-wambito-user` is
  also read on a 401), AGENTS (the `/v2/keys` device-removal sentence; the `requireUser` line),
  regenerate the clients. **Commit:**
  ```bash
  git add apps/api/src/services/keys.ts apps/api/src/http/session.ts apps/api/test/unauthenticated.test.ts CHANGELOG.md apps/api/AGENTS.md apps/web/app/api/schema.d.ts apps/mcp/src/api/schema.d.ts apps/mobile/lib/api/gen
  git commit -m "feat(api): tell a removed device from a deleted user on a 401"
  ```

### Task 10: Admin metrics

**Files:**
- Modify: `apps/api/src/services/admin/metrics.ts`, `apps/api/src/routes/admin.ts` (the
  `AdminMetrics` schema), `docs/admin.md` (a "Numbers" section).
- Test: `apps/api/test/admin-read.test.ts` (or a new `apps/api/test/admin-metrics.test.ts`).

**Interfaces:**
- Consumes: `activityDaily`, `user.platform`, `user.appVersion`, `user.lastSeenDay` (Tasks 2, 7).
- Produces (added to `AdminMetrics`; existing fields unchanged, decision 15):
  - `dailyActive: { day: string; count: number }[]` — 90 days ending today (UTC), oldest first,
    zero-filled, the sum of `activity_daily.count` per day;
  - `cohorts: { weekStart: string; size: number; week1: number | null; week4: number | null; week12: number | null }[]`
    — the last 12 ISO weeks of `user.created_at`; `weekN` per decision 14, `null` while that week has
    not ended;
  - `installsByPlatform: { platform: "android" | "ios" | "web" | "unknown"; count: number }[]`
    (`null` platform → `unknown`);
  - `versions: { platform: string; appVersion: string; users: number }[]` — users whose
    `last_seen_day` is within the last 30 days, by platform and version, most users first.

- [ ] **Step 1: Write the failing test** `metrics: dailyActive, cohorts, installs by platform and versions on seeded users`:
  seed invented users through `t.admin` (three android, one ios, one with no platform, created in
  two different weeks) and `activity_daily` rows; assert `dailyActive.length === 90`, the seeded
  days' counts and zeros elsewhere; the cohort sizes and a `week1` equal to the highest seeded day
  of that week; `installsByPlatform` `[android 3, ios 1, unknown 1]` (web 0 included);
  `versions` sorted; `guests` still counts users without an email.
- [ ] **Step 2: Run** `pnpm vitest run apps/api/test/admin-metrics.test.ts`. Expected: FAIL (fields
  missing).
- [ ] **Step 3: Implement** the four SQL aggregates in `adminMetrics` (aggregates only, no user row
  leaves the database) and extend the zod schema.
- [ ] **Step 4: Run** `pnpm vitest run apps/api` and `pnpm --filter @wambito/web typecheck`.
  Expected: PASS.
- [ ] **Step 5: `docs/admin.md`:** what each number means, that `guests` is "without email", where
  installs and actives come from, and that no IP or finance field is read. CHANGELOG (Added: the
  four metrics), AGENTS (admin bullet), regenerate the clients. **Commit:**
  ```bash
  git add apps/api/src/services/admin/metrics.ts apps/api/src/routes/admin.ts apps/api/test/admin-metrics.test.ts docs/admin.md CHANGELOG.md apps/api/AGENTS.md apps/web/app/api/schema.d.ts apps/mcp/src/api/schema.d.ts apps/mobile/lib/api/gen
  git commit -m "feat(api): installs, daily actives, cohorts and versions in the admin metrics"
  ```

### Task 11: Close-out

**Files:** none new, unless a check fails.

- [ ] **Step 1: Run everything** from the repo root:
  `pnpm lint && pnpm typecheck && pnpm test && scripts/check-old-name.sh && scripts/check-channels.sh`,
  then the generated-file checks CI runs (`pnpm --filter @wambito/web api:types --file`,
  `pnpm --filter @wambito/mcp api:types`, `apps/mobile/scripts/gen-api.sh`, then
  `git diff --exit-code`). Expected: all green, no diff.
- [ ] **Step 2: Read the `## Unreleased` section once** and merge duplicate lines; every new route,
  header, error code and changed lifetime appears once.
- [ ] **Step 3: Whole-branch review** (superpowers:requesting-code-review), against the spec
  sections in the header and the Review Focus list.
- [ ] **Step 4: Report the Caddy finding** to the founder (below) and ask whether to open it as its
  own task.

## Outside this plan: Caddy access log (spec §9)

`deploy/personal/routes.caddy` writes an access log to stdout for every request, `/api/*`
included, with `log_append visitor_ip {vars.client_ip}`, and its `format filter` deletes only the
request headers, `tls` and the response headers, so Caddy's own `request>remote_ip` and
`request>client_ip` fields stay too. Client IPs therefore reach `docker compose logs web` today,
which the spec forbids for the API host. The fix (drop `visitor_ip` and filter out `remote_ip` and
`client_ip`, at least for `/api/*`, with a case in `deploy/personal/test-caddy.sh`) is a deploy
change; it is left to its own task, before the switch day.

## Follow-ups for later deliveries (found while planning)

- The phone sends `x-wambito-client: android` on iOS too (`apps/mobile/lib/api/device.dart`), so
  iOS installs count as Android until delivery 2 sends `ios`.
- Turning `NEW_USERS_ENCRYPTED` on in the root `docker-compose.yml` and CI e2e goes with the web
  delivery (decision 17).
