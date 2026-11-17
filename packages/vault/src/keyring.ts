import type { RecordKeys } from "@wambito/crypto";

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
/** The record keys this browser holds, by key version; `current` is the account's newest. */
export interface Keyring {
  current: number;
  byVersion: Map<number, RecordKeys>;
}
