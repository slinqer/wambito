import { createRoute, z } from "@hono/zod-openapi";
import type { AppDeps } from "../deps.ts";
import { jsonBody, jsonResponse, problems } from "../http/openapi.ts";
import { ApiError } from "../http/problem.ts";
import { router } from "../http/router.ts";
import { KeyWrap, KeyWraps, PutKeyWrap, RotateKeys } from "../http/schemas.ts";
import {
  deleteKeyWrap,
  listKeyWraps,
  putKeyWrap,
  rotateKeys,
  useAssistantWrap,
} from "../services/keys.ts";

const idParam = z.object({ id: z.uuid() });

/**
 * The wrapped copies of the account's data key (spec 2026-11-08 sections 5.2 and 7): one per
 * passkey, the recovery key, each device and each connected assistant. The server stores opaque
 * bytes; it never unwraps anything. Assistants reach only `GET /v2/keys/assistant` (scopes.ts).
 */
export function keyRoutes(deps: AppDeps) {
  const app = router();

  // Before `/v2/keys/{id}`, which takes only uuids anyway.
  app.openapi(
    createRoute({
      method: "get",
      path: "/v2/keys/assistant",
      operationId: "getAssistantWrap",
      description:
        "For an assistant's token: the wrap of that assistant (its OAuth client), and marks it used. 404 when the person made none for it, and for every session.",
      responses: { 200: jsonResponse(KeyWrap, "The assistant's wrap"), ...problems(404) },
    }),
    async (c) => {
      const grant = c.get("grant");
      if (grant.kind !== "oauth") throw new ApiError(404, "not_found");
      const wrap = await useAssistantWrap(deps.db, c.get("userId"), grant.clientId);
      if (!wrap) throw new ApiError(404, "not_found");
      return c.json(wrap, 200);
    },
  );

  app.openapi(
    createRoute({
      method: "get",
      path: "/v2/keys",
      operationId: "listKeyWraps",
      description: "Every wrap of the account's data key.",
      responses: { 200: jsonResponse(KeyWraps, "The wraps") },
    }),
    async (c) => c.json({ wraps: await listKeyWraps(deps.db, c.get("userId")) }, 200),
  );

  app.openapi(
    createRoute({
      method: "put",
      path: "/v2/keys/{id}",
      operationId: "putKeyWrap",
      description:
        "Adds the wrap `id`, or replaces it. `keyV` must be the account's current key version (any for the first wrap), else 409 `key_version_mismatch`. A `passkey` wrap's `ref` is one of the person's passkey credential ids (422 `unknown_passkey`); an `assistant` wrap's, an OAuth client the person connected (422 `unknown_assistant`); a `device` wrap carries its 32-byte public key. A new `recovery` wrap replaces the old one (whose id cannot take another kind: 409 `recovery_required`), and a wrap replaces the one of the same kind and ref. 409 `id_taken` when the id is someone else's.",
      request: { params: idParam, body: jsonBody(PutKeyWrap) },
      responses: { 200: jsonResponse(KeyWrap, "The stored wrap"), ...problems(409, 422) },
    }),
    async (c) => {
      const { id } = c.req.valid("param");
      return c.json(await putKeyWrap(deps.db, c.get("userId"), id, c.req.valid("json")), 200);
    },
  );

  app.openapi(
    createRoute({
      method: "delete",
      path: "/v2/keys/{id}",
      operationId: "deleteKeyWrap",
      description:
        "Removes a wrap. The recovery wrap stays (409 `recovery_required`): make a new recovery key to replace it.",
      request: { params: idParam },
      responses: { 204: { description: "Deleted" }, ...problems(404, 409) },
    }),
    async (c) => {
      await deleteKeyWrap(deps.db, c.get("userId"), c.req.valid("param").id);
      return c.body(null, 204);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v2/keys/rotate",
      operationId: "rotateKeys",
      description:
        "Replaces every wrap at once with `wraps`, made for a new data key. `keyV` is the current key version + 1 (409 `key_version_mismatch`); every wrap carries it; exactly one is `recovery` (422 `recovery_required`). Records are re-encrypted through `/v2/sync` afterwards.",
      request: { body: jsonBody(RotateKeys) },
      responses: { 200: jsonResponse(KeyWraps, "The new wraps"), ...problems(409, 422) },
    }),
    async (c) => {
      const { keyV, wraps } = c.req.valid("json");
      return c.json({ wraps: await rotateKeys(deps.db, c.get("userId"), keyV, wraps) }, 200);
    },
  );

  return app;
}
