import { parseRecord } from "@wambito/core";
import { describe, expect, it } from "vitest";
import { uuidv5 } from "./ids.ts";
import {
  countsOf,
  type MigrationRecord,
  type MigrationSource,
  recordsFromSource,
  SETTINGS_SEED_NAMESPACE,
} from "./migration.ts";

const USER = "user-migrate-1";
const ACCOUNT = "01930000-0000-7000-8000-0000000000a1";
const FOOD = "01930000-0000-7000-8000-0000000000c1";
const OLD = "01930000-0000-7000-8000-0000000000c2";
const RENT = "01930000-0000-7000-8000-0000000000f1";
const YEARLY = "01930000-0000-7000-8000-0000000000f2";
const AT = "2026-10-03T09:30:00.000Z";

const tx = (
  id: string,
  extra: Partial<MigrationSource["transactions"][number]> = {},
): MigrationSource["transactions"][number] => ({
  id,
  accountId: ACCOUNT,
  categoryId: FOOD,
  name: "Bakery",
  amount: -1250,
  currency: "EUR",
  date: "2026-10-03",
  status: "paid",
  note: null,
  recurrenceId: null,
  occurrenceMonth: null,
  importId: null,
  source: "web",
  externalHash: null,
  needsReview: false,
  captureSource: null,
  capturedAt: null,
  captureMerchantKey: null,
  deletedAt: null,
  createdAt: AT,
  updatedAt: AT,
  ...extra,
});

function source(): MigrationSource {
  return {
    profile: {
      timezone: "Europe/Madrid",
      locale: "en",
      onboardingCompletedAt: "2026-09-01T08:00:00.000Z",
      currency: "EUR",
    },
    categories: [
      {
        id: FOOD,
        name: "Food",
        kind: "expense",
        icon: "🍞",
        color: "#f0a000",
        sortOrder: 0,
        archivedAt: null,
        systemKey: null,
        createdAt: AT,
        updatedAt: AT,
      },
      {
        id: OLD,
        name: "Old hobby",
        kind: "expense",
        icon: "🎸",
        color: "#3355ff",
        sortOrder: 1,
        archivedAt: "2026-09-20T10:00:00.000Z",
        systemKey: null,
        createdAt: AT,
        updatedAt: AT,
      },
    ],
    budgets: [
      {
        id: "01930000-0000-7000-8000-0000000000b1",
        categoryId: FOOD,
        amount: 30000,
        effectiveFrom: "2026-08-01",
        createdAt: AT,
        updatedAt: AT,
      },
      {
        id: "01930000-0000-7000-8000-0000000000b2",
        categoryId: FOOD,
        amount: 35000,
        effectiveFrom: "2026-10-01",
        createdAt: AT,
        updatedAt: AT,
      },
    ],
    recurrences: [
      {
        id: RENT,
        accountId: ACCOUNT,
        categoryId: FOOD,
        name: "Veg box",
        amount: -4000,
        frequency: "monthly",
        dayOfMonth: 5,
        monthOfYear: null,
        startDate: "2026-08-05",
        endDate: null,
        createdAt: AT,
        updatedAt: AT,
      },
      {
        id: YEARLY,
        accountId: ACCOUNT,
        categoryId: OLD,
        name: "Club membership",
        amount: -9000,
        frequency: "yearly",
        dayOfMonth: 15,
        monthOfYear: 3,
        startDate: "2026-03-15",
        endDate: "2030-03-15",
        createdAt: AT,
        updatedAt: AT,
      },
    ],
    transactions: [
      tx("01930000-0000-7000-8000-000000000001", {
        name: "Corner shop",
        captureSource: "revolut",
        capturedAt: "2026-10-02T18:00:00.000Z",
        captureMerchantKey: "corner shop",
        source: "capture",
        needsReview: true,
      }),
      tx("01930000-0000-7000-8000-000000000002", {
        categoryId: OLD,
        deletedAt: "2026-10-10T12:00:00.000Z",
        note: "a mistake",
      }),
      // A dismissed month: soft-deleted, pending, made by the recurrence.
      tx("01930000-0000-7000-8000-000000000003", {
        name: "Veg box",
        amount: -4000,
        date: "2026-10-05",
        status: "pending",
        recurrenceId: RENT,
        occurrenceMonth: "2026-10-01",
        source: "recurrence",
        deletedAt: "2026-10-06T07:00:00.000Z",
      }),
      // Paid occurrence.
      tx("01930000-0000-7000-8000-000000000004", {
        name: "Veg box",
        amount: -4000,
        date: "2026-09-05",
        status: "paid",
        recurrenceId: RENT,
        occurrenceMonth: "2026-09-01",
        source: "recurrence",
      }),
      // Edited, still pending, live.
      tx("01930000-0000-7000-8000-000000000005", {
        name: "Veg box (bigger)",
        amount: -4500,
        date: "2026-11-06",
        status: "pending",
        recurrenceId: RENT,
        occurrenceMonth: "2026-11-01",
        source: "recurrence",
      }),
    ],
    merchants: [
      {
        id: "01930000-0000-7000-8000-0000000000e1",
        merchantKey: "corner shop",
        categoryId: FOOD,
        createdAt: AT,
        updatedAt: AT,
      },
    ],
  };
}

const find = (records: MigrationRecord[], type: string, id: string) =>
  records.find((r) => r.type === type && r.id === id);

describe("recordsFromSource", () => {
  it("every body passes parseRecord", async () => {
    const records = await recordsFromSource(source(), USER);
    for (const r of records) expect(parseRecord(r.type, r.body)).toMatchObject({ ok: true });
  });

  it("a transaction keeps its id and cents, with YYYY-MM occurrenceMonth and accountId null", async () => {
    const records = await recordsFromSource(source(), USER);
    const shop = find(records, "transaction", "01930000-0000-7000-8000-000000000001");
    expect(shop).toMatchObject({ deleted: false });
    expect(shop?.body).toEqual({
      s: 1,
      name: "Corner shop",
      amount: -1250,
      currency: "EUR",
      date: "2026-10-03",
      status: "paid",
      note: null,
      categoryId: FOOD,
      accountId: null,
      recurrenceId: null,
      occurrenceMonth: null,
      source: "capture",
      needsReview: true,
      captureSource: "revolut",
      capturedAt: "2026-10-02T18:00:00.000Z",
      captureMerchantKey: "corner shop",
      createdAt: AT,
      updatedAt: AT,
    });
    const paid = find(records, "transaction", "01930000-0000-7000-8000-000000000004");
    expect(paid?.body).toMatchObject({ occurrenceMonth: "2026-09", accountId: null });
    // Nothing of the server's bookkeeping columns gets into a body.
    for (const r of records) {
      expect(r.body).not.toHaveProperty("importId");
      expect(r.body).not.toHaveProperty("externalHash");
      expect(r.body).not.toHaveProperty("deletedAt");
      expect(r.body).not.toHaveProperty("id");
    }
  });

  it("a soft-deleted transaction is a deleted record with its body", async () => {
    const records = await recordsFromSource(source(), USER);
    const gone = find(records, "transaction", "01930000-0000-7000-8000-000000000002");
    expect(gone).toMatchObject({ deleted: true });
    expect(gone?.body).toMatchObject({ name: "Bakery", note: "a mistake", categoryId: OLD });
  });

  it('a dismissed occurrence takes uuidv5(recurrenceId, "2026-10:0") and is deleted', async () => {
    const records = await recordsFromSource(source(), USER);
    const id = await uuidv5(RENT, "2026-10:0");
    expect(find(records, "transaction", "01930000-0000-7000-8000-000000000003")).toBeUndefined();
    const dismissed = find(records, "transaction", id);
    expect(dismissed).toMatchObject({ deleted: true });
    expect(dismissed?.body).toMatchObject({
      status: "pending",
      source: "recurrence",
      recurrenceId: RENT,
      occurrenceMonth: "2026-10",
    });
  });

  it("a paid or edited occurrence keeps its server id", async () => {
    const records = await recordsFromSource(source(), USER);
    expect(find(records, "transaction", "01930000-0000-7000-8000-000000000004")).toMatchObject({
      deleted: false,
    });
    expect(
      find(records, "transaction", "01930000-0000-7000-8000-000000000005")?.body,
    ).toMatchObject({
      name: "Veg box (bigger)",
      amount: -4500,
      status: "pending",
      occurrenceMonth: "2026-11",
    });
    // A deleted occurrence the person had paid is no dismissal: it keeps its id too.
    const src = source();
    src.transactions = [
      tx("01930000-0000-7000-8000-000000000006", {
        status: "paid",
        recurrenceId: RENT,
        occurrenceMonth: "2026-08-01",
        source: "recurrence",
        deletedAt: AT,
      }),
    ];
    const [only] = (await recordsFromSource(src, USER)).filter((r) => r.type === "transaction");
    expect(only).toMatchObject({ id: "01930000-0000-7000-8000-000000000006", deleted: true });
  });

  it("an archived category keeps archivedAt", async () => {
    const records = await recordsFromSource(source(), USER);
    expect(find(records, "category", OLD)).toMatchObject({
      deleted: false,
      body: {
        s: 1,
        name: "Old hobby",
        kind: "expense",
        icon: "🎸",
        color: "#3355ff",
        sortOrder: 1,
        archivedAt: "2026-09-20T10:00:00.000Z",
        systemKey: null,
        createdAt: AT,
      },
    });
    expect(find(records, "category", FOOD)?.body).toMatchObject({ archivedAt: null });
  });

  it("budgets become effectiveFrom YYYY-MM, one record per month row", async () => {
    const records = await recordsFromSource(source(), USER);
    const budgets = records.filter((r) => r.type === "budget");
    expect(budgets).toEqual([
      {
        type: "budget",
        id: "01930000-0000-7000-8000-0000000000b1",
        deleted: false,
        body: { s: 1, categoryId: FOOD, amount: 30000, effectiveFrom: "2026-08" },
      },
      {
        type: "budget",
        id: "01930000-0000-7000-8000-0000000000b2",
        deleted: false,
        body: { s: 1, categoryId: FOOD, amount: 35000, effectiveFrom: "2026-10" },
      },
    ]);
  });

  it("a yearly recurrence keeps monthOfYear, rev 0", async () => {
    const records = await recordsFromSource(source(), USER);
    expect(find(records, "recurrence", YEARLY)).toEqual({
      type: "recurrence",
      id: YEARLY,
      deleted: false,
      body: {
        s: 1,
        name: "Club membership",
        amount: -9000,
        categoryId: OLD,
        frequency: "yearly",
        dayOfMonth: 15,
        monthOfYear: 3,
        startDate: "2026-03-15",
        endDate: "2030-03-15",
        rev: 0,
        createdAt: AT,
      },
    });
    expect(find(records, "recurrence", RENT)?.body).toMatchObject({ monthOfYear: null, rev: 0 });
  });

  it("merchants become merchant records with their categoryId", async () => {
    const records = await recordsFromSource(source(), USER);
    expect(records.filter((r) => r.type === "merchant")).toEqual([
      {
        type: "merchant",
        id: "01930000-0000-7000-8000-0000000000e1",
        deleted: false,
        body: { s: 1, merchantKey: "corner shop", categoryId: FOOD },
      },
    ]);
  });

  it("settings carry currency, locale, timezone and onboardingCompletedAt, with the seed-derived id", async () => {
    const records = await recordsFromSource(source(), USER);
    const settings = records.filter((r) => r.type === "settings");
    const id = await uuidv5(await uuidv5(SETTINGS_SEED_NAMESPACE, USER), "settings");
    expect(settings).toEqual([
      {
        type: "settings",
        id,
        deleted: false,
        body: {
          s: 1,
          name: null,
          currency: "EUR",
          locale: "en",
          timezone: "Europe/Madrid",
          onboardingCompletedAt: "2026-09-01T08:00:00.000Z",
          revokedDevices: [],
          recoveryKeySavedAt: null,
        },
      },
    ]);
  });

  it("refuses a row that would not make a valid record", async () => {
    const src = source();
    src.profile.currency = "XXX";
    await expect(recordsFromSource(src, USER)).rejects.toThrow(/settings/);
  });
});

describe("countsOf", () => {
  it("countsOf matches the server's counting rule", async () => {
    const src = source();
    const records = await recordsFromSource(src, USER);
    // Live rows per type, and soft-deleted transactions apart (dismissed months among them);
    // the settings record is checked apart and never counted.
    expect(countsOf(records)).toEqual({
      transaction: src.transactions.filter((t) => t.deletedAt === null).length,
      deletedTransaction: src.transactions.filter((t) => t.deletedAt !== null).length,
      category: src.categories.length,
      budget: src.budgets.length,
      recurrence: src.recurrences.length,
      merchant: src.merchants.length,
    });
    expect(countsOf(records)).toEqual({
      transaction: 3,
      deletedTransaction: 2,
      category: 2,
      budget: 2,
      recurrence: 2,
      merchant: 1,
    });
    expect(countsOf([])).toEqual({
      transaction: 0,
      deletedTransaction: 0,
      category: 0,
      budget: 0,
      recurrence: 0,
      merchant: 0,
    });
  });
});
