# E2E Stage 5 Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `plain` account with an email migrates itself to `encrypted` from the web, once, without losing a row. Old clients are told to update, and the switch-day copy and runbook are ready.

**Architecture:** The API gains an account state `migrating` and four session-only routes:
- `start` binds the session;
- `source` hands over the plaintext;
- `finish` checks the counts and deletes the plaintext in one locked transaction;
- `cancel` starts over.

A pure mapper in `@wambito/vault` turns the source into record bodies. The web runs a resumable flow that sets up keys (the existing `prepareAccount`), writes the records into the encrypted store, pushes them with the sync engine, and calls `finish`. Everything waits on a new flag, `MIGRATION_OPEN`.

**Tech Stack:** Hono + Drizzle (API, testcontainers tests), `@wambito/vault` / `@wambito/core` (TS), React Router web (Vitest unit + Storybook play + Playwright e2e), MCP (TS).

**Spec:** `docs/superpowers/specs/2026-11-19-e2e-stage-5-switch-design.md`

## Global Constraints

- **Account states:** `user.encryption` in `plain` | `migrating` | `encrypted`. Elsewhere, `migrating` behaves as `plain` (cleanup tiers, session length, 401 codes, recovery sign-in). It behaves as `encrypted` only for the 426 and the write rule.
- **Gate:** `GET /v1/me` `migration` is:
  - `"available"` for a non-anonymous `plain` user when `MIGRATION_OPEN` is true or its id is in `MIGRATION_OPEN_USER_IDS`;
  - `"in_progress"` while `migrating`;
  - absent otherwise.

  `encryption` answers `"preview"` for `migrating` and `encrypted`.
- **Write rule:** while `migrating`, only `user.migration_session_id` may push `/v2/sync` or write `/v2/keys*` (PUT, DELETE, POST rotate) and the pairing and recovery wrap writes. Any other session gets 409 `migration_in_progress`.
- **426:** 426 `update_required` (title "Upgrade Required") on every `FINANCE_PATHS` route, and on `PATCH /v1/me` with a currency, for `migrating` and `encrypted`. It replaces 403 `encrypted_account`.
- **Locks:** `finish` and `cancel` take the same advisory locks as `pushRecords` (`records:<userId>`) and `putKeyWrap` (`lockWraps`), so nothing lands between the count and the delete.
- **What `finish` deletes:** `transactions`, `categories`, `category_budgets`, `recurrences`, `merchant_categories`, `accounts`, `imports`, `idempotency_keys` of the user, then `revokeAllAssistants`, then `encryption='encrypted'` and `migration_session_id=null`. The `user` profile columns stay.
- **Ids:**
  - Records keep the server ids.
  - A dismissed occurrence (soft-deleted, `status='pending'`, `source='recurrence'`) takes the id `uuidv5(recurrenceId, "<YYYY-MM>:0")`.
  - The settings record id is `uuidv5(uuidv5(SEED_NAMESPACE, userId), "settings")` (`apps/web/app/local/vault-session.ts`).
- **Dates and money:** a server date `YYYY-MM-DD` becomes `YYYY-MM` for `occurrenceMonth` and `effectiveFrom`. Amounts stay integer cents. A transaction body's `accountId` is null.
- **Settings currency:** the default `accounts` row's `currency`.
- **Never log** the `/v2/migration/source` body or a sync body.
- Each API change gets a `CHANGELOG.md` line under "Unreleased". Regenerate the web, MCP and mobile clients after a route or schema change; never hand-edit them.
- **Copy:** es, en, it, pt; PT-PT; Wambi's voice; no money slang in it or pt.
- Failing test first. Stage by path. `feat(area): …` commits. No `Co-Authored-By`. Each area's `AGENTS.md` is updated when its flows change. No real data in fixtures, logs or the repo.

## Review Focus

1. A reload or a closed tab mid-flow resumes from `in_progress` and never makes a second data key. Test: the flow model resumes after every step.
2. A second device or tab writing during `migrating` is refused, and the count check still passes for the starting session. Test: in the Task 2 API tests.
3. The founder's real shapes: an archived category with transactions, a budget history with several months, a yearly recurrence, a deleted transaction, a dismissed month, a capture with a merchant key. Test: in the Task 3 mapper tests and the Task 5 e2e.
4. `finish` racing a push from the starting session itself: the lock makes it either count the push or wait for it. Test: in Task 2.
5. A plain account in CI's plain-app e2e never sees the flow: its id is not in `MIGRATION_OPEN_USER_IDS`, and `MIGRATION_OPEN` is off in CI. Test: in Task 1 (`migration` absent) and by the full web e2e staying green.

---

### Task 1: API account state, gate and 426

**Files:**
- Create: `packages/db/drizzle/0021_*.sql` (custom), with its snapshot and journal entry: drop and re-add `user_encryption_check` with `'migrating'`, and add `"user"."migration_session_id" text` (nullable).
- Modify:
  - `packages/db/src/schema/auth.ts` (column), `packages/db/AGENTS.md` (migration list)
  - `apps/api/src/services/encryption.ts` (`Encryption` type and `accountEncryption` returning `migrating`)
  - `apps/api/src/config.ts`: `MIGRATION_OPEN` (boolean, default false), `MIGRATION_OPEN_USER_IDS` (csv, default empty); `isPreviewAccount` true for `migrating`
  - `apps/api/src/http/preview.ts`: `updateRequired()` = `ApiError(426, "update_required", …)` replaces `encryptedAccount()`
  - `apps/api/src/http/problem.ts` (`426: "Upgrade Required"`)
  - `apps/api/src/routes/me.ts`: `profileDto.migration` optional enum `["available","in_progress"]`; the currency PATCH throws 426
  - every raw `encryption` site the recon listed, so each keeps `plain` behaviour for `migrating`: `auth.ts` (555, 601, 626), `routes/recovery.ts:62`, `services/keys.ts:155`, `services/sessions.ts` (28, 58), `services/guest-cleanup.ts` (86, 127)
  - `docker-compose.yml`: `MIGRATION_OPEN_USER_IDS: ${MIGRATION_OPEN_USER_IDS:-migrate-e2e}` and `MIGRATION_OPEN: ${MIGRATION_OPEN:-false}`; `.env.example`; `deploy/personal` compose and `.env.example` pass both
  - `CHANGELOG.md`; `apps/api/AGENTS.md`
- Regenerate: `pnpm --filter @wambito/web api:types --file`, `pnpm --filter @wambito/mcp api:types`, `apps/mobile/scripts/gen-api.sh`.
- Test: `apps/api/test/preview.test.ts` (the 403 cases become 426), new `apps/api/test/migration-state.test.ts`.

**Interfaces:**
- Produces:
  - `type Encryption = "plain" | "migrating" | "encrypted"`
  - `accountEncryption(db, userId): Promise<Encryption>`
  - `migrationOf(config, user: {id, encryption, isAnonymous}): "available" | "in_progress" | undefined` in `services/encryption.ts`
  - `updateRequired(): ApiError`

- [ ] **Failing tests in `migration-state.test.ts`:**
  - `migration is absent for a plain user while MIGRATION_OPEN is off`
  - `migration is "available" for a plain user with an email when MIGRATION_OPEN is on, and for an id in MIGRATION_OPEN_USER_IDS`
  - `a guest never gets "available"`
  - `a migrating user gets encryption "preview" and migration "in_progress"`
  - `an encrypted user gets no migration field`
  - `a migrating user keeps plain session length, cleanup and 401 codes` (one test per site)
- [ ] **Failing test in `preview.test.ts`:** every `FINANCE_ROUTES` entry answers 426 `update_required` for `migrating` and for `encrypted`; `PATCH /v1/me` `{currency}` the same; `GET /v1/me` and `DELETE /v1/me` still answer.
- [ ] Run `pnpm --filter @wambito/api test -- migration-state preview` and watch them fail.
- [ ] Implement the migration and the code above. `pnpm --filter @wambito/db generate --custom` for 0021.
- [ ] Regenerate the three clients. Update every place that matches 403 `encrypted_account`:
  - web `app.*.json` `errors.encrypted_account` → `errors.update_required` "Actualiza Wambito: recarga la página.";
  - `apps/mcp/src/api-wambito.ts` `toToolError`: 426 `update_required` → `reconnectError()`;
  - tests that assert the old code.
- [ ] `pnpm --filter @wambito/api test`, `pnpm typecheck`, `pnpm lint` all pass; the CI generated-file checks are clean (`git diff --exit-code` after regenerating).
- [ ] Commit `feat(api): a migrating account state, the migration gate and 426 for old clients`.

### Task 2: API migration routes

**Files:**
- Create: `apps/api/src/routes/migration.ts`, `apps/api/src/services/migration.ts`, `apps/api/src/http/migration-lock.ts` (the write-rule middleware)
- Modify: `apps/api/src/app.ts` (mount routes; the middleware after `assistantScopes` on `POST /v2/sync`, `/v2/keys*` writes, `/v2/pairing/*` and `/v2/recovery/*` writes), `CHANGELOG.md`, `apps/api/AGENTS.md`
- Regenerate the three clients.
- Test: `apps/api/test/migration.test.ts`

**Interfaces:**
- Produces (JSON over HTTP; the generated web types are named after these operationIds):
  - `POST /v2/migration/start` → 200 `MigrationCounts`. operationId `startMigration`.
    - The user must be `plain` with an email (409 `not_migratable` otherwise), or `migrating`: then it re-binds the session (takeover) and answers the same counts.
  - `GET /v2/migration/source` → 200 `MigrationSource`. operationId `migrationSource`. `migrating` and the bound session only (409 `migration_in_progress` for another session, 409 `not_migrating` otherwise).
  - `POST /v2/migration/finish` body `{counts: MigrationCounts}` → 200 Profile. operationId `finishMigration`. A mismatch gives 409 `count_mismatch` with `errors: {server: MigrationCounts, records: MigrationCounts, client: MigrationCounts}`.
  - `POST /v2/migration/cancel` → 204. operationId `cancelMigration`.
- `MigrationCounts = {transaction: number, deletedTransaction: number, category: number, budget: number, recurrence: number, merchant: number}`:
  - `deletedTransaction` counts the soft-deleted rows still in the restore window (records: deleted with a body);
  - dismissed occurrences are counted in `deletedTransaction`;
  - `settings` (always 1) is checked apart: the records must hold exactly one live `settings`.
- `MigrationSource = {profile: {timezone, locale, onboardingCompletedAt, currency}, categories[], budgets[], recurrences[], transactions[], merchants[]}`. Rows are as the DB holds them (ids, ISO timestamps, `YYYY-MM-DD` dates, integer cents, `deletedAt`). `transactions` includes soft-deleted rows inside the restore window, read from `services/transactions.ts`'s window constant.

- [ ] **Failing tests in `migration.test.ts`**, with a seeded plain user through the `/v1` routes plus direct `t.admin` rows for a dismissed month and an archived category:
  - `start` sets migrating and binds the session; a second `start` from the same session gives the same counts
  - `start` from another session takes over; the first session's push then gets 409 `migration_in_progress`
  - `start` for a guest, an encrypted account or `MIGRATION_OPEN` off with no listed id gives 409 `not_migratable`
  - `source` holds every type, includes a soft-deleted transaction inside the window, and excludes one outside it
  - `source` is refused to another session and to an assistant token (403 `insufficient_scope`)
  - `finish` with records matching every count deletes the plaintext rows of all eight tables, revokes assistants, sets encrypted, and `GET /v1/me` then has no `migration`
  - `finish` with one record short gives 409 `count_mismatch` and changes nothing (plaintext rows still there, still migrating)
  - `finish` with no settings record or two settings records gives 409 `count_mismatch`
  - `cancel` deletes records and purge rows, keeps key wraps, sets plain and clears the session
  - a push from the bound session that commits while `finish` waits on the lock is counted, or `finish` reports the mismatch; never a delete with a record missing
  - `the source answer is never logged`: run `source` with a log capture, and assert no transaction name appears
- [ ] Watch them fail; implement; rerun.
- [ ] Regenerate the clients; `pnpm --filter @wambito/api test`, `pnpm typecheck`, `pnpm lint`.
- [ ] Commit `feat(api): migration routes that only delete plaintext once the encrypted copy matches`.

### Task 3: Vault: source to records, and a full store reset

**Files:**
- Create: `packages/vault/src/migration.ts`, `packages/vault/src/migration.test.ts`
- Modify:
  - `packages/vault/src/encrypted.ts` (the `EncryptedStore` interface gains `resetAll()`)
  - `apps/web/app/local/encrypted-store.ts` and the memory store `createMemoryEncryptedStore`: `resetAll()` clears records, the outbox and the sync cursors, and keeps meta
  - `packages/vault/src/index.ts` exports, `packages/vault/AGENTS.md`
- Test: `packages/vault/src/migration.test.ts`, the store tests for `resetAll`.

**Interfaces:**
- Consumes: `MigrationSource`, `MigrationCounts` shapes (Task 2), `uuidv5` (`packages/vault/src/ids.ts`), `parseRecord` (`@wambito/core`).
- Produces:
  - `recordsFromSource(source: MigrationSource, userId: string): Promise<MigrationRecord[]>`, where `MigrationRecord = {type: RecordType, id: string, body: unknown, deleted: boolean}`. Every body passes `parseRecord`.
  - `countsOf(records: MigrationRecord[]): MigrationCounts`
  - `SETTINGS_SEED_NAMESPACE`: moved here from `vault-session.ts`, and imported back by it.

- [ ] **Failing tests:**
  - `a transaction keeps its id and cents, with YYYY-MM occurrenceMonth and accountId null`
  - `a soft-deleted transaction is a deleted record with its body`
  - `a dismissed occurrence takes uuidv5(recurrenceId, "2026-10:0") and is deleted`
  - `a paid or edited occurrence keeps its server id`
  - `an archived category keeps archivedAt`
  - `budgets become effectiveFrom YYYY-MM, one record per month row`
  - `a yearly recurrence keeps monthOfYear, rev 0`
  - `merchants become merchant records with their categoryId`
  - `settings carry currency, locale, timezone and onboardingCompletedAt, with the seed-derived id`
  - `countsOf matches the server's counting rule`
  - `resetAll leaves no record, no outbox entry and no cursor, and keeps keyV and deviceWrapId`
- [ ] Watch them fail; implement; rerun `pnpm --filter @wambito/vault test` and the web store tests.
- [ ] Commit `feat(vault): map a plain account's source to sealed-record bodies, and reset a store`.

### Task 4: Web migration flow

**Files:**
- Create:
  - `apps/web/app/features/migration/migration-flow.ts` (pure state machine, as `vault-gate.ts` is) and `migration-flow.test.ts`
  - `apps/web/app/features/migration/MigrationScreen.tsx` and `Migration.stories.tsx`
  - `apps/web/app/local/migration.ts` (live deps: the API calls, keys, store writes, sync loop)
- Modify:
  - `apps/web/app/auth/encryption.ts`: `previewProfile` returns null when `migration` is set; a new `migrationOf(profile)`
  - `apps/web/app/routes/app.tsx` and `routes/welcome.tsx` loaders: a profile with `migration` renders the flow before `VaultGate` or the plain app
  - `apps/web/app/api/client.ts`: 426 → `ApiProblem("update_required")`, shown by the existing error copy
  - `app.{es,en,it,pt}.json` (`migration.*`)
  - `apps/web/AGENTS.md`

**Interfaces:**
- Consumes:
  - Task 2's routes (generated types);
  - Task 3's `recordsFromSource`, `countsOf`, `resetAll`;
  - `prepareAccount` and `loadLocalKeys` (`apps/web/app/local/keys.ts`);
  - `createEncryptedStore`, `createSyncEngine` (`@wambito/vault`);
  - `RecoveryKeySetup` (`features/vault/RecoveryKeySetup.tsx`).
- Produces: `createMigrationFlow(deps: MigrationDeps)`, with states:
  - `intro`
  - `keys {recoveryKey}`
  - `copying {done, total}`
  - `finishing`
  - `done`
  - `failed {problem: "count_mismatch" | "offline" | "server" | "taken_over"}`
  - `noLocalVault` (`in_progress` with no keys here; offers cancel and restart)

  The store meta key `migrationStep` (`"keys" | "copying" | "finishing"`) is what a resume reads.

Flow rules (from the spec):
1. `start`.
2. Keys: `prepareAccount({guest:false})`, `RecoveryKeySetup`, `commit()`. Skipped when `loadLocalKeys` finds keys.
3. `source`, then `recordsFromSource`.
4. In `store.transaction`: `put` each record, then `delete` the deleted ones (tombstone with body).
5. Loop `engine.run()` until `readOutbox(1)` is empty.
6. `finish(countsOf(records))`.

Other rules:
- The flow never calls `openVaultSession` or the local backend before `done`, so `seedIfEmpty` and `materialize` add nothing.
- On `done` the loader reloads, and `VaultGate` opens the existing keys (`seedIfEmpty` is a no-op, since settings exist).
- On a failure, the retry runs `cancel`, `resetAll()`, then from step 1 with the same keys.

Copy (es, fixed; en, it and pt in the same voice):
- intro title "Protege tus datos"
- intro body "Vamos a cifrar tu cuenta: desde ahora solo tú podrás leer tus movimientos. Toma un minuto y no se pierde nada."
- copying "Cifrando tus datos… {done} de {total}"
- done "Listo: tu cuenta está cifrada."
- count mismatch "Algo no cuadró y no borramos nada. Inténtalo de nuevo."
- taken over "Esta migración sigue en otra pestaña o dispositivo."

- [ ] **Failing model tests:**
  - `runs start, keys, source, write, sync, finish in order`
  - `a reload at each step resumes there and never calls prepareAccount twice`
  - `count_mismatch keeps the plaintext: retry calls cancel then resetAll then start`
  - `offline at source leaves migrating and offers retry`
  - `in_progress with no local keys shows noLocalVault`
  - `409 migration_in_progress shows taken_over`
  - `never opens the vault session before done`
- [ ] Story play tests per state, with `expectTarget` on the buttons.
- [ ] Watch them fail; implement; rerun the web unit and storybook projects for `features/migration`, `auth`, `routes`; `pnpm --filter @wambito/web typecheck`; `pnpm lint`.
- [ ] Commit `feat(web): migrate a plain account to encrypted from the web`.

### Task 5: Web e2e of the migration

**Files:**
- Create:
  - `apps/api/src/scripts/seed-e2e-migrate.ts` (script `seed:e2e-migrate`): it resets the user id `migrate-e2e` (email `migrate@wambito.test`) as `plain` with every shape in Review Focus 3, through the services or direct inserts, all invented data;
  - `apps/web/e2e/migration.spec.ts`
- Modify: `apps/web/e2e/helpers.ts` (`seedMigrateUser()`, `psql(sql)` via `docker compose exec -T postgres psql -U wambito -d wambito -tAc`), `apps/web/AGENTS.md` (e2e accounts list), `apps/api/package.json`.
- Test: `apps/web/e2e/migration.spec.ts` (desktop project only, like `vault.spec.ts`).

- [ ] Failing spec `a plain account migrates and keeps everything`:
  1. Seed, then sign in by email code.
  2. The flow runs: intro, keys with the 4-character check, copying, done.
  3. Then:
     - home's month summary and the budgets match the figures read before (via the plain API before migrating);
     - the archived category is still archived;
     - the dismissed recurring month does not come back;
     - restoring the deleted transaction brings it back;
     - `psql` finds 0 rows of `migrate-e2e` in the eight tables and `encryption = 'encrypted'`.
- [ ] Spec `a reload during copying resumes and finishes`.
- [ ] Run with the e2e stack: `E2E_NOW=2026-10-21T15:00:00Z NEW_USERS_ENCRYPTED=true docker compose up -d --build`, then `pnpm --filter @wambito/web exec playwright test e2e/migration.spec.ts`. Then the whole `pnpm --filter @wambito/web e2e` stays green (the plain-app specs never see the flow).
- [ ] Commit `test(web): the migration keeps every kind of row`.

### Task 6: Copy, policy, stores and the switch-day runbook

**Files:**
- Modify:
  - `apps/web/app/i18n/messages/{es,en,it,pt}.json`: `legal.privacy.sections.data` and `storage` say the server keeps finance data only as ciphertext and what metadata it still sees (record types, sizes, times, the profile columns, IPs per session); `version` dated the switch day; the date after which no plaintext backup exists is left as `{date}`, filled on the day
  - `docs/privacy-policy.md` (the same in English)
  - the landing FAQ only if a sentence is no longer true (its tests in `apps/web/e2e/landing.spec.ts` pin the text)
  - `apps/mobile/fastlane/metadata/android/*/full_description.txt` (one encryption line)
- Create: `docs/deploy/switch-day.md`, the runbook:
  - the rehearsal: restore the R2 dump into a throwaway local Postgres; the founder decrypts with their age key; migrate through the local stack with the Mailpit link; compare counts and a month's summary; delete the database and the dump; record only counts and totals;
  - the production steps 3–5 of the spec, each with who does it: the flags in the VPS `.env`, the founder's migration, pairing the phone, reconnecting the assistant, deleting the 11 test accounts;
  - the later table-drop PR;
  - the Play data safety answers.
- Modify: `docs/AGENTS.md` (map entry for `docs/deploy/switch-day.md`).
- Test: `pnpm --filter @wambito/web test` (messages tests), `pnpm --filter @wambito/web e2e:landing` (the FAQ and privacy pins).

- [ ] Write the copy and the runbook; run the two test commands; commit `docs: switch-day runbook, and policy and store copy for encrypted accounts`.
