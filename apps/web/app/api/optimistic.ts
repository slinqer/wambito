import type { InfiniteData, QueryClient, QueryKey } from "@tanstack/react-query";
import {
  type CategoryDto,
  type MonthSummary,
  monthOf,
  monthSummary,
  type TransactionDto,
} from "@wambito/core";

/** One page of `GET /v1/transactions`: newest first, and where the next page starts. */
export interface TransactionList {
  items: TransactionDto[];
  nextCursor: string | null;
  /** Only with `totals=true`: every match, in positive cents. */
  totals?: { count: number; expense: number; income: number } | undefined;
}

/**
 * The cached shape of a month's list (`useTransactions(month)`, and a category's in it under
 * `[...transactionsKey(month), "category", id]`): the pages fetched so far, in order.
 */
export type TransactionPages = InfiniteData<TransactionList, string | null>;

/** Undoes an optimistic change: puts back exactly what the caches held before it. */
export type Rollback = () => void;

export const summaryKey = (month: string) => ["summary", month] as const;
export const transactionsKey = (month: string) => ["transactions", month] as const;
export const categoriesKey = () => ["categories"] as const;

type Kind = "expense" | "income";

/** Stands in for every income category: the summary only keeps their total. */
const INCOME = "income";

/**
 * The month summary after adding (`direction` 1) or taking away (-1) one transaction, worked out by
 * the same `monthSummary` the API uses, so totals, remaining and the near/over state match what the
 * server will say. It is rebuilt from the summary itself: each expense category's budget and spending
 * become one budget entry and one transaction.
 */
export function patchSummary(
  summary: MonthSummary,
  tx: { categoryId: string; amount: number },
  kind: Kind,
  direction: 1 | -1,
): MonthSummary {
  const month = summary.month;
  const categories: { id: string; kind: Kind }[] = summary.categories.map((c) => ({
    id: c.categoryId,
    kind: "expense",
  }));
  const budgets = summary.categories.flatMap((c) =>
    c.budget === null ? [] : [{ categoryId: c.categoryId, amount: c.budget, effectiveFrom: month }],
  );
  const transactions = summary.categories.map((c) => ({
    categoryId: c.categoryId,
    amount: -c.spent,
  }));

  categories.push({ id: INCOME, kind: "income" });
  transactions.push({ categoryId: INCOME, amount: summary.income });

  const target = kind === "income" ? INCOME : tx.categoryId;
  if (!categories.some((c) => c.id === target)) {
    categories.splice(categories.length - 1, 0, { id: target, kind: "expense" });
  }
  transactions.push({ categoryId: target, amount: direction * tx.amount });

  return monthSummary({ month, categories, budgets, transactions });
}

/** Newest first, like the API: by date, then id. */
function byNewest(a: TransactionDto, b: TransactionDto): number {
  if (a.date !== b.date) return a.date < b.date ? 1 : -1;
  return a.id < b.id ? 1 : a.id > b.id ? -1 : 0;
}

function kindOf(qc: QueryClient, tx: Pick<TransactionDto, "categoryId" | "amount">): Kind {
  const known = qc
    .getQueryData<CategoryDto[]>(categoriesKey())
    ?.find((c) => c.id === tx.categoryId);
  // Expenses are stored negative and income positive.
  return known?.kind ?? (tx.amount < 0 ? "expense" : "income");
}

/** Edits one cached query, if it is cached, and returns how to put it back. */
function edit<T>(qc: QueryClient, key: QueryKey, change: (current: T) => T): Rollback {
  const before = qc.getQueryData<T>(key);
  if (before === undefined) return () => {};
  qc.setQueryData<T>(key, change(before));
  return () => qc.setQueryData<T>(key, before);
}

const together =
  (rollbacks: Rollback[]): Rollback =>
  () => {
    for (const rollback of rollbacks.toReversed()) rollback();
  };

/** Every cached list of `month`: the month's own and each category's (with that category's id). */
function listsOf(
  qc: QueryClient,
  month: string,
): { key: QueryKey; data: TransactionPages; categoryId: string | undefined; review: boolean }[] {
  return qc
    .getQueriesData<TransactionPages>({ queryKey: transactionsKey(month) })
    .flatMap(([key, data]) =>
      data && Array.isArray(data.pages)
        ? [
            {
              key,
              data,
              categoryId: key[2] === "category" ? String(key[3]) : undefined,
              review: key[2] === "review",
            },
          ]
        : [],
    );
}

function withoutRow(data: TransactionPages, id: string): TransactionPages {
  return {
    ...data,
    pages: data.pages.map((p) => ({ ...p, items: p.items.filter((t) => t.id !== id) })),
  };
}

/**
 * Puts `tx` in the page it sorts into: the first whose last row is not newer than it. Older than
 * everything fetched, it goes at the end only when nothing is left to fetch; otherwise it belongs
 * to a page not loaded yet, which will bring it.
 */
function withRow(data: TransactionPages, tx: TransactionDto): TransactionPages {
  const pages = withoutRow(data, tx.id).pages;
  let at = pages.findIndex((p) => {
    const last = p.items.at(-1);
    return last ? byNewest(tx, last) <= 0 : p.nextCursor === null;
  });
  if (at === -1 && pages.at(-1)?.nextCursor === null) at = pages.length - 1;
  if (at === -1) return { ...data, pages };
  return {
    ...data,
    pages: pages.map((p, i) => (i === at ? { ...p, items: [...p.items, tx].sort(byNewest) } : p)),
  };
}

function addToCaches(qc: QueryClient, tx: TransactionDto): Rollback {
  const month = monthOf(tx.date);
  return together([
    ...listsOf(qc, month)
      .filter((list) => list.categoryId === undefined || list.categoryId === tx.categoryId)
      .filter((list) => !list.review || tx.needsReview)
      .map((list) => edit<TransactionPages>(qc, list.key, (data) => withRow(data, tx))),
    edit<MonthSummary>(qc, summaryKey(month), (s) => patchSummary(s, tx, kindOf(qc, tx), 1)),
  ]);
}

function removeFromCaches(qc: QueryClient, month: string, tx: TransactionDto): Rollback {
  return together([
    ...listsOf(qc, month).map((list) =>
      edit<TransactionPages>(qc, list.key, (data) => withoutRow(data, tx.id)),
    ),
    edit<MonthSummary>(qc, summaryKey(month), (s) => patchSummary(s, tx, kindOf(qc, tx), -1)),
  ]);
}

/** The transaction as cached in any of the month's lists (home's, or a category's). */
function findCached(qc: QueryClient, month: string, id: string): TransactionDto | undefined {
  for (const { data } of listsOf(qc, month)) {
    for (const page of data.pages) {
      const found = page.items.find((t) => t.id === id);
      if (found) return found;
    }
  }
  return undefined;
}

/** Shows a new transaction right away in its month's list and summary (when they are cached). */
export function optimisticAdd(qc: QueryClient, tx: TransactionDto): Rollback {
  return addToCaches(qc, tx);
}

/** Takes a transaction out of its month's list and summary. Does nothing if it is not cached. */
export function optimisticRemove(qc: QueryClient, month: string, id: string): Rollback {
  const tx = findCached(qc, month, id);
  return tx ? removeFromCaches(qc, month, tx) : () => {};
}

/**
 * Applies an edit to a cached transaction. A new date in another month moves it between that
 * month's caches. Does nothing if the transaction is not cached.
 */
export function optimisticUpdate(
  qc: QueryClient,
  month: string,
  id: string,
  patch: Partial<
    Pick<
      TransactionDto,
      "name" | "amount" | "categoryId" | "date" | "status" | "note" | "needsReview"
    >
  >,
): Rollback {
  const before = findCached(qc, month, id);
  if (!before) return () => {};
  const after: TransactionDto = { ...before, ...patch };
  return together([removeFromCaches(qc, month, before), addToCaches(qc, after)]);
}

/** The cache entries a change to these months touches; cancel their in-flight fetches first. */
export function keysFor(months: string[]): QueryKey[] {
  return months.flatMap((month) => [summaryKey(month), transactionsKey(month)]);
}
