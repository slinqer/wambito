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
