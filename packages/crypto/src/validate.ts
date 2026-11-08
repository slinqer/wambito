import { CryptoError } from "./errors.ts";

/** Only lower-case canonical UUIDs: they go byte for byte into the associated data. */
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/**
 * The account's exact id (Better Auth ids: letters, digits, `-`, `_`; case is significant). No `/`,
 * so the associated data stays unambiguous.
 */
const USER_ID = /^[A-Za-z0-9_-]{1,128}$/;

export const NONCE_BYTES = 12;

export function assertUuid(value: unknown, what: string): asserts value is string {
  if (typeof value !== "string" || !UUID.test(value)) {
    throw new CryptoError("bad_input", `${what} must be a lower-case UUID`);
  }
}

export function assertUserId(value: unknown): asserts value is string {
  if (typeof value !== "string" || !USER_ID.test(value)) {
    throw new CryptoError("bad_input", "userId must be 1 to 128 letters, digits, '-' or '_'");
  }
}

export function assertKeyV(value: unknown): asserts value is number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0 || value > 32767) {
    throw new CryptoError("bad_input", "keyV must be an integer from 0 to 32767");
  }
}

export function assertNonce(nonce: Uint8Array): void {
  if (!(nonce instanceof Uint8Array) || nonce.length !== NONCE_BYTES) {
    throw new CryptoError("bad_input", "nonce must be 12 bytes");
  }
}

export function assertBytes(
  value: unknown,
  length: number,
  what: string,
): asserts value is Uint8Array {
  if (!(value instanceof Uint8Array) || value.length !== length) {
    throw new CryptoError("bad_input", `${what} must be ${length} bytes`);
  }
}

export function randomNonce(): Uint8Array {
  return globalThis.crypto.getRandomValues(new Uint8Array(NONCE_BYTES));
}
