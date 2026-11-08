import { createMiddleware } from "hono/factory";
import type { AppEnv } from "../env.ts";
import { ApiError } from "./problem.ts";

/**
 * What an assistant's token may reach: reading and writing the person's finances. The account
 * itself (deleting it, exporting it, claiming an email, imports, connected assistants) stays with
 * the person's own sessions.
 */
const ASSISTANT_PATHS = [
  /^\/v1\/categories(\/|$)/,
  /^\/v1\/transactions(\/|$)/,
  /^\/v1\/recurrences(\/|$)/,
  /^\/v1\/summary$/,
  /^\/v1\/reports\//,
  // Encrypted records: GET pulls (finance:read), POST pushes (finance:write). Nothing else under
  // /v2 (keys, pairing) is reachable by an assistant here.
  /^\/v2\/sync$/,
];

/**
 * Enforces an OAuth grant's scopes (the API decides, not the MCP): reads need `finance:read`,
 * anything else `finance:write`, and paths outside ASSISTANT_PATHS are refused. `GET /v1/me` is
 * readable, for the person's time zone, locale and currency. Sessions pass untouched.
 */
export function assistantScopes() {
  return createMiddleware<AppEnv>(async (c, next) => {
    const grant = c.get("grant");
    if (grant.kind === "oauth") {
      const path = c.req.path.replace(/^.*?(?=\/v[12]\/)/, "");
      const read = c.req.method === "GET" || c.req.method === "HEAD";
      const reachable = ASSISTANT_PATHS.some((p) => p.test(path)) || (read && path === "/v1/me");
      const needed = read ? "finance:read" : "finance:write";
      if (!reachable || !grant.scopes.includes(needed)) {
        throw new ApiError(403, "insufficient_scope", `This assistant cannot do that`);
      }
    }
    await next();
  });
}
