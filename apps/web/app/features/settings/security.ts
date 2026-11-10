import { createEncryptedStore } from "../../local/encrypted-store.ts";
import { addPasskeyWrap, api, type KeysOptions, listWraps, withDataKey } from "../../local/keys.ts";
import {
  type ApproverPairing,
  findPairing as findRealPairing,
  type PairingOptions,
} from "../../local/pairing.ts";
import { evaluatePrf, type PasskeyPrf } from "../../local/prf.ts";
import {
  attested,
  checkRecoveryKey,
  newRecoveryKey,
  type RotateResult,
  revokedDevices,
  rotateKeys,
} from "../../local/rotate.ts";
import type { VaultSession } from "../../local/vault-session.ts";
import type { SecurityWrap } from "./security-model.ts";

/** The react-query key of `SecurityApi.load()` (Security and the passkeys' "Unlocks" share it). */
export const SECURITY_KEY = ["security"] as const;

/** What Settings → Security reads: the wraps, this browser's, the revoked list, the checks. */
export interface SecuritySnapshot {
  wraps: SecurityWrap[];
  /** This browser's device wrap id (meta `deviceWrapId`), null when unknown. */
  ownId: string | null;
  revoked: string[];
  /** Device wrap ids whose attestation checks out under the data key. */
  verified: Set<string>;
  /** Records the sync could not open (the vault's `quarantine` store). */
  unreadable: number;
}

export interface RotateRequest {
  remove: string[];
  recovery: { text: string } | { fresh: true };
  /** A touched passkey with its PRF: it keeps its wrap. Used up (zeroed) by the call. */
  passkey?: PasskeyPrf;
}

/**
 * Settings → Security's effects, as a prop so stories stand in for the vault, WebAuthn and
 * `/v2/keys`. Errors carry a `code` (`KeysError` / `PairingError` codes).
 */
export interface SecurityApi {
  load(): Promise<SecuritySnapshot>;
  rotate(request: RotateRequest): Promise<{
    recoveryKey: string | null;
    commit(): Promise<RotateResult>;
  }>;
  /** Resolves when `text` opens the current recovery wrap (`bad_` / `wrong_recovery_key`). */
  checkRecoveryKey(text: string): Promise<void>;
  newRecoveryKey(): Promise<{ recoveryKey: string; commit(): Promise<void> }>;
  /** After a rotation committed: the sync takes the new keyring. */
  reloadKeys(): Promise<void>;
  /** A passkey touch for its PRF: null when cancelled; `{ code: "no_prf" }` without one. */
  evaluatePrf(credentialIds?: string[]): Promise<PasskeyPrf | null>;
  /** The touched passkey's wrap, from this browser's device wrap. The caller zeroes the PRF. */
  addPasskeyWrap(passkey: PasskeyPrf): Promise<void>;
  /** Approving a new device (`ApproveDevice`). */
  pairing: PairingOptions;
  findPairing?: (
    options: PairingOptions & ({ code: string } | { qr: string }),
  ) => Promise<ApproverPairing>;
  scanSupported?(): boolean;
}

/** The open vault's keys, against the real `/v2/keys`, WebAuthn and IndexedDB. */
export function liveSecurity(session: VaultSession): SecurityApi {
  const options: KeysOptions = { userId: session.userId };
  return {
    async load() {
      const wraps = (await listWraps(api(options))) as SecurityWrap[];
      const store = await createEncryptedStore(session.userId);
      let ownId: string | null;
      let unreadable: number;
      try {
        ownId = (await store.getMeta<string>("deviceWrapId")) ?? null;
        unreadable = await store.quarantineCount();
      } finally {
        store.close();
      }
      const revoked = await revokedDevices(session.userId);
      const verified = new Set<string>();
      const others = wraps.filter((w) => w.kind === "device" && w.id !== ownId);
      if (others.length > 0) {
        await withDataKey(options, async (dataKey) => {
          for (const wrap of others) {
            if (await attested(session.userId, dataKey, wrap)) verified.add(wrap.id);
          }
        });
      }
      return { wraps, ownId, revoked, verified, unreadable };
    },
    rotate: (request) => rotateKeys({ ...options, ...request }),
    checkRecoveryKey: (text) => checkRecoveryKey({ ...options, text }),
    newRecoveryKey: () => newRecoveryKey(options),
    reloadKeys: () => session.reloadKeys(),
    evaluatePrf: (ids) => evaluatePrf(ids),
    addPasskeyWrap: (passkey) => addPasskeyWrap({ ...options, ...passkey }),
    pairing: options,
    findPairing: findRealPairing,
  };
}

export const codeOf = (error: unknown): string | undefined =>
  error && typeof error === "object" && "code" in error && typeof error.code === "string"
    ? error.code
    : undefined;
