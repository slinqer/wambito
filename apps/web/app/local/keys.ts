import {
  type DevicePrivateKey,
  deriveRecordKeys,
  deviceAttestation,
  formatRecoveryKey,
  fromBase64Url,
  generateDataKey,
  generateDeviceKeyPair,
  newRecoverySecret,
  parseRecoveryKey,
  type RecordKeys,
  sealToDevice,
  toBase64Url,
  unwrapDataKey,
  wrapDataKey,
} from "@wambito/crypto";
import { deleteVault } from "./db.ts";
import { createEncryptedStore, type EncryptedStore } from "./encrypted-store.ts";
import { uuidv7 } from "./ids.ts";

/**
 * Keys on the web (spec 2026-11-08 sections 4.1, 5.2, 7.1, 7.2, 7.4). This browser keeps only the
 * record and dedupe `CryptoKey`s (non-extractable) and its device private key, in the vault's
 * `keys` store; the data key DK lives in memory during setup or unlock and is dropped after.
 * All network goes through an injected `fetch` against `baseUrl` (`/api`).
 */

export type KeysErrorCode =
  | "already_set_up"
  | "bad_recovery_key"
  | "wrong_recovery_key"
  | "offline"
  | "server";

export class KeysError extends Error {
  constructor(
    readonly code: KeysErrorCode,
    readonly status?: number,
  ) {
    super(code);
    this.name = "KeysError";
  }
}

/** The names under which the vault's `keys` store keeps them. */
export const RECORD_KEY = "record";
export const DEDUPE_KEY = "dedupe";
export const DEVICE_KEY = "device";
/** The key version a new account starts at. */
export const FIRST_KEY_V = 1;
const DEVICE_LABEL = "Web";

export interface KeysOptions {
  userId: string;
  /** Defaults to the global `fetch`. */
  fetch?: typeof globalThis.fetch;
  baseUrl?: string;
}

export interface LocalKeys {
  keys: RecordKeys;
  keyV: number;
}

interface WrapDto {
  id: string;
  kind: string;
  keyV: number;
  wrapped: string;
}

function api(options: KeysOptions) {
  const baseUrl = options.baseUrl ?? "/api";
  return async (path: string, init?: RequestInit): Promise<Response> => {
    let response: Response;
    try {
      response = await (options.fetch ?? fetch)(`${baseUrl}${path}`, init);
    } catch {
      throw new KeysError("offline");
    }
    if (!response.ok) throw new KeysError("server", response.status);
    return response;
  };
}

async function listWraps(call: ReturnType<typeof api>): Promise<WrapDto[]> {
  const body = (await (await call("/v2/keys")).json()) as { wraps: WrapDto[] };
  return body.wraps;
}

const putJson = (body: unknown): RequestInit => ({
  method: "PUT",
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

/**
 * Adds this browser as a device: a key pair, a wrap of DK sealed to its own public key with an
 * attestation of that key under DK, then the derived keys and the private key kept locally.
 */
async function enrollDevice(
  call: ReturnType<typeof api>,
  userId: string,
  dataKey: Uint8Array,
  keyV: number,
): Promise<LocalKeys> {
  const pair = await generateDeviceKeyPair();
  const id = uuidv7();
  const wrapped = await sealToDevice(pair.publicKey, { kind: "device", userId, keyV }, dataKey);
  const attestation = await deviceAttestation(dataKey, {
    userId,
    wrapId: id,
    publicKey: pair.publicKey,
  });
  await call(
    `/v2/keys/${id}`,
    putJson({
      kind: "device",
      ref: id,
      keyV,
      wrapped: toBase64Url(wrapped),
      publicKey: toBase64Url(pair.publicKey),
      attestation: toBase64Url(attestation),
      label: DEVICE_LABEL,
    }),
  );
  return keepLocally(userId, dataKey, keyV, pair.privateKey);
}

async function keepLocally(
  userId: string,
  dataKey: Uint8Array,
  keyV: number,
  devicePrivateKey: DevicePrivateKey,
): Promise<LocalKeys> {
  const keys = await deriveRecordKeys(dataKey, false);
  const store = await createEncryptedStore(userId);
  try {
    await store.putKey(RECORD_KEY, keys.record);
    await store.putKey(DEDUPE_KEY, keys.dedupe);
    await store.putKey(DEVICE_KEY, devicePrivateKey);
    await store.setMeta("keyV", keyV);
    await store.setMeta("userId", userId);
  } finally {
    store.close();
  }
  return { keys, keyV };
}

/**
 * First run of an account: DK, the recovery secret and this device's key pair. The recovery wrap
 * goes first (the server refuses any other kind first), then the device wrap. A guest has no
 * recovery key to show (spec section 10): its recovery secret is thrown away unseen, which still
 * satisfies the server's first-wrap rule; turning the guest into a real account later replaces
 * that wrap with a recovery key the person keeps. Throws `already_set_up` when the account has
 * wraps: the caller shows Unlock.
 */
export async function setUpAccount(
  options: KeysOptions & { guest: boolean },
): Promise<{ recoveryKey: string | null }> {
  const { userId, guest } = options;
  const call = api(options);
  if ((await listWraps(call)).length > 0) throw new KeysError("already_set_up");

  const dataKey = generateDataKey();
  const secret = newRecoverySecret();
  const wrapped = await wrapDataKey(
    secret,
    { kind: "recovery", userId, keyV: FIRST_KEY_V },
    dataKey,
  );
  await call(
    `/v2/keys/${uuidv7()}`,
    putJson({ kind: "recovery", keyV: FIRST_KEY_V, wrapped: toBase64Url(wrapped) }),
  );
  await enrollDevice(call, userId, dataKey, FIRST_KEY_V);
  dataKey.fill(0);
  return { recoveryKey: guest ? null : formatRecoveryKey(secret) };
}

/**
 * Unlocks this browser with the typed recovery key: opens the recovery wrap, enrolls this device
 * and keeps the derived keys. The caller then runs a full sync. `bad_recovery_key` is a key that
 * does not parse (nothing was sent); `wrong_recovery_key` one that parses but opens nothing.
 */
export async function unlockWithRecovery(
  options: KeysOptions & { text: string },
): Promise<LocalKeys> {
  const { userId, text } = options;
  let secret: Uint8Array;
  try {
    secret = parseRecoveryKey(text);
  } catch {
    throw new KeysError("bad_recovery_key");
  }
  const call = api(options);
  const wrap = (await listWraps(call)).find((w) => w.kind === "recovery");
  if (!wrap) throw new KeysError("wrong_recovery_key");
  let dataKey: Uint8Array;
  try {
    dataKey = await unwrapDataKey(
      secret,
      { kind: "recovery", userId, keyV: wrap.keyV },
      fromBase64Url(wrap.wrapped),
    );
  } catch {
    throw new KeysError("wrong_recovery_key");
  }
  try {
    return await enrollDevice(call, userId, dataKey, wrap.keyV);
  } finally {
    dataKey.fill(0);
  }
}

/** The keys this browser kept, or `null` when it was never set up (the app is locked). */
export async function loadLocalKeys(userId: string): Promise<LocalKeys | null> {
  const store: EncryptedStore = await createEncryptedStore(userId);
  try {
    const record = await store.getKey<CryptoKey>(RECORD_KEY);
    const dedupe = await store.getKey<CryptoKey>(DEDUPE_KEY);
    const keyV = await store.getMeta<number>("keyV");
    if (!record || !dedupe || keyV === undefined) return null;
    return { keys: { record, dedupe }, keyV };
  } finally {
    store.close();
  }
}

/** Signing out: deletes this browser's database, keys included. */
export function forgetDevice(userId: string): Promise<void> {
  return deleteVault(userId);
}
