import { useQuery } from "@tanstack/react-query";
import { monthOf, type SupportedCurrency, todayIn } from "@wambito/core";
import { useApi } from "../../api/ApiProvider.tsx";
import type { ApiClient } from "../../api/client.ts";
import { ApiProblem } from "../../api/errors.ts";
import type { paths } from "../../api/schema";
import type { Locale } from "../../i18n/format.ts";
import { parseBudgetInput } from "./budget-input.ts";
import type { ImportDto } from "./import-state.ts";
import {
  SUGGESTED_CATEGORIES,
  type SuggestedCategory,
  suggestionFor,
  suggestionName,
} from "./suggested-categories.ts";

export type Profile = paths["/v1/me"]["get"]["responses"][200]["content"]["application/json"];
export type Category =
  paths["/v1/categories"]["get"]["responses"][200]["content"]["application/json"][number];

/** The data of a successful call (failures already threw an `ApiProblem`). */
export function dataOf<T>(result: { data?: T; response: Response }): T {
  if (result.data === undefined) {
    throw new ApiProblem({ status: result.response.status, code: "internal_error" });
  }
  return result.data;
}

export async function uploadImport(api: ApiClient, file: File): Promise<ImportDto> {
  // openapi-fetch sends FormData as is (the browser sets the multipart boundary).
  const form = new FormData();
  form.append("source", "budge");
  form.append("file", file);
  return dataOf(
    await api.POST("/v1/imports", { body: form as unknown as { source: "budge"; file: string } }),
  );
}

export async function patchCurrency(api: ApiClient, code: SupportedCurrency): Promise<Profile> {
  return dataOf(await api.PATCH("/v1/me", { body: { currency: code } }));
}

/** Every category, archived ones included: what "already exists" is decided against. */
export async function allCategories(api: ApiClient): Promise<Category[]> {
  return dataOf(
    await api.GET("/v1/categories", { params: { query: { includeArchived: "true" } } }),
  );
}

/** The body that creates a suggested category, named in the person's language. */
export function suggestionBody(suggestion: SuggestedCategory, locale: Locale) {
  return {
    name: suggestionName(suggestion, locale),
    kind: suggestion.kind,
    icon: suggestion.glyph,
    color: suggestion.tint,
    sortOrder: SUGGESTED_CATEGORIES.indexOf(suggestion),
  };
}

const nameTaken = (problem: unknown) =>
  problem instanceof ApiProblem && problem.code === "category_name_taken";

/**
 * Makes sure the suggestions in `keys` are active categories: one they have active stays as it
 * is, one that exists only archived is brought back (so "Usar las sugeridas" works after every
 * suggestion was deselected), and the missing ones are created. It reads the categories first and
 * a 409 `category_name_taken` counts as created, so after a partial failure (a lost connection
 * halfway) running it again finishes the job instead of failing on the ones already there.
 */
export async function createSuggestions(
  api: ApiClient,
  keys: ReadonlySet<string>,
  locale: Locale,
): Promise<void> {
  const all = await allCategories(api);
  const active = new Set(all.filter((c) => !c.archived).map((c) => suggestionFor(c.name)?.key));
  await Promise.all(
    SUGGESTED_CATEGORIES.filter((s) => keys.has(s.key) && !active.has(s.key)).map(async (s) => {
      const archived = all.find((c) => c.archived && suggestionFor(c.name)?.key === s.key);
      if (archived) {
        dataOf(
          await api.PATCH("/v1/categories/{id}", {
            params: { path: { id: archived.id } },
            body: { archived: false },
          }),
        );
        return;
      }
      try {
        await api.POST("/v1/categories", { body: suggestionBody(s, locale) });
      } catch (problem) {
        if (!nameTaken(problem)) throw problem;
      }
    }),
  );
}

/**
 * Whether the account has any transaction: then its currency is locked, and what it has is what
 * the currency step shows.
 */
export function useHasTransactions() {
  const api = useApi();
  return useQuery({
    queryKey: ["onboarding", "has-transactions"],
    queryFn: async ({ signal }) =>
      dataOf(await api.GET("/v1/transactions", { params: { query: { limit: 1 } }, signal })).items
        .length > 0,
  });
}

/** What can be changed on one of the person's categories from the edit sheet. */
export interface CategoryEdit {
  name: string;
  glyph: string;
  tint: string;
  kind: "expense" | "income";
}

/**
 * How many transactions a category has, counting up to `cap` (pages of 200); `capped` when there
 * are at least that many. It decides whether the category can be deleted here.
 */
export async function countCategoryTransactions(
  api: ApiClient,
  categoryId: string,
  cap = 2000,
): Promise<{ count: number; capped: boolean }> {
  let count = 0;
  let cursor: string | undefined;
  do {
    const page = dataOf(
      await api.GET("/v1/transactions", {
        params: { query: { category: [categoryId], limit: 200, ...(cursor ? { cursor } : {}) } },
      }),
    );
    count += page.items.length;
    cursor = page.nextCursor ?? undefined;
  } while (cursor && count < cap);
  return { count, capped: Boolean(cursor) };
}

/**
 * Saves an edit of one of the person's categories, in one PATCH: name, emoji, tint, and the kind
 * when it changed. The API refuses a kind change (409 `category_has_transactions`) while the
 * category has transactions, so the count the sheet shows is only a hint.
 */
export async function saveCategoryEdit(
  api: ApiClient,
  category: Category,
  edit: CategoryEdit,
): Promise<Category> {
  return dataOf(
    await api.PATCH("/v1/categories/{id}", {
      params: { path: { id: category.id } },
      body: {
        name: edit.name,
        icon: edit.glyph,
        color: edit.tint,
        ...(edit.kind !== category.kind ? { kind: edit.kind } : {}),
      },
    }),
  );
}

/** Archives one of the person's categories ("Eliminar" with no transactions, or "Archivar"). */
export async function archiveCategory(api: ApiClient, id: string): Promise<void> {
  dataOf(
    await api.PATCH("/v1/categories/{id}", { params: { path: { id } }, body: { archived: true } }),
  );
}

/**
 * Applies the categories step: the chosen suggestions are made (or brought back, when an archived
 * category already has that name), and with `archive` the person's categories they deselected are
 * archived. SALTAR passes `archive: false`: skipping never takes anything away.
 */
export async function applyCategorySelection(
  api: ApiClient,
  chips: readonly { id: string; source: "category" | "suggestion"; suggestionKey?: string }[],
  selected: ReadonlySet<string>,
  locale: Locale,
  { archive }: { archive: boolean },
): Promise<void> {
  const all = await allCategories(api);
  const writes: Promise<unknown>[] = [];
  for (const chip of chips) {
    const chosen = selected.has(chip.id);
    if (chip.source === "category") {
      if (archive && !chosen) writes.push(archiveCategory(api, chip.id));
      continue;
    }
    const suggestion = SUGGESTED_CATEGORIES.find((s) => s.key === chip.suggestionKey);
    if (!chosen || !suggestion) continue;
    const archived = all.find((c) => c.archived && suggestionFor(c.name)?.key === suggestion.key);
    if (archived) {
      writes.push(
        api.PATCH("/v1/categories/{id}", {
          params: { path: { id: archived.id } },
          body: { archived: false },
        }),
      );
      continue;
    }
    writes.push(
      api.POST("/v1/categories", { body: suggestionBody(suggestion, locale) }).catch((problem) => {
        if (!nameTaken(problem)) throw problem;
      }),
    );
  }
  await Promise.all(writes);
}

/**
 * Saves the budgets typed or prefilled, from this month on (in the profile's time zone): each
 * valid amount that differs from what the category already has. Empty fields write nothing.
 */
export async function saveBudgets(
  api: ApiClient,
  categories: readonly Category[],
  drafts: Readonly<Record<string, string>>,
  locale: Locale,
  timezone: string,
): Promise<void> {
  const month = monthOf(todayIn(timezone));
  await Promise.all(
    categories
      .filter((c) => c.kind === "expense" && !c.archived)
      .map(async (c) => {
        let amount: number | null;
        try {
          amount = parseBudgetInput(drafts[c.id] ?? "", locale);
        } catch {
          return;
        }
        if (amount === null || c.currentBudget === amount) return;
        dataOf(
          await api.PUT("/v1/categories/{id}/budget", {
            params: { path: { id: c.id } },
            body: { amount, effectiveFrom: month },
          }),
        );
      }),
  );
}
