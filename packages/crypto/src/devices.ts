import { x25519 } from "@noble/curves/ed25519.js";
import { timingSafeEqual } from "./bytes.ts";
import { CryptoError } from "./errors.ts";
import { assertBytes, NONCE_BYTES, randomNonce } from "./validate.ts";
import {
  assertWrapContext,
  deriveWrapKey,
  gcmOpen,
  gcmSeal,
  type WrapContext,
  wrapAssociatedData,
} from "./wraps.ts";

const subtle = globalThis.crypto.subtle;
const KEY_BYTES = 32;

type Backend = "native" | "noble";
let forced: Backend | null = null;
let detected: Promise<Backend> | null = null;

/** Test hook (not exported from the package): force one X25519 path, or null to detect again. */
export function __forceX25519Backend(mode: Backend | null): void {
  forced = mode;
}

function backend(): Promise<Backend> {
  if (forced) return Promise.resolve(forced);
  detected ??= subtle
    .generateKey({ name: "X25519" }, false, ["deriveBits"])
    .then((): Backend => "native")
    .catch((): Backend => "noble");
  return detected;
}

/**
 * A device private key. Normally a non-extractable WebCrypto `CryptoKey`. Only where WebCrypto
 * lacks X25519 (`@noble/curves` fallback) it is the raw 32-byte scalar in a plain object: that
 * form survives structured clone (IndexedDB) but is NOT protected, so the web must treat it as a
 * raw secret.
 */
export type DevicePrivateKey = CryptoKey | { kind: "noble-x25519"; raw: Uint8Array };

function nobleKey(raw: Uint8Array): DevicePrivateKey {
  return { kind: "noble-x25519", raw };
}

function rawOf(key: unknown): Uint8Array | undefined {
  if (typeof CryptoKey !== "undefined" && key instanceof CryptoKey) return undefined;
  const k = key as { kind?: unknown; raw?: unknown } | null;
  if (k && typeof k === "object" && k.kind === "noble-x25519" && k.raw instanceof Uint8Array) {
    return k.raw.length === KEY_BYTES ? k.raw : undefined;
  }
  throw new CryptoError("bad_input", "not a device private key");
}

const PKCS8_X25519_PREFIX = Uint8Array.from([
  0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x04, 0x22, 0x04, 0x20,
]);

/** A non-extractable X25519 private key from its 32 raw bytes (for test vectors and the Dart port). */
export async function importDevicePrivateKey(raw: Uint8Array): Promise<DevicePrivateKey> {
  assertBytes(raw, KEY_BYTES, "private key");
  if ((await backend()) === "noble") return nobleKey(raw.slice());
  const pkcs8 = new Uint8Array(PKCS8_X25519_PREFIX.length + KEY_BYTES);
  pkcs8.set(PKCS8_X25519_PREFIX);
  pkcs8.set(raw, PKCS8_X25519_PREFIX.length);
  return subtle.importKey("pkcs8", pkcs8, { name: "X25519" }, false, ["deriveBits"]);
}

export async function generateDeviceKeyPair(): Promise<{
  publicKey: Uint8Array;
  privateKey: DevicePrivateKey;
}> {
  if ((await backend()) === "noble") {
    const secret = x25519.utils.randomSecretKey();
    return { publicKey: x25519.getPublicKey(secret), privateKey: nobleKey(secret) };
  }
  const pair = (await subtle.generateKey({ name: "X25519" }, false, [
    "deriveBits",
  ])) as CryptoKeyPair;
  const publicKey = new Uint8Array(await subtle.exportKey("raw", pair.publicKey));
  return { publicKey, privateKey: pair.privateKey };
}

/** X25519 shared secret of a private key (either kind) and a raw public key. */
async function ecdh(privateKey: DevicePrivateKey, publicKey: Uint8Array): Promise<Uint8Array> {
  const raw = rawOf(privateKey);
  if (raw) return x25519.getSharedSecret(raw, publicKey);
  if (!(privateKey instanceof CryptoKey))
    throw new CryptoError("bad_input", "not a device private key");
  const pub = await subtle.importKey(
    "raw",
    publicKey as BufferSource,
    { name: "X25519" },
    false,
    [],
  );
  return new Uint8Array(
    await subtle.deriveBits({ name: "X25519", public: pub }, privateKey, KEY_BYTES * 8),
  );
}

/**
 * Sealed = ephemeral public key (32) || nonce (12) || AES-256-GCM ciphertext and tag. The ephemeral
 * pair is made here unless the caller passes one (pairing: the approver's key behind the number).
 */
export async function sealToDevice(
  publicKey: Uint8Array,
  ctx: WrapContext,
  dataKey: Uint8Array,
  ephemeral?: { publicKey: Uint8Array; privateKey: DevicePrivateKey },
): Promise<Uint8Array> {
  assertBytes(publicKey, KEY_BYTES, "public key");
  assertBytes(dataKey, 32, "data key");
  assertWrapContext(ctx);
  if (ctx.kind !== "device") throw new CryptoError("bad_input", "kind must be device");
  const aad = wrapAssociatedData(ctx);
  if (ephemeral) assertBytes(ephemeral.publicKey, KEY_BYTES, "ephemeral public key");
  const eph = ephemeral ?? (await generateDeviceKeyPair());
  let shared: Uint8Array;
  try {
    shared = await ecdh(eph.privateKey, publicKey);
  } catch {
    throw new CryptoError("bad_input", "not a valid public key");
  }
  const sealed = await gcmSeal(await deriveWrapKey(shared, "device"), aad, dataKey, randomNonce());
  const out = new Uint8Array(KEY_BYTES + sealed.length);
  out.set(eph.publicKey);
  out.set(sealed, KEY_BYTES);
  return out;
}

export async function openFromDevice(
  privateKey: DevicePrivateKey,
  ctx: WrapContext,
  sealed: Uint8Array,
): Promise<Uint8Array> {
  assertWrapContext(ctx);
  if (ctx.kind !== "device") throw new CryptoError("bad_input", "kind must be device");
  const aad = wrapAssociatedData(ctx);
  if (sealed.length < KEY_BYTES + NONCE_BYTES) throw new CryptoError("cannot_open");
  try {
    const shared = await ecdh(privateKey, sealed.slice(0, KEY_BYTES));
    const dataKey = await gcmOpen(
      await deriveWrapKey(shared, "device"),
      aad,
      sealed.slice(KEY_BYTES),
    );
    if (dataKey.length !== 32) throw new CryptoError("cannot_open");
    return dataKey;
  } catch (e) {
    if (e instanceof CryptoError && e.code === "bad_input") throw e;
    throw new CryptoError("cannot_open");
  }
}

/**
 * `openFromDevice` for pairing: refuses (`cannot_open`) a blob whose first 32 bytes, the ephemeral
 * key, are not the approver key both devices saw behind the number.
 */
export async function openFromPairing(
  privateKey: DevicePrivateKey,
  ctx: WrapContext,
  sealed: Uint8Array,
  approverKey: Uint8Array,
): Promise<Uint8Array> {
  assertBytes(approverKey, KEY_BYTES, "approver key");
  if (!(sealed instanceof Uint8Array)) throw new CryptoError("bad_input", "sealed must be bytes");
  if (!timingSafeEqual(sealed.slice(0, KEY_BYTES), approverKey))
    throw new CryptoError("cannot_open");
  return openFromDevice(privateKey, ctx, sealed);
}
