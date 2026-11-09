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
  | "server"
  /** WebCrypto lacks X25519: the device key would be raw bytes, which the web never stores. */
  | "unsupported_browser"
  /** The signed-in account is not this vault's (409): the app reloads for the new one. */
  | "session_changed";

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
  /** Makes the device key pair; tests pass the noble fallback's shape. */
  deviceKeyPair?: typeof generateDeviceKeyPair;
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
      // Names the vault's account: a cookie that now belongs to someone else gets a 409.
      response = await (options.fetch ?? fetch)(`${baseUrl}${path}`, {
        ...init,
        headers: {
          ...(init?.headers as Record<string, string> | undefined),
          "x-wambito-user": options.userId,
        },
      });
    } catch {
      throw new KeysError("offline");
    }
    if (!response.ok) {
      const code = await problemCode(response);
      if (response.status === 409 && code === "already_set_up") {
        throw new KeysError("already_set_up", 409);
      }
      if (response.status === 409 && code === "session_changed") {
        throw new KeysError("session_changed", 409);
      }
      throw new KeysError("server", response.status);
    }
    return response;
  };
}

async function problemCode(response: Response): Promise<string | undefined> {
  try {
    const body = (await response.json()) as { code?: unknown };
    return typeof body.code === "string" ? body.code : undefined;
  } catch {
    return undefined;
  }
}

/**
 * A device key pair this browser can keep: the private key must be a non-extractable `CryptoKey`.
 * Without X25519 in WebCrypto, `@wambito/crypto` falls back to raw bytes, which would sit in
 * IndexedDB readable by any script: refused (`unsupported_browser`), nothing is stored or sent.
 */
async function safeDeviceKeyPair(options: KeysOptions) {
  const pair = await (options.deviceKeyPair ?? generateDeviceKeyPair)();
  if (!(pair.privateKey instanceof CryptoKey)) throw new KeysError("unsupported_browser");
  return pair;
}

async function listWraps(call: ReturnType<typeof api>): Promise<WrapDto[]> {
  const body = (await (await call("/v2/keys")).json()) as { wraps: WrapDto[] };
  return body.wraps;
}

const putJson = (body: unknown, headers: Record<string, string> = {}): RequestInit => ({
  method: "PUT",
  headers: { "content-type": "application/json", ...headers },
  body: JSON.stringify(body),
});

/** A device key pair and its wrap of DK, made in memory; nothing sent yet. */
async function prepareDevice(
  userId: string,
  dataKey: Uint8Array,
  keyV: number,
  pair: Awaited<ReturnType<typeof generateDeviceKeyPair>>,
) {
  const id = uuidv7();
  const wrapped = await sealToDevice(pair.publicKey, { kind: "device", userId, keyV }, dataKey);
  const attestation = await deviceAttestation(dataKey, {
    userId,
    wrapId: id,
    publicKey: pair.publicKey,
  });
  return {
    id,
    privateKey: pair.privateKey,
    body: {
      kind: "device",
      ref: id,
      keyV,
      wrapped: toBase64Url(wrapped),
      publicKey: toBase64Url(pair.publicKey),
      attestation: toBase64Url(attestation),
      label: DEVICE_LABEL,
    },
  };
}

/**
 * Adds this browser as a device: a key pair, a wrap of DK sealed to its own public key with an
 * attestation of that key under DK, then the derived keys and the private key kept locally.
 */
async function enrollDevice(
  call: ReturnType<typeof api>,
  userId: string,
  dataKey: Uint8Array,
  keyV: number,
  pair: Awaited<ReturnType<typeof generateDeviceKeyPair>>,
): Promise<LocalKeys> {
  const device = await prepareDevice(userId, dataKey, keyV, pair);
  await call(`/v2/keys/${device.id}`, putJson(device.body));
  return keepLocally(userId, dataKey, keyV, device.privateKey);
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

/** A new account's keys, made but not yet sent: see `prepareAccount`. */
export interface PreparedAccount {
  /** The formatted recovery key to show; `null` for a guest (nothing to show). */
  recoveryKey: string | null;
  /**
   * Sends the recovery wrap, then the device wrap, then keeps the derived keys in this browser.
   * Retry-safe: after a failure, calling it again sends the same wraps under the same ids. After
   * success DK is zeroed, and a further call only returns the same keys.
   */
  commit(): Promise<LocalKeys>;
}

/**
 * First run of an account (spec 7.1): DK, the recovery secret and this device's key pair, all in
 * memory. Nothing reaches the server until `commit()`, which the setup screen calls only once the
 * person has typed back four characters of the key, so the account never ends up with a recovery
 * wrap whose key nobody saw. The recovery wrap goes first (the server refuses any other kind
 * first), then the device wrap. A guest has no recovery key to show (spec section 10): its
 * recovery secret is never shown, which still satisfies the server's first-wrap rule, and the
 * caller commits at once; turning the guest into a real account later replaces that wrap with a
 * recovery key the person keeps. Throws `already_set_up` when the account has wraps: the caller
 * shows Unlock. The recovery wrap goes with `If-None-Match: *`: if another setup (another tab or
 * device) made the account's keys between this check and the commit, `commit()` throws
 * `already_set_up` too and this data key is dropped. `unsupported_browser` before anything is sent
 * when the browser cannot keep a device key safely.
 */
export async function prepareAccount(
  options: KeysOptions & { guest: boolean },
): Promise<PreparedAccount> {
  const { userId, guest } = options;
  const pair = await safeDeviceKeyPair(options);
  const call = api(options);
  if ((await listWraps(call)).length > 0) throw new KeysError("already_set_up");

  const dataKey = generateDataKey();
  const secret = newRecoverySecret();
  const recoveryId = uuidv7();
  const recoveryBody = {
    kind: "recovery",
    keyV: FIRST_KEY_V,
    wrapped: toBase64Url(
      await wrapDataKey(secret, { kind: "recovery", userId, keyV: FIRST_KEY_V }, dataKey),
    ),
  };
  const device = await prepareDevice(userId, dataKey, FIRST_KEY_V, pair);
  const recoveryKey = guest ? null : formatRecoveryKey(secret);
  secret.fill(0);

  let recoverySent = false;
  let done: LocalKeys | null = null;
  let running: Promise<LocalKeys> | null = null;

  async function run(): Promise<LocalKeys> {
    if (done) return done;
    if (!recoverySent) {
      try {
        // Create-only: of two setups at once, one makes the account's data key.
        await call(`/v2/keys/${recoveryId}`, putJson(recoveryBody, { "if-none-match": "*" }));
      } catch (error) {
        if (error instanceof KeysError && error.code === "already_set_up") dataKey.fill(0);
        throw error;
      }
      recoverySent = true;
    }
    await call(`/v2/keys/${device.id}`, putJson(device.body));
    done = await keepLocally(userId, dataKey, FIRST_KEY_V, device.privateKey);
    dataKey.fill(0);
    return done;
  }

  return {
    recoveryKey,
    commit() {
      // One at a time: a double tap shares the call in flight.
      running ??= run().finally(() => {
        running = null;
      });
      return running;
    },
  };
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
  try {
    const pair = await safeDeviceKeyPair(options);
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
      return await enrollDevice(call, userId, dataKey, wrap.keyV, pair);
    } finally {
      dataKey.fill(0);
    }
  } finally {
    secret.fill(0);
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
