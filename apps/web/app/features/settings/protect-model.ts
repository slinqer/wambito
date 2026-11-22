/**
 * "Protect your data" (spec 2026-11-15 section 5.2): the checklist an account without an email
 * sees at the top of Settings → Security. Pure: `ProtectSection` loads the inputs.
 */

export interface ProtectInput {
  /** The profile's `isAnonymous`: an account made by the phone, no email. */
  anonymous: boolean;
  /** The settings record's `recoveryKeySavedAt`: a recovery key shown and typed back. */
  recoveryKeySavedAt: string | null;
  /** A passkey wrap exists (`kind: "passkey"`): a passkey opens the data. */
  passkeyWrap: boolean;
  /** One of the person's passkeys has no wrap (its provider gave no PRF). */
  passkeyWithoutWrap: boolean;
  /** This browser can make a passkey (`passkeysSupported()`). */
  passkeysSupported: boolean;
}

export interface ProtectStatus {
  /** The "N of 2" count shows: nothing is done yet (then the block stays as a quiet list). */
  show: boolean;
  /** Step 1 is done: a recovery key was saved. */
  recoveryKey: boolean;
  /** Step 2 is done: a passkey wrap exists (never the passkey row alone). */
  passkey: boolean;
  /** Step 2 is shown: only where this browser can make a passkey. */
  passkeyOffered: boolean;
  /** A passkey that signs in but cannot open the data: step 2 says so. */
  passkeyWithoutPrf: boolean;
  /** How many of the first two steps are done (0, 1 or 2). */
  done: number;
  /** One of the first two is done: the data can be opened again elsewhere. */
  protected: boolean;
}

/** Null for an account with an email (it never sees the block). */
export function protectStatus(input: ProtectInput): ProtectStatus | null {
  if (!input.anonymous) return null;
  const recoveryKey = input.recoveryKeySavedAt !== null;
  const passkey = input.passkeyWrap;
  const done = (recoveryKey ? 1 : 0) + (passkey ? 1 : 0);
  return {
    show: done === 0,
    recoveryKey,
    passkey,
    passkeyOffered: input.passkeysSupported,
    passkeyWithoutPrf: input.passkeysSupported && !passkey && input.passkeyWithoutWrap,
    done,
    protected: done > 0,
  };
}
