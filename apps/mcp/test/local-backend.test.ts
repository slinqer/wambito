import { createLocalBackend, createMemoryStore, type LocalBackend } from "@wambito/vault";
import { beforeEach, describe, expect, test } from "vitest";
import { apiWambito } from "../src/api-wambito.ts";

// The vault's local backend answering the same routes as the API, reached the way the MCP will:
// through `apiWambito` with the backend's `fetch`.
const NOW = new Date("2026-10-21T18:00:00Z");
const USER = "22222222-2222-4222-8222-222222222222";

let store: ReturnType<typeof createMemoryStore>;
let wambito: ReturnType<typeof apiWambito>;
let categoryId: string;

const build = (): LocalBackend =>
  createLocalBackend({
    store,
    now: () => new Date(NOW),
    source: "mcp",
    idsFromIdempotencyKey: { userId: USER },
  });

beforeEach(async () => {
  store = createMemoryStore();
  wambito = apiWambito("http://local", "token", build().fetch);
  const category = await wambito.createCategory({
    name: "Food",
    kind: "expense",
    icon: "fork",
    color: "#f90",
  });
  categoryId = category.id;
});

const item = (name: string, extra: { source?: "app" | "mcp" | "web" | "widget" } = {}) => ({
  name,
  status: "paid" as const,
  source: "app" as const,
  amount: -1000,
  categoryId,
  date: "2026-10-21",
  ...extra,
});

describe("addTransactions", () => {
  test("saves the items, forced to source mcp", async () => {
    const saved = await wambito.addTransactions(
      [item("a", { source: "app" }), item("b", { source: "widget" })],
      "key-1",
    );
    expect(saved.replayed).toBe(false);
    expect(saved.items.map((t) => [t.name, t.source])).toEqual([
      ["a", "mcp"],
      ["b", "mcp"],
    ]);
  });

  test("a retry with the same key writes nothing and is replayed", async () => {
    const items = [item("a"), item("b")];
    const first = await wambito.addTransactions(items, "key-2");
    const again = apiWambito("http://local", "token", build().fetch);
    const second = await again.addTransactions(items, "key-2");
    expect(second.replayed).toBe(true);
    expect(second.items).toEqual(first.items);
    expect(await store.list("transaction")).toHaveLength(2);
  });

  test("a partial earlier write creates only the missing, not replayed", async () => {
    const first = await wambito.addTransactions([item("a")], "key-3");
    const again = apiWambito("http://local", "token", build().fetch);
    const second = await again.addTransactions([item("a"), item("b")], "key-3");
    expect(second.replayed).toBe(false);
    expect(second.items[0]?.id).toBe(first.items[0]?.id);
    expect(second.items).toHaveLength(2);
    expect(await store.list("transaction")).toHaveLength(2);
  });
});

describe("deleteTransactions", () => {
  test("deletes every id and restores one", async () => {
    const { items } = await wambito.addTransactions([item("a"), item("b"), item("c")], "key-4");
    const [a, b, c] = items;
    await wambito.deleteTransactions([a?.id as string, b?.id as string]);
    expect((await store.list("transaction")).map((r) => r.id)).toEqual([c?.id]);
    await wambito.restoreTransaction(a?.id as string);
    expect(await store.list("transaction")).toHaveLength(2);
  });
});
