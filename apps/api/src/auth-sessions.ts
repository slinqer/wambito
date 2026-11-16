import type { BetterAuthPlugin } from "better-auth";
import {
  APIError,
  createAuthEndpoint,
  createAuthMiddleware,
  setShouldSkipSessionRefresh,
} from "better-auth/api";
import { parseCookies, setSessionCookie } from "better-auth/cookies";
import * as z from "zod";
import type { SessionLifetime } from "./services/sessions.ts";

const LIFETIMES = ["standard", "long", "short"] as const satisfies readonly SessionLifetime[];

/** The server-only endpoint's path: the session create hook keeps the lifetime it gives. */
export const SERVER_SESSION_PATH = "/wambito/server-session";

/**
 * The session token a request presents, from `Authorization: Bearer` (the app) or the session
 * cookie (the web), without its signature; null without one. Better Auth checks the signature;
 * this only decides whether to refresh, so a forged token can only stop a refresh.
 */
function presentedToken(headers: Headers | undefined, cookieName: string): string | null {
  const bearer = /^Bearer\s+(\S+)$/i.exec(headers?.get("authorization") ?? "")?.[1];
  const signed = bearer ?? parseCookies(headers?.get("cookie") ?? "").get(cookieName);
  if (!signed) return null;
  let value = signed;
  try {
    value = decodeURIComponent(signed);
  } catch {}
  return value.split(".")[0] || null;
}

/**
 * Sessions made by our own routes (a recovery-key sign-in, a web QR pickup), through Better Auth so
 * that its session hooks, cookies and bearer token apply as for any sign-in. `SERVER_ONLY`: the
 * router never serves it; only `auth.api.createServerSession` reaches it, after the route has
 * proved who the person is.
 *
 * The lifetime travels on the session row (`overrideAll`, so Better Auth's `standard` default does
 * not replace it), and the session create hook in auth.ts keeps it as given, `standard` included
 * (it recomputes only sessions Better Auth makes itself). A `short` session is Better Auth's "don't remember me":
 * a signed `dont_remember` cookie and a session cookie without `Max-Age`.
 */
export const wambitoSessions = () =>
  ({
    id: "wambito-sessions",
    hooks: {
      before: [
        {
          // A `short` session (an unticked web sign-in) is never refreshed, on any path. Better
          // Auth skips the refresh only when the browser sends its `dont_remember` cookie; a bearer
          // token, or a cookie header without it, would otherwise be slid to 60 days (its refresh
          // window starts 59 days before an expiry a 12-hour session is always inside) and get a
          // cookie with a Max-Age. Request-scoped, so every session read of this call skips it.
          matcher: () => true,
          handler: createAuthMiddleware(async (ctx) => {
            const headers = ctx.headers ?? ctx.request?.headers;
            const token = presentedToken(headers, ctx.context.authCookies.sessionToken.name);
            if (!token) return;
            const found = (await ctx.context.adapter.findOne({
              model: "session",
              where: [{ field: "token", value: token }],
              select: ["lifetime"],
            })) as { lifetime?: unknown } | null;
            if (found?.lifetime === "short") await setShouldSkipSessionRefresh(true);
          }),
        },
      ],
    },
    endpoints: {
      createServerSession: createAuthEndpoint(
        SERVER_SESSION_PATH,
        {
          method: "POST",
          body: z.object({ userId: z.string().min(1), lifetime: z.enum(LIFETIMES) }),
          metadata: { SERVER_ONLY: true },
        },
        async (ctx) => {
          const { userId, lifetime } = ctx.body;
          const user = await ctx.context.internalAdapter.findUserById(userId);
          if (!user) throw new APIError("NOT_FOUND", { message: "No such user" });
          const dontRememberMe = lifetime === "short";
          const session = await ctx.context.internalAdapter.createSession(
            userId,
            dontRememberMe,
            { lifetime },
            true,
          );
          if (!session) {
            throw new APIError("INTERNAL_SERVER_ERROR", { message: "No session was created" });
          }
          await setSessionCookie(ctx, { session, user }, dontRememberMe);
          return ctx.json({ userId });
        },
      ),
    },
  }) satisfies BetterAuthPlugin;
