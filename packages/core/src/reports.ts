import { type BudgetEntry, effectiveBudget } from "./budget.ts";
import { firstDay, lastDay, type Month } from "./dates.ts";

export interface ReportTransaction {
  categoryId: string;
  /** Signed cents: expenses negative, income positive. */
  amount: number;
  date: string;
  status: "paid" | "pending";
}

export interface ReportCategory {
  id: string;
  name: string;
  kind: "expense" | "income";
  icon: string;
  color: string;
  sortOrder?: number;
  archivedAt: string | null;
}

export interface ByCategoryItem {
  categoryId: string;
  name: string;
  icon: string;
  color: string;
  total: number;
  share: number;
}

export interface ByCategoryReport {
  total: number;
  items: ByCategoryItem[];
}

export interface ByCategoryInput {
  /** Live (not deleted) transactions. */
  transactions: ReportTransaction[];
  /** In the order the items tie-break in. */
  categories: ReportCategory[];
  /** The range's months, ascending and consecutive. */
  months: Month[];
  kind?: "expense" | "income";
  status?: "paid" | "pending";
}

/** Spending (or income) per category over a range of months, biggest first. */
export function byCategory(input: ByCategoryInput): ByCategoryReport {
  const kind = input.kind ?? "expense";
  const { status } = input;
  const from = firstDay(input.months[0] as Month);
  const to = lastDay(input.months.at(-1) as Month);
  const sums = new Map<string, number>();
  for (const t of input.transactions) {
    if (t.date < from || t.date > to || (status && t.status !== status)) continue;
    sums.set(t.categoryId, (sums.get(t.categoryId) ?? 0) + t.amount);
  }
  const sign = kind === "expense" ? -1 : 1;
  const items = input.categories
    .filter((c) => c.kind === kind && sums.has(c.id))
    .map((c) => ({
      categoryId: c.id,
      name: c.name,
      icon: c.icon,
      color: c.color,
      total: sign * (sums.get(c.id) ?? 0),
    }))
    .filter((i) => i.total !== 0)
    .sort((x, y) => y.total - x.total);
  const total = items.reduce((acc, i) => acc + i.total, 0);
  return {
    total,
    items: items.map((i) => ({
      ...i,
      share: total === 0 ? 0 : Math.round((i.total / total) * 10_000) / 10_000,
    })),
  };
}

export interface TrendMonth {
  month: Month;
  income: number;
  expenses: number;
  budget: number;
}

export interface TrendInput {
  transactions: ReportTransaction[];
  categories: ReportCategory[];
  budgets: BudgetEntry[];
  months: Month[];
}

/** Income, expenses and budget per month. The budget counts archived categories only if used. */
export function trend(input: TrendInput): { months: TrendMonth[] } {
  const kindOf = new Map(input.categories.map((c) => [c.id, c.kind]));
  return {
    months: input.months.map((month) => {
      const start = firstDay(month);
      const end = lastDay(month);
      const txs = input.transactions.filter((t) => t.date >= start && t.date <= end);
      const used = new Set(txs.map((t) => t.categoryId));
      let income = 0;
      let expenses = 0;
      for (const t of txs) {
        if (kindOf.get(t.categoryId) === "income") income += t.amount;
        else expenses -= t.amount;
      }
      const budget = input.categories
        .filter((c) => c.kind === "expense" && (c.archivedAt === null || used.has(c.id)))
        .reduce((acc, c) => acc + (effectiveBudget(input.budgets, c.id, month) ?? 0), 0);
      return { month, income, expenses, budget };
    }),
  };
}
