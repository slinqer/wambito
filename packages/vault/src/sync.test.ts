import {
  deriveRecordKeys,
  fromBase64Url,
  generateDataKey,
  openRecord,
  sealRecord,
  toBase64Url,
} from "@wambito/crypto";
import { expect, test } from "vitest";
import { createMemoryEncryptedStore } from "./memory-encrypted-store.ts";
import type { RecordBodies } from "./store.ts";
import { createSyncEngine } from "./sync.ts";

const USER = "user_smoke";
const A = "01930000-0000-7000-8000-00000000000a";
const B = "01930000-0000-7000-8000-00000000000b";
const C = "01930000-0000-7000-8000-00000000000c";

const category = (name: string): RecordBodies["category"] => ({
  s: 1,
  name,
  kind: "expense",
  icon: "x",
  color: "#fff",
  sortOrder: 0,
  archivedAt: null,
  systemKey: null,
});

interface Wire {
  id: string;
  type: string;
  version: number;
  deleted: boolean;
  keyV: number;
  encV: number;
  body: string | null;
}

test("a sync engine pulls, opens and pushes over the memory store", async () => {
  const keys = await deriveRecordKeys(generateDataKey());
  const keyring = { current: 1, byVersion: new Map([[1, keys]]) };
  const seal = async (id: string, body: unknown) =>
    toBase64Url(await sealRecord(keys, { userId: USER, type: "category", id, keyV: 1 }, body));

  const rows = new Map<string, Wire>();
  for (const [i, [id, name]] of [
    [A, "Food"],
    [B, "Rent"],
  ].entries()) {
    rows.set(id as string, {
      id: id as string,
      type: "category",
      version: i + 1,
      deleted: false,
      keyV: 1,
      encV: 1,
      body: await seal(id as string, category(name as string)),
    });
  }
  const posted: Array<Wire & { baseVersion: number | null }> = [];
  const fakeFetch = (async (input: string, init?: RequestInit) => {
    const json = (body: unknown) =>
      new Response(JSON.stringify(body), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    if (init?.method === "POST") {
      const { changes } = JSON.parse(String(init.body)) as { changes: typeof posted };
      posted.push(...changes);
      return json({ results: changes.map((c, i) => ({ id: c.id, version: 10 + i })) });
    }
    const since = Number(new URL(input, "http://x").searchParams.get("since"));
    const list = [...rows.values()].filter((r) => r.version > since);
    return json({ records: list, next: null, latest: 2 });
  }) as unknown as typeof fetch;

  const store = createMemoryEncryptedStore(USER);
  const engine = createSyncEngine({
    store,
    fetch: fakeFetch,
    userId: USER,
    keyring,
    refreshKeys: async () => keyring,
    upgrade: false,
  });

  expect(await engine.run()).toMatchObject({ ok: true, pushed: 0 });
  expect((await store.list("category")).map((r) => r.body.name).sort()).toEqual(["Food", "Rent"]);

  await store.put("category", C, category("Fun"));
  expect(await engine.run()).toMatchObject({ ok: true, pushed: 1 });
  expect(await store.readOutbox(10)).toEqual([]);
  expect(posted).toHaveLength(1);
  const [change] = posted;
  expect(change).toMatchObject({ id: C, type: "category", keyV: keyring.current });
  expect(JSON.stringify(change)).not.toContain("Fun");
  const opened = await openRecord(
    keys,
    { userId: USER, type: "category", id: C, keyV: keyring.current },
    fromBase64Url(change?.body ?? ""),
  );
  expect(opened).toMatchObject({ name: "Fun" });
});

test("a change the server leaves unanswered is parked and the run ends", async () => {
  const keys = await deriveRecordKeys(generateDataKey());
  const keyring = { current: 1, byVersion: new Map([[1, keys]]) };
  let posts = 0;
  const fakeFetch = (async (_input: string, init?: RequestInit) => {
    if (init?.method === "POST") posts += 1;
    const body = init?.method === "POST" ? { results: [] } : { records: [], next: null, latest: 0 };
    return new Response(JSON.stringify(body), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }) as unknown as typeof fetch;
  const store = createMemoryEncryptedStore(USER);
  const engine = createSyncEngine({
    store,
    fetch: fakeFetch,
    userId: USER,
    keyring,
    refreshKeys: async () => keyring,
    upgrade: false,
  });
  await store.put("category", C, category("Fun"));
  // The memory store's write counter is the `seq` meta, as in IndexedDB: a change left pending
  // (parked) is not taken for a write made during the run, so no further pass runs.
  expect(await store.getMeta("seq")).toBe(1);
  expect(await engine.run()).toMatchObject({ ok: true, pushed: 0, parked: [C] });
  expect(posts).toBe(1);
});

test("a pulled tombstone that carries a body still deletes, and quarantines nothing", async () => {
  const keys = await deriveRecordKeys(generateDataKey());
  const keyring = { current: 1, byVersion: new Map([[1, keys]]) };
  const seal = async (id: string, body: unknown) =>
    toBase64Url(await sealRecord(keys, { userId: USER, type: "category", id, keyV: 1 }, body));
  let tombstone = false;
  const fakeFetch = (async (input: string) => {
    const since = Number(new URL(input, "http://x").searchParams.get("since"));
    const rec: Wire = tombstone
      ? {
          id: A,
          type: "category",
          version: 2,
          deleted: true,
          keyV: 1,
          encV: 1,
          body: await seal(A, category("Food")),
        }
      : {
          id: A,
          type: "category",
          version: 1,
          deleted: false,
          keyV: 1,
          encV: 1,
          body: await seal(A, category("Food")),
        };
    const records = rec.version > since ? [rec] : [];
    return new Response(JSON.stringify({ records, next: null, latest: rec.version }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }) as unknown as typeof fetch;
  const store = createMemoryEncryptedStore(USER);
  const engine = createSyncEngine({
    store,
    fetch: fakeFetch,
    userId: USER,
    keyring,
    refreshKeys: async () => keyring,
    upgrade: false,
  });

  expect(await engine.run()).toMatchObject({ ok: true });
  expect(await store.get("category", A)).not.toBeNull();

  tombstone = true;
  expect(await engine.run()).toMatchObject({ ok: true, quarantined: 0 });
  expect(await store.get("category", A)).toBeUndefined();
  expect((await store.get("category", A, { includeDeleted: true }))?.deleted).toBe(true);
  expect(await store.quarantined()).toEqual([]);
});

// ---- tombstones carry their body --------------------------------------------------------------

type Posted = Wire & { baseVersion: number | null };

/**
 * A fake `/v2/sync` over `rows`: a post is accepted unless `answer` says otherwise (`null`: no
 * result for that change); `gone` makes the next pull with `base > 0` answer 410.
 */
function fakeServer(answer?: (change: Posted) => unknown) {
  const rows = new Map<string, Wire>();
  const posted: Posted[] = [];
  const state = { latest: 0, gone: false };
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json" },
    });
  const fetch = (async (input: string, init?: RequestInit) => {
    if (init?.method === "POST") {
      const { changes } = JSON.parse(String(init.body)) as { changes: Posted[] };
      posted.push(...changes);
      const results = changes.flatMap((c) => {
        const r = answer ? answer(c) : undefined;
        if (r === null) return [];
        if (r !== undefined) return [r];
        state.latest += 1;
        rows.set(c.id, { ...c, version: state.latest });
        return [{ id: c.id, version: state.latest }];
      });
      return json({ results });
    }
    const url = new URL(input, "http://x");
    if (state.gone && Number(url.searchParams.get("base")) > 0) {
      state.gone = false;
      return json({ code: "resync_required" }, 410);
    }
    const since = Number(url.searchParams.get("since"));
    const records = [...rows.values()]
      .filter((r) => r.version > since)
      .sort((a, b) => a.version - b.version);
    return json({ records, next: null, latest: state.latest });
  }) as unknown as typeof globalThis.fetch;
  /** Stores a record on the server at the next version. */
  function serve(rec: Omit<Wire, "version" | "encV">) {
    state.latest += 1;
    const row = { ...rec, encV: 1, version: state.latest };
    rows.set(rec.id, row);
    return row;
  }
  return { rows, posted, state, fetch, serve };
}

const sealAs = async (
  keys: Awaited<ReturnType<typeof deriveRecordKeys>>,
  keyV: number,
  id: string,
  body: unknown,
) => toBase64Url(await sealRecord(keys, { userId: USER, type: "category", id, keyV }, body));

const openAs = (
  keys: Awaited<ReturnType<typeof deriveRecordKeys>>,
  keyV: number,
  id: string,
  body: string | null,
) => openRecord(keys, { userId: USER, type: "category", id, keyV }, fromBase64Url(body ?? ""));

async function setup(answer?: (change: Posted) => unknown) {
  const keys = await deriveRecordKeys(generateDataKey());
  const keyring = { current: 1, byVersion: new Map([[1, keys]]) };
  const server = fakeServer(answer);
  const store = createMemoryEncryptedStore(USER);
  const engine = createSyncEngine({
    store,
    fetch: server.fetch,
    userId: USER,
    keyring,
    refreshKeys: async () => keyring,
    upgrade: false,
  });
  return { keys, server, store, engine };
}

test("a delete pushes its sealed body", async () => {
  const { keys, server, store, engine } = await setup();
  await store.put("category", C, category("Fun"));
  expect(await engine.run()).toMatchObject({ ok: true, pushed: 1 });

  await store.delete("category", C);
  expect(await engine.run()).toMatchObject({ ok: true, pushed: 1 });
  const change = server.posted[1];
  expect(change).toMatchObject({ id: C, deleted: true, keyV: 1, baseVersion: 1 });
  expect(JSON.stringify(change)).not.toContain("Fun");
  expect(await openAs(keys, 1, C, change?.body ?? null)).toEqual(category("Fun"));
});

test("a delete of a record downloaded without a body pushes null", async () => {
  const keys = await deriveRecordKeys(generateDataKey());
  const keyring = { current: 1, byVersion: new Map([[1, keys]]) };
  const server = fakeServer();
  server.serve({
    id: A,
    type: "category",
    deleted: false,
    keyV: 1,
    body: await sealAs(keys, 1, A, category("Food")),
  });
  const inner = createMemoryEncryptedStore(USER);
  // A store that holds no body for this tombstone (a delete downloaded before tombstones had one).
  const store = {
    ...inner,
    getRaw: (async (type, id) => {
      const row = await inner.getRaw(type, id);
      return row?.deleted ? { ...row, body: null as never } : row;
    }) as typeof inner.getRaw,
  };
  const engine = createSyncEngine({
    store,
    fetch: server.fetch,
    userId: USER,
    keyring,
    refreshKeys: async () => keyring,
    upgrade: false,
  });
  expect(await engine.run()).toMatchObject({ ok: true, pulled: 1 });

  await store.delete("category", A);
  expect(await engine.run()).toMatchObject({ ok: true, pushed: 1 });
  expect(server.posted).toEqual([expect.objectContaining({ id: A, deleted: true, body: null })]);
});

test("a pulled tombstone with a body is kept, even for an id this device never had", async () => {
  const { keys, server, store, engine } = await setup();
  server.serve({
    id: A,
    type: "category",
    deleted: false,
    keyV: 1,
    body: await sealAs(keys, 1, A, category("Food")),
  });
  expect(await engine.run()).toMatchObject({ ok: true, pulled: 1 });

  for (const [id, name] of [
    [A, "Food"],
    [B, "Rent"],
  ] as const) {
    server.serve({
      id,
      type: "category",
      deleted: true,
      keyV: 1,
      body: await sealAs(keys, 1, id, category(name)),
    });
  }
  expect(await engine.run()).toMatchObject({ ok: true, quarantined: 0 });
  expect(await store.get("category", A)).toBeUndefined();
  expect(await store.get("category", B)).toBeUndefined();
  expect(await store.get("category", A, { includeDeleted: true })).toEqual({
    id: A,
    deleted: true,
    body: category("Food"),
  });
  expect(await store.get("category", B, { includeDeleted: true })).toEqual({
    id: B,
    deleted: true,
    body: category("Rent"),
  });
  expect(await store.readOutbox(10)).toEqual([]);
});

test("a pulled tombstone whose body does not open still deletes, without quarantine", async () => {
  const { keys, server, store, engine } = await setup();
  const otherKeys = await deriveRecordKeys(generateDataKey());
  server.serve({
    id: A,
    type: "category",
    deleted: false,
    keyV: 1,
    body: await sealAs(keys, 1, A, category("Food")),
  });
  expect(await engine.run()).toMatchObject({ ok: true, pulled: 1 });

  // Sealed under a key version this keyring lacks (a refresh does not bring it either).
  for (const [id, name] of [
    [A, "Food"],
    [B, "Rent"],
  ] as const) {
    server.serve({
      id,
      type: "category",
      deleted: true,
      keyV: 5,
      body: await sealAs(otherKeys, 5, id, category(name)),
    });
  }
  expect(await engine.run()).toMatchObject({ ok: true, quarantined: 0 });
  expect(await store.get("category", A)).toBeUndefined();
  expect((await store.get("category", A, { includeDeleted: true }))?.deleted).toBe(true);
  expect(await store.get("category", B, { includeDeleted: true })).toBeUndefined();
  expect(await store.quarantined()).toEqual([]);
});

test("an unsent edit meeting a server tombstone keeps the person's body", async () => {
  const conflicts = new Map<string, Wire>();
  const { keys, server, store, engine } = await setup((c) => {
    const server = conflicts.get(c.id);
    return server ? { id: c.id, conflict: server } : undefined;
  });
  server.serve({
    id: A,
    type: "category",
    deleted: false,
    keyV: 1,
    body: await sealAs(keys, 1, A, category("Food")),
  });
  expect(await engine.run()).toMatchObject({ ok: true, pulled: 1 });

  // Another device deleted it; this one edited it before hearing of that.
  conflicts.set(
    A,
    server.serve({
      id: A,
      type: "category",
      deleted: true,
      keyV: 1,
      body: await sealAs(keys, 1, A, category("Food")),
    }),
  );
  await store.put("category", A, category("Groceries"));
  expect(await engine.run()).toMatchObject({ ok: true, serverDeleted: [A] });
  expect(await store.get("category", A)).toBeUndefined();
  expect((await store.get("category", A, { includeDeleted: true }))?.body).toEqual(
    category("Groceries"),
  );
  expect(await store.readOutbox(10)).toEqual([]);
  // The server's tombstone holds a body under key version 1: that key is still needed.
  expect(await store.keyVersionsInUse()).toEqual(new Set([1]));
});

test("a set-aside edit meeting a server tombstone after a resync keeps the person's body", async () => {
  let silent = false;
  const { keys, server, store, engine } = await setup(() => (silent ? null : undefined));
  server.serve({
    id: A,
    type: "category",
    deleted: false,
    keyV: 1,
    body: await sealAs(keys, 1, A, category("Food")),
  });
  expect(await engine.run()).toMatchObject({ ok: true, pulled: 1 });

  // The edit is not taken (no result), then the server asks for a resync: it is set aside, and
  // the full download brings another device's delete.
  silent = true;
  server.serve({
    id: A,
    type: "category",
    deleted: true,
    keyV: 1,
    body: await sealAs(keys, 1, A, category("Food")),
  });
  server.state.gone = true;
  await store.put("category", A, category("Groceries"));
  expect(await engine.run()).toMatchObject({ ok: true, resynced: true, serverDeleted: [A] });
  expect(await store.get("category", A)).toBeUndefined();
  expect((await store.get("category", A, { includeDeleted: true }))?.body).toEqual(
    category("Groceries"),
  );
  expect(await store.readOutbox(10)).toEqual([]);
});

test("the upgrade pass re-seals a tombstone's body under the new key", async () => {
  const keys1 = await deriveRecordKeys(generateDataKey());
  const keys2 = await deriveRecordKeys(generateDataKey());
  const keyring = {
    current: 2,
    byVersion: new Map([
      [1, keys1],
      [2, keys2],
    ]),
  };
  const store = createMemoryEncryptedStore(USER);
  await store.putKey("record:1", "k1");
  await store.putKey("dedupe:1", "d1");
  await store.putKey("record:2", "k2");
  const namesAtPost: string[][] = [];
  const server = fakeServer();
  const fetch = (async (input: string, init?: RequestInit) => {
    if (init?.method === "POST") namesAtPost.push(await store.keyNames());
    return server.fetch(input, init);
  }) as typeof globalThis.fetch;
  // Deleted on another device before the rotation: its body is under key version 1.
  server.serve({
    id: B,
    type: "category",
    deleted: true,
    keyV: 1,
    body: await sealAs(keys1, 1, B, category("Rent")),
  });
  const engine = createSyncEngine({
    store,
    fetch,
    userId: USER,
    keyring,
    refreshKeys: async () => keyring,
  });

  expect(await engine.run()).toMatchObject({ ok: true, pushed: 1 });
  expect(server.posted).toEqual([
    expect.objectContaining({ id: B, deleted: true, keyV: 2, baseVersion: 1 }),
  ]);
  expect(await openAs(keys2, 2, B, server.posted[0]?.body ?? null)).toEqual(category("Rent"));
  // The old key was still there when the reseal went out, and is gone once it was acked.
  expect(namesAtPost[0]).toContain("record:1");
  expect((await store.keyNames()).sort()).toEqual(["record:2"]);
  expect(await store.keyVersionsInUse()).toEqual(new Set([2]));
});
