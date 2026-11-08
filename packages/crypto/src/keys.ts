import { CryptoError } from "./errors.ts";

export interface RecordKeys {
  record: CryptoKey;
  dedupe: CryptoKey;
}

const encoder = new TextEncoder();
const subtle = globalThis.crypto.subtle;

export function generateDataKey(): Uint8Array {
  return globalThis.crypto.getRandomValues(new Uint8Array(32));
}

/** Both keys come from the data key by HKDF-SHA256 with an empty salt and a fixed info. */
export async function deriveRecordKeys(
  dataKey: Uint8Array,
  extractable = false,
): Promise<RecordKeys> {
  if (dataKey.length !== 32) throw new CryptoError("bad_input", "data key must be 32 bytes");
  const base = await subtle.importKey("raw", dataKey as BufferSource, "HKDF", false, ["deriveKey"]);
  const hkdf = (info: string) => ({
    name: "HKDF",
    hash: "SHA-256",
    salt: new Uint8Array(0),
    info: encoder.encode(info),
  });
  const record = await subtle.deriveKey(
    hkdf("wambito/v1/record"),
    base,
    { name: "AES-GCM", length: 256 },
    extractable,
    ["encrypt", "decrypt"],
  );
  const dedupe = await subtle.deriveKey(
    hkdf("wambito/v1/dedupe"),
    base,
    { name: "HMAC", hash: "SHA-256", length: 256 },
    extractable,
    ["sign"],
  );
  return { record, dedupe };
}
