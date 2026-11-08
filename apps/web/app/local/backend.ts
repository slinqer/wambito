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
  type RecordBodies,
  type RecurrenceDto,
  type SettingsRecord,
  setBudgetSchema,
  type TransactionDto,
  todayIn,
  trend as trendReport,
  updateCategorySchema,
  updateProfileSchema,
  updateRecurrenceSchema,
  updateTransactionSchema,
} from "@wambito/core";
import { uuidv5, uuidv7 } from "./ids.ts";
import type { FinanceStore, ReadOptions, RecordType, StoreOps } from "./store.ts";

/**
 * The local backend: the `/api/v1/*` routes the screens use, answered from a `FinanceStore` with
 * the same shapes, the same `@wambito/core` rules, the same zod validation and the same
 * problem+json codes as the API. Nothing leaves the page. It is what the demo runs on (over the
 * memory store) and what the end-to-end encrypted web will run on (over the IndexedDB store).
 *
 * Each request runs in one store transaction: it reads a consistent snapshot, its writes commit
 * together, and a refusal (a 4xx) leaves the store untouched. Non-record state (the idempotency
 * keys) lives here, not in the store.
 */
export interface LocalBackend {
  fetch: typeof globalThis.fetch;
}

/** The account facts the settings record does not hold. */
export interface LocalProfile {
  id: string;
  email: string;
  isAnonymous: boolean;
}

/** A route this backend refuses with 403 `demo_unavailable`. */
export interface UnavailableRoute {
  /** An HTTP method, or `*`. */
  method: string;
  /** Under `/v1`, e.g. `/v1/me/export`. */
  path: string;
  /** Also match every path below it. */
  prefix?: boolean;
}

/** What the demo turns off: deleting the account, export and imports. */
export const DEMO_UNAVAILABLE: readonly UnavailableRoute[] = [
  { method: "DELETE", path: "/v1/me" },
  { method: "*", path: "/v1/me/export" },
  { method: "*", path: "/v1/imports", prefix: true },
];

export interface LocalBackendOptions {
  store: FinanceStore;
  now: () => Date;
  profile?: LocalProfile;
  /** Routes answered with 403 `demo_unavailable`. Default: none. */
  unavailable?: readonly UnavailableRoute[];
  /** Ids of new records. Default: UUID v7 from `now()`. The demo passes a counter. */
  newId?: () => string;
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

// -- Records as rows --------------------------------------------------------------------------

type Row<T extends RecordType> = RecordBodies[T] & { id: string };
type CategoryRow = Row<"category">;
type RecurrenceRow = Row<"recurrence">;
type TxBody = RecordBodies["transaction"];

/** A transaction as the screens and the core reports read it. */
interface TxRow extends TransactionDto {
  occurrenceMonth: Month | null;
  deleted: boolean;
}

const toTxRow = (id: string, b: TxBody, deleted = false): TxRow => ({
  id,
  name: b.name,
  amount: b.amount,
  currency: b.currency,
  date: b.date,
  status: b.status,
  note: b.note,
  categoryId: b.categoryId,
  recurrenceId: b.recurrenceId,
  importId: null,
  source: b.source,
  needsReview: b.needsReview,
  captureSource: b.captureSource,
  createdAt: b.createdAt ?? "",
  updatedAt: b.updatedAt ?? b.createdAt ?? "",
  occurrenceMonth: b.occurrenceMonth,
  deleted,
});

const toTransactionDto = ({
  occurrenceMonth: _o,
  deleted: _d,
  ...dto
}: TxRow): TransactionDto => dto;
const toRecurrenceDto = (r: RecurrenceRow): RecurrenceDto => ({
  id: r.id,
  name: r.name,
  amount: r.amount,
  categoryId: r.categoryId,
  frequency: r.frequency,
  dayOfMonth: r.dayOfMonth,
  monthOfYear: r.monthOfYear,
  startDate: r.startDate,
  endDate: r.endDate,
});

const rows = async <T extends RecordType>(
  s: StoreOps,
  type: T,
  opts?: ReadOptions,
): Promise<Row<T>[]> =>
  (await s.list(type, opts)).map((r) => ({ ...r.body, id: r.id }) as unknown as Row<T>);

const txRows = async (s: StoreOps, opts?: ReadOptions): Promise<TxRow[]> =>
  (await s.list("transaction", opts)).map((r) => toTxRow(r.id, r.body, r.deleted));

/** A row back to its record body: the `id` is the envelope's. */
function bodyOf<T extends RecordType>(row: Row<T>): RecordBodies[T] {
  const { id: _id, ...body } = row;
  return body as unknown as RecordBodies[T];
}

const byNewest = (x: TxRow, y: TxRow) =>
  x.date !== y.date ? (x.date < y.date ? 1 : -1) : x.id < y.id ? 1 : x.id > y.id ? -1 : 0;
const byOrder = (x: CategoryRow, y: CategoryRow) =>
  x.sortOrder - y.sortOrder ||
  ((x.createdAt ?? "") < (y.createdAt ?? "")
    ? -1
    : (x.createdAt ?? "") > (y.createdAt ?? "")
      ? 1
      : 0);

const encodeCursor = (row: TxRow) =>
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

// -- Query parameters -------------------------------------------------------------------------

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

/** The settings of an account that has not saved any yet. */
const FRESH_SETTINGS: SettingsRecord = {
  s: 1,
  name: null,
  currency: "USD",
  locale: "en",
  timezone: "UTC",
  onboardingCompletedAt: null,
};

/** What one request works with: its transaction and the account's clock. */
interface Env {
  s: StoreOps;
  settings: SettingsRecord;
  settingsId: string | null;
  today: string;
  month: Month;
}

export function createLocalBackend(options: LocalBackendOptions): LocalBackend {
  const { store, now } = options;
  const profile = options.profile ?? { id: "local", email: "", isAnonymous: false };
  const unavailable = options.unavailable ?? [];
  const newId = options.newId ?? (() => uuidv7(now().getTime()));
  /** Idempotency-Key → the body it was sent with and what it got. */
  const idempotency = new Map<string, { body: string; status: number; payload: unknown }>();

  const stamp = () => now().toISOString();

  async function envOf(s: StoreOps): Promise<Env> {
    const [first] = await s.list("settings");
    const settings = first?.body ?? FRESH_SETTINGS;
    const today = todayIn(settings.timezone, now());
    return { s, settings, settingsId: first?.id ?? null, today, month: monthOf(today) };
  }

  async function budgetEntries(s: StoreOps): Promise<BudgetEntry[]> {
    return (await s.list("budget")).map(({ body }) => ({
      categoryId: body.categoryId,
      amount: body.amount,
      effectiveFrom: body.effectiveFrom,
    }));
  }

  async function findCategory(s: StoreOps, id: string): Promise<CategoryRow> {
    const found = await s.get("category", id);
    if (!found) throw new Problem(404, "not_found", "Category not found");
    return { ...found.body, id };
  }

  async function requireActiveCategory(s: StoreOps, id: string): Promise<CategoryRow> {
    const found = await s.get("category", id);
    if (!found || found.body.archivedAt !== null) {
      throw new Problem(422, "category_not_found", "Pick one of your active categories");
    }
    return { ...found.body, id };
  }

  async function findLive(s: StoreOps, id: string) {
    const found = await s.get("transaction", id);
    if (!found) throw new Problem(404, "not_found", "Transaction not found");
    return found;
  }

  async function findRecurrence(s: StoreOps, id: string): Promise<RecurrenceRow> {
    const found = await s.get("recurrence", id);
    if (!found) throw new Problem(404, "not_found", "Recurrence not found");
    return { ...found.body, id };
  }

  function categoryDto(e: Env, row: CategoryRow, budgets: BudgetEntry[]): CategoryDto {
    return {
      id: row.id,
      name: row.name,
      kind: row.kind,
      icon: row.icon,
      color: row.color,
      sortOrder: row.sortOrder,
      archived: row.archivedAt !== null,
      currentBudget: row.kind === "expense" ? effectiveBudget(budgets, row.id, e.month) : null,
    };
  }

  async function requireUniqueName(s: StoreOps, name: string, except?: string) {
    const key = name.toLowerCase();
    const taken = (await rows(s, "category")).some(
      (c) => c.id !== except && c.archivedAt === null && c.name.toLowerCase() === key,
    );
    if (taken) {
      throw new Problem(409, "category_name_taken", "You already have a category with that name");
    }
  }

  /**
   * The API's materializeRecurrences: the missing pending occurrences of these months. An
   * occurrence's id is the UUID v5 of its rule and month, so every device makes the same one.
   */
  async function materialize(e: Env, months: Month[]) {
    const wanted = months.filter((m) => m <= addMonths(e.month, 1));
    if (wanted.length === 0) return;
    const rules = await rows(e.s, "recurrence");
    if (rules.length === 0) return;
    const categories = new Map((await rows(e.s, "category")).map((c) => [c.id, c]));
    const existing = await txRows(e.s, { includeDeleted: true });
    const byKey = new Map<string, TxRow[]>();
    for (const t of existing) {
      if (!t.recurrenceId || !t.occurrenceMonth) continue;
      const key = `${t.recurrenceId}|${t.occurrenceMonth}`;
      byKey.set(key, [...(byKey.get(key) ?? []), t]);
    }
    for (const month of wanted) {
      for (const rule of rules) {
        const category = categories.get(rule.categoryId);
        if (!category || category.archivedAt !== null) continue;
        for (const date of occurrences(rule, month)) {
          const id = await uuidv5(rule.id, `${month}:${rule.rev}`);
          // One per rule and month, deleted or not. A pending occurrence of an older revision
          // that was dropped (a tombstone under another id) does not count.
          const blocked = (byKey.get(`${rule.id}|${month}`) ?? []).some(
            (t) =>
              !t.deleted ||
              t.id === id ||
              t.status !== "pending" ||
              t.source !== "recurrence",
          );
          if (blocked) continue;
          byKey.set(`${rule.id}|${month}`, [{ id } as TxRow]);
          await e.s.put("transaction", id, {
            s: 1,
            name: rule.name,
            amount: rule.amount,
            currency: e.settings.currency,
            date,
            status: "pending",
            note: null,
            categoryId: rule.categoryId,
            accountId: null,
            recurrenceId: rule.id,
            occurrenceMonth: month,
            source: "recurrence",
            needsReview: false,
            captureSource: null,
            capturedAt: null,
            captureMerchantKey: null,
            createdAt: stamp(),
            updatedAt: stamp(),
          });
        }
      }
    }
  }

  /**
   * Unpaid, not dismissed pending rows of these rules, from a month (by occurrence) or a date on,
   * go (a normal delete). The rules then move to the next revision, so the occurrences made again
   * get new ids; the occurrences the person had deleted move with them and stay deleted.
   * `bump: false` is for rules that are going away.
   */
  async function dropPending(
    s: StoreOps,
    ids: string[],
    from: { fromMonth: Month } | { fromDate: string },
    bump = true,
  ) {
    const all = await txRows(s, { includeDeleted: true });
    const kept: TxRow[] = [];
    for (const t of all) {
      if (!t.recurrenceId || !ids.includes(t.recurrenceId)) continue;
      if (t.deleted) {
        if (t.status === "pending" && t.source === "recurrence" && t.occurrenceMonth) kept.push(t);
        continue;
      }
      if (t.status !== "pending") continue;
      const later =
        "fromMonth" in from
          ? (t.occurrenceMonth ?? monthOf(t.date)) >= from.fromMonth
          : t.date >= from.fromDate;
      if (later) await s.delete("transaction", t.id);
    }
    if (!bump) return;
    for (const id of ids) {
      const rule = await s.get("recurrence", id);
      if (!rule) continue;
      const rev = rule.body.rev + 1;
      await s.put("recurrence", id, { ...rule.body, rev });
      for (const t of kept) {
        if (t.recurrenceId !== id || !t.occurrenceMonth) continue;
        const moved = await uuidv5(id, `${t.occurrenceMonth}:${rev}`);
        const old = await s.get("transaction", t.id, { includeDeleted: true });
        if (!old) continue;
        await s.put("transaction", moved, old.body);
        await s.delete("transaction", moved);
      }
    }
  }

  const inMonth = (t: TxRow, month: Month) => t.date >= firstDay(month) && t.date <= lastDay(month);

  // -- /v1/me ---------------------------------------------------------------------------------

  const meOf = (e: Env) => ({
    id: profile.id,
    email: profile.email,
    timezone: e.settings.timezone,
    locale: e.settings.locale,
    onboardingCompletedAt: e.settings.onboardingCompletedAt,
    currency: e.settings.currency,
    isAnonymous: profile.isAnonymous,
  });

  async function patchMe(e: Env, body: unknown): Promise<Answer> {
    const { onboardingCompleted, currency, ...fields } = valid(updateProfileSchema, body);
    const next: SettingsRecord = { ...e.settings };
    if (currency && currency !== e.settings.currency) {
      const used =
        (await e.s.list("transaction", { includeDeleted: true })).length > 0 ||
        (await e.s.list("recurrence")).length > 0;
      if (used) {
        throw new Problem(
          409,
          "currency_locked",
          "The currency cannot change once the account has transactions or recurrences",
        );
      }
      next.currency = currency;
    }
    Object.assign(next, fields);
    if (onboardingCompleted) next.onboardingCompletedAt ??= stamp();
    await e.s.put("settings", e.settingsId ?? newId(), next);
    return ok(meOf({ ...e, settings: next }));
  }

  // -- /v1/summary ----------------------------------------------------------------------------

  async function summary(e: Env, month: Month) {
    await materialize(e, [month]);
    const txs = (await txRows(e.s)).filter((t) => inMonth(t, month));
    const used = new Set(txs.map((t) => t.categoryId));
    const cats = (await rows(e.s, "category"))
      .sort(byOrder)
      .filter((c) => c.archivedAt === null || used.has(c.id));
    return monthSummary({
      month,
      categories: cats,
      budgets: await budgetEntries(e.s),
      transactions: txs,
    });
  }

  // -- /v1/transactions -----------------------------------------------------------------------

  async function listTransactions(e: Env, params: URLSearchParams): Promise<Answer> {
    const month = monthParam(params, "month");
    const search = searchParams(params);
    const status = enumParam(params, "status", ["paid", "pending"] as const);
    const needsReview = enumParam(params, "needsReview", ["true", "false"] as const);
    const cursor = params.get("cursor");
    const after = cursor === null ? null : decodeCursor(cursor);
    const limit = intParam(params, "limit", 1, 200, 50);
    if (month) await materialize(e, [month]);
    const matches = (await txRows(e.s))
      .filter(
        (t) =>
          (!month || inMonth(t, month)) &&
          matchesMovementSearch(t, { ...search, ...(status ? { status } : {}) }) &&
          (needsReview !== "true" || t.needsReview),
      )
      .sort(byNewest);
    // Totals cover every match, whatever the cursor.
    const totals = params.get("totals") === "true" ? movementTotals(matches) : undefined;
    const rest = matches.filter(
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
  async function suggestions(e: Env, params: URLSearchParams): Promise<Answer> {
    const q = (params.get("q") ?? "").trim();
    if (q.length > 100) throw invalid("q", "At most 100 characters");
    const limit = intParam(params, "limit", 1, 20, 8);
    const needle = q.toLowerCase();
    const active = new Map(
      (await rows(e.s, "category")).filter((c) => c.archivedAt === null).map((c) => [c.id, c]),
    );
    const used = (await txRows(e.s)).filter((t) => {
      const category = active.get(t.categoryId);
      return category && t.name.toLowerCase() !== category.name.toLowerCase();
    });
    const newestFirst = (x: TxRow, y: TxRow) =>
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
    const byKey = new Map<string, TxRow[]>();
    for (const t of [...used].sort(newestFirst)) {
      const key = t.name.toLowerCase();
      byKey.set(key, [...(byKey.get(key) ?? []), t]);
    }
    const found = [...byKey.entries()]
      .filter(([key]) => needle === "" || key.includes(needle))
      .map(([key, group]) => {
        const latest = group[0] as TxRow;
        // The usual category: the most uses, then the most recent.
        const counts = new Map<string, number>();
        for (const row of group) counts.set(row.categoryId, (counts.get(row.categoryId) ?? 0) + 1);
        let usual = latest.categoryId;
        for (const row of group) {
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

  async function createTransaction(
    e: Env,
    raw: string,
    body: unknown,
    key: string | null,
  ): Promise<Answer> {
    if (key) {
      const seen = idempotency.get(key);
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
    await requireActiveCategory(e.s, input.categoryId);
    const at = stamp();
    // "Repetir": its recurrence first, and this row is that rule's occurrence for its month.
    let ruleId: string | null = null;
    if (input.repeat) {
      ruleId = newId();
      await e.s.put("recurrence", ruleId, {
        s: 1,
        name: input.name,
        amount: input.amount,
        categoryId: input.categoryId,
        frequency: input.repeat.frequency,
        dayOfMonth: Number(input.date.slice(8, 10)),
        monthOfYear: input.repeat.frequency === "yearly" ? Number(input.date.slice(5, 7)) : null,
        startDate: input.date,
        endDate: input.repeat.endDate ?? null,
        rev: 0,
        createdAt: at,
      });
    }
    const id = newId();
    const record: TxBody = {
      s: 1,
      name: input.name,
      amount: input.amount,
      currency: e.settings.currency,
      date: input.date,
      status: input.status,
      note: input.note ?? null,
      categoryId: input.categoryId,
      accountId: null,
      recurrenceId: ruleId,
      occurrenceMonth: ruleId ? monthOf(input.date) : null,
      source: input.source,
      needsReview: false,
      captureSource: null,
      capturedAt: null,
      captureMerchantKey: null,
      createdAt: at,
      updatedAt: at,
    };
    await e.s.put("transaction", id, record);
    const payload = toTransactionDto(toTxRow(id, record));
    if (key) idempotency.set(key, { body: raw, status: 201, payload });
    return ok(payload, 201);
  }

  async function updateTransaction(e: Env, id: string, body: unknown): Promise<Answer> {
    const input = valid(updateTransactionSchema, body);
    const found = await findLive(e.s, id);
    if (input.categoryId) await requireActiveCategory(e.s, input.categoryId);
    const next: TxBody = { ...found.body, ...input, updatedAt: stamp() };
    await e.s.put("transaction", id, next);
    return ok(toTransactionDto(toTxRow(id, next)));
  }

  // -- /v1/categories -------------------------------------------------------------------------

  async function createCategory(e: Env, body: unknown): Promise<Answer> {
    const input = valid(createCategorySchema, body);
    await requireUniqueName(e.s, input.name);
    const id = newId();
    const record: RecordBodies["category"] = {
      s: 1,
      name: input.name,
      kind: input.kind,
      icon: input.icon,
      color: input.color,
      sortOrder: input.sortOrder ?? 0,
      archivedAt: null,
      systemKey: null,
      createdAt: stamp(),
    };
    await e.s.put("category", id, record);
    return ok({ ...categoryDto(e, { ...record, id }, []), currentBudget: null }, 201);
  }

  async function updateCategory(e: Env, id: string, body: unknown): Promise<Answer> {
    const { archived, ...fields } = valid(updateCategorySchema, body);
    const existing = await findCategory(e.s, id);
    if (fields.kind && fields.kind !== existing.kind) {
      const used = (await txRows(e.s, { includeDeleted: true })).some((t) => t.categoryId === id);
      if (used) {
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
    if (archivedAt === null) await requireUniqueName(e.s, fields.name ?? existing.name, id);
    const archiving = archived === true && existing.archivedAt === null;
    const next: CategoryRow = { ...existing, ...fields, archivedAt };
    await e.s.put("category", id, bodyOf<"category">(next));
    if (archiving) {
      // Its active recurrences end today, and their unpaid pending rows from today on go.
      const day = e.today;
      const stopped = (await rows(e.s, "recurrence")).filter(
        (r) => r.categoryId === id && (r.endDate === null || r.endDate >= day),
      );
      for (const rule of stopped) {
        await e.s.put("recurrence", rule.id, {
          ...bodyOf<"recurrence">(rule),
          endDate: day,
          startDate: rule.startDate > day ? day : rule.startDate,
        });
      }
      await dropPending(
        e.s,
        stopped.map((r) => r.id),
        { fromDate: day },
      );
    }
    return ok(categoryDto(e, next, await budgetEntries(e.s)));
  }

  async function setBudget(e: Env, id: string, body: unknown): Promise<Answer> {
    const { amount, effectiveFrom } = valid(setBudgetSchema, body);
    const category = await findCategory(e.s, id);
    if (category.kind !== "expense") {
      throw new Problem(422, "budget_category_not_expense", "Only expense categories have budgets");
    }
    const entry = (await rows(e.s, "budget")).find(
      (b) => b.categoryId === id && b.effectiveFrom === effectiveFrom,
    );
    await e.s.put("budget", entry?.id ?? newId(), { s: 1, categoryId: id, amount, effectiveFrom });
    return ok(categoryDto(e, category, await budgetEntries(e.s)));
  }

  // -- /v1/recurrences ------------------------------------------------------------------------

  async function createRecurrence(e: Env, body: unknown): Promise<Answer> {
    const input = valid(createRecurrenceSchema, body);
    await requireActiveCategory(e.s, input.categoryId);
    const id = newId();
    const record: RecordBodies["recurrence"] = {
      s: 1,
      name: input.name,
      amount: input.amount,
      categoryId: input.categoryId,
      frequency: input.frequency,
      dayOfMonth: input.dayOfMonth,
      monthOfYear: input.monthOfYear ?? null,
      startDate: input.startDate,
      endDate: input.endDate ?? null,
      rev: 0,
      createdAt: stamp(),
    };
    await e.s.put("recurrence", id, record);
    return ok(toRecurrenceDto({ ...record, id }), 201);
  }

  async function updateRecurrence(e: Env, id: string, body: unknown): Promise<Answer> {
    const input = valid(updateRecurrenceSchema, body);
    const existing = await findRecurrence(e.s, id);
    if (input.categoryId) await requireActiveCategory(e.s, input.categoryId);
    valid(
      createRecurrenceSchema,
      { ...toRecurrenceDto(existing), ...input },
      "The recurrence is invalid",
    );
    const next = { ...existing, ...input } as RecurrenceRow;
    await e.s.put("recurrence", id, bodyOf<"recurrence">(next));
    await dropPending(e.s, [id], { fromMonth: e.month });
    return ok(toRecurrenceDto(next));
  }

  async function deleteRecurrence(e: Env, id: string): Promise<Answer> {
    await findRecurrence(e.s, id);
    await dropPending(e.s, [id], { fromMonth: e.month }, false);
    await e.s.delete("recurrence", id);
    // The rows it made stay, no longer tied to a rule (deleted ones too).
    for (const t of await e.s.list("transaction", { includeDeleted: true })) {
      if (t.body.recurrenceId !== id) continue;
      await e.s.put("transaction", t.id, { ...t.body, recurrenceId: null });
      if (t.deleted) await e.s.delete("transaction", t.id);
    }
    return { status: 204 };
  }

  // -- /v1/reports ----------------------------------------------------------------------------

  async function byCategory(e: Env, params: URLSearchParams): Promise<Answer> {
    const months = rangeParams(params);
    // Reports read their months like the screens do, as the API's reports.ts does.
    await materialize(e, months);
    return ok(
      byCategoryReport({
        transactions: await txRows(e.s),
        categories: await rows(e.s, "category"),
        months,
        kind: enumParam(params, "kind", ["expense", "income"] as const) ?? "expense",
        status: enumParam(params, "status", ["paid", "pending"] as const),
      }),
    );
  }

  async function trend(e: Env, params: URLSearchParams): Promise<Answer> {
    const months = rangeParams(params);
    await materialize(e, months);
    return ok(
      trendReport({
        transactions: await txRows(e.s),
        categories: await rows(e.s, "category"),
        budgets: await budgetEntries(e.s),
        months,
      }),
    );
  }

  async function livingCost(e: Env, params: URLSearchParams): Promise<Answer> {
    const count = intParam(params, "months", 1, 24, 6);
    const to = addMonths(e.month, -1);
    const from = addMonths(to, 1 - count);
    await materialize(e, monthsBetween(from, to));
    const start = firstDay(from);
    return ok(
      costOfLiving({
        months: monthsBetween(from, to),
        categories: await rows(e.s, "category"),
        fixedCategoryIds: [
          ...new Set(
            (await rows(e.s, "recurrence"))
              .filter((r) => r.endDate === null || r.endDate >= start)
              .map((r) => r.categoryId),
          ),
        ],
        transactions: (await txRows(e.s)).filter((t) => t.date >= start && t.date <= lastDay(to)),
      }),
    );
  }

  // -- Dispatch -------------------------------------------------------------------------------

  const isUnavailable = (method: string, path: string) =>
    unavailable.some(
      (u) =>
        (u.method === "*" || u.method === method) &&
        (u.prefix ? path === u.path || path.startsWith(`${u.path}/`) : path === u.path),
    );

  async function route(
    s: StoreOps,
    method: string,
    path: string,
    params: URLSearchParams,
    raw: string,
    headers: Headers,
  ): Promise<Answer> {
    let body: unknown;
    if (raw !== "") {
      try {
        body = JSON.parse(raw);
      } catch {
        throw new Problem(400, "bad_request", "Malformed JSON in request body");
      }
    }
    if (isUnavailable(method, path)) throw new Problem(403, "demo_unavailable", "Not in the demo");
    const idOf = (match: RegExpExecArray | null) => {
      const id = match?.[1] ?? "";
      if (!UUID.test(id)) throw invalid("id", "Invalid UUID");
      return id;
    };
    const at = (pattern: RegExp) => pattern.exec(path);
    const e = await envOf(s);

    if (path === "/v1/me") {
      if (method === "GET") return ok(meOf(e));
      if (method === "PATCH") return patchMe(e, body);
    }
    if (path === "/v1/summary" && method === "GET") {
      return ok(await summary(e, monthParam(params, "month") ?? e.month));
    }
    if (path === "/v1/transactions") {
      if (method === "GET") return listTransactions(e, params);
      if (method === "POST") {
        return createTransaction(e, raw, body, headers.get("idempotency-key"));
      }
    }
    if (path === "/v1/transactions/suggestions" && method === "GET") return suggestions(e, params);
    let match = at(/^\/v1\/transactions\/([^/]+)$/);
    if (match) {
      const id = idOf(match);
      if (method === "PATCH") return updateTransaction(e, id, body);
      if (method === "DELETE") {
        await findLive(s, id);
        await s.delete("transaction", id);
        return { status: 204 };
      }
    }
    match = at(/^\/v1\/transactions\/([^/]+)\/restore$/);
    if (match && method === "POST") {
      const id = idOf(match);
      const deleted = await s.get("transaction", id, { includeDeleted: true });
      if (deleted?.deleted) await s.put("transaction", id, deleted.body);
      const found = deleted ?? (await findLive(s, id));
      return ok(toTransactionDto(toTxRow(id, found.body)));
    }
    if (path === "/v1/categories") {
      if (method === "GET") {
        const includeArchived =
          enumParam(params, "includeArchived", ["true", "false"] as const) === "true";
        const budgets = await budgetEntries(s);
        return ok(
          (await rows(s, "category"))
            .filter((c) => includeArchived || c.archivedAt === null)
            .sort(byOrder)
            .map((c) => categoryDto(e, c, budgets)),
        );
      }
      if (method === "POST") return createCategory(e, body);
    }
    match = at(/^\/v1\/categories\/([^/]+)$/);
    if (match && method === "PATCH") return updateCategory(e, idOf(match), body);
    match = at(/^\/v1\/categories\/([^/]+)\/budget$/);
    if (match && method === "PUT") return setBudget(e, idOf(match), body);
    if (path === "/v1/recurrences") {
      if (method === "GET") {
        return ok(
          (await rows(s, "recurrence"))
            .sort((x, y) =>
              (x.createdAt ?? "") < (y.createdAt ?? "")
                ? -1
                : (x.createdAt ?? "") > (y.createdAt ?? "")
                  ? 1
                  : 0,
            )
            .map(toRecurrenceDto),
        );
      }
      if (method === "POST") return createRecurrence(e, body);
    }
    match = at(/^\/v1\/recurrences\/([^/]+)$/);
    if (match) {
      const id = idOf(match);
      if (method === "PATCH") return updateRecurrence(e, id, body);
      if (method === "DELETE") return deleteRecurrence(e, id);
    }
    if (method === "GET" && path === "/v1/reports/by-category") return byCategory(e, params);
    if (method === "GET" && path === "/v1/reports/trend") return trend(e, params);
    if (method === "GET" && path === "/v1/reports/cost-of-living") return livingCost(e, params);
    throw new Problem(404, "not_found");
  }

  async function localFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
    const request = input instanceof Request && !init ? input : new Request(input, init);
    const url = new URL(request.url);
    const v1 = url.pathname.indexOf("/v1/");
    const raw = request.method === "GET" || request.method === "HEAD" ? "" : await request.text();
    let answer: Answer;
    try {
      if (v1 < 0) throw new Problem(404, "not_found");
      const path = url.pathname.slice(v1);
      answer = await store.transaction((s) =>
        route(s, request.method, path, url.searchParams, raw, request.headers),
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

  return { fetch: localFetch as typeof globalThis.fetch };
}
