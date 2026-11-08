import { randomUUID } from "node:crypto";
import { records } from "@wambito/db";
import { sql } from "@wambito/db/orm";
import { afterAll, afterEach, beforeAll, describe, expect, test, vi } from "vitest";
import type { SyncHooks } from "../src/deps.ts";
import { purgeTombstones } from "../src/services/sync.ts";
import { createTestApp, type TestApp } from "./harness.ts";

type Headers = { authorization: string };
interface SyncRecord {
  id: string;
  type: string;
  version: number;
  deleted: boolean;
  keyV: number;
  encV: number;
  body: string | null;
}
interface Change {
  id: string;
  type: string;
  baseVersion: number | null;
  deleted: boolean;
  keyV: number;
  encV: number;
  body: string | null;
}
type Result = { id: string; version?: number; conflict?: SyncRecord; error?: string };

const hooks: SyncHooks = {};
let t: TestApp;
let a: Headers;
let b: Headers;
let aId: string;

beforeAll(async () => {
  t = await createTestApp({}, { syncHooks: hooks });
  ({ headers: a, userId: aId } = await t.signIn("a@wambito.test"));
  ({ headers: b } = await t.signIn("b@wambito.test"));
});
afterAll(() => t?.stop());
afterEach(() => {
  hooks.beforeCommit = undefined;
  vi.restoreAllMocks();
});

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
const b64 = (text: string) => Buffer.from(text).toString("base64url");

function create(body: string, overrides: Partial<Change> = {}): Change {
  return {
    id: randomUUID(),
    type: "transaction",
    baseVersion: null,
    deleted: false,
    keyV: 1,
    encV: 1,
    body: b64(body),
    ...overrides,
  };
}

const pushRaw = (headers: Headers, changes: unknown[]) =>
  t.request("POST", "/v2/sync", { headers, body: { changes } });

async function push(headers: Headers, changes: Change[]): Promise<Result[]> {
  const res = await pushRaw(headers, changes);
  expect(res.status).toBe(200);
  return ((await res.json()) as { results: Result[] }).results;
}

async function pull(
  headers: Headers,
  since = 0,
  limit?: number,
): Promise<{ records: SyncRecord[]; next: number | null; latest: number }> {
  const query = `since=${since}${limit === undefined ? "" : `&limit=${limit}`}`;
  const res = await t.request("GET", `/v2/sync?${query}`, { headers });
  expect(res.status).toBe(200);
  return (await res.json()) as { records: SyncRecord[]; next: number | null; latest: number };
}

async function pullAll(headers: Headers): Promise<SyncRecord[]> {
  return (await pull(headers, 0, 1000)).records;
}

describe("/v2/sync", () => {
  test("pull from 0 returns every record in version order", async () => {
    const { headers } = await t.signIn("pull@wambito.test");
    const changes = [create("one"), create("two"), create("three")];
    const results = await push(headers, changes);
    const versions = results.map((r) => r.version as number);
    expect(versions).toEqual([...versions].sort((x, y) => x - y));

    const first = await pull(headers, 0, 2);
    expect(first.records.map((r) => r.id)).toEqual([changes[0]?.id, changes[1]?.id]);
    expect(first.records[0]).toEqual({
      id: changes[0]?.id,
      type: "transaction",
      version: versions[0],
      deleted: false,
      keyV: 1,
      encV: 1,
      body: b64("one"),
    });
    expect(first.next).toBe(versions[1]);
    expect(first.latest).toBe(versions[2]);

    const second = await pull(headers, first.next as number, 2);
    expect(second.records.map((r) => r.id)).toEqual([changes[2]?.id]);
    expect(second.next).toBeNull();
    expect(second.latest).toBe(versions[2]);

    const empty = await pull(headers, second.latest);
    expect(empty).toEqual({ records: [], next: null, latest: versions[2] });
  });

  test("a new account pulls nothing, latest 0", async () => {
    const { headers } = await t.signIn("empty@wambito.test");
    expect(await pull(headers)).toEqual({ records: [], next: null, latest: 0 });
  });

  test("create, update with the right baseVersion, delete", async () => {
    const change = create("v1");
    const [created] = await push(a, [change]);
    const v1 = created?.version as number;
    const [updated] = await push(a, [{ ...change, baseVersion: v1, body: b64("v2") }]);
    const v2 = updated?.version as number;
    expect(v2).toBeGreaterThan(v1);
    const [deleted] = await push(a, [{ ...change, baseVersion: v2, deleted: true, body: null }]);
    const v3 = deleted?.version as number;
    expect(v3).toBeGreaterThan(v2);

    const { records: pulled } = await pull(a, v2);
    expect(pulled.find((r) => r.id === change.id)).toEqual({
      id: change.id,
      type: "transaction",
      version: v3,
      deleted: true,
      keyV: 1,
      encV: 1,
      body: null,
    });
  });

  test("a stale baseVersion is a conflict carrying the current record", async () => {
    const first = create("first");
    const second = create("second");
    const [r1, r2] = await push(a, [first, second]);
    const [moved] = await push(a, [
      { ...first, baseVersion: r1?.version as number, body: b64("first, edited") },
    ]);

    const results = await push(a, [
      { ...first, baseVersion: r1?.version as number, body: b64("stale edit") },
      { ...second, baseVersion: r2?.version as number, body: b64("second, edited") },
    ]);
    expect(results[0]).toEqual({
      id: first.id,
      conflict: {
        id: first.id,
        type: "transaction",
        version: moved?.version,
        deleted: false,
        keyV: 1,
        encV: 1,
        body: b64("first, edited"),
      },
    });
    expect(results[1]?.id).toBe(second.id);
    expect(results[1]?.version).toBeGreaterThan(moved?.version as number);
    const all = await pullAll(a);
    expect(all.find((r) => r.id === second.id)?.body).toBe(b64("second, edited"));
    expect(all.find((r) => r.id === first.id)?.body).toBe(b64("first, edited"));
  });

  test("an update for an id the person does not have is not_found, and creates nothing", async () => {
    const ghost = create("resurrected", { baseVersion: 1 });
    const tombstone = create("", { baseVersion: 1, deleted: true, body: null });
    const results = await push(a, [ghost, tombstone]);
    expect(results).toEqual([
      { id: ghost.id, error: "not_found" },
      { id: tombstone.id, error: "not_found" },
    ]);
    const ids = (await pullAll(a)).map((r) => r.id);
    expect(ids).not.toContain(ghost.id);
    expect(ids).not.toContain(tombstone.id);
  });

  test("type is immutable: an update with another type is a conflict", async () => {
    const change = create("a category", { type: "category" });
    const [created] = await push(a, [change]);
    const [changed] = await push(a, [
      { ...change, type: "transaction", baseVersion: created?.version as number },
    ]);
    expect(changed).toEqual({
      id: change.id,
      conflict: {
        id: change.id,
        type: "category",
        version: created?.version,
        deleted: false,
        keyV: 1,
        encV: 1,
        body: b64("a category"),
      },
    });
  });

  test("retrying a create is idempotent", async () => {
    const change = create("same");
    const [first] = await push(a, [change]);
    const [retry] = await push(a, [change]);
    expect(retry).toEqual({ id: change.id, version: first?.version });

    const [different] = await push(a, [{ ...change, body: b64("different") }]);
    expect(different).toEqual({
      id: change.id,
      conflict: {
        id: change.id,
        type: "transaction",
        version: first?.version,
        deleted: false,
        keyV: 1,
        encV: 1,
        body: b64("same"),
      },
    });
  });

  test("versions are visible in commit order", async () => {
    const { headers } = await t.signIn("order@wambito.test");
    let calls = 0;
    // The first push holds its transaction open after writing; the second must wait for it.
    hooks.beforeCommit = async () => {
      if (calls++ === 0) await sleep(600);
    };
    const one = create("one");
    const two = create("two");
    const firstPush = push(headers, [one]);
    await sleep(150);
    const secondPush = push(headers, [two]);
    await sleep(250);
    const middle = (await pullAll(headers)).map((r) => r.id);
    if (middle.includes(two.id)) expect(middle).toContain(one.id);

    const [[r1], [r2]] = await Promise.all([firstPush, secondPush]);
    expect(r2?.version).toBeGreaterThan(r1?.version as number);
    expect((await pullAll(headers)).map((r) => r.id)).toEqual([one.id, two.id]);
  });

  test("two users never see each other's records", async () => {
    const mine = create("a's secret");
    await push(a, [mine]);
    expect((await pullAll(b)).map((r) => r.id)).not.toContain(mine.id);

    const results = await push(b, [create("b's attempt", { id: mine.id }), create("b's own")]);
    expect(results[0]).toEqual({ id: mine.id, error: "id_taken" });
    expect(results[1]?.version).toBeTypeOf("number");
    expect(JSON.stringify(results)).not.toContain(b64("a's secret"));

    const theirs = await push(b, [{ ...mine, baseVersion: 1, body: b64("overwrite") }]);
    expect(theirs[0]).toEqual({ id: mine.id, error: "id_taken" });
    const own = (await pullAll(a)).find((r) => r.id === mine.id);
    expect(own?.body).toBe(b64("a's secret"));
  });

  describe("limits", () => {
    const code = async (res: Response) => ((await res.json()) as { code: string }).code;

    test("more than 500 changes", async () => {
      const changes = Array.from({ length: 501 }, () => create("x"));
      const res = await pushRaw(a, changes);
      expect(res.status).toBe(422);
      expect(await code(res)).toBe("validation_failed");
    });

    test("a body over 64 KiB decoded", async () => {
      const ok = create("");
      ok.body = Buffer.alloc(64 * 1024, 1).toString("base64url");
      expect((await push(a, [ok]))[0]?.version).toBeTypeOf("number");
      const big = create("");
      big.body = Buffer.alloc(64 * 1024 + 1, 1).toString("base64url");
      const res = await pushRaw(a, [big]);
      expect(res.status).toBe(422);
      expect(await code(res)).toBe("validation_failed");
    });

    test("deleted and body inconsistent, unknown type, not base64url", async () => {
      for (const change of [
        create("x", { deleted: true }),
        { ...create("x"), body: null },
        create("x", { type: "secret" }),
        { ...create("x"), body: "not base64url!" },
      ]) {
        const res = await pushRaw(a, [change]);
        expect(res.status).toBe(422);
        expect(await code(res)).toBe("validation_failed");
      }
    });

    test("a request over 4 MiB", async () => {
      const changes = Array.from({ length: 70 }, () => {
        const change = create("");
        change.body = Buffer.alloc(64 * 1024, 2).toString("base64url");
        return change;
      });
      const res = await pushRaw(a, changes);
      expect(res.status).toBe(413);
      expect(await code(res)).toBe("payload_too_large");
    });

    test("the 100,001st live record", async () => {
      const { headers, userId } = await t.signIn("full@wambito.test");
      await t.admin.execute(sql`insert into ${records} (id, user_id, type, key_v, enc_v, body)
        select gen_random_uuid(), ${userId}, 'transaction', 1, 1, '\\x00'::bytea
        from generate_series(1, 100000)`);
      const res = await pushRaw(headers, [create("one too many")]);
      expect(res.status).toBe(409);
      expect(await code(res)).toBe("record_limit");
      // A tombstone is not a live record.
      const tombstone = create("", { deleted: true, body: null });
      expect((await push(headers, [tombstone]))[0]?.version).toBeTypeOf("number");
    });
  });

  test("scopes: finance:read pulls, finance:write pushes", async () => {
    const { headers } = await t.signIn("assistant@wambito.test");
    const read = await t.authorize("assistant@wambito.test", { scope: "finance:read", headers });
    const readHeaders = { authorization: `Bearer ${read.accessToken}` };
    expect((await t.request("GET", "/v2/sync?since=0", { headers: readHeaders })).status).toBe(200);
    const denied = await pushRaw(readHeaders, [create("x")]);
    expect(denied.status).toBe(403);
    expect(((await denied.json()) as { code: string }).code).toBe("insufficient_scope");

    const write = await t.authorize("assistant@wambito.test", {
      scope: "finance:read finance:write",
      headers,
    });
    const writeHeaders = { authorization: `Bearer ${write.accessToken}` };
    expect((await pushRaw(writeHeaders, [create("x")])).status).toBe(200);
  });

  test("purgeTombstones removes tombstones older than 180 days, nothing else", async () => {
    const now = new Date("2026-11-08T12:00:00Z");
    const daysAgo = (days: number) => new Date(now.getTime() - days * 86_400_000).toISOString();
    const old = randomUUID();
    const recent = randomUUID();
    const oldLive = randomUUID();
    await t.admin.execute(sql`insert into ${records}
      (id, user_id, type, deleted, key_v, enc_v, body, updated_at) values
      (${old}, ${aId}, 'transaction', true, 1, 1, null, ${daysAgo(181)}::timestamptz),
      (${recent}, ${aId}, 'transaction', true, 1, 1, null, ${daysAgo(179)}::timestamptz),
      (${oldLive}, ${aId}, 'transaction', false, 1, 1, '\\x01'::bytea, ${daysAgo(400)}::timestamptz)`);
    const before = (await pullAll(a)).length;

    expect(await purgeTombstones(t.db, now)).toBe(1);
    const ids = (await pullAll(a)).map((r) => r.id);
    expect(ids).not.toContain(old);
    expect(ids).toContain(recent);
    expect(ids).toContain(oldLive);
    expect(ids).toHaveLength(before - 1);
  });

  test("no request body is logged", async () => {
    const marker = "MARKER-7f3a9c-do-not-log";
    const spies = (["log", "info", "warn", "error", "debug"] as const).map((level) =>
      vi.spyOn(console, level),
    );
    await push(a, [create(marker)]);
    const logged = JSON.stringify(spies.flatMap((spy) => spy.mock.calls));
    expect(logged).not.toContain(marker);
    expect(logged).not.toContain(b64(marker));
  });
});
