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
- `src/memory-encrypted-store.ts`: `createMemoryEncryptedStore(userId)`, the in-process
  `EncryptedStore` (the MCP's, per request); passes both contracts.
- `src/keyring.ts`: `Keyring`, `recordKeyName`, `dedupeKeyName`, `KeysError`.
- `src/sync.ts`: `createSyncEngine` over an `EncryptedStore`; option `upgrade: false` skips the
  re-seal pass (the MCP). Its tests stay in `apps/web/app/local/sync.test.ts` (over IndexedDB); `src/sync.test.ts` is a smoke
  test over the memory store.
- `src/ids.ts`: `uuidv7`, `uuidv5`.
- `src/backend.ts`: `createLocalBackend` (the `/v1` routes over a store, one store transaction per
  request), `DEMO_UNAVAILABLE`. Its round-trip tests need the web's typed API client, so they stay in
  `apps/web/app/local/backend.test.ts`.

## Test

`pnpm vitest run --project @wambito/vault`; typecheck: `pnpm --filter @wambito/vault typecheck`.
