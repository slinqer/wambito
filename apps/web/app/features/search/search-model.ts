/** The search screen's filters, their URL form and the API query they become. */

export interface SearchFilters {
  text: string;
  kind: "all" | "expense" | "income";
  categoryIds: string[];
  status: "all" | "paid" | "pending";
}

export const emptyFilters: SearchFilters = {
  text: "",
  kind: "all",
  categoryIds: [],
  status: "all",
};

const KINDS = ["expense", "income"] as const;
const STATUSES = ["paid", "pending"] as const;

export function filtersFromParams(p: URLSearchParams): SearchFilters {
  const kind = p.get("kind");
  const status = p.get("status");
  return {
    text: p.get("q") ?? "",
    kind: KINDS.find((k) => k === kind) ?? "all",
    categoryIds: p.getAll("category"),
    status: STATUSES.find((s) => s === status) ?? "all",
  };
}

/** Defaults are left out, so no filter gives an empty query string. */
export function filtersToParams(f: SearchFilters): URLSearchParams {
  const p = new URLSearchParams();
  if (f.text !== "") p.set("q", f.text);
  if (f.kind !== "all") p.set("kind", f.kind);
  for (const id of f.categoryIds) p.append("category", id);
  if (f.status !== "all") p.set("status", f.status);
  return p;
}

export function isSearching(f: SearchFilters): boolean {
  return f.text.trim() !== "" || f.kind !== "all" || f.categoryIds.length > 0 || f.status !== "all";
}

export interface SearchApiQuery {
  q?: string[];
  kind?: "expense" | "income";
  category?: string[];
  status?: "paid" | "pending";
  totals?: "true";
  cursor?: string;
  limit: 50;
}

/** The list query for one page: the totals cover every match, so only the first page asks for them. */
export function toApiQuery(f: SearchFilters, cursor: string | null = null): SearchApiQuery {
  const text = f.text.trim();
  return {
    ...(text !== "" ? { q: [text] } : {}),
    ...(f.kind !== "all" ? { kind: f.kind } : {}),
    ...(f.categoryIds.length > 0 ? { category: f.categoryIds } : {}),
    ...(f.status !== "all" ? { status: f.status } : {}),
    ...(cursor ? { cursor } : { totals: "true" as const }),
    limit: 50,
  };
}
