import type { MonthSummary, TransactionDto } from "@wambito/core";
import { describe, expect, it } from "vitest";
import {
  feedbackForSave,
  groupByDay,
  groupNewestFirst,
  homeWambiLine,
  orderByUse,
  overallState,
  reviewMark,
} from "./home-model.ts";

function tx(id: string, date: string, amount: number, status: "paid" | "pending" = "paid") {
  return {
    id,
    name: id,
    amount,
    currency: "EUR",
    date,
    status,
    note: null,
    categoryId: "cat-groceries",
    recurrenceId: null,
    importId: null,
    source: "web",
    needsReview: false,
    captureSource: null,
    createdAt: "2026-10-01T10:00:00.000Z",
    updatedAt: "2026-10-01T10:00:00.000Z",
  } satisfies TransactionDto;
}

describe("groupByDay", () => {
  it("puts today first, then the past (newest first), then the upcoming days (nearest first)", () => {
    // The API sends the month newest first.
    const items = [
      tx("internet", "2026-10-28", -3990, "pending"),
      tx("streaming", "2026-10-23", -799, "pending"),
      tx("coffee", "2026-10-21", -120),
      tx("lunch", "2026-10-21", -1240),
      tx("bus", "2026-10-08", -200),
      tx("salary", "2026-10-01", 300000),
    ];
    const groups = groupByDay(items, "2026-10-21");
    expect(groups.map((g) => [g.date, g.when])).toEqual([
      ["2026-10-21", "today"],
      ["2026-10-08", "past"],
      ["2026-10-01", "past"],
      ["2026-10-23", "upcoming"],
      ["2026-10-28", "upcoming"],
    ]);
    expect(groups[0]?.items.map((t) => t.id)).toEqual(["coffee", "lunch"]);
    expect(groups[0]?.total).toBe(-1360);
    expect(groups[2]?.total).toBe(300000);
  });

  it("keeps the pending days still to come after yesterday, not between today and yesterday", () => {
    const items = [
      tx("internet", "2026-11-28", -3990, "pending"),
      tx("plan", "2026-11-26", -1039, "pending"),
      tx("gym", "2026-11-02", -3200),
      tx("uber", "2026-11-02", -316),
      tx("sushi", "2026-11-01", -1093),
    ];
    const groups = groupByDay(items, "2026-11-02");
    expect(groups.map((g) => [g.date, g.when, g.total])).toEqual([
      ["2026-11-02", "today", -3516],
      ["2026-11-01", "yesterday", -1093],
      ["2026-11-26", "upcoming", -1039],
      ["2026-11-28", "upcoming", -3990],
    ]);
  });

  it("marks the day before today as yesterday", () => {
    const groups = groupByDay([tx("a", "2026-10-20", -1), tx("b", "2026-10-19", -1)], "2026-10-21");
    expect(groups.map((g) => g.when)).toEqual(["yesterday", "past"]);
  });

  it("works across a month boundary for yesterday", () => {
    expect(groupByDay([tx("a", "2026-09-30", -1)], "2026-10-01")[0]?.when).toBe("yesterday");
  });

  it("is empty without transactions", () => {
    expect(groupByDay([], "2026-10-21")).toEqual([]);
  });
});

const category = (
  categoryId: string,
  budget: number | null,
  spent: number,
  state: "ok" | "near" | "over" = "ok",
) => ({
  categoryId,
  budget,
  spent,
  remaining: budget === null ? null : budget - spent,
  ratio: budget ? spent / budget : null,
  state,
});

function summary(over: Partial<MonthSummary> = {}): MonthSummary {
  return {
    month: "2026-10",
    budgetTotal: 100000,
    spent: 40000,
    remaining: 60000,
    income: 0,
    balance: -40000,
    categories: [category("cat-groceries", 50000, 30000), category("cat-fun", 50000, 10000)],
    ...over,
  };
}

const names: Record<string, string> = {
  "cat-groceries": "Supermercado",
  "cat-fun": "Ocio",
  "cat-salary": "Salario",
};
const base = {
  today: "2026-10-21",
  todayCount: 0,
  categoryName: (id: string) => names[id] ?? "?",
  money: (cents: number) => `${(cents / 100).toFixed(2)} €`,
};

describe("homeWambiLine", () => {
  it("fills core's params with the category's name and formatted money", () => {
    const line = homeWambiLine({
      ...base,
      summary: summary({
        categories: [category("cat-groceries", 50000, 45000, "near"), category("cat-fun", 0, 0)],
      }),
    });
    expect(line).toEqual({
      key: "wambi.near_limit",
      varied: true,
      params: { category: "Supermercado", remaining: "50.00 €" },
    });
  });

  it("formats the overspend as a positive amount", () => {
    const line = homeWambiLine({
      ...base,
      summary: summary({ categories: [category("cat-groceries", 50000, 51408, "over")] }),
    });
    expect(line.key).toBe("wambi.over_budget");
    expect(line.params).toEqual({ category: "Supermercado", over: "14.08 €" });
  });

  it("keeps numbers that are not money (days left) as numbers", () => {
    const line = homeWambiLine({ ...base, summary: summary() });
    expect(line).toEqual({
      key: "wambi.on_track",
      varied: true,
      params: { remaining: "600.00 €", daysLeft: 11 },
    });
  });

  it("talks about an income event's amount and names it", () => {
    const line = homeWambiLine({
      ...base,
      summary: summary(),
      todayCount: 2,
      event: { kind: "saved", categoryId: "cat-salary", amount: 250000, name: "Nómina" },
    });
    expect(line).toEqual({
      key: "wambi.income_received",
      varied: true,
      params: { amount: "2500.00 €", name: "Nómina", category: "Salario" },
    });
  });

  it("names a paid movement, or says its category when it has no name", () => {
    const paid = (name: string) =>
      homeWambiLine({
        ...base,
        summary: summary(),
        todayCount: 2,
        event: { kind: "paid", categoryId: "cat-fun", amount: -3200, name },
      });
    expect(paid("gym")).toEqual({
      key: "wambi.pending_paid",
      varied: true,
      params: { amount: "32.00 €", name: "gym", category: "Ocio" },
    });
    expect(paid("").params).toEqual({ amount: "32.00 €", name: "Ocio", category: "Ocio" });
  });

  it("without budgets, never says what is left: it says what was spent", () => {
    const line = homeWambiLine({
      ...base,
      summary: summary({
        budgetTotal: 0,
        remaining: -40000,
        categories: [category("cat-groceries", null, 40000)],
      }),
    });
    expect(line).toEqual({
      key: "home.wambi_no_budget",
      varied: false,
      params: { spent: "400.00 €" },
    });
  });

  it("on an empty month without budgets, invites the first entry", () => {
    const line = homeWambiLine({
      ...base,
      summary: summary({ budgetTotal: 0, spent: 0, remaining: 0, categories: [] }),
    });
    expect(line).toEqual({ key: "home.wambi_empty", varied: false, params: {} });
  });

  it("never calls a negative total 'on track'", () => {
    const line = homeWambiLine({
      ...base,
      summary: summary({ budgetTotal: 10000, spent: 15000, remaining: -5000 }),
    });
    expect(line).toEqual({
      key: "home.wambi_over_total",
      varied: false,
      params: { over: "50.00 €" },
    });
  });

  it("keeps the save's own message (first of the day) even without budgets", () => {
    const line = homeWambiLine({
      ...base,
      todayCount: 1,
      summary: summary({ budgetTotal: 0, categories: [category("cat-groceries", null, 608)] }),
      event: { kind: "saved", categoryId: "cat-groceries", amount: -608, name: "pan" },
    });
    expect(line.key).toBe("wambi.first_of_day");
    expect(line.params).toEqual({ name: "pan", category: "Supermercado" });
  });
});

describe("orderByUse", () => {
  it("puts the most used first, then keeps the categories' own order", () => {
    const categories = [
      { id: "a", sortOrder: 0 },
      { id: "b", sortOrder: 1 },
      { id: "c", sortOrder: 2 },
      { id: "d", sortOrder: 3 },
    ];
    const used = [{ categoryId: "c" }, { categoryId: "c" }, { categoryId: "b" }];
    expect(orderByUse(categories, used).map((c) => c.id)).toEqual(["c", "b", "a", "d"]);
  });
});

describe("feedbackForSave", () => {
  const after = summary({
    categories: [
      category("cat-groceries", 50000, 45000, "near"),
      category("cat-fun", 10000, 12000, "over"),
      category("cat-home", 10000, 100),
    ],
  });
  it("is incomeSaved for income", () => {
    expect(feedbackForSave(after, "cat-salary", "income")).toBe("incomeSaved");
  });
  it("follows the category's state after the save", () => {
    expect(feedbackForSave(after, "cat-groceries", "expense")).toBe("nearLimit");
    expect(feedbackForSave(after, "cat-fun", "expense")).toBe("overBudget");
    expect(feedbackForSave(after, "cat-home", "expense")).toBe("expenseSaved");
  });
  it("celebrates when the month is not loaded", () => {
    expect(feedbackForSave(undefined, "cat-home", "expense")).toBe("expenseSaved");
  });
});

describe("overallState", () => {
  it("is near from 80% of the budget and over past it", () => {
    expect(overallState(100, 79)).toBe("ok");
    expect(overallState(100, 80)).toBe("near");
    expect(overallState(100, 101)).toBe("over");
    expect(overallState(0, 0)).toBe("ok");
  });
});

// -- Detected transactions -------------------------------------------------------------------------

function detected(id: string, captureSource: TransactionDto["captureSource"], needsReview = true) {
  return { ...tx(id, "2026-10-21", -1240), source: "capture" as const, captureSource, needsReview };
}

describe("reviewMark", () => {
  it("is null for a transaction that needs no review", () => {
    expect(reviewMark(tx("lunch", "2026-10-21", -1240))).toBeNull();
    expect(reviewMark(detected("done", "revolut", false))).toBeNull();
  });

  it("names where a detected transaction came from", () => {
    expect(reviewMark(detected("a", "revolut"))).toBe("revolut");
    expect(reviewMark(detected("b", "google_wallet"))).toBe("google_wallet");
  });

  it("still marks one whose source is unknown", () => {
    expect(reviewMark(detected("c", null))).toBe("other");
  });
});

describe("groupNewestFirst", () => {
  it("keeps the API order: a future pending day stays above older days", () => {
    const items = [
      tx("c", "2026-10-25", -100, "pending"),
      tx("b", "2026-10-21", -200),
      tx("a", "2026-10-20", -300),
      tx("a2", "2026-10-20", -50),
    ];
    const groups = groupNewestFirst(items, "2026-10-21");
    expect(groups.map((g) => [g.date, g.when])).toEqual([
      ["2026-10-25", "upcoming"],
      ["2026-10-21", "today"],
      ["2026-10-20", "yesterday"],
    ]);
    expect(groups[2]?.total).toBe(-350);
    expect(groups[2]?.items.map((i) => i.id)).toEqual(["a", "a2"]);
  });
});
