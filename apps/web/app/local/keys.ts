import {
  type DevicePrivateKey,
  deriveRecordKeys,
  deviceAttestation,
  formatRecoveryKey,
  fromBase64Url,
  generateDataKey,
  generateDeviceKeyPair,
  newRecoverySecret,
  openFromDevice,
  parseRecoveryKey,
  type RecordKeys,
  sealToDevice,
  toBase64Url,
  unwrapDataKey,
  wrapDataKey,
} from "@wambito/crypto";
import { deleteVault } from "./db.ts";
import { deviceLabel } from "./device-label.ts";
import { createEncryptedStore, type EncryptedStore } from "./encrypted-store.ts";
import { uuidv7 } from "./ids.ts";

/**
 * Keys on the web (spec 2026-11-08 sections 4.1, 5.2, 7.1, 7.2, 7.4, 7.5). This browser keeps only
 * the record and dedupe `CryptoKey`s (non-extractable) of each key version it still needs
 * (`record:<v>`, `dedupe:<v>`) and its device private key, in the vault's `keys` store; meta keeps
 * the current `keyV` and this browser's device wrap (`deviceWrapId`, `devicePublicKey`). The data
 * key DK lives in memory during setup, unlock or one `withDataKey` operation and is zeroed after.
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
  | "session_changed"
  /** The server lists no device wrap for this browser (or one sealed to another key): removed. */
  | "device_removed";

export class KeysError extends Error {
  constructor(
    readonly code: KeysErrorCode,
    readonly status?: number,
  ) {
    super(code);
    this.name = "KeysError";
  }
}

/** The names under which the vault's `keys` store keeps them: `record:<v>`, `dedupe:<v>`. */
export const recordKeyName = (keyV: number) => `record:${keyV}`;
export const dedupeKeyName = (keyV: number) => `dedupe:${keyV}`;
export const DEVICE_KEY = "device";
/** Stage 2a's single-version names, read as version `meta.keyV` and renamed on first load. */
const LEGACY_RECORD_KEY = "record";
const LEGACY_DEDUPE_KEY = "dedupe";
/** The key version a new account starts at. */
export const FIRST_KEY_V = 1;

export interface KeysOptions {
  userId: string;
  /** Defaults to the global `fetch`. */
  fetch?: typeof globalThis.fetch;
  baseUrl?: string;
  /** Makes the device key pair; tests pass the noble fallback's shape. */
  deviceKeyPair?: typeof generateDeviceKeyPair;
}

/** The record keys this browser holds, by key version; `current` is the account's newest. */
export interface Keyring {
  current: number;
  byVersion: Map<number, RecordKeys>;
}

export interface LocalKeys {
  keyring: Keyring;
}

/** The record keys of the keyring's current version (always present in a loaded keyring). */
export function currentRecordKeys(local: LocalKeys): RecordKeys {
  const keys = local.keyring.byVersion.get(local.keyring.current);
  if (!keys) throw new Error(`no record keys for key version ${local.keyring.current}`);
  return keys;
}

interface WrapDto {
  id: string;
  kind: string;
  keyV: number;
  wrapped: string;
  publicKey?: string | null;
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
      label: deviceLabel(typeof navigator === "undefined" ? "" : navigator.userAgent),
    },
  };
}

/**
 * Adds this browser as a device: a key pair (`unsupported_browser` before anything is sent when it
 * cannot be kept safely), a wrap of DK sealed to its own public key with an attestation of that
 * key under DK, then the derived keys, the private key and the wrap's id and public key kept
 * locally. The caller owns `dataKey` and zeroes it. Also the end of pairing (a later task).
 */
export async function enrollDevice(
  options: KeysOptions,
  dataKey: Uint8Array,
  keyV: number,
): Promise<LocalKeys> {
  const pair = await safeDeviceKeyPair(options);
  return enrollWithPair(api(options), options.userId, dataKey, keyV, pair);
}

async function enrollWithPair(
  call: ReturnType<typeof api>,
  userId: string,
  dataKey: Uint8Array,
  keyV: number,
  pair: Awaited<ReturnType<typeof generateDeviceKeyPair>>,
): Promise<LocalKeys> {
  const device = await prepareDevice(userId, dataKey, keyV, pair);
  await call(`/v2/keys/${device.id}`, putJson(device.body));
  return keepLocally(userId, dataKey, keyV, device);
}

async function keepLocally(
  userId: string,
  dataKey: Uint8Array,
  keyV: number,
  device: { id: string; privateKey: DevicePrivateKey; body: { publicKey: string } },
): Promise<LocalKeys> {
  const keys = await deriveRecordKeys(dataKey, false);
  const store = await createEncryptedStore(userId);
  try {
    await store.putKey(recordKeyName(keyV), keys.record);
    await store.putKey(dedupeKeyName(keyV), keys.dedupe);
    await store.putKey(DEVICE_KEY, device.privateKey);
    await store.setMeta("deviceWrapId", device.id);
    await store.setMeta("devicePublicKey", device.body.publicKey);
    await store.setMeta("keyV", keyV);
    await store.setMeta("userId", userId);
  } finally {
    store.close();
  }
  return { keyring: { current: keyV, byVersion: new Map([[keyV, keys]]) } };
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
    done = await keepLocally(userId, dataKey, FIRST_KEY_V, device);
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
      return await enrollWithPair(call, userId, dataKey, wrap.keyV, pair);
    } finally {
      dataKey.fill(0);
    }
  } finally {
    secret.fill(0);
  }
}

/**
 * The keys this browser kept, or `null` when it was never set up or lacks the current version's
 * keys (the app is locked). A 2a vault's `record` and `dedupe` are version `meta.keyV`: they are
 * written under the versioned names first, then the old names go.
 */
export async function loadLocalKeys(userId: string): Promise<LocalKeys | null> {
  const store: EncryptedStore = await createEncryptedStore(userId);
  try {
    const current = await store.getMeta<number>("keyV");
    if (current === undefined) return null;
    const legacyRecord = await store.getKey<CryptoKey>(LEGACY_RECORD_KEY);
    const legacyDedupe = await store.getKey<CryptoKey>(LEGACY_DEDUPE_KEY);
    if (legacyRecord && legacyDedupe) {
      await store.putKey(recordKeyName(current), legacyRecord);
      await store.putKey(dedupeKeyName(current), legacyDedupe);
      await store.deleteKey(LEGACY_RECORD_KEY);
      await store.deleteKey(LEGACY_DEDUPE_KEY);
    }
    const byVersion = new Map<number, RecordKeys>();
    for (const name of await store.keyNames()) {
      const match = /^record:(\d+)$/.exec(name);
      if (!match) continue;
      const keyV = Number(match[1]);
      const record = await store.getKey<CryptoKey>(name);
      const dedupe = await store.getKey<CryptoKey>(dedupeKeyName(keyV));
      if (record && dedupe) byVersion.set(keyV, { record, dedupe });
    }
    if (!byVersion.has(current)) return null;
    return { keyring: { current, byVersion: new Map([...byVersion].sort(([a], [b]) => a - b)) } };
  } finally {
    store.close();
  }
}

/**
 * Opens DK from this browser's own `device` wrap (spec 7.5, Ruling 1 of stage 2b) for one
 * operation: `fn` gets DK and the wrap's `keyV`, and DK is zeroed once `fn` settles. The wrap is the
 * one whose id this browser kept at enroll, and it must still be sealed to this browser's public
 * key; else `device_removed`. A 2a browser kept no wrap id: it tries each device wrap with its
 * private key, and keeps the id and public key of the one that opens.
 */
export async function withDataKey<T>(
  options: KeysOptions,
  fn: (dk: Uint8Array, keyV: number) => Promise<T>,
): Promise<T> {
  const { userId } = options;
  let dataKey: Uint8Array | undefined;
  try {
    const store = await createEncryptedStore(userId);
    let keyV = 0;
    try {
      const privateKey = await store.getKey<DevicePrivateKey>(DEVICE_KEY);
      if (!privateKey) throw new KeysError("device_removed");
      const wrapId = await store.getMeta<string>("deviceWrapId");
      const publicKey = await store.getMeta<string>("devicePublicKey");
      const devices = (await listWraps(api(options))).filter((w) => w.kind === "device");
      const open = (wrap: WrapDto) =>
        openFromDevice(
          privateKey,
          { kind: "device", userId, keyV: wrap.keyV },
          fromBase64Url(wrap.wrapped),
        );
      if (wrapId && publicKey) {
        const wrap = devices.find((w) => w.id === wrapId);
        // base64url of the same 32 bytes is one string: compare as text
        if (!wrap || wrap.publicKey !== publicKey) throw new KeysError("device_removed");
        try {
          dataKey = await open(wrap);
        } catch {
          throw new KeysError("device_removed");
        }
        keyV = wrap.keyV;
      } else {
        for (const wrap of devices) {
          if (!wrap.publicKey) continue;
          try {
            dataKey = await open(wrap);
          } catch {
            continue;
          }
          keyV = wrap.keyV;
          await store.setMeta("deviceWrapId", wrap.id);
          await store.setMeta("devicePublicKey", wrap.publicKey);
          break;
        }
      }
    } finally {
      store.close();
    }
    if (!dataKey) throw new KeysError("device_removed");
    return await fn(dataKey, keyV);
  } finally {
    dataKey?.fill(0);
  }
}

/**
 * The account moved to a new key version (a rotation): opens this browser's device wrap and, only
 * when its `keyV` is higher than the current one, keeps that version's record and dedupe keys
 * beside the older ones (records under them still need opening) and makes it current. Key
 * versions only grow: a wrap at or below the current version (a stale listing, or a server
 * replaying an old wrap or sealing another DK to this browser's public key) changes nothing, and
 * a version already held is never overwritten. Returns the keyring. `device_removed` as
 * `withDataKey`.
 */
export async function refreshKeys(options: KeysOptions): Promise<LocalKeys> {
  const { userId } = options;
  const before = await loadLocalKeys(userId);
  if (!before) throw new KeysError("device_removed");
  await withDataKey(options, async (dataKey, keyV) => {
    if (keyV <= before.keyring.current || before.keyring.byVersion.has(keyV)) return;
    const keys = await deriveRecordKeys(dataKey, false);
    const store = await createEncryptedStore(userId);
    try {
      await store.putKey(recordKeyName(keyV), keys.record);
      await store.putKey(dedupeKeyName(keyV), keys.dedupe);
      await store.setMeta("keyV", keyV);
    } finally {
      store.close();
    }
  });
  const local = await loadLocalKeys(userId);
  if (!local) throw new KeysError("device_removed");
  return local;
}

/** Forgets one old key version's record and dedupe keys, once no local record uses it. */
export async function dropKeyVersion(userId: string, keyV: number): Promise<void> {
  const store = await createEncryptedStore(userId);
  try {
    await store.deleteKey(recordKeyName(keyV));
    await store.deleteKey(dedupeKeyName(keyV));
  } finally {
    store.close();
  }
}

/** Signing out: deletes this browser's database, keys included. */
export function forgetDevice(userId: string): Promise<void> {
  return deleteVault(userId);
}
