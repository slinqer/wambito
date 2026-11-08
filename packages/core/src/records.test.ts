import { describe, expect, test } from "vitest";
import { parseRecord, RECORD_TYPES } from "./records.ts";

const id = "0190a8a0-0000-7000-8000-000000000001";

const valid: Record<string, unknown> = {
  transaction: {
    s: 1,
    name: "Lunch",
    amount: -18000,
    currency: "COP",
    date: "2026-10-21",
    status: "paid",
    categoryId: id,
    source: "app",
  },
  category: { s: 1, name: "Food", kind: "expense", icon: "food", color: "red", sortOrder: 0 },
  budget: { s: 1, categoryId: id, amount: 50000, effectiveFrom: "2026-10" },
  recurrence: {
    s: 1,
    name: "Rent",
    amount: -80000,
    categoryId: id,
    frequency: "monthly",
    dayOfMonth: 1,
    startDate: "2026-01-01",
  },
  merchant: { s: 1, merchantKey: "rappi", categoryId: id },
  settings: { s: 1, currency: "COP", locale: "es", timezone: "America/Bogota" },
  account: { s: 1, name: "Main", currency: "COP" },
};

describe("parseRecord", () => {
  test("covers every record type", () => {
    expect([...RECORD_TYPES].sort()).toEqual(Object.keys(valid).sort());
  });

  for (const type of RECORD_TYPES) {
    test(`${type}: accepts a valid body and fills defaults`, () => {
      const r = parseRecord(type, valid[type]);
      expect(r.ok).toBe(true);
    });

    test(`${type}: requires s`, () => {
      const { s: _s, ...rest } = valid[type] as Record<string, unknown>;
      expect(parseRecord(type, rest).ok).toBe(false);
    });

    test(`${type}: strips unknown keys`, () => {
      const r = parseRecord(type, { ...(valid[type] as object), future: "x" });
      expect(r.ok && "future" in r.value).toBe(false);
    });

    test(`${type}: never throws on garbage`, () => {
      for (const junk of [null, undefined, 1, "x", [], {}]) {
        expect(parseRecord(type, junk).ok).toBe(false);
      }
    });
  }

  test("a transaction defaults its optional fields", () => {
    const r = parseRecord("transaction", valid.transaction);
    expect(r).toMatchObject({
      ok: true,
      value: { note: null, recurrenceId: null, occurrenceMonth: null, needsReview: false },
    });
  });

  test("rejects a zero amount and a bad date", () => {
    expect(parseRecord("transaction", { ...(valid.transaction as object), amount: 0 }).ok).toBe(
      false,
    );
    expect(
      parseRecord("transaction", { ...(valid.transaction as object), date: "2026-13-01" }).ok,
    ).toBe(false);
  });

  test("an unknown type is an error, not a throw", () => {
    expect(parseRecord("nope" as "account", {}).ok).toBe(false);
  });

  test("a recurrence's rev defaults to 0 and must be a non-negative integer", () => {
    expect(parseRecord("recurrence", valid.recurrence)).toMatchObject({
      ok: true,
      value: { rev: 0 },
    });
    expect(parseRecord("recurrence", { ...(valid.recurrence as object), rev: 3 })).toMatchObject({
      ok: true,
      value: { rev: 3 },
    });
    expect(parseRecord("recurrence", { ...(valid.recurrence as object), rev: -1 }).ok).toBe(false);
  });

  test("a transaction's updatedAt is optional", () => {
    expect(parseRecord("transaction", valid.transaction).ok).toBe(true);
    expect(
      parseRecord("transaction", { ...(valid.transaction as object), updatedAt: "2026-10-21T10:00:00Z" }),
    ).toMatchObject({ ok: true, value: { updatedAt: "2026-10-21T10:00:00Z" } });
  });
});
