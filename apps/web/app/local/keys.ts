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
  openKeyLink,
  openRecord,
  parseRecoveryKey,
  type RecordKeys,
  sealRecord,
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
  | "device_removed"
  /** Another device rotated the data key first (409 `key_version_mismatch`): nothing was kept. */
  | "rotated_elsewhere"
  /** The touched passkey gave no PRF output (some password managers): it cannot open a wrap. */
  | "no_prf"
  /** No passkey wrap has the touched credential as `ref`, or its PRF does not open it. */
  | "no_passkey_wrap"
  /** 422: the credential is not one of the signed-in account's passkeys; no wrap was stored. */
  | "unknown_passkey"
  /**
   * This browser's device wrap holds a data key that is not the one this browser already keeps
   * for that key version (anyone with its public key can seal one to it), or a newer version
   * whose links do not lead back to the key this browser holds: refused, every key zeroed.
   */
  | "tampered";

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

/** A wrap as `GET /v2/keys` lists it. */
export interface WrapDto {
  id: string;
  kind: string;
  ref?: string | null;
  keyV: number;
  wrapped: string;
  publicKey?: string | null;
  attestation?: string | null;
  label?: string | null;
}

/** `/v2/keys` calls for the vault's account, with the errors as `KeysError`s. */
export type KeysApi = ReturnType<typeof api>;

export function api(options: KeysOptions) {
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
      if (response.status === 409 && code === "key_version_mismatch") {
        throw new KeysError("rotated_elsewhere", 409);
      }
      if (response.status === 422 && code === "unknown_passkey") {
        throw new KeysError("unknown_passkey", 422);
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

/**
 * `GET /v2/keys`: the wraps, and the links by the version whose key seals them (`link(v)` holds
 * DK(v-1) under DK(v)). A link whose base64url does not decode counts as missing.
 */
export async function listKeys(
  call: KeysApi,
): Promise<{ wraps: WrapDto[]; links: Map<number, Uint8Array> }> {
  const body = (await (await call("/v2/keys")).json()) as {
    wraps: WrapDto[];
    links?: Array<{ keyV: number; link: string }>;
  };
  const links = new Map<number, Uint8Array>();
  for (const entry of body.links ?? []) {
    try {
      links.set(entry.keyV, fromBase64Url(entry.link));
    } catch {
      // missing
    }
  }
  return { wraps: body.wraps, links };
}

export async function listWraps(call: KeysApi): Promise<WrapDto[]> {
  return (await listKeys(call)).wraps;
}

/** Zeroes every data key in the map. */
function zeroKeys(keys: Map<number, Uint8Array>): void {
  for (const key of keys.values()) key.fill(0);
}

/**
 * Walks the key links down from `top` (spec 2026-11-10 section 2.2): the data keys of the versions
 * `top.keyV - 1` down to `floor`, each opened from the link of the version above it. `strict`: a
 * missing or failing link is `KeysError("tampered")`; otherwise the walk stops there and returns
 * what it reached. On a throw every key it opened is zeroed; on success the caller owns them (and
 * `top.dataKey` stays the caller's either way).
 */
export async function chainDown(
  userId: string,
  top: { keyV: number; dataKey: Uint8Array },
  links: Map<number, Uint8Array>,
  floor: number,
  strict: boolean,
): Promise<Map<number, Uint8Array>> {
  const older = new Map<number, Uint8Array>();
  try {
    let key = top.dataKey;
    for (let v = top.keyV; v >= 2 && v - 1 >= floor; v--) {
      const link = links.get(v);
      let opened: Uint8Array | undefined;
      if (link) {
        try {
          opened = await openKeyLink(key, { userId, keyV: v }, link);
        } catch {
          opened = undefined;
        }
      }
      if (!opened) {
        if (strict) throw new KeysError("tampered");
        break;
      }
      older.set(v - 1, opened);
      key = opened;
    }
    return older;
  } catch (error) {
    zeroKeys(older);
    throw error;
  }
}

/** The record key this browser keeps for `keyV` (a 2a vault's single one is version `meta.keyV`). */
async function heldRecordKey(store: EncryptedStore, keyV: number): Promise<CryptoKey | undefined> {
  return (
    (await store.getKey<CryptoKey>(recordKeyName(keyV))) ??
    ((await store.getMeta<number>("keyV")) === keyV
      ? await store.getKey<CryptoKey>(LEGACY_RECORD_KEY)
      : undefined)
  );
}

/**
 * A data key at `top.keyV`, at or above the `current` version this browser holds, is accepted only
 * when the links lead strictly down to `current` and the key reached there is the one this browser
 * holds (`sameDataKey`); else `tampered`, with every key opened on the way zeroed. Returns the
 * older keys from `top.keyV - 1` down to `current` (empty when `top.keyV` is `current`).
 */
async function chainToHeld(
  store: EncryptedStore,
  userId: string,
  top: { keyV: number; dataKey: Uint8Array },
  links: Map<number, Uint8Array>,
  current: number,
): Promise<Map<number, Uint8Array>> {
  if (top.keyV < current) throw new KeysError("tampered");
  const older = await chainDown(userId, top, links, current, true);
  try {
    const reached = top.keyV === current ? top.dataKey : older.get(current);
    const held = await heldRecordKey(store, current);
    if (!reached || !held || !(await sameDataKey(userId, reached, current, held))) {
      throw new KeysError("tampered");
    }
    return older;
  } catch (error) {
    zeroKeys(older);
    throw error;
  }
}

/**
 * The older keys a data key from a trusted way in (a passkey or recovery wrap, or pairing) brings
 * along. With a vault held here: the strict walk down to its current version, checked against the
 * key it holds (`tampered` otherwise, and a version below the held one too, since versions only
 * grow). Without one: every version the links reach, down to the first, stopping silently at the
 * first missing or failing link.
 */
async function olderForTrustedKey(
  userId: string,
  top: { keyV: number; dataKey: Uint8Array },
  links: Map<number, Uint8Array>,
): Promise<Map<number, Uint8Array>> {
  const store = await createEncryptedStore(userId);
  try {
    const current = await store.getMeta<number>("keyV");
    if (current !== undefined && (await heldRecordKey(store, current))) {
      return await chainToHeld(store, userId, top, links, current);
    }
    return await chainDown(userId, top, links, FIRST_KEY_V, false);
  } finally {
    store.close();
  }
}

export const putJson = (body: unknown, headers: Record<string, string> = {}): RequestInit => ({
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
 * locally. The caller owns `dataKey` and zeroes it. The end of pairing: DK came authenticated by
 * the number, and the links bring the older versions it reaches (`olderForTrustedKey`).
 */
export async function enrollDevice(
  options: KeysOptions,
  dataKey: Uint8Array,
  keyV: number,
): Promise<LocalKeys> {
  const pair = await safeDeviceKeyPair(options);
  const call = api(options);
  const { links } = await listKeys(call);
  return enrollTrusted(call, options.userId, dataKey, keyV, links, pair);
}

/** Enrolls with a trusted DK (passkey, recovery, pairing), after its walk; nothing sent before. */
async function enrollTrusted(
  call: KeysApi,
  userId: string,
  dataKey: Uint8Array,
  keyV: number,
  links: Map<number, Uint8Array>,
  pair: Awaited<ReturnType<typeof generateDeviceKeyPair>>,
): Promise<LocalKeys> {
  const older = await olderForTrustedKey(userId, { keyV, dataKey }, links);
  try {
    return await enrollWithPair(call, userId, dataKey, keyV, pair, older);
  } finally {
    zeroKeys(older);
  }
}

async function enrollWithPair(
  call: KeysApi,
  userId: string,
  dataKey: Uint8Array,
  keyV: number,
  pair: Awaited<ReturnType<typeof generateDeviceKeyPair>>,
  older: Map<number, Uint8Array>,
): Promise<LocalKeys> {
  const device = await prepareDevice(userId, dataKey, keyV, pair);
  await call(`/v2/keys/${device.id}`, putJson(device.body));
  return keepLocally(userId, dataKey, keyV, device, older);
}

/**
 * Keeps the derived keys of `keyV` (made current) and of every `older` version, the device private
 * key and its wrap's id and public key. The caller owns and zeroes the data keys.
 */
async function keepLocally(
  userId: string,
  dataKey: Uint8Array,
  keyV: number,
  device: { id: string; privateKey: DevicePrivateKey; body: { publicKey: string } },
  older: Map<number, Uint8Array>,
): Promise<LocalKeys> {
  const derived = new Map<number, RecordKeys>([[keyV, await deriveRecordKeys(dataKey, false)]]);
  for (const [v, key] of older) derived.set(v, await deriveRecordKeys(key, false));
  const store = await createEncryptedStore(userId);
  try {
    for (const [v, keys] of derived) {
      await store.putKey(recordKeyName(v), keys.record);
      await store.putKey(dedupeKeyName(v), keys.dedupe);
    }
    await store.putKey(DEVICE_KEY, device.privateKey);
    await store.setMeta("deviceWrapId", device.id);
    await store.setMeta("devicePublicKey", device.body.publicKey);
    await store.setMeta("keyV", keyV);
    await store.setMeta("userId", userId);
  } finally {
    store.close();
  }
  const local = await loadLocalKeys(userId);
  if (!local) throw new Error(`no record keys for key version ${keyV}`);
  return local;
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
    done = await keepLocally(userId, dataKey, FIRST_KEY_V, device, new Map());
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
 * and keeps the derived keys, of the older versions the links reach too (`olderForTrustedKey`: with
 * a vault held here, the links must lead to its key, else `tampered` and nothing is sent or kept).
 * The caller then runs a full sync. `bad_recovery_key` is a key that
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
    const { wraps, links } = await listKeys(call);
    const wrap = wraps.find((w) => w.kind === "recovery");
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
      return await enrollTrusted(call, userId, dataKey, wrap.keyV, links, pair);
    } finally {
      dataKey.fill(0);
    }
  } finally {
    secret.fill(0);
  }
}

/** A passkey's credential id (base64url, Better Auth's `credentialID`) and its PRF output. */
export interface PasskeySecret {
  credentialId: string;
  prf: Uint8Array;
}

/**
 * Unlocks this browser with a passkey's PRF (spec 7.2): opens the passkey wrap whose `ref` is the
 * credential, enrolls this device and keeps the derived keys, as `unlockWithRecovery` (the same walk
 * of the links, `tampered` with a held vault the links do not reach). The caller
 * owns the PRF and zeroes it. `no_passkey_wrap` when no wrap has that `ref` or the PRF does not
 * open it (nothing is sent).
 */
export async function unlockWithPasskey(options: KeysOptions & PasskeySecret): Promise<LocalKeys> {
  const { userId, credentialId, prf } = options;
  const pair = await safeDeviceKeyPair(options);
  const call = api(options);
  const { wraps, links } = await listKeys(call);
  const wrap = wraps.find((w) => w.kind === "passkey" && w.ref === credentialId);
  if (!wrap) throw new KeysError("no_passkey_wrap");
  let dataKey: Uint8Array;
  try {
    dataKey = await unwrapDataKey(
      prf,
      { kind: "passkey", userId, keyV: wrap.keyV },
      fromBase64Url(wrap.wrapped),
    );
  } catch {
    throw new KeysError("no_passkey_wrap");
  }
  try {
    return await enrollTrusted(call, userId, dataKey, wrap.keyV, links, pair);
  } finally {
    dataKey.fill(0);
  }
}

/**
 * Adds (or replaces) the wrap of DK for one passkey: DK from this browser's own device wrap
 * (`withDataKey`, Ruling 1 of stage 2b; the touch on that passkey is the confirmation), wrapped
 * under its PRF at the current `keyV`, PUT as `kind: "passkey"`, `ref: credentialId`. A passkey
 * that already has a wrap keeps its id. The caller owns the PRF and zeroes it. The server stores it
 * only for one of the signed-in account's passkeys (the cookie's, which must be the vault's):
 * another credential is `KeysError("unknown_passkey")`, so a wrap is never made under someone
 * else's passkey.
 */
export async function addPasskeyWrap(options: KeysOptions & PasskeySecret): Promise<void> {
  const { userId, credentialId, prf } = options;
  await withDataKey(options, async (dataKey, keyV) => {
    const call = api(options);
    const existing = (await listWraps(call)).find(
      (w) => w.kind === "passkey" && w.ref === credentialId,
    );
    const wrapped = await wrapDataKey(prf, { kind: "passkey", userId, keyV }, dataKey);
    await call(
      `/v2/keys/${existing?.id ?? uuidv7()}`,
      putJson({ kind: "passkey", ref: credentialId, keyV, wrapped: toBase64Url(wrapped) }),
    );
  });
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
 * Opens DK from this browser's own `device` wrap (spec 7.5, Ruling 1 of stage 2b). The wrap is the
 * one whose id this browser kept at enroll, and it must still be sealed to this browser's public
 * key; else `device_removed`. A 2a browser kept no wrap id: it tries each device wrap with its
 * private key, and keeps the id and public key of the one that opens. A wrap at a version above
 * the current one this browser holds is accepted only through its links (`chainToHeld`, spec
 * 2026-11-10 section 2.2), which also give `older`: the data keys from `keyV - 1` down to the held
 * current version. At or below it, when this browser holds that `keyV`'s record key, DK must be
 * the one it came from (`sameDataKey`). Else `tampered`. On a throw every key is zeroed.
 */
async function openOwnDeviceKey(
  options: KeysOptions,
): Promise<{ dataKey: Uint8Array; keyV: number; older: Map<number, Uint8Array> }> {
  const { userId } = options;
  let dataKey: Uint8Array | undefined;
  let older = new Map<number, Uint8Array>();
  const store = await createEncryptedStore(userId);
  try {
    let keyV = 0;
    const privateKey = await store.getKey<DevicePrivateKey>(DEVICE_KEY);
    if (!privateKey) throw new KeysError("device_removed");
    const wrapId = await store.getMeta<string>("deviceWrapId");
    const publicKey = await store.getMeta<string>("devicePublicKey");
    const listed = await listKeys(api(options));
    const devices = listed.wraps.filter((w) => w.kind === "device");
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
    if (!dataKey) throw new KeysError("device_removed");
    const current = await store.getMeta<number>("keyV");
    // a device key without a current version: nothing to check a new version against
    if (current === undefined) throw new KeysError("tampered");
    if (keyV > current) {
      older = await chainToHeld(store, userId, { keyV, dataKey }, listed.links, current);
    } else {
      const held = await heldRecordKey(store, keyV);
      if (held && !(await sameDataKey(userId, dataKey, keyV, held))) {
        throw new KeysError("tampered");
      }
    }
    return { dataKey, keyV, older };
  } catch (error) {
    dataKey?.fill(0);
    zeroKeys(older);
    throw error;
  } finally {
    store.close();
  }
}

/** `openOwnDeviceKey` for one operation: `fn` runs, then DK and the older keys are zeroed. */
async function withOwnDeviceKey<T>(
  options: KeysOptions,
  fn: (dk: Uint8Array, keyV: number, older: Map<number, Uint8Array>) => Promise<T>,
): Promise<T> {
  const { dataKey, keyV, older } = await openOwnDeviceKey(options);
  try {
    return await fn(dataKey, keyV, older);
  } finally {
    dataKey.fill(0);
    zeroKeys(older);
  }
}

/**
 * Opens DK from this browser's own `device` wrap for one operation: `fn` gets DK and the wrap's
 * `keyV`, and DK is zeroed once `fn` settles. `device_removed` when this browser's wrap is gone or
 * sealed to another key. A version this browser holds must be the DK its record key came from, and
 * a newer one must lead back to it through its links; else `tampered` (every key zeroed, `fn`
 * never runs). See `openOwnDeviceKey`.
 */
export async function withDataKey<T>(
  options: KeysOptions,
  fn: (dk: Uint8Array, keyV: number) => Promise<T>,
): Promise<T> {
  return withOwnDeviceKey(options, (dk, keyV) => fn(dk, keyV));
}

/**
 * Whether `dataKey` is the data key whose record key this browser keeps for `keyV`: a random
 * canary sealed with the kept `record:<v>` key must open with the record key derived from
 * `dataKey`. The device wrap is an anonymous sealed box, so this is what stops a server from
 * handing this browser another DK at a version it already holds.
 */
async function sameDataKey(
  userId: string,
  dataKey: Uint8Array,
  keyV: number,
  held: CryptoKey,
): Promise<boolean> {
  const derived = await deriveRecordKeys(dataKey, false);
  const ctx = { userId, type: "settings" as const, id: uuidv7(), keyV };
  const canary = toBase64Url(crypto.getRandomValues(new Uint8Array(16)));
  try {
    const sealed = await sealRecord({ record: held, dedupe: derived.dedupe }, ctx, canary);
    return (await openRecord(derived, ctx, sealed)) === canary;
  } catch {
    return false;
  }
}

/**
 * The account moved to a new key version (a rotation): opens this browser's device wrap and, only
 * when its `keyV` (n) is higher than the current one (c) and its links lead back to the key held
 * for c, keeps the record and dedupe keys of every version from c + 1 to n beside the older ones
 * (records under them still need opening) and makes n current. Key versions only grow: a wrap at
 * or below the current version (a stale listing, or a server replaying an old wrap) changes
 * nothing, and a version already held is never overwritten. Returns the keyring. `device_removed`
 * and `tampered` (another DK at a held version, or a chain that does not reach the held key:
 * nothing kept) as `withDataKey`.
 */
export async function refreshKeys(options: KeysOptions): Promise<LocalKeys> {
  const { userId } = options;
  const before = await loadLocalKeys(userId);
  if (!before) throw new KeysError("device_removed");
  await withOwnDeviceKey(options, async (dataKey, keyV, older) => {
    const { current, byVersion } = before.keyring;
    if (keyV <= current || byVersion.has(keyV)) return;
    const fresh = new Map<number, RecordKeys>([[keyV, await deriveRecordKeys(dataKey, false)]]);
    for (const [v, key] of older) {
      if (v > current && !byVersion.has(v)) fresh.set(v, await deriveRecordKeys(key, false));
    }
    const store = await createEncryptedStore(userId);
    try {
      for (const [v, keys] of fresh) {
        await store.putKey(recordKeyName(v), keys.record);
        await store.putKey(dedupeKeyName(v), keys.dedupe);
      }
      // current last: a write that fails half-way leaves the held version current
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
