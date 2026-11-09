# apps/api: the HTTP API (`@wambito/api`)

Hono + Better Auth + Drizzle (`@wambito/db`), OpenAPI document "Wambito API". Every client
(web, mobile, MCP) goes through it.

## Entry points

- `src/server.ts` starts it; `src/app.ts` builds the app (routes, OpenAPI).
- `src/config.ts`: zod env schema (`WAMBITO_VERSION` included); `.env.example` at the repo root.
- `src/auth.ts`: Better Auth: email OTP + magic link, anonymous guests, passkeys (`rpName`
  "Wambito", rpID = WEB_URL host), jwt + oauthProvider for the MCP.
- `src/http/session.ts`: `requireUser` (cookie or bearer session, or an OAuth JWT with `aud` =
  MCP_URL). `src/http/scopes.ts`: OAuth scopes (`finance:read`, …), enforced here, not in the MCP.
- `src/http/client-headers.ts`: `clientHeader`. `src/routes/*.ts`: the routes.
  `src/services/`: domain services. `src/emails/sign-in.ts`: sign-in mail copy (es/en/it/pt);
  `src/emails/layout.ts`: the frame every email shares (Wambi, wordmark image, card, footer; day
  colours inline, night in a `prefers-color-scheme` block; fonts by `@font-face` from WEB_URL).
- `POST /v1/captures` (`src/routes/captures.ts`, `src/services/captures.ts`): saves a bank-notification
  capture to review; 10-minute duplicate merge, merchant → category memory, `system_key = other`
  fallback categories; the Idempotency-Key is required.
- Reviewing captures: `PATCH /v1/transactions/{id}` with `needsReview: false` and `POST
  /v1/transactions/review` (all or nothing, 404 on any foreign id) confirm them; list filter
  `needsReview=true|false`. `learn` (`services/captures.ts`) upserts the merchant → category memory,
  keyed on `transactions.capture_merchant_key` (the merchant as notified; the name only when null),
  only when a `capture` row flips to confirmed in that request, with an active, same-kind category
  that has no `system_key`.
- Admin panel (spec `docs/superpowers/specs/2026-11-04-admin-panel-design.md`):
  `src/routes/admin.ts` (`/v1/admin/*`, mounted before `requireUser`), guarded by `requireAdmin`
  (`src/http/admin.ts`): a cookie session (no `authorization` header), the id in `ADMIN_USER_IDS`,
  the client IP in `ADMIN_ALLOWED_IPS` when set, else 404 `not_found`; actions also need a passkey
  verification < 15 min old (401 `admin_verification_required`). `ADMIN_USER_IDS` unset: every
  admin path is 404. Actions take a `reason` (1–300, 422 without), write the effect and its
  `admin_audit` row in one transaction, then mail the person (`src/emails/admin.ts`, after commit;
  failures logged, never a guest/`.invalid` address). `src/services/admin/` touches identity tables
  only (`user`, `session`, `passkey`, OAuth, `email_change`, `admin_*`); finance data only through
  `deleteAccount`. An email change refuses a new address `SIGN_IN_ALLOWLIST` does not list (409
  `sign_in_not_allowed`, at request and confirm) or under `.invalid` (422). A suspend of a
  suspended account, or a reactivate of an active one, is a 204 no-op: no audit row, no mail.
- `src/routes/email-change.ts`: public `POST /v1/email-change/confirm` (mounted before
  `requireUser`), the person's end of an admin's email change; 10 per 10 min per client IP in the
  `rate_limit` table (key `email-change-confirm|<ip>`).
- `GET`/`POST /v2/sync` (`src/routes/sync.ts`, `src/services/sync.ts`; spec
  `docs/superpowers/specs/2026-11-08-end-to-end-encryption-design.md` §5–6): opaque encrypted
  records, never read or logged. A push holds `pg_advisory_xact_lock(hashtextextended('records:'
  || user_id, 0))` (every `records` write takes it, so versions commit in order per person), one
  savepoint per change; limits 500 changes, 4 MiB (`hono/body-limit`), 64 KiB body, 100,000 live
  records. `purgeTombstones` (daily, `server.ts`) goes person by person through `withUser`, since
  `records` has forced RLS; in the same transaction it raises `record_purges.through_version`
  (per person, `greatest`), and `GET /v2/sync` answers 410 `resync_required` when
  `0 < base < through_version`, where `base` is the optional query param for the `latest` a pull
  cycle started from (defaults to `since`; a full download pages with `base=0`, which never fails).
  The purge mark is read after the records query in the same pull. An update never creates (`not_found`) nor changes `type` (conflict);
  a hidden id (`id_taken`) is found by a rolled-back insert probe. `deps.syncHooks` is a test-only
  seam.
- `/v2/keys` (`src/routes/keys.ts`, `src/services/keys.ts`; same spec §5.2, §7): wraps of the
  data key, opaque bytes. Every write holds `pg_advisory_xact_lock(hashtextextended('key_wraps:' ||
  user_id, 0))`; the current keyV is the max over the account's wraps (any keyV for the first).
  Passkey wraps' `ref` is the passkey's `credentialID`; `auth.ts` hooks on
  `/passkey/delete-passkey` (before: read the credential id; after, on success: delete the wrap; two
  statements, not one transaction). Assistant wraps' `ref` is the OAuth client id (needs an
  `oauth_consent` row). Known follow-up: revoking an assistant does not delete its wrap yet (stage
  4, rotation). Tokens reach only `GET /v2/keys/assistant` (`http/scopes.ts`), which sets
  `last_used_at`; sessions get 404 there. A `device` wrap also carries a 32-byte `attestation`
  (HMAC under a key derived from the data key, `deviceAttestation` in `@wambito/crypto`); the
  server cannot verify it, only requires it (422 `attestation_required`, checked before the DB;
  other kinds sending `publicKey` or `attestation` are 422 `validation_failed`).
  `PUT /v2/keys/{id}` with `If-None-Match: *` (`onlyFirst`): stored only while the account has no wrap but `id` (a retry of
  the same PUT), else 409 `already_set_up`, checked under the lock; the web's first setup sends its
  recovery wrap with it, so two setups at once cannot make two data keys.
- `/v2/pairing` (`src/routes/pairing.ts`, `src/services/pairing.ts`; stage 1b spec §1): relay for
  approving a new device with a key commitment; opaque bytes, never read or logged. Flow: `POST`
  `{commitment}` (new device, commits first) -> `GET ?code=` (approver; 404 once an approver key is
  set) -> `POST /{id}/approver` (once, 409 `already_set`) -> `POST /{id}/reveal` (new device's key;
  409 `not_ready`/`already_set`, 422 `commitment_mismatch` via `pairingCommitment` from
  `@wambito/crypto`) -> `POST /{id}/seal` `{sealed, keyV}` (409 `not_ready`/`already_sealed`, 422
  `approver_mismatch`: first 32 bytes must be the approver key; 409 `key_version_mismatch` unless
  `keyV` is the account's current key version) -> `GET /{id}` returns the full state (null fields
  until set), never deletes -> `POST /{id}/pickup` returns `{sealed, keyV}` and deletes the row in
  one transaction (409 `not_ready` while unsealed). Unexpected DB errors are logged without bound
  params (`safeLogFields` in `http/problem.ts`). The server makes the
  8-char code (`pairingCode`), unique per person (a collision retries); lookup normalizes the typed
  code. 10 min TTL read from `deps.now`, max 5 open (429). Every write holds
  `pg_advisory_xact_lock(hashtextextended('pairing_requests:' || user_id, 0))`.
  `purgeExpiredPairings` runs with the daily tombstone purge (`scheduleTombstonePurge`). Assistant
  tokens get 403 (not in `ASSISTANT_PATHS`).
- `/v2` rules: record and key-wrap ids are lower-case UUIDs (`lowerCaseUuid` in `http/schemas.ts`,
  the `@wambito/crypto` rule; never lower-cased, upper case is 422); a live record body is at least
  28 bytes (nonce + tag); an account's first wrap is `recovery` (422 `recovery_required`). Every
  statement in `services/keys.ts`, `sync.ts` and `pairing.ts` also filters on the user id, on top
  of RLS.
- End-to-end encryption preview (stage 2a): `E2E_PREVIEW_USER_IDS` (comma-separated user ids,
  unset by default; `isPreviewAccount` in `config.ts`). `GET /v1/me` (every profile answer) says
  `encryption: "preview" | "plain"`. A preview account's finances live only as records under
  `/v2`; the user-create hook in `auth.ts` seeds no default account or categories for it (the web
  creates them as records), so its `/v1` finance tables stay empty.
  `previewOnlyV2` (`src/http/preview.ts`, after `requireUser` and the scopes on `/v1/*`) answers 403 `encrypted_account` on the `/v1` finance
  routes (transactions, categories, recurrences, summary, reports, captures, imports,
  `/v1/me/export`) for a preview account's sessions and tokens; `PATCH /v1/me` with `currency` is
  403 too (the currency lives in the settings record). `DELETE /v1/me` still works:
  `records`, `key_wraps`, `record_purges` and `pairing_requests` cascade from `user`.
- `src/scripts/seed.ts`: creates `dev@wambito.test`.
- `src/scripts/seed-admin.ts` (`seed:admin`): upserts the admin `dev-admin` (`admin@wambito.test`,
  onboarded, default account and categories) through `DATABASE_ADMIN_URL` and clears its email
  throttle; the root compose lists it in `ADMIN_USER_IDS`. CI runs it before the web e2e.

## Talks to

- Mounted under API_URL's path (`/api` behind the web origin / Caddy, so auth cookies are
  first-party). Web and mobile call it; the MCP forwards the assistant's OAuth token.
- Client headers `x-wambito-{locale,next,timezone,client,background,user}`, always read via
  `clientHeader`, never `headers.get("x-…")`. A timezone header means "from the device"; `background: 1` reads the
  session with `disableRefresh` (not counted as activity); `user` on `/v2/*` is the account the
  client means: another signed-in account gets 409 `session_changed` (`expectedUser` in
  `src/http/expected-user.ts`, after `requireUser`, before the scopes; sessions and tokens alike).
- DB: connects as the runtime role (RLS); migrations run as admin (`packages/db`).

## Run and test (repo root)

- Services: `docker compose up -d postgres mailpit`; then `pnpm --filter @wambito/api dev`,
  seed with `pnpm --filter @wambito/api seed`. Mail lands in Mailpit (http://localhost:8025).
- Tests: `pnpm vitest run apps/api`, one file `pnpm vitest run apps/api/test/auth.test.ts`.
  Each file starts a Postgres testcontainer via `test/harness.ts` (`createTestApp`): Docker must
  run, or set `WAMBITO_TEST_DB=local`.
- After changing a route or schema, regenerate the clients' types (root `AGENTS.md`); CI diffs them.

## Traps

- Every change here that clients can see goes under "Unreleased" in the root `CHANGELOG.md`.
- See root `AGENTS.md`: secrets.
- Better Auth tables: `pnpm --filter @wambito/api auth:generate` writes
  `packages/db/src/schema/auth.ts`; then add a migration in `packages/db`.
- Rate limits trust one X-Forwarded-For hop set by Caddy: `docs/deploy/api.md`.
