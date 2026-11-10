import { createRoute, z } from "@hono/zod-openapi";
import { bodyLimit } from "hono/body-limit";
import type { AppDeps } from "../deps.ts";
import { jsonBody, jsonResponse, problems } from "../http/openapi.ts";
import { ApiError } from "../http/problem.ts";
import { router } from "../http/router.ts";
import { PulledRecords, PushRecords, PushResults } from "../http/schemas.ts";
import { pullRecords, pushRecords } from "../services/sync.ts";

/** Largest `POST /v2/sync` request body. */
export const MAX_SYNC_REQUEST = 4 * 1024 * 1024;

/**
 * End-to-end encrypted records (spec 2026-11-08 section 6): the server stores and serves opaque
 * bodies; it never reads them, and never logs them.
 */
export function syncRoutes(deps: AppDeps) {
  const app = router();

  app.post(
    "/v2/sync",
    bodyLimit({
      maxSize: MAX_SYNC_REQUEST,
      onError: () => {
        throw new ApiError(413, "payload_too_large", "A sync request is at most 4 MiB");
      },
    }),
  );

  app.openapi(
    createRoute({
      method: "get",
      path: "/v2/sync",
      operationId: "pullRecords",
      description:
        "The person's records with a version above `since`, oldest first. `since=0` downloads everything; follow `next` until it is null, then keep `latest` for the next pull. `base` is the `latest` the cycle started from (0 for a full download, so paging one never fails; defaults to `since`). 410 `resync_required` when `0 < base` and `base` is below the version of a tombstone the server has purged: the device may have missed deletions, so it downloads everything again from `since=0&base=0`.",
      request: {
        query: z.object({
          since: z.coerce.number().int().min(0),
          limit: z.coerce.number().int().min(1).max(1000).default(500),
          base: z.coerce.number().int().min(0).optional().openapi({
            description:
              "The `latest` this pull cycle started from (0 for a full download); defaults to `since`",
          }),
        }),
      },
      responses: { 200: jsonResponse(PulledRecords, "Records"), ...problems(410, 422) },
    }),
    async (c) => {
      const { since, limit, base } = c.req.valid("query");
      return c.json(await pullRecords(deps.db, c.get("userId"), since, limit, base), 200);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v2/sync",
      operationId: "pushRecords",
      description:
        "Applies each change on its own, in order: `baseVersion: null` creates (a retry of the same create answers the stored version), otherwise the change applies only on the stored version. An update also needs the stored type (a record's type never changes). Each result is the new version, a conflict with the current record, `id_taken` when the id is someone else's, `not_found` for an update of a record the server does not have (resync in full), or `key_version_mismatch` (with the current `keyV`) when the change's `keyV` is not the account's current key version and the account has key wraps.",
      request: { body: jsonBody(PushRecords) },
      responses: {
        200: jsonResponse(PushResults, "One result per change, in request order"),
        ...problems(409, 413, 422),
      },
    }),
    async (c) => {
      const { changes } = c.req.valid("json");
      const results = await pushRecords(deps.db, c.get("userId"), changes, deps.syncHooks);
      return c.json({ results }, 200);
    },
  );

  return app;
}
