import { timingSafeEqual } from "./bytes.ts";
import { assertBytes, assertUserId, assertUuid } from "./validate.ts";

const subtle = globalThis.crypto.subtle;
const encoder = new TextEncoder();

export interface DeviceAttestationInput {
  userId: string;
  wrapId: string;
  publicKey: Uint8Array;
}

/**
 * HMAC-SHA256 under HKDF-SHA256(DK, empty salt, "wambito/v1/device-attest") of
 * utf8(userId) || 0x00 || utf8(wrapId) || 0x00 || publicKey. 32 bytes.
 */
export async function deviceAttestation(
  dataKey: Uint8Array,
  input: DeviceAttestationInput,
): Promise<Uint8Array> {
  assertBytes(dataKey, 32, "data key");
  assertUserId(input.userId);
  assertUuid(input.wrapId, "wrapId");
  assertBytes(input.publicKey, 32, "public key");
  const base = await subtle.importKey("raw", dataKey as BufferSource, "HKDF", false, ["deriveKey"]);
  const key = await subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: new Uint8Array(0),
      info: encoder.encode("wambito/v1/device-attest"),
    },
    base,
    { name: "HMAC", hash: "SHA-256", length: 256 },
    false,
    ["sign"],
  );
  const user = encoder.encode(input.userId);
  const wrap = encoder.encode(input.wrapId);
  const msg = new Uint8Array(user.length + 1 + wrap.length + 1 + 32);
  msg.set(user);
  msg.set(wrap, user.length + 1);
  msg.set(input.publicKey, user.length + 1 + wrap.length + 1);
  return new Uint8Array(await subtle.sign("HMAC", key, msg));
}

export async function verifyDeviceAttestation(
  dataKey: Uint8Array,
  input: DeviceAttestationInput,
  attestation: Uint8Array,
): Promise<boolean> {
  if (!(attestation instanceof Uint8Array) || attestation.length !== 32) return false;
  return timingSafeEqual(await deviceAttestation(dataKey, input), attestation);
}
