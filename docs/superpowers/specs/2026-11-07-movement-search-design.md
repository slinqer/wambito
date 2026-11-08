# Movement search: design

Date: 2026-11-07. Status: approved in conversation, spec under review.

## Goal

A person can find their movements (expenses and income) in every month: on the phone, on the web
and through an AI assistant over the MCP. "¿Cuánto gasté en almuerzos?" asked to an assistant gets
one exact total, counting the Restaurantes category and every movement whose name or note says
"almuerzo" or a related word.

## What exists today

- `GET /v1/transactions` already filters by `q` (a substring of the name or the note, ignoring case
  and accents, SQL `like` over `translate(lower(...))`), `category`, `status`, `needsReview`,
  `month`, `from`/`to`, newest first, pages with a cursor (`apps/api/src/routes/transactions.ts`).
- Neither the web nor the phone sends `q`; there is no search screen.
- The MCP tool `list_transactions` has `text` (passed as `q`) but defaults to the current month when
  no range is given, so "gastos de café" only sees this month
  (`packages/ai-assistant-tools/src/tools/read.ts`).

## Scope

In: text, kind (expense or income), category and status filters; all months; mobile, web, demo,
MCP. Out: an amount filter, a date range filter in the apps, typo tolerance, semantic search (see
"Later").

## Part 1: API

`GET /v1/transactions` query, additions:

- `kind=expense|income`. Decided by the sign of `amount` (integer cents): negative is an expense,
  positive is income. No join with categories.
- `q` may repeat (`?q=almuerzo&q=corrientazo`), up to 10 terms, each 1–100 characters after trim.
  A movement matches the text filter when any term is in its name or note (same folding as today).
- `category` may repeat, up to 20 ids. A movement matches when it is in any of them.
- `match=all|any`, default `all`.
  - `all`: every given filter must hold (text AND category AND kind AND status...), as today.
  - `any`: text OR category; `kind`, `status`, `needsReview` and the date filters still always
    hold. With only one of text/category given, `any` behaves as `all`.
- `totals=true` adds `totals: { count, expense, income }` to the response: over every matching
  movement (not just the page), `expense` and `income` as positive integer cents. Without it the
  field is absent. The totals ignore `cursor`, so every page reports the same numbers.
- A single `q` or `category` keeps working as before; old clients are unaffected.

Errors: more terms or categories than allowed, or an unknown `kind`/`match`, answer 422
`validation_failed` as the other query errors do.

Recurrences: as today, they are materialized only when `month` is given. A search without `month`
does not create pending occurrences of future months.

Generated files: `apps/web/app/api/schema.d.ts`, `apps/mcp/src/api/schema.d.ts`,
`apps/mobile/lib/api/gen` are regenerated with their commands, never edited.

`CHANGELOG.md` (root), under "Unreleased": the new `kind`, repeated `q`/`category`, `match` and
`totals` on `GET /v1/transactions`.

Tests first, in `apps/api/test/transactions.test.ts`: a mix of expenses and income across months
and categories; `kind` alone and with `q`; several terms; several categories; `match=any` without
double counting a movement that matches both; `totals` across pages and equal on every page;
validation errors; another user's movements never appear.

## Part 2: MCP (`packages/ai-assistant-tools`)

`list_transactions`:

- `text` accepts a string or a list of up to 10 strings; `category` a name or a list of up to 20
  names (resolved with `findCategory` as today, archived included).
- New `kind` (`expense` | `income`) and `match` (`all` | `any`, default `all`).
- Range default: with `text` or `category` and no `month`/`from`/`to`, it searches every month.
  With neither, it keeps defaulting to the current month.
- Always asks the API for `totals` and returns them: in `structured` as `totals` with formatted
  money (the same `money(...)` the other tools use), and as the first line of `text`
  ("12 movimientos · gastos $340.000 · ingresos $0").
- The description tells the assistant: to answer "how much on X", look at the categories first,
  then send the matching categories and the words, synonyms and brands for X with `match: "any"`,
  and use the returned totals rather than adding items up.

The `Wambito` interface (`wambito.ts`), its API client (`apps/mcp/src/api-wambito.ts`) and the
in-memory one (`memory.ts`) gain the same fields. Every API/MCP change is in the changelog line of
Part 1.

Tests first: the tool with the in-memory backend (range default, lists, `match: any`, totals and
their text line) and the API client's query building.

## Part 3 and 4: the search screen (mobile and web)

Same shape on both.

Entry: a magnifier button in the Home header, next to the avatar. Mobile route `/search`; web
`/app/search` (and `/demo/search` in the demo). On wide web screens the sidebar gets "Buscar".

Top of the screen:

- A text field, focused on open.
- Kind: the existing `SegmentedControl`, Todos · Gastos · Ingresos.
- Two chips: Categoría (a sheet with the categories, several can be chosen; a movement in any of
  them matches) and Estado (todos, pagados, pendientes).
- The filters add up (`match=all`); several chosen categories are OR among themselves.

Query: about 300 ms after the last change, when there is text or any filter; every month. Each
request asks for `totals`.

Results:

- First a line with the totals from the server ("12 movimientos · gastos $340.000").
- Then the list grouped by day, with the existing `TransactionRow` and day headings, pending and
  to-review marks included.
- More pages: on scroll on the phone, the existing "Ver más" on the web.
- Tapping a movement opens the same edit sheet as Home; after saving or deleting, the results and
  totals reload.

States:

- Nothing to search yet: Wambi says "Busca por nombre, nota, categoría…".
- No results: "No encontré nada con «almuerzo»".
- No network or a server error: the existing failure row with Reintentar.
- Known limit: movements saved offline and not yet sent are not in the results (they are not on the
  server yet).

State: on the web, in the URL (`?q=almuerzo&kind=expense&category=...&status=...`), so back and
forward work and the link can be kept. On the phone, kept while the screen is open; not cached.

Copy in es, en, it, pt in both apps (web i18n; Flutter `.arb` files).

Demo and stories: `apps/web/app/demo/demo-backend.ts` and `apps/web/app/features/home/story-harness.tsx`
understand `kind`, repeated `q`/`category`, `match` and `totals`, so the screen works in `/demo`
and in Storybook.

Tests first:

- Web: the model that turns filters into query params and back from the URL; stories for empty, no
  results, results, error; an e2e on the demo (type, filter by kind, open a result).
- Mobile: the repository (query building, pages, totals) and widget tests of the screen (empty, no
  results, results, error, filters). No goldens, as in CI.

## Later (not in this spec)

Semantic search, in steps, each only when the previous one falls short:

1. This spec: substring search plus the assistant expanding the words itself. Over the MCP it
   covers most "related" searches with no new model.
2. `pg_trgm`: typo tolerance and ranking by similarity, no model.
3. Embeddings with `pgvector`: its own spec. Open questions: short merchant names embed poorly
   without context, and where the model runs (server or phone) with a free licence for F-Droid.

A movement with no useful word in a wrong category ("Pago QR 4821" in Otros) is better solved by
categorizing well at capture time than by search.
