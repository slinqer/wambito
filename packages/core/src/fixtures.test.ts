import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";
import { effectiveBudget } from "./budget.ts";
import { costOfLiving } from "./cost-of-living.ts";
import { addMonths, firstDay, isMonth, lastDay, monthOf, monthsBetween, todayIn } from "./dates.ts";
import { matchesMovementSearch, movementTotals } from "./movement-search.ts";
import { occurrences } from "./recurrence.ts";
import { monthSummary } from "./summary.ts";

interface FixtureCase {
  name: string;
  fn?: string;
  input: unknown[];
  expected: unknown;
}

function load(file: string): FixtureCase[] {
  const url = new URL(`../fixtures/${file}`, import.meta.url);
  return (JSON.parse(readFileSync(fileURLToPath(url), "utf8")) as { cases: FixtureCase[] }).cases;
}

type Fn = (...args: any[]) => unknown;

function run(file: string, fns: Record<string, Fn>, only?: string) {
  const cases = load(file);
  test("has at least three cases per function", () => {
    const counts = new Map<string, number>();
    for (const c of cases) {
      const key = only ?? (c.fn as string);
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
    expect([...counts.keys()].sort()).toEqual(Object.keys(fns).sort());
    for (const [fn, n] of counts) expect(n, fn).toBeGreaterThanOrEqual(3);
  });
  for (const c of cases) {
    test(c.name, () => {
      const fn = fns[only ?? (c.fn as string)];
      if (!fn) throw new Error(`unknown function ${c.fn}`);
      // JSON has no -0 (monthSummary reports `remaining: -0` for a zero budget), so compare the
      // result as JSON would carry it.
      expect(JSON.parse(JSON.stringify(fn(...c.input)))).toEqual(c.expected);
    });
  }
}

describe("summary.json", () => run("summary.json", { monthSummary }, "monthSummary"));
describe("budget.json", () => run("budget.json", { effectiveBudget }, "effectiveBudget"));
describe("recurrence.json", () => run("recurrence.json", { occurrences }, "occurrences"));
describe("cost-of-living.json", () => run("cost-of-living.json", { costOfLiving }, "costOfLiving"));
describe("movement-search.json", () =>
  run("movement-search.json", { matchesMovementSearch, movementTotals }));
describe("dates.json", () =>
  run("dates.json", {
    // todayIn takes a Date: the fixture carries an ISO instant string instead.
    todayIn: (timeZone: string, now: string) => todayIn(timeZone, new Date(now)),
    monthOf,
    firstDay,
    lastDay,
    addMonths,
    monthsBetween,
    isMonth,
  }));
