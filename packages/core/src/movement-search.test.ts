import { describe, expect, it } from "vitest";
import { foldText, matchesMovementSearch, movementTotals } from "./movement-search.ts";

const tx = (over: Partial<Parameters<typeof matchesMovementSearch>[0]> = {}) => ({
  name: "Café Juan Valdez",
  note: "con Valdez" as string | null,
  categoryId: "cat-food",
  amount: -500,
  status: "paid" as const,
  ...over,
});

describe("foldText", () => {
  it("lowers case and strips accents", () => {
    expect(foldText("CAFÉ Ñandú")).toBe("cafe nandu");
  });
});

describe("matchesMovementSearch", () => {
  it("matches a term in the name or the note after folding", () => {
    expect(matchesMovementSearch(tx({ note: null }), { terms: ["cafe"] })).toBe(true);
    expect(matchesMovementSearch(tx({ name: "Lunch" }), { terms: ["valdez"] })).toBe(true);
    expect(matchesMovementSearch(tx({ name: "Lunch" }), { terms: ["pizza"] })).toBe(false);
  });
  it("needs only one of several terms", () => {
    expect(matchesMovementSearch(tx(), { terms: ["pizza", "cafe"] })).toBe(true);
  });
  it("needs only one of several categories", () => {
    expect(matchesMovementSearch(tx(), { categoryIds: ["x", "cat-food"] })).toBe(true);
    expect(matchesMovementSearch(tx(), { categoryIds: ["x", "y"] })).toBe(false);
  });
  it("match all needs terms and categories, any needs one", () => {
    const s = { terms: ["cafe"], categoryIds: ["other"] };
    expect(matchesMovementSearch(tx(), { ...s, match: "all" })).toBe(false);
    expect(matchesMovementSearch(tx(), { ...s, match: "any" })).toBe(true);
    expect(
      matchesMovementSearch(tx(), { terms: ["pizza"], categoryIds: ["other"], match: "any" }),
    ).toBe(false);
  });
  it("kind holds under any too", () => {
    expect(matchesMovementSearch(tx(), { kind: "expense" })).toBe(true);
    expect(matchesMovementSearch(tx(), { kind: "income" })).toBe(false);
    expect(matchesMovementSearch(tx({ amount: 900 }), { kind: "income" })).toBe(true);
    expect(matchesMovementSearch(tx(), { terms: ["cafe"], kind: "income", match: "any" })).toBe(
      false,
    );
  });
  it("status holds under any too", () => {
    expect(matchesMovementSearch(tx(), { status: "pending" })).toBe(false);
    expect(matchesMovementSearch(tx(), { terms: ["cafe"], status: "pending", match: "any" })).toBe(
      false,
    );
    expect(matchesMovementSearch(tx(), { status: "paid" })).toBe(true);
  });
  it("trims terms and ignores blank ones", () => {
    expect(matchesMovementSearch(tx(), { terms: [" cafe "] })).toBe(true);
    expect(matchesMovementSearch(tx(), { terms: ["  "] })).toBe(true);
  });
  it("defaults to match all", () => {
    expect(matchesMovementSearch(tx(), { terms: ["cafe"], categoryIds: ["other"] })).toBe(false);
    expect(matchesMovementSearch(tx(), { terms: ["cafe"], categoryIds: ["cat-food"] })).toBe(true);
  });
  it("a zero amount is neither expense nor income", () => {
    expect(matchesMovementSearch(tx({ amount: 0 }), { kind: "expense" })).toBe(false);
    expect(matchesMovementSearch(tx({ amount: 0 }), { kind: "income" })).toBe(false);
  });
  it("an empty search matches everything", () => {
    expect(matchesMovementSearch(tx(), {})).toBe(true);
    expect(matchesMovementSearch(tx(), { terms: [], categoryIds: [] })).toBe(true);
  });
});

describe("movementTotals", () => {
  it("counts and sums expenses and income", () => {
    expect(movementTotals([{ amount: -500 }, { amount: -250 }, { amount: 1000 }])).toEqual({
      count: 3,
      expense: 750,
      income: 1000,
    });
  });
});
