import type { BetterAuthPlugin } from "better-auth";
import { APIError, createAuthEndpoint } from "better-auth/api";
import { setSessionCookie } from "better-auth/cookies";
import * as z from "zod";
import type { SessionLifetime } from "./services/sessions.ts";

const LIFETIMES = ["standard", "long", "short"] as const satisfies readonly SessionLifetime[];

/**
 * Sessions made by our own routes (a recovery-key sign-in, a web QR pickup), through Better Auth so
 * that its session hooks, cookies and bearer token apply as for any sign-in. `SERVER_ONLY`: the
 * router never serves it; only `auth.api.createServerSession` reaches it, after the route has
 * proved who the person is.
 *
 * The lifetime travels on the session row (`overrideAll`, so Better Auth's `standard` default does
 * not replace it), and the session create hook in auth.ts keeps a `long` or `short` one (a
 * `standard` one is computed there again). A `short` session is Better Auth's "don't remember me":
 * a signed `dont_remember` cookie and a session cookie without `Max-Age`.
 */
export const wambitoSessions = () =>
  ({
    id: "wambito-sessions",
    endpoints: {
      createServerSession: createAuthEndpoint(
        "/wambito/server-session",
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
