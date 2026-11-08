# Movement search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Search movements in every month by text, kind, category and status, on the phone, the web
and over the MCP, with exact totals from the server.

**Architecture:** `GET /v1/transactions` gains `kind`, repeated `q`/`category`, `match` and
`totals`. One shared matcher in `@wambito/core` keeps the JS backends (MCP in-memory, web demo,
web stories) identical to the API's SQL. The MCP tool passes lists and returns totals; the web and
the phone get a search screen that reuses Home's rows, day headings and edit sheet.

**Tech Stack:** Hono + `@hono/zod-openapi` + Drizzle (API), Vitest + testcontainers, React Router +
TanStack Query (web), Flutter + Riverpod + dart-dio generated client (mobile).

**Spec:** `docs/superpowers/specs/2026-11-07-movement-search-design.md`

## Global Constraints

- Money is integer cents; `totals.expense` and `totals.income` are positive cents.
- Kind is the sign of `amount`: `< 0` expense, `> 0` income.
- `q`: up to 10 terms, each 1–100 characters after trim. `category`: up to 20 uuids.
- `match`: `all` (default) or `any`; `any` is text OR category, every other filter still holds.
- `totals` ignore `cursor`: every page reports the same numbers.
- No `month` → no recurrence materialization.
- Generated files are regenerated with their commands, never edited (root `AGENTS.md`).
- Root `CHANGELOG.md`, "Unreleased": one line for the API + MCP change.
- Copy in es, en, it, pt in both apps. Everything in the repo in English.
- Commits: `feat(api): …`, `feat(mcp): …`, `feat(web): …`, `feat(mobile): …`; stage by path; no
  `Co-Authored-By` line.
- Tests first in every task.

## Review Focus

1. Accents and case: "cafe" finds "Café" and "CAFÉ" in the API, the in-memory MCP backend, the demo
   and the stories alike (one fold table in core). Test in Task 1 and Task 2.
2. Typing fast: an older response arriving after a newer one must not replace the newer results.
   Web: the query key carries the filters. Mobile: test in Task 7.
3. Editing or deleting a result from the search screen updates its list and its totals. Tests in
   Task 5 (web) and Task 8 (mobile).
4. Text that is only spaces is no search: no request, the empty state stays. Tests in Task 4 and
   Task 7.
5. `%`, `_` and `\` in the text are literal characters, not wildcards (already escaped in SQL; the
   new multi-term path must keep it). Test in Task 2.

---

### Task 1: Shared movement matcher in core

**Files:**
- Create: `packages/core/src/movement-search.ts`, `packages/core/src/movement-search.test.ts`
- Modify: `packages/core/src/index.ts` (export it)

**Interfaces:**
- Produces:
  - `FOLD_FROM: string`, `FOLD_TO: string`: the accented letters and their plain ones, the table
    the API's `ACCENTED`/`PLAIN` hold today in `apps/api/src/routes/transactions.ts` (move it here
    unchanged).
  - `foldText(text: string): string`: lower case, then `FOLD_FROM`→`FOLD_TO`.
  - `type MovementKind = "expense" | "income"`
  - `interface MovementSearch { terms?: string[]; categoryIds?: string[]; kind?: MovementKind; status?: "paid" | "pending"; match?: "all" | "any" }`
  - `matchesMovementSearch(tx: { name: string; note: string | null; categoryId: string; amount: number; status: "paid" | "pending" }, s: MovementSearch): boolean`
  - `interface MovementTotals { count: number; expense: number; income: number }`
  - `movementTotals(rows: { amount: number }[]): MovementTotals`

- [ ] **Step 1: Write the failing tests** in `movement-search.test.ts`:
  - `foldText("CAFÉ Ñandú")` is `"cafe nandu"`.
  - a term matches when it is in the name or the note after folding (`["cafe"]` matches name
    `"Café Juan Valdez"`; `["valdez"]` matches note `"con Valdez"`).
  - several terms: any one is enough.
  - several categories: any one is enough.
  - `match: "all"` with terms and categories needs both; `match: "any"` needs one.
  - `kind: "expense"` keeps `amount < 0` only; `"income"` keeps `> 0`; it holds under `any` too.
  - `status` holds under `any` too.
  - empty `MovementSearch` matches everything.
  - `movementTotals([{amount:-500},{amount:-250},{amount:1000}])` is
    `{ count: 3, expense: 750, income: 1000 }`.
- [ ] **Step 2: Run** `pnpm --filter @wambito/core test movement-search` — FAIL (module missing).
- [ ] **Step 3: Implement** the module. Terms are compared already trimmed and folded; an empty
  list means "no filter".
- [ ] **Step 4: Run** the same command — PASS. Then `pnpm --filter @wambito/core typecheck`.
- [ ] **Step 5: Commit** `feat(core): shared movement search matcher`.

### Task 2: API filters, totals, changelog, generated types

**Files:**
- Modify: `apps/api/src/routes/transactions.ts` (`listQuery`, the `/v1/transactions` handler,
  `TransactionPage`; use `foldText`/`FOLD_FROM`/`FOLD_TO` from core in place of the local copy)
- Test: `apps/api/test/transactions.test.ts`
- Modify: `CHANGELOG.md` (root, "Unreleased")
- Regenerate: `apps/web/app/api/schema.d.ts`, `apps/mcp/src/api/schema.d.ts`, `apps/mobile/lib/api/gen`
- Modify: mobile callers of `listTransactions(category: …)` (e.g.
  `apps/mobile/lib/budgets/category_detail_screen.dart` or its repository) to the new list type

**Interfaces:**
- Consumes: Task 1 `foldText`, `FOLD_FROM`, `FOLD_TO`.
- Produces (HTTP): query `kind?: "expense"|"income"`, `q?: string[]` (repeated), `category?: string[]`
  (repeated), `match?: "all"|"any"`, `totals?: "true"|"false"`; response
  `{ items, nextCursor, totals?: { count: number; expense: number; income: number } }`.

- [ ] **Step 1: Write the failing tests** (seed one user with expenses and income over three months
  and two categories, plus another user's rows):
  - `kind=expense` returns only negative amounts, across months, newest first.
  - `kind=income&q=sueldo` returns only income named like "sueldo".
  - `q=almuerzo&q=corrientazo` returns both kinds of names.
  - `category=A&category=B` returns rows of A and B.
  - `match=any&category=A&q=almuerzo` returns rows in A plus rows named "almuerzo" elsewhere, each
    once; `match=all` with the same returns only A rows named "almuerzo".
  - `totals=true` with `limit=2` over 5 matches: `totals.count === 5` on page 1 and on page 2 (via
    `nextCursor`), `expense`/`income` positive cents equal to the seeded sums.
  - without `totals`, the response has no `totals` key.
  - `q=50%` matches only a name containing `50%`, not every name; `q=a_b` likewise.
  - 11 `q` terms, a 101-character term, 21 categories, `kind=other`, `match=some` → 422
    `validation_failed`.
  - a single `q=cafe` and a single `category=<id>` behave as before; "cafe" finds "Café".
  - the other user's rows never appear, in items or in totals.
  - a request without `month` creates no pending recurrence rows.
  - the OpenAPI document (`/openapi.json` or however the existing tests read it) declares `q` and
    `category` as `type: array` with `style: form, explode: true`.
- [ ] **Step 2: Run** `pnpm --filter @wambito/api test transactions` — FAIL on the new cases.
- [ ] **Step 3: Implement.**
  - Hono hands a single value as a string and several as an array: define `q` and `category` as
    `z.preprocess((v) => (typeof v === "string" ? [v] : v), z.array(…).max(N))`, and check the
    OpenAPI output stays a plain array (the doc test above). If the generator cannot emit it from
    `preprocess`, set `.openapi({ type: "array", items: …, style: "form", explode: true })` on the param.
  - Text: `or(...terms.map(term => or(name like, note like)))` with the existing escaping.
  - Category: `inArray(transactions.categoryId, ids)`.
  - `match=any` and both given: `or(textCondition, categoryCondition)`; otherwise push each.
  - Kind: `lt(transactions.amount, 0)` / `gt(transactions.amount, 0)`.
  - Totals: a second select over the same filters minus the cursor:
    `count(*)`, `sum(-amount) filter (where amount < 0)`, `sum(amount) filter (where amount > 0)`,
    coalesced to 0, in the same `withUser` transaction.
- [ ] **Step 4: Run** the API tests — PASS. Then `pnpm --filter @wambito/api typecheck`.
- [ ] **Step 5: Changelog line** under "Unreleased": "`GET /v1/transactions`: `kind`
  (expense/income), `q` and `category` may repeat, `match=all|any`, `totals=true` adds the count
  and sums of every match."
- [ ] **Step 6: Regenerate** `pnpm --filter @wambito/web api:types --file`,
  `pnpm --filter @wambito/mcp api:types`, `apps/mobile/scripts/gen-api.sh`; fix the mobile callers
  the new `category`/`q` list types break; `pnpm typecheck` and
  `flutter analyze` (in `apps/mobile`) pass.
- [ ] **Step 7: Commit** `feat(api): search transactions by kind, several words or categories, with totals`.

### Task 3: MCP `list_transactions`

**Files:**
- Modify: `packages/ai-assistant-tools/src/wambito.ts` (`TransactionQuery`, `listTransactions` return)
- Modify: `apps/mcp/src/api-wambito.ts` (query mapping)
- Modify: `packages/ai-assistant-tools/src/memory.ts` (use `matchesMovementSearch`, `movementTotals`)
- Modify: `packages/ai-assistant-tools/src/tools/read.ts` (`listTransactions` tool)
- Modify: phrases for the totals line in the tools' locale file (where `phrases(locale)` lives), es/en/it/pt
- Test: the existing tests of `read.ts` tools and of `api-wambito.ts`

**Interfaces:**
- Consumes: Task 1 matcher and totals; Task 2 HTTP params.
- Produces: `TransactionQuery` becomes
  `{ month?; from?; to?; categoryIds?: string[]; kind?: MovementKind; match?: "all"|"any"; status?; needsReview?; q?: string[]; cursor?; limit: number; totals?: boolean }`;
  `listTransactions` returns `{ items; nextCursor; totals?: MovementTotals }`.
  Tool input: `text?: string | string[]` (≤10), `category?: string | string[]` (≤20 names),
  `kind?`, `match?`. Tool output: `{ items, nextCursor, totals: { count, expense, income } }` with
  `expense`/`income` as the tools' formatted money objects.

- [ ] **Step 1: Write the failing tests** (in-memory backend):
  - `text: "cafe"` with no range finds a "Café" movement of three months ago.
  - no `text`, no `category`, no range → only the current month (unchanged).
  - `category: ["Restaurantes"], text: ["almuerzo","corrientazo"], match: "any", kind: "expense"`
    returns the union once; `totals.count` equals the union's size; the first `text` line is the
    totals line (Spanish profile: `"3 movimientos · gastos $45.000 · ingresos $0"`, formatted as the
    other tools format money).
  - an unknown category name in the list throws the same error as a single unknown one today.
  - the API client sends repeated `q`/`category`, `kind`, `match` and `totals=true`.
- [ ] **Step 2: Run** `pnpm --filter @wambito/ai-assistant-tools test` and
  `pnpm --filter @wambito/mcp test` — FAIL on the new cases.
- [ ] **Step 3: Implement.** The tool always asks for totals. Range default: current month only
  when there is no `text`, no `category` and no `month`/`from`/`to`. Description adds, in English:
  "To answer how much was spent on something, list the categories first, then send the matching
  categories and the words, synonyms and brands for it with match: \"any\", and use totals instead
  of adding items up." `memory.ts` filters with `matchesMovementSearch` and computes totals over all
  matches before paging.
- [ ] **Step 4: Run** both test commands — PASS; `pnpm typecheck`.
- [ ] **Step 5: Commit** `feat(mcp): list_transactions searches several words and categories, with totals`.

### Task 4: Web search model, query hook and JS backends

**Files:**
- Create: `apps/web/app/features/search/search-model.ts`, `search-model.test.ts`
- Modify: `apps/web/app/api/queries.ts` (`useTransactionSearch`, its key)
- Modify: `apps/web/app/demo/demo-backend.ts`, `apps/web/app/demo/demo-backend.test.ts`
- Modify: `apps/web/app/features/home/story-harness.tsx`
- Modify: `apps/web/app/features/home/home-model.ts` (+ test): `groupNewestFirst`

**Interfaces:**
- Consumes: Task 1 matcher/totals; Task 2 generated `paths` types.
- Produces:
  - `interface SearchFilters { text: string; kind: "all" | "expense" | "income"; categoryIds: string[]; status: "all" | "paid" | "pending" }`
  - `emptyFilters: SearchFilters`
  - `filtersFromParams(p: URLSearchParams): SearchFilters` / `filtersToParams(f: SearchFilters): URLSearchParams`
    (keys `q`, `kind`, `category` repeated, `status`; defaults omitted)
  - `isSearching(f: SearchFilters): boolean` (trimmed text non-empty or any filter set)
  - `toApiQuery(f: SearchFilters): { q?: string[]; kind?; category?: string[]; status?; totals: "true"; limit: 50 }`
  - `useTransactionSearch(f: SearchFilters)`: infinite query, disabled when `!isSearching(f)`,
    key `[...queryKeys.transactions-prefix, "search", filtersToParams(f).toString()]` so the
    existing invalidations after create/update/delete also refresh it (confirm the prefix the
    mutations invalidate in `optimistic.ts`/`keysFor` and use it).
  - `groupNewestFirst(items: TransactionDto[], today: string): DayGroup[]`: days in API order
    (newest first), `when` as `groupByDay` computes it.

- [ ] **Step 1: Write the failing tests:**
  - URL round trip of a full filter set; defaults give an empty query string.
  - `isSearching({ ...emptyFilters, text: "   " })` is false; `kind: "income"` alone is true.
  - `toApiQuery` trims text and sends it as one term; omits `all` values.
  - `groupNewestFirst` keeps a future pending day above older days when it is newer (no "upcoming
    at the bottom" reordering).
  - demo backend: `kind`, repeated `q`/`category`, `match`, `totals` give the same answers as the
    API tests' core cases (a short mirror: one test per param), and `q=cafe` finds "Café".
- [ ] **Step 2: Run** `pnpm --filter @wambito/web test search-model home-model demo-backend` — FAIL.
- [ ] **Step 3: Implement.** Demo backend and story harness parse the params with
  `URLSearchParams.getAll` and filter with `matchesMovementSearch`, totals with `movementTotals`
  before paging.
- [ ] **Step 4: Run** the same — PASS; `pnpm --filter @wambito/web typecheck`.
- [ ] **Step 5: Commit** `feat(web): search model, query and demo support`.

### Task 5: Web search screen

**Files:**
- Create: `apps/web/app/features/search/Search.tsx`, `Search.stories.tsx`, `Search.test.tsx` (if the
  folder's convention has component tests; otherwise stories + e2e only)
- Create: `apps/web/app/routes/app.search.tsx`
- Modify: `apps/web/app/routes.ts` (`search` under `/app` and under `demo` with id `demo-search`)
- Modify: `apps/web/app/features/home/HomeHeader.tsx` (magnifier link), `apps/web/app/ui/Sidebar.tsx`
  (a `search` link)
- Modify: `apps/web/app/i18n/messages/app.{es,en,it,pt}.json` (`search.*`, `nav.search`),
  `apps/web/app/i18n/screen-meta.ts` (title)
- Test: an e2e spec next to the existing ones (`apps/web/e2e/…`), on `/demo/search`

**Interfaces:**
- Consumes: Task 4 everything; Home's `Day`, `ShowMore`, `TransactionRow`, `SegmentedControl`,
  `CategoryChip`, `Sheet`, `PageHeader`, `ScreenError`/failure row, `WambiBubble`.

Copy (es; translate the others):
`search.title` "Buscar", `search.placeholder` "Busca por nombre o nota",
`search.kind_all` "Todos", `search.kind_expense` "Gastos", `search.kind_income` "Ingresos",
`search.category` "Categoría", `search.status` "Estado", `search.status_all` "Todos",
`search.status_paid` "Pagados", `search.status_pending` "Pendientes",
`search.hint` "Busca por nombre, nota, categoría…",
`search.none` "No encontré nada con «{text}»", `search.none_filters` "No encontré nada con esos filtros",
`search.totals` "{count, plural, one {# movimiento} other {# movimientos}} · gastos {expense} · ingresos {income}",
`nav.search` "Buscar".

- [ ] **Step 1: Write the failing e2e** on `/demo/search`: typing a demo name shows its row and a
  totals line; choosing Ingresos hides the expenses; opening a row shows the edit sheet; deleting it
  removes it and the totals count drops by one; going back to Home and forward restores the URL's
  filters.
- [ ] **Step 2: Run** the e2e (`pnpm --filter @wambito/web e2e` with the pinned-clock stack, see
  `apps/web/AGENTS.md`) — FAIL.
- [ ] **Step 3: Implement** the screen: filters from/to the URL (`useSearchParams`, replace on each
  change), text debounced 300 ms before it reaches the URL, the category sheet with every category
  (archived ones last, marked), results with `groupNewestFirst` + `Day`, `ShowMore`, the states of
  the spec (hint, none, error with Reintentar).
- [ ] **Step 4: Stories** for hint, results, none, error; run the e2e — PASS; `pnpm lint`,
  `pnpm --filter @wambito/web typecheck`, `pnpm --filter @wambito/web test`.
- [ ] **Step 5: Commit** `feat(web): search screen`.

### Task 6: Mobile search repository

**Files:**
- Create: `apps/mobile/lib/search/search_repository.dart`, `apps/mobile/test/search/search_repository_test.dart`
- Modify: `apps/mobile/lib/home/day_groups.dart` (+ `test/home/day_groups_test.dart`): `groupNewestFirst`

**Interfaces:**
- Consumes: Task 2 generated `listTransactions` (list params, `kind`, `match`, `totals`) and
  `TransactionPage.totals`.
- Produces:
  - `enum SearchKind { all, expense, income }`, `enum SearchStatus { all, paid, pending }`
  - `class SearchFilters { final String text; final SearchKind kind; final Set<String> categoryIds; final SearchStatus status; bool get isSearching; }` with value equality
  - `class SearchTotals { final int count; final int expense; final int income; }`
  - `class SearchPage { final List<Transaction> items; final String? nextCursor; final SearchTotals totals; }`
  - `abstract interface class SearchRepository { Future<SearchPage> search(SearchFilters f, {String? cursor}); }`
  - `ApiSearchRepository`, `searchRepositoryProvider`; failures as `HomeFailure.fromDio`
  - `List<DayGroup> groupNewestFirst(List<Transaction> items, String today)`

- [ ] **Step 1: Write the failing tests** (fake Dio adapter, as `home_repository_test.dart` does):
  sends trimmed text as one `q`, repeated `category`, `kind`, `status`, `totals=true`,
  `limit=50`, no `month`; omits `all` values; maps totals; a Dio error becomes `HomeFailure`;
  `SearchFilters(text: "  ").isSearching` is false; `groupNewestFirst` order as in Task 4.
- [ ] **Step 2: Run** `flutter test test/search test/home/day_groups_test.dart` — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — PASS; `flutter analyze`.
- [ ] **Step 5: Commit** `feat(mobile): search repository`.

### Task 7: Mobile search controller

**Files:**
- Create: `apps/mobile/lib/search/search_controller.dart`, `apps/mobile/test/search/search_controller_test.dart`

**Interfaces:**
- Consumes: Task 6.
- Produces: `searchControllerProvider` (auto-dispose `Notifier<SearchState>`), with
  `SearchState { SearchFilters filters; List<Transaction> items; SearchTotals? totals; String? nextCursor; bool loading; bool loadingMore; HomeFailure? failure; }` and methods
  `setText(String)`, `setKind(SearchKind)`, `setCategories(Set<String>)`, `setStatus(SearchStatus)`,
  `loadMore()`, `retry()`, `refresh()`.

- [ ] **Step 1: Write the failing tests** (fake repository, fake clock / `fakeAsync`):
  - `setText` searches once 300 ms after the last call, not per keystroke.
  - a filter change (kind, categories, status) searches at once.
  - an older response arriving after a newer one is dropped (generation counter).
  - only spaces → no call, state is idle (`items` empty, `totals` null).
  - `loadMore` appends and keeps the totals; a failure keeps the items and sets `failure`.
  - `refresh()` reloads the first page with the same filters.
- [ ] **Step 2: Run** `flutter test test/search/search_controller_test.dart` — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `feat(mobile): search controller`.

### Task 8: Mobile search screen

**Files:**
- Create: `apps/mobile/lib/search/search_screen.dart`, `apps/mobile/test/search/search_screen_test.dart`
- Modify: `apps/mobile/lib/router.dart` (`GoRoute(path: '/search', …)`)
- Modify: `apps/mobile/lib/home/home_header.dart` (magnifier `Pressable`, semantics "Buscar", pushes `/search`)
- Modify: `apps/mobile/lib/l10n/app_{es,en,it,pt}.arb` (same keys and copy as Task 5, camelCase:
  `searchTitle`, `searchPlaceholder`, `searchKindAll`, …, `searchTotals` with ICU plural)
- Modify: `apps/mobile/AGENTS.md` (map: `lib/search`), `docs/mobile/parity.md` (the new screen)

**Interfaces:**
- Consumes: Task 7 controller; `openEditSheet(context, tx)` from `lib/add/add_sheet.dart`;
  `TransactionRow`, `DayHeading`, `SegmentedControl`, `CategoryChip`, `Sheet`, `PageHeader`,
  `FailureRow`, `WambiBubble`, `PendingBadge`.

- [ ] **Step 1: Write the failing widget tests** (fake repository through the provider):
  hint state on open with the field focused; typing shows rows grouped by day and the totals line;
  Ingresos hides expenses; the category sheet selects two categories and both are sent; no results
  shows `searchNone` with the text; a failure shows the failure row and Reintentar searches again;
  scrolling to the end loads the next page; after `openEditSheet` returns (fake: the row was
  deleted), the list and the totals reload; the Home header's magnifier opens `/search`.
- [ ] **Step 2: Run** `flutter test test/search` — FAIL.
- [ ] **Step 3: Implement** (`flutter pub get` regenerates l10n).
- [ ] **Step 4: Run** `flutter test` (without goldens, as CI) and `flutter analyze` — PASS.
- [ ] **Step 5: Commit** `feat(mobile): search screen`.

### Task 9: Whole-branch check

- [ ] `pnpm lint`, `pnpm typecheck`, `pnpm test`, the web e2e suites, `flutter analyze`,
  `flutter test` in `apps/mobile`, `scripts/check-old-name.sh`, and the generated-file checks of CI
  (`git diff --exit-code` after `tokens`, both `api:types`, `gen-api.sh`).
- [ ] Try it: `/demo/search` in the browser preview, and the phone screen in the emulator.
