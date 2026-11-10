import { localArea, readStored, type StoredArea, writeStored } from "../lib/stored.ts";
import {
  evaluatePrf,
  keepSignInPrf,
  type PasskeyPrf,
  prfEnabledWithoutResults,
  prfExtension,
  readPrf,
} from "../local/prf.ts";
import { authClient } from "./auth-client.ts";

/**
 * Passkeys, as the web app uses them: what this browser remembers about them (a flag that gates
 * the sign-in screen's fingerprint button, and the offer's decision per user), whether to offer
 * one after a sign-in, and creating one. The sign-in itself is in `features/sign-in/auth.ts`.
 *
 * Everything remembered lives in `localStorage` (through `lib/stored.ts`), which can be missing or
 * blocked (private mode): then nothing is remembered and nothing breaks.
 */

/** What adding a passkey came to; `cancelled` is the person closing the browser's prompt. */
export type PasskeyOutcome = "added" | "cancelled" | "failed";

/** The part of `localStorage` used here. */
export type MemoryStorage = StoredArea;

/** Set once a passkey signed in, or was registered, in this browser (`wambito.passkey.used`). */
export const PASSKEY_USED_KEY = "passkey.used";
/**
 * The ids of the users who made their choice about the offer ("Crear mi huella" or "Ahora no"),
 * kept under `wambito.passkey.offered`.
 */
export const PASSKEY_OFFERED_KEY = "passkey.offered";

const browserStorage = localArea;

function read(storage: MemoryStorage | null, name: string): string | null {
  return readStored(name, storage);
}

function write(storage: MemoryStorage | null, name: string, value: string): void {
  writeStored(name, value, storage);
}

/** Whether this browser can use passkeys at all (WebAuthn). */
export function passkeysSupported(): boolean {
  return typeof window !== "undefined" && typeof window.PublicKeyCredential === "function";
}

/**
 * Whether the browser can offer passkeys in a text field's autofill (WebAuthn conditional
 * mediation). Checked before asking, so a browser without it makes no request at all.
 */
export async function conditionalMediationAvailable(): Promise<boolean> {
  try {
    return (
      passkeysSupported() &&
      typeof PublicKeyCredential.isConditionalMediationAvailable === "function" &&
      (await PublicKeyCredential.isConditionalMediationAvailable())
    );
  } catch {
    return false;
  }
}

/** Whether a passkey has signed in, or been registered, in this browser before. */
export function hasUsedPasskey(storage: MemoryStorage | null = browserStorage()): boolean {
  return read(storage, PASSKEY_USED_KEY) === "1";
}

/** Called after a successful passkey sign-in or registration. */
export function rememberPasskeyUsed(storage: MemoryStorage | null = browserStorage()): void {
  write(storage, PASSKEY_USED_KEY, "1");
}

/** Called when the person deleted their last passkey: the fingerprint button would only fail. */
export function forgetPasskeyUsed(storage: MemoryStorage | null = browserStorage()): void {
  write(storage, PASSKEY_USED_KEY, "0");
}

function decidedIds(storage: MemoryStorage | null): string[] {
  try {
    const parsed: unknown = JSON.parse(read(storage, PASSKEY_OFFERED_KEY) ?? "[]");
    return Array.isArray(parsed) ? parsed.filter((id) => typeof id === "string") : [];
  } catch {
    return [];
  }
}

/** Whether this user already made their choice about the offer on this device. */
export function offerDecided(
  userId: string,
  storage: MemoryStorage | null = browserStorage(),
): boolean {
  return decidedIds(storage).includes(userId);
}

/** The offer is shown once per user per device: call this on either answer. */
export function rememberOfferDecided(
  userId: string,
  storage: MemoryStorage | null = browserStorage(),
): void {
  const ids = decidedIds(storage);
  if (!ids.includes(userId)) write(storage, PASSKEY_OFFERED_KEY, JSON.stringify([...ids, userId]));
}

/** What `shouldOfferPasskey` asks about; the live ones are `liveOfferDeps`. */
export interface OfferDeps {
  supported(): boolean;
  decided(userId: string): boolean;
  /** How many passkeys the signed-in user has, or null when the list can't be read. */
  passkeyCount(): Promise<number | null>;
}

/**
 * Whether to offer a passkey right after an email sign-in: this browser can use one, the person
 * has not answered the offer on this device, and they have no passkey yet (on any device). The
 * cheap local checks come first; if the list can't be read, the offer is skipped, not blocked on.
 */
export async function shouldOfferPasskey(userId: string, deps: OfferDeps): Promise<boolean> {
  if (!deps.supported() || deps.decided(userId)) return false;
  try {
    return (await deps.passkeyCount()) === 0;
  } catch {
    return false;
  }
}

export const liveOfferDeps: OfferDeps = {
  supported: passkeysSupported,
  decided: (userId) => offerDecided(userId),
  passkeyCount: async () => {
    const { data, error } = await authClient.passkey.listUserPasskeys();
    return error || !Array.isArray(data) ? null : data.length;
  },
};

/**
 * The browser's and Better Auth's error codes when registering. Closing the prompt (or letting it
 * time out: browsers report both as `NotAllowedError`, passed through by SimpleWebAuthn) is not a
 * failure worth a message, as on sign-in. A passkey this device already has counts as added.
 */
export function passkeyOutcome(error: { code?: string | undefined } | null): PasskeyOutcome {
  if (!error) return "added";
  switch (error.code) {
    case "AUTH_CANCELLED":
    case "ERROR_CEREMONY_ABORTED":
    case "ERROR_PASSTHROUGH_SEE_CAUSE_PROPERTY":
      return "cancelled";
    case "ERROR_AUTHENTICATOR_PREVIOUSLY_REGISTERED":
      return "added";
    default:
      return "failed";
  }
}

/**
 * What a new passkey's PRF is for: an encrypted account wraps its data key under it (stage 2b).
 * Without one (a plain account), the PRF is asked for anyway (harmless) and dropped.
 */
export interface PasskeyPrfUse {
  /**
   * Whether a passkey that gave `prf.enabled` without an output is worth a second touch: the
   * account's data is encrypted. Asked only then.
   */
  wantsPrf(): Promise<boolean>;
  /** Says why the browser asks for a second touch, before it does. */
  explainSecondTouch(): void;
  /** Takes the new passkey's PRF; it owns (and zeroes) the bytes from then on. */
  keep(passkey: PasskeyPrf): Promise<void> | void;
}

/**
 * The passkey offer's use (right after sign-in, before the vault opens): the new passkey's PRF
 * waits in the stash for `userId`'s vault gate, which adds its wrap once the data is open. Whether
 * the account is encrypted comes from the caller (the profile the sign-in already read): no
 * request here, and a plain account never gets a second touch.
 */
export function offerPrfUse(options: {
  userId: string;
  encrypted: boolean;
  explainSecondTouch(): void;
}): PasskeyPrfUse {
  return {
    wantsPrf: async () => options.encrypted,
    explainSecondTouch: options.explainSecondTouch,
    keep: (passkey) => keepSignInPrf({ userId: options.userId, ...passkey }),
  };
}

/** SimpleWebAuthn's extension inputs do not list `prf`, which it passes on unchanged. */
type AddExtensions = NonNullable<Parameters<typeof authClient.passkey.addPasskey>[0]>["extensions"];

/**
 * The new passkey's PRF: from the registration itself, else (when it said `prf.enabled` without an
 * output and the account wants one) from a second touch of that passkey only. A second touch that
 * is cancelled or gives nothing leaves the passkey without a wrap: it still signs in.
 */
async function prfOfNewPasskey(
  webauthn: { response?: { id?: string }; clientExtensionResults?: unknown } | undefined,
  use: PasskeyPrfUse,
): Promise<PasskeyPrf | null> {
  const credentialId = webauthn?.response?.id;
  const prf = readPrf(webauthn?.clientExtensionResults);
  if (prf && !credentialId) prf.fill(0);
  if (!credentialId) return null;
  if (prf) return { credentialId, prf };
  if (!prfEnabledWithoutResults(webauthn?.clientExtensionResults)) return null;
  if (!(await use.wantsPrf().catch(() => false))) return null;
  use.explainSecondTouch();
  try {
    return await evaluatePrf([credentialId]);
  } catch {
    return null;
  }
}

/**
 * Creates a passkey for the signed-in user (the browser asks for the fingerprint or face), asking
 * for its PRF; `prf` says what to do with it (nothing: it is dropped).
 */
export async function addPasskey(prf?: PasskeyPrfUse): Promise<PasskeyOutcome> {
  try {
    const result = await authClient.passkey.addPasskey({
      extensions: prfExtension() as unknown as AddExtensions,
      returnWebAuthnResponse: true,
    });
    const { error } = result;
    const outcome = passkeyOutcome(
      error ? { code: "code" in error ? error.code : undefined } : null,
    );
    if (outcome === "added") rememberPasskeyUsed();
    const webauthn = (result as { webauthn?: Parameters<typeof prfOfNewPasskey>[0] }).webauthn;
    if (error || !prf) {
      // Nothing wants it: the browser's bytes are zeroed all the same.
      readPrf(webauthn?.clientExtensionResults)?.fill(0);
    } else {
      const passkey = await prfOfNewPasskey(webauthn, prf);
      if (passkey) {
        try {
          await prf.keep(passkey);
        } catch {
          // The passkey was added and signs in; it only does not open the data yet.
        }
      }
    }
    return outcome;
  } catch {
    return "failed";
  }
}
