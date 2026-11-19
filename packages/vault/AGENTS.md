# packages/vault (`@wambito/vault`)

The vault code that runs without a browser, shared by the web and the MCP. Nothing inside needs a
browser: no `indexedDB`, `window`, `navigator` or `BroadcastChannel`. The one exception is
`sync.ts`, which touches Web Locks, `document` visibility and `window` focus only behind `typeof`
guards; they are no-ops in Node (the MCP calls `run()` only, never `start()`). `"DOM"` stays in the
tsconfig `lib` for types only (`CryptoKey`, `BufferSource`, `RequestInfo`).

## Entry points

- `src/index.ts` re-exports the public names; `./contract` (`src/contract.ts`: `storeContract`,
  `encryptedStoreContract`) is a second entry because it imports `vitest`: production code never
  imports it.
- `src/store.ts`: `FinanceStore`, `StoreOps`, `StoredRecord`, `ReadOptions`, `WriteOptions`,
  `RecordBodies`, `RecordType`.
- `src/memory-store.ts`: `createMemoryStore()`. `src/store-contract.ts`: `storeContract(name, make)`,
  the tests every store must pass.
- `src/encrypted.ts`: `EncryptedStore` (a `FinanceStore` plus outbox, quarantine, meta and keys) and
  its types (`RawRecord`, `OutboxEntry`, `OutboxPark`, `QuarantineEntry`, `SetAsideOutcome`),
  `changedKeys`, `VaultClosedError`. `src/encrypted-contract.ts`: `encryptedStoreContract(name, make)`;
  the IndexedDB-only cases (other tabs, `deleteVault`, non-extractable keys) stay in the web's test.
  Every store has `resetAll()`: records, quarantine, the whole outbox and the `latest`/`base`
  cursors go, keys and the other meta (`keyV`, `userId`, `deviceWrapId`) stay (the switch day's
  retry after `cancel`, with the same data key).
- `src/memory-encrypted-store.ts`: `createMemoryEncryptedStore(userId)`, the in-process
  `EncryptedStore` (the MCP's, per request); passes both contracts.
- `src/keyring.ts`: `Keyring`, `recordKeyName`, `dedupeKeyName`, `KeysError`.
- `src/sync.ts`: `createSyncEngine` over an `EncryptedStore`; option `upgrade: false` skips the
  re-seal pass (the MCP). Its tests stay in `apps/web/app/local/sync.test.ts` (over IndexedDB);
  `src/sync.test.ts` is a smoke test over the memory store.
- `src/migration.ts`: the switch day (stage 5, a plain account becomes encrypted from the web):
  `MigrationSource` / `MigrationCounts` (the JSON of `/v2/migration/source`, `start` and
  `finish`), `recordsFromSource(source, userId)` (every row to a `MigrationRecord` with the server's
  id, each body checked by `parseRecord`; dates `YYYY-MM-DD` to `YYYY-MM` for `occurrenceMonth` and
  `effectiveFrom`, `accountId` null, recurrences at `rev` 0; a dismissed month, soft-deleted
  pending `source: "recurrence"`, takes `uuidv5(recurrenceId, "<YYYY-MM>:0")` as the backend's
  `materialize` expects), `countsOf(records)` (live per type, deleted transactions apart, the
  settings not counted), `SETTINGS_SEED_NAMESPACE` and `settingsRecordId(userId)` (the web's seed
  uses the same namespace). Tests: `src/migration.test.ts`.
- `src/ids.ts`: `uuidv7`, `uuidv5`, `IDEMPOTENCY_NAMESPACE` (ids derived from an `Idempotency-Key`).
- `src/backend.ts`: `createLocalBackend` (the `/v1` routes over a store, one store transaction per
  request), `DEMO_UNAVAILABLE`. Its round-trip tests need the web's typed API client, so they stay in
  `apps/web/app/local/backend.test.ts`.
  Options for the MCP: `source: "mcp"` (forced on every created movement) and
  `idsFromIdempotencyKey: { userId }` (batch ids stable across retries); it also answers the batch
  create and batch-delete routes and `Idempotent-Replayed`. Their tests: `src/backend-mcp.test.ts`,
  and through `apiWambito` in `apps/mcp/test/local-backend.test.ts`.

## Users

- The web (IndexedDB store, browser hooks on) and the MCP (`apps/mcp/src/vault-wambito.ts`: the
  memory store, a sync engine fed by a cache of ciphertext, `run()` only, `upgrade: false`, the local
  backend with `source: "mcp"`). A change to the sync engine, the stores or the backend is a change
  to both: run `apps/mcp/test/vault-wambito.test.ts` and `vault-end-to-end.test.ts` too. Design:
  `docs/superpowers/specs/2026-11-16-e2e-stage-4-mcp-design.md`.
- A delete carries its sealed body to the server, kept until the server's 180-day purge, so
  `restore_transactions` works across requests and devices. The MCP's cache replay includes
  tombstones, so a later request still sees (and can restore) a delete, and a deleted recurrence
  occurrence is not made again.

## Test

`pnpm vitest run --project @wambito/vault`; typecheck: `pnpm --filter @wambito/vault typecheck`.
