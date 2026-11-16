# packages/vault (`@wambito/vault`)

The vault code that runs without a browser, shared by the web and the MCP. No browser API inside
(no `indexedDB`, `window`, `navigator`, `BroadcastChannel`, Web Locks).

## Entry points

- `src/index.ts` re-exports the public names; `./contract` (`src/store-contract.ts`) is a second
  entry because it imports `vitest`: production code never imports it.
- `src/store.ts`: `FinanceStore`, `StoreOps`, `StoredRecord`, `ReadOptions`, `WriteOptions`,
  `RecordBodies`, `RecordType`.
- `src/memory-store.ts`: `createMemoryStore()`. `src/store-contract.ts`: `storeContract(name, make)`,
  the tests every store must pass.
- `src/ids.ts`: `uuidv7`, `uuidv5`.
- `src/backend.ts`: `createLocalBackend` (the `/v1` routes over a store, one store transaction per
  request), `DEMO_UNAVAILABLE`. Its round-trip tests need the web's typed API client, so they stay in
  `apps/web/app/local/backend.test.ts`.

## Test

`pnpm vitest run --project @wambito/vault`; typecheck: `pnpm --filter @wambito/vault typecheck`.
