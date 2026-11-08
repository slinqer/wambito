import { CROCKFORD } from "./recovery.ts";
import { assertBytes } from "./validate.ts";

const subtle = globalThis.crypto.subtle;

/** 8 Crockford base32 characters the new device shows and the signed-in device types in. */
export function pairingCode(): string {
  const bytes = globalThis.crypto.getRandomValues(new Uint8Array(8));
  let code = "";
  for (const b of bytes) code += CROCKFORD[b & 31]; // 256 is a multiple of 32: no bias
  return code;
}

function compare(a: Uint8Array, b: Uint8Array): number {
  for (let i = 0; i < a.length; i++) {
    const d = (a[i] ?? 0) - (b[i] ?? 0);
    if (d !== 0) return d;
  }
  return 0;
}

/**
 * Six digits both devices show, from SHA-256("wambito/v1/pairing" || the two public keys sorted),
 * so the number is the same from either side and a swapped key shows a different one.
 * Async because WebCrypto digests are.
 */
export async function pairingNumber(a: Uint8Array, b: Uint8Array): Promise<string> {
  assertBytes(a, 32, "public key");
  assertBytes(b, 32, "public key");
  const [first, second] = compare(a, b) <= 0 ? [a, b] : [b, a];
  const label = new TextEncoder().encode("wambito/v1/pairing");
  const input = new Uint8Array(label.length + 64);
  input.set(label);
  input.set(first, label.length);
  input.set(second, label.length + 32);
  const hash = new Uint8Array(await subtle.digest("SHA-256", input));
  const n = new DataView(hash.buffer).getUint32(0) % 1_000_000;
  return String(n).padStart(6, "0");
}

/**
 * The new device's commitment: SHA-256("wambito/v1/pairing-commit" || its public key). It sends this
 * first and reveals the key last, so the server cannot choose the approver key after seeing it.
 */
export async function pairingCommitment(publicKey: Uint8Array): Promise<Uint8Array> {
  assertBytes(publicKey, 32, "public key");
  const label = new TextEncoder().encode("wambito/v1/pairing-commit");
  const input = new Uint8Array(label.length + 32);
  input.set(label);
  input.set(publicKey, label.length);
  return new Uint8Array(await subtle.digest("SHA-256", input));
}
