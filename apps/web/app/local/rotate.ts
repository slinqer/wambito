import {
  deriveRecordKeys,
  deviceAttestation,
  formatRecoveryKey,
  fromBase64Url,
  generateDataKey,
  newRecoverySecret,
  parseRecoveryKey,
  type RecordKeys,
  sealKeyLink,
  sealToDevice,
  toBase64Url,
  unwrapDataKey,
  verifyDeviceAttestation,
  wrapDataKey,
} from "@wambito/crypto";
import { createEncryptedStore } from "./encrypted-store.ts";
import { uuidv7 } from "./ids.ts";
import {
  api,
  dedupeKeyName,
  KeysError,
  type KeysOptions,
  listWraps,
  migrateLegacyKeys,
  putJson,
  recordKeyName,
  type WrapDto,
  withDataKey,
} from "./keys.ts";

/**
 * Removing a device rotates the data key (spec 2026-11-08 section 7.5, addendum 2026-11-08-e2e-
 * stage-1b section 2, stage 2b Rulings 1, 2 and 7), and a new recovery key replaces the recovery
 * wrap. Both are two steps, like `prepareAccount`: everything is made in memory first (DK from
 * this browser's own device wrap, the new DK and the recovery secret are zeroed before the first
 * step returns: only the sealed wraps and the derived non-extractable record keys are kept), and
 * nothing reaches the server until `commit()`.
 */

export interface DroppedWrap {
  id: string;
  label: string | null;
  /** `removed`: asked for now; `revoked`: in `settings.revokedDevices`; `attestation`: forged. */
  reason: "removed" | "revoked" | "attestation";
}

export interface RotateResult {
  keyV: number;
  dropped: DroppedWrap[];
}

export interface RotateOptions extends KeysOptions {
  /** Device wrap ids to remove. */
  remove: string[];
  /**
   * The recovery wrap of the new DK: the typed recovery key (it must open the current recovery
   * wrap, else `wrong_recovery_key`; the same key is re-wrapped), or a new one (shown by the
   * caller before `commit()`).
   */
  recovery: { text: string } | { fresh: true };
  /**
   * The passkey touched during the operation, with its PRF output: its wrap is re-made under the
   * new DK. The PRF output is used up: zeroed before `rotateKeys` returns. Other passkeys lose
   * their wrap until they are next used.
   */
  passkey?: { credentialId: string; prf: Uint8Array };
}

interface WrapBody {
  id: string;
  kind: string;
  ref?: string;
  keyV: number;
  wrapped: string;
  publicKey?: string;
  attestation?: string;
  label?: string;
}

const postJson = (body: unknown): RequestInit => ({
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

/** `wrong_recovery_key` unless `secret` opens the account's current recovery wrap. */
async function checkRecovery(userId: string, wraps: WrapDto[], secret: Uint8Array): Promise<void> {
  const wrap = wraps.find((w) => w.kind === "recovery");
  if (!wrap) throw new KeysError("wrong_recovery_key");
  let opened: Uint8Array;
  try {
    opened = await unwrapDataKey(
      secret,
      { kind: "recovery", userId, keyV: wrap.keyV },
      fromBase64Url(wrap.wrapped),
    );
  } catch {
    throw new KeysError("wrong_recovery_key");
  }
  opened.fill(0);
}

/** Whether a device wrap's attestation checks out under `dataKey` (Settings → Security shows the rest as "Not verified"). */
export async function attested(
  userId: string,
  dataKey: Uint8Array,
  wrap: WrapDto,
): Promise<boolean> {
  if (!wrap.publicKey || !wrap.attestation) return false;
  try {
    return await verifyDeviceAttestation(
      dataKey,
      { userId, wrapId: wrap.id, publicKey: fromBase64Url(wrap.publicKey) },
      fromBase64Url(wrap.attestation),
    );
  } catch {
    return false;
  }
}

/** The settings record's `revokedDevices` (none when the vault has no settings yet). */
export async function revokedDevices(userId: string): Promise<string[]> {
  const store = await createEncryptedStore(userId);
  try {
    const [settings] = await store.list("settings");
    return settings?.body.revokedDevices ?? [];
  } finally {
    store.close();
  }
}

/**
 * Settings' confirmation before a new recovery key (stage 2b Ruling 1): resolves when `text` opens
 * the account's current recovery wrap; `bad_recovery_key` / `wrong_recovery_key` otherwise. Nothing
 * is made or sent; the secret is zeroed.
 */
export async function checkRecoveryKey(options: KeysOptions & { text: string }): Promise<void> {
  let secret: Uint8Array;
  try {
    secret = parseRecoveryKey(options.text);
  } catch {
    throw new KeysError("bad_recovery_key");
  }
  try {
    await checkRecovery(options.userId, await listWraps(api(options)), secret);
  } finally {
    secret.fill(0);
  }
}

/**
 * Removes devices and rotates the data key, in the order of spec 7.5 and addendum section 2:
 * 1. the typed recovery key must open the current recovery wrap (before anything is made);
 * 2. DK from this browser's own device wrap; every other device wrap's attestation is verified
 *    under it, and the ids in `remove` and in `settings.revokedDevices` are left out, whatever the
 *    server lists (reported in `dropped`, with a forged attestation as `attestation`);
 * 3. a new DK at `keyV + 1`, and its wraps: one recovery, the kept devices (same id, ref and
 *    label, sealed to their public keys with fresh attestations; this browser's own with the
 *    public key it kept), the touched passkey. Assistants have no web wraps yet (stage 4).
 *
 * `commit()` then `POST /v2/keys/rotate`s them with the key link (the old DK sealed under the new one) (409 `key_version_mismatch` = `rotated_elsewhere`:
 * another device rotated first, nothing is kept), keeps the new version's record and dedupe keys
 * in this browser and makes it current, and writes the removed ids into `settings.revokedDevices`
 * (a local write: the sync seals it under the new version). The caller then calls the session's
 * `reloadKeys()`, whose sync's upgrade pass re-seals the old records. Retry-safe: a failed post is
 * sent again with the same wraps.
 */
export async function rotateKeys(
  options: RotateOptions,
): Promise<{ recoveryKey: string | null; commit(): Promise<RotateResult> }> {
  const { userId } = options;
  const call = api(options);
  let secret: Uint8Array | undefined;
  try {
    if ("text" in options.recovery) {
      try {
        secret = parseRecoveryKey(options.recovery.text);
      } catch {
        throw new KeysError("bad_recovery_key");
      }
      await checkRecovery(userId, await listWraps(call), secret);
    } else {
      secret = newRecoverySecret();
    }
    const recoveryKey = "fresh" in options.recovery ? formatRecoveryKey(secret) : null;
    const recoverySecret = secret;
    const revoked = new Set([...(await revokedDevices(userId)), ...options.remove]);

    const prepared = await withDataKey(options, async (dataKey, keyV) => {
      // Read after `withDataKey`, which remembers them for a 2a browser.
      const local = await createEncryptedStore(userId);
      let ownId: string | undefined;
      let ownPublicKey: string | undefined;
      try {
        ownId = await local.getMeta<string>("deviceWrapId");
        ownPublicKey = await local.getMeta<string>("devicePublicKey");
      } finally {
        local.close();
      }
      if (!ownId || !ownPublicKey) throw new KeysError("device_removed");
      if (revoked.has(ownId)) throw new Error("this browser cannot remove itself");
      const wraps = await listWraps(call);
      const dropped: DroppedWrap[] = [];
      const kept: WrapDto[] = [];
      for (const wrap of wraps) {
        if (wrap.kind !== "device") continue;
        const label = wrap.label ?? null;
        if (wrap.id === ownId) kept.push({ ...wrap, publicKey: ownPublicKey });
        else if (options.remove.includes(wrap.id))
          dropped.push({ id: wrap.id, label, reason: "removed" });
        else if (revoked.has(wrap.id)) dropped.push({ id: wrap.id, label, reason: "revoked" });
        else if (!(await attested(userId, dataKey, wrap)))
          dropped.push({ id: wrap.id, label, reason: "attestation" });
        else kept.push(wrap);
      }
      if (!kept.some((w) => w.id === ownId)) throw new KeysError("device_removed");

      const nextV = keyV + 1;
      const newKey = generateDataKey();
      try {
        const body: WrapBody[] = [];
        const recoveryWrap = wraps.find((w) => w.kind === "recovery");
        body.push({
          id: recoveryKey === null && recoveryWrap ? recoveryWrap.id : uuidv7(),
          kind: "recovery",
          keyV: nextV,
          wrapped: toBase64Url(
            await wrapDataKey(recoverySecret, { kind: "recovery", userId, keyV: nextV }, newKey),
          ),
        });
        for (const device of kept) {
          const publicKey = fromBase64Url(device.publicKey as string);
          const wrapped = await sealToDevice(
            publicKey,
            { kind: "device", userId, keyV: nextV },
            newKey,
          );
          const attestation = await deviceAttestation(newKey, {
            userId,
            wrapId: device.id,
            publicKey,
          });
          body.push({
            id: device.id,
            kind: "device",
            ...(device.ref ? { ref: device.ref } : {}),
            keyV: nextV,
            wrapped: toBase64Url(wrapped),
            publicKey: device.publicKey as string,
            attestation: toBase64Url(attestation),
            ...(device.label ? { label: device.label } : {}),
          });
        }
        if (options.passkey) {
          const { credentialId, prf } = options.passkey;
          const existing = wraps.find((w) => w.kind === "passkey" && w.ref === credentialId);
          body.push({
            id: existing?.id ?? uuidv7(),
            kind: "passkey",
            ref: credentialId,
            keyV: nextV,
            wrapped: toBase64Url(
              await wrapDataKey(prf, { kind: "passkey", userId, keyV: nextV }, newKey),
            ),
            ...(existing?.label ? { label: existing.label } : {}),
          });
        }
        // The link: the old DK (version `keyV`) sealed under the new one, so other browsers can
        // follow the rotation. Made here, kept in `prepared`: a retried commit posts the same one.
        const link = toBase64Url(await sealKeyLink(newKey, dataKey, { userId, keyV: nextV }));
        const keys = await deriveRecordKeys(newKey, false);
        return { keyV: nextV, wraps: body, link, keys, dropped, ownId };
      } finally {
        newKey.fill(0);
      }
    });

    /** The server's current wraps include this browser's prepared wrap: the rotation is ours. */
    async function landed(): Promise<boolean> {
      const own = prepared.wraps.find((w) => w.id === prepared.ownId);
      try {
        const wrap = (await listWraps(call)).find((w) => w.id === prepared.ownId);
        return !!own && wrap?.keyV === prepared.keyV && wrap.wrapped === own.wrapped;
      } catch {
        return false;
      }
    }

    let posted = false;
    let done: RotateResult | null = null;
    let running: Promise<RotateResult> | null = null;

    async function run(): Promise<RotateResult> {
      if (done) return done;
      if (!posted) {
        try {
          await call(
            "/v2/keys/rotate",
            postJson({ keyV: prepared.keyV, wraps: prepared.wraps, link: prepared.link }),
          );
        } catch (error) {
          // The rotate is not idempotent: a post whose answer was lost (`offline`), retried, gets
          // 409 (`rotated_elsewhere`). Ours if the server holds this browser's prepared wrap.
          const lost =
            error instanceof KeysError &&
            (error.code === "offline" || error.code === "rotated_elsewhere");
          if (!lost || !(await landed())) throw error;
        }
        posted = true;
      }
      await keepRotated(userId, prepared.keyV, prepared.keys, options.remove);
      done = { keyV: prepared.keyV, dropped: prepared.dropped };
      return done;
    }

    return {
      recoveryKey,
      commit() {
        running ??= run().finally(() => {
          running = null;
        });
        return running;
      },
    };
  } finally {
    secret?.fill(0);
    options.passkey?.prf.fill(0);
  }
}

/** The new version's keys become current, and the removed ids join `settings.revokedDevices`. */
async function keepRotated(
  userId: string,
  keyV: number,
  keys: RecordKeys,
  removed: string[],
): Promise<void> {
  const store = await createEncryptedStore(userId);
  try {
    // a 2a vault's legacy names move to their version first, or a later load would overwrite
    await migrateLegacyKeys(store);
    await store.putKey(recordKeyName(keyV), keys.record);
    await store.putKey(dedupeKeyName(keyV), keys.dedupe);
    await store.setMeta("keyV", keyV);
    const [settings] = await store.list("settings");
    if (!settings) return;
    const before = settings.body.revokedDevices ?? [];
    const revoked = [...new Set([...before, ...removed])];
    if (revoked.length === before.length) return;
    await store.put("settings", settings.id, { ...settings.body, revokedDevices: revoked });
  } finally {
    store.close();
  }
}

/**
 * A new recovery key (spec 7.5: no rotation): a new secret wraps DK, opened from this browser's
 * own device wrap, at the current `keyV`. `recoveryKey` is shown; `commit()` PUTs the wrap, which
 * replaces the account's recovery wrap (`rotated_elsewhere` when the key version moved meanwhile:
 * make it again). Retry-safe: the same id and wrap on every try, and a PUT whose answer was lost
 * counts as saved when `GET /v2/keys` shows the prepared wrap (`landed()`). Any other failure may
 * still have been saved: the caller keeps showing the key and retries. DK and the secret are
 * zeroed before this returns.
 */
export async function newRecoveryKey(
  options: KeysOptions,
): Promise<{ recoveryKey: string; commit(): Promise<void> }> {
  const { userId } = options;
  const call = api(options);
  const secret = newRecoverySecret();
  try {
    const recoveryKey = formatRecoveryKey(secret);
    const body = await withDataKey(options, async (dataKey, keyV) => ({
      kind: "recovery",
      keyV,
      wrapped: toBase64Url(await wrapDataKey(secret, { kind: "recovery", userId, keyV }, dataKey)),
    }));
    const id = uuidv7();
    /** The server's recovery wrap is the prepared one: an answer lost on the way was a success. */
    async function landed(): Promise<boolean> {
      try {
        const wrap = (await listWraps(call)).find((w) => w.kind === "recovery");
        return wrap?.id === id && wrap.wrapped === body.wrapped;
      } catch {
        return false;
      }
    }
    async function send(): Promise<void> {
      try {
        await call(`/v2/keys/${id}`, putJson(body));
      } catch (error) {
        // `rotated_elsewhere` was refused for sure; anything else may have been kept.
        const refused = error instanceof KeysError && error.code === "rotated_elsewhere";
        if (refused || !(await landed())) throw error;
      }
    }
    let sent: Promise<void> | null = null;
    return {
      recoveryKey,
      commit() {
        sent ??= send().catch((error) => {
          sent = null;
          throw error;
        });
        return sent;
      },
    };
  } finally {
    secret.fill(0);
  }
}
