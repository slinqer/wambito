import { ApiError } from "../http/problem.ts";

/**
 * The checks shared by the two relays of a sealed data key (stage 1b spec section 1): a new
 * device's pairing (`pairing.ts`) and the web's sign-in through the phone (`signin.ts`). Both rows
 * hold a commitment to the receiving key, then the approver's ephemeral key, the revealed key and
 * the sealed blob, set in that order. Pure: the services load and lock the row, these decide.
 */
export interface RelayRow {
  commitment: Uint8Array;
  approverKey: Uint8Array | null;
  publicKey: Uint8Array | null;
  sealed: Uint8Array | null;
  keyV: number | null;
}

const same = (a: Uint8Array, b: Uint8Array) => Buffer.from(a).equals(Buffer.from(b));

/** The approver key is set once; 409 `already_set` after. */
export function assertCanSetApprover(row: RelayRow): void {
  if (row.approverKey) throw new ApiError(409, "already_set", "The approver key is already set");
}

/**
 * The receiving key may be revealed once the approver key is set, once, and only when it hashes
 * to the commitment (`keyHash`, `pairingCommitment` of the key). 409 `not_ready`, 409
 * `already_set`, 422 `commitment_mismatch`.
 */
export function assertCanReveal(row: RelayRow, keyHash: Uint8Array): void {
  if (!row.approverKey) throw new ApiError(409, "not_ready", "The approver key is not set yet");
  if (row.publicKey) throw new ApiError(409, "already_set", "The key was already revealed");
  if (!same(keyHash, row.commitment)) {
    throw new ApiError(422, "commitment_mismatch", "The key does not match the commitment");
  }
}

/**
 * The sealed key is stored once, after the reveal, when it starts with the approver key and is for
 * the account's current key version (`current`, null without one). 409 `already_sealed`, 409
 * `not_ready`, 422 `approver_mismatch`, 409 `key_version_mismatch`.
 */
export function assertCanSeal(
  row: RelayRow,
  blob: Uint8Array,
  keyV: number,
  current: number | null,
): void {
  if (row.sealed) throw new ApiError(409, "already_sealed", "Already sealed");
  if (!row.approverKey || !row.publicKey) {
    throw new ApiError(409, "not_ready", "The new device has not revealed its key yet");
  }
  if (!same(blob.subarray(0, row.approverKey.length), row.approverKey)) {
    throw new ApiError(422, "approver_mismatch", "The sealed key is not from the approver key");
  }
  if (current !== keyV) {
    throw new ApiError(
      409,
      "key_version_mismatch",
      `The account's key version is ${current ?? "unset"}; the seal is for ${keyV}`,
    );
  }
}

/**
 * What the person typed, as the stored code: upper case, `I`/`L` read as 1, `O` as 0, dashes and
 * spaces dropped (the same reading as the recovery key's parser).
 */
export function normalizeRelayCode(input: string): string {
  return input.toUpperCase().replace(/[-\s]/g, "").replace(/[IL]/g, "1").replace(/O/g, "0");
}
