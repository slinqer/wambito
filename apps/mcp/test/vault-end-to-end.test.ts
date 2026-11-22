import { Client, StreamableHTTPClientTransport } from "@modelcontextprotocol/client";
import { fromBase64Url, toBase64Url, wrapDataKey } from "@wambito/crypto";
import { createLocalJWKSet, decodeJwt, type JSONWebKeySet } from "jose";
import { afterAll, beforeAll, expect, test } from "vitest";
import { createTestApp, newAssistantSecret, type TestApp } from "../../api/test/harness.ts";
import { RECONNECT_MESSAGE } from "../src/api-wambito.ts";
import { createMcpApp } from "../src/app.ts";
import { createVaultCache } from "../src/vault-cache.ts";
import { createWambitoFor } from "../src/vault-wambito.ts";
import { jwtVerifier } from "../src/verifier.ts";
import { encryptedSupport, NOW } from "./support/encrypted-account.ts";

// An assistant on an encrypted account, end to end (spec 2026-11-16 §7, §10): the real API and its
// database, the OAuth flow with `wk`, the MCP's own token check, the vault path, and the SDK's
// client. The "web" side is a vault of its own that seals the person's records and makes the
// assistant's wrap, as the browser does.

let t: TestApp;
let mcp: ReturnType<typeof createMcpApp>;
const support = encryptedSupport(() => t);
const { encryptedAccount, withFixture, rotate, putWrap } = support;
type Account = Awaited<ReturnType<typeof encryptedAccount>>;

beforeAll(async () => {
  t = await createTestApp();
  const API = t.config.API_URL;
  const jwks = (await (await t.app.request("/auth/jwks")).json()) as JSONWebKeySet;
  const config = {
    MCP_URL: t.config.MCP_URL ?? "",
    AUTH_ISSUER: `${API}/auth`,
    MCP_API_URL: API,
    RATE_LIMIT_PER_MINUTE: 1000,
  };
  mcp = createMcpApp({
    config,
    verifier: jwtVerifier(config, createLocalJWKSet(jwks)),
    wambitoFor: createWambitoFor({
      apiUrl: API,
      privateKey: t.wkPrivateKey as CryptoKey,
      cache: createVaultCache({ maxAccounts: 50, maxBytes: 50_000_000, idleMs: 30 * 60_000 }),
      fetch: support.network(),
      now: () => new Date(NOW),
    }),
    now: () => new Date(NOW),
  });
});
afterAll(() => t?.stop());

async function client(token: string) {
  const c = new Client(
    { name: "e2e", version: "1.0.0" },
    { versionNegotiation: { mode: { pin: "2026-07-28" } } },
  );
  await c.connect(
    new StreamableHTTPClientTransport(new URL(t.config.MCP_URL ?? ""), {
      fetch: (async (url: string | URL, init?: RequestInit) =>
        mcp.request(String(url), init)) as typeof fetch,
      requestInit: { headers: { authorization: `Bearer ${token}` } },
    }),
  );
  return c;
}

type Json = Record<string, any>;

/** A tool call that must succeed: its structured answer. */
async function ok(c: Client, name: string, args: Record<string, unknown> = {}): Promise<Json> {
  const result = await c.callTool({ name, arguments: args });
  expect(result.isError, JSON.stringify(result.content)).toBeFalsy();
  return result.structuredContent as Json;
}

/** A tool call that must fail: the code and message the model reads. */
async function failure(c: Client, name: string, args: Record<string, unknown> = {}) {
  const result = await c.callTool({ name, arguments: args });
  expect(result.isError).toBe(true);
  const text = (result.content as { text: string }[])[0]?.text ?? "";
  return { text, structured: result.structuredContent as Json | undefined };
}

/** Connects an assistant (consent with `wk`, the code exchange) and PUTs its wrap, as the web does. */
async function connectAssistant(account: Account, scope?: string) {
  const S = newAssistantSecret();
  const tokens = await t.connectAssistant(account.email, {
    headers: account.headers,
    wk: S,
    ...(scope ? { scope } : {}),
  });
  await wrap(account, tokens.clientId, S);
  return { ...tokens, S, token: tokens.accessToken };
}

async function wrap(account: Account, clientId: string, S: string) {
  const ctx = { kind: "assistant" as const, userId: account.userId, keyV: 1 };
  const wrapped = await wrapDataKey(fromBase64Url(S), ctx, account.dk);
  await putWrap(account.headers, {
    kind: "assistant",
    ref: clientId,
    keyV: 1,
    wrapped: toBase64Url(wrapped),
  });
}

const revoke = (account: Account, clientId: string) =>
  t.request("DELETE", `/v1/me/assistants/${clientId}`, { headers: account.headers });

const RECONNECT = `reconnect: ${RECONNECT_MESSAGE}`;
const WORDS = ["panaderia-e2e", "almuerzo-e2e"];
const secrets: string[] = [];

test("an assistant uses all 14 tools on an encrypted account, and the person sees the result", async () => {
  const account = await encryptedAccount();
  const { food, items } = await withFixture(account);
  const conn = await connectAssistant(account);
  secrets.push(conn.S);
  const c = await client(conn.token);
  expect((await c.listTools()).tools.map((x) => x.name).sort()).toHaveLength(14);

  // The read tools: the fixture's figures (October: 4500 + 3200 spent, 250000 in; September: 900).
  const categories = await ok(c, "list_categories");
  expect(categories.items.map((i: Json) => i.name).sort()).toEqual(["Food", "Salary"]);
  const overview = await ok(c, "get_month_overview", { month: "2026-10" });
  expect(overview.spent.amount).toBe(77);
  expect(overview.income.amount).toBe(2500);
  const list = await ok(c, "list_transactions", { month: "2026-10" });
  expect(list.items.map((i: Json) => i.name).sort()).toEqual(["Dinner", "Groceries", "Pay"]);
  const byCategory = await ok(c, "spending_by_category", { from: "2026-09", to: "2026-10" });
  expect(byCategory.total.amount).toBe(86);
  const trend = await ok(c, "spending_trend", { from: "2026-09", to: "2026-10" });
  expect(trend.months.map((m: Json) => [m.month, m.expenses.amount])).toEqual([
    ["2026-09", 9],
    ["2026-10", 77],
  ]);
  expect((await ok(c, "list_recurring")).items).toEqual([]);

  // The write tools, each then read back.
  await ok(c, "create_category", { name: "almuerzo-e2e", kind: "expense" });
  await ok(c, "update_category", { category: "almuerzo-e2e", icon: "🍽" });
  await ok(c, "set_budget", { category: "almuerzo-e2e", amount: 500, effectiveFrom: "2026-10" });
  const added = await ok(c, "add_transactions", {
    items: [
      { name: "panaderia-e2e", amount: 12.5, category: "food", date: "2026-10-18", note: "pan" },
    ],
  });
  expect(added.saved).toBe(1);
  const seen = await ok(c, "list_transactions", { month: "2026-10", text: "panaderia-e2e" });
  expect(seen.items).toEqual([
    expect.objectContaining({ name: "panaderia-e2e", amount: 12.5, kind: "expense" }),
  ]);
  const id = seen.items[0].id as string;
  await ok(c, "update_transaction", { id, amount: 13, name: "panaderia-e2e" });
  expect(
    (await ok(c, "list_transactions", { month: "2026-10", text: "panaderia-e2e" })).items[0].amount,
  ).toBe(13);
  await ok(c, "delete_transactions", { ids: [id] });
  expect(
    (await ok(c, "list_transactions", { month: "2026-10", text: "panaderia-e2e" })).items,
  ).toEqual([]);
  // A deletion carries its sealed body to the server, so a later request restores it.
  await ok(c, "restore_transactions", { ids: [id] });
  const restored = await ok(c, "list_transactions", { month: "2026-10", text: "panaderia-e2e" });
  expect(restored.items).toEqual([expect.objectContaining({ id, amount: 13 })]);
  const rule = await ok(c, "manage_recurring", {
    action: "create",
    name: "almuerzo-e2e",
    amount: 20,
    category: "food",
    startDate: "2026-10-05",
  });
  expect((await ok(c, "list_recurring")).items).toHaveLength(1);
  await ok(c, "manage_recurring", { action: "stop", id: rule.recurrence.id });
  const overview2 = await ok(c, "get_month_overview", { month: "2026-10" });
  expect(overview2.budgets.map((b: Json) => b.category)).toContain("almuerzo-e2e");
  await ok(c, "add_transactions", {
    items: [{ name: "almuerzo-e2e", amount: 25, category: "food", date: "2026-10-19" }],
  });
  await c.close();

  // The person's own vault pulls what the assistant wrote: sealed with source mcp inside.
  await account.web.sync();
  const mine = (await account.web.store.list("transaction")).map(
    (r) => r.body as { name: string; source: string; amount: number },
  );
  expect(mine).toContainEqual(
    expect.objectContaining({ name: "almuerzo-e2e", source: "mcp", amount: -2500 }),
  );
  expect(items).toHaveLength(4);
  expect(food.id).toBeTruthy();
});

test("revoked while the access token is still valid: the next tool call is the reconnect error", async () => {
  const account = await encryptedAccount();
  await withFixture(account);
  const conn = await connectAssistant(account);
  secrets.push(conn.S);
  const c = await client(conn.token);
  await ok(c, "list_categories");
  expect(decodeJwt(conn.token).exp ?? 0).toBeGreaterThan(Date.now() / 1000);

  expect((await revoke(account, conn.clientId)).status).toBe(204);
  const refused = await failure(c, "list_categories");
  expect(refused.text).toBe(RECONNECT);
  expect((await failure(c, "get_month_overview", { month: "2026-10" })).text).toBe(RECONNECT);
  expect(
    (
      await failure(c, "add_transactions", {
        items: [{ name: "panaderia-e2e", amount: 1, category: "food" }],
      })
    ).text,
  ).toBe(RECONNECT);
  await c.close();
});

test("after the web rotates the keys the assistant must reconnect, and a new connection works", async () => {
  const account = await encryptedAccount();
  await withFixture(account);
  const conn = await connectAssistant(account);
  secrets.push(conn.S);
  const c = await client(conn.token);
  await ok(c, "list_categories");

  const { dk2 } = await rotate(account);
  expect((await failure(c, "list_categories")).text).toBe(RECONNECT);
  await c.close();

  // A new connection wraps the new key.
  const S = newAssistantSecret();
  secrets.push(S);
  const tokens = await t.connectAssistant(account.email, { headers: account.headers, wk: S });
  const ctx = { kind: "assistant" as const, userId: account.userId, keyV: 2 };
  await putWrap(account.headers, {
    kind: "assistant",
    ref: tokens.clientId,
    keyV: 2,
    wrapped: toBase64Url(await wrapDataKey(fromBase64Url(S), ctx, dk2)),
  });
  const again = await client(tokens.accessToken);
  const list = await ok(again, "list_transactions", { month: "2026-10" });
  expect(list.items).toHaveLength(3);
  await again.close();
});

test("a second consent with the same signed query, after a revoke, gets a fresh code that works", async () => {
  const account = await encryptedAccount();
  await withFixture(account);
  const clientId = await t.registerAssistant();
  const { res, verifier } = await t.authorizeRequest(clientId, account.headers);
  const oauthQuery = new URL(res.headers.get("location") ?? "").search.slice(1);
  const consent = async (S: string) => {
    const r = await t.request("POST", "/auth/oauth2/consent", {
      headers: account.headers,
      body: { accept: true, oauth_query: oauthQuery, wk: S },
    });
    expect(r.status, await r.clone().text()).toBe(200);
    const back = new URL(((await r.json()) as { url: string }).url);
    return back.searchParams.get("code") ?? "";
  };
  const S1 = newAssistantSecret();
  const code1 = await consent(S1);
  expect(code1).not.toBe("");
  // The web's "Try again": the wrap failed, so the client is removed and consent is asked again.
  expect((await revoke(account, clientId)).status).toBe(204);
  const S2 = newAssistantSecret();
  secrets.push(S1, S2);
  const code2 = await consent(S2);
  expect(code2).not.toBe("");
  expect(code2).not.toBe(code1);

  const exchange = await t.exchangeCode({
    code: code2,
    verifier,
    clientId,
    clientSecret: undefined,
    resource: t.config.MCP_URL ?? "",
  });
  expect(exchange.status, await exchange.clone().text()).toBe(200);
  const tokens = (await exchange.json()) as { access_token: string };
  await wrap(account, clientId, S2);
  const c = await client(tokens.access_token);
  expect((await ok(c, "list_transactions", { month: "2026-10" })).items).toHaveLength(3);
  await c.close();
});

test("a grant with only finance:write gets a clear tool error on an encrypted account", async () => {
  const account = await encryptedAccount();
  await withFixture(account);
  const conn = await connectAssistant(account, "finance:write offline_access");
  secrets.push(conn.S);
  expect(decodeJwt(conn.token).scope).toBe("finance:write offline_access");
  const c = await client(conn.token);
  // A read tool: the MCP asks for the missing scope before touching the vault.
  await expect(c.callTool({ name: "list_categories", arguments: {} })).rejects.toThrow(
    /Insufficient scope/,
  );
  // A write tool reaches the vault, which cannot pull without finance:read.
  const write = await failure(c, "add_transactions", {
    items: [{ name: "panaderia-e2e", amount: 1, category: "food" }],
  });
  expect(write.text).toMatch(/cannot do that/i);
  await c.close();
  // Nothing was saved.
  await account.web.sync();
  expect(
    (await account.web.store.list("transaction")).some(
      (r) => (r.body as { name: string }).name === "panaderia-e2e",
    ),
  ).toBe(false);
});

// Relies on the tests above having filled `secrets` (it is asserted, so a lone run fails loudly).
test("a scan of every table finds none of the run's words nor an assistant secret", async () => {
  expect(secrets.length).toBeGreaterThan(3);
  const found = await t.tablesHolding([
    ...WORDS,
    "Groceries",
    "Dinner",
    "Bakery",
    ...secrets,
    // S stored raw in a bytea column would read as hex.
    ...secrets.map((S) => fromBase64Url(S)),
  ]);
  expect(found).toEqual([]);
});

test("the scan reads text and bytea columns", async () => {
  // text: an email is there in plain text
  expect((await t.tablesHolding(["@wambito.test"])).length).toBeGreaterThan(0);
  // bytea: a wrap whose bytes are a known string (48 bytes, as the API takes them) is found
  const { userId, headers } = await t.signIn("bytea-control@wambito.test");
  t.config.E2E_PREVIEW_USER_IDS.push(userId);
  const control = "bytea-control-e2e";
  const bytes = new Uint8Array(48);
  bytes.set(new TextEncoder().encode(control));
  await putWrap(headers, { kind: "recovery", ref: null, keyV: 1, wrapped: toBase64Url(bytes) });
  expect((await t.tablesHolding([control])).length).toBeGreaterThan(0);
});
