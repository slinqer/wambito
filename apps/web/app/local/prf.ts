import { fromBase64Url, PRF_SALT } from "@wambito/crypto";
import { KeysError, type PasskeySecret } from "./keys.ts";

/**
 * A passkey's PRF (WebAuthn `prf` extension, spec 2026-11-08 section 4.1): the 32 bytes a passkey
 * gives for `PRF_SALT`, which open that passkey's wrap of DK. They never leave this browser and
 * are never stored: the sign-in's PRF waits in module memory (`keepSignInPrf`) until the vault
 * gate takes it, and is zeroed after use, on sign-out and once the app is open.
 *
 * Providers differ (docs/superpowers/reports/2026-11-08-e2e-spikes.md): Google Password Manager
 * returns 32 bytes; the Proton Pass and 1Password extensions return `prf: {}`. A registration may
 * return `prf: { enabled: true }` without results: the PRF then needs a second touch.
 */

/** The credential that was touched (base64url, as Better Auth stores `credentialID`) and its PRF. */
export type PasskeyPrf = PasskeySecret;

/** The WebAuthn extension input: evaluate the PRF at `PRF_SALT` (a copy, so nothing changes it). */
export function prfExtension(): { prf: { eval: { first: Uint8Array } } } {
  return { prf: { eval: { first: PRF_SALT.slice() } } };
}

const asBytes = (value: unknown): Uint8Array | null => {
  if (value instanceof ArrayBuffer) return new Uint8Array(value);
  if (ArrayBuffer.isView(value)) {
    return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  }
  return null;
};

type PrfResults = { prf?: { enabled?: unknown; results?: { first?: unknown } } };

const prfOf = (clientExtensionResults: unknown) =>
  clientExtensionResults && typeof clientExtensionResults === "object"
    ? (clientExtensionResults as PrfResults).prf
    : undefined;

/**
 * `prf.results.first` from `getClientExtensionResults()`, copied, only when it is 32 bytes; else
 * null (no extension, `prf: {}`, `enabled` without results, another length). The browser's bytes
 * are zeroed once read: only the returned copy holds the PRF.
 */
export function readPrf(clientExtensionResults: unknown): Uint8Array | null {
  const bytes = asBytes(prfOf(clientExtensionResults)?.results?.first);
  if (!bytes) return null;
  const copy = bytes.byteLength === 32 ? bytes.slice() : null;
  bytes.fill(0);
  return copy;
}

/** Whether a registration's results say the passkey supports PRF but gave no output yet. */
export function prfEnabledWithoutResults(clientExtensionResults: unknown): boolean {
  const prf = prfOf(clientExtensionResults);
  return prf?.enabled === true && asBytes(prf.results?.first) === null;
}

const isCancel = (error: unknown) =>
  error instanceof DOMException &&
  (error.name === "NotAllowedError" || error.name === "AbortError");

/**
 * A touch of one of the person's passkeys (of `credentialIds` when given) only to evaluate its
 * PRF: a raw `navigator.credentials.get` with a random challenge for this site, user verification
 * required. Nothing goes to the server (the assertion is not verified anywhere: the PRF opening a
 * wrap is the proof). Null when the person cancels; `KeysError("no_prf")` when the passkey gives no
 * PRF.
 */
export async function evaluatePrf(credentialIds?: string[]): Promise<PasskeyPrf | null> {
  const challenge = crypto.getRandomValues(new Uint8Array(32));
  let credential: Credential | null;
  try {
    credential = await navigator.credentials.get({
      publicKey: {
        challenge,
        rpId: location.hostname,
        userVerification: "required",
        ...(credentialIds
          ? {
              allowCredentials: credentialIds.map((id) => ({
                type: "public-key" as const,
                id: fromBase64Url(id) as BufferSource,
              })),
            }
          : {}),
        extensions: prfExtension() as AuthenticationExtensionsClientInputs,
      },
    });
  } catch (error) {
    if (isCancel(error)) return null;
    throw error;
  }
  if (!credential) return null;
  const pk = credential as PublicKeyCredential;
  const prf = readPrf(pk.getClientExtensionResults());
  if (!prf) throw new KeysError("no_prf");
  return { credentialId: pk.id, prf };
}

/**
 * The sign-in's (or a fresh registration's) PRF, for the vault gate of the account it belongs to:
 * memory only, read once.
 */
let signInPrf: (PasskeyPrf & { userId: string }) | null = null;

/** Keeps a PRF for `userId`'s gate, zeroing any earlier one. The stash now owns `value.prf`. */
export function keepSignInPrf(value: PasskeyPrf & { userId: string }): void {
  if (signInPrf && signInPrf.prf !== value.prf) signInPrf.prf.fill(0);
  signInPrf = value;
}

/**
 * The kept PRF, once, when it is `userId`'s: the caller owns (and zeroes) it after. Another
 * account's (the session changed after a passkey sign-in) is zeroed and dropped: null.
 */
export function takeSignInPrf(userId: string): PasskeyPrf | null {
  const value = signInPrf;
  signInPrf = null;
  if (!value) return null;
  if (value.userId !== userId) {
    value.prf.fill(0);
    return null;
  }
  return { credentialId: value.credentialId, prf: value.prf };
}

/** Zeroes and drops the kept PRF (sign-out, a plain account, the open app). */
export function clearSignInPrf(): void {
  signInPrf?.prf.fill(0);
  signInPrf = null;
}
