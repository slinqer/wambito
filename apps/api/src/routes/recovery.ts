import { createRoute } from "@hono/zod-openapi";
import { user as userTable } from "@wambito/db";
import { eq } from "@wambito/db/orm";
import { type Auth, platformOf } from "../auth.ts";
import type { AppDeps } from "../deps.ts";
import { clientIp } from "../http/client-ip.ts";
import { IpWindowLimit } from "../http/ip-limit.ts";
import { jsonBody, jsonResponse, problems } from "../http/openapi.ts";
import { ApiError } from "../http/problem.ts";
import { router } from "../http/router.ts";
import { PutRecoveryVerifier, RecoverySignedIn, RecoverySignIn } from "../http/schemas.ts";
import { signInAs } from "../http/sign-in-response.ts";
import { toEncryption } from "../services/encryption.ts";
import { findVerifiedUser, putVerifier } from "../services/recovery.ts";
import { lifetimeFor } from "../services/sessions.ts";

/** Recovery-key sign-ins per client address and window (plan decision 18). Kept in memory. */
export const RECOVERY_SIGNIN_LIMIT = { max: 10, windowMs: 10 * 60 * 1000 };

const bytes = (text: string) => new Uint8Array(Buffer.from(text, "base64url"));

/** One answer for an unknown lookup and a wrong auth, so neither tells the other apart. */
const recoveryKeyInvalid = () =>
  new ApiError(401, "recovery_key_invalid", "This recovery key does not sign in");

/**
 * The public recovery-key sign-in (spec 2026-11-15): the person typed their recovery key on a new
 * phone or in a browser, which derives `lookup` and `auth` from it (`recoveryVerifier` in
 * @wambito/crypto). Mounted before `requireUser` (app.ts): the person is signed out.
 */
export function recoverySignInRoutes(deps: AppDeps, auth: Auth) {
  const app = router();
  // Real time, not the pinned clock: the limit protects the live server.
  const limiter = new IpWindowLimit(RECOVERY_SIGNIN_LIMIT);

  app.openapi(
    createRoute({
      method: "post",
      path: "/v2/recovery/sign-in",
      operationId: "recoverySignIn",
      description: `Signs in with the recovery key: \`lookup\` and \`auth\` are what it derives. On success the session travels in the \`set-cookie\` headers (the web) and the \`set-auth-token\` header (the app's bearer token); from the app (\`x-wambito-client\`), an encrypted account without an email gets a 25-month session. 401 \`recovery_key_invalid\` for a key that does not sign in, whatever the reason; 403 \`account_suspended\`; 429 after ${RECOVERY_SIGNIN_LIMIT.max} tries per address in ${RECOVERY_SIGNIN_LIMIT.windowMs / 60_000} minutes.`,
      request: { body: jsonBody(RecoverySignIn) },
      responses: {
        200: jsonResponse(RecoverySignedIn, "Signed in; the session is in the headers"),
        ...problems(401, 403, 422, 429),
      },
    }),
    async (c) => {
      if (limiter.hit(clientIp(c.req.raw.headers, deps.config), Date.now())) {
        c.header("retry-after", String(RECOVERY_SIGNIN_LIMIT.windowMs / 1000));
        throw new ApiError(429, "too_many_requests", "Too many attempts; try again later");
      }
      const { lookup, auth: proof } = c.req.valid("json");
      const userId = await findVerifiedUser(deps.db, bytes(lookup), bytes(proof));
      if (!userId) throw recoveryKeyInvalid();
      const [found] = await deps.db
        .select({ encryption: userTable.encryption, isAnonymous: userTable.isAnonymous })
        .from(userTable)
        .where(eq(userTable.id, userId));
      if (!found) throw recoveryKeyInvalid();
      const lifetime = lifetimeFor(
        {
          encryption: toEncryption(found.encryption),
          isAnonymous: found.isAnonymous === true,
        },
        platformOf(c.req.raw.headers),
      );
      await signInAs(auth, c, userId, lifetime);
      return c.json({ userId }, 200);
    },
  );

  return app;
}

/** The signed-in person's end: storing the verifier of the recovery key they just made. */
export function recoveryRoutes(deps: AppDeps) {
  const app = router();

  app.openapi(
    createRoute({
      method: "put",
      path: "/v2/recovery/verifier",
      operationId: "putRecoveryVerifier",
      description:
        "Stores what lets the recovery key sign in: the SHA-256 of its `lookup` and of its `auth`. Replaces the earlier verifier, so only the newest key signs in; a new recovery wrap with other bytes deletes it too (store the new key's verifier after it). Needs the account's recovery wrap (409 `recovery_required`); a `lookupHash` another account holds is 409 `verifier_taken`.",
      request: { body: jsonBody(PutRecoveryVerifier) },
      responses: { 204: { description: "Stored" }, ...problems(409, 422) },
    }),
    async (c) => {
      const { lookupHash, authHash } = c.req.valid("json");
      await putVerifier(deps.db, c.get("userId"), bytes(lookupHash), bytes(authHash));
      return c.body(null, 204);
    },
  );

  return app;
}
