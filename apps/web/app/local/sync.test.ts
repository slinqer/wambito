import "fake-indexeddb/auto";
import {
  deriveRecordKeys,
  fromBase64Url,
  generateDataKey,
  openRecord,
  type RecordKeys,
  sealRecord,
  toBase64Url,
} from "@wambito/crypto";
import { describe, expect, it } from "vitest";
import { createEncryptedStore, type EncryptedStore } from "./encrypted-store.ts";
import type { RecordBodies } from "./store.ts";
import { createSyncEngine } from "./sync.ts";

const USER = "user_sync";
const A = "01930000-0000-7000-8000-00000000000a";
const B = "01930000-0000-7000-8000-00000000000b";
const C = "01930000-0000-7000-8000-00000000000c";

interface Wire {
  id: string;
  type: string;
  version: number;
  deleted: boolean;
  keyV: number;
  encV: number;
  body: string | null;
}

/** A /v2/sync server written from the contract: versions from a counter, conflicts, purges. */
function fakeServer() {
  const rows = new Map<string, Wire>();
  const s = {
    counter: 0,
    purgeThrough: 0,
    offline: false,
    posts: 0,
    pullLimit: undefined as number | undefined,
    rows,
    purge() {
      // Purge every tombstone, as the daily job does after 180 days.
      let through = 0;
      for (const [id, r] of rows) {
        if (r.deleted) {
          through = Math.max(through, r.version);
          rows.delete(id);
        }
      }
      s.purgeThrough = Math.max(s.purgeThrough, through);
    },
    fetch: (async (input: string, init?: RequestInit) => {
      if (s.offline) throw new TypeError("Failed to fetch");
      const url = new URL(input, "http://x");
      const json = (status: number, body: unknown) =>
        new Response(JSON.stringify(body), {
          status,
          headers: { "content-type": "application/json" },
        });
      if (init?.method === "POST") {
        s.posts += 1;
        const { changes } = JSON.parse(String(init.body)) as {
          changes: Array<Wire & { baseVersion: number | null }>;
        };
        const results = changes.map((c) => {
          const cur = rows.get(c.id);
          const put = () => {
            const { baseVersion: _b, ...rest } = c;
            const row = { ...rest, version: ++s.counter };
            rows.set(c.id, row);
            return { id: c.id, version: row.version };
          };
          if (c.baseVersion === null) {
            if (!cur) return put();
            if (cur.body === c.body && cur.deleted === c.deleted)
              return { id: c.id, version: cur.version };
            return { id: c.id, conflict: cur };
          }
          if (!cur) return { id: c.id, error: "not_found" };
          if (cur.version !== c.baseVersion || cur.type !== c.type)
            return { id: c.id, conflict: cur };
          return put();
        });
        return json(200, { results });
      }
      const since = Number(url.searchParams.get("since"));
      const limit = Math.min(Number(url.searchParams.get("limit")), s.pullLimit ?? 1000);
      const base = Number(url.searchParams.get("base") ?? since);
      const latest = Math.max(0, ...[...rows.values()].map((r) => r.version));
      if (base > 0 && base < s.purgeThrough) {
        return json(410, { code: "resync_required" });
      }
      const list = [...rows.values()]
        .filter((r) => r.version > since && r.version <= latest)
        .sort((x, y) => x.version - y.version);
      const page = list.slice(0, limit);
      return json(200, {
        records: page,
        next: list.length > limit ? (page.at(-1)?.version ?? null) : null,
        latest,
      });
    }) as unknown as typeof fetch,
  };
  return s;
}

type Server = ReturnType<typeof fakeServer>;

let counter = 0;
let keys: RecordKeys;
const getKeys = async () => (keys ??= await deriveRecordKeys(generateDataKey()));

async function device(server: Server, k?: RecordKeys) {
  const store = await createEncryptedStore(`device-${++counter}`);
  const problems: Array<{ code: string }> = [];
  const engine = createSyncEngine({
    store,
    fetch: (...args) => server.fetch(...args),
    userId: USER,
    keys: k ?? (await getKeys()),
    keyV: 1,
    onError: (p) => problems.push(p),
    debounceMs: 20,
    intervalMs: 100000,
  });
  return { store, engine, problems };
}

const category = (name: string, color = "#fff"): RecordBodies["category"] => ({
  s: 1,
  name,
  kind: "expense",
  icon: "x",
  color,
  sortOrder: 0,
  archivedAt: null,
  systemKey: null,
});

const names = async (store: EncryptedStore) =>
  (await store.list("category")).map((r) => `${r.id}:${r.body.name}/${r.body.color}`).sort();

describe("push and pull between two devices", () => {
  it("round-trips creates, edits and deletes", async () => {
    const server = fakeServer();
    const one = await device(server);
    const two = await device(server);
    await one.store.put("category", A, category("Food"));
    await one.store.put("category", B, category("Rent"));
    const r1 = await one.engine.run();
    expect(r1).toMatchObject({ ok: true, pushed: 2 });
    expect(await one.store.readOutbox(10)).toEqual([]);
    expect((await one.store.getRaw("category", A))?.version).toBeGreaterThan(0);

    await two.engine.run();
    expect(await names(two.store)).toEqual([`${A}:Food/#fff`, `${B}:Rent/#fff`]);
    expect(await two.store.readOutbox(10)).toEqual([]);

    await two.store.put("category", A, category("Groceries"));
    await two.store.delete("category", B);
    await two.engine.run();
    await one.engine.run();
    expect(await names(one.store)).toEqual([`${A}:Groceries/#fff`]);
  });

  it("never stores plaintext on the server", async () => {
    const server = fakeServer();
    const one = await device(server);
    await one.store.put("category", A, category("Secret name"));
    await one.engine.run();
    const wire = server.rows.get(A);
    expect(JSON.stringify(wire)).not.toContain("Secret");
    const opened = await openRecord(
      await getKeys(),
      { userId: USER, type: "category", id: A, keyV: 1 },
      fromBase64Url(wire?.body ?? ""),
    );
    expect((opened as { name: string }).name).toBe("Secret name");
  });
});

describe("conflicts", () => {
  async function setup() {
    const server = fakeServer();
    const one = await device(server);
    const two = await device(server);
    await one.store.put("category", A, category("Food", "#111"));
    await one.engine.run();
    await two.engine.run();
    return { server, one, two };
  }

  it("merges disjoint fields", async () => {
    const { one, two } = await setup();
    await one.store.put("category", A, category("Groceries", "#111"));
    await two.store.put("category", A, category("Food", "#222"));
    await one.engine.run();
    const r = await two.engine.run();
    expect(r.merged).toBe(1);
    expect(await names(two.store)).toEqual([`${A}:Groceries/#222`]);
    await one.engine.run();
    expect(await names(one.store)).toEqual([`${A}:Groceries/#222`]);
    expect(await two.store.readOutbox(10)).toEqual([]);
  });

  it("keeps the local value of a field both changed", async () => {
    const { one, two } = await setup();
    await one.store.put("category", A, category("Mine"));
    await two.store.put("category", A, category("Theirs"));
    await one.engine.run();
    await two.engine.run();
    await one.engine.run();
    expect(await names(one.store)).toEqual([`${A}:Theirs/#fff`]);
    expect(await names(two.store)).toEqual(await names(one.store));
  });

  it("takes the server copy without pushing when the content is identical", async () => {
    const server = fakeServer();
    const one = await device(server);
    const two = await device(server);
    await one.store.put("category", C, category("Same"));
    await two.store.put("category", C, category("Same"));
    await one.engine.run();
    const posts = server.posts;
    const r = await two.engine.run();
    expect(r.ok).toBe(true);
    expect(server.posts).toBe(posts + 1); // only the conflicting push, no re-push
    expect(await two.store.readOutbox(10)).toEqual([]);
    expect((await two.store.getRaw("category", C))?.version).toBe(
      (await one.store.getRaw("category", C))?.version,
    );
  });

  it("keeps the server's deletion and reports an unsent edit", async () => {
    const { one, two } = await setup();
    await one.store.delete("category", A);
    await one.engine.run();
    await two.store.put("category", A, category("Edited"));
    const r = await two.engine.run();
    expect(r.serverDeleted).toEqual([A]);
    expect(two.problems.some((p) => p.code === "server_deleted")).toBe(true);
    expect(await two.store.list("category")).toEqual([]);
    expect(await two.store.readOutbox(10)).toEqual([]);
  });

  it("a local delete beats a server edit", async () => {
    const { server, one, two } = await setup();
    await one.store.put("category", A, category("Edited"));
    await one.engine.run();
    await two.store.delete("category", A);
    await two.engine.run();
    expect(server.rows.get(A)?.deleted).toBe(true);
    await one.engine.run();
    expect(await one.store.list("category")).toEqual([]);
  });

  it("drops a change the server answers not_found to", async () => {
    const { server, one } = await setup();
    server.rows.delete(A);
    await one.store.put("category", A, category("Edited"));
    const r = await one.engine.run();
    expect(r.dropped).toEqual([A]);
    expect(await one.store.readOutbox(10)).toEqual([]);
  });
});

describe("pull", () => {
  it("pages and follows next", async () => {
    const server = fakeServer();
    server.pullLimit = 2;
    const one = await device(server);
    const two = await device(server);
    for (const id of [A, B, C]) await one.store.put("category", id, category(`n${id.slice(-1)}`));
    await one.engine.run();
    await two.engine.run();
    expect((await two.store.list("category")).length).toBe(3);
    expect(await two.store.getMeta("latest")).toBe(3);
  });

  it("pages a full download past a purge with base=0", async () => {
    const server = fakeServer();
    server.pullLimit = 1;
    const one = await device(server);
    await one.store.put("category", A, category("a"));
    await one.store.put("category", B, category("b"));
    await one.store.put("category", C, category("c"));
    await one.engine.run();
    await one.store.delete("category", B);
    await one.engine.run();
    server.purge();
    const fresh = await device(server);
    const r = await fresh.engine.run();
    expect(r.ok).toBe(true);
    expect((await fresh.store.list("category")).map((x) => x.id).sort()).toEqual([A, C]);
  });

  it("resyncs on 410 and re-applies pending local edits", async () => {
    const server = fakeServer();
    const one = await device(server);
    const two = await device(server);
    await one.store.put("category", A, category("a", "#111"));
    await one.store.put("category", B, category("b"));
    await one.engine.run();
    await two.engine.run();
    await one.store.delete("category", B);
    await one.engine.run();
    server.purge();
    // Two never saw the delete; it has a pending edit that cannot be pushed (offline).
    await two.store.put("category", A, category("a", "#999"));
    server.offline = true;
    expect((await two.engine.run()).ok).toBe(false);
    server.offline = false;
    // Only the pull fails with 410: make the push impossible by keeping the entry through a stop.
    const r = await two.engine.run();
    expect(r.ok).toBe(true);
    expect(await names(two.store)).toEqual([`${A}:a/#999`]);
    expect(server.rows.get(A) && (await one.engine.run()).ok).toBe(true);
    expect(await names(one.store)).toEqual([`${A}:a/#999`]);
  });

  it("keeps a pending edit set aside across a resync that follows a failed push", async () => {
    const server = fakeServer();
    const one = await device(server);
    const two = await device(server);
    await one.store.put("category", A, category("a", "#111"));
    await one.store.put("category", B, category("b"));
    await one.engine.run();
    await two.engine.run();
    await one.store.delete("category", B);
    await one.engine.run();
    server.purge();
    // The push answers 500 once, then everything is fine: the 410 pull still must not lose it.
    await two.store.put("category", A, category("a", "#999"));
    const real = server.fetch;
    let failed = false;
    server.fetch = (async (input: string, init?: RequestInit) => {
      if (init?.method === "POST" && !failed) {
        failed = true;
        return new Response("{}", { status: 500 });
      }
      return real(input, init);
    }) as typeof fetch;
    expect((await two.engine.run()).error).toBe("server");
    expect((await two.engine.run()).ok).toBe(true);
    expect(await names(two.store)).toEqual([`${A}:a/#999`]);
  });

  it("quarantines a body sealed with another key, and a body that fails validation", async () => {
    const server = fakeServer();
    const other = await deriveRecordKeys(generateDataKey());
    const sealed = toBase64Url(
      await sealRecord(other, { userId: USER, type: "category", id: A, keyV: 1 }, category("x")),
    );
    server.rows.set(A, {
      id: A,
      type: "category",
      version: ++server.counter,
      deleted: false,
      keyV: 1,
      encV: 1,
      body: sealed,
    });
    const invalid = toBase64Url(
      await sealRecord(
        await getKeys(),
        { userId: USER, type: "category", id: B, keyV: 1 },
        { nope: 1 },
      ),
    );
    server.rows.set(B, {
      id: B,
      type: "category",
      version: ++server.counter,
      deleted: false,
      keyV: 1,
      encV: 1,
      body: invalid,
    });
    const good = await device(server);
    await good.store.put("category", C, category("fine"));
    await good.engine.run();
    const r = await good.engine.run();
    expect(r.ok).toBe(true);
    expect(await good.store.quarantineCount()).toBe(2);
    expect((await good.store.list("category")).map((x) => x.id)).toEqual([C]);
  });
});

describe("runs", () => {
  it("fails offline, keeps the outbox, and succeeds once online", async () => {
    const server = fakeServer();
    const one = await device(server);
    await one.store.put("category", A, category("a"));
    server.offline = true;
    const off = await one.engine.run();
    expect(off).toMatchObject({ ok: false, error: "offline" });
    expect((await one.store.readOutbox(10)).length).toBe(1);
    server.offline = false;
    expect((await one.engine.run()).ok).toBe(true);
    expect(await one.store.readOutbox(10)).toEqual([]);
    expect(server.rows.size).toBe(1);
  });

  it("coalesces overlapping runs and picks up writes made during one", async () => {
    const server = fakeServer();
    const one = await device(server);
    await one.store.put("category", A, category("a"));
    const p1 = one.engine.run();
    const p2 = one.engine.run();
    expect(p2).toBe(p1);
    await one.store.put("category", B, category("b"));
    await p1;
    expect(server.rows.size).toBe(2);
    expect(await one.store.readOutbox(10)).toEqual([]);
  });

  it("start() syncs after a local write, ignoring its own commits", async () => {
    const server = fakeServer();
    const one = await device(server);
    const two = await device(server);
    const stop = one.engine.start();
    await new Promise((r) => setTimeout(r, 100));
    await one.store.put("category", A, category("a"));
    await new Promise((r) => setTimeout(r, 400));
    expect(server.rows.has(A)).toBe(true);
    const posts = server.posts;
    await two.store.put("category", B, category("b"));
    await two.engine.run();
    await new Promise((r) => setTimeout(r, 300));
    // one's own pull applied B without scheduling pushes
    expect(server.posts).toBe(posts + 1);
    stop();
  });
});
