import { CryptoError } from "./errors.ts";
import { assertBytes } from "./validate.ts";

/** Crockford base32 (no I, L, O, U). */
export const CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const DATA_CHARS = 26;

export function newRecoverySecret(): Uint8Array {
  return globalThis.crypto.getRandomValues(new Uint8Array(16));
}

function toBigInt(bytes: Uint8Array): bigint {
  let n = 0n;
  for (const b of bytes) n = (n << 8n) | BigInt(b);
  return n;
}

/**
 * Luhn mod N check character (N = 32, code points = index in the Crockford alphabet) over the 26
 * data characters. It is always alphanumeric, catches every single-character error and almost
 * every swap of two adjacent characters.
 */
function luhnCheck(data: string): string {
  let factor = 2;
  let sum = 0;
  for (let i = data.length - 1; i >= 0; i--) {
    const addend = factor * CROCKFORD.indexOf(data[i] as string);
    factor = factor === 2 ? 1 : 2;
    sum += Math.floor(addend / 32) + (addend % 32);
  }
  return CROCKFORD[(32 - (sum % 32)) % 32] as string;
}

/**
 * 128 bits as 26 base32 characters (the last one carries 3 data bits and 2 zero bits) plus a
 * Luhn mod 32 check character, in groups of four.
 */
export function formatRecoveryKey(secret: Uint8Array): string {
  assertBytes(secret, 16, "recovery secret");
  const value = toBigInt(secret);
  const padded = value << 2n; // 130 bits
  let text = "";
  for (let i = DATA_CHARS - 1; i >= 0; i--) {
    text += CROCKFORD[Number((padded >> BigInt(i * 5)) & 31n)];
  }
  text += luhnCheck(text);
  return text.match(/.{1,4}/g)?.join("-") ?? text;
}

export function parseRecoveryKey(input: string): Uint8Array {
  const bad = () => new CryptoError("bad_recovery_key", "that recovery key is not valid");
  if (typeof input !== "string") throw bad();
  const text = input
    .replace(/[\s-]+/g, "")
    .toUpperCase()
    .replace(/[IL]/g, "1")
    .replace(/O/g, "0");
  if (text.length !== DATA_CHARS + 1) throw bad();
  let padded = 0n;
  for (let i = 0; i < DATA_CHARS; i++) {
    const v = CROCKFORD.indexOf(text[i] as string);
    if (v < 0) throw bad();
    padded = (padded << 5n) | BigInt(v);
  }
  if ((padded & 3n) !== 0n) throw bad();
  const value = padded >> 2n;
  if (luhnCheck(text.slice(0, DATA_CHARS)) !== text[DATA_CHARS]) throw bad();
  const out = new Uint8Array(16);
  for (let i = 15; i >= 0; i--) {
    out[i] = Number((value >> BigInt((15 - i) * 8)) & 255n);
  }
  return out;
}
