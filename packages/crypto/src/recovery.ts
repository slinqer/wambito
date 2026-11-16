import { CryptoError } from "./errors.ts";
import { assertBytes } from "./validate.ts";

const subtle = globalThis.crypto.subtle;
const encoder = new TextEncoder();

export const RECOVERY_LOOKUP_INFO = "wambito/v1/recovery/lookup";
export const RECOVERY_AUTH_INFO = "wambito/v1/recovery/auth";

/** What the server stores (as SHA-256 hashes) to let a recovery key sign in without the data key. */
export interface RecoveryVerifier {
  /** 16 bytes: finds the verifier row. */
  lookup: Uint8Array;
  /** 32 bytes: proves the person holds the recovery key. */
  auth: Uint8Array;
}

async function hkdfBits(secret: Uint8Array, info: string, bits: number): Promise<Uint8Array> {
  const base = await subtle.importKey("raw", secret as BufferSource, "HKDF", false, ["deriveBits"]);
  return new Uint8Array(
    await subtle.deriveBits(
      { name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info: encoder.encode(info) },
      base,
      bits,
    ),
  );
}

/**
 * HKDF-SHA256 (empty salt) of the 16-byte recovery secret under two infos, different from the wrap
 * info, so what the server sees never opens the recovery wrap.
 */
export async function recoveryVerifier(secret: Uint8Array): Promise<RecoveryVerifier> {
  assertBytes(secret, 16, "recovery secret");
  return {
    lookup: await hkdfBits(secret, RECOVERY_LOOKUP_INFO, 128),
    auth: await hkdfBits(secret, RECOVERY_AUTH_INFO, 256),
  };
}

/** SHA-256 of verifier bytes: what the server stores as `lookup_hash` and `auth_hash`. */
export async function verifierHash(bytes: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await subtle.digest("SHA-256", bytes as BufferSource));
}

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
