import {
  type DevicePrivateKey,
  fromBase64Url,
  generateDeviceKeyPair,
  openFromPairing,
  pairingCommitment,
  pairingNumber,
  sealToDevice,
  toBase64Url,
} from "@wambito/crypto";
import {
  api,
  enrollDevice,
  KeysError,
  type KeysOptions,
  type LocalKeys,
  withDataKey,
} from "./keys.ts";

/**
 * Pairing a new browser from an unlocked device (stage 1b spec section 1, steps 1–8). The server
 * only relays: the new device's commitment to its ephemeral key `N`, the approver's ephemeral key
 * `A`, the revealed `N.pub` and DK sealed from `A` to `N`. Pinning (`packages/crypto/AGENTS.md`):
 * the approving device keeps the `commitment` it read before posting `A.pub` and never takes it
 * again; the new device keeps the first `approverKey` it sees and aborts if a later poll shows
 * another. Both show `pairingNumber(N.pub, A.pub)`, QR or not. Both poll every 1.5 s and stop at
 * `expiresAt` (`expired`) or on `cancel()` (`cancelled`). DK and the opened DK are zeroed in a
 * `finally`; the ephemeral private keys are zeroed where they are raw bytes (noble fallback).
 */

export type PairingErrorCode =
  /** 404 from the relay (gone, or expired there), or `expiresAt` passed on this device's clock. */
  | "expired"
  /** A value the server relayed does not match what this device pinned or computed. */
  | "tampered"
  /** A typed code that cannot be one or finds nothing, or a QR not `wambito://pair?id=…&key=…`. */
  | "bad_code"
  | "offline"
  | "server"
  /** `cancel()` was called. */
  | "cancelled";

export class PairingError extends Error {
  constructor(readonly code: PairingErrorCode) {
    super(code);
    this.name = "PairingError";
  }
}

/** A 404: the relay no longer has the request (picked up, or expired there). */
class Gone extends PairingError {
  constructor() {
    super("expired");
  }
}

export const PAIRING_POLL_MS = 1500;
/** A request lives 10 minutes (spec 7.3): the most either device waits, whatever the relay says. */
export const PAIRING_TTL_MS = 10 * 60 * 1000;

export interface PairingClock {
  now(): number;
  /** Waits `ms`; may resolve early when `signal` aborts. */
  sleep(ms: number, signal: AbortSignal): Promise<void>;
}

export interface PairingOptions extends KeysOptions {
  /** Defaults to `Date.now` and `setTimeout`; tests pass a fake one. */
  clock?: PairingClock;
}

const realClock: PairingClock = {
  now: () => Date.now(),
  sleep: (ms, signal) =>
    new Promise((resolve) => {
      if (signal.aborted) return resolve();
      const timer = setTimeout(done, ms);
      function done() {
        clearTimeout(timer);
        signal.removeEventListener("abort", done);
        resolve();
      }
      signal.addEventListener("abort", done);
    }),
};

export interface NewDevicePairing {
  id: string;
  code: string;
  /** `wambito://pair?id=<id>&key=<base64url N.pub>` */
  qr: string;
  expiresAt: string;
  /** The 6 digits, once this device revealed its key (after it pinned the approver key). */
  number(): Promise<string>;
  /** Picks up the sealed DK, opens it and enrolls this browser with an attested device wrap. */
  finish(): Promise<LocalKeys>;
  cancel(): void;
}

export interface ApproverPairing {
  /** The 6 digits, once the new device revealed a key that matches the pinned commitment. */
  number(): Promise<string>;
  /**
   * Rejects with a plain `Error("approve before number")`, sending nothing, unless `number()` has
   * resolved on this object. The person confirmed the numbers match: seals DK (from this browser's device wrap) to the
   * revealed key from `A`, then waits for the new device to pick it up (the relay answers 404).
   */
  approve(): Promise<void>;
  cancel(): void;
}

interface PairingState {
  commitment: string;
  approverKey: string | null;
  publicKey: string | null;
  sealed: string | null;
  keyV: number | null;
  expiresAt: string;
}

const CODE = /^[0-9A-HJKMNP-TV-Z]{8}$/;
const QR =
  /^wambito:\/\/pair\?id=([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})&key=([A-Za-z0-9_-]{43})$/;

/** The server's reading of a typed code: upper case, no dashes or spaces, I/L as 1, O as 0. */
export function normalizePairingCode(input: string): string {
  return input.toUpperCase().replace(/[-\s]/g, "").replace(/[IL]/g, "1").replace(/O/g, "0");
}

const noop = () => {};

/** A one-shot promise whose rejection never goes unhandled (callers still see it). */
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  promise.catch(noop);
  return { promise, resolve, reject };
}

/** Raw private bytes exist only on the noble fallback: zero them; a `CryptoKey` has none. */
function zeroPrivate(key: DevicePrivateKey) {
  if (!(key instanceof CryptoKey)) key.raw.fill(0);
}

const sameBytes = (a: Uint8Array, b: Uint8Array) =>
  a.length === b.length && a.every((x, i) => x === b[i]);

/** 32 bytes from base64url, or `tampered` for anything else the server relays. */
function key32(text: string): Uint8Array {
  let bytes: Uint8Array;
  try {
    bytes = fromBase64Url(text);
  } catch {
    throw new PairingError("tampered");
  }
  if (bytes.length !== 32) throw new PairingError("tampered");
  return bytes;
}

/**
 * The relay for one pairing: `api(options)` (the `x-wambito-user` header, `session_changed`)
 * with its errors read as pairing errors: offline → `offline`, 404 → `expired`, 422 → `tampered`,
 * a 409 → `conflict`, the rest `server`. `KeysError`s that are not about the relay
 * (`session_changed`, `rotated_elsewhere`) go through unchanged. Every call first checks the
 * cancel signal and the clock against the deadline: the relay's `expiresAt`, capped at 10 minutes
 * from when this device started (the new device's request, the approver's lookup).
 */
function relay(options: PairingOptions, signal: AbortSignal, clock: PairingClock) {
  const call = api(options);
  // this device's own cap: a relay cannot stretch a request past 10 minutes from its start
  const cap = clock.now() + PAIRING_TTL_MS;
  let deadline = cap;
  const check = () => {
    if (signal.aborted) throw new PairingError("cancelled");
    if (clock.now() >= deadline) throw new PairingError("expired");
  };
  const send = async (
    path: string,
    init: RequestInit | undefined,
    conflict: PairingErrorCode | "retry",
  ): Promise<Response | null> => {
    check();
    try {
      return await call(path, { ...init, signal });
    } catch (error) {
      if (signal.aborted) throw new PairingError("cancelled");
      if (!(error instanceof KeysError)) throw error;
      if (error.code === "offline") throw new PairingError("offline");
      if (error.code !== "server") throw error;
      if (error.status === 404) throw new Gone();
      if (error.status === 422) throw new PairingError("tampered");
      if (error.status === 409) {
        if (conflict === "retry") return null;
        throw new PairingError(conflict);
      }
      throw new PairingError("server");
    }
  };
  const post = (path: string, body: unknown, conflict: PairingErrorCode | "retry" = "server") =>
    send(
      path,
      body === undefined
        ? { method: "POST" }
        : {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify(body),
          },
      conflict,
    );
  return {
    check,
    setDeadline(expiresAt: string) {
      const at = Date.parse(expiresAt);
      deadline = Number.isNaN(at) ? cap : Math.min(at, cap);
    },
    get: async <T>(path: string): Promise<T> =>
      (await (await send(path, undefined, "server"))?.json()) as T,
    post,
    async poll<T>(id: string, step: (state: PairingState) => Promise<T | undefined>): Promise<T> {
      for (;;) {
        const state = (await (await send(`/v2/pairing/${id}`, undefined, "server"))?.json()) as
          | PairingState
          | undefined;
        if (!state) throw new PairingError("server");
        const done = await step(state);
        if (done !== undefined) return done;
        check();
        await clock.sleep(PAIRING_POLL_MS, signal);
      }
    },
  };
}

/**
 * The new device (steps 1, 4, 7, 8): makes `N`, posts its commitment and returns the code and the
 * QR. Polling starts with the first `number()` or `finish()`.
 */
export async function startPairing(options: PairingOptions): Promise<NewDevicePairing> {
  const clock = options.clock ?? realClock;
  const abort = new AbortController();
  const net = relay(options, abort.signal, clock);
  const pair = await generateDeviceKeyPair();
  const newKey = toBase64Url(pair.publicKey);
  let started: { id: string; code: string; expiresAt: string };
  try {
    const commitment = toBase64Url(await pairingCommitment(pair.publicKey));
    started = (await (await net.post("/v2/pairing", { commitment }))?.json()) as typeof started;
  } catch (error) {
    zeroPrivate(pair.privateKey);
    throw error;
  }
  net.setDeadline(started.expiresAt);
  const { id } = started;

  const number = deferred<string>();
  const ready = deferred<{ approverKey: Uint8Array }>();
  let running: Promise<void> | null = null;
  let finishing: Promise<LocalKeys> | null = null;

  const run = async () => {
    let pinned: string | null = null;
    let revealed = false;
    await net.poll(id, async (state) => {
      if (state.approverKey === null) {
        if (pinned !== null) throw new PairingError("tampered");
        return undefined;
      }
      // the first approver key seen is the one: any other later is the server's
      if (pinned === null) {
        key32(state.approverKey);
        pinned = state.approverKey;
      } else if (state.approverKey !== pinned) {
        throw new PairingError("tampered");
      }
      if (!revealed) {
        if (state.publicKey !== null) {
          // our own reveal whose answer was lost, or someone else's key
          if (state.publicKey !== newKey) throw new PairingError("tampered");
        } else {
          // 409 `not_ready`/`already_set`: look again at the next poll
          const sent = await net.post(`/v2/pairing/${id}/reveal`, { publicKey: newKey }, "retry");
          if (!sent) return undefined;
        }
        revealed = true;
        number.resolve(await pairingNumber(pair.publicKey, key32(pinned)));
      } else if (state.publicKey !== null && state.publicKey !== newKey) {
        throw new PairingError("tampered");
      }
      return state.sealed !== null ? true : undefined;
    });
    ready.resolve({ approverKey: key32(pinned as unknown as string) });
  };

  const ensureRunning = () => {
    running ??= run().catch((error) => {
      number.reject(error);
      ready.reject(error);
      zeroPrivate(pair.privateKey);
    });
  };

  const finish = async (): Promise<LocalKeys> => {
    ensureRunning();
    const { approverKey } = await ready.promise;
    try {
      const picked = (await (await net.post(`/v2/pairing/${id}/pickup`, undefined))?.json()) as {
        sealed: string;
        keyV: number;
      };
      let sealed: Uint8Array;
      try {
        sealed = fromBase64Url(picked.sealed);
      } catch {
        throw new PairingError("tampered");
      }
      let dataKey: Uint8Array;
      try {
        dataKey = await openFromPairing(
          pair.privateKey,
          { kind: "device", userId: options.userId, keyV: picked.keyV },
          sealed,
          approverKey,
        );
      } catch {
        throw new PairingError("tampered");
      }
      try {
        net.check();
        return await enrollDevice(options, dataKey, picked.keyV);
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
    qr: `wambito://pair?id=${id}&key=${newKey}`,
    expiresAt: started.expiresAt,
    number() {
      ensureRunning();
      return number.promise;
    },
    finish() {
      finishing ??= finish();
      return finishing;
    },
    cancel() {
      abort.abort();
      const error = new PairingError("cancelled");
      number.reject(error);
      ready.reject(error);
      zeroPrivate(pair.privateKey);
    },
  };
}

/**
 * The approving device (steps 2, 3, 5, 6): finds the request by its typed code or its QR, pins the
 * commitment (checked against the QR's key for a scan), makes `A` and posts `A.pub`. `bad_code`
 * for a code that cannot be one or finds nothing (404) and for a QR not exactly
 * `wambito://pair?id=<id>&key=<key>`.
 */
export async function findPairing(
  options: PairingOptions & ({ code: string } | { qr: string }),
): Promise<ApproverPairing> {
  const clock = options.clock ?? realClock;
  const abort = new AbortController();
  const net = relay(options, abort.signal, clock);

  let id: string;
  let commitment: Uint8Array;
  let qrKey: Uint8Array | null = null;
  if ("qr" in options) {
    const match = QR.exec(options.qr);
    if (!match) throw new PairingError("bad_code");
    id = match[1] as string;
    try {
      qrKey = fromBase64Url(match[2] as string);
    } catch {
      throw new PairingError("bad_code");
    }
    if (qrKey.length !== 32) throw new PairingError("bad_code");
    const state = await net.get<PairingState>(`/v2/pairing/${id}`);
    commitment = await pairingCommitment(qrKey);
    // the QR authenticates the new device: the relay's commitment must be its key's
    if (state.commitment !== toBase64Url(commitment)) throw new PairingError("tampered");
    if (state.approverKey !== null) throw new PairingError("tampered");
    net.setDeadline(state.expiresAt);
  } else {
    const code = normalizePairingCode(options.code);
    if (!CODE.test(code)) throw new PairingError("bad_code");
    let found: { id: string; commitment: string; expiresAt: string };
    try {
      found = await net.get(`/v2/pairing?code=${encodeURIComponent(code)}`);
    } catch (error) {
      if (error instanceof PairingError && error.code === "expired") {
        throw new PairingError("bad_code");
      }
      throw error;
    }
    id = found.id;
    // pinned now, before A.pub goes out; never read again
    commitment = key32(found.commitment);
    net.setDeadline(found.expiresAt);
  }

  const pair = await generateDeviceKeyPair();
  const approverKey = toBase64Url(pair.publicKey);
  try {
    // a second approver key is not ours: someone else answered this request
    await net.post(`/v2/pairing/${id}/approver`, { publicKey: approverKey }, "tampered");
  } catch (error) {
    zeroPrivate(pair.privateKey);
    throw error;
  }

  let numbering: Promise<{ number: string; newKey: Uint8Array }> | null = null;
  let approving: Promise<void> | null = null;
  /** Set once `number()` resolved on this object: the person has been shown the number. */
  let shown = false;

  const reveal = () => {
    numbering ??= (async () => {
      const newKey = await net.poll(id, async (state) => {
        if (state.approverKey !== approverKey) throw new PairingError("tampered");
        if (state.publicKey === null) return undefined;
        const key = key32(state.publicKey);
        if (!sameBytes(await pairingCommitment(key), commitment)) {
          throw new PairingError("tampered");
        }
        if (qrKey && !sameBytes(key, qrKey)) throw new PairingError("tampered");
        return key;
      });
      return { number: await pairingNumber(newKey, pair.publicKey), newKey };
    })();
    numbering.catch(() => zeroPrivate(pair.privateKey));
    return numbering;
  };

  const approve = async () => {
    const { newKey } = await reveal();
    try {
      net.check();
      await withDataKey(options, async (dataKey, keyV) => {
        const sealed = await sealToDevice(
          newKey,
          { kind: "device", userId: options.userId, keyV },
          dataKey,
          pair,
        );
        await net.post(`/v2/pairing/${id}/seal`, { sealed: toBase64Url(sealed), keyV });
      });
    } finally {
      zeroPrivate(pair.privateKey);
    }
    // done when the new device picked it up: the relay forgets the request (404)
    try {
      await net.poll(id, async () => undefined);
    } catch (error) {
      if (error instanceof Gone) return;
      throw error;
    }
  };

  return {
    async number() {
      const { number } = await reveal();
      shown = true;
      return number;
    },
    approve() {
      // the number comparison is the only check of a relayed `N` after a typed code: never seal
      // before the person could compare it
      if (!shown) return Promise.reject(new Error("approve before number"));
      approving ??= approve();
      return approving;
    },
    cancel() {
      abort.abort();
      zeroPrivate(pair.privateKey);
    },
  };
}
