import { type DevicePrivateKey, fromBase64Url } from "@wambito/crypto";

/**
 * What the two relays (`pairing.ts`, a new device paired from an unlocked one; `signin.ts`, a
 * signed-out browser signed in by the phone) share: the clock they poll by, one-shot promises,
 * zeroing an ephemeral private key and reading a relayed 32-byte key.
 */

export interface PairingClock {
  now(): number;
  /** Waits `ms`; may resolve early when `signal` aborts. */
  sleep(ms: number, signal: AbortSignal): Promise<void>;
}

export const realClock: PairingClock = {
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

const noop = () => {};

/** A one-shot promise whose rejection never goes unhandled (callers still see it). */
export function deferred<T>() {
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
export function zeroPrivate(key: DevicePrivateKey) {
  if (!(key instanceof CryptoKey)) key.raw.fill(0);
}

export const sameBytes = (a: Uint8Array, b: Uint8Array) =>
  a.length === b.length && a.every((x, i) => x === b[i]);

/** 32 bytes from base64url, or `onBad()` thrown for anything else the server relays. */
export function key32(text: string, onBad: () => Error): Uint8Array {
  let bytes: Uint8Array;
  try {
    bytes = fromBase64Url(text);
  } catch {
    throw onBad();
  }
  if (bytes.length !== 32) throw onBad();
  return bytes;
}

/** The `code` of a problem body, when it has one. */
export async function problemCode(response: Response): Promise<string | undefined> {
  try {
    const body = (await response.json()) as { code?: unknown };
    return typeof body.code === "string" ? body.code : undefined;
  } catch {
    return undefined;
  }
}

/** Seconds from `retry-after`, when it is a whole number of them. */
export function retryAfter(response: Response): number | undefined {
  const value = Number(response.headers.get("retry-after"));
  return Number.isInteger(value) && value >= 0 ? value : undefined;
}
