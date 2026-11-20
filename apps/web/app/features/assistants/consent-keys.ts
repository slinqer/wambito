import type { DataKeySource, PasskeySecret } from "../../local/keys.ts";
import { KeysError } from "../../local/keys.ts";
import type { UnlockMeans } from "../vault/vault-gate.ts";
import type { ConsentKeys } from "./consent-model.ts";

/** What the consent page's keys use; the route passes the live ones, the tests fakes. */
export interface ConsentKeysDeps {
  /** `keys.ts` `withDataKeyFrom`, for the signed-in account. */
  withDataKeyFrom<T>(
    options: { userId: string },
    source: DataKeySource,
    fn: (dk: Uint8Array, keyV: number) => Promise<T>,
  ): Promise<T>;
  /** `prf.ts` `evaluatePrf`: null when cancelled, `KeysError("no_prf")` without a PRF. */
  evaluatePrf(credentialIds?: string[]): Promise<PasskeySecret | null>;
  /** The signed-in account's passkey credential ids; throws when unreadable. */
  accountPasskeyIds(): Promise<string[]>;
  /** `unlock-hint.ts`: a passkey touch here gave no PRF. */
  notePasskeyWithoutPrf(userId: string): void;
  /** `unlock-hint.ts`: a passkey's PRF opened the data here. */
  notePasskeyOpened(userId: string): void;
}

const codeOf = (error: unknown): string | undefined =>
  error && typeof error === "object" && "code" in error && typeof error.code === "string"
    ? error.code
    : undefined;

/**
 * The consent page's keys for an encrypted account, as the vault gate treats a passkey (spec
 * 2026-11-20 section 1): a touch offers only the account's passkeys (none: `no_passkey_wrap`, no
 * touch; an unreadable list leaves the browser's choice open); one without PRF notes the "no PRF
 * here" hint for this account, only when the touch was limited to its passkeys (another account's
 * passkey must never mark it), so a reload of the page leads with the recovery key; a passkey's PRF
 * that opens the data key clears it. The hint never fails the step.
 */
export function consentKeysOf(
  account: { userId: string; device: boolean; means?: UnlockMeans | undefined },
  deps: ConsentKeysDeps,
): ConsentKeys {
  const { userId, device, means } = account;
  const quietly = (note: (userId: string) => void) => {
    try {
      note(userId);
    } catch {
      // A hint that cannot be written only costs a different layout.
    }
  };
  return {
    userId,
    device,
    open: (source, fn) =>
      deps.withDataKeyFrom({ userId }, source, (dk, keyV) => {
        // DK is open: when a passkey's PRF opened it, that passkey works here.
        if ("prf" in source) quietly(deps.notePasskeyOpened);
        return fn(dk, keyV);
      }),
    async touchPasskey() {
      let ids: string[] | undefined;
      try {
        ids = await deps.accountPasskeyIds();
      } catch {
        ids = undefined;
      }
      if (ids && ids.length === 0) throw new KeysError("no_passkey_wrap");
      try {
        return await deps.evaluatePrf(ids);
      } catch (error) {
        if (codeOf(error) === "no_prf" && ids !== undefined) quietly(deps.notePasskeyWithoutPrf);
        throw error;
      }
    },
    ...(means ? { means } : {}),
  };
}
