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
  `records` has forced RLS. `deps.syncHooks` is a test-only seam.
- `src/scripts/seed.ts`: creates `dev@wambito.test`.
- `src/scripts/seed-admin.ts` (`seed:admin`): upserts the admin `dev-admin` (`admin@wambito.test`,
  onboarded, default account and categories) through `DATABASE_ADMIN_URL` and clears its email
  throttle; the root compose lists it in `ADMIN_USER_IDS`. CI runs it before the web e2e.

## Talks to

- Mounted under API_URL's path (`/api` behind the web origin / Caddy, so auth cookies are
  first-party). Web and mobile call it; the MCP forwards the assistant's OAuth token.
- Client headers `x-wambito-{locale,next,timezone,client,background}`, always read via
  `clientHeader`, never `headers.get("x-…")`. A timezone header means "from the device"; `background: 1` reads the
  session with `disableRefresh` (not counted as activity).
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
