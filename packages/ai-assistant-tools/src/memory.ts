import {
  type BudgetEntry,
  type CategoryDto,
  type CreateCategory,
  type CreateRecurrence,
  type CreateTransaction,
  effectiveBudget,
  firstDay,
  lastDay,
  type MovementTotals,
  matchesMovementSearch,
  monthOf,
  monthSummary,
  monthsBetween,
  movementTotals,
  type RecurrenceDto,
  type SetBudget,
  type TransactionDto,
  todayIn,
  type UpdateCategory,
  type UpdateRecurrence,
  type UpdateTransaction,
} from "@wambito/core";
import { normalizeName } from "./categories.ts";
import { ToolError } from "./errors.ts";
import type { MonthSummaryDto, Profile, TransactionQuery, Wambito } from "./wambito.ts";

/** The API's limit for one batch write. */
const BATCH_LIMIT = 20;

/** A month before any test data: where seeded `currentBudget`s start. */
const SEEDED_BUDGET_MONTH = "1970-01";

interface Seed {
  profile?: Partial<Profile>;
  categories?: CategoryDto[];
  transactions?: TransactionDto[];
  now?: () => Date;
}

const notFound = (what: string) => new ToolError("not_found", `${what} not found`);

/** A patch without its undefined fields: as JSON drops them on the way to the API. */
const defined = <T extends object>(patch: T): Partial<T> =>
  Object.fromEntries(Object.entries(patch).filter(([, v]) => v !== undefined)) as Partial<T>;

function tooMany(count: number): ToolError {
  return new ToolError(
    "validation_failed",
    `At most ${BATCH_LIMIT} items per call to Wambito (got ${count})`,
  );
}

/**
 * A Wambito in memory, for tests and demos. It mirrors the API where the tools depend on it:
 * signed amounts, soft deletes, the batch limit of 20, active category names unique ignoring case,
 * and idempotent batches (the same key and body replay, the same key with another body is
 * refused). Recurrences are stored but not materialized into pending transactions.
 */
export class MemoryWambito implements Wambito {
  private readonly person: Profile;
  private readonly now: () => Date;
  private readonly categories: CategoryDto[];
  private readonly budgets: BudgetEntry[] = [];
  private readonly rows: { tx: TransactionDto; deleted: boolean }[];
  private readonly recurrences: RecurrenceDto[] = [];
  private readonly replays = new Map<string, { body: string; items: TransactionDto[] }>();

  constructor(seed: Seed = {}) {
    this.person = {
      timezone: "America/Bogota",
      locale: "es",
      currency: "COP",
      ...seed.profile,
    };
    this.now = seed.now ?? (() => new Date());
    this.categories = (seed.categories ?? []).map((c) => ({ ...c }));
    for (const c of this.categories) {
      if (c.currentBudget !== null) {
        this.budgets.push({
          categoryId: c.id,
          amount: c.currentBudget,
          effectiveFrom: SEEDED_BUDGET_MONTH,
        });
      }
    }
    this.rows = (seed.transactions ?? []).map((tx) => ({ tx: { ...tx }, deleted: false }));
  }

  private currentMonth(): string {
    return monthOf(todayIn(this.person.timezone, this.now()));
  }

  private toCategoryDto(c: CategoryDto, month = this.currentMonth()): CategoryDto {
    return {
      ...c,
      currentBudget: c.kind === "expense" ? effectiveBudget(this.budgets, c.id, month) : null,
    };
  }

  private category(id: string): CategoryDto {
    const found = this.categories.find((c) => c.id === id);
    if (!found) throw notFound("Category");
    return found;
  }

  private activeCategory(id: string): CategoryDto {
    const found = this.categories.find((c) => c.id === id && !c.archived);
    if (!found) throw new ToolError("category_not_found", "Pick one of your active categories");
    return found;
  }

  private live(): TransactionDto[] {
    return this.rows.filter((r) => !r.deleted).map((r) => r.tx);
  }

  private inMonths(from: string, to: string): TransactionDto[] {
    return this.live().filter((t) => t.date >= firstDay(from) && t.date <= lastDay(to));
  }

  private stamp(): string {
    return this.now().toISOString();
  }

  async profile(): Promise<Profile> {
    return { ...this.person };
  }

  async monthSummary(month: string): Promise<MonthSummaryDto> {
    const transactions = this.inMonths(month, month);
    const used = new Set(transactions.map((t) => t.categoryId));
    // As the API: archived categories count only with movements that month.
    const categories = this.categories.filter((c) => !c.archived || used.has(c.id));
    return monthSummary({ month, categories, budgets: this.budgets, transactions });
  }

  async listTransactions(
    q: TransactionQuery,
  ): Promise<{ items: TransactionDto[]; nextCursor: string | null; totals?: MovementTotals }> {
    const [afterDate, afterId] = q.cursor ? q.cursor.split("|") : [];
    const search = {
      terms: q.q,
      categoryIds: q.categoryIds,
      kind: q.kind,
      status: q.status,
      match: q.match,
    };
    const matches = this.live()
      .filter(
        (t) =>
          (!q.month || monthOf(t.date) === q.month) &&
          (!q.from || t.date >= q.from) &&
          (!q.to || t.date <= q.to) &&
          (q.needsReview === undefined || t.needsReview === q.needsReview) &&
          matchesMovementSearch(t, search),
      )
      .sort((a, b) =>
        a.date === b.date ? b.id.localeCompare(a.id) : b.date.localeCompare(a.date),
      );
    const page = matches.filter(
      (t) =>
        afterDate === undefined ||
        t.date < afterDate ||
        (t.date === afterDate && t.id < (afterId ?? "")),
    );
    const items = page.slice(0, q.limit);
    const last = items.at(-1);
    return {
      items: items.map((t) => ({ ...t })),
      nextCursor: page.length > q.limit && last ? `${last.date}|${last.id}` : null,
      ...(q.totals ? { totals: movementTotals(matches) } : {}),
    };
  }

  async categoryReport(r: {
    from: string;
    to: string;
    kind: "expense" | "income";
  }): Promise<{ total: number; items: { categoryId: string; total: number }[] }> {
    const sign = r.kind === "expense" ? -1 : 1;
    const totals = new Map<string, number>();
    for (const t of this.inMonths(r.from, r.to)) {
      if (this.category(t.categoryId).kind !== r.kind) continue;
      totals.set(t.categoryId, (totals.get(t.categoryId) ?? 0) + sign * t.amount);
    }
    const items = [...totals]
      .map(([categoryId, total]) => ({ categoryId, total }))
      .filter((i) => i.total !== 0)
      .sort((a, b) => b.total - a.total);
    return { total: items.reduce((acc, i) => acc + i.total, 0), items };
  }

  async trend(r: { from: string; to: string }): Promise<{
    months: { month: string; income: number; expenses: number; budget: number }[];
  }> {
    const months = monthsBetween(r.from, r.to).map((month) => {
      const s = monthSummary({
        month,
        categories: this.categories,
        budgets: this.budgets,
        transactions: this.inMonths(month, month),
      });
      return { month, income: s.income, expenses: s.spent, budget: s.budgetTotal };
    });
    return { months };
  }

  async listCategories(): Promise<CategoryDto[]> {
    return this.categories.map((c) => this.toCategoryDto(c));
  }

  async listRecurrences(): Promise<RecurrenceDto[]> {
    return this.recurrences.map((r) => ({ ...r }));
  }

  async addTransactions(
    items: CreateTransaction[],
    idempotencyKey: string,
  ): Promise<{ items: TransactionDto[]; replayed: boolean }> {
    const body = JSON.stringify(items);
    const replay = this.replays.get(idempotencyKey);
    if (replay) {
      if (replay.body !== body) {
        throw new ToolError(
          "idempotency_key_reused",
          "This Idempotency-Key was used with a different request",
        );
      }
      return { items: replay.items.map((t) => ({ ...t })), replayed: true };
    }
    if (items.length === 0 || items.length > BATCH_LIMIT) throw tooMany(items.length);
    for (const i of items) this.activeCategory(i.categoryId);
    const stamp = this.stamp();
    const saved = items.map(
      ({ repeat: _repeat, ...i }): TransactionDto => ({
        id: crypto.randomUUID(),
        name: i.name,
        amount: i.amount,
        currency: this.person.currency,
        date: i.date,
        status: i.status,
        note: i.note ?? null,
        categoryId: i.categoryId,
        recurrenceId: null,
        importId: null,
        source: i.source,
        needsReview: false,
        captureSource: null,
        createdAt: stamp,
        updatedAt: stamp,
      }),
    );
    for (const tx of saved) this.rows.push({ tx, deleted: false });
    this.replays.set(idempotencyKey, { body, items: saved });
    return { items: saved.map((t) => ({ ...t })), replayed: false };
  }

  async updateTransaction(id: string, patch: UpdateTransaction): Promise<TransactionDto> {
    const row = this.rows.find((r) => r.tx.id === id && !r.deleted);
    if (!row) throw notFound("Transaction");
    if (patch.categoryId) this.activeCategory(patch.categoryId);
    row.tx = { ...row.tx, ...defined(patch), updatedAt: this.stamp() };
    return { ...row.tx };
  }

  async deleteTransactions(ids: string[]): Promise<void> {
    if (ids.length === 0 || ids.length > BATCH_LIMIT) throw tooMany(ids.length);
    for (const row of this.rows) if (ids.includes(row.tx.id)) row.deleted = true;
  }

  async restoreTransaction(id: string): Promise<TransactionDto> {
    const row = this.rows.find((r) => r.tx.id === id);
    if (!row) throw notFound("Transaction");
    row.deleted = false;
    return { ...row.tx };
  }

  async setBudget(categoryId: string, b: SetBudget): Promise<CategoryDto> {
    const c = this.category(categoryId);
    if (c.kind !== "expense") {
      throw new ToolError("budget_category_not_expense", "Only expense categories have budgets");
    }
    const existing = this.budgets.find(
      (e) => e.categoryId === categoryId && e.effectiveFrom === b.effectiveFrom,
    );
    if (existing) existing.amount = b.amount;
    else this.budgets.push({ categoryId, amount: b.amount, effectiveFrom: b.effectiveFrom });
    return this.toCategoryDto(c);
  }

  private checkNameFree(name: string, exceptId?: string) {
    const taken = this.categories.some(
      (c) => !c.archived && c.id !== exceptId && c.name.toLowerCase() === name.trim().toLowerCase(),
    );
    if (taken) {
      throw new ToolError("category_name_taken", "You already have a category with that name");
    }
  }

  async createCategory(input: CreateCategory): Promise<CategoryDto> {
    this.checkNameFree(input.name);
    const created: CategoryDto = {
      id: crypto.randomUUID(),
      name: input.name.trim(),
      kind: input.kind,
      icon: input.icon,
      color: input.color,
      sortOrder: input.sortOrder ?? this.categories.length,
      archived: false,
      currentBudget: null,
    };
    this.categories.push(created);
    return this.toCategoryDto(created);
  }

  async updateCategory(id: string, input: UpdateCategory): Promise<CategoryDto> {
    const c = this.category(id);
    if (input.name !== undefined) this.checkNameFree(input.name, id);
    Object.assign(c, defined(input));
    return this.toCategoryDto(c);
  }

  async createRecurrence(input: CreateRecurrence): Promise<RecurrenceDto> {
    this.activeCategory(input.categoryId);
    const created: RecurrenceDto = {
      id: crypto.randomUUID(),
      name: input.name,
      amount: input.amount,
      categoryId: input.categoryId,
      frequency: input.frequency,
      dayOfMonth: input.dayOfMonth,
      monthOfYear: input.monthOfYear ?? null,
      startDate: input.startDate,
      endDate: input.endDate ?? null,
    };
    this.recurrences.push(created);
    return { ...created };
  }

  async updateRecurrence(id: string, input: UpdateRecurrence): Promise<RecurrenceDto> {
    const r = this.recurrences.find((x) => x.id === id);
    if (!r) throw notFound("Recurrence");
    if (input.categoryId) this.activeCategory(input.categoryId);
    Object.assign(r, defined(input));
    return { ...r };
  }

  async deleteRecurrence(id: string): Promise<void> {
    const index = this.recurrences.findIndex((x) => x.id === id);
    if (index < 0) throw notFound("Recurrence");
    this.recurrences.splice(index, 1);
  }
}
