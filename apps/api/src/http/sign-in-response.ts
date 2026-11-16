import { APIError } from "better-auth/api";
import type { Context } from "hono";
import type { Auth } from "../auth.ts";
import type { SessionLifetime } from "../services/sessions.ts";
import { ApiError } from "./problem.ts";

/**
 * Signs `userId` in on this response, once a route has proved who the person is: a session of
 * `lifetime` made by Better Auth (`createServerSession`, auth-sessions.ts), whose `set-cookie`
 * headers and `set-auth-token` (the bearer token the app keeps) are copied onto `c`. The session
 * create hook still applies: a suspended account gets 403 `account_suspended` and no session.
 */
export async function signInAs(
  auth: Auth,
  c: Context,
  userId: string,
  lifetime: SessionLifetime,
): Promise<void> {
  let headers: Headers;
  try {
    ({ headers } = await auth.api.createServerSession({
      body: { userId, lifetime },
      headers: c.req.raw.headers,
      returnHeaders: true,
    }));
  } catch (error) {
    if (error instanceof APIError) {
      const body = error.body as { code?: unknown; message?: unknown } | undefined;
      const code = typeof body?.code === "string" ? body.code.toLowerCase() : "sign_in_failed";
      throw new ApiError(
        error.statusCode,
        code,
        typeof body?.message === "string" ? body.message : undefined,
      );
    }
    throw error;
  }
  for (const cookie of headers.getSetCookie()) c.header("set-cookie", cookie, { append: true });
  const token = headers.get("set-auth-token");
  if (token) {
    c.header("set-auth-token", token);
    c.header("access-control-expose-headers", "set-auth-token");
  }
}
