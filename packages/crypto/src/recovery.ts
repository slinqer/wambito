import { CryptoError } from "./errors.ts";
import { assertBytes } from "./validate.ts";

/** Crockford base32 (no I, L, O, U) and its five extra check symbols. */
export const CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const CHECK_ALPHABET = `${CROCKFORD}*~$=U`;
const DATA_CHARS = 26;

export function newRecoverySecret(): Uint8Array {
  return globalThis.crypto.getRandomValues(new Uint8Array(16));
}

function toBigInt(bytes: Uint8Array): bigint {
  let n = 0n;
  for (const b of bytes) n = (n << 8n) | BigInt(b);
  return n;
}

/** 128 bits as 26 base32 characters (the last one carries 3 data bits and 2 zero bits) + check. */
export function formatRecoveryKey(secret: Uint8Array): string {
  assertBytes(secret, 16, "recovery secret");
  const value = toBigInt(secret);
  const padded = value << 2n; // 130 bits
  let text = "";
  for (let i = DATA_CHARS - 1; i >= 0; i--) {
    text += CROCKFORD[Number((padded >> BigInt(i * 5)) & 31n)];
  }
  text += CHECK_ALPHABET[Number(value % 37n)];
  return text.match(/.{1,4}/g)?.join("-") ?? text;
}

export function parseRecoveryKey(input: string): Uint8Array {
  const bad = () => new CryptoError("bad_recovery_key", "that recovery key is not valid");
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
  if (CHECK_ALPHABET.indexOf(text[DATA_CHARS] as string) !== Number(value % 37n)) throw bad();
  const out = new Uint8Array(16);
  for (let i = 15; i >= 0; i--) {
    out[i] = Number((value >> BigInt((15 - i) * 8)) & 255n);
  }
  return out;
}
