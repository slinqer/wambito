import { CryptoError } from "./errors.ts";
import { assertBytes, assertKeyV, assertNonce, assertUserId, randomNonce } from "./validate.ts";
import { gcmOpen, gcmSeal } from "./wraps.ts";

const subtle = globalThis.crypto.subtle;
const encoder = new TextEncoder();

/** nonce (12) || AES-256-GCM(older data key, 32) with its tag (16). */
export const LINK_BYTES = 60;

export interface LinkContext {
  userId: string;
  /** The newer version (the one whose key seals the link); at least 2. */
  keyV: number;
}

function checkContext(ctx: LinkContext): Uint8Array {
  assertUserId(ctx.userId);
  assertKeyV(ctx.keyV);
  if (ctx.keyV < 2) throw new CryptoError("bad_input", "keyV of a link must be at least 2");
  return encoder.encode(`wambito/v1/link/${ctx.userId}/${ctx.keyV}`);
}

/** HKDF-SHA256 (empty salt) from the newer data key to an AES-256-GCM key, info `wambito/v1/link`. */
async function deriveLinkKey(newKey: Uint8Array): Promise<CryptoKey> {
  const base = await subtle.importKey("raw", newKey as BufferSource, "HKDF", false, ["deriveKey"]);
  return subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: new Uint8Array(0),
      info: encoder.encode("wambito/v1/link"),
    },
    base,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

/** Seals the older data key under a key derived from the newer one. 60 bytes. */
export async function sealKeyLink(
  newKey: Uint8Array,
  oldKey: Uint8Array,
  ctx: LinkContext,
  nonce: Uint8Array = randomNonce(),
): Promise<Uint8Array> {
  assertBytes(newKey, 32, "new key");
  assertBytes(oldKey, 32, "old key");
  const aad = checkContext(ctx);
  assertNonce(nonce);
  return gcmSeal(await deriveLinkKey(newKey), aad, oldKey, nonce);
}

/** Opens a link with the newer data key; returns the older one. Throws `CryptoError` on failure. */
export async function openKeyLink(
  newKey: Uint8Array,
  ctx: LinkContext,
  link: Uint8Array,
): Promise<Uint8Array> {
  assertBytes(newKey, 32, "new key");
  const aad = checkContext(ctx);
  assertBytes(link, LINK_BYTES, "link");
  const oldKey = await gcmOpen(await deriveLinkKey(newKey), aad, link);
  if (oldKey.length !== 32) throw new CryptoError("cannot_open");
  return oldKey;
}
