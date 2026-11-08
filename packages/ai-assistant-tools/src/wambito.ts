import type {
  CategoryDto,
  CreateCategory,
  CreateRecurrence,
  CreateTransaction,
  MovementKind,
  MovementTotals,
  monthSummaryDto,
  RecurrenceDto,
  SetBudget,
  TransactionDto,
  UpdateCategory,
  UpdateRecurrence,
  UpdateTransaction,
} from "@wambito/core";
import type { z } from "zod";

export type MonthSummaryDto = z.infer<typeof monthSummaryDto>;

/** What the tools need to know about the person: where they are, how they read, what they count in. */
export interface Profile {
  timezone: string;
  locale: "es" | "en" | "it" | "pt";
  currency: string;
}

/**
 * A page of transactions. `from`/`to` are inclusive dates (YYYY-MM-DD). `q` are words matched
 * against name or note and `categoryIds` categories; `match` says whether both groups must hold
 * ("all", the default) or either ("any"); `kind` and `status` always apply. `totals` asks for the
 * count and sums of every match, not only of the page.
 */
export interface TransactionQuery {
  month?: string;
  from?: string;
  to?: string;
  categoryIds?: string[];
  kind?: MovementKind;
  match?: "all" | "any";
  status?: "paid" | "pending";
  /** true: only detected transactions the person has not confirmed yet. */
  needsReview?: boolean;
  q?: string[];
  cursor?: string;
  limit: number;
  totals?: boolean;
}

/**
 * The person's Wambito as domain operations, not HTTP routes: the tools are written against this,
 * so they serve the remote MCP (over the API) today and a local Wambito on the device later.
 *
 * Amounts are integer hundredths, signed (expenses negative), as everywhere in Wambito. Months are
 * "YYYY-MM", dates "YYYY-MM-DD". Implementations throw `ToolError` for problems the model can fix
 * (`not_found`, `category_not_found`, `validation_failed`, `category_name_taken`…), with the API's
 * problem code.
 */
export interface Wambito {
  profile(): Promise<Profile>;
  monthSummary(month: string): Promise<MonthSummaryDto>;
  /** Live transactions, newest first (date, then id). */
  listTransactions(
    q: TransactionQuery,
  ): Promise<{ items: TransactionDto[]; nextCursor: string | null; totals?: MovementTotals }>;
  /** Totals per category over months `from`..`to` (inclusive), positive, largest first. */
  categoryReport(r: {
    from: string;
    to: string;
    kind: "expense" | "income";
  }): Promise<{ total: number; items: { categoryId: string; total: number }[] }>;
  /** Months `from`..`to` (inclusive): income and expenses as positive totals, and the budget. */
  trend(r: {
    from: string;
    to: string;
  }): Promise<{ months: { month: string; income: number; expenses: number; budget: number }[] }>;
  /** Every category, archived ones included (`archived: true`). */
  listCategories(): Promise<CategoryDto[]>;
  listRecurrences(): Promise<RecurrenceDto[]>;
  /**
   * Saves at most 20 transactions, all or nothing. The same key with the same items returns the
   * first answer with `replayed: true` and saves nothing.
   */
  addTransactions(
    items: CreateTransaction[],
    idempotencyKey: string,
  ): Promise<{ items: TransactionDto[]; replayed: boolean }>;
  updateTransaction(id: string, patch: UpdateTransaction): Promise<TransactionDto>;
  /** Soft-deletes (restorable) at most 20 transactions; unknown ids are ignored. */
  deleteTransactions(ids: string[]): Promise<void>;
  restoreTransaction(id: string): Promise<TransactionDto>;
  setBudget(categoryId: string, b: SetBudget): Promise<CategoryDto>;
  createCategory(c: CreateCategory): Promise<CategoryDto>;
  updateCategory(id: string, c: UpdateCategory): Promise<CategoryDto>;
  createRecurrence(r: CreateRecurrence): Promise<RecurrenceDto>;
  updateRecurrence(id: string, r: UpdateRecurrence): Promise<RecurrenceDto>;
  /** Removes the rule; its unpaid pending transactions from this month on go, the rest stay. */
  deleteRecurrence(id: string): Promise<void>;
}
