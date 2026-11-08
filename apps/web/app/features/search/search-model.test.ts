import { describe, expect, it } from "vitest";
import {
  emptyFilters,
  filtersFromParams,
  filtersToParams,
  isSearching,
  type SearchFilters,
  toApiQuery,
} from "./search-model.ts";

describe("search filters in the URL", () => {
  it("round-trips a full filter set", () => {
    const f: SearchFilters = {
      text: "café con leche",
      kind: "expense",
      categoryIds: ["a", "b"],
      status: "pending",
    };
    const params = filtersToParams(f);
    expect(params.getAll("category")).toEqual(["a", "b"]);
    expect(filtersFromParams(new URLSearchParams(params.toString()))).toEqual(f);
  });

  it("gives an empty query string for the defaults", () => {
    expect(filtersToParams(emptyFilters).toString()).toBe("");
    expect(filtersFromParams(new URLSearchParams(""))).toEqual(emptyFilters);
  });

  it("ignores values it does not know", () => {
    const p = new URLSearchParams("kind=nope&status=late");
    expect(filtersFromParams(p)).toEqual(emptyFilters);
  });
});

describe("isSearching", () => {
  it("is false for blank text and true for any filter", () => {
    expect(isSearching({ ...emptyFilters, text: "   " })).toBe(false);
    expect(isSearching({ ...emptyFilters, kind: "income" })).toBe(true);
    expect(isSearching({ ...emptyFilters, categoryIds: ["a"] })).toBe(true);
    expect(isSearching({ ...emptyFilters, status: "paid" })).toBe(true);
    expect(isSearching({ ...emptyFilters, text: "x" })).toBe(true);
  });
});

describe("toApiQuery", () => {
  it("trims the text, sends it as one term and omits the all values", () => {
    expect(toApiQuery({ ...emptyFilters, text: "  cafe " })).toEqual({
      q: ["cafe"],
      totals: "true",
      limit: 50,
    });
  });

  it("sends the filters that are set", () => {
    expect(toApiQuery({ text: "", kind: "income", categoryIds: ["a"], status: "paid" })).toEqual({
      kind: "income",
      category: ["a"],
      status: "paid",
      totals: "true",
      limit: 50,
    });
  });

  it("asks for the totals only on the first page and sends the cursor on later ones", () => {
    const later = toApiQuery({ ...emptyFilters, text: "cafe" }, "2026-10-01|abc");
    expect(later).toEqual({ q: ["cafe"], cursor: "2026-10-01|abc", limit: 50 });
    expect(later).not.toHaveProperty("totals");
  });
});
