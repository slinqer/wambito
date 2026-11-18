import {
  fromBase64Url,
  generateDeviceKeyPair,
  openFromPairing,
  pairingCommitment,
  pairingNumber,
  toBase64Url,
} from "@wambito/crypto";
import { enrollDevice, type LocalKeys } from "./keys.ts";
import {
  deferred,
  key32,
  type PairingClock,
  problemCode,
  realClock,
  retryAfter,
  zeroPrivate,
} from "./relay.ts";
import { deleteStaleVaults } from "./stale-vaults.ts";

/**
 * Signing in a signed-out browser by the phone (spec 2026-11-15 section 8; the API's
 * `routes/signin.ts`). The browser makes an ephemeral pair `N`, opens a request with its
 * commitment, `remember` (the "Keep me signed in" box) and its `label`, and shows the code and the
 * QR `wambito://signin?id=<id>&key=<base64url N.pub>`. The phone approves with its ephemeral `A`;
 * the browser pins the first `approverKey` it sees (another later is `tampered`), reveals `N.pub`
 * and shows `pairingNumber(N.pub, A.pub)`; the phone seals DK from `A` to `N` under
 * `{ kind: "device", userId, keyV }`; the browser picks it up (the response sets the session
 * cookie), opens it against the pinned key, deletes every other account's vault here and enrolls
 * this browser (`ephemeral` when the box was unticked).
 *
 * The routes are signed out: plain `fetch` to `/api/v2/signin…` with `credentials: "same-origin"`,
 * never `x-wambito-user`; the poll secret (`x-wambito-poll`) lives in this closure only, never
 * logged or stored. Polls every 1.5 s; stops at `expiresAt` capped at 2 minutes from the start
 * (`expired`) or on `cancel()` (`cancelled`). DK and `N.priv` are zeroed in a `finally` (the
 * private key where it is raw bytes, the noble fallback). `KeysError`s from the enroll go
 * through unchanged.
 */

export type SigninErrorCode =
  /** 404 from the relay (gone, expired, or picked up), or `expiresAt` passed on this browser's clock. */
  | "expired"
  /** A value the server relayed does not match what this browser pinned, a 422, a blob that does not open. */
  | "tampered"
  | "offline"
  | "server"
  /** `cancel()` was called. */
  | "cancelled"
  /** 429 `too_many_requests` / `too_many_signins`; `retryAfterS` from `retry-after`. */
  | "too_many"
  /** 403 `account_suspended` at the pickup. */
  | "suspended";

export class SigninError extends Error {
  constructor(
    readonly code: SigninErrorCode,
    readonly retryAfterS?: number,
  ) {
    super(code);
    this.name = "SigninError";
  }
}

export const SIGNIN_POLL_MS = 1500;
/** A request lives 2 minutes (spec 8.1): the most this browser waits, whatever the relay says. */
export const SIGNIN_TTL_MS = 2 * 60 * 1000;

export interface SigninOptions {
  /** The "Keep me signed in on this browser" box; false makes a short session and an ephemeral vault. */
  remember: boolean;
  /** `deviceLabel(navigator.userAgent)`, for the phone to show. */
  label: string;
  /** Defaults to `Date.now` and `setTimeout`; tests pass a fake one. */
  clock?: PairingClock;
  /** Defaults to the global `fetch`. */
  fetch?: typeof globalThis.fetch;
}

export interface WebSignin {
  id: string;
  /** The server's code, for the phone to type. */
  code: string;
  /** `wambito://signin?id=<id>&key=<base64url N.pub>` */
  qr: string;
  expiresAt: string;
  /** The 6 digits, once this browser pinned the approver key and revealed its own. */
  number(): Promise<string>;
  /** Resolves once the relay says the phone sealed, before the pickup (the panel's "Opening your data…"). */
  ready(): Promise<void>;
  /** Picks up the sealed DK and the session, opens DK and enrolls this browser for that user. */
  finish(): Promise<{ userId: string; keys: LocalKeys }>;
  cancel(): void;
}

interface SigninPoll {
  approverKey: string | null;
  ready: boolean;
  expiresAt: string;
}

const BASE = "/api";

/** The shapes `startPairing`'s QR and code use: a UUID, an 8-character code, base64url. */
const ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const CODE = /^[0-9A-HJKMNP-TV-Z]{8}$/;
const BASE64URL = /^[A-Za-z0-9_-]+$/;

/** The 201 of `POST /v2/signin`, or false: anything else is `server` before a poll. */
function validStart(body: unknown): boolean {
  if (typeof body !== "object" || body === null) return false;
  const { id, code, pollSecret, expiresAt } = body as Record<string, unknown>;
  return (
    typeof id === "string" &&
    ID.test(id) &&
    typeof code === "string" &&
    CODE.test(code) &&
    typeof pollSecret === "string" &&
    BASE64URL.test(pollSecret) &&
    typeof expiresAt === "string" &&
    !Number.isNaN(Date.parse(expiresAt))
  );
}

const tampered = () => new SigninError("tampered");

/**
 * The signed-out relay for one request: every call first checks the cancel signal and the clock
 * against the deadline. 404 → `expired`, 403 → `suspended`, 422 → `tampered`, 429 → `too_many`,
 * a 409 → `conflict` (or `null` for "retry"), offline → `offline`, the rest `server`.
 */
function relay(options: SigninOptions, signal: AbortSignal, clock: PairingClock) {
  const cap = clock.now() + SIGNIN_TTL_MS;
  let deadline = cap;
  let secret: string | null = null;
  const check = () => {
    if (signal.aborted) throw new SigninError("cancelled");
    if (clock.now() >= deadline) throw new SigninError("expired");
  };
  const send = async (
    path: string,
    init: { method?: string; body?: unknown },
    conflict: SigninErrorCode | ((code: string | undefined) => "retry" | "done"),
  ): Promise<Response | "retry" | "done"> => {
    check();
    const headers: Record<string, string> = {};
    if (secret !== null) headers["x-wambito-poll"] = secret;
    if (init.body !== undefined) headers["content-type"] = "application/json";
    let response: Response;
    try {
      response = await (options.fetch ?? fetch)(`${BASE}${path}`, {
        method: init.method ?? "GET",
        headers,
        body: init.body === undefined ? undefined : JSON.stringify(init.body),
        credentials: "same-origin",
        signal,
      });
    } catch {
      if (signal.aborted) throw new SigninError("cancelled");
      throw new SigninError("offline");
    }
    if (response.ok) return response;
    if (response.status === 404) throw new SigninError("expired");
    if (response.status === 403) throw new SigninError("suspended");
    if (response.status === 422) throw tampered();
    if (response.status === 429) throw new SigninError("too_many", retryAfter(response));
    if (response.status === 409) {
      if (typeof conflict === "function") return conflict(await problemCode(response));
      throw new SigninError(conflict);
    }
    throw new SigninError("server");
  };
  const json = async <T>(answer: Response | "retry" | "done"): Promise<T> => {
    if (typeof answer === "string") throw new SigninError("server");
    try {
      return (await answer.json()) as T;
    } catch {
      throw new SigninError("server");
    }
  };
  return {
    check,
    start: async (body: unknown) =>
      json<{ id: string; code: string; pollSecret: string; expiresAt: string }>(
        await send("/v2/signin", { method: "POST", body }, "server"),
      ),
    useSecret(pollSecret: string, expiresAt: string) {
      secret = pollSecret;
      const at = Date.parse(expiresAt);
      deadline = Number.isNaN(at) ? cap : Math.min(at, cap);
    },
    /** 204; `retry` on 409 `not_ready`; `done` on `already_set` (only this browser holds the secret). */
    reveal: (id: string, publicKey: string) =>
      send(`/v2/signin/${id}/reveal`, { method: "POST", body: { publicKey } }, (code) =>
        code === "already_set" ? "done" : "retry",
      ),
    /** `onAnswered` runs once the pickup answered 200, before its body is read. */
    pickup: async (id: string, onAnswered: () => void) => {
      const answer = await send(`/v2/signin/${id}/pickup`, { method: "POST" }, "server");
      if (typeof answer !== "string") onAnswered();
      return json<{ sealed: unknown; keyV: unknown; userId: unknown }>(answer);
    },
    async poll<T>(id: string, step: (state: SigninPoll) => Promise<T | undefined>): Promise<T> {
      for (;;) {
        const state = await json<SigninPoll>(await send(`/v2/signin/${id}`, {}, "server"));
        const done = await step(state);
        if (done !== undefined) return done;
        check();
        await clock.sleep(SIGNIN_POLL_MS, signal);
      }
    },
  };
}

/**
 * Opens a sign-in request for the phone to approve: makes `N`, posts `{ commitment, remember,
 * label }` and returns the code and the QR. Polling starts with the first `number()` or `finish()`.
 */
export async function startSignin(options: SigninOptions): Promise<WebSignin> {
  const clock = options.clock ?? realClock;
  const abort = new AbortController();
  const net = relay(options, abort.signal, clock);
  const pair = await generateDeviceKeyPair();
  const newKey = toBase64Url(pair.publicKey);
  let started: { id: string; code: string; pollSecret: string; expiresAt: string };
  try {
    const commitment = toBase64Url(await pairingCommitment(pair.publicKey));
    started = await net.start({ commitment, remember: options.remember, label: options.label });
    if (!validStart(started)) throw new SigninError("server");
  } catch (error) {
    zeroPrivate(pair.privateKey);
    throw error;
  }
  // the poll secret goes into the relay's closure only; never on the returned object
  net.useSecret(started.pollSecret, started.expiresAt);
  const { id } = started;

  const number = deferred<string>();
  const ready = deferred<{ approverKey: Uint8Array }>();
  let running: Promise<void> | null = null;
  let finishing: Promise<{ userId: string; keys: LocalKeys }> | null = null;
  /** The pickup answered: the session exists, so `cancel()` no longer stops the enroll. */
  let pickedUp = false;

  const run = async () => {
    let pinned: string | null = null;
    let revealed = false;
    await net.poll(id, async (state) => {
      if (state.approverKey === null) {
        if (pinned !== null || state.ready) throw tampered();
        return undefined;
      }
      // the first approver key seen is the one: any other later is the server's
      if (pinned === null) {
        key32(state.approverKey, tampered);
        pinned = state.approverKey;
      } else if (state.approverKey !== pinned) {
        throw tampered();
      }
      if (!revealed) {
        // sealed before this browser revealed its key: not to this browser
        if (state.ready) throw tampered();
        // 409 `not_ready`: look again at the next poll; `already_set`: our own lost answer
        if ((await net.reveal(id, newKey)) === "retry") return undefined;
        revealed = true;
        number.resolve(await pairingNumber(pair.publicKey, key32(pinned, tampered)));
      }
      return state.ready ? true : undefined;
    });
    ready.resolve({ approverKey: key32(pinned as unknown as string, tampered) });
  };

  const ensureRunning = () => {
    running ??= run().catch((error) => {
      number.reject(error);
      ready.reject(error);
      zeroPrivate(pair.privateKey);
    });
  };

  const finish = async (): Promise<{ userId: string; keys: LocalKeys }> => {
    ensureRunning();
    const { approverKey } = await ready.promise;
    try {
      const picked = await net.pickup(id, () => {
        pickedUp = true;
      });
      const { userId, keyV } = picked;
      if (typeof userId !== "string" || userId === "") throw new SigninError("server");
      if (typeof keyV !== "number" || !Number.isInteger(keyV) || keyV < 1) {
        throw new SigninError("server");
      }
      let sealed: Uint8Array;
      try {
        sealed = fromBase64Url(picked.sealed as string);
      } catch {
        throw tampered();
      }
      let dataKey: Uint8Array;
      try {
        dataKey = await openFromPairing(
          pair.privateKey,
          { kind: "device", userId, keyV },
          sealed,
          approverKey,
        );
      } catch {
        throw tampered();
      }
      try {
        // another account's vault never outlives this sign-in; ours is made after
        await deleteStaleVaults(userId);
        const keys = await enrollDevice({ userId, fetch: options.fetch }, dataKey, keyV, {
          ephemeral: !options.remember,
        });
        return { userId, keys };
      } finally {
        dataKey.fill(0);
      }
    } finally {
      zeroPrivate(pair.privateKey);
    }
  };

  return {
    id,
    code: started.code,
    qr: `wambito://signin?id=${id}&key=${newKey}`,
    expiresAt: started.expiresAt,
    number() {
      ensureRunning();
      return number.promise;
    },
    ready() {
      ensureRunning();
      return ready.promise.then(() => undefined);
    },
    finish() {
      finishing ??= finish();
      return finishing;
    },
    cancel() {
      // after the pickup, finishing the enroll beats a session with no keys
      if (pickedUp) return;
      abort.abort();
      const error = new SigninError("cancelled");
      number.reject(error);
      ready.reject(error);
      zeroPrivate(pair.privateKey);
    },
  };
}
