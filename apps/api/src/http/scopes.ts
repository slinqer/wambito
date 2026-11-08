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
  // /v2 (keys, pairing) is reachable by an assistant here; only reads below add its own wrap.
  /^\/v2\/sync$/,
];

/** Paths an assistant may only read (GET or HEAD), on top of ASSISTANT_PATHS. */
const ASSISTANT_WRAP_PATH = "/v2/keys/assistant";
const READABLE_PATHS = ["/v1/me", ASSISTANT_WRAP_PATH];
const FINANCE_SCOPES = ["finance:read", "finance:write"];

/**
 * Enforces an OAuth grant's scopes (the API decides, not the MCP): reads need `finance:read`,
 * anything else `finance:write`, and paths outside ASSISTANT_PATHS are refused. `GET /v1/me` is
 * readable, for the person's time zone, locale and currency, and `GET /v2/keys/assistant`, for the
 * assistant's own wrap of the data key (either scope). Sessions pass untouched.
 */
export function assistantScopes() {
  return createMiddleware<AppEnv>(async (c, next) => {
    const grant = c.get("grant");
    if (grant.kind === "oauth") {
      const path = c.req.path.replace(/^.*?(?=\/v[12]\/)/, "");
      const read = c.req.method === "GET" || c.req.method === "HEAD";
      const reachable =
        ASSISTANT_PATHS.some((p) => p.test(path)) || (read && READABLE_PATHS.includes(path));
      const needed = read ? "finance:read" : "finance:write";
      // An assistant needs its wrap to read or to write, so either scope reaches it.
      const scoped =
        path === ASSISTANT_WRAP_PATH
          ? FINANCE_SCOPES.some((scope) => grant.scopes.includes(scope))
          : grant.scopes.includes(needed);
      if (!reachable || !scoped) {
        throw new ApiError(403, "insufficient_scope", `This assistant cannot do that`);
      }
    }
    await next();
  });
}
