import "fake-indexeddb/auto";
import {
  fromBase64Url,
  generateDataKey,
  generateDeviceKeyPair,
  pairingCommitment,
  pairingNumber,
  sealToDevice,
  toBase64Url,
} from "@wambito/crypto";
import { describe, expect, it, vi } from "vitest";

/** What the crypto handed out, to check zeroing; `nobleNext` makes the next key pair raw bytes. */
const handed = vi.hoisted(() => ({
  openedPairing: [] as Uint8Array[],
  nobleNext: false,
  noble: [] as Uint8Array[],
}));
vi.mock("@wambito/crypto", async (original) => {
  const crypto = await original<typeof import("@wambito/crypto")>();
  return {
    ...crypto,
    openFromPairing: async (...args: Parameters<typeof crypto.openFromPairing>) => {
      const out = await crypto.openFromPairing(...args);
      handed.openedPairing.push(out);
      return out;
    },
    generateDeviceKeyPair: async () => {
      const pair = await crypto.generateDeviceKeyPair();
      if (!handed.nobleNext) return pair;
      handed.nobleNext = false;
      // the noble fallback's shape: raw private bytes this module must zero
      const raw = new Uint8Array(32).fill(9);
      handed.noble.push(raw);
      return { publicKey: pair.publicKey, privateKey: { kind: "noble-x25519" as const, raw } };
    },
  };
});

import { vaultName } from "./db.ts";
import { createEncryptedStore } from "./encrypted-store.ts";
import { enrollDevice } from "./keys.ts";
import {
  SIGNIN_POLL_MS,
  SIGNIN_TTL_MS,
  SigninError,
  type SigninErrorCode,
  startSignin,
} from "./signin.ts";

const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
const problem = (status: number, code: string, headers: Record<string, string> = {}) =>
  json({ code }, status, headers);

interface Row {
  id: string;
  code: string;
  pollSecret: string;
  commitment: string;
  remember: boolean;
  label: string;
  approverKey: string | null;
  userId: string | null;
  publicKey: string | null;
  sealed: string | null;
  keyV: number | null;
  expiresAt: number;
}

interface Wrap {
  id: string;
  kind: string;
  keyV: number;
  wrapped: string;
  publicKey: string | null;
  attestation: string | null;
}

let counter = 0;

/**
 * The `/v2/signin` relay with the rules of `apps/api/src/services/signin.ts` (spec 2026-11-15
 * section 8), signed out, and enough of `/v2/keys` for the browser's enroll after the pickup (the
 * cookie then exists). The test plays the phone: `approve` (its ephemeral `A`) and `seal` (DK
 * sealed from `A` to the revealed key). Tamper hooks stand in for a malicious server.
 */
function fakeServer(clock: { t: number }) {
  const state = {
    rows: new Map<string, Row>(),
    wraps: [] as Wrap[],
    log: [] as Array<{ method: string; path: string; headers: Record<string, string> }>,
    ignoreExpiry: false,
    onPoll: undefined as undefined | ((body: Record<string, unknown>) => void),
    onPickup: undefined as undefined | ((body: Record<string, unknown>) => Response | undefined),
    onStart: undefined as undefined | (() => Response | undefined),
    /** Rewrites the 201 of the opening (a malformed server). */
    onStarted: undefined as undefined | ((body: Record<string, unknown>) => void),
    /** Who the pickup's session cookie is for: `/v2/keys` then answers for that user only. */
    session: null as string | null,
  };
  const current = () => Math.max(0, ...state.wraps.map((w) => w.keyV));
  const live = (id: string) => {
    const row = state.rows.get(id);
    if (!row || (!state.ignoreExpiry && row.expiresAt <= clock.t)) return undefined;
    return row;
  };
  const answer = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const url = new URL(String(input), "http://x");
    const method = init?.method ?? "GET";
    const headers = (init?.headers ?? {}) as Record<string, string>;
    state.log.push({ method, path: url.pathname, headers });
    const body = init?.body ? JSON.parse(String(init.body)) : undefined;
    const path = url.pathname.replace(/^\/api/, "");

    if (path.startsWith("/v2/keys")) {
      // the enroll runs on the pickup's session, for that user
      expect(state.session).not.toBeNull();
      expect(headers["x-wambito-user"]).toBe(state.session);
      if (path === "/v2/keys" && method === "GET") return json({ wraps: state.wraps });
      const put = /^\/v2\/keys\/([0-9a-f-]{36})$/.exec(path);
      if (put && method === "PUT") {
        state.wraps.push({ id: put[1] as string, ...body });
        return json(body);
      }
      if (put && method === "DELETE") {
        state.wraps = state.wraps.filter((w) => w.id !== put[1]);
        return new Response(null, { status: 204 });
      }
      return new Response(null, { status: 404 });
    }

    // the sign-in routes are signed out: never a user named
    expect(headers["x-wambito-user"]).toBeUndefined();
    expect(init?.credentials).toBe("same-origin");
    if (path === "/v2/signin" && method === "POST") {
      const early = state.onStart?.();
      if (early) return early;
      const id = crypto.randomUUID();
      const row: Row = {
        id,
        code: `ABCD${String(++counter % 10000).padStart(4, "0")}`,
        pollSecret: toBase64Url(crypto.getRandomValues(new Uint8Array(32))),
        commitment: body.commitment,
        remember: body.remember,
        label: body.label,
        approverKey: null,
        userId: null,
        publicKey: null,
        sealed: null,
        keyV: null,
        expiresAt: clock.t + SIGNIN_TTL_MS,
      };
      state.rows.set(id, row);
      const out: Record<string, unknown> = {
        id,
        code: row.code,
        pollSecret: row.pollSecret,
        expiresAt: new Date(row.expiresAt).toISOString(),
      };
      state.onStarted?.(out);
      return json(out, 201);
    }
    const match = /^\/v2\/signin\/([0-9a-f-]{36})(?:\/(\w+))?$/.exec(path);
    if (!match) return new Response(null, { status: 404 });
    const row = live(match[1] as string);
    if (!row || headers["x-wambito-poll"] !== row.pollSecret) return problem(404, "not_found");
    const action = match[2];
    if (!action && method === "GET") {
      const out: Record<string, unknown> = {
        approverKey: row.approverKey,
        ready: row.sealed !== null,
        expiresAt: new Date(row.expiresAt).toISOString(),
      };
      state.onPoll?.(out);
      return json(out);
    }
    if (action === "reveal" && method === "POST") {
      if (!row.approverKey) return problem(409, "not_ready");
      if (row.publicKey) return problem(409, "already_set");
      const hash = toBase64Url(await pairingCommitment(fromBase64Url(body.publicKey)));
      if (hash !== row.commitment) return problem(422, "commitment_mismatch");
      row.publicKey = body.publicKey;
      return new Response(null, { status: 204 });
    }
    if (action === "pickup" && method === "POST") {
      if (!row.sealed || row.keyV === null || !row.userId) return problem(409, "not_ready");
      const out: Record<string, unknown> = {
        sealed: row.sealed,
        keyV: row.keyV,
        userId: row.userId,
      };
      const early = state.onPickup?.(out);
      if (early) return early;
      state.rows.delete(row.id);
      state.session = row.userId;
      return json(out);
    }
    return new Response(null, { status: 404 });
  };
  return Object.assign(state, { fetch: answer as typeof globalThis.fetch });
}

/** A fake clock whose `sleep` moves time on, a server, and the phone's account. */
function world() {
  const clock = { t: Date.parse("2026-11-18T12:00:00Z") };
  const sleeps: number[] = [];
  const server = fakeServer(clock);
  const userId = `signin_user_${++counter}`;
  const dataKey = generateDataKey();
  handed.openedPairing.length = 0;
  const options = {
    remember: true,
    label: "Firefox on macOS",
    fetch: server.fetch,
    clock: {
      now: () => clock.t,
      sleep: async (ms: number) => {
        sleeps.push(ms);
        clock.t += ms;
        await new Promise((resolve) => setTimeout(resolve, 0));
      },
    },
  };
  /** The phone approves: its ephemeral `A`, the request bound to its user. */
  const approve = async (id: string) => {
    const a = await generateDeviceKeyPair();
    const row = server.rows.get(id) as Row;
    row.approverKey = toBase64Url(a.publicKey);
    row.userId = userId;
    return a;
  };
  /** The phone seals DK at `keyV` from `A` to the revealed key (phone ruling 15). */
  const seal = async (
    id: string,
    a: Awaited<ReturnType<typeof generateDeviceKeyPair>>,
    keyV = 1,
  ) => {
    const row = server.rows.get(id) as Row;
    const revealed = fromBase64Url(row.publicKey as string);
    const blob = await sealToDevice(revealed, { kind: "device", userId, keyV }, dataKey, a);
    row.sealed = toBase64Url(blob);
    row.keyV = keyV;
  };
  return { clock, sleeps, server, userId, dataKey, options, approve, seal };
}

const signinErrorOf = async (promise: Promise<unknown>): Promise<SigninErrorCode> => {
  try {
    await promise;
  } catch (error) {
    if (error instanceof SigninError) return error.code;
    throw error;
  }
  throw new Error("expected a SigninError");
};

const ticks = async (n: number) => {
  for (let i = 0; i < n; i++) await new Promise((resolve) => setTimeout(resolve, 0));
};

const ephemeralOf = async (userId: string) => {
  const store = await createEncryptedStore(userId);
  try {
    return await store.getMeta<boolean>("ephemeral");
  } finally {
    store.close();
  }
};

describe("startSignin", () => {
  it("the happy path: the request posts the commitment of the QR key, number() equals pairingNumber(N, A), finish() enrolls this browser for the picked-up user", async () => {
    const w = world();
    const signin = await startSignin(w.options);
    const row = w.server.rows.get(signin.id) as Row;
    const qrKey = fromBase64Url(signin.qr.split("&key=")[1] as string);
    expect(row.commitment).toBe(toBase64Url(await pairingCommitment(qrKey)));
    expect(row.remember).toBe(true);
    expect(row.label).toBe("Firefox on macOS");

    const a = await w.approve(signin.id);
    const number = await signin.number();
    expect(number).toBe(await pairingNumber(qrKey, a.publicKey));
    expect(row.publicKey).toBe(toBase64Url(qrKey));

    await w.seal(signin.id, a, 3);
    const { userId, keys } = await signin.finish();
    expect(userId).toBe(w.userId);
    expect(keys.keyring.current).toBe(3);
    expect(w.server.rows.size).toBe(0);
    // this browser's own attested device wrap, for the picked-up user
    const enrolled = w.server.wraps.at(-1) as Wrap;
    expect(enrolled.kind).toBe("device");
    expect(enrolled.keyV).toBe(3);
    expect(enrolled.publicKey).not.toBe(toBase64Url(qrKey));
    // the opened DK is zeroed once enrolled
    expect(handed.openedPairing).toHaveLength(1);
    expect(handed.openedPairing[0]?.every((x) => x === 0)).toBe(true);
    // every poll waits 1.5 s
    expect(w.sleeps.length).toBeGreaterThan(0);
    expect(new Set(w.sleeps)).toEqual(new Set([SIGNIN_POLL_MS]));
    expect(SIGNIN_POLL_MS).toBe(1500);
    expect(SIGNIN_TTL_MS).toBe(2 * 60 * 1000);
  });

  it("the qr is wambito://signin?id=<id>&key=<43 base64url chars> and the code is the server's", async () => {
    const w = world();
    const signin = await startSignin(w.options);
    const row = w.server.rows.get(signin.id) as Row;
    expect(signin.qr).toMatch(
      new RegExp(`^wambito://signin\\?id=${signin.id}&key=[A-Za-z0-9_-]{43}$`),
    );
    expect(signin.code).toBe(row.code);
    expect(signin.expiresAt).toBe(new Date(row.expiresAt).toISOString());
    // the poll secret stays in the closure: never on the returned object
    expect(JSON.stringify(signin)).not.toContain(row.pollSecret);
    signin.cancel();
  });

  it("every poll, reveal and pickup carries x-wambito-poll and no x-wambito-user", async () => {
    const w = world();
    const signin = await startSignin(w.options);
    const secret = (w.server.rows.get(signin.id) as Row).pollSecret;
    const a = await w.approve(signin.id);
    await signin.number();
    await w.seal(signin.id, a);
    await signin.finish();
    const relayed = w.server.log.filter((l) => l.path.startsWith(`/api/v2/signin/${signin.id}`));
    expect(relayed.some((l) => l.path.endsWith("/reveal"))).toBe(true);
    expect(relayed.some((l) => l.path.endsWith("/pickup"))).toBe(true);
    expect(relayed.some((l) => l.method === "GET")).toBe(true);
    for (const l of relayed) {
      expect(l.headers["x-wambito-poll"]).toBe(secret);
      expect(l.headers["x-wambito-user"]).toBeUndefined();
    }
    // the opening carries neither
    const opened = w.server.log.find((l) => l.path === "/api/v2/signin");
    expect(opened?.headers["x-wambito-poll"]).toBeUndefined();
    expect(opened?.headers["x-wambito-user"]).toBeUndefined();
  });

  it("a second approver key on a later poll is tampered, and nothing is picked up", async () => {
    const w = world();
    const signin = await startSignin(w.options);
    const a = await w.approve(signin.id);
    await signin.number();
    const evil = toBase64Url((await generateDeviceKeyPair()).publicKey);
    w.server.onPoll = (body) => {
      body.approverKey = evil;
    };
    await w.seal(signin.id, a);
    expect(await signinErrorOf(signin.finish())).toBe("tampered");
    expect(w.server.log.some((l) => l.path.endsWith("/pickup"))).toBe(false);
    expect(w.server.wraps).toHaveLength(0);
  });

  it("a sealed blob that does not open with the pinned key is tampered", async () => {
    const w = world();
    const signin = await startSignin(w.options);
    const a = await w.approve(signin.id);
    await signin.number();
    // the right DK, sealed under a key that is not the pinned approver key
    const other = await generateDeviceKeyPair();
    await w.seal(signin.id, other);
    expect(await signinErrorOf(signin.finish())).toBe("tampered");
    expect(w.server.wraps).toHaveLength(0);
    void a;
  });

  it("404 on a poll is expired; the clock past expiresAt is expired; cancel() is cancelled and zeroes N", async () => {
    // the row goes (404)
    const w = world();
    const gone = await startSignin(w.options);
    w.server.rows.clear();
    expect(await signinErrorOf(gone.number())).toBe("expired");
    expect(await signinErrorOf(gone.finish())).toBe("expired");

    // the clock passes expiresAt while the server still answers
    const v = world();
    v.server.ignoreExpiry = true;
    const start = v.clock.t;
    const lonely = await startSignin(v.options);
    expect(await signinErrorOf(lonely.number())).toBe("expired");
    expect(v.clock.t - start).toBeGreaterThanOrEqual(SIGNIN_TTL_MS);
    expect(v.clock.t - start).toBeLessThan(SIGNIN_TTL_MS + 2 * SIGNIN_POLL_MS);

    // cancel() stops polling and zeroes N's raw private bytes (the noble fallback's shape)
    const u = world();
    u.server.ignoreExpiry = true;
    handed.nobleNext = true;
    const cancelled = await startSignin(u.options);
    const raw = handed.noble.at(-1) as Uint8Array;
    expect(raw.some((x) => x !== 0)).toBe(true);
    const number = cancelled.number();
    await ticks(5);
    cancelled.cancel();
    expect(await signinErrorOf(number)).toBe("cancelled");
    expect(await signinErrorOf(cancelled.finish())).toBe("cancelled");
    expect(raw.every((x) => x === 0)).toBe(true);
    const after = u.server.log.length;
    await ticks(20);
    expect(u.server.log.length).toBe(after);
  });

  it("a server clock behind this browser's does not end the request: the 2 minutes run on this browser's clock", async () => {
    // The server's expiresAt is on its own clock (four weeks behind here, as the e2e's pinned
    // API); compared with this browser's, every new request looked expired at once.
    const w = world();
    w.server.onStarted = (body) => {
      body.expiresAt = new Date(w.clock.t - 28 * 24 * 60 * 60 * 1000).toISOString();
    };
    const signin = await startSignin(w.options);
    const a = await w.approve(signin.id);
    expect(await signin.number()).toBeTypeOf("string");
    await w.seal(signin.id, a);
    expect((await signin.finish()).userId).toBeTypeOf("string");
  });

  it("429 with no retry-after has no retryAfterS (never 0: the caller would retry at once)", async () => {
    const w = world();
    w.server.onStart = () => problem(429, "too_many_signins");
    const error = await startSignin(w.options).catch((e: unknown) => e);
    expect((error as SigninError).code).toBe("too_many");
    expect((error as SigninError).retryAfterS).toBeUndefined();
  });

  it("429 too_many_signins is too_many with retryAfterS from retry-after; 403 on pickup is suspended", async () => {
    const w = world();
    w.server.onStart = () => problem(429, "too_many_signins", { "retry-after": "42" });
    let error: unknown;
    try {
      await startSignin(w.options);
    } catch (e) {
      error = e;
    }
    expect(error).toBeInstanceOf(SigninError);
    expect((error as SigninError).code).toBe("too_many");
    expect((error as SigninError).retryAfterS).toBe(42);

    const v = world();
    const signin = await startSignin(v.options);
    const a = await v.approve(signin.id);
    await signin.number();
    await v.seal(signin.id, a);
    v.server.onPickup = () => problem(403, "account_suspended");
    expect(await signinErrorOf(signin.finish())).toBe("suspended");
    expect(v.server.wraps).toHaveLength(0);

    // a network failure is offline
    const u = world();
    const offline = await startSignin({
      ...u.options,
      fetch: async () => {
        throw new TypeError("network");
      },
    }).catch((e: unknown) => e);
    expect((offline as SigninError).code).toBe("offline");
  });

  it("unticked: the enrolled vault's meta ephemeral is true; ticked: absent", async () => {
    const w = world();
    const unticked = await startSignin({ ...w.options, remember: false });
    expect((w.server.rows.get(unticked.id) as Row).remember).toBe(false);
    const a = await w.approve(unticked.id);
    await unticked.number();
    await w.seal(unticked.id, a);
    await unticked.finish();
    expect(await ephemeralOf(w.userId)).toBe(true);

    const v = world();
    const ticked = await startSignin(v.options);
    const b = await v.approve(ticked.id);
    await ticked.number();
    await v.seal(ticked.id, b);
    await ticked.finish();
    expect(await ephemeralOf(v.userId)).toBeUndefined();
  });

  it("another account's vault in this browser is deleted before enrollment and the new account's vault remains", async () => {
    const w = world();
    // another account enrolled here earlier (its own server, its own keys)
    const elsewhere = fakeServer(w.clock);
    elsewhere.session = "someone_else";
    await enrollDevice({ userId: "someone_else", fetch: elsewhere.fetch }, generateDataKey(), 1);
    const names = async () => (await indexedDB.databases()).map((d) => d.name);
    expect(await names()).toContain(vaultName("someone_else"));

    const signin = await startSignin(w.options);
    const a = await w.approve(signin.id);
    await signin.number();
    await w.seal(signin.id, a);
    const { keys } = await signin.finish();
    expect(keys.keyring.current).toBe(1);
    expect(await names()).not.toContain(vaultName("someone_else"));
    expect(await names()).toContain(vaultName(w.userId));
  });

  it("a malformed 201 is server, before any poll, and N is zeroed", async () => {
    const bad: Array<[string, unknown]> = [
      ["id", "not-an-id"],
      ["id", undefined],
      ["pollSecret", ""],
      ["pollSecret", "not base64url!"],
      ["pollSecret", 42],
      ["code", "ABC"],
      ["code", "abcdefgh"],
      ["expiresAt", "soon"],
      ["expiresAt", undefined],
    ];
    for (const [field, value] of bad) {
      const w = world();
      w.server.onStarted = (body) => {
        body[field] = value;
      };
      handed.nobleNext = true;
      const error = await startSignin(w.options).catch((e: unknown) => e);
      expect(error, `${field}: ${String(value)}`).toBeInstanceOf(SigninError);
      expect((error as SigninError).code).toBe("server");
      expect(handed.noble.at(-1)?.every((x) => x === 0)).toBe(true);
      expect(w.server.log.filter((l) => l.path !== "/api/v2/signin")).toHaveLength(0);
    }
  });

  it("cancel() once the pickup answered does not stop finish(): the session exists", async () => {
    const w = world();
    let signin: Awaited<ReturnType<typeof startSignin>> | undefined;
    const fetch: typeof globalThis.fetch = async (input, init) => {
      const response = await w.server.fetch(input, init);
      if (String(input).endsWith("/pickup") && response.ok) signin?.cancel();
      return response;
    };
    signin = await startSignin({ ...w.options, fetch });
    const a = await w.approve(signin.id);
    await signin.number();
    await w.seal(signin.id, a);
    const { userId, keys } = await signin.finish();
    expect(userId).toBe(w.userId);
    expect(keys.keyring.current).toBe(1);
    expect(w.server.wraps.filter((x) => x.kind === "device")).toHaveLength(1);
    expect(handed.openedPairing[0]?.every((x) => x === 0)).toBe(true);
  });

  it("cancel() while the pickup is in flight does not stop finish(): the server may have set the cookie", async () => {
    const w = world();
    let signin: Awaited<ReturnType<typeof startSignin>> | undefined;
    const fetch: typeof globalThis.fetch = async (input, init) => {
      // the cancel lands after the pickup left, before its answer
      if (String(input).endsWith("/pickup")) signin?.cancel();
      const response = await w.server.fetch(input, init);
      // a real fetch drops an aborted request's answer, cookie set or not
      if (init?.signal?.aborted) throw new DOMException("aborted", "AbortError");
      return response;
    };
    signin = await startSignin({ ...w.options, fetch });
    const a = await w.approve(signin.id);
    await signin.number();
    await w.seal(signin.id, a);
    const { userId, keys } = await signin.finish();
    expect(userId).toBe(w.userId);
    expect(keys.keyring.current).toBe(1);
    expect(w.server.wraps.filter((x) => x.kind === "device")).toHaveLength(1);
  });

  it("ready() resolves once the phone sealed, before the pickup; a cancel rejects it", async () => {
    const w = world();
    const signin = await startSignin(w.options);
    let isReady = false;
    void signin.ready().then(() => {
      isReady = true;
    });
    const a = await w.approve(signin.id);
    await signin.number();
    await ticks(3);
    expect(isReady).toBe(false);
    await w.seal(signin.id, a);
    await signin.ready();
    expect(w.server.log.some((l) => l.path.endsWith("/pickup"))).toBe(false);
    await signin.finish();

    const other = await startSignin(w.options);
    const waiting = other.ready();
    other.cancel();
    expect(await signinErrorOf(waiting)).toBe("cancelled");
  });

  it("a ticked sign-in deletes the ephemeral mark of a vault held here for the same user", async () => {
    const w = world();
    const unticked = await startSignin({ ...w.options, remember: false });
    const a = await w.approve(unticked.id);
    await unticked.number();
    await w.seal(unticked.id, a);
    await unticked.finish();
    expect(await ephemeralOf(w.userId)).toBe(true);

    // the same person signs in again here with the box ticked: the vault is now kept
    const ticked = await startSignin(w.options);
    const b = await w.approve(ticked.id);
    await ticked.number();
    await w.seal(ticked.id, b);
    await ticked.finish();
    expect(await ephemeralOf(w.userId)).toBeUndefined();
  });
});
