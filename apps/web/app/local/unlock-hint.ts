import { readStored, removeStored, writeStored } from "../lib/stored.ts";

/**
 * "A passkey touch here gave no PRF" (spec 2026-11-20, section 1): a non-secret hint per user id,
 * so the unlock screen leads with the recovery key on a device whose password manager signs the
 * person in but will not open the data. A boolean, never a credential id. It survives a reload
 * and a sign-out; deleting the account removes it. Storage may be missing or blocked: then the
 * hint reads false and nothing throws.
 */
const name = (userId: string) => `unlock.no-prf.${userId}`;

/** Whether the last passkey touch for `userId` on this device gave no PRF. */
export function passkeyGaveNoPrf(userId: string): boolean {
  return readStored(name(userId)) === "1";
}

/** A passkey touch for `userId` (sign-in or unlock) gave no PRF. */
export function notePasskeyWithoutPrf(userId: string): void {
  writeStored(name(userId), "1");
}

/** A passkey's PRF opened `userId`'s data here: the hint no longer holds. */
export function notePasskeyOpened(userId: string): void {
  removeStored(name(userId));
}

/** Removes the hint (the account's local data is deleted). */
export function forgetUnlockHint(userId: string): void {
  removeStored(name(userId));
}
