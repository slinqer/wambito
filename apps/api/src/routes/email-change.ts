import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";
import { isSignInAllowed } from "../auth.ts";
import type { AppDeps } from "../deps.ts";
import { clientIp } from "../http/client-ip.ts";
import { IpWindowLimit } from "../http/ip-limit.ts";
import { jsonBody, problems } from "../http/openapi.ts";
import { ApiError, validationHook } from "../http/problem.ts";
import { confirmEmailChange } from "../services/admin/email-change.ts";
import { nowOf } from "../services/time.ts";

/** Confirm attempts per client address and window, like Better Auth's own per-IP limits. Kept in memory. */
export const CONFIRM_LIMIT = { max: 10, windowMs: 10 * 60 * 1000 };

const ConfirmBody = z.object({ token: z.string().min(1).max(200) }).openapi("EmailChangeConfirm");

/**
 * The public end of an admin's email change (spec §5.2): the `/confirm-email` page posts the
 * link's token here. Mounted before `requireUser` (app.ts): the person is usually signed out.
 */
export function emailChangeRoutes(deps: AppDeps) {
  const app = new OpenAPIHono({ defaultHook: validationHook });
  // Real time, not the pinned clock: the limit protects the live server.
  const limiter = new IpWindowLimit(CONFIRM_LIMIT);

  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/email-change/confirm",
      operationId: "confirmEmailChange",
      request: { body: jsonBody(ConfirmBody) },
      responses: {
        204: { description: "The email changed; every session was signed out" },
        ...problems(409, 410, 422, 429),
      },
    }),
    async (c) => {
      if (limiter.hit(clientIp(c.req.raw.headers, deps.config), Date.now())) {
        c.header("retry-after", String(CONFIRM_LIMIT.windowMs / 1000));
        throw new ApiError(429, "too_many_requests", "Too many attempts; try again later");
      }
      const { token } = c.req.valid("json");
      await confirmEmailChange(
        {
          db: deps.db,
          mailer: deps.mailer,
          webUrl: deps.config.WEB_URL,
          now: nowOf(deps),
          signInAllowed: (email) => isSignInAllowed(deps.config, email),
        },
        token,
      );
      return c.body(null, 204);
    },
  );

  return app;
}
