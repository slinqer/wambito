import type { ApiClient } from "../../api/client.ts";
import { ApiProblem } from "../../api/errors.ts";
import type { AuthErrorKey } from "../sign-in/auth.ts";

/**
 * The words for a refused claim: sign-in's `errors.*` keys, and `email_taken` with its own (the web
 * never merges two accounts, web ruling 5: it says to bring this data into that account on the phone).
 */
export type ClaimErrorKey = AuthErrorKey | "settings.add_email.taken";

/** A failed `send` or `verify`, already in the catalog's words. */
export class ClaimError extends Error {
  readonly key: ClaimErrorKey;
  constructor(key: ClaimErrorKey) {
    super(key);
    this.name = "ClaimError";
    this.key = key;
  }
}

/** The API's codes for a claim (`apps/api/src/routes/me.ts`) → the catalog's keys. */
const CODES: Record<string, ClaimErrorKey> = {
  email_taken: "settings.add_email.taken",
  invalid_code: "errors.invalid_code",
  invalid_or_expired_code: "errors.invalid_or_expired_code",
  too_many_attempts: "errors.too_many_attempts",
  too_many_requests: "errors.too_many_requests",
  sign_in_not_allowed: "errors.sign_in_not_allowed",
  account_suspended: "errors.account_suspended",
};

export function claimErrorKey(error: unknown): ClaimErrorKey {
  if (!(error instanceof ApiProblem)) return "errors.generic";
  if (error.status === 0) return "errors.network_error";
  const known = CODES[error.code];
  if (known) return known;
  if (error.status === 422) return "errors.invalid_email";
  if (error.status === 429) return "errors.too_many_requests";
  if (error.status >= 500) return "errors.internal_error";
  return "errors.generic";
}

export interface ClaimEmail {
  /** Emails a 6-digit code to the address (`POST /v1/me/claim-email/send`). */
  send(email: string): Promise<void>;
  /** Claims the email with the code; the account stays the same user, with the same keys. */
  verify(email: string, code: string): Promise<void>;
}

/** Adding an email to the signed-in account without one, over the API client. Rejects with `ClaimError`. */
export function claimEmail(api: ApiClient): ClaimEmail {
  const run = async (call: () => Promise<unknown>) => {
    try {
      await call();
    } catch (error) {
      throw new ClaimError(claimErrorKey(error));
    }
  };
  return {
    send: (email) => run(() => api.POST("/v1/me/claim-email/send", { body: { email } })),
    verify: (email, code) =>
      run(() => api.POST("/v1/me/claim-email/verify", { body: { email, code } })),
  };
}
