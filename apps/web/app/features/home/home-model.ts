import {
  type IsoDate,
  type MonthSummary,
  NEAR_LIMIT_RATIO,
  type TransactionDto,
  type WambiMessageInput,
  wambiMessage,
} from "@wambito/core";
import type { FeedbackEvent } from "../../feedback/feedback.ts";

// -- Transactions by day ---------------------------------------------------------------------------

export type DayWhen = "today" | "yesterday" | "upcoming" | "past";

export interface DayGroup {
  date: IsoDate;
  when: DayWhen;
  /** The day's signed total, in cents. */
  total: number;
  /** In the API's order (newest first). */
  items: TransactionDto[];
}

function dayBefore(date: IsoDate): IsoDate {
  const [year, month, day] = date.split("-").map(Number) as [number, number, number];
  return new Date(Date.UTC(year, month - 1, day - 1)).toISOString().slice(0, 10);
}

/**
 * Transactions by day in the API's order (newest first), as a search lists them: a future pending
 * day stays above older days when it is newer, nothing is moved to the bottom.
 */
export function groupNewestFirst(items: TransactionDto[], today: IsoDate): DayGroup[] {
  const yesterday = dayBefore(today);
  const groups: DayGroup[] = [];
  for (const tx of items) {
    const last = groups.at(-1);
    if (last && last.date === tx.date) {
      last.items.push(tx);
      last.total += tx.amount;
      continue;
    }
    groups.push({
      date: tx.date,
      when:
        tx.date === today
          ? "today"
          : tx.date > today
            ? "upcoming"
            : tx.date === yesterday
              ? "yesterday"
              : "past",
      total: tx.amount,
      items: [tx],
    });
  }
  return groups;
}

/**
 * A month's transactions by day, as home lists them: today on top, then the days gone by (newest
 * first), then the days still to come at the bottom (the nearest first, where the pending ones are).
 */
export function groupByDay(items: TransactionDto[], today: IsoDate): DayGroup[] {
  const byDate = new Map<IsoDate, TransactionDto[]>();
  for (const tx of items) byDate.set(tx.date, [...(byDate.get(tx.date) ?? []), tx]);
  const yesterday = dayBefore(today);
  const groups = [...byDate].map(
    ([date, list]): DayGroup => ({
      date,
      when:
        date === today
          ? "today"
          : date > today
            ? "upcoming"
            : date === yesterday
              ? "yesterday"
              : "past",
      total: list.reduce((sum, tx) => sum + tx.amount, 0),
      items: list,
    }),
  );
  const rank = (g: DayGroup) => (g.when === "today" ? 0 : g.when === "upcoming" ? 2 : 1);
  return groups.sort((a, b) => {
    if (rank(a) !== rank(b)) return rank(a) - rank(b);
    if (a.when === "upcoming") return a.date < b.date ? -1 : 1;
    return a.date < b.date ? 1 : -1;
  });
}

// -- What Wambi says -----------------------------------------------------------------------------

export interface WambiLineInput extends Omit<WambiMessageInput, "event"> {
  event?: WambiMessageInput["event"] | undefined;
  categoryName(id: string): string;
  /** Formats cents in the person's currency and locale. */
  money(cents: number): string;
}

export interface WambiLine {
  /** Catalog key: `wambi.<key>` (pick a variant: `.1`, `.2`, `.3`) or a single `home.*` line. */
  key: string;
  varied: boolean;
  params: Record<string, string | number>;
}

/** Core's parameters that hold money (cents); the rest are numbers to keep as they are. */
const MONEY_PARAMS = new Set(["remaining", "over", "amount", "spent"]);

/**
 * The line Wambi says on home: core's rule-based message with its parameters ready for the
 * catalog (a category's id becomes its name, cents become money, an unnamed movement takes its
 * category's name). Two cases core cannot know
 * about get their own line, so Wambi never says something false: without any budget there is
 * nothing "left", so he talks about what was spent; and a month over its total budget is never
 * "on track", even if each category alone is fine.
 */
export function homeWambiLine(input: WambiLineInput): WambiLine {
  const { categoryName, money, event, ...core } = input;
  const message = wambiMessage({ ...core, ...(event ? { event } : {}) });
  const { summary } = input;
  const aboutTheMonth =
    message.key === "on_track" ||
    message.key === "month_last_day" ||
    message.key === "month_closed_green";

  if (aboutTheMonth && summary.budgetTotal === 0) {
    return summary.spent === 0
      ? { key: "home.wambi_empty", varied: false, params: {} }
      : { key: "home.wambi_no_budget", varied: false, params: { spent: money(summary.spent) } };
  }
  if (aboutTheMonth && summary.remaining < 0) {
    return {
      key: "home.wambi_over_total",
      varied: false,
      params: { over: money(-summary.remaining) },
    };
  }

  const params: Record<string, string | number> = {};
  for (const [name, value] of Object.entries(message.params)) {
    if (name === "categoryId") params.category = categoryName(String(value));
    else if (MONEY_PARAMS.has(name) && typeof value === "number") params[name] = money(value);
    else params[name] = value;
  }
  // A movement without a name is called by its category.
  if (params.name === "") params.name = params.category ?? "";
  return { key: `wambi.${message.key}`, varied: true, params };
}

// -- The add sheet ---------------------------------------------------------------------------------

/** Categories by how often they were used (most first), then in their own order. */
export function orderByUse<C extends { id: string; sortOrder: number }>(
  categories: C[],
  used: { categoryId: string }[],
): C[] {
  const uses = new Map<string, number>();
  for (const { categoryId } of used) uses.set(categoryId, (uses.get(categoryId) ?? 0) + 1);
  return [...categories].sort(
    (a, b) => (uses.get(b.id) ?? 0) - (uses.get(a.id) ?? 0) || a.sortOrder - b.sortOrder,
  );
}

/**
 * The feedback after a save, from the month's summary once the save is in it: income is
 * `incomeSaved`; an expense that leaves its category over or near its limit says so instead of
 * celebrating; otherwise `expenseSaved`.
 */
export function feedbackForSave(
  after: MonthSummary | undefined,
  categoryId: string,
  kind: "expense" | "income",
): FeedbackEvent {
  if (kind === "income") return "incomeSaved";
  const state = after?.categories.find((c) => c.categoryId === categoryId)?.state;
  if (state === "over") return "overBudget";
  if (state === "near") return "nearLimit";
  return "expenseSaved";
}

/** The whole month's state against its total budget, as each category's is computed. */
export function overallState(budgetTotal: number, spent: number): "ok" | "near" | "over" {
  if (budgetTotal <= 0) return spent > 0 ? "over" : "ok";
  const ratio = spent / budgetTotal;
  return ratio > 1 ? "over" : ratio >= NEAR_LIMIT_RATIO ? "near" : "ok";
}

// -- Detected transactions -----------------------------------------------------------------------

/**
 * Where a transaction to review was detected, as the message's `source` choice (`revolut`,
 * `google_wallet`, or `other` when the API sent none); null when it needs no review.
 */
export function reviewMark(tx: TransactionDto): "revolut" | "google_wallet" | "other" | null {
  return tx.needsReview ? (tx.captureSource ?? "other") : null;
}
