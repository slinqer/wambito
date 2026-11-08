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
import { describe, expect, it, vi } from "vitest";
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

// ---- review fixes ------------------------------------------------------------------------------

type Fetch = typeof fetch;
/** Replaces the server's fetch with `fn`, which gets the real one to call. */
function intercept(
  server: Server,
  fn: (real: Fetch, input: string, init?: RequestInit) => unknown,
) {
  const real = server.fetch;
  server.fetch = ((input: string, init?: RequestInit) => fn(real, input, init)) as Fetch;
}
const status = (code: number, body: unknown = { code: "x" }) =>
  new Response(JSON.stringify(body), {
    status: code,
    headers: { "content-type": "application/json" },
  });
const changeIds = (init?: RequestInit) =>
  (JSON.parse(String(init?.body)) as { changes: Array<{ id: string }> }).changes.map((c) => c.id);

async function sealedBy(k: RecordKeys, id: string, body: unknown) {
  return toBase64Url(await sealRecord(k, { userId: USER, type: "category", id, keyV: 1 }, body));
}

describe("runs never loop and park what keeps failing", () => {
  it("parks a change whose conflict copy cannot be opened, and the run ends", async () => {
    const server = fakeServer();
    const one = await device(server);
    await one.store.put("category", A, category("a"));
    await one.engine.run();
    const other = await deriveRecordKeys(generateDataKey());
    const row = server.rows.get(A);
    if (row) {
      row.version = ++server.counter;
      row.body = await sealedBy(other, A, category("x"));
    }
    await one.store.put("category", A, category("mine"));
    const r = await one.engine.run();
    expect(r.ok).toBe(true);
    expect(r.parked).toEqual([A]);
    expect(one.problems).toContainEqual({ code: "parked", ids: [A] });
    const [entry] = await one.store.readOutbox(10);
    expect(entry?.park).toMatchObject({ attempts: 1, lastError: "conflict_unreadable" });
    // Backing off: the next run does not send it again.
    const posts = server.posts;
    await one.engine.run();
    expect(server.posts).toBe(posts);
  });

  it("parks a change the server gave no result for", async () => {
    const server = fakeServer();
    const one = await device(server);
    intercept(server, async (real, input, init) => {
      if (init?.method !== "POST") return real(input, init);
      const res = (await (await real(input, init)).json()) as { results: unknown[] };
      return status(200, { results: res.results.filter((x) => (x as { id: string }).id !== B) });
    });
    await one.store.put("category", A, category("a"));
    await one.store.put("category", B, category("b"));
    const r = await one.engine.run();
    expect(r.ok).toBe(true);
    expect(r.parked).toEqual([B]);
    expect((await one.store.readOutbox(10)).map((e) => [e.id, e.park?.lastError])).toEqual([
      [B, "no_result"],
    ]);
  });

  it("parks a change that conflicts on every push", async () => {
    const server = fakeServer();
    const one = await device(server);
    await one.store.put("category", A, category("a"));
    await one.engine.run();
    await one.store.put("category", A, category("b"));
    intercept(server, async (real, input, init) => {
      if (init?.method !== "POST") return real(input, init);
      const row = server.rows.get(A);
      if (row) row.version = ++server.counter; // someone else always wins the race
      return real(input, init);
    });
    const r = await one.engine.run();
    expect(r.ok).toBe(true);
    expect(r.parked).toEqual([A]);
    expect((await one.store.readOutbox(10))[0]?.park?.lastError).toBe("conflict_limit");
  });

  it("tries a parked change again after its back-off, or as soon as the person edits it", async () => {
    const server = fakeServer();
    let clock = 1_000_000;
    const store = await createEncryptedStore(`device-${++counter}`);
    const engine = createSyncEngine({
      store,
      fetch: (...args) => server.fetch(...args),
      userId: USER,
      keys: await getKeys(),
      keyV: 1,
      now: () => clock,
    });
    let reject = true;
    intercept(server, (real, input, init) =>
      init?.method === "POST" && reject ? status(422) : real(input, init),
    );
    await store.put("category", A, category("a"));
    expect((await engine.run()).parked).toEqual([A]);
    reject = false;
    expect((await engine.run()).pushed).toBe(0);
    clock += 24 * 60 * 60 * 1000;
    expect((await engine.run()).pushed).toBe(1);
    reject = true;
    await store.put("category", A, category("a2"));
    await engine.run();
    reject = false;
    await store.put("category", A, category("a3"));
    expect((await engine.run()).pushed).toBe(1);
    expect(await store.readOutbox(10)).toEqual([]);
  });
});

describe("one bad change does not block the others", () => {
  it("bisects a batch the server rejects whole and parks only the bad change", async () => {
    const server = fakeServer();
    const one = await device(server);
    const two = await device(server);
    await two.store.put("category", C, category("from two"));
    await two.engine.run();
    intercept(server, (real, input, init) =>
      init?.method === "POST" && changeIds(init).includes(B) ? status(422) : real(input, init),
    );
    await one.store.put("category", A, category("a"));
    await one.store.put("category", B, category("b"));
    const r = await one.engine.run();
    expect(r).toMatchObject({ ok: true, pushed: 1, parked: [B] });
    expect(server.rows.has(A)).toBe(true);
    expect((await one.store.readOutbox(10))[0]).toMatchObject({
      id: B,
      park: { lastError: "rejected_422" },
    });
    // The pull still ran.
    expect((await one.store.get("category", C))?.body.name).toBe("from two");
  });

  it("parks the batch on 409 key_version_mismatch and still pulls", async () => {
    const server = fakeServer();
    const one = await device(server);
    const two = await device(server);
    await two.store.put("category", C, category("from two"));
    await two.engine.run();
    intercept(server, (real, input, init) =>
      init?.method === "POST" ? status(409, { code: "key_version_mismatch" }) : real(input, init),
    );
    await one.store.put("category", A, category("a"));
    const r = await one.engine.run();
    expect(r).toMatchObject({ ok: true, parked: [A] });
    expect((await one.store.readOutbox(10))[0]?.park?.lastError).toBe("rejected_409");
    expect((await one.store.get("category", C))?.body.name).toBe("from two");
  });

  it("still stops on a server error, keeping the change unparked", async () => {
    const server = fakeServer();
    const one = await device(server);
    intercept(server, (real, input, init) =>
      init?.method === "POST" ? status(503) : real(input, init),
    );
    await one.store.put("category", A, category("a"));
    expect(await one.engine.run()).toMatchObject({ ok: false, error: "server" });
    expect((await one.store.readOutbox(10))[0]?.park).toBeUndefined();
  });
});

describe("pulls never overwrite or lose local edits", () => {
  it("does not apply a pulled record over a local write made while the page was opened", async () => {
    const server = fakeServer();
    const one = await device(server);
    await one.store.put("category", A, category("a"));
    await one.engine.run();
    const twoStore = await createEncryptedStore(`device-${++counter}`);
    await twoStore.put("category", A, category("a"), { origin: "remote", version: 1, keyV: 1 });
    await twoStore.setMeta("latest", 1);
    await one.store.put("category", A, category("server edit"));
    await one.engine.run();
    // Between the decrypt and the apply, the person edits A on device two.
    let injected = false;
    const sneaky = {
      ...twoStore,
      transaction: (async (fn: Parameters<EncryptedStore["transaction"]>[0]) => {
        if (!injected) {
          injected = true;
          await twoStore.put("category", A, category("typed meanwhile"));
        }
        return twoStore.transaction(fn);
      }) as EncryptedStore["transaction"],
    } satisfies EncryptedStore;
    const engine = createSyncEngine({
      store: sneaky,
      fetch: (input, init) =>
        // Only the pull: the push of the injected write comes in a later run.
        init?.method === "POST"
          ? Promise.reject(new TypeError("offline"))
          : server.fetch(input, init),
      userId: USER,
      keys: await getKeys(),
      keyV: 1,
    });
    await engine.run();
    expect(injected).toBe(true);
    expect((await twoStore.get("category", A))?.body.name).toBe("typed meanwhile");
    expect((await twoStore.readOutbox(10)).map((e) => e.id)).toEqual([A]);
  });

  it("takes the server's copy of a deterministic id both devices created (paid beats pending)", async () => {
    const server = fakeServer();
    const one = await device(server);
    const two = await device(server);
    const occurrence = (status: "paid" | "pending"): RecordBodies["transaction"] => ({
      s: 1,
      name: "Rent",
      amount: -80000,
      currency: "COP",
      date: "2026-11-01",
      status,
      note: null,
      categoryId: A,
      accountId: null,
      recurrenceId: B,
      occurrenceMonth: "2026-11",
      source: "recurrence",
      needsReview: false,
      captureSource: null,
      capturedAt: null,
      captureMerchantKey: null,
    });
    await one.store.put("transaction", C, occurrence("paid"));
    await one.engine.run();
    const version = server.rows.get(C)?.version;
    await two.store.put("transaction", C, occurrence("pending"));
    const posts = server.posts;
    const r = await two.engine.run();
    expect(r.ok).toBe(true);
    expect(server.posts).toBe(posts + 1);
    expect(server.rows.get(C)?.version).toBe(version);
    expect((await two.store.get("transaction", C))?.body.status).toBe("paid");
    expect(await two.store.readOutbox(10)).toEqual([]);
  });

  it("carries fields it does not know through a conflict merge", async () => {
    const server = fakeServer();
    const one = await device(server);
    await one.store.put("category", A, category("a"));
    await one.engine.run();
    // A newer client adds a field this one does not know.
    const row = server.rows.get(A);
    if (row) {
      row.version = ++server.counter;
      row.body = await sealedBy(await getKeys(), A, { ...category("a"), future: { x: 1 } });
    }
    await one.store.put("category", A, category("renamed"));
    await one.engine.run();
    const opened = await openRecord(
      await getKeys(),
      { userId: USER, type: "category", id: A, keyV: 1 },
      fromBase64Url(server.rows.get(A)?.body ?? ""),
    );
    expect(opened).toMatchObject({ name: "renamed", future: { x: 1 } });
  });
});

describe("resync keeps pending edits", () => {
  async function stale() {
    const server = fakeServer();
    const one = await device(server);
    const two = await device(server);
    await one.store.put("category", A, category("a", "#111"));
    await one.store.put("category", B, category("b"));
    await one.engine.run();
    await two.engine.run();
    await one.store.delete("category", B);
    await one.store.put("category", A, category("renamed", "#111"));
    await one.store.put("category", C, category("c"));
    await one.engine.run();
    server.purge();
    return { server, one, two };
  }

  it("re-applies only the touched fields onto the fresh server copy", async () => {
    const { server, two } = await stale();
    await two.store.put("category", A, category("a", "#999"));
    let rejected = false;
    intercept(server, (real, input, init) => {
      if (init?.method === "POST" && !rejected) {
        rejected = true;
        return status(422);
      }
      return real(input, init);
    });
    const r = await two.engine.run();
    expect(r).toMatchObject({ ok: true, resynced: true });
    expect(await names(two.store)).toEqual([`${A}:renamed/#999`, `${C}:c/#fff`]);
    await two.engine.run();
    expect(await two.store.readOutbox(10)).toEqual([]);
  });

  it("keeps the edit when the pull fails mid-resync, and recovers it on a later run", async () => {
    const { server, one, two } = await stale();
    await two.store.put("category", A, category("a", "#999"));
    server.pullLimit = 1;
    let rejectPush = true;
    let breakPage = true;
    intercept(server, (real, input, init) => {
      if (init?.method === "POST" && rejectPush) {
        rejectPush = false;
        return status(422);
      }
      // The second page of the full download fails.
      if (init?.method !== "POST" && input.includes("base=0") && !input.includes("since=0")) {
        if (breakPage) {
          breakPage = false;
          throw new TypeError("Failed to fetch");
        }
      }
      return real(input, init);
    });
    expect(await two.engine.run()).toMatchObject({ ok: false, error: "offline" });
    expect((await two.store.readOutbox(10)).map((e) => e.id)).toEqual([A]);
    const r = await two.engine.run();
    expect(r.ok).toBe(true);
    expect(await names(two.store)).toEqual([`${A}:renamed/#999`, `${C}:c/#fff`]);
    expect(await two.store.readOutbox(10)).toEqual([]);
    await one.engine.run();
    expect(await names(one.store)).toEqual([`${A}:renamed/#999`, `${C}:c/#fff`]);
  });
});

describe("tabs", () => {
  it("runs under a Web Lock named for the account when the browser has them", async () => {
    const server = fakeServer();
    const one = await device(server);
    const request = vi.fn((_name: string, fn: () => Promise<unknown>) => fn());
    vi.stubGlobal("navigator", { locks: { request } });
    try {
      expect((await one.engine.run()).ok).toBe(true);
      expect(request).toHaveBeenCalledWith(`wambito-sync-${USER}`, expect.any(Function));
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it("stops with `closed` when the vault was closed", async () => {
    const server = fakeServer();
    const one = await device(server);
    one.store.close();
    expect(await one.engine.run()).toMatchObject({ ok: false, error: "closed" });
  });
});
