import { createRoute } from "@hono/zod-openapi";
import { platformOf } from "../auth.ts";
import type { AppDeps } from "../deps.ts";
import { clientHeader } from "../http/client-headers.ts";
import { problems } from "../http/openapi.ts";
import { router } from "../http/router.ts";
import { appVersionOf, markSeen } from "../services/activity.ts";
import { nowOf, userToday } from "../services/time.ts";

/** The app says it is open: the first call of the person's local day counts in the daily activity. */
export function activityRoutes(deps: AppDeps) {
  const app = router();

  app.openapi(
    createRoute({
      method: "post",
      path: "/v2/me/seen",
      operationId: "markSeen",
      description:
        "The app was opened by the person. The first call of their local day counts one in the daily activity numbers, which keep no per-person history; later calls the same day count nothing. `x-wambito-client` says the platform and `x-wambito-version` the app's version (up to 64 characters). A call with `x-wambito-background: 1` changes nothing: background work never calls this. Not for assistants.",
      responses: { 204: { description: "Noted" }, ...problems(401, 403) },
    }),
    async (c) => {
      const headers = c.req.raw.headers;
      if (clientHeader(headers, "background") === "1") return c.body(null, 204);
      await markSeen(deps.db, {
        userId: c.get("userId"),
        today: userToday(deps, c.get("user")),
        platform: platformOf(headers),
        appVersion: appVersionOf(clientHeader(headers, "version")),
        now: nowOf(deps),
      });
      return c.body(null, 204);
    },
  );

  return app;
}
