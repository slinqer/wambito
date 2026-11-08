import { type Profile, ToolError, type Wambito } from "@wambito/ai-assistant-tools";
import createClient from "openapi-fetch";
import type { paths } from "./api/schema.d.ts";

type ApiClient = ReturnType<typeof createClient<paths>>;

interface Problem {
  code?: string;
  title?: string;
  detail?: string;
  errors?: { path: string; message: string }[];
}

/** What the API's answer means for the model: its problem code and words, or a plain failure. */
function toToolError(status: number, problem: Problem | undefined): ToolError {
  const code = problem?.code ?? (status === 404 ? "not_found" : `http_${status}`);
  const message = problem?.detail ?? problem?.title ?? `Wambito answered ${status}`;
  return new ToolError(code, message, problem?.errors ? { errors: problem.errors } : undefined);
}

/**
 * Unwraps an openapi-fetch result: the data, or a ToolError with the API's problem. A missing body
 * on success (204) is fine for the callers that expect none.
 */
async function unwrap<T>(
  call: Promise<{ data?: T; error?: unknown; response: Response }>,
): Promise<T> {
  const { data, error, response } = await call;
  if (!response.ok) throw toToolError(response.status, error as Problem | undefined);
  return data as T;
}

/**
 * The person's Wambito over the HTTP API, with the assistant's own access token: the API applies
 * every rule and the token's scopes, exactly as for the app.
 */
export function apiWambito(baseUrl: string, token: string, fetchImpl?: typeof fetch): Wambito {
  const api: ApiClient = createClient<paths>({
    baseUrl: baseUrl.replace(/\/+$/, ""),
    headers: { authorization: `Bearer ${token}` },
    ...(fetchImpl ? { fetch: fetchImpl } : {}),
  });
  let profile: Promise<Profile> | undefined;

  return {
    profile() {
      profile ??= unwrap(api.GET("/v1/me")).then(
        (me): Profile => ({
          timezone: me.timezone,
          locale: me.locale as Profile["locale"],
          currency: me.currency,
        }),
      );
      return profile;
    },
    monthSummary: (month) => unwrap(api.GET("/v1/summary", { params: { query: { month } } })),
    listTransactions: (q) =>
      unwrap(
        api.GET("/v1/transactions", {
          params: {
            query: {
              month: q.month,
              from: q.from,
              to: q.to,
              kind: q.kind,
              q: q.q,
              category: q.categoryIds,
              match: q.match,
              totals: q.totals === undefined ? undefined : q.totals ? "true" : "false",
              status: q.status,
              needsReview:
                q.needsReview === undefined ? undefined : q.needsReview ? "true" : "false",
              cursor: q.cursor,
              limit: q.limit,
            },
          },
        }),
      ),
    categoryReport: (r) =>
      unwrap(api.GET("/v1/reports/by-category", { params: { query: r } })).then((report) => ({
        total: report.total,
        items: report.items.map((i) => ({ categoryId: i.categoryId, total: i.total })),
      })),
    trend: (r) => unwrap(api.GET("/v1/reports/trend", { params: { query: r } })),
    listCategories: () =>
      unwrap(api.GET("/v1/categories", { params: { query: { includeArchived: "true" } } })),
    listRecurrences: () => unwrap(api.GET("/v1/recurrences")),
    async addTransactions(items, idempotencyKey) {
      const { data, error, response } = await api.POST("/v1/transactions/batch", {
        params: { header: { "Idempotency-Key": idempotencyKey } },
        body: { items },
      });
      if (!response.ok) throw toToolError(response.status, error as Problem | undefined);
      return {
        items: data?.items ?? [],
        replayed: response.headers.get("idempotent-replayed") === "true",
      };
    },
    updateTransaction: (id, patch) =>
      unwrap(api.PATCH("/v1/transactions/{id}", { params: { path: { id } }, body: patch })),
    async deleteTransactions(ids) {
      await unwrap(api.POST("/v1/transactions/batch-delete", { body: { ids } }));
    },
    restoreTransaction: (id) =>
      unwrap(api.POST("/v1/transactions/{id}/restore", { params: { path: { id } } })),
    setBudget: (categoryId, budget) =>
      unwrap(
        api.PUT("/v1/categories/{id}/budget", {
          params: { path: { id: categoryId } },
          body: budget,
        }),
      ),
    createCategory: (category) => unwrap(api.POST("/v1/categories", { body: category })),
    updateCategory: (id, patch) =>
      unwrap(api.PATCH("/v1/categories/{id}", { params: { path: { id } }, body: patch })),
    createRecurrence: (recurrence) => unwrap(api.POST("/v1/recurrences", { body: recurrence })),
    updateRecurrence: (id, patch) =>
      unwrap(api.PATCH("/v1/recurrences/{id}", { params: { path: { id } }, body: patch })),
    async deleteRecurrence(id) {
      await unwrap(api.DELETE("/v1/recurrences/{id}", { params: { path: { id } } }));
    },
  };
}
