import { createRoute, z } from "@hono/zod-openapi";
import {
  FOLD_FROM,
  FOLD_TO,
  firstDay,
  foldText,
  isIsoDate,
  isoDateSchema,
  lastDay,
  monthOf,
  monthSchema,
  type CreateTransaction as NewTransaction,
} from "@wambito/core";
import { recurrences, type Tx, transactions, withUser } from "@wambito/db";
import {
  and,
  type Column,
  desc,
  eq,
  gt,
  gte,
  inArray,
  isNotNull,
  isNull,
  lt,
  lte,
  or,
  type SQL,
  sql,
} from "@wambito/db/orm";
import type { AppDeps } from "../deps.ts";
import type { Grant } from "../env.ts";
import { idempotent } from "../http/idempotency.ts";
import { jsonBody, jsonResponse, problems } from "../http/openapi.ts";
import { ApiError } from "../http/problem.ts";
import { router } from "../http/router.ts";
import {
  CreateTransaction,
  CreateTransactionsBatch,
  DeleteTransactionsBatch,
  idempotencyKeyHeader,
  ReviewTransactions,
  Transaction,
  UpdateTransaction,
} from "../http/schemas.ts";
import { learn } from "../services/captures.ts";
import { materializeRecurrences } from "../services/materialize.ts";
import { currentMonth } from "../services/time.ts";
import {
  defaultAccount,
  requireActiveCategory,
  type TransactionRow,
  toTransactionDto,
} from "../services/transactions.ts";

/** A query param that may repeat: Hono hands one value as a string and several as an array. */
function repeated<T extends z.ZodType>(item: T, max: number) {
  return z
    .preprocess((v) => (typeof v === "string" ? [v] : v), z.array(item).max(max))
    .optional()
    .openapi({ type: "array", items: { type: "string" }, param: { style: "form", explode: true } });
}

const idParam = z.object({ id: z.uuid() });
const listQuery = z
  .object({
    month: monthSchema.optional(),
    /** First and last day to include (YYYY-MM-DD), each optional; with `month`, both narrow it. */
    from: isoDateSchema.optional(),
    to: isoDateSchema.optional(),
    /** `expense`: only negative amounts; `income`: only positive ones. */
    kind: z.enum(["expense", "income"]).optional(),
    /** Words the name or the note contains, ignoring case and accents; repeat to match any of them. */
    q: repeated(z.string().trim().min(1).max(100), 10),
    /** Repeat to match any of the categories. */
    category: repeated(z.uuid(), 20),
    /** With both text and categories: `all` (default) needs both, `any` either. */
    match: z.enum(["all", "any"]).default("all"),
    /** `true` adds `totals` (count and sums of every match, ignoring the cursor) to the page. */
    totals: z
      .enum(["true", "false"])
      .transform((v) => v === "true")
      .optional(),
    status: z.enum(["paid", "pending"]).optional(),
    /** `true`: only detected transactions waiting for review; `false`: only the rest. */
    needsReview: z
      .enum(["true", "false"])
      .transform((v) => v === "true")
      .optional(),
    cursor: z.string().optional(),
    limit: z.coerce.number().int().min(1).max(200).default(50),
  })
  .refine((q) => !q.from || !q.to || q.from <= q.to, {
    message: "from must not be after to",
    path: ["from"],
  });

const suggestionsQuery = z.object({
  q: z.string().trim().max(100).optional(),
  limit: z.coerce.number().int().min(1).max(20).default(8),
});
const TransactionSuggestion = z
  .object({ name: z.string(), categoryId: z.uuid() })
  .openapi("TransactionSuggestion");
const TransactionPage = z
  .object({
    items: z.array(Transaction),
    nextCursor: z.string().nullable(),
    totals: z
      .object({
        count: z.number().int(),
        expense: z.number().int().describe("Cents, positive"),
        income: z.number().int().describe("Cents, positive"),
      })
      .optional()
      .describe("Only with `totals=true`: every match, not just this page"),
  })
  .openapi("TransactionPage");
const TransactionList = z.object({ items: z.array(Transaction) }).openapi("TransactionList");

const foldColumn = (column: Column) => sql`translate(lower(${column}), ${FOLD_FROM}, ${FOLD_TO})`;

const encodeCursor = (row: TransactionRow) =>
  Buffer.from(`${row.date}|${row.id}`).toString("base64url");
function decodeCursor(cursor: string): { date: string; id: string } {
  const [date, id] = Buffer.from(cursor, "base64url").toString().split("|");
  if (!date || !isIsoDate(date) || !id || !z.uuid().safeParse(id).success) {
    throw new ApiError(422, "validation_failed", "Invalid cursor", [
      { path: "cursor", message: "Invalid cursor" },
    ]);
  }
  return { date, id };
}

async function findLive(tx: Tx, id: string): Promise<TransactionRow> {
  const [row] = await tx
    .select()
    .from(transactions)
    .where(and(eq(transactions.id, id), isNull(transactions.deletedAt)));
  if (!row) throw new ApiError(404, "not_found", "Transaction not found");
  return row;
}

export function transactionRoutes(deps: AppDeps) {
  const app = router();

  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/transactions",
      operationId: "listTransactions",
      request: { query: listQuery },
      responses: {
        200: jsonResponse(TransactionPage, "A page of transactions, newest first"),
        ...problems(422),
      },
    }),
    async (c) => {
      const q = c.req.valid("query");
      const user = c.get("user");
      const filters: (SQL | undefined)[] = [isNull(transactions.deletedAt)];
      if (q.month)
        filters.push(
          gte(transactions.date, firstDay(q.month)),
          lte(transactions.date, lastDay(q.month)),
        );
      if (q.from) filters.push(gte(transactions.date, q.from));
      if (q.to) filters.push(lte(transactions.date, q.to));
      const textCondition = q.q?.length
        ? or(
            ...q.q.map((term) => {
              const pattern = `%${foldText(term).replace(/[\\%_]/g, (ch) => `\\${ch}`)}%`;
              return or(
                sql`${foldColumn(transactions.name)} like ${pattern}`,
                sql`${foldColumn(transactions.note)} like ${pattern}`,
              );
            }),
          )
        : undefined;
      const categoryCondition = q.category?.length
        ? inArray(transactions.categoryId, q.category)
        : undefined;
      if (q.match === "any" && textCondition && categoryCondition) {
        filters.push(or(textCondition, categoryCondition));
      } else {
        filters.push(textCondition, categoryCondition);
      }
      if (q.kind)
        filters.push(
          q.kind === "expense" ? lt(transactions.amount, 0) : gt(transactions.amount, 0),
        );
      if (q.status) filters.push(eq(transactions.status, q.status));
      if (q.needsReview !== undefined) filters.push(eq(transactions.needsReview, q.needsReview));
      const pageFilters = [...filters];
      if (q.cursor) {
        const { date, id } = decodeCursor(q.cursor);
        pageFilters.push(
          sql`(${transactions.date}, ${transactions.id}) < (${date}::date, ${id}::uuid)`,
        );
      }
      const { rows, totals } = await withUser(deps.db, user.id, async (tx) => {
        if (q.month) await materializeRecurrences(tx, user.id, q.month, currentMonth(deps, user));
        const rows = await tx
          .select()
          .from(transactions)
          .where(and(...pageFilters))
          .orderBy(desc(transactions.date), desc(transactions.id))
          .limit(q.limit + 1);
        if (!q.totals) return { rows, totals: undefined };
        const [sums] = await tx
          .select({
            count: sql<number>`count(*)::int`,
            expense: sql<number>`coalesce(sum(-${transactions.amount}) filter (where ${transactions.amount} < 0), 0)::int`,
            income: sql<number>`coalesce(sum(${transactions.amount}) filter (where ${transactions.amount} > 0), 0)::int`,
          })
          .from(transactions)
          .where(and(...filters));
        return { rows, totals: sums };
      });
      const items = rows.slice(0, q.limit);
      const last = items.at(-1);
      return c.json(
        {
          items: items.map(toTransactionDto),
          nextCursor: rows.length > q.limit && last ? encodeCursor(last) : null,
          ...(totals ? { totals } : {}),
        },
        200,
      );
    },
  );

  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/transactions/suggestions",
      operationId: "listTransactionSuggestions",
      request: { query: suggestionsQuery },
      responses: {
        200: jsonResponse(
          z.object({ items: z.array(TransactionSuggestion) }).openapi("TransactionSuggestions"),
          "Transaction names already used, with the category they usually go in, most used first (ties: most recent)",
        ),
        ...problems(422),
      },
    }),
    async (c) => {
      const { q, limit } = c.req.valid("query");
      const needle = (q ?? "").toLowerCase();
      // A name that equals its category's name is the default, not a shortcut, so it is skipped.
      // `position` (not LIKE) keeps `%` and `_` in the search text literal.
      const rows = await withUser(deps.db, c.get("userId"), (tx) =>
        tx.execute<{ name: string; category_id: string }>(sql`
          with used as (
            select lower(t.name) as key, t.name, t.category_id, t.date, t.created_at
            from transactions t
            join categories c on c.id = t.category_id
            where t.deleted_at is null
              and c.archived_at is null
              and lower(t.name) <> lower(c.name)
          ),
          latest as (
            select distinct on (key) key, name, date, created_at
            from used
            order by key, date desc, created_at desc
          ),
          uses as (
            select key, count(*) as uses from used group by key
          ),
          usual as (
            select distinct on (key) key, category_id
            from (
              select key, category_id, count(*) as uses, max(date) as last_date,
                max(created_at) as last_created
              from used
              group by key, category_id
            ) per_category
            order by key, uses desc, last_date desc, last_created desc
          )
          select latest.name, usual.category_id
          from latest
          join usual using (key)
          join uses using (key)
          where ${needle} = '' or position(${needle} in latest.key) > 0
          order by (position(${needle} in latest.key) = 1) desc,
            uses.uses desc, latest.date desc, latest.created_at desc
          limit ${limit}
        `),
      );
      return c.json({ items: rows.map((r) => ({ name: r.name, categoryId: r.category_id })) }, 200);
    },
  );

  app.use("/v1/transactions", async (c, next) =>
    c.req.method === "POST" ? idempotent(deps.db)(c, next) : next(),
  );
  // A retried batch would save everything twice, so here the key is mandatory.
  app.use("/v1/transactions/batch", idempotent(deps.db, { required: true }));
  app.use("/v1/transactions/review", idempotent(deps.db));

  /**
   * The one insert path for single and batch create: category check, account lock, currency. One
   * with `repeat` first makes its recurrence and is saved as that rule's occurrence for its month,
   * so materializing the month finds it there and adds no pending twin; later months get theirs.
   */
  /**
   * Under an assistant's OAuth token the API sets `source = mcp` itself, whatever the body says,
   * so the person can always tell what an assistant saved.
   */
  async function insertTransactions(
    tx: Tx,
    userId: string,
    inputs: NewTransaction[],
    grant: Grant,
  ) {
    for (const categoryId of new Set(inputs.map((i) => i.categoryId))) {
      await requireActiveCategory(tx, categoryId);
    }
    // Locked like the import's (and any recurrence write): the currency cannot change under these
    // inserts, and a read materializing the month waits for the new rule and its first row.
    const account = await defaultAccount(tx, { lock: true });
    const values = [];
    for (const { repeat, ...i } of inputs) {
      const row = {
        ...i,
        ...(grant.kind === "oauth" ? { source: "mcp" as const } : {}),
        userId,
        accountId: account.id,
        currency: account.currency,
      };
      if (!repeat) {
        values.push(row);
        continue;
      }
      const [rule] = await tx
        .insert(recurrences)
        .values({
          userId,
          accountId: account.id,
          name: i.name,
          amount: i.amount,
          categoryId: i.categoryId,
          frequency: repeat.frequency,
          dayOfMonth: Number(i.date.slice(8, 10)),
          monthOfYear: repeat.frequency === "yearly" ? Number(i.date.slice(5, 7)) : null,
          startDate: i.date,
          endDate: repeat.endDate ?? null,
        })
        .returning({ id: recurrences.id });
      values.push({
        ...row,
        recurrenceId: rule?.id ?? null,
        occurrenceMonth: firstDay(monthOf(i.date)),
      });
    }
    return (await tx.insert(transactions).values(values).returning()) as TransactionRow[];
  }

  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/transactions",
      operationId: "createTransaction",
      description:
        "With `repeat`, it also makes a recurrence from it (its name, amount, category; its date gives the day, the month of a yearly one and the start) and is that recurrence's occurrence for its month: the following ones come as pending.",
      request: {
        headers: idempotencyKeyHeader({ required: false }),
        body: jsonBody(CreateTransaction),
      },
      responses: { 201: jsonResponse(Transaction, "Created"), ...problems(422) },
    }),
    async (c) => {
      const input = c.req.valid("json");
      const userId = c.get("userId");
      const [row] = await withUser(deps.db, userId, (tx) =>
        insertTransactions(tx, userId, [input], c.get("grant")),
      );
      return c.json(toTransactionDto(row as TransactionRow), 201);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/transactions/batch",
      operationId: "createTransactionsBatch",
      description:
        "Saves up to 20 transactions in one transaction: all or nothing. `Idempotency-Key` is required; a retry with the same key and body returns the first response.",
      request: {
        headers: idempotencyKeyHeader({ required: true }),
        body: jsonBody(CreateTransactionsBatch),
      },
      responses: {
        201: jsonResponse(TransactionList, "Created, in request order"),
        ...problems(400, 422),
      },
    }),
    async (c) => {
      const { items } = c.req.valid("json");
      const userId = c.get("userId");
      const rows = await withUser(deps.db, userId, (tx) =>
        insertTransactions(tx, userId, items, c.get("grant")),
      );
      return c.json({ items: rows.map(toTransactionDto) }, 201);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/transactions/batch-delete",
      operationId: "deleteTransactionsBatch",
      description:
        "Soft-deletes (restorable) the given transactions that are the caller's. Other ids are ignored without a trace.",
      request: { body: jsonBody(DeleteTransactionsBatch) },
      responses: { 204: { description: "Deleted (restorable)" }, ...problems(422) },
    }),
    async (c) => {
      const { ids } = c.req.valid("json");
      await withUser(deps.db, c.get("userId"), (tx) =>
        tx
          .update(transactions)
          .set({ deletedAt: new Date() })
          .where(and(inArray(transactions.id, ids), isNull(transactions.deletedAt))),
      );
      return c.body(null, 204);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/transactions/review",
      operationId: "reviewTransactions",
      description:
        "Confirms detected transactions at once, learning the category of each. All or nothing: an id that is not the caller's, or was deleted, answers 404 and nothing changes. Ids already confirmed are left as they are.",
      request: {
        headers: idempotencyKeyHeader({ required: false }),
        body: jsonBody(ReviewTransactions),
      },
      responses: {
        200: jsonResponse(TransactionList, "The transactions, in request order"),
        ...problems(404, 422),
      },
    }),
    async (c) => {
      const { ids } = c.req.valid("json");
      const unique = [...new Set(ids)];
      const rows = await withUser(deps.db, c.get("userId"), async (tx) => {
        const found = await tx
          .select()
          .from(transactions)
          .where(and(inArray(transactions.id, unique), isNull(transactions.deletedAt)));
        if (found.length !== unique.length) {
          throw new ApiError(404, "not_found", "Transaction not found");
        }
        const byId = new Map<string, TransactionRow>(found.map((r) => [r.id, r]));
        for (const before of found) {
          if (!before.needsReview) continue;
          const [updated] = await tx
            .update(transactions)
            .set({ needsReview: false })
            .where(eq(transactions.id, before.id))
            .returning();
          if (!updated) continue;
          byId.set(updated.id, updated);
          if (before.source === "capture") await learn(tx, before.userId, updated);
        }
        return ids.map((id) => byId.get(id) as TransactionRow);
      });
      return c.json({ items: rows.map(toTransactionDto) }, 200);
    },
  );

  app.openapi(
    createRoute({
      method: "patch",
      path: "/v1/transactions/{id}",
      operationId: "updateTransaction",
      request: { params: idParam, body: jsonBody(UpdateTransaction) },
      responses: { 200: jsonResponse(Transaction, "Updated"), ...problems(404, 422) },
    }),
    async (c) => {
      const { id } = c.req.valid("param");
      const input = c.req.valid("json");
      const row = await withUser(deps.db, c.get("userId"), async (tx) => {
        const before = await findLive(tx, id);
        if (input.categoryId) await requireActiveCategory(tx, input.categoryId);
        const [updated] = await tx
          .update(transactions)
          .set(input)
          .where(eq(transactions.id, id))
          .returning();
        if (before.source === "capture" && before.needsReview && input.needsReview === false) {
          await learn(tx, before.userId, updated as TransactionRow);
        }
        return updated as TransactionRow;
      });
      return c.json(toTransactionDto(row), 200);
    },
  );

  app.openapi(
    createRoute({
      method: "delete",
      path: "/v1/transactions/{id}",
      operationId: "deleteTransaction",
      request: { params: idParam },
      responses: { 204: { description: "Deleted (restorable)" }, ...problems(404) },
    }),
    async (c) => {
      const { id } = c.req.valid("param");
      await withUser(deps.db, c.get("userId"), async (tx) => {
        await findLive(tx, id);
        await tx.update(transactions).set({ deletedAt: new Date() }).where(eq(transactions.id, id));
      });
      return c.body(null, 204);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/transactions/{id}/restore",
      operationId: "restoreTransaction",
      request: { params: idParam },
      responses: { 200: jsonResponse(Transaction, "Restored"), ...problems(404) },
    }),
    async (c) => {
      const { id } = c.req.valid("param");
      const row = await withUser(deps.db, c.get("userId"), async (tx) => {
        const [restored] = await tx
          .update(transactions)
          .set({ deletedAt: null })
          .where(and(eq(transactions.id, id), isNotNull(transactions.deletedAt)))
          .returning();
        if (restored) return restored;
        return findLive(tx, id);
      });
      return c.json(toTransactionDto(row), 200);
    },
  );

  return app;
}
