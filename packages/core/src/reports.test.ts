import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";
import type { BudgetEntry, Month } from "./index.ts";
import type { ReportCategory, ReportTransaction } from "./reports.ts";
import { byCategory, trend } from "./reports.ts";

interface Cases {
  categories: ReportCategory[];
  transactions: ReportTransaction[];
  budgets: BudgetEntry[];
  byCategory: {
    id: string;
    months: Month[];
    kind?: "expense" | "income";
    status?: "paid" | "pending";
    expect: unknown;
  }[];
  trend: { id: string; months: Month[]; expect: unknown }[];
}

const cases = JSON.parse(
  readFileSync(fileURLToPath(new URL("../reports/cases.json", import.meta.url)), "utf8"),
) as Cases;

describe("byCategory (shared cases)", () => {
  for (const c of cases.byCategory) {
    test(c.id, () => {
      expect(
        byCategory({
          transactions: cases.transactions,
          categories: cases.categories,
          months: c.months,
          kind: c.kind,
          status: c.status,
        }),
      ).toEqual(c.expect);
    });
  }
});

describe("trend (shared cases)", () => {
  for (const c of cases.trend) {
    test(c.id, () => {
      expect(
        trend({
          transactions: cases.transactions,
          categories: cases.categories,
          budgets: cases.budgets,
          months: c.months,
        }),
      ).toEqual(c.expect);
    });
  }
});
