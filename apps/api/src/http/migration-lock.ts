import { createMiddleware } from "hono/factory";
import type { AppDeps } from "../deps.ts";
import type { AppEnv } from "../env.ts";
import { migrationWriteRefusal } from "../services/migration.ts";

/**
 * The migration's write rule (spec 2026-11-19 §1): while the account is `migrating`, a write to
 * the records or the key material (`POST /v2/sync`, `/v2/keys*`, `/v2/pairing*`,
 * `PUT /v2/recovery/verifier`) from any session but the one bound by `POST /v2/migration/start`
 * (an assistant's token included) is 409 `migration_in_progress`, so the count `finish` checks
 * cannot change under it. Reads pass. Mounted after `requireUser` and the scopes.
 */
export function migrationWriteRule(deps: Pick<AppDeps, "db">) {
  return createMiddleware<AppEnv>(async (c, next) => {
    if (c.req.method !== "GET" && c.req.method !== "HEAD") {
      const grant = c.get("grant");
      const refusal = await migrationWriteRefusal(
        deps.db,
        c.get("userId"),
        grant.kind === "session" ? grant.sessionId : null,
      );
      if (refusal) throw refusal;
    }
    await next();
  });
}
