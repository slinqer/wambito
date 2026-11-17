# Restore after delete on encrypted accounts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A delete on an encrypted account carries its sealed body to the server, so the record can be restored from any device and from the MCP until the 180-day purge.

**Architecture:** The server accepts and returns a sealed body on tombstones (the `records` check and the push schema relax). Both sync engines (TypeScript `packages/vault`, Dart `apps/mobile`) seal the body on a delete push, open it on a pull, store it in a tombstone row (created if the device never had the record), keep counting its key version and re-seal it on rotation. The existing restore route of the local backends then works unchanged.

**Tech Stack:** Hono + zod-openapi + Drizzle (Postgres), TypeScript (`packages/vault`, web IndexedDB store, MCP), Dart/Flutter (sqflite). Vitest with testcontainers; `flutter test`.

**Spec:** `docs/superpowers/specs/2026-11-17-e2e-restore-after-delete-design.md`

## Global Constraints

- The body on a tombstone is sealed exactly like a live record's: `sealRecord` under the current key, same associated data (`ctx(type, id, keyV)`). The server never sees plaintext.
- A live change still must carry a body; a deleted change may carry a body or `null`.
- A deleted change's body goes through the same checks as a live one: base64url, `MIN_RECORD_BODY`, `MAX_RECORD_BODY`.
- The 180-day tombstone purge (`purgeTombstones`, `TOMBSTONE_DAYS`) is unchanged; it removes the row, body and all.
- A tombstone body that fails to open never blocks the delete and never quarantines the record: the tombstone is stored without a body.
- A local unsent edit that meets a server tombstone: the deletion wins and `server_deleted` is reported, as today; the local tombstone keeps the person's latest local body. With no local edit, the server's body is kept.
- An old client's delete (body `null`) is still accepted.
- Reseal of tombstones shares the existing 500-per-pass limit (`RESEAL_LIMIT`).
- The Dart engine is the twin of `packages/vault/src/sync.ts`: same rules, same test cases.
- Generated files are regenerated, never hand-edited: `apps/web/app/api/schema.d.ts` (`pnpm --filter @wambito/web api:types --file`), `apps/mcp/src/api/schema.d.ts` (`pnpm --filter @wambito/mcp api:types`), `apps/mobile/lib/api/gen` (`apps/mobile/scripts/gen-api.sh`).
- Root `CHANGELOG.md` "Unreleased": one line for the API change, mentioning the recurrence effect (spec section 7).
- Write the failing test first. Commits: Conventional Commits, lowercase, no `Co-Authored-By`, stage by path.

## Review Focus

1. A record deleted on device A that device B never had (B paired later, or B is the MCP) — B gets a tombstone row it can restore. Pinned in Tasks 3, 4, 6, 7.
2. A key rotation after a delete — the tombstone body is re-sealed under the new key, and the old key is not dropped while a pushed tombstone body still uses it. Pinned in Tasks 3, 4, 6, 7.
3. A restore of a record whose tombstone came from an old client (no body) — still `not_found`, nothing written, no crash. Pinned in Tasks 5 and 7.
4. A tombstone body sealed under a key version the device does not hold — the delete applies, no quarantine. Pinned in Tasks 4 and 7.
5. An occurrence of a recurring payment deleted on one device — the MCP does not create it again in a later request. Pinned in Task 5.

---

### Task 1: Pin what today's engines do with a tombstone that has a body

Spec section 5: confirmed before the server change ships.

**Files:**
- Test: `packages/vault/src/sync.test.ts`
- Test: `apps/mobile/test/local/sync_test.dart`

**Interfaces:**
- Consumes: the existing fake servers of both test files (a pulled page of `WireRecord`s).
- Produces: nothing new; two tests later tasks keep green.

- [ ] **Step 1: Write the tests**

TypeScript, test `"a pulled tombstone that carries a body still deletes, and quarantines nothing"`: seed a live record locally (pushed, version 1), serve a pull page with `{ id, type, version: 2, deleted: true, keyV: 1, encV: 1, body: <a sealed body of the same record> }`; after `run()`, `store.get(type, id)` is `null`, `store.get(type, id, { includeDeleted: true })?.deleted` is `true`, and the quarantine is empty. Same test in Dart (`'a pulled tombstone that carries a body still deletes, and quarantines nothing'`).

- [ ] **Step 2: Run them**

Run: `pnpm vitest run --project @wambito/vault -t "carries a body"` and, in `apps/mobile`, `flutter test test/local/sync_test.dart --plain-name "carries a body"`.
Expected: PASS on both (they pin current behaviour). If either fails, stop and report: the server change would break that engine.

- [ ] **Step 3: Commit**

```bash
git add packages/vault/src/sync.test.ts apps/mobile/test/local/sync_test.dart
git commit -m "test: pin that both sync engines delete on a pulled tombstone with a body"
```

### Task 2: The server keeps a sealed body on a tombstone

**Files:**
- Modify: `packages/db/src/schema/domain.ts` (the `records` check)
- Create: `packages/db/drizzle/0020_<generated name>.sql` (via `pnpm --filter @wambito/db generate`)
- Modify: `apps/api/src/http/schemas.ts` (push change refine and OpenAPI descriptions)
- Modify: `apps/api/src/services/sync.ts` (doc comments only if behaviour already follows; `pushRecords` must store the body given)
- Regenerate: `apps/web/app/api/schema.d.ts`, `apps/mcp/src/api/schema.d.ts`, `apps/mobile/lib/api/gen`
- Modify: `CHANGELOG.md`
- Test: `apps/api/test/sync.test.ts`

**Interfaces:**
- Produces: `POST /v2/sync` accepts `{ deleted: true, body: string }`; `GET /v2/sync` returns `body` on such tombstones.

- [ ] **Step 1: Write the failing tests** in `apps/api/test/sync.test.ts`:
  - `"a delete may carry its sealed body, and a pull returns it"` — create, then delete with a valid body; pull shows `deleted: true` and the same `body`.
  - `"a delete without a body still works"` — body `null`, pull shows `body: null`.
  - `"a live change without a body is still refused"` — 400.
  - `"a delete's body has the live limits"` — a 1-byte body on a delete is 400.
  - `"an update from a tombstone with a body brings the record back"` — update with `deleted: false`, `baseVersion` = tombstone version; the live count rises by 1 (a push at `MAX_LIVE_RECORDS` is `record_limit`).
  - `"a replay of a delete with a body answers the stored version"`; and a different body with the same `baseVersion` is a conflict.
  - `"the purge removes a tombstone that has a body"`.

- [ ] **Step 2: Run them** — `pnpm vitest run --project @wambito/api test/sync.test.ts`. Expected: the body cases FAIL (400 / check violation).

- [ ] **Step 3: Implement**
  - Check becomes `deleted or body is not null` (constraint name `records_live_body`); generate the migration with drizzle-kit and keep its generated name.
  - Push refine becomes "a live record has a body"; message `"A live record has a body"`. Body descriptions: `"The encrypted record, base64url without padding. Always present on a live record; on a deleted one, null unless the client sent the sealed body so the record can be restored"`.
  - Regenerate the three generated clients; `git diff --exit-code` must show only description changes in them.
  - CHANGELOG, under Unreleased → Changed: `` `/v2/sync`: a deleted record may carry its sealed body, kept until the 180-day purge, so it can be restored from any device and by the assistant; deleted occurrences of a recurring payment are no longer made again on another device. ``

- [ ] **Step 4: Run** — the API tests above, then `pnpm typecheck`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/db apps/api apps/web/app/api/schema.d.ts apps/mcp/src/api/schema.d.ts apps/mobile/lib/api/gen CHANGELOG.md
git commit -m "feat(api): keep a deleted record's sealed body until the purge"
```

### Task 3: TypeScript stores hold a remote tombstone with a body

**Files:**
- Modify: `packages/vault/src/store.ts` (`WriteOptions`)
- Modify: `packages/vault/src/encrypted.ts` (interface docs of `keyVersionsInUse`, `queueReseal`)
- Modify: `packages/vault/src/memory-encrypted-store.ts`, `packages/vault/src/memory-store.ts` if it implements `delete` options
- Modify: `apps/web/app/local/encrypted-store.ts`
- Test: `packages/vault/src/encrypted-contract.ts` (run by `memory-encrypted-store.test.ts` and `apps/web/app/local/encrypted-store.test.ts`)

**Interfaces:**
- Produces: `WriteOptions.tombstoneBody?: Json` — remote deletes only: the tombstone stores this body; when the id is unknown locally, a tombstone row is created with `version` and `keyV` from the options and no outbox entry. `skipIfPending` and `ifSeq` apply as for any remote write.
- Produces: `keyVersionsInUse()` also counts pushed tombstones (`version > 0`) that hold a body. `queueReseal(current, limit)` also queues pushed tombstones with a body under a `keyV` below `current`.

- [ ] **Step 1: Contract cases** in `encrypted-contract.ts`:
  - `"a remote delete with tombstoneBody creates a tombstone for an unknown id"` — `get(..., { includeDeleted: true })` returns `deleted: true` with that body, `version` and `keyV`; `readOutbox` is empty.
  - `"a remote delete with tombstoneBody replaces the local tombstone's body"`.
  - `"a remote delete with tombstoneBody and skipIfPending leaves a pending local change alone"`.
  - `"keyVersionsInUse counts a pushed tombstone with a body"` and `"…not one without a body"`.
  - `"queueReseal queues a pushed tombstone with a body under an older key"`, and its entry is a delete (`deleted: true`).
- [ ] **Step 2: Run** — `pnpm vitest run --project @wambito/vault` and, in `apps/web`, `pnpm exec vitest run --project unit app/local/encrypted-store.test.ts`. Expected: new cases FAIL.
- [ ] **Step 3: Implement** in both stores.
- [ ] **Step 4: Run** the same commands. Expected: PASS.
- [ ] **Step 5: Commit** — `feat(vault): keep a remote tombstone's body and its key version`.

### Task 4: The TypeScript sync engine sends and receives tombstone bodies

**Files:**
- Modify: `packages/vault/src/sync.ts` (`prepare`, the pull's apply loop, `handleConflict`, the set-aside path, the upgrade pass doc comment)
- Test: `packages/vault/src/sync.test.ts`

**Interfaces:**
- Consumes: `WriteOptions.tombstoneBody`, the new `keyVersionsInUse`/`queueReseal` (Task 3).

- [ ] **Step 1: Failing tests** in `sync.test.ts`:
  - `"a delete pushes its sealed body"` — the pushed change has `deleted: true` and a body that `openRecord` turns back into the local body.
  - `"a delete of a record downloaded without a body pushes null"`.
  - `"a pulled tombstone with a body is kept, even for an id this device never had"` — `get(..., { includeDeleted: true }).body` equals the original.
  - `"a pulled tombstone whose body does not open still deletes, without quarantine"` (sealed under a key version the keyring lacks).
  - `"an unsent edit meeting a server tombstone keeps the person's body"` — `server_deleted` reported, tombstone body = the local edit.
  - `"the upgrade pass re-seals a tombstone's body under the new key"` — after rotation, the pushed reseal is `deleted: true` with a body under the new `keyV`; the old key is dropped only after that ack.
- [ ] **Step 2: Run** — `pnpm vitest run --project @wambito/vault src/sync.test.ts`. Expected: new tests FAIL; Task 1's test still PASSES.
- [ ] **Step 3: Implement.** In `prepare`, seal `row.body` whenever it is present, deleted or not (`body: null` only when there is none). On pull, open a tombstone body like a live one; on failure, apply the delete with no `tombstoneBody`. In the conflict and set-aside paths, pass the local body as `tombstoneBody` when the person had an unsent edit, else the server's opened body.
- [ ] **Step 4: Run** — `pnpm vitest run --project @wambito/vault` and, in `apps/web`, `pnpm exec vitest run --project unit app/local`. Expected: PASS.
- [ ] **Step 5: Commit** — `feat(vault): carry a deleted record's sealed body through sync`.

### Task 5: The MCP restores a delete from an earlier request

**Files:**
- Modify: `apps/mcp/test/vault-end-to-end.test.ts` (lines ~159-161: the `not_found` expectation)
- Test: `apps/mcp/test/vault-wambito.test.ts`
- Modify: `packages/vault/AGENTS.md` (drop the "Known limit" bullet; say tombstones carry their body)

The stage 4 spec is history: do not edit it.

- [ ] **Step 1: Failing tests**
  - In `vault-end-to-end.test.ts`, replace the `not_found` assertion: `restore_transactions` with `[id]` succeeds, and `list_transactions` for `"panaderia-e2e"` shows it again with amount 13; the plaintext scan at the end still finds nothing.
  - In `vault-wambito.test.ts`: `"a delete whose tombstone has no body is still not_found"` (seed the fake server with an old-client tombstone).
  - In `vault-wambito.test.ts`: `"an occurrence deleted on another device is not made again"` — seed a recurrence rule and its occurrence's tombstone (with body) for the current month; `list_transactions` for that month does not show it and the next push contains no create for that id.
- [ ] **Step 2: Run** — `pnpm vitest run --project @wambito/mcp test/vault-end-to-end.test.ts test/vault-wambito.test.ts` (Docker running). Expected: restore and occurrence tests FAIL before Task 4 is in, PASS after; if they already pass, say so in the report.
- [ ] **Step 3: Implement** whatever the tests show is missing (expected: nothing beyond Tasks 2–4); update `packages/vault/AGENTS.md`.
- [ ] **Step 4: Run** `pnpm test` from the root. Expected: PASS.
- [ ] **Step 5: Commit** — `test(mcp): restore a delete made in an earlier request`.

### Task 6: Dart store holds a remote tombstone with a body

**Files:**
- Modify: `apps/mobile/lib/local/store.dart` (`WriteOptions`: `tombstoneBody`)
- Modify: `apps/mobile/lib/local/sqlite_store.dart` (`delete` at ~699, `keyVersionsInUse` ~384, `queueReseal` ~346)
- Test: `apps/mobile/test/local/sqlite_store_test.dart`

**Interfaces:**
- Produces: `WriteOptions.tombstoneBody` (`Map<String, Object?>?`), same meaning as Task 3; same `keyVersionsInUse`/`queueReseal` rules.

- [ ] **Step 1: Failing tests** — the six cases of Task 3 Step 1, same names, in `sqlite_store_test.dart`.
- [ ] **Step 2: Run** — `flutter test test/local/sqlite_store_test.dart`. Expected: new cases FAIL.
- [ ] **Step 3: Implement** in `sqlite_store.dart`. No schema change: `body` already stores a tombstone's body.
- [ ] **Step 4: Run** the same. Expected: PASS.
- [ ] **Step 5: Commit** — `feat(mobile): keep a remote tombstone's body and its key version`.

### Task 7: The Dart sync engine sends and receives tombstone bodies

**Files:**
- Modify: `apps/mobile/lib/local/sync.dart` (`prepare` ~514, pull apply ~815, conflict ~545, set-aside ~632/~896)
- Test: `apps/mobile/test/local/sync_test.dart`
- Test: `apps/mobile/test_stack/vault_3b_e2e_test.dart`

- [ ] **Step 1: Failing tests** — the six cases of Task 4 Step 1, same names, in `sync_test.dart`. In the stack e2e: `'a delete on one phone is restored on the other'` — phone A deletes a movement and syncs; phone B (synced before) syncs, then `POST /v1/transactions/{id}/restore` through its local backend, syncs; phone A syncs and sees it live. And `'a restore of an old-client delete is not_found'` (a tombstone pushed with `body: null` through the API).
- [ ] **Step 2: Run** — `flutter test test/local/sync_test.dart`. Expected: new cases FAIL.
- [ ] **Step 3: Implement** as in Task 4.
- [ ] **Step 4: Run** — `flutter analyze`, `flutter test --exclude-tags golden,stack`, then `apps/mobile/scripts/run-vault-e2e.sh` with the root stack up. Expected: all PASS.
- [ ] **Step 5: Commit** — `feat(mobile): carry a deleted record's sealed body through sync`.
