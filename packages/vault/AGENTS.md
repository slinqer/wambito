# packages/vault (`@wambito/vault`)

The vault code that runs without a browser, shared by the web and the MCP. No browser API inside
(no `indexedDB`, `window`, `navigator`, `BroadcastChannel`, Web Locks).

## Entry points

- `src/index.ts` re-exports the public names; `./contract` (`src/contract.ts`: `storeContract`, `encryptedStoreContract`) is a
  second entry because it imports `vitest`: production code never imports it.
- `src/store.ts`: `FinanceStore`, `StoreOps`, `StoredRecord`, `ReadOptions`, `WriteOptions`,
  `RecordBodies`, `RecordType`.
- `src/memory-store.ts`: `createMemoryStore()`. `src/store-contract.ts`: `storeContract(name, make)`,
  the tests every store must pass.
- `src/encrypted.ts`: `EncryptedStore` (a `FinanceStore` plus outbox, quarantine, meta and keys) and
  its types (`RawRecord`, `OutboxEntry`, `OutboxPark`, `QuarantineEntry`, `SetAsideOutcome`),
  `changedKeys`, `VaultClosedError`. `src/encrypted-contract.ts`: `encryptedStoreContract(name, make)`;
  the IndexedDB-only cases (other tabs, `deleteVault`, non-extractable keys) stay in the web's test.
- `src/keyring.ts`: `Keyring`, `recordKeyName`, `dedupeKeyName`, `KeysError`.
- `src/sync.ts`: `createSyncEngine` over an `EncryptedStore`; option `upgrade: false` skips the
  re-seal pass (the MCP). Its tests stay in `apps/web/app/local/sync.test.ts` (over IndexedDB).
- `src/ids.ts`: `uuidv7`, `uuidv5`.
- `src/backend.ts`: `createLocalBackend` (the `/v1` routes over a store, one store transaction per
  request), `DEMO_UNAVAILABLE`. Its round-trip tests need the web's typed API client, so they stay in
  `apps/web/app/local/backend.test.ts`.

## Test

`pnpm vitest run --project @wambito/vault`; typecheck: `pnpm --filter @wambito/vault typecheck`.
