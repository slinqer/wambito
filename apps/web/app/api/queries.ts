import {
  keepPreviousData,
  type QueryClient,
  useInfiniteQuery,
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import { monthOf, type TransactionDto } from "@wambito/core";
import { useApi } from "./ApiProvider.tsx";
import { ApiProblem } from "./errors.ts";
import {
  keysFor,
  optimisticAdd,
  optimisticRemove,
  optimisticUpdate,
  type Rollback,
  summaryKey,
  type TransactionList,
  type TransactionPages,
  transactionsKey,
} from "./optimistic.ts";
import { confirmInBatches } from "./review.ts";
import type { paths } from "./schema";

type JsonBody<
  Path extends keyof paths,
  Method extends keyof paths[Path],
> = paths[Path][Method] extends {
  requestBody?: { content: { "application/json": infer Body } };
}
  ? Body
  : never;

/** The fields to create a transaction with: name, amount (minor units, negative for spending), category, date. */
export type NewTransaction = JsonBody<"/v1/transactions", "post">;
/** The fields to change on a transaction; send only those that changed. */
export type TransactionPatch = JsonBody<"/v1/transactions/{id}", "patch">;
export type ReportRange = { from: string; to: string };
export type ByCategoryRange = ReportRange & {
  kind?: "expense" | "income";
  status?: "paid" | "pending";
};

/** The data of a successful response. Failures never get here: the client throws `ApiProblem`. */
function dataOf<T>(result: { data?: T; response: Response }): T {
  if (result.data === undefined) {
    throw new ApiProblem({ status: result.response.status, code: "internal_error" });
  }
  return result.data;
}

export const queryKeys = {
  me: () => ["me"] as const,
  summary: summaryKey,
  transactions: transactionsKey,
  categories: () => ["categories"] as const,
  suggestions: (q: string) => ["suggestions", q] as const,
  recurrences: () => ["recurrences"] as const,
  /** Everything built from transactions beyond one month's list and summary. */
  reports: () => ["reports"] as const,
  costOfLiving: (months: number) => ["reports", "cost-of-living", months] as const,
  byCategory: (range: ByCategoryRange) =>
    [
      "reports",
      "by-category",
      range.from,
      range.to,
      range.kind ?? null,
      range.status ?? null,
    ] as const,
  trend: (range: ReportRange) => ["reports", "trend", range.from, range.to] as const,
};

// -- Reads ------------------------------------------------------------------------------------

export function useMe() {
  const api = useApi();
  return useQuery({
    queryKey: queryKeys.me(),
    queryFn: async () => dataOf(await api.GET("/v1/me")),
  });
}

export function useSummary(month: string) {
  const api = useApi();
  return useQuery({
    queryKey: queryKeys.summary(month),
    queryFn: async ({ signal }) =>
      dataOf(await api.GET("/v1/summary", { params: { query: { month } }, signal })),
  });
}

/** Rows per page of a transaction list: the API's most. */
export const TRANSACTIONS_PAGE = 200;

/**
 * A month's transactions (one category's with `category`), newest first, a page at a time: `data`
 * is every row fetched so far, `hasNextPage` says there are more, and `fetchNextPage` brings them
 * ("Ver más movimientos"). A refetch fetches again every page already shown.
 */
function useTransactionPages(
  queryKey: readonly unknown[],
  query: { month: string; category?: string[]; needsReview?: "true" },
) {
  const api = useApi();
  return useInfiniteQuery({
    queryKey,
    initialPageParam: null as string | null,
    queryFn: async ({ pageParam, signal }): Promise<TransactionList> =>
      dataOf(
        await api.GET("/v1/transactions", {
          params: {
            query: {
              ...query,
              limit: TRANSACTIONS_PAGE,
              ...(pageParam ? { cursor: pageParam } : {}),
            },
          },
          signal,
        }),
      ),
    getNextPageParam: (last) => last.nextCursor,
    select: (data: TransactionPages) => data.pages.flatMap((page) => page.items),
  });
}

/**
 * The month's transactions still to review (detected from notifications), asked of the API, so
 * the list, its count and "Confirmar todos" cover the whole month, not only the pages shown.
 */
export function useReviewTransactions(month: string) {
  return useTransactionPages([...queryKeys.transactions(month), "review"], {
    month,
    needsReview: "true",
  });
}

/** The month's transactions, newest first, a page at a time (see `useTransactionPages`). */
export function useTransactions(month: string) {
  return useTransactionPages(queryKeys.transactions(month), { month });
}

export function useCategories() {
  const api = useApi();
  return useQuery({
    queryKey: queryKeys.categories(),
    queryFn: async ({ signal }) => dataOf(await api.GET("/v1/categories", { signal })),
  });
}

/**
 * Every category, archived ones too: what older transactions are in. Lists of choices use
 * `useCategories` (active only); lookups by id (a row's name, the transaction being edited) use
 * this. Invalidating `categories()` refreshes both.
 */
export function useAllCategories() {
  const api = useApi();
  return useQuery({
    queryKey: [...queryKeys.categories(), "all"] as const,
    queryFn: async ({ signal }) =>
      dataOf(
        await api.GET("/v1/categories", {
          params: { query: { includeArchived: "true" } },
          signal,
        }),
      ),
  });
}

/** Names you used before, with the category they usually go in, matching what is being typed. */
export function useSuggestions(q: string) {
  const api = useApi();
  return useQuery({
    queryKey: queryKeys.suggestions(q),
    queryFn: async ({ signal }) =>
      dataOf(await api.GET("/v1/transactions/suggestions", { params: { query: { q } }, signal })),
    placeholderData: keepPreviousData,
  });
}

export function useRecurrences({ enabled = true }: { enabled?: boolean } = {}) {
  const api = useApi();
  return useQuery({
    queryKey: queryKeys.recurrences(),
    enabled,
    queryFn: async ({ signal }) => dataOf(await api.GET("/v1/recurrences", { signal })),
  });
}

/** Average monthly spending over the last `months` complete months; `enabled: false` waits. */
export function useCostOfLiving(months: number, { enabled = true }: { enabled?: boolean } = {}) {
  const api = useApi();
  return useQuery({
    queryKey: queryKeys.costOfLiving(months),
    enabled,
    queryFn: async ({ signal }) =>
      dataOf(
        await api.GET("/v1/reports/cost-of-living", { params: { query: { months } }, signal }),
      ),
  });
}

/**
 * Totals per category over a range, with the `range` (kind and status included) they answer. While
 * another range, kind or status loads, the previous answer stays (`isPlaceholderData`), so a chart
 * moves from one to the other instead of blinking; label it from its own `range`, never from what
 * is being loaded, so old figures never sit under new words.
 */
export function useReportByCategory(range: ByCategoryRange) {
  const api = useApi();
  return useQuery({
    queryKey: queryKeys.byCategory(range),
    placeholderData: keepPreviousData,
    queryFn: async ({ signal }) => ({
      ...dataOf(
        await api.GET("/v1/reports/by-category", {
          params: {
            query: {
              from: range.from,
              to: range.to,
              ...(range.kind ? { kind: range.kind } : {}),
              ...(range.status ? { status: range.status } : {}),
            },
          },
          signal,
        }),
      ),
      range,
    }),
  });
}

/** What `useReportByCategory` answers: totals per category and the range they are for. */
export type ByCategoryReport = NonNullable<ReturnType<typeof useReportByCategory>["data"]>;

/**
 * Income, expenses and budget per month over a range, with the `range` they answer; keeps the
 * previous answer while another range loads (label it from its own `range`).
 */
export function useTrend(range: ReportRange) {
  const api = useApi();
  return useQuery({
    queryKey: queryKeys.trend(range),
    placeholderData: keepPreviousData,
    queryFn: async ({ signal }) => ({
      ...dataOf(
        await api.GET("/v1/reports/trend", {
          params: { query: { from: range.from, to: range.to } },
          signal,
        }),
      ),
      range,
    }),
  });
}

/** What `useTrend` answers: one entry per month, oldest first, and the range they are for. */
export type TrendReport = NonNullable<ReturnType<typeof useTrend>["data"]>;

// -- Writes -----------------------------------------------------------------------------------
//
// Each write shows its result at once in the month's list and summary, undoes it if the API says
// no, and refetches either way so the screen ends up showing what the server has.

interface Optimistic {
  rollback: Rollback;
  months: string[];
}

/** Stops in-flight fetches that would overwrite the optimistic change, then applies it. */
async function applyOptimistic(
  qc: QueryClient,
  months: string[],
  apply: () => Rollback,
): Promise<Optimistic> {
  await Promise.all(keysFor(months).map((queryKey) => qc.cancelQueries({ queryKey })));
  return { rollback: apply(), months };
}

function settle(qc: QueryClient, months: string[]) {
  for (const queryKey of keysFor(months)) void qc.invalidateQueries({ queryKey });
  void qc.invalidateQueries({ queryKey: queryKeys.reports() });
  // Names you used before (and their usual category) change with every write.
  void qc.invalidateQueries({ queryKey: ["suggestions"] });
  // Whether the account has any transaction at all (home's "Trae tu historial").
  void qc.invalidateQueries({ queryKey: ["onboarding", "has-transactions"] });
}

function mutation<Vars, Result>(
  qc: QueryClient,
  run: (vars: Vars) => Promise<Result>,
  optimistic: (vars: Vars) => { months: string[]; apply: () => Rollback },
) {
  return {
    mutationFn: run,
    onMutate: (vars: Vars) => {
      const { months, apply } = optimistic(vars);
      return applyOptimistic(qc, months, apply);
    },
    onError: (_error: Error, _vars: Vars, context: Optimistic | undefined) => context?.rollback(),
    onSettled: (
      _data: Result | undefined,
      _error: Error | null,
      vars: Vars,
      context: Optimistic | undefined,
    ) => settle(qc, context?.months ?? optimistic(vars).months),
  };
}

/** A stand-in for a transaction the API has not confirmed yet. */
function draftFrom(qc: QueryClient, input: NewTransaction): TransactionDto {
  const now = new Date().toISOString();
  const sibling = qc.getQueryData<TransactionPages>(queryKeys.transactions(monthOf(input.date)))
    ?.pages[0]?.items[0];
  return {
    id: `pending-${crypto.randomUUID()}`,
    name: input.name,
    amount: input.amount,
    currency: sibling?.currency ?? "EUR",
    date: input.date,
    status: input.status ?? "paid",
    note: input.note ?? null,
    categoryId: input.categoryId,
    recurrenceId: null,
    importId: null,
    source: input.source ?? "app",
    needsReview: false,
    captureSource: null,
    createdAt: now,
    updatedAt: now,
  };
}

export interface CreateTransactionVars {
  input: NewTransaction;
  /**
   * Lets the API drop a duplicate if this intent is ever sent twice. A form holds one key per
   * intent (the add sheet makes one when it opens), so a retry of the same save is deduplicated;
   * without one, each call gets a new key.
   */
  idempotencyKey?: string;
}

export function useCreateTransaction() {
  const api = useApi();
  const qc = useQueryClient();
  return useMutation(
    mutation(
      qc,
      async ({ input, idempotencyKey = crypto.randomUUID() }: CreateTransactionVars) => {
        const created = dataOf(
          await api.POST("/v1/transactions", {
            body: input,
            headers: { "Idempotency-Key": idempotencyKey },
          }),
        );
        // With "Repetir" it also made a recurrence, which reaches the months it materializes in.
        if (input.repeat) void settleRecurrences(qc);
        return created;
      },
      ({ input }) => ({
        months: [monthOf(input.date)],
        apply: () => optimisticAdd(qc, draftFrom(qc, input)),
      }),
    ),
  );
}

/** `month` is the month of the list the transaction is shown in; `patch.date` may move it elsewhere. */
export interface UpdateTransactionVars {
  id: string;
  month: string;
  patch: TransactionPatch;
}

export function useUpdateTransaction() {
  const api = useApi();
  const qc = useQueryClient();
  return useMutation(
    mutation(
      qc,
      async ({ id, patch }: UpdateTransactionVars) =>
        dataOf(await api.PATCH("/v1/transactions/{id}", { params: { path: { id } }, body: patch })),
      ({ id, month, patch }) => ({
        months: patch.date ? [month, monthOf(patch.date)] : [month],
        apply: () => optimisticUpdate(qc, month, id, patch),
      }),
    ),
  );
}

export interface TransactionRef {
  id: string;
  month: string;
}

/** Deleting is undoable: the API keeps the transaction, and `useRestoreTransaction` brings it back. */
export function useDeleteTransaction() {
  const api = useApi();
  const qc = useQueryClient();
  return useMutation(
    mutation(
      qc,
      async ({ id }: TransactionRef) => {
        await api.DELETE("/v1/transactions/{id}", { params: { path: { id } } });
      },
      ({ id, month }) => ({ months: [month], apply: () => optimisticRemove(qc, month, id) }),
    ),
  );
}

/** Pass the transaction being brought back (the screen has it from the delete); it reappears at once. */
export function useRestoreTransaction() {
  const api = useApi();
  const qc = useQueryClient();
  return useMutation(
    mutation(
      qc,
      async ({ transaction }: { transaction: TransactionDto }) =>
        dataOf(
          await api.POST("/v1/transactions/{id}/restore", {
            params: { path: { id: transaction.id } },
          }),
        ),
      ({ transaction }) => ({
        months: [monthOf(transaction.date)],
        apply: () => optimisticAdd(qc, transaction),
      }),
    ),
  );
}

/** Marks a pending transaction paid. */
export function useMarkPaid() {
  const api = useApi();
  const qc = useQueryClient();
  return useMutation(
    mutation(
      qc,
      async ({ id }: TransactionRef) =>
        dataOf(
          await api.PATCH("/v1/transactions/{id}", {
            params: { path: { id } },
            body: { status: "paid" },
          }),
        ),
      ({ id, month }) => ({
        months: [month],
        apply: () => optimisticUpdate(qc, month, id, { status: "paid" }),
      }),
    ),
  );
}

/**
 * Confirms detected transactions at once ("Confirmar todos"), the mark gone from the lists as
 * soon as it is asked. The API takes 50 ids at most, so more go in batches; a batch that fails
 * puts every mark back.
 */
export function useConfirmReview() {
  const api = useApi();
  const qc = useQueryClient();
  return useMutation(
    mutation(
      qc,
      async ({ items }: { items: TransactionDto[] }) => {
        await confirmInBatches(
          items.map((tx) => tx.id),
          async (ids) => {
            dataOf(await api.POST("/v1/transactions/review", { body: { ids } }));
          },
        );
      },
      ({ items }) => ({
        months: [...new Set(items.map((tx) => monthOf(tx.date)))],
        apply: () => {
          const rollbacks = items.map((tx) =>
            optimisticUpdate(qc, monthOf(tx.date), tx.id, { needsReview: false }),
          );
          return () => {
            for (const rollback of rollbacks.reverse()) rollback();
          };
        },
      }),
    ),
  );
}

// -- Categories, budgets and recurrences ------------------------------------------------------
//
// Not optimistic: each waits for the API (the sheet shows a refusal, such as a name already
// taken) and then refetches what it changes.

export type CategoryPatch = JsonBody<"/v1/categories/{id}", "patch">;
export type NewCategoryBody = JsonBody<"/v1/categories", "post">;
export type NewRecurrence = JsonBody<"/v1/recurrences", "post">;
export type RecurrencePatch = JsonBody<"/v1/recurrences/{id}", "patch">;

/**
 * One category's transactions in a month, newest first, a page at a time. Under the month's key,
 * so every write that refetches the month refetches this too, and the optimistic changes reach it.
 */
export function useCategoryTransactions(month: string, categoryId: string) {
  return useTransactionPages([...queryKeys.transactions(month), "category", categoryId], {
    month,
    category: [categoryId],
  });
}

/** What a change to categories or budgets shows up in: the lists, every month's summary, reports. */
function settleCategories(qc: QueryClient) {
  return Promise.all([
    qc.invalidateQueries({ queryKey: queryKeys.categories() }),
    qc.invalidateQueries({ queryKey: ["summary"] }),
    qc.invalidateQueries({ queryKey: queryKeys.reports() }),
    qc.invalidateQueries({ queryKey: ["suggestions"] }),
  ]);
}

export function useCreateCategory() {
  const api = useApi();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (body: NewCategoryBody) => dataOf(await api.POST("/v1/categories", { body })),
    onSettled: () => settleCategories(qc),
  });
}

/**
 * Rename, restyle, change the kind (409 while it has transactions), archive or restore. Archiving
 * also ends the category's recurrences and drops their pending rows from today on (the API does
 * it), so those lists are refetched too.
 */
export function useUpdateCategory() {
  const api = useApi();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, patch }: { id: string; patch: CategoryPatch }) =>
      dataOf(await api.PATCH("/v1/categories/{id}", { params: { path: { id } }, body: patch })),
    onSettled: (_data, _error, { patch }) =>
      patch.archived
        ? Promise.all([settleCategories(qc), settleRecurrences(qc)])
        : settleCategories(qc),
  });
}

/** A category's budget from `effectiveFrom` (a month) on, in hundredths. */
export function useSetBudget() {
  const api = useApi();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      id,
      amount,
      effectiveFrom,
    }: {
      id: string;
      amount: number;
      effectiveFrom: string;
    }) =>
      dataOf(
        await api.PUT("/v1/categories/{id}/budget", {
          params: { path: { id } },
          body: { amount, effectiveFrom },
        }),
      ),
    onSettled: () => settleCategories(qc),
  });
}

/**
 * A recurrence's change reaches the months it materializes in (this one and the next): their
 * lists and summaries are refetched, which makes the API add the pending occurrences.
 */
function settleRecurrences(qc: QueryClient) {
  return Promise.all([
    qc.invalidateQueries({ queryKey: queryKeys.recurrences() }),
    qc.invalidateQueries({ queryKey: ["transactions"] }),
    qc.invalidateQueries({ queryKey: ["summary"] }),
    qc.invalidateQueries({ queryKey: queryKeys.reports() }),
    qc.invalidateQueries({ queryKey: ["onboarding", "has-transactions"] }),
  ]);
}

export function useCreateRecurrence() {
  const api = useApi();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (body: NewRecurrence) => dataOf(await api.POST("/v1/recurrences", { body })),
    onSettled: () => settleRecurrences(qc),
  });
}

export function useUpdateRecurrence() {
  const api = useApi();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, patch }: { id: string; patch: RecurrencePatch }) =>
      dataOf(await api.PATCH("/v1/recurrences/{id}", { params: { path: { id } }, body: patch })),
    onSettled: () => settleRecurrences(qc),
  });
}

/** Deletes the rule; the transactions it already made stay. */
export function useDeleteRecurrence() {
  const api = useApi();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id }: { id: string }) => {
      await api.DELETE("/v1/recurrences/{id}", { params: { path: { id } } });
    },
    onSettled: () => settleRecurrences(qc),
  });
}
