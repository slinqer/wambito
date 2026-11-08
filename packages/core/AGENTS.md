# packages/core (`@wambito/core`)

Shared domain logic for the API and web: money, currencies, dates, budgets, recurrence, summaries,
suggested categories, Wambi's messages. No I/O.

## Entry points

- `src/index.ts` re-exports everything.
- `src/money.ts`, `src/currencies.ts`, `src/default-currency.ts`: integer cents, never floats.
- `src/budget.ts`, `src/recurrence.ts`, `src/summary.ts`, `src/dates.ts`, `src/schemas.ts` (zod).
- `src/movement-search.ts`: the shared movement matcher and totals (`matchesMovementSearch`,
  `movementTotals`) used by the MCP in-memory backend and the web demo/stories, and the fold table
  (`FOLD_FROM`/`FOLD_TO`, `foldText`) the API's SQL search uses.
- `src/wambi-message.ts`: `wambiMessage`, the rule-based lines of the mascot.
- `src/capture.ts` (+ `src/capture-sources.ts`): automatic capture from bank notifications:
  `CAPTURE_SOURCES` (`revolut`, `google_wallet`), `createCaptureSchema` (`POST /v1/captures`),
  `reviewTransactionsSchema` (1–50 ids), `FALLBACK_CATEGORY_NAMES`, `merchantKey` (the merchant
  memory's key). The privacy policy's `capture` section (`apps/web`, four languages) describes what
  reaches the server: changing these fields means changing it too.
- `quick-capture/cases.json` (+ `cases.schema.json`, `README.md`): shared cases for the phrase
  parser. There is no parser here: `src/quick-capture-cases.test.ts` only validates the file; the
  Dart parser runs every case in `apps/mobile/test/capture/parser_cases_test.dart`.

## Test

- `pnpm vitest run --project @wambito/core`.

## Rules

- Money slang (see root `AGENTS.md`) lives in `quick-capture/`: never change it.
- Changing `cases.json` changes what the mobile parser must accept: run
  `flutter test test/capture/parser_cases_test.dart` in `apps/mobile` too.
