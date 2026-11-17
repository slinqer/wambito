import { AsyncLocalStorage } from "node:async_hooks";
import { ToolError, type Wambito } from "@wambito/ai-assistant-tools";
import {
  deriveRecordKeys,
  fromBase64Url,
  openKeyLink,
  type RecordKeys,
  unwrapDataKey,
} from "@wambito/crypto";
import {
  createLocalBackend,
  createMemoryEncryptedStore,
  createSyncEngine,
  type EncryptedStore,
  type Keyring,
  KeysError,
  type SyncEngine,
  type SyncProblem,
  type SyncResult,
} from "@wambito/vault";
import { compactDecrypt, decodeJwt, importJWK } from "jose";
import { apiWambito, type Problem, reconnectError, toToolError } from "./api-wambito.ts";
import type { VaultCache, VaultCacheEntry, WireRecord } from "./vault-cache.ts";

/**
 * The MCP's Wambito for an end-to-end-encrypted account (spec 2026-11-16 §7). Per MCP request, under
 * the account's lock: the `wk` claim gives the assistant secret `S`, `S` opens the assistant's wrap
 * of the data key, the key links open the older versions, an in-memory encrypted store is rebuilt
 * from the account's cached ciphertext and synced once (`/v2/sync` sends only what changed), and
 * the tools run through `apiWambito` over the vault's local backend, as the web's do. A writing
 * tool pushes once more and fails unless every change of its own was acknowledged.
 *
 * `S` and the data keys exist as bytes only while the keys are derived, then are zeroed; the
 * record keys are non-extractable `CryptoKey`s. Nothing logged carries a body, `S` or a key: only
 * codes and counts.
 */

export const NOT_SAVED_MESSAGE =
  "Wambito could not confirm that this change was saved. Part of it may have been saved; trying again is safe and saves nothing twice.";
const UNAVAILABLE_MESSAGE = "Wambito could not be reached right now. Try again in a moment.";

/** How long one API call (keys, profile, a sync page) may take: it runs under the account's lock. */
export const API_TIMEOUT_MS = 20_000;

const unavailable = () => new ToolError("unavailable", UNAVAILABLE_MESSAGE);
const notSaved = () => new ToolError("not_saved", NOT_SAVED_MESSAGE);

/** The vault's own lines: codes and counts only. */
function log(line: string) {
  console.warn(`vault: ${line}`);
}

function logProblem(problem: SyncProblem) {
  if (problem.code === "quarantined") {
    log(`${problem.count ?? 0} record(s) could not be opened and were left out`);
  } else {
    const ids = problem.ids ? ` (${problem.ids.length} record(s))` : "";
    const status = problem.status ? ` ${problem.status}` : "";
    log(`sync ${problem.code}${status}${ids}`);
  }
}

type Method = keyof Wambito;
const READS = [
  "profile",
  "monthSummary",
  "listTransactions",
  "categoryReport",
  "trend",
  "listCategories",
  "listRecurrences",
] as const satisfies readonly Method[];
const WRITES = [
  "addTransactions",
  "updateTransaction",
  "deleteTransactions",
  "restoreTransaction",
  "setBudget",
  "createCategory",
  "updateCategory",
  "createRecurrence",
  "updateRecurrence",
  "deleteRecurrence",
] as const satisfies readonly Method[];
// Every method of `Wambito` is a read or a write: a new one fails to compile until it is listed.
const everyMethod: [Exclude<Method, (typeof READS)[number] | (typeof WRITES)[number]>] extends [
  never,
]
  ? true
  : never = true;
void everyMethod;

type Call = (name: Method, args: unknown[]) => Promise<unknown>;

/** A `Wambito` whose every method goes through `call`. */
function wambitoOf(call: Call): Wambito {
  const out: Record<string, unknown> = {};
  for (const name of [...READS, ...WRITES]) {
    out[name] = (...args: unknown[]) => call(name, args);
  }
  return out as unknown as Wambito;
}

/** Every call is the reconnect error (a `wk` token while this MCP has no private key). */
const disconnectedWambito = () => wambitoOf(() => Promise.reject(reconnectError()));

/** `MCP_WK_PRIVATE_KEY` (a JWK as a JSON string) as the key that opens `wk` claims. */
export async function importWkPrivateKey(json: string | undefined): Promise<CryptoKey | undefined> {
  if (!json) return undefined;
  const key = await importJWK(JSON.parse(json) as Record<string, unknown>, "ECDH-ES");
  if (key instanceof Uint8Array) throw new Error("MCP_WK_PRIVATE_KEY must be an asymmetric JWK");
  return key;
}

/** A `Wambito` whose calls can be bracketed as one MCP request (`app.ts` wraps each tool). */
export interface VaultWambito extends Wambito {
  inRequest<T>(fn: () => Promise<T>): Promise<T>;
}

/** Runs `fn` as one request of `wambito` when it is a vault's, else as is. */
export function inRequest<T>(wambito: Wambito, fn: () => Promise<T>): Promise<T> {
  const scoped = wambito as Partial<VaultWambito>;
  return typeof scoped.inRequest === "function" ? scoped.inRequest(fn) : fn();
}

export interface VaultDeps {
  /** Where the MCP reaches the API (`MCP_API_URL`). */
  apiUrl: string;
  /** Opens the access tokens' `wk` claims (`MCP_WK_PRIVATE_KEY`). */
  privateKey: CryptoKey;
  cache: VaultCache;
  fetch?: typeof fetch;
  now?: () => Date;
  /** Each API call's deadline (default `API_TIMEOUT_MS`); past it the call fails as unavailable. */
  timeoutMs?: number;
}

/** `promise`, or `signal`'s reason once it aborts (even when the fetch ignores the signal). */
function until<T>(promise: Promise<T>, signal: AbortSignal): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const abort = () => reject(signal.reason);
    if (signal.aborted) {
      abort();
      return;
    }
    signal.addEventListener("abort", abort, { once: true });
    promise.then(
      (value) => {
        signal.removeEventListener("abort", abort);
        resolve(value);
      },
      (error: unknown) => {
        signal.removeEventListener("abort", abort);
        reject(error);
      },
    );
  });
}

/**
 * `deps.wambitoFor(token, wk)`: a token with a `wk` claim takes the encrypted path, one without it
 * today's `/v1` path. Without a private key, a `wk` token gets the reconnect error.
 */
export function createWambitoFor(
  deps: Omit<VaultDeps, "privateKey"> & { privateKey?: CryptoKey },
): (token: string, wk: string | undefined) => Wambito {
  return (token, wk) => {
    if (wk === undefined) return apiWambito(deps.apiUrl, token, deps.fetch);
    const { privateKey } = deps;
    if (!privateKey) return disconnectedWambito();
    return vaultWambito({ ...deps, privateKey }, token, wk);
  };
}

interface AssistantKeys {
  wrap: { keyV: number; wrapped: string };
  links: { keyV: number; link: string }[];
}

/** One MCP request's open vault: the store, its sync, and the tools' way in. */
interface Session {
  keyV: number;
  store: EncryptedStore;
  engine: SyncEngine;
  api: Wambito;
  /** The cache entry this session was built from (or last wrote back). */
  base: VaultCacheEntry | undefined;
  epoch: number;
  /** What `/v2/sync` sent since `base`, by `type:id`. */
  pulled: Map<string, WireRecord>;
  /** A `410 resync_required` emptied the store: `pulled` is the whole account. */
  resynced: boolean;
}

let epochs = 0;
const nextEpoch = () => ++epochs;
const recordKey = (r: { type: string; id: string }) => `${r.type}:${r.id}`;

/** Keeps the newest copy of each record. */
function keep(into: Map<string, WireRecord>, record: WireRecord) {
  const key = recordKey(record);
  const held = into.get(key);
  if (!held || held.version < record.version) into.set(key, record);
}

/** `S` from the `wk` claim: a JWE to the MCP's key whose plaintext is `S` in base64url. */
async function secretOf(wk: string, privateKey: CryptoKey): Promise<Uint8Array> {
  let plaintext: Uint8Array;
  try {
    ({ plaintext } = await compactDecrypt(wk, privateKey, {
      keyManagementAlgorithms: ["ECDH-ES"],
      contentEncryptionAlgorithms: ["A256GCM"],
    }));
  } catch {
    throw reconnectError();
  }
  try {
    const text = new TextDecoder().decode(plaintext);
    const secret = text.length === 43 ? fromBase64Url(text) : undefined;
    if (!secret || secret.length !== 32) throw reconnectError();
    return secret;
  } catch {
    throw reconnectError();
  } finally {
    plaintext.fill(0);
  }
}

/**
 * The record keys of the wrap's version and, through the key links (each holds the previous data
 * key sealed under the next one), of every older version they reach. `S` opens the wrap; every
 * data key is zeroed once its record keys exist.
 */
async function openKeyring(
  userId: string,
  secret: Uint8Array,
  { wrap, links }: AssistantKeys,
): Promise<Keyring> {
  let dataKey: Uint8Array;
  try {
    dataKey = await unwrapDataKey(
      secret,
      { kind: "assistant", userId, keyV: wrap.keyV },
      fromBase64Url(wrap.wrapped),
    );
  } catch {
    throw reconnectError();
  }
  const byVersion = new Map<number, RecordKeys>();
  const linkOf = new Map(links.map((l) => [l.keyV, l.link]));
  let key = dataKey;
  try {
    byVersion.set(wrap.keyV, await deriveRecordKeys(dataKey));
    for (let v = wrap.keyV; v >= 2; v--) {
      const link = linkOf.get(v);
      if (!link) break;
      let older: Uint8Array;
      try {
        older = await openKeyLink(key, { userId, keyV: v }, fromBase64Url(link));
      } catch {
        break; // records under older versions stay unopened (left out, counted)
      }
      if (key !== dataKey) key.fill(0);
      key = older;
      byVersion.set(v - 1, await deriveRecordKeys(older));
    }
  } finally {
    key.fill(0);
    dataKey.fill(0);
  }
  return { current: wrap.keyV, byVersion };
}

/** Fills a fresh store from the cached ciphertext, opened and checked exactly as a pull does. */
async function replay(
  store: EncryptedStore,
  entry: VaultCacheEntry,
  userId: string,
  keyring: Keyring,
): Promise<void> {
  const records = [...entry.records.values()].filter((r) => !r.deleted);
  const engine = createSyncEngine({
    store,
    userId,
    keyring,
    refreshKeys: async () => keyring,
    upgrade: false,
    baseUrl: "",
    fetch: async () => Response.json({ records, next: null, latest: entry.latest }),
    onError: logProblem,
  });
  const result = await engine.run();
  if (!result.ok) throw unavailable();
}

/**
 * The person's Wambito for an encrypted account, for one MCP request (see the file's comment).
 * `token` is the assistant's access token, `wk` its claim.
 */
export function vaultWambito(deps: VaultDeps, token: string, wk: string): VaultWambito {
  const apiUrl = deps.apiUrl.replace(/\/+$/, "");
  const network = deps.fetch ?? fetch;
  const now = deps.now ?? (() => new Date());
  const timeoutMs = deps.timeoutMs ?? API_TIMEOUT_MS;
  const { cache } = deps;
  let userId: string | undefined;
  try {
    const sub = decodeJwt(token).sub;
    if (typeof sub === "string") userId = sub;
  } catch {
    // reconnect below
  }

  /**
   * A call to the API with the assistant's token, as the account it is for. It runs under the
   * account's lock, so it has a deadline: past it the call rejects (the tool error is unavailable).
   */
  function callApi(user: string, input: string, init?: RequestInit): Promise<Response> {
    const headers = new Headers(init?.headers);
    headers.set("authorization", `Bearer ${token}`);
    headers.set("x-wambito-user", user);
    const deadline = AbortSignal.timeout(timeoutMs);
    const signal = init?.signal ? AbortSignal.any([init.signal, deadline]) : deadline;
    return until(network(input, { ...init, headers, signal }), signal);
  }

  async function getJson<T>(user: string, path: string): Promise<T> {
    let res: Response;
    try {
      res = await callApi(user, `${apiUrl}${path}`);
    } catch {
      throw unavailable();
    }
    if (res.status === 404 && path === "/v2/keys/assistant") throw reconnectError();
    if (!res.ok) {
      const problem = (await res.json().catch(() => undefined)) as Problem | undefined;
      throw toToolError(res.status, problem);
    }
    return (await res.json()) as T;
  }

  /** A run that stopped before the tool could trust the store. */
  function failed(result: SyncResult): ToolError {
    if (result.error === "unauthorized" || result.problem === "device_removed") {
      return reconnectError();
    }
    return unavailable();
  }

  async function prepare(user: string): Promise<Session> {
    const secret = await secretOf(wk, deps.privateKey);
    let keyring: Keyring;
    let me: { email: string; isAnonymous: boolean };
    try {
      const [keys, profile] = await Promise.all([
        getJson<AssistantKeys>(user, "/v2/keys/assistant"),
        getJson<{ email: string; isAnonymous: boolean }>(user, "/v1/me"),
      ]);
      me = profile;
      keyring = await openKeyring(user, secret, keys);
    } finally {
      secret.fill(0);
    }

    let entry = cache.get(user);
    if (entry && entry.keyV !== keyring.current) {
      cache.drop(user);
      entry = undefined;
    }
    const store = createMemoryEncryptedStore(user);
    if (entry) {
      try {
        await replay(store, entry, user, keyring);
      } catch (error) {
        // A broken entry would fail every call until it expires: the next one starts over.
        cache.drop(user);
        store.close();
        throw error;
      }
    }

    const session = {
      keyV: keyring.current,
      store,
      base: entry,
      epoch: entry?.epoch ?? nextEpoch(),
      pulled: new Map<string, WireRecord>(),
      resynced: false,
    } as Session;

    /** The sync's network: the token, and a copy of every record `/v2/sync` sends. */
    const syncFetch = (async (input: string | URL | Request, init?: RequestInit) => {
      const url = String(input);
      const res = await callApi(user, url, init);
      const method = (init?.method ?? "GET").toUpperCase();
      if (method === "GET" && new URL(url).pathname.endsWith("/v2/sync")) {
        if (res.status === 410) {
          // The server purged what the cache may still hold: the entry goes, the pull starts over.
          cache.drop(user);
          session.pulled.clear();
          session.resynced = true;
        } else if (res.ok) {
          const page = (await res.clone().json()) as { records: WireRecord[] };
          for (const record of page.records) keep(session.pulled, record);
        }
      }
      return res;
    }) as typeof fetch;

    session.engine = createSyncEngine({
      store,
      fetch: syncFetch,
      baseUrl: apiUrl,
      userId: user,
      keyring,
      // A newer key version means the account rotated, which deletes this assistant's wrap.
      refreshKeys: async () => {
        const res = await callApi(user, `${apiUrl}/v2/keys/assistant`).catch(() => undefined);
        if (res?.status === 404 || res?.status === 401) throw new KeysError("device_removed");
        if (!res?.ok) throw new KeysError("server");
        return keyring;
      },
      upgrade: false,
      now: () => now().getTime(),
      onError: logProblem,
    });
    const first = await session.engine.run();
    if (!first.ok) throw failed(first);

    const backend = createLocalBackend({
      store,
      now,
      profile: { id: user, email: me.email, isAnonymous: me.isAnonymous, encryption: "preview" },
      source: "mcp",
      idsFromIdempotencyKey: { userId: user },
    });
    session.api = apiWambito(apiUrl, token, backend.fetch);
    return session;
  }

  /** Stores what this session pulled back into the cache, unless a newer lineage took over. */
  async function writeBack(user: string, session: Session) {
    const latest = (await session.store.getMeta<number>("latest")) ?? 0;
    const current = cache.get(user);
    let from: VaultCacheEntry | undefined;
    let epoch = session.epoch;
    if (session.resynced) {
      epoch = nextEpoch();
    } else if (current && current.epoch === session.epoch && current.keyV === session.keyV) {
      from = current;
    } else if (!current) {
      from = session.base;
    } else {
      return;
    }
    const records = new Map(from?.records);
    for (const record of session.pulled.values()) keep(records, record);
    const entry: VaultCacheEntry = {
      keyV: session.keyV,
      latest: Math.max(from?.latest ?? 0, latest),
      records,
      epoch,
    };
    cache.set(user, entry);
    session.base = entry;
    session.epoch = epoch;
    session.pulled = new Map();
    session.resynced = false;
  }

  let opened: Promise<Session> | undefined;
  /**
   * Set inside `inRequest`, for the async calls it makes: a method called there is part of the
   * request; one called anywhere else (another tool of the same MCP request) waits for the lock.
   */
  const bracket = new AsyncLocalStorage<true>();

  /**
   * One MCP request (one tool call, all its methods): under the account's lock, so two requests
   * never interleave (a check-then-act tool decides on the store it then writes to). The vault
   * opens on the first method and is dropped (store closed, keys released) when `fn` ends.
   */
  async function inRequest<T>(fn: () => Promise<T>): Promise<T> {
    if (bracket.getStore()) return fn();
    const user = userId;
    if (!user) throw reconnectError();
    return cache.lock(user, async () => {
      try {
        return await bracket.run(true, fn);
      } finally {
        const session = opened;
        opened = undefined;
        await session?.then(
          (s) => s.store.close(),
          () => undefined,
        );
      }
    });
  }

  /** Stores what was pulled, but a failed cache write is never what the tool reports. */
  async function keepPulled(user: string, session: Session) {
    try {
      await writeBack(user, session);
    } catch {
      log("the cache could not be written");
    }
  }

  async function call(name: Method, args: unknown[], write: boolean): Promise<unknown> {
    // A method called outside a request bracket is a request of its own.
    if (!bracket.getStore()) return inRequest(() => call(name, args, write));
    const user = userId;
    if (!user) throw reconnectError();
    opened ??= prepare(user);
    let session: Session;
    try {
      session = await opened;
    } catch (error) {
      opened = undefined;
      throw error;
    }
    try {
      const method = session.api[name] as (...a: unknown[]) => Promise<unknown>;
      const answer = await method(...args);
      if (write) {
        const pushed = await session.engine.run();
        const pending = await session.store.readOutbox(Number.MAX_SAFE_INTEGER);
        if (
          !pushed.ok ||
          pushed.parked.length > 0 ||
          pushed.dropped.length > 0 ||
          pending.length > 0
        ) {
          // Nothing is kept to retry later: the next call starts from the server's copy.
          opened = undefined;
          session.store.close();
          throw notSaved();
        }
      }
      return answer;
    } finally {
      await keepPulled(user, session);
    }
  }

  return {
    ...wambitoOf((name, args) => call(name, args, (WRITES as readonly string[]).includes(name))),
    inRequest,
  };
}
