import { toBase64Url } from "./bytes.ts";
import { CryptoError } from "./errors.ts";
import type { RecordKeys } from "./keys.ts";
import {
  assertKeyV,
  assertNonce,
  assertUserId,
  assertUuid,
  NONCE_BYTES,
  randomNonce,
} from "./validate.ts";

export type RecordType =
  | "transaction"
  | "category"
  | "budget"
  | "recurrence"
  | "merchant"
  | "settings"
  | "account";

export interface RecordContext {
  userId: string;
  type: RecordType;
  id: string;
  keyV: number;
}

const RECORD_TYPES: readonly string[] = [
  "transaction",
  "category",
  "budget",
  "recurrence",
  "merchant",
  "settings",
  "account",
];
const PAD_TO = 64;
const subtle = globalThis.crypto.subtle;

function associatedData(ctx: RecordContext): Uint8Array {
  assertUserId(ctx.userId);
  assertUuid(ctx.id, "id");
  assertKeyV(ctx.keyV);
  if (!RECORD_TYPES.includes(ctx.type)) throw new CryptoError("bad_input", "unknown record type");
  return new TextEncoder().encode(
    `wambito/v1/record/${ctx.userId}/${ctx.type}/${ctx.id}/${ctx.keyV}`,
  );
}

/**
 * body = nonce (12) || AES-256-GCM ciphertext and tag, over JSON padded with spaces to 64 bytes.
 * `nonce` is only for test vectors: leave it out so a fresh random one is used.
 */
export async function sealRecord(
  keys: RecordKeys,
  ctx: RecordContext,
  value: unknown,
  nonce: Uint8Array = randomNonce(),
): Promise<Uint8Array> {
  const aad = associatedData(ctx);
  assertNonce(nonce);
  const text = JSON.stringify(value);
  if (text === undefined) throw new CryptoError("bad_input", "value is not JSON");
  const json = new TextEncoder().encode(text);
  const plain = new Uint8Array(Math.ceil(json.length / PAD_TO) * PAD_TO).fill(0x20);
  plain.set(json);
  const sealed = await subtle.encrypt(
    {
      name: "AES-GCM",
      iv: nonce as BufferSource,
      additionalData: aad as BufferSource,
    },
    keys.record,
    plain,
  );
  const body = new Uint8Array(NONCE_BYTES + sealed.byteLength);
  body.set(nonce);
  body.set(new Uint8Array(sealed), NONCE_BYTES);
  return body;
}

export async function openRecord(
  keys: RecordKeys,
  ctx: RecordContext,
  body: Uint8Array,
): Promise<unknown> {
  const aad = associatedData(ctx);
  try {
    const plain = await subtle.decrypt(
      {
        name: "AES-GCM",
        iv: body.slice(0, NONCE_BYTES) as BufferSource,
        additionalData: aad as BufferSource,
      },
      keys.record,
      body.slice(NONCE_BYTES),
    );
    return JSON.parse(new TextDecoder().decode(plain));
  } catch {
    throw new CryptoError("cannot_open");
  }
}

/** Stable keyed tag of a text (base64url HMAC-SHA256), for server-side duplicate detection. */
export async function dedupeTag(keys: RecordKeys, text: string): Promise<string> {
  const mac = await subtle.sign("HMAC", keys.dedupe, new TextEncoder().encode(text));
  return toBase64Url(new Uint8Array(mac));
}
