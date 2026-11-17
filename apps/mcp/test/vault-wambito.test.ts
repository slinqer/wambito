import { randomUUID } from "node:crypto";
import { Client, StreamableHTTPClientTransport } from "@modelcontextprotocol/client";
import { ToolError, type Wambito } from "@wambito/ai-assistant-tools";
import {
  deriveRecordKeys,
  fromBase64Url,
  generateDataKey,
  type RecordKeys,
  sealKeyLink,
  sealRecord,
  toBase64Url,
  wrapDataKey,
} from "@wambito/crypto";
import {
  createLocalBackend,
  createMemoryEncryptedStore,
  createSyncEngine,
  type EncryptedStore,
  type Keyring,
} from "@wambito/vault";
import { createLocalJWKSet, decodeJwt, type JSONWebKeySet } from "jose";
import { afterAll, afterEach, beforeAll, describe, expect, test, vi } from "vitest";
import { createTestApp, type TestApp } from "../../api/test/harness.ts";
import { apiWambito, RECONNECT_MESSAGE } from "../src/api-wambito.ts";
import { createMcpApp } from "../src/app.ts";
import { createVaultCache, type VaultCache } from "../src/vault-cache.ts";
import { createWambitoFor, vaultWambito } from "../src/vault-wambito.ts";
import { jwtVerifier } from "../src/verifier.ts";
import {
  type Account,
  type Call,
  encryptedSupport,
  NOW,
  type Override,
  random,
} from "./support/encrypted-account.ts";

// The MCP opening an end-to-end-encrypted account (spec 2026-11-16 §7): the real API and its
// database; the "web" side is a vault of its own (memory store, sync engine, local backend) that
// seals and pushes the person's records, makes the assistant's wrap, and rotates the keys.

let t: TestApp;
let API: string;
const support = encryptedSupport(() => t);
const { network, localFetch, encryptedAccount, connect, withFixture, rotate, nextPerson } = support;
let privateKey: CryptoKey;
let cache: VaultCache;

beforeAll(async () => {
  t = await createTestApp();
  API = t.config.API_URL;
  privateKey = t.wkPrivateKey as CryptoKey;
});
afterAll(() => t?.stop());
afterEach(() => {
  vi.restoreAllMocks();
});

/** The MCP's Wambito for one request, over `fetch`. */
function vault(conn: { token: string; wk: string }, fetch: typeof globalThis.fetch = network()) {
  return vaultWambito(
    { apiUrl: API, privateKey, cache, fetch, now: () => new Date(NOW) },
    conn.token,
    conn.wk,
  );
}

const sorted = <T extends { id: string }>(items: T[]) =>
  [...items].sort((a, b) => a.id.localeCompare(b.id));

async function toolError(promise: Promise<unknown>): Promise<ToolError> {
  const error = await promise.then(
    () => undefined,
    (e: unknown) => e,
  );
  expect(error).toBeInstanceOf(ToolError);
  return error as ToolError;
}

beforeAll(() => {
  cache = createVaultCache({ maxAccounts: 50, maxBytes: 50_000_000, idleMs: 30 * 60_000 });
});

test("a token without wk uses the /v1 path as today", async () => {
  const email = `plain-${nextPerson()}@wambito.test`;
  const { headers } = await t.signIn(email);
  await t.request("POST", "/v1/categories", {
    headers,
    body: { name: "Rent", kind: "expense", icon: "home", color: "blue" },
  });
  const { accessToken } = await t.authorize(email, { headers });
  expect(decodeJwt(accessToken).wk).toBeUndefined();
  const calls: Call[] = [];
  const wambitoFor = createWambitoFor({ apiUrl: API, privateKey, cache, fetch: network(calls) });
  const categories = await wambitoFor(accessToken, undefined).listCategories();
  expect(categories.map((c) => c.name)).toContain("Rent");
  expect(calls.map((c) => `${c.method} ${c.path}`)).toEqual(["GET /v1/categories"]);
});

test("a token with wk without the MCP's private key is the reconnect error", async () => {
  const account = await encryptedAccount();
  const conn = await connect(account);
  const wambitoFor = createWambitoFor({ apiUrl: API, cache, fetch: network() });
  const error = await toolError(wambitoFor(conn.token, conn.wk).listCategories());
  expect(error.code).toBe("reconnect");
  expect(error.message).toBe(RECONNECT_MESSAGE);
});

test("the verifier hands the wk claim on, still encrypted", async () => {
  const account = await encryptedAccount();
  const conn = await connect(account);
  const jwks = (await (await t.app.request("/auth/jwks")).json()) as JSONWebKeySet;
  const verifier = jwtVerifier(
    { MCP_URL: t.config.MCP_URL ?? "", AUTH_ISSUER: `${API}/auth`, MCP_API_URL: API },
    createLocalJWKSet(jwks),
  );
  const info = await verifier.verifyAccessToken(conn.token);
  expect(info.extra).toEqual({ userId: account.userId, wk: conn.wk });
});

test("reads through the local backend match the web's backend over the same records", async () => {
  const account = await encryptedAccount();
  await withFixture(account);
  const conn = await connect(account);
  const mcp = vault(conn);
  const web = apiWambito(API, "web", localFetch(account.web.store, account));

  const list = await mcp.listTransactions({ month: "2026-10", limit: 100 });
  expect(list.items).toHaveLength(3);
  expect(list).toEqual(await web.listTransactions({ month: "2026-10", limit: 100 }));
  expect(await mcp.monthSummary("2026-10")).toEqual(await web.monthSummary("2026-10"));
  const report = { from: "2026-09", to: "2026-10", kind: "expense" as const };
  expect(await mcp.categoryReport(report)).toEqual(await web.categoryReport(report));
  expect((await mcp.categoryReport(report)).total).toBe(8600);
});

test("a write is pushed sealed, with source mcp inside", async () => {
  const account = await encryptedAccount();
  const { food } = await withFixture(account);
  const conn = await connect(account);
  const calls: Call[] = [];
  const saved = await vault(conn, network(calls)).addTransactions(
    [
      {
        name: "Secret bread",
        amount: -2500,
        categoryId: food.id,
        date: "2026-10-21",
        status: "paid",
        source: "app",
      },
    ],
    "sealed-key",
  );
  expect(saved.items[0]?.source).toBe("mcp");

  const pushes = calls.filter((c) => c.method === "POST" && c.path === "/v2/sync");
  expect(pushes).toHaveLength(1);
  const { changes } = JSON.parse(pushes[0]?.body ?? "{}") as {
    changes: { id: string; type: string; body: string; keyV: number }[];
  };
  expect(changes.map((c) => [c.id, c.type, c.keyV])).toEqual([
    [saved.items[0]?.id, "transaction", 1],
  ]);
  expect(pushes[0]?.body).not.toContain("Secret bread");
  expect(pushes[0]?.body).not.toContain("2500");

  await account.web.sync();
  const row = await account.web.store.get("transaction", saved.items[0]?.id ?? "");
  expect(row?.body).toMatchObject({ name: "Secret bread", amount: -2500, source: "mcp" });
});

test("a read tool never posts /v2/sync", async () => {
  const account = await encryptedAccount();
  await withFixture(account);
  const conn = await connect(account);
  const calls: Call[] = [];
  const mcp = vault(conn, network(calls));
  // One MCP request (one tool) may read many times.
  await mcp.inRequest(async () => {
    await mcp.profile();
    await mcp.monthSummary("2026-10");
    await mcp.listTransactions({ month: "2026-10", limit: 100 });
    await mcp.categoryReport({ from: "2026-10", to: "2026-10", kind: "expense" });
    await mcp.trend({ from: "2026-09", to: "2026-10" });
    await mcp.listCategories();
    await mcp.listRecurrences();
  });
  expect(calls.filter((c) => c.method !== "GET")).toEqual([]);
  // One sync pass for the whole request, whatever the number of reads.
  expect(calls.filter((c) => c.path === "/v2/keys/assistant")).toHaveLength(1);
  // Outside a request bracket, each call is its own request.
  await mcp.listCategories();
  expect(calls.filter((c) => c.path === "/v2/keys/assistant")).toHaveLength(2);
});

/** The MCP app over the real verifier: `callTool` runs one tool as one MCP request. */
async function mcpApp(
  conn: { token: string },
  wambitoFor: (token: string, wk: string | undefined) => Wambito,
) {
  const jwks = (await (await t.app.request("/auth/jwks")).json()) as JSONWebKeySet;
  const config = {
    MCP_URL: t.config.MCP_URL ?? "",
    AUTH_ISSUER: `${API}/auth`,
    MCP_API_URL: API,
    RATE_LIMIT_PER_MINUTE: 120,
  };
  const mcp = createMcpApp({
    config,
    verifier: jwtVerifier(config, createLocalJWKSet(jwks)),
    wambitoFor,
    now: () => new Date(NOW),
  });
  async function client() {
    const c = new Client(
      { name: "vault", version: "1.0.0" },
      { versionNegotiation: { mode: { pin: "2026-07-28" } } },
    );
    await c.connect(
      new StreamableHTTPClientTransport(new URL(config.MCP_URL), {
        fetch: (async (url: string | URL, init?: RequestInit) =>
          mcp.request(String(url), init)) as typeof fetch,
        requestInit: { headers: { authorization: `Bearer ${conn.token}` } },
      }),
    );
    return c;
  }
  return {
    client,
    async callTool(name: string, args: Record<string, unknown>) {
      const c = await client();
      const result = await c.callTool({ name, arguments: args });
      await c.close();
      return result;
    },
  };
}

test("a retried add_transactions writes once and says alreadySaved", async () => {
  const account = await encryptedAccount();
  await withFixture(account);
  const conn = await connect(account);
  const mcp = await mcpApp(
    conn,
    createWambitoFor({ apiUrl: API, privateKey, cache, fetch: network() }),
  );
  const call = () =>
    mcp.callTool("add_transactions", {
      items: [{ name: "Lunch", amount: 18000, kind: "expense", category: "food" }],
    });
  const first = await call();
  expect(first.isError, JSON.stringify(first.content)).toBeFalsy();
  expect(first.structuredContent).toMatchObject({ alreadySaved: false });
  const second = await call();
  expect(second.isError, JSON.stringify(second.content)).toBeFalsy();
  expect(second.structuredContent).toMatchObject({ alreadySaved: true });

  await account.web.sync();
  const lunches = (await account.web.store.list("transaction")).filter(
    (r) => (r.body as { name: string }).name === "Lunch",
  );
  expect(lunches).toHaveLength(1);
  expect(lunches[0]?.body).toMatchObject({ amount: -1800000, source: "mcp" });
});

describe("an unacknowledged push is a not_saved tool error", () => {
  test.each([
    ["the push fails", () => new Response("down", { status: 503 })],
    ["the server answers nothing for the change", () => Response.json({ results: [] })],
    [
      "the server refuses the change",
      () => new Response(JSON.stringify({ code: "nope" }), { status: 400 }),
    ],
  ])("%s", async (_, answer) => {
    const account = await encryptedAccount();
    const { food } = await withFixture(account);
    const conn = await connect(account);
    const override: Override = (method, path) =>
      method === "POST" && path === "/v2/sync" ? answer() : undefined;
    const error = await toolError(
      vault(conn, network([], "", override)).addTransactions(
        [
          {
            name: "Tea",
            amount: -300,
            categoryId: food.id,
            date: "2026-10-21",
            status: "paid",
            source: "app",
          },
        ],
        "unacked",
      ),
    );
    expect(error.code).toBe("not_saved");
    expect(error.message).toMatch(/part of it may have been saved/i);
    expect(error.message).toMatch(/try(ing)? again is safe/i);
  });
});

describe("two calls on one account run one after the other", () => {
  /** A `wambitoFor` whose every MCP request gets its own tag on the recorded calls. */
  function tagged(calls: Call[]) {
    let requests = 0;
    return (token: string, wk: string | undefined) =>
      createWambitoFor({
        apiUrl: API,
        privateKey,
        cache,
        fetch: network(calls, String(++requests)),
      })(token, wk);
  }
  /** How often the recorded calls switch from one request to another. */
  const switches = (calls: Call[]) =>
    calls.map((c) => c.tag).filter((tag, i, tags) => i > 0 && tag !== tags[i - 1]).length;

  test("two create_category of one name: one category, one name-taken answer", async () => {
    const account = await encryptedAccount();
    await withFixture(account);
    const conn = await connect(account);
    const calls: Call[] = [];
    const mcp = await mcpApp(conn, tagged(calls));
    const results = await Promise.all([
      mcp.callTool("create_category", { name: "Pets", kind: "expense" }),
      mcp.callTool("create_category", { name: "Pets", kind: "expense" }),
    ]);
    // Every API call of one tool call comes before every call of the other.
    expect(switches(calls)).toBe(1);
    expect(results.filter((r) => !r.isError)).toHaveLength(1);
    const refused = results.find((r) => r.isError);
    expect(JSON.stringify(refused?.content)).toContain("category_name_taken");

    await account.web.sync();
    const pets = (await account.web.store.list("category")).filter(
      (r) => (r.body as { name: string }).name === "Pets",
    );
    expect(pets).toHaveLength(1);
  });

  test("two update_transaction on one movement: both writes land", async () => {
    const account = await encryptedAccount();
    const { items } = await withFixture(account);
    const conn = await connect(account);
    const id = items[0]?.id ?? "";
    const calls: Call[] = [];
    const mcp = await mcpApp(conn, tagged(calls));
    const results = await Promise.all([
      mcp.callTool("update_transaction", { id, name: "Market" }),
      mcp.callTool("update_transaction", { id, amount: 42 }),
    ]);
    for (const r of results) expect(r.isError, JSON.stringify(r.content)).toBeFalsy();
    expect(switches(calls)).toBe(1);
    expect(calls.filter((c) => c.method === "POST" && c.path === "/v2/sync")).toHaveLength(2);

    await account.web.sync();
    const row = await account.web.store.get("transaction", id);
    expect(row?.body).toMatchObject({ name: "Market", amount: -4200 });
  });
});

test("a failed cache write never replaces the tool's answer", async () => {
  const account = await encryptedAccount();
  await withFixture(account);
  const conn = await connect(account);
  const broken: VaultCache = {
    ...cache,
    get: (userId) => cache.get(userId),
    drop: (userId) => cache.drop(userId),
    lock: (userId, fn) => cache.lock(userId, fn),
    set: () => {
      throw new Error("cache full");
    },
  };
  const mcp = vaultWambito(
    { apiUrl: API, privateKey, cache: broken, fetch: network(), now: () => new Date(NOW) },
    conn.token,
    conn.wk,
  );
  expect((await mcp.listCategories()).map((c) => c.name)).toContain("Food");
});

test("a prompt request whose vault cannot open falls back to the default language", async () => {
  const account = await encryptedAccount();
  const conn = await connect(account, { wrap: false });
  const mcp = await mcpApp(
    conn,
    createWambitoFor({ apiUrl: API, privateKey, cache, fetch: network() }),
  );
  const c = await mcp.client();
  const { prompts } = await c.listPrompts();
  expect(prompts.length).toBeGreaterThan(0);
  await c.close();
});

test("a record under an older key version opens through the links", async () => {
  const account = await encryptedAccount();
  const { food } = await withFixture(account);
  const { dk2, web } = await rotate(account);
  await web.wambito.addTransactions(
    [
      {
        name: "Coffee",
        amount: -700,
        categoryId: food.id,
        date: "2026-10-20",
        status: "paid",
        source: "app",
      },
    ],
    "after-rotation",
  );
  await web.sync();
  const coffee = (await web.store.list("transaction")).find(
    (r) => (r.body as { name: string }).name === "Coffee",
  );
  expect((await web.store.getRaw("transaction", coffee?.id ?? ""))?.keyV).toBe(2);
  const old = (await web.store.list("transaction")).find(
    (r) => (r.body as { name: string }).name === "Dinner",
  );
  expect((await web.store.getRaw("transaction", old?.id ?? ""))?.keyV).toBe(1);

  const conn = await connect(account, { keyV: 2, dk: dk2 });
  const mcp = vault(conn);
  const reference = apiWambito(API, "web", localFetch(web.store, account));
  const list = await mcp.listTransactions({ month: "2026-10", limit: 100 });
  expect(list.items.map((i) => i.name).sort()).toEqual(["Coffee", "Dinner", "Groceries", "Pay"]);
  expect(list).toEqual(await reference.listTransactions({ month: "2026-10", limit: 100 }));
  const summary = await mcp.monthSummary("2026-10");
  expect(summary).toEqual(await reference.monthSummary("2026-10"));
  expect(
    (await mcp.categoryReport({ from: "2026-10", to: "2026-10", kind: "expense" })).total,
  ).toBe(4500 + 3200 + 700);
});

describe("the cache", () => {
  test("the second call pulls only what changed", async () => {
    const account = await encryptedAccount();
    const { food } = await withFixture(account);
    const more = Array.from({ length: 20 }, (_, i) => ({
      name: `Snack ${i}`,
      amount: -100 - i,
      categoryId: food.id,
      date: "2026-10-15",
      status: "paid" as const,
      source: "app" as const,
    }));
    await account.web.wambito.addTransactions(more, "more");
    await account.web.sync();
    const conn = await connect(account);

    const first: Call[] = [];
    await vault(conn, network(first)).listTransactions({ month: "2026-10", limit: 100 });
    const total = (await account.web.store.list("transaction")).length + 2; // + categories
    expect(sumRecords(first)).toBeGreaterThanOrEqual(total);

    await account.web.wambito.addTransactions(
      [{ ...more[0], name: "Late snack" } as (typeof more)[number]],
      "late",
    );
    await account.web.sync();
    const second: Call[] = [];
    const list = await vault(conn, network(second)).listTransactions({
      month: "2026-10",
      limit: 100,
    });
    expect(sumRecords(second)).toBe(1);
    expect(list.items.map((i) => i.name)).toContain("Late snack");
    expect(cache.get(account.userId)?.keyV).toBe(1);
  });

  test("resync_required drops the cache entry", async () => {
    const account = await encryptedAccount();
    const { items } = await withFixture(account);
    const conn = await connect(account);
    await vault(conn).listCategories();
    const before = cache.get(account.userId);
    if (!before) throw new Error("no cache entry");

    // A ghost: a record the server no longer has (its tombstone purged) but the cache still holds.
    const source = await account.web.store.getRaw("transaction", items[0]?.id ?? "");
    const ghostId = randomUUID();
    const sealed = await sealRecord(
      account.keys,
      { userId: account.userId, type: "transaction", id: ghostId, keyV: 1 },
      { ...source?.body, name: "Ghost" },
    );
    cache.set(account.userId, {
      ...before,
      records: new Map([
        ...before.records,
        [
          `transaction:${ghostId}`,
          {
            id: ghostId,
            type: "transaction",
            version: 1,
            deleted: false,
            keyV: 1,
            encV: 1,
            body: toBase64Url(sealed),
          },
        ],
      ]),
    });
    const names = async (fetch?: typeof globalThis.fetch) =>
      (await vault(conn, fetch).listTransactions({ month: "2026-10", limit: 100 })).items.map(
        (i) => i.name,
      );
    expect(await names()).toContain("Ghost"); // the cache is what the store is built from

    let refused = false;
    const resync: Override = (method, path, url) => {
      if (method !== "GET" || path !== "/v2/sync" || refused) return undefined;
      if (url.searchParams.get("since") === "0") return undefined;
      refused = true;
      return Response.json(
        { type: "about:blank", title: "Gone", status: 410, code: "resync_required" },
        { status: 410, headers: { "content-type": "application/problem+json" } },
      );
    };
    expect(await names(network([], "", resync))).not.toContain("Ghost");
    expect(refused).toBe(true);
    const after = cache.get(account.userId);
    expect(after?.records.has(`transaction:${ghostId}`)).toBe(false);
    expect(after?.epoch).not.toBe(before.epoch);
    expect(await names()).not.toContain("Ghost");
  });

  test("a new key version drops the cache entry", async () => {
    const account = await encryptedAccount();
    await withFixture(account);
    const conn = await connect(account);
    await vault(conn).listCategories();
    expect(cache.get(account.userId)?.keyV).toBe(1);

    const { dk2, web } = await rotate(account);
    const again = await connect(account, { keyV: 2, dk: dk2 });
    const calls: Call[] = [];
    await vault(again, network(calls)).listCategories();
    const everything = (await web.store.list("transaction")).length + 2;
    expect(sumRecords(calls)).toBeGreaterThanOrEqual(everything);
    expect(cache.get(account.userId)?.keyV).toBe(2);
  });
});

const sumRecords = (calls: Call[]) => calls.reduce((n, c) => n + (c.records ?? 0), 0);

test("a 404 wrap is the reconnect error", async () => {
  const account = await encryptedAccount();
  const conn = await connect(account, { wrap: false });
  const error = await toolError(vault(conn).listCategories());
  expect(error.code).toBe("reconnect");
  expect(error.message).toBe(
    "This assistant was disconnected from Wambito. Connect it again to keep going.",
  );
});

test("an encrypted account reaching /v1 is the reconnect error", async () => {
  const account = await encryptedAccount();
  const conn = await connect(account);
  // An old connection: the token goes to /v1, which refuses encrypted accounts.
  const error = await toolError(apiWambito(API, conn.token, network()).listCategories());
  expect(error.code).toBe("reconnect");
  expect(error.message).toBe(RECONNECT_MESSAGE);
});

test("nothing logged carries a body, S or a key", async () => {
  const lines: string[] = [];
  for (const level of ["log", "info", "warn", "error", "debug"] as const) {
    vi.spyOn(console, level).mockImplementation((...args: unknown[]) => {
      lines.push(args.map((a) => (typeof a === "string" ? a : JSON.stringify(a))).join(" "));
    });
  }
  const account = await encryptedAccount();
  const { food } = await withFixture(account);
  // A record no key opens: the MCP leaves it out and logs only the count.
  const res = await t.request("POST", "/v2/sync", {
    headers: { ...account.headers, "x-wambito-user": account.userId },
    body: {
      changes: [
        {
          id: randomUUID(),
          type: "transaction",
          baseVersion: null,
          deleted: false,
          keyV: 1,
          encV: 1,
          body: toBase64Url(random(80)),
        },
      ],
    },
  });
  expect(res.status, await res.clone().text()).toBe(200);
  const conn = await connect(account);
  const mcp: Wambito = vault(conn);
  await mcp.listTransactions({ month: "2026-10", limit: 100 });
  await mcp.addTransactions(
    [
      {
        name: "Hidden noodles",
        amount: -1234,
        categoryId: food.id,
        date: "2026-10-21",
        status: "paid",
        source: "app",
      },
    ],
    "logged",
  );
  const failing = await connect(account, { wrap: false });
  await toolError(vault(failing).listCategories());

  const log = lines.join("\n");
  expect(log).toMatch(/1 record\(s\) could not be opened/); // positive control
  for (const secret of [
    conn.S,
    failing.S,
    conn.wk,
    conn.token,
    toBase64Url(account.dk),
    Buffer.from(account.dk).toString("hex"),
    "Hidden noodles",
    "Groceries",
    "Food",
    "1234",
  ]) {
    expect(log).not.toContain(secret);
  }
});

describe("a call the API never answers is the unavailable error, and frees the account", () => {
  test.each([
    ["GET", "/v2/keys/assistant"],
    ["GET", "/v1/me"],
    ["GET", "/v2/sync"],
  ])("%s %s", async (hungMethod, hungPath) => {
    const account = await encryptedAccount();
    await withFixture(account);
    const conn = await connect(account);
    const real = network();
    let hung = 0;
    // Answers nothing and ignores the abort signal: only the MCP's own deadline ends the wait.
    const hanging = (async (input: string | URL | Request, init?: RequestInit) => {
      const request = new Request(input instanceof Request ? input : String(input), init);
      if (request.method === hungMethod && new URL(request.url).pathname === hungPath) {
        hung++;
        return new Promise<Response>(() => {});
      }
      return real(input, init);
    }) as typeof fetch;
    const deps = { apiUrl: API, privateKey, cache, now: () => new Date(NOW), timeoutMs: 50 };
    const stuck = vaultWambito({ ...deps, fetch: hanging }, conn.token, conn.wk);
    const next = vaultWambito({ ...deps, fetch: real }, conn.token, conn.wk);

    // Both on the account's lock: the second waits for the first, which must give up.
    const first = toolError(stuck.listCategories());
    const second = next.listCategories();
    const error = await first;
    expect(hung).toBe(1);
    expect(error.code).toBe("unavailable");
    expect((await second).map((c) => c.name)).toEqual(
      expect.arrayContaining(["Food", "Salary"]),
    );
  });
});

test("a cache entry that cannot be replayed is dropped, so the next call starts over", async () => {
  const account = await encryptedAccount();
  await withFixture(account);
  const conn = await connect(account);
  await vault(conn).listCategories();
  const before = cache.get(account.userId);
  if (!before) throw new Error("no cache entry");
  // A cursor no JSON holds: the replay's own page cannot be built, so the replay fails.
  cache.set(account.userId, { ...before, latest: 1n as unknown as number });

  const error = await toolError(vault(conn).listCategories());
  expect(error.code).toBe("unavailable");
  expect(cache.get(account.userId)).toBeUndefined();
  expect((await vault(conn).listCategories()).length).toBeGreaterThan(0);
});
