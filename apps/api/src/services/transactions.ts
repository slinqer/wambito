import type { TransactionDto } from "@wambito/core";
import { accounts, categories, type Tx, transactions } from "@wambito/db";
import { and, eq, isNull } from "@wambito/db/orm";
import { ApiError } from "../http/problem.ts";

export type TransactionRow = typeof transactions.$inferSelect;

export function toTransactionDto(row: TransactionRow): TransactionDto {
  return {
    id: row.id,
    name: row.name,
    amount: row.amount,
    currency: row.currency,
    date: row.date,
    status: row.status,
    note: row.note,
    categoryId: row.categoryId,
    recurrenceId: row.recurrenceId,
    importId: row.importId,
    source: row.source,
    needsReview: row.needsReview,
    captureSource: row.captureSource,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
  };
}

/**
 * The user's default account. With `lock`, its row stays locked (`FOR UPDATE`) until the
 * transaction ends. Everything that writes transactions in the account's currency, and the
 * currency change itself, takes that lock, so they run one after the other: a change cannot slip
 * between an import's currency check and its inserts. So do the writes that change or remove
 * recurrences (create, edit, delete, archiving their category).
 *
 * `lock: "share"` (`FOR SHARE`) is for materializing recurrences on a read: reads do not wait for
 * each other, but each waits for a writer in flight and a writer waits for it. Take it (or the
 * full lock) before any other row lock in the transaction, as every writer does, so two never
 * wait on each other.
 */
export async function defaultAccount(tx: Tx, { lock = false }: { lock?: boolean | "share" } = {}) {
  const query = tx.select().from(accounts).where(eq(accounts.isDefault, true));
  const [row] = await (lock === "share" ? query.for("share") : lock ? query.for("update") : query);
  if (!row) throw new Error("User has no default account");
  return row;
}

/** The user's non-archived category, or 422 `category_not_found`. */
export async function requireActiveCategory(tx: Tx, id: string) {
  const [row] = await tx
    .select()
    .from(categories)
    .where(and(eq(categories.id, id), isNull(categories.archivedAt)));
  if (!row) throw new ApiError(422, "category_not_found", "Pick one of your active categories");
  return row;
}
