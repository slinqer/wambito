import type { CreateTransaction } from "@wambito/core";
import { describe, expect, it } from "vitest";
import { MemoryWambito, ToolError } from "../src/index.ts";
import { category, transaction } from "./fixtures.ts";

const now = () => new Date("2026-10-15T15:00:00Z");

function setup() {
  const comida = category("Comida", "expense", { currentBudget: 50000000 });
  const salario = category("Salario", "income");
  const wambito = new MemoryWambito({
    categories: [comida, salario],
    transactions: [
      transaction(comida, -1800000, "2026-10-02", { name: "Almuerzo" }),
      transaction(comida, -500000, "2026-09-20"),
      transaction(salario, 200000000, "2026-10-01"),
    ],
    now,
  });
  return { wambito, comida, salario };
}

const item = (categoryId: string, amount = -1800000): CreateTransaction => ({
  name: "Almuerzo",
  amount,
  categoryId,
  date: "2026-10-15",
  status: "paid",
  source: "mcp",
});

describe("MemoryWambito", () => {
  it("has a Colombian Spanish profile by default", async () => {
    expect(await new MemoryWambito().profile()).toEqual({
      timezone: "America/Bogota",
      locale: "es",
      currency: "COP",
    });
  });

  it("summarizes a month like the API: spent positive, income, budgets", async () => {
    const { wambito, comida } = setup();
    const summary = await wambito.monthSummary("2026-10");
    expect(summary).toMatchObject({ month: "2026-10", spent: 1800000, income: 200000000 });
    expect(summary.categories).toEqual([
      expect.objectContaining({ categoryId: comida.id, budget: 50000000, spent: 1800000 }),
    ]);
  });

  it("lists newest first, filters and pages with a cursor", async () => {
    const { wambito, comida } = setup();
    const first = await wambito.listTransactions({ limit: 2 });
    expect(first.items.map((t) => t.date)).toEqual(["2026-10-02", "2026-10-01"]);
    expect(first.nextCursor).not.toBeNull();
    const second = await wambito.listTransactions({ limit: 2, cursor: first.nextCursor ?? "" });
    expect(second.items.map((t) => t.date)).toEqual(["2026-09-20"]);
    expect(second.nextCursor).toBeNull();

    expect((await wambito.listTransactions({ month: "2026-09", limit: 10 })).items).toHaveLength(1);
    expect(
      (await wambito.listTransactions({ from: "2026-10-01", to: "2026-10-01", limit: 10 })).items,
    ).toHaveLength(1);
    expect(
      (await wambito.listTransactions({ categoryIds: [comida.id], limit: 10 })).items,
    ).toHaveLength(2);
    expect((await wambito.listTransactions({ q: ["ALMÚ"], limit: 10 })).items).toHaveLength(1);
  });

  it("replays a batch sent again with the same key", async () => {
    const { wambito, comida } = setup();
    const first = await wambito.addTransactions([item(comida.id)], "key-1");
    const again = await wambito.addTransactions([item(comida.id)], "key-1");
    expect(first.replayed).toBe(false);
    expect(again.replayed).toBe(true);
    expect(again.items).toEqual(first.items);
    expect((await wambito.listTransactions({ month: "2026-10", limit: 50 })).items).toHaveLength(3);
  });

  it("refuses a key reused with another body", async () => {
    const { wambito, comida } = setup();
    await wambito.addTransactions([item(comida.id)], "key-1");
    await expect(wambito.addTransactions([item(comida.id, -1)], "key-1")).rejects.toMatchObject({
      code: "idempotency_key_reused",
    });
  });

  it("refuses batches over the API's limit of 20", async () => {
    const { wambito, comida } = setup();
    const items = Array.from({ length: 21 }, () => item(comida.id));
    await expect(wambito.addTransactions(items, "big")).rejects.toBeInstanceOf(ToolError);
  });

  it("refuses an archived or unknown category", async () => {
    const { wambito, comida } = setup();
    await wambito.updateCategory(comida.id, { archived: true });
    await expect(wambito.addTransactions([item(comida.id)], "k")).rejects.toMatchObject({
      code: "category_not_found",
    });
  });

  it("soft-deletes and restores", async () => {
    const { wambito } = setup();
    const [tx] = (await wambito.listTransactions({ limit: 1 })).items;
    if (!tx) throw new Error("no transaction");
    await wambito.deleteTransactions([tx.id]);
    expect((await wambito.listTransactions({ limit: 10 })).items).toHaveLength(2);
    expect(await wambito.restoreTransaction(tx.id)).toEqual(tx);
    expect((await wambito.listTransactions({ limit: 10 })).items).toHaveLength(3);
  });

  it("reports by category and by month", async () => {
    const { wambito, comida } = setup();
    expect(
      await wambito.categoryReport({ from: "2026-09", to: "2026-10", kind: "expense" }),
    ).toEqual({ total: 2300000, items: [{ categoryId: comida.id, total: 2300000 }] });
    expect(await wambito.trend({ from: "2026-09", to: "2026-10" })).toEqual({
      months: [
        { month: "2026-09", income: 0, expenses: 500000, budget: 50000000 },
        { month: "2026-10", income: 200000000, expenses: 1800000, budget: 50000000 },
      ],
    });
  });

  it("sets a budget from a month on", async () => {
    const { wambito, comida } = setup();
    await wambito.setBudget(comida.id, { amount: 10000000, effectiveFrom: "2026-11" });
    expect((await wambito.monthSummary("2026-10")).budgetTotal).toBe(50000000);
    expect((await wambito.monthSummary("2026-11")).budgetTotal).toBe(10000000);
  });

  it("keeps active category names unique ignoring case", async () => {
    const { wambito } = setup();
    await expect(
      wambito.createCategory({ name: "comida", kind: "expense", icon: "x", color: "y" }),
    ).rejects.toMatchObject({ code: "category_name_taken" });
  });
});
