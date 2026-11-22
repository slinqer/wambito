import { describe, expect, it } from "vitest";
import { createLocalBackend, type LocalBackendOptions } from "./backend.ts";
import { IDEMPOTENCY_NAMESPACE, uuidv5 } from "./ids.ts";
import { createMemoryStore } from "./memory-store.ts";

const NOW = new Date("2026-10-21T18:00:00Z");
const BASE = "http://local/v1";

async function setup(options: Partial<LocalBackendOptions> = {}) {
  const store = createMemoryStore();
  const backend = createLocalBackend({ store, now: () => new Date(NOW), ...options });
  const call = (method: string, path: string, body?: unknown, headers: HeadersInit = {}) =>
    backend.fetch(`${BASE}${path}`, {
      method,
      headers: { "content-type": "application/json", ...headers },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
  const made = await call("POST", "/categories", {
    name: "Food",
    kind: "expense",
    icon: "fork",
    color: "#f90",
  });
  const categoryId = ((await made.json()) as { id: string }).id;
  const item = (name: string, extra: object = {}) => ({
    name,
    amount: -1000,
    categoryId,
    date: "2026-10-21",
    ...extra,
  });
  const batch = (items: object[], key: string | null = "key-1") =>
    call("POST", "/transactions/batch", { items }, key ? { "idempotency-key": key } : {});
  return { store, call, categoryId, item, batch };
}

interface Tx {
  id: string;
  name: string;
  source: string;
}

describe("POST /v1/transactions/batch", () => {
  it("answers 201 with the items in request order, like the API", async () => {
    const { batch, item, store } = await setup();
    const res = await batch([item("one"), item("two", { source: "widget" })]);
    expect(res.status).toBe(201);
    expect(res.headers.get("idempotent-replayed")).toBeNull();
    const { items } = (await res.json()) as { items: Tx[] };
    expect(items.map((t) => t.name)).toEqual(["one", "two"]);
    expect(items[1]?.source).toBe("widget");
    expect(await store.list("transaction")).toHaveLength(2);
  });

  it("is refused without an Idempotency-Key, with 21 items and with none", async () => {
    const { batch, item, store } = await setup();
    const noKey = await batch([item("a")], null);
    expect(noKey.status).toBe(400);
    expect(await noKey.json()).toMatchObject({ status: 400, code: "idempotency_key_required" });
    const many = Array.from({ length: 21 }, (_, i) => item(`n${i}`));
    expect((await batch(many)).status).toBe(422);
    expect((await batch([])).status).toBe(422);
    expect((await batch(many.slice(0, 20), "key-20")).status).toBe(201);
    expect(await store.list("transaction")).toHaveLength(20);
  });

  it("is all or nothing: an unknown category in item 2 saves neither", async () => {
    const { batch, item, store } = await setup();
    const res = await batch([
      item("first"),
      item("second", { categoryId: "00000000-0000-4000-8000-000000000000" }),
    ]);
    expect(res.status).toBe(422);
    expect(await res.json()).toMatchObject({ code: "category_not_found" });
    expect(await store.list("transaction")).toHaveLength(0);
  });

  it("replays the same key and body: same answer, nothing new, Idempotent-Replayed", async () => {
    const { batch, item, store } = await setup();
    const items = [item("one"), item("two")];
    const first = await batch(items);
    const second = await batch(items);
    expect(second.status).toBe(201);
    expect(second.headers.get("idempotent-replayed")).toBe("true");
    expect(await second.json()).toEqual(await first.json());
    expect(await store.list("transaction")).toHaveLength(2);
    const other = await batch([item("different")]);
    expect(other.status).toBe(422);
    expect(await other.json()).toMatchObject({ code: "idempotency_key_reused" });
  });

  it("says Idempotent-Replayed on a replayed single create too", async () => {
    const { call, item } = await setup();
    const send = () => call("POST", "/transactions", item("solo"), { "idempotency-key": "solo" });
    expect((await send()).headers.get("idempotent-replayed")).toBeNull();
    expect((await send()).headers.get("idempotent-replayed")).toBe("true");
  });
});

describe("POST /v1/transactions/batch-delete", () => {
  it("soft-deletes the ids with 204 and ignores unknown or deleted ones", async () => {
    const { batch, item, call, store } = await setup();
    const { items } = (await (await batch([item("a"), item("b"), item("c")])).json()) as {
      items: Tx[];
    };
    const [a, b, c] = items as [Tx, Tx, Tx];
    const res = await call("POST", "/transactions/batch-delete", {
      ids: [a.id, b.id, "00000000-0000-4000-8000-000000000000"],
    });
    expect(res.status).toBe(204);
    expect((await store.list("transaction")).map((r) => r.id)).toEqual([c.id]);
    const again = await call("POST", "/transactions/batch-delete", { ids: [a.id] });
    expect(again.status).toBe(204);
    const restored = await call("POST", `/transactions/${a.id}/restore`);
    expect(restored.status).toBe(200);
    expect(await store.list("transaction")).toHaveLength(2);
  });

  it("refuses 0 and 21 ids", async () => {
    const { call } = await setup();
    expect((await call("POST", "/transactions/batch-delete", { ids: [] })).status).toBe(422);
    const ids = Array.from(
      { length: 21 },
      (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`,
    );
    expect((await call("POST", "/transactions/batch-delete", { ids })).status).toBe(422);
  });
});

describe("source", () => {
  it("forces mcp whatever the body says, on single and batch creates", async () => {
    const { batch, item, call } = await setup({ source: "mcp" });
    const { items } = (await (
      await batch([item("a", { source: "app" }), item("b", { source: "widget" }), item("c")])
    ).json()) as { items: Tx[] };
    expect(items.map((t) => t.source)).toEqual(["mcp", "mcp", "mcp"]);
    const single = await call("POST", "/transactions", item("d", { source: "widget" }));
    expect(((await single.json()) as Tx).source).toBe("mcp");
  });

  it("leaves the body's source alone when not set", async () => {
    const { batch, item } = await setup();
    const { items } = (await (await batch([item("a", { source: "widget" })])).json()) as {
      items: Tx[];
    };
    expect(items[0]?.source).toBe("widget");
  });
});

describe("ids from the idempotency key", () => {
  const userId = "11111111-1111-4111-8111-111111111111";

  it("derives item i's id from the user, the key and i", async () => {
    const { batch, item } = await setup({ idsFromIdempotencyKey: { userId } });
    const { items } = (await (await batch([item("a"), item("b")], "k")).json()) as { items: Tx[] };
    const expected = await Promise.all(
      [0, 1].map((i) => uuidv5(IDEMPOTENCY_NAMESPACE, `${userId}/k/${i}`)),
    );
    expect(items.map((t) => t.id)).toEqual(expected);
  });

  it("a retry after a lost answer writes nothing and replays", async () => {
    const { batch, item, store } = await setup({ idsFromIdempotencyKey: { userId } });
    const items = [item("a"), item("b")];
    const first = await batch(items, "retry");
    // A new backend over the same store has no memory of the key: only the derived ids tell.
    const again = createLocalBackend({
      store,
      now: () => new Date(NOW),
      idsFromIdempotencyKey: { userId },
    });
    const second = await again.fetch(`${BASE}/transactions/batch`, {
      method: "POST",
      headers: { "content-type": "application/json", "idempotency-key": "retry" },
      body: JSON.stringify({ items }),
    });
    expect(second.status).toBe(201);
    expect(second.headers.get("idempotent-replayed")).toBe("true");
    expect(await second.json()).toEqual(await first.json());
    expect(await store.list("transaction")).toHaveLength(2);
  });

  it("counts a deleted one as written", async () => {
    const { batch, item, call, store } = await setup({ idsFromIdempotencyKey: { userId } });
    const items = [item("a")];
    const { items: made } = (await (await batch(items, "gone")).json()) as { items: Tx[] };
    await call("DELETE", `/transactions/${made[0]?.id}`);
    const res = await batch(items, "gone");
    expect(res.headers.get("idempotent-replayed")).toBe("true");
    expect(await store.list("transaction")).toHaveLength(0);
  });

  it("a partial earlier write creates only the missing, with no replay header", async () => {
    const { batch, item, store } = await setup({ idsFromIdempotencyKey: { userId } });
    const first = await batch([item("a")], "part");
    const [a] = ((await first.json()) as { items: Tx[] }).items as [Tx];
    const again = createLocalBackend({
      store,
      now: () => new Date(NOW),
      idsFromIdempotencyKey: { userId },
    });
    const res = await again.fetch(`${BASE}/transactions/batch`, {
      method: "POST",
      headers: { "content-type": "application/json", "idempotency-key": "part" },
      body: JSON.stringify({ items: [item("a"), item("b")] }),
    });
    expect(res.status).toBe(201);
    expect(res.headers.get("idempotent-replayed")).toBeNull();
    const { items } = (await res.json()) as { items: Tx[] };
    expect(items.map((t) => t.name)).toEqual(["a", "b"]);
    expect(items[0]?.id).toBe(a.id);
    expect(items[1]?.id).toBe(await uuidv5(IDEMPOTENCY_NAMESPACE, `${userId}/part/1`));
    expect(await store.list("transaction")).toHaveLength(2);
  });
});
