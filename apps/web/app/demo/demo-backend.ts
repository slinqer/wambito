import {
  addMonths,
  type BudgetEntry,
  byCategory as byCategoryReport,
  type CategoryDto,
  costOfLiving,
  createCategorySchema,
  createRecurrenceSchema,
  createTransactionSchema,
  effectiveBudget,
  firstDay,
  isMonth,
  lastDay,
  type Month,
  type MovementSearch,
  matchesMovementSearch,
  monthOf,
  monthSummary,
  monthsBetween,
  movementTotals,
  occurrences,
  type RecurrenceDto,
  setBudgetSchema,
  type TransactionDto,
  todayIn,
  trend as trendReport,
  updateCategorySchema,
  updateProfileSchema,
  updateRecurrenceSchema,
  updateTransactionSchema,
} from "@wambito/core";
import type { DemoSeed } from "./demo-data.ts";

/**
 * The demo's backend: an in-memory stand-in for the API, behind a `fetch` that `ApiProvider`
 * hands to the screens (`<ApiProvider mode="demo" fetch={demo.fetch}>`). It answers the `/api/v1/*`
 * routes the screens use with the same shapes, applies the same `@wambito/core` rules (month
 * summaries, budgets, recurrences, cost of living), validates bodies with the same zod schemas and
 * fails with the same problem+json codes. Nothing leaves the page: no network, no storage. A reload
 * builds it again from the seed; `reset()` does the same in place.
 *
 * The account is laid over the last 3 months counted back from `now()` in the seed's time zone.
 * Ids come from a counter, not from randomness, so the same seed and clock give the same answers.
 */
export interface DemoBackend {
  fetch: typeof globalThis.fetch;
  /** Back to the seed, as a reload would. */
  reset(): void;
}

interface Profile {
  id: string;
  email: string;
  timezone: string;
  locale: string;
  onboardingCompletedAt: string | null;
  currency: string;
  isAnonymous: boolean;
}

interface CategoryRow {
  id: string;
  name: string;
  kind: "expense" | "income";
  icon: string;
  color: string;
  sortOrder: number;
  archivedAt: string | null;
  createdAt: string;
}

interface RecurrenceRow extends RecurrenceDto {
  createdAt: string;
}

interface TransactionRow extends TransactionDto {
  deleted: boolean;
  /** The month a recurrence generated it for; one per rule and month, deleted or not. */
  occurrenceMonth: Month | null;
}

interface State {
  profile: Profile;
  categories: CategoryRow[];
  budgets: BudgetEntry[];
  recurrences: RecurrenceRow[];
  transactions: TransactionRow[];
  /** Idempotency-Key → the body it was sent with and what it got. */
  idempotency: Map<string, { body: string; status: number; payload: unknown }>;
  nextId: number;
}

/** Field errors, as the API lists them in a 422. */
interface FieldError {
  path: string;
  message: string;
}

/** A refusal, rendered as the API's problem+json. */
class Problem extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly detail?: string,
    readonly errors?: FieldError[],
  ) {
    super(detail ?? code);
  }
}

const TITLES: Record<number, string> = {
  400: "Bad Request",
  403: "Forbidden",
  404: "Not Found",
  409: "Conflict",
  422: "Unprocessable Content",
  500: "Internal Server Error",
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const pad = (n: number, width = 2) => String(n).padStart(width, "0");

/** A valid v4-shaped UUID from a counter: `00000000-0000-4000-8000-000000000001`, and so on. */
const uuidFrom = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;

/** What the zod schemas in core have in common, without importing zod here. */
interface Schema<T> {
  safeParse(
    value: unknown,
  ):
    | { success: true; data: T }
    | { success: false; error: { issues: { path: PropertyKey[]; message: string }[] } };
}

function valid<T>(schema: Schema<T>, value: unknown, detail = "The request is invalid"): T {
  const result = schema.safeParse(value);
  if (result.success) return result.data;
  throw new Problem(
    422,
    "validation_failed",
    detail,
    result.error.issues.map((issue) => ({
      path: issue.path.map(String).join("."),
      message: issue.message,
    })),
  );
}

const invalid = (path: string, message: string) =>
  new Problem(422, "validation_failed", "The request is invalid", [{ path, message }]);

// -- The seed, laid over the calendar ---------------------------------------------------------

/** Major units to hundredths. Past months round to whole hundreds of pesos or to 5 cents. */
function cents(amount: number, currency: string, factor = 1): number {
  const scaled = amount * factor;
  if (currency === "COP") return Math.round(scaled / 100) * 100 * 100;
  return factor === 1 ? Math.round(scaled * 100) : Math.round(scaled * 20) * 5;
}

function build(seed: DemoSeed, now: Date): State {
  let nextId = 1;
  const id = () => uuidFrom(nextId++);
  const { profile } = seed;
  const today = todayIn(profile.timezone, now);
  const current = monthOf(today);
  const first = addMonths(current, -2);
  const since = `${firstDay(first)}T12:00:00.000Z`;

  const categories: CategoryRow[] = seed.categories.map((c, index) => ({
    id: id(),
    name: c.name,
    kind: c.kind,
    icon: c.icon,
    color: c.color,
    sortOrder: index,
    archivedAt: null,
    createdAt: since,
  }));
  const categoryId = (key: string) => {
    const index = seed.categories.findIndex((c) => c.key === key);
    const row = categories[index];
    if (!row) throw new Error(`Demo seed: unknown category "${key}"`);
    return row.id;
  };
  const budgets: BudgetEntry[] = seed.categories.flatMap((c) =>
    c.budget === null
      ? []
      : [
          {
            categoryId: categoryId(c.key),
            amount: cents(c.budget, profile.currency),
            effectiveFrom: first,
          },
        ],
  );
  const recurrences: RecurrenceRow[] = seed.recurrences.map((r) => ({
    id: id(),
    name: r.name,
    amount: cents(r.amount, profile.currency),
    categoryId: categoryId(r.category),
    frequency: "monthly",
    dayOfMonth: r.dayOfMonth,
    monthOfYear: null,
    startDate: `${first}-${pad(r.dayOfMonth)}`,
    endDate: null,
    createdAt: since,
  }));

  const transactions: TransactionRow[] = [];
  const todayDay = Number(today.slice(8));
  const lastSeedDay = Math.max(...seed.month.map((s) => s.day));
  for (const back of [2, 1, 0]) {
    const month = addMonths(current, -back);
    const factors = back === 0 ? null : (seed.pastMonths[back - 1] ?? {});
    type Entry = Omit<TransactionRow, "id" | "createdAt" | "updatedAt">;
    const entries: Entry[] = [];
    for (const rule of recurrences) {
      for (const date of occurrences(rule, month)) {
        // This month only what is due by today is paid; the rest comes as pending on read.
        if (back === 0 && date > today) continue;
        entries.push({
          name: rule.name,
          amount: rule.amount,
          currency: profile.currency,
          date,
          status: "paid",
          note: null,
          categoryId: rule.categoryId,
          recurrenceId: rule.id,
          importId: null,
          source: "recurrence",
          needsReview: false,
          captureSource: null,
          deleted: false,
          occurrenceMonth: month,
        });
      }
    }
    for (const spend of seed.month) {
      // Early in the month the month's story is squeezed into the days so far: never in the future.
      const day =
        back > 0 || todayDay >= lastSeedDay
          ? spend.day
          : Math.max(1, Math.ceil((spend.day * todayDay) / lastSeedDay));
      entries.push({
        name: spend.name,
        amount: -cents(spend.amount, profile.currency, factors?.[spend.category] ?? 1),
        currency: profile.currency,
        date: `${month}-${pad(day)}`,
        status: "paid",
        note: null,
        categoryId: categoryId(spend.category),
        recurrenceId: null,
        importId: null,
        source: "app",
        needsReview: false,
        captureSource: null,
        deleted: false,
        occurrenceMonth: null,
      });
    }
    entries.sort((x, y) => (x.date < y.date ? -1 : x.date > y.date ? 1 : 0));
    entries.forEach((entry, index) => {
      const at = `${entry.date}T12:${pad(Math.floor(index / 60))}:${pad(index % 60)}.000Z`;
      transactions.push({ id: id(), ...entry, createdAt: at, updatedAt: at });
    });
  }

  return {
    profile: {
      id: "demo-valentina",
      email: profile.email,
      timezone: profile.timezone,
      locale: profile.locale,
      onboardingCompletedAt: since,
      currency: profile.currency,
      isAnonymous: false,
    },
    categories,
    budgets,
    recurrences,
    transactions,
    idempotency: new Map(),
    nextId,
  };
}

// -- The routes -------------------------------------------------------------------------------

const toTransactionDto = ({ deleted: _d, occurrenceMonth: _o, ...dto }: TransactionRow) => dto;
const toRecurrenceDto = ({ createdAt: _c, ...dto }: RecurrenceRow): RecurrenceDto => dto;

const byNewest = (x: TransactionRow, y: TransactionRow) =>
  x.date !== y.date ? (x.date < y.date ? 1 : -1) : x.id < y.id ? 1 : x.id > y.id ? -1 : 0;
const byOrder = (x: CategoryRow, y: CategoryRow) =>
  x.sortOrder - y.sortOrder || (x.createdAt < y.createdAt ? -1 : x.createdAt > y.createdAt ? 1 : 0);

const encodeCursor = (row: TransactionRow) =>
  btoa(`${row.date}|${row.id}`).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
function decodeCursor(cursor: string): { date: string; id: string } {
  try {
    const [date, id] = atob(cursor.replaceAll("-", "+").replaceAll("_", "/")).split("|");
    if (date && /^\d{4}-\d{2}-\d{2}$/.test(date) && id && UUID.test(id)) return { date, id };
  } catch {
    // Not base64: invalid like any other.
  }
  throw new Problem(422, "validation_failed", "Invalid cursor", [
    { path: "cursor", message: "Invalid cursor" },
  ]);
}

/** An integer query parameter within [min, max], or its default when absent. */
function intParam(
  params: URLSearchParams,
  name: string,
  min: number,
  max: number,
  fallback: number,
) {
  const raw = params.get(name);
  if (raw === null) return fallback;
  const value = Number(raw);
  if (raw.trim() === "" || !Number.isInteger(value) || value < min || value > max) {
    throw invalid(name, `Expected an integer from ${min} to ${max}`);
  }
  return value;
}

function monthParam(params: URLSearchParams, name: string, required: true): Month;
function monthParam(params: URLSearchParams, name: string, required?: false): Month | undefined;
function monthParam(params: URLSearchParams, name: string, required = false) {
  const raw = params.get(name);
  if (raw === null) {
    if (required) throw invalid(name, "Required");
    return undefined;
  }
  if (!isMonth(raw)) throw invalid(name, "Expected a month as YYYY-MM");
  return raw;
}

function enumParam<T extends string>(params: URLSearchParams, name: string, values: readonly T[]) {
  const raw = params.get(name);
  if (raw === null) return undefined;
  if (!values.includes(raw as T)) throw invalid(name, `Expected one of ${values.join(", ")}`);
  return raw as T;
}

/** The search params of the list, validated like the API: repeated `q` and `category`, `kind`, `match`. */
function searchParams(params: URLSearchParams): MovementSearch {
  const terms = params.getAll("q");
  if (terms.length > 10) throw invalid("q", "At most 10 terms");
  if (terms.some((t) => t.length > 100)) throw invalid("q", "At most 100 characters per term");
  const categoryIds = params.getAll("category");
  if (categoryIds.length > 20) throw invalid("category", "At most 20 categories");
  if (categoryIds.some((c) => !UUID.test(c))) throw invalid("category", "Invalid UUID");
  const kind = enumParam(params, "kind", ["expense", "income"] as const);
  const match = enumParam(params, "match", ["all", "any"] as const);
  return {
    ...(terms.length > 0 ? { terms } : {}),
    ...(categoryIds.length > 0 ? { categoryIds } : {}),
    ...(kind ? { kind } : {}),
    ...(match ? { match } : {}),
  };
}

const MAX_MONTHS = 36;

function rangeParams(params: URLSearchParams): Month[] {
  const from = monthParam(params, "from", true);
  const to = monthParam(params, "to", true);
  if (from > to) throw invalid("from", "from must not be after to");
  const months = monthsBetween(from, to);
  if (months.length > MAX_MONTHS) {
    throw new Problem(422, "range_too_large", `Ranges are limited to ${MAX_MONTHS} months`);
  }
  return months;
}

interface Answer {
  status: number;
  body?: unknown;
}

const ok = (body: unknown, status = 200): Answer => ({ status, body });

export function createDemoBackend(seed: DemoSeed, now: () => Date = () => new Date()): DemoBackend {
  let state = build(seed, now());

  const nextId = () => uuidFrom(state.nextId++);
  const stamp = () => now().toISOString();
  const today = () => todayIn(state.profile.timezone, now());
  const currentMonth = () => monthOf(today());

  const live = () => state.transactions.filter((t) => !t.deleted);
  const inMonth = (t: TransactionRow, month: Month) =>
    t.date >= firstDay(month) && t.date <= lastDay(month);

  function findCategory(id: string): CategoryRow {
    const row = state.categories.find((c) => c.id === id);
    if (!row) throw new Problem(404, "not_found", "Category not found");
    return row;
  }

  function requireActiveCategory(id: string): CategoryRow {
    const row = state.categories.find((c) => c.id === id && c.archivedAt === null);
    if (!row) throw new Problem(422, "category_not_found", "Pick one of your active categories");
    return row;
  }

  function findLive(id: string): TransactionRow {
    const row = state.transactions.find((t) => t.id === id && !t.deleted);
    if (!row) throw new Problem(404, "not_found", "Transaction not found");
    return row;
  }

  function findRecurrence(id: string): RecurrenceRow {
    const row = state.recurrences.find((r) => r.id === id);
    if (!row) throw new Problem(404, "not_found", "Recurrence not found");
    return row;
  }

  function categoryDto(row: CategoryRow): CategoryDto {
    return {
      id: row.id,
      name: row.name,
      kind: row.kind,
      icon: row.icon,
      color: row.color,
      sortOrder: row.sortOrder,
      archived: row.archivedAt !== null,
      currentBudget:
        row.kind === "expense" ? effectiveBudget(state.budgets, row.id, currentMonth()) : null,
    };
  }

  function requireUniqueName(name: string, except?: string) {
    const key = name.toLowerCase();
    const taken = state.categories.some(
      (c) => c.id !== except && c.archivedAt === null && c.name.toLowerCase() === key,
    );
    if (taken) {
      throw new Problem(409, "category_name_taken", "You already have a category with that name");
    }
  }

  /** The API's materializeRecurrences: the missing pending occurrences of `month`. */
  function materialize(month: Month) {
    if (month > addMonths(currentMonth(), 1)) return;
    for (const rule of state.recurrences) {
      const category = state.categories.find((c) => c.id === rule.categoryId);
      if (!category || category.archivedAt !== null) continue;
      for (const date of occurrences(rule, month)) {
        const exists = state.transactions.some(
          (t) => t.recurrenceId === rule.id && t.occurrenceMonth === month,
        );
        if (exists) continue;
        const at = stamp();
        state.transactions.push({
          id: nextId(),
          name: rule.name,
          amount: rule.amount,
          currency: state.profile.currency,
          date,
          status: "pending",
          note: null,
          categoryId: rule.categoryId,
          recurrenceId: rule.id,
          importId: null,
          source: "recurrence",
          needsReview: false,
          captureSource: null,
          createdAt: at,
          updatedAt: at,
          deleted: false,
          occurrenceMonth: month,
        });
      }
    }
  }

  /** Unpaid, not dismissed pending rows of these rules, from a month (by occurrence) or a date on. */
  function dropPending(ids: string[], from: { fromMonth: Month } | { fromDate: string }) {
    state.transactions = state.transactions.filter((t) => {
      if (!t.recurrenceId || !ids.includes(t.recurrenceId)) return true;
      if (t.status !== "pending" || t.deleted) return true;
      const later =
        "fromMonth" in from
          ? (t.occurrenceMonth ?? monthOf(t.date)) >= from.fromMonth
          : t.date >= from.fromDate;
      return !later;
    });
  }

  // -- /v1/me ---------------------------------------------------------------------------------

  function patchMe(body: unknown): Answer {
    const { onboardingCompleted, currency, ...fields } = valid(updateProfileSchema, body);
    if (currency && currency !== state.profile.currency) {
      const used = state.transactions.length > 0 || state.recurrences.length > 0;
      if (used) {
        throw new Problem(
          409,
          "currency_locked",
          "The currency cannot change once the account has transactions or recurrences",
        );
      }
      state.profile.currency = currency;
    }
    Object.assign(state.profile, fields);
    if (onboardingCompleted) state.profile.onboardingCompletedAt ??= stamp();
    return ok(state.profile);
  }

  // -- /v1/summary ----------------------------------------------------------------------------

  function summary(month: Month) {
    materialize(month);
    const txs = live().filter((t) => inMonth(t, month));
    const used = new Set(txs.map((t) => t.categoryId));
    const cats = [...state.categories]
      .sort(byOrder)
      .filter((c) => c.archivedAt === null || used.has(c.id));
    return monthSummary({ month, categories: cats, budgets: state.budgets, transactions: txs });
  }

  // -- /v1/transactions -----------------------------------------------------------------------

  function listTransactions(params: URLSearchParams): Answer {
    const month = monthParam(params, "month");
    const search = searchParams(params);
    const status = enumParam(params, "status", ["paid", "pending"] as const);
    const needsReview = enumParam(params, "needsReview", ["true", "false"] as const);
    const cursor = params.get("cursor");
    const after = cursor === null ? null : decodeCursor(cursor);
    const limit = intParam(params, "limit", 1, 200, 50);
    if (month) materialize(month);
    const rows = live()
      .filter(
        (t) =>
          (!month || inMonth(t, month)) &&
          matchesMovementSearch(t, { ...search, ...(status ? { status } : {}) }) &&
          (needsReview !== "true" || t.needsReview),
      )
      .sort(byNewest);
    // Totals cover every match, whatever the cursor.
    const totals = params.get("totals") === "true" ? movementTotals(rows) : undefined;
    const rest = rows.filter(
      (t) => !after || t.date < after.date || (t.date === after.date && t.id < after.id),
    );
    const items = rest.slice(0, limit);
    const last = items.at(-1);
    return ok({
      items: items.map(toTransactionDto),
      nextCursor: rest.length > limit && last ? encodeCursor(last) : null,
      ...(totals ? { totals } : {}),
    });
  }

  /** The API's suggestions: names used before (not the category's own), with their usual category. */
  function suggestions(params: URLSearchParams): Answer {
    const q = (params.get("q") ?? "").trim();
    if (q.length > 100) throw invalid("q", "At most 100 characters");
    const limit = intParam(params, "limit", 1, 20, 8);
    const needle = q.toLowerCase();
    const active = new Map(
      state.categories.filter((c) => c.archivedAt === null).map((c) => [c.id, c]),
    );
    const used = live().filter((t) => {
      const category = active.get(t.categoryId);
      return category && t.name.toLowerCase() !== category.name.toLowerCase();
    });
    const newestFirst = (x: TransactionRow, y: TransactionRow) =>
      x.date !== y.date
        ? x.date < y.date
          ? 1
          : -1
        : x.createdAt !== y.createdAt
          ? x.createdAt < y.createdAt
            ? 1
            : -1
          : x.id < y.id
            ? 1
            : -1;
    const byKey = new Map<string, TransactionRow[]>();
    for (const t of [...used].sort(newestFirst)) {
      const key = t.name.toLowerCase();
      byKey.set(key, [...(byKey.get(key) ?? []), t]);
    }
    const found = [...byKey.entries()]
      .filter(([key]) => needle === "" || key.includes(needle))
      .map(([key, rows]) => {
        const latest = rows[0] as TransactionRow;
        // The usual category: the most uses, then the most recent.
        const counts = new Map<string, number>();
        for (const row of rows) counts.set(row.categoryId, (counts.get(row.categoryId) ?? 0) + 1);
        let usual = latest.categoryId;
        for (const row of rows) {
          if ((counts.get(row.categoryId) ?? 0) > (counts.get(usual) ?? 0)) usual = row.categoryId;
        }
        return { key, latest, usual };
      })
      .sort((x, y) => {
        const px = needle !== "" && x.key.startsWith(needle) ? 1 : 0;
        const py = needle !== "" && y.key.startsWith(needle) ? 1 : 0;
        return py - px || newestFirst(x.latest, y.latest);
      })
      .slice(0, limit);
    return ok({ items: found.map((f) => ({ name: f.latest.name, categoryId: f.usual })) });
  }

  function createTransaction(raw: string, body: unknown, key: string | null): Answer {
    if (key) {
      const seen = state.idempotency.get(key);
      if (seen) {
        if (seen.body !== raw) {
          throw new Problem(
            422,
            "idempotency_key_reused",
            "This Idempotency-Key was used with a different request",
          );
        }
        return ok(seen.payload, seen.status);
      }
    }
    const input = valid(createTransactionSchema, body);
    requireActiveCategory(input.categoryId);
    const at = stamp();
    // "Repetir": its recurrence first, and this row is that rule's occurrence for its month.
    let rule: RecurrenceRow | null = null;
    if (input.repeat) {
      rule = {
        id: nextId(),
        name: input.name,
        amount: input.amount,
        categoryId: input.categoryId,
        frequency: input.repeat.frequency,
        dayOfMonth: Number(input.date.slice(8, 10)),
        monthOfYear: input.repeat.frequency === "yearly" ? Number(input.date.slice(5, 7)) : null,
        startDate: input.date,
        endDate: input.repeat.endDate ?? null,
        createdAt: at,
      };
      state.recurrences.push(rule);
    }
    const row: TransactionRow = {
      id: nextId(),
      name: input.name,
      amount: input.amount,
      currency: state.profile.currency,
      date: input.date,
      status: input.status,
      note: input.note ?? null,
      categoryId: input.categoryId,
      recurrenceId: rule?.id ?? null,
      importId: null,
      source: input.source,
      needsReview: false,
      captureSource: null,
      createdAt: at,
      updatedAt: at,
      deleted: false,
      occurrenceMonth: rule ? monthOf(input.date) : null,
    };
    state.transactions.push(row);
    const payload = toTransactionDto(row);
    if (key) state.idempotency.set(key, { body: raw, status: 201, payload });
    return ok(payload, 201);
  }

  function updateTransaction(id: string, body: unknown): Answer {
    const input = valid(updateTransactionSchema, body);
    const row = findLive(id);
    if (input.categoryId) requireActiveCategory(input.categoryId);
    Object.assign(row, input, { updatedAt: stamp() });
    return ok(toTransactionDto(row));
  }

  // -- /v1/categories -------------------------------------------------------------------------

  function createCategory(body: unknown): Answer {
    const input = valid(createCategorySchema, body);
    requireUniqueName(input.name);
    const row: CategoryRow = {
      id: nextId(),
      name: input.name,
      kind: input.kind,
      icon: input.icon,
      color: input.color,
      sortOrder: input.sortOrder ?? 0,
      archivedAt: null,
      createdAt: stamp(),
    };
    state.categories.push(row);
    return ok({ ...categoryDto(row), currentBudget: null }, 201);
  }

  function updateCategory(id: string, body: unknown): Answer {
    const { archived, ...fields } = valid(updateCategorySchema, body);
    const existing = findCategory(id);
    if (fields.kind && fields.kind !== existing.kind) {
      if (state.transactions.some((t) => t.categoryId === id)) {
        throw new Problem(
          409,
          "category_has_transactions",
          "A category with transactions cannot change its kind",
        );
      }
    }
    const archivedAt =
      archived === undefined
        ? existing.archivedAt
        : archived
          ? (existing.archivedAt ?? stamp())
          : null;
    if (archivedAt === null) requireUniqueName(fields.name ?? existing.name, id);
    const archiving = archived === true && existing.archivedAt === null;
    Object.assign(existing, fields, { archivedAt });
    if (archiving) {
      // Its active recurrences end today, and their unpaid pending rows from today on go.
      const day = today();
      const stopped = state.recurrences.filter(
        (r) => r.categoryId === id && (r.endDate === null || r.endDate >= day),
      );
      for (const rule of stopped) {
        rule.endDate = day;
        if (rule.startDate > day) rule.startDate = day;
      }
      dropPending(
        stopped.map((r) => r.id),
        { fromDate: day },
      );
    }
    return ok(categoryDto(existing));
  }

  function setBudget(id: string, body: unknown): Answer {
    const { amount, effectiveFrom } = valid(setBudgetSchema, body);
    const category = findCategory(id);
    if (category.kind !== "expense") {
      throw new Problem(422, "budget_category_not_expense", "Only expense categories have budgets");
    }
    const entry = state.budgets.find(
      (b) => b.categoryId === id && b.effectiveFrom === effectiveFrom,
    );
    if (entry) entry.amount = amount;
    else state.budgets.push({ categoryId: id, amount, effectiveFrom });
    return ok(categoryDto(category));
  }

  // -- /v1/recurrences ------------------------------------------------------------------------

  function createRecurrence(body: unknown): Answer {
    const input = valid(createRecurrenceSchema, body);
    requireActiveCategory(input.categoryId);
    const row: RecurrenceRow = {
      id: nextId(),
      name: input.name,
      amount: input.amount,
      categoryId: input.categoryId,
      frequency: input.frequency,
      dayOfMonth: input.dayOfMonth,
      monthOfYear: input.monthOfYear ?? null,
      startDate: input.startDate,
      endDate: input.endDate ?? null,
      createdAt: stamp(),
    };
    state.recurrences.push(row);
    return ok(toRecurrenceDto(row), 201);
  }

  function updateRecurrence(id: string, body: unknown): Answer {
    const input = valid(updateRecurrenceSchema, body);
    const existing = findRecurrence(id);
    if (input.categoryId) requireActiveCategory(input.categoryId);
    valid(
      createRecurrenceSchema,
      { ...toRecurrenceDto(existing), ...input },
      "The recurrence is invalid",
    );
    Object.assign(existing, input);
    dropPending([id], { fromMonth: currentMonth() });
    return ok(toRecurrenceDto(existing));
  }

  function deleteRecurrence(id: string): Answer {
    findRecurrence(id);
    dropPending([id], { fromMonth: currentMonth() });
    state.recurrences = state.recurrences.filter((r) => r.id !== id);
    for (const t of state.transactions) if (t.recurrenceId === id) t.recurrenceId = null;
    return { status: 204 };
  }

  // -- /v1/reports ----------------------------------------------------------------------------

  function byCategory(params: URLSearchParams): Answer {
    const months = rangeParams(params);
    // Reports read their months like the screens do, as the API's reports.ts does.
    for (const month of months) materialize(month);
    return ok(
      byCategoryReport({
        transactions: live(),
        categories: state.categories,
        months,
        kind: enumParam(params, "kind", ["expense", "income"] as const) ?? "expense",
        status: enumParam(params, "status", ["paid", "pending"] as const),
      }),
    );
  }

  function trend(params: URLSearchParams): Answer {
    const months = rangeParams(params);
    for (const month of months) materialize(month);
    return ok(
      trendReport({
        transactions: live(),
        categories: state.categories,
        budgets: state.budgets,
        months,
      }),
    );
  }

  function livingCost(params: URLSearchParams): Answer {
    const count = intParam(params, "months", 1, 24, 6);
    const to = addMonths(currentMonth(), -1);
    const from = addMonths(to, 1 - count);
    for (const month of monthsBetween(from, to)) materialize(month);
    const start = firstDay(from);
    return ok(
      costOfLiving({
        months: monthsBetween(from, to),
        categories: state.categories,
        fixedCategoryIds: [
          ...new Set(
            state.recurrences
              .filter((r) => r.endDate === null || r.endDate >= start)
              .map((r) => r.categoryId),
          ),
        ],
        transactions: live().filter((t) => t.date >= start && t.date <= lastDay(to)),
      }),
    );
  }

  // -- Dispatch -------------------------------------------------------------------------------

  function route(
    method: string,
    path: string,
    params: URLSearchParams,
    raw: string,
    headers: Headers,
  ): Answer {
    let body: unknown;
    if (raw !== "") {
      try {
        body = JSON.parse(raw);
      } catch {
        throw new Problem(400, "bad_request", "Malformed JSON in request body");
      }
    }
    const idOf = (match: RegExpExecArray | null) => {
      const id = match?.[1] ?? "";
      if (!UUID.test(id)) throw invalid("id", "Invalid UUID");
      return id;
    };
    const at = (pattern: RegExp) => pattern.exec(path);

    if (path === "/v1/me") {
      if (method === "GET") return ok(state.profile);
      if (method === "PATCH") return patchMe(body);
      // Deleting the account has no meaning here: settings turns it off in the demo.
      if (method === "DELETE") throw new Problem(403, "demo_unavailable", "Not in the demo");
    }
    if (path === "/v1/summary" && method === "GET") {
      return ok(summary(monthParam(params, "month") ?? currentMonth()));
    }
    if (path === "/v1/transactions") {
      if (method === "GET") return listTransactions(params);
      if (method === "POST") return createTransaction(raw, body, headers.get("idempotency-key"));
    }
    if (path === "/v1/transactions/suggestions" && method === "GET") return suggestions(params);
    let match = at(/^\/v1\/transactions\/([^/]+)$/);
    if (match) {
      const id = idOf(match);
      if (method === "PATCH") return updateTransaction(id, body);
      if (method === "DELETE") {
        findLive(id).deleted = true;
        return { status: 204 };
      }
    }
    match = at(/^\/v1\/transactions\/([^/]+)\/restore$/);
    if (match && method === "POST") {
      const id = idOf(match);
      const deleted = state.transactions.find((t) => t.id === id && t.deleted);
      if (deleted) deleted.deleted = false;
      return ok(toTransactionDto(deleted ?? findLive(id)));
    }
    if (path === "/v1/categories") {
      if (method === "GET") {
        const includeArchived =
          enumParam(params, "includeArchived", ["true", "false"] as const) === "true";
        return ok(
          [...state.categories]
            .filter((c) => includeArchived || c.archivedAt === null)
            .sort(byOrder)
            .map(categoryDto),
        );
      }
      if (method === "POST") return createCategory(body);
    }
    match = at(/^\/v1\/categories\/([^/]+)$/);
    if (match && method === "PATCH") return updateCategory(idOf(match), body);
    match = at(/^\/v1\/categories\/([^/]+)\/budget$/);
    if (match && method === "PUT") return setBudget(idOf(match), body);
    if (path === "/v1/recurrences") {
      if (method === "GET") {
        return ok(
          [...state.recurrences]
            .sort((x, y) => (x.createdAt < y.createdAt ? -1 : x.createdAt > y.createdAt ? 1 : 0))
            .map(toRecurrenceDto),
        );
      }
      if (method === "POST") return createRecurrence(body);
    }
    match = at(/^\/v1\/recurrences\/([^/]+)$/);
    if (match) {
      const id = idOf(match);
      if (method === "PATCH") return updateRecurrence(id, body);
      if (method === "DELETE") return deleteRecurrence(id);
    }
    if (method === "GET" && path === "/v1/reports/by-category") return byCategory(params);
    if (method === "GET" && path === "/v1/reports/trend") return trend(params);
    if (method === "GET" && path === "/v1/reports/cost-of-living") return livingCost(params);
    // Export and imports: settings turns them off in the demo.
    if (path === "/v1/me/export" || path.startsWith("/v1/imports")) {
      throw new Problem(403, "demo_unavailable", "Not in the demo");
    }
    throw new Problem(404, "not_found");
  }

  async function demoFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
    const request = input instanceof Request && !init ? input : new Request(input, init);
    const url = new URL(request.url);
    const v1 = url.pathname.indexOf("/v1/");
    const raw = request.method === "GET" || request.method === "HEAD" ? "" : await request.text();
    let answer: Answer;
    try {
      if (v1 < 0) throw new Problem(404, "not_found");
      answer = route(
        request.method,
        url.pathname.slice(v1),
        url.searchParams,
        raw,
        request.headers,
      );
    } catch (error) {
      if (!(error instanceof Problem)) throw error;
      const problem = {
        type: "about:blank",
        title: TITLES[error.status] ?? "Error",
        status: error.status,
        code: error.code,
        ...(error.detail ? { detail: error.detail } : {}),
        ...(error.errors ? { errors: error.errors } : {}),
      };
      return new Response(JSON.stringify(problem), {
        status: error.status,
        headers: { "content-type": "application/problem+json" },
      });
    }
    if (answer.body === undefined) return new Response(null, { status: answer.status });
    return new Response(JSON.stringify(answer.body), {
      status: answer.status,
      headers: { "content-type": "application/json" },
    });
  }

  return {
    fetch: demoFetch as typeof globalThis.fetch,
    reset() {
      state = build(seed, now());
    },
  };
}
