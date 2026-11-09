# E2E stage 2a (web, first half) implementation plan

> **For agentic workers:** execute this plan task by task with subagent-driven development. Write the failing tests first and make one commit per task.

**Goal:** a web account in "preview" keeps its finances only as encrypted records. The browser holds
the plaintext in IndexedDB, computes everything with `packages/core`, and syncs through `/v2/sync`.
Unlocking uses the recovery key. Every other account keeps working exactly as today.

**Architecture:** the demo already swaps the API for a `fetch` replacement (`demo/demo-backend.ts`)
behind `<ApiProvider mode fetch>`, so the screens and `api/queries.ts` stay as they are. This plan
splits that backend into:

- a store interface;
- the in-memory demo store;
- an encrypted store over IndexedDB, with a sync engine.

A third `ApiMode`, `"local"`, serves preview accounts.

**Spec:**
- `docs/superpowers/specs/2026-11-08-end-to-end-encryption-design.md`, sections 4–8, 10 and 13;
- the addendum `docs/superpowers/specs/2026-11-08-e2e-stage-1b-design.md`, which takes precedence.

**Split of the spec's stage 2:**
- **2a (this plan):** records, local store, sync, local computation, the recovery key, device keys,
  and the preview switch.
- **2b (next plan):**
  - passkey PRF unlock and passkey wraps;
  - approving a device (QR, camera, code, number);
  - Settings → Security (passkeys, devices with remove and rotate, new recovery key);
  - the conflict-merge e2e.

## Global constraints

- Follow the root `AGENTS.md` and `apps/web/AGENTS.md`.
  - Copy goes in all four languages (`app.{es,en,it,pt}.json`; `messages.test.ts`).
  - Story titles are parity ids; the new screens are web-only for now and stay out of
    `parity.json`.
- Never log, send or store plaintext outside the browser's IndexedDB. The data key DK is never
  stored; only non-extractable record and dedupe keys, plus the device private key, are kept
  (spec 7.4).
- Signing out deletes that browser's local database and keys.
- Ids are lower-case UUID v7 (`crypto.randomUUID()` gives v4; use a v7 helper). Recurrence
  occurrences use UUID v5 of the rule id and the month (spec 8.1).
- Money is in integer cents.
- New dependencies:
  - `fake-indexeddb`, as a web devDependency, for unit tests;
  - nothing else without a ruling in the ledger.

## Task 1: record schemas and reports in `packages/core`

- `src/records.ts`: one zod schema per record type: `transaction`, `category`, `budget`,
  `recurrence`, `merchant`, `settings` and `account`.
  - Each body is `{ s: 1, ...fields }`, with the fields the DTOs in `schemas.ts` carry today.
  - Also `RECORD_TYPES` and `parseRecord(type, json)`.
- `src/reports.ts`: `byCategory` and `trend`, moved from `apps/web/app/demo/demo-backend.ts` with
  the same results.
  - Their tests are the demo's cases.
  - The demo then imports them.
- Shared JSON fixtures next to the existing `quick-capture/cases.json`, for the Dart port.

## Task 2: a store interface under the demo backend

- `apps/web/app/local/store.ts`: a `FinanceStore` interface with typed get, list, put and delete
  per record type, `transaction(fn)` for atomic multi-writes, and `subscribe`.
- `apps/web/app/local/memory-store.ts`: the demo's in-memory state, behind that interface.
- `apps/web/app/local/backend.ts`:
  - `createLocalBackend(store, now)`, the route logic of `demo-backend.ts` written against
    `FinanceStore`;
  - `demo-backend.ts` becomes the seed plus the memory store.
  - **Gate:** `demo-backend.test.ts` passes unchanged.

## Task 3: the encrypted record store (IndexedDB)

- `apps/web/app/local/db.ts`: a small IndexedDB wrapper.
  - The rule that storage goes only through `stored.ts` gets a documented exception for this
    folder in `apps/web/AGENTS.md`.
  - One object store per record type: decrypted plaintext plus `{ version, keyV }`.
  - `outbox`: pending changes `{ id, type, baseVersion, deleted, fields touched }`.
  - `meta`: the cursor `latest`, the cycle `base`, `keyV`, the user id.
  - `quarantine`: records that failed to open or validate. They are counted, never shown and never
    overwritten.
  - `keys`: non-extractable record and dedupe `CryptoKey`s, plus the device private key.
- `apps/web/app/local/encrypted-store.ts`: a `FinanceStore` over `db.ts`. Each write updates the
  plaintext and adds an outbox entry in one IndexedDB transaction.
- Tests use `fake-indexeddb` and real `@wambito/crypto`.

## Task 4: the sync engine

- `apps/web/app/local/sync.ts`.
- **Push:** the outbox in batches of up to 500, sealed with `sealRecord`. For each result:
  - `{version}` stores the version;
  - `conflict` runs the field-by-field merge from spec section 6, then a re-push (identical content
    takes the server's copy);
  - `not_found` and `id_taken` drop the change and log only the id;
  - 409 or 500 for the whole batch retries with backoff.
- **Pull:** pages with `since`, `base` and `limit=1000`; opens each record and validates it with
  `parseRecord`.
  - A record that fails goes to quarantine.
  - `410 resync_required` wipes the local records and pulls from 0 with `base=0`.
- **Triggers:** on open, on focus, after each write (debounced), and every 60 s while visible. Only
  one run at a time.
- After each run the engine fires the store's `subscribe` listeners, and `ApiProvider`'s scope
  invalidates its queries.
- Unit tests against a fake `/v2` written for the test:
  - paging past a purge;
  - a conflict merge;
  - same content from two devices;
  - quarantine;
  - offline then online.

## Task 5: keys on the web (recovery key and device key)

- `apps/web/app/local/keys.ts`.
  - **`setUpAccount()`:**
    1. make DK, the recovery secret and the device key pair;
    2. `PUT` the recovery wrap first, then the device wrap with its attestation;
    3. derive the record keys and keep them in `keys` (non-extractable);
    4. drop DK from memory.
  - **`unlockWithRecovery(text)`:** `parseRecoveryKey`, `GET /v2/keys`, then `unwrapDataKey` on
    the recovery wrap. Then it adds this browser's device wrap with an attestation, derives the
    keys, and runs a full pull.
  - **Opening the app on a known browser:** the keys in IndexedDB unlock it without asking.
- **Screens** in `apps/web/app/features/vault/`, with stories and copy:
  - `RecoveryKeySetup`: the key in groups of four; download as a `.txt` file; confirm by typing
    four characters back (spec 7.1).
  - `Unlock`: paste or type the recovery key. The other ways of unlocking are listed as "coming
    soon" until 2b.
  - `Locked`: an error state with a retry.
- Guest accounts get DK and a device key, but no recovery key (spec section 10).

## Task 6: the preview switch

- **API:**
  - `GET /v1/me` gains `encryption: "plain" | "preview"`;
  - `preview` applies when the user id is in a new env `E2E_PREVIEW_USER_IDS`, comma-separated,
    unset by default;
  - add it to `config.ts` and `.env.example`, with a CHANGELOG line.
  - A preview account uses `/v2` only. Its `/v1` finance tables stay empty: no migration until
    stage 5.
  - Onboarding seeds no server rows for preview accounts; the client creates the `settings` record
    and the suggested categories as records.
- **Web:**
  - The app layout reads `encryption`. For `preview` it runs setup or unlock before `AppShell`,
    then renders `<ApiProvider mode="local" fetch={backend.fetch}>`.
  - Export, import and assistants show the same "not available yet" note the demo uses.
  - Signing out wipes the local database.
- Regenerate the types.

## Task 7: e2e

- `apps/web/e2e/vault.spec.ts`. The compose file sets `E2E_PREVIEW_USER_IDS` for a dedicated e2e
  user.
  - Sign up, set up the recovery key, add movements, and reload: the movements are still there.
  - A second browser context unlocks with the recovery key and sees the same movements.
  - Go offline in the first context and edit; go online: the second context gets the edit.
  - Sign out: IndexedDB is empty.

## Final

- Run `pnpm lint && pnpm typecheck && pnpm test`, the e2e suites, and the old-name guard.
- Get a whole-branch review.
- Update the `AGENTS.md` maps (`apps/web`, `packages/core`).
