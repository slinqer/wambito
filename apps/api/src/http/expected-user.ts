import { createMiddleware } from "hono/factory";
import type { AppEnv } from "../env.ts";
import { clientHeader } from "./client-headers.ts";
import { ApiError } from "./problem.ts";

/**
 * A `/v2` call may name the account it means (`x-wambito-user`, the id a web vault belongs to).
 * When the signed-in account is another one (someone signed in as another person in another tab),
 * it answers 409 `session_changed` before anything is read or written. After `requireUser`.
 */
export function expectedUser() {
  return createMiddleware<AppEnv>(async (c, next) => {
    const expected = clientHeader(c.req.raw.headers, "user");
    if (expected !== undefined && expected !== c.get("userId")) {
      throw new ApiError(409, "session_changed", "The signed-in account is not the one expected");
    }
    await next();
  });
}
