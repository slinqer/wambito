import { CryptoError } from "./errors.ts";
import {
  assertBytes,
  assertKeyV,
  assertNonce,
  assertUuid,
  NONCE_BYTES,
  randomNonce,
} from "./validate.ts";

export type WrapKind = "passkey" | "recovery" | "device" | "assistant";

export interface WrapContext {
  kind: WrapKind;
  userId: string;
  keyV: number;
}

const KINDS: readonly string[] = ["passkey", "recovery", "device", "assistant"];
const encoder = new TextEncoder();
const subtle = globalThis.crypto.subtle;

/** SHA-256("wambito/v1/prf"): the same salt for every passkey (a test checks it against WebCrypto). */
export const PRF_SALT: Uint8Array = Uint8Array.from(
  "999d11fd4d3213d08d6d21fd1e08fa663b32f6c21c4d60374015461bfcfdbedb".match(/../g) ?? [],
  (h) => Number.parseInt(h, 16),
);

export function assertWrapContext(ctx: WrapContext): void {
  if (!KINDS.includes(ctx.kind)) throw new CryptoError("bad_input", "unknown wrap kind");
  assertUuid(ctx.userId, "userId");
  assertKeyV(ctx.keyV);
}

export function wrapAssociatedData(ctx: WrapContext): Uint8Array {
  assertWrapContext(ctx);
  return encoder.encode(`wambito/v1/wrap/${ctx.kind}/${ctx.userId}/${ctx.keyV}`);
}

/** HKDF-SHA256 (empty salt) from a secret to an AES-256-GCM key, info `wambito/v1/wrap/<kind>`. */
export async function deriveWrapKey(secret: Uint8Array, kind: WrapKind): Promise<CryptoKey> {
  const base = await subtle.importKey("raw", secret as BufferSource, "HKDF", false, ["deriveKey"]);
  return subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: new Uint8Array(0),
      info: encoder.encode(`wambito/v1/wrap/${kind}`),
    },
    base,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

export async function gcmSeal(
  key: CryptoKey,
  aad: Uint8Array,
  plain: Uint8Array,
  nonce: Uint8Array,
): Promise<Uint8Array> {
  const ct = await subtle.encrypt(
    { name: "AES-GCM", iv: nonce as BufferSource, additionalData: aad as BufferSource },
    key,
    plain as BufferSource,
  );
  const out = new Uint8Array(NONCE_BYTES + ct.byteLength);
  out.set(nonce);
  out.set(new Uint8Array(ct), NONCE_BYTES);
  return out;
}

export async function gcmOpen(
  key: CryptoKey,
  aad: Uint8Array,
  wrapped: Uint8Array,
): Promise<Uint8Array> {
  try {
    const plain = await subtle.decrypt(
      {
        name: "AES-GCM",
        iv: wrapped.slice(0, NONCE_BYTES) as BufferSource,
        additionalData: aad as BufferSource,
      },
      key,
      wrapped.slice(NONCE_BYTES),
    );
    return new Uint8Array(plain);
  } catch {
    throw new CryptoError("cannot_open");
  }
}

function checkSecretWrap(secret: Uint8Array, ctx: WrapContext): Uint8Array {
  const aad = wrapAssociatedData(ctx);
  if (ctx.kind === "device") {
    throw new CryptoError("bad_input", "device wraps use sealToDevice");
  }
  if (!(secret instanceof Uint8Array) || secret.length === 0) {
    throw new CryptoError("bad_input", "secret must not be empty");
  }
  return aad;
}

/**
 * Wraps the data key under a secret (passkey PRF output, recovery secret or `S`).
 * Result = nonce (12) || AES-256-GCM ciphertext and tag. `nonce` is only for test vectors.
 */
export async function wrapDataKey(
  secret: Uint8Array,
  ctx: WrapContext,
  dataKey: Uint8Array,
  nonce: Uint8Array = randomNonce(),
): Promise<Uint8Array> {
  const aad = checkSecretWrap(secret, ctx);
  assertBytes(dataKey, 32, "data key");
  assertNonce(nonce);
  return gcmSeal(await deriveWrapKey(secret, ctx.kind), aad, dataKey, nonce);
}

export async function unwrapDataKey(
  secret: Uint8Array,
  ctx: WrapContext,
  wrapped: Uint8Array,
): Promise<Uint8Array> {
  const aad = checkSecretWrap(secret, ctx);
  const key = await deriveWrapKey(secret, ctx.kind);
  const dataKey = await gcmOpen(key, aad, wrapped);
  if (dataKey.length !== 32) throw new CryptoError("cannot_open");
  return dataKey;
}
