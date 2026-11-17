import { randomUUID } from "node:crypto";
import type { Wambito } from "@wambito/ai-assistant-tools";
import {
  deriveRecordKeys,
  fromBase64Url,
  generateDataKey,
  type RecordKeys,
  sealKeyLink,
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
import { decodeJwt } from "jose";
import { expect } from "vitest";
import { newAssistantSecret, type TestApp } from "../../../api/test/harness.ts";
import { apiWambito } from "../../src/api-wambito.ts";

// What the vault tests share: the person's side of an encrypted account (a memory vault with a
// sync engine and a local backend over the real API), an assistant connected to it, and rotation.

export const NOW = new Date("2026-10-21T18:00:00Z");

/** One request the MCP (or the web) made. */
export interface Call {
  tag: string;
  method: string;
  path: string;
  body?: string;
  /** Records in a `GET /v2/sync` answer. */
  records?: number;
}

export type Override = (method: string, path: string, url: URL) => Response | undefined;

export const random = (n: number) => globalThis.crypto.getRandomValues(new Uint8Array(n));

/** The helpers over the API test app that `getApp` returns (read lazily: the app starts in a hook). */
export function encryptedSupport(getApp: () => TestApp) {
  let ip = 0;
  let people = 0;
  const nextPerson = () => ++people;
  const API = () => getApp().config.API_URL;
  const t = new Proxy({} as TestApp, { get: (_, key) => Reflect.get(getApp(), key) });

  /** The API over `t.app`, recording every call; `override` may answer instead of the API. */
  function network(calls: Call[] = [], tag = "", override?: Override): typeof fetch {
    return (async (input: string | URL | Request, init?: RequestInit) => {
      const request = new Request(input instanceof Request ? input : String(input), init);
      const url = new URL(request.url);
      const body = request.method === "GET" ? undefined : await request.clone().text();
      const call: Call = { tag, method: request.method, path: url.pathname, body };
      calls.push(call);
      const answer = override?.(request.method, url.pathname, url);
      if (answer) return answer;
      const headers = new Headers(request.headers);
      headers.set("x-forwarded-for", `203.0.${Math.floor(++ip / 250)}.${ip % 250}, 10.0.0.1`);
      const res = await t.app.request(url.pathname + url.search, {
        method: request.method,
        headers,
        ...(body === undefined ? {} : { body }),
      });
      if (request.method === "GET" && url.pathname === "/v2/sync" && res.ok) {
        call.records = ((await res.clone().json()) as { records: unknown[] }).records.length;
      }
      return res;
    }) as typeof fetch;
  }

  /** The web's own calls, with its session. */
  function sessionFetch(session: { authorization: string }): typeof fetch {
    const net = network([], "web");
    return (async (input: string | URL | Request, init?: RequestInit) => {
      const headers = new Headers(init?.headers);
      headers.set("authorization", session.authorization);
      return net(String(input), { ...init, headers });
    }) as typeof fetch;
  }

  /** The person's browser: a vault over the API with their session. */
  async function webSide(
    account: { userId: string; email: string; headers: { authorization: string } },
    keyring: Keyring,
  ) {
    const store = createMemoryEncryptedStore(account.userId);
    const engine = createSyncEngine({
      store,
      fetch: sessionFetch(account.headers),
      baseUrl: API(),
      userId: account.userId,
      keyring,
      refreshKeys: async () => keyring,
      upgrade: false,
    });
    const wambito = apiWambito(API(), "web", localFetch(store, account));
    async function sync() {
      const result = await engine.run();
      expect(result.ok).toBe(true);
      expect(result.parked).toEqual([]);
    }
    return { store, wambito, sync, keyring };
  }

  /** The web's local backend over a store: the reference the MCP's answers must equal. */
  function localFetch(store: EncryptedStore, account: { userId: string; email: string }) {
    return createLocalBackend({
      store,
      now: () => new Date(NOW),
      profile: {
        id: account.userId,
        email: account.email,
        isAnonymous: false,
        encryption: "preview",
      },
    }).fetch;
  }

  async function putWrap(headers: { authorization: string }, body: Record<string, unknown>) {
    const res = await t.request("PUT", `/v2/keys/${randomUUID()}`, { headers, body });
    expect(res.status, await res.clone().text()).toBe(200);
  }

  /** An account in the encryption preview, with a data key (version 1) and a web vault. */
  async function encryptedAccount() {
    const email = `vault-${nextPerson()}@wambito.test`;
    const { userId, headers } = await t.signIn(email);
    t.config.E2E_PREVIEW_USER_IDS.push(userId);
    const dk = generateDataKey();
    await putWrap(headers, {
      kind: "recovery",
      ref: null,
      keyV: 1,
      wrapped: toBase64Url(random(48)),
    });
    const keys = await deriveRecordKeys(dk);
    const account = { email, userId, headers, dk, keys };
    const web = await webSide(account, { current: 1, byVersion: new Map([[1, keys]]) });
    return { ...account, web };
  }

  /** Connects an assistant with `S` and, as the web's consent page does, stores its wrap. */
  async function connect(
    account: Account,
    {
      keyV = 1,
      dk = account.dk,
      wrap = true,
    }: { keyV?: number; dk?: Uint8Array; wrap?: boolean } = {},
  ) {
    const S = newAssistantSecret();
    const tokens = await t.connectAssistant(account.email, { headers: account.headers, wk: S });
    if (wrap) {
      const ctx = { kind: "assistant" as const, userId: account.userId, keyV };
      const wrapped = await wrapDataKey(fromBase64Url(S), ctx, dk);
      await putWrap(account.headers, {
        kind: "assistant",
        ref: tokens.clientId,
        keyV,
        wrapped: toBase64Url(wrapped),
      });
    }
    const wk = decodeJwt(tokens.accessToken).wk;
    if (typeof wk !== "string") throw new Error("the token has no wk");
    return { S, token: tokens.accessToken, wk };
  }

  /** Two categories and a few movements over September and October, pushed sealed. */
  async function withFixture(account: Account) {
    const food = await account.web.wambito.createCategory({
      name: "Food",
      kind: "expense",
      icon: "fork",
      color: "#f90",
    });
    const salary = await account.web.wambito.createCategory({
      name: "Salary",
      kind: "income",
      icon: "cash",
      color: "#0a0",
    });
    const tx = (name: string, amount: number, categoryId: string, date: string) => ({
      name,
      amount,
      categoryId,
      date,
      status: "paid" as const,
      source: "app" as const,
    });
    const { items } = await account.web.wambito.addTransactions(
      [
        tx("Groceries", -4500, food.id, "2026-10-03"),
        tx("Dinner", -3200, food.id, "2026-10-12"),
        tx("Pay", 250000, salary.id, "2026-10-01"),
        tx("Bakery", -900, food.id, "2026-09-20"),
      ],
      "fixture",
    );
    await account.web.sync();
    return { food, salary, items };
  }

  /** The next key version: the web rotates (no re-seal), then works under it. */
  async function rotate(account: Account) {
    const dk2 = generateDataKey();
    const link = await sealKeyLink(dk2, account.dk, { userId: account.userId, keyV: 2 });
    const res = await t.request("POST", "/v2/keys/rotate", {
      headers: account.headers,
      body: {
        keyV: 2,
        wraps: [
          {
            id: randomUUID(),
            kind: "recovery",
            ref: null,
            keyV: 2,
            wrapped: toBase64Url(random(48)),
          },
        ],
        link: toBase64Url(link),
      },
    });
    expect(res.status, await res.clone().text()).toBe(200);
    const keys2 = await deriveRecordKeys(dk2);
    const web = await webSide(account, {
      current: 2,
      byVersion: new Map<number, RecordKeys>([
        [1, account.keys],
        [2, keys2],
      ]),
    });
    await web.sync();
    return { dk2, web };
  }

  return {
    network,
    sessionFetch,
    webSide,
    localFetch,
    putWrap,
    encryptedAccount,
    connect,
    withFixture,
    rotate,
    nextPerson,
  };
}

export type Support = ReturnType<typeof encryptedSupport>;
export interface Account {
  email: string;
  userId: string;
  headers: { authorization: string };
  dk: Uint8Array;
  keys: RecordKeys;
  web: {
    store: EncryptedStore;
    wambito: Wambito;
    sync(): Promise<void>;
    keyring: Keyring;
  };
}
