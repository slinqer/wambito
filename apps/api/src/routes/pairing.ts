import { createRoute, z } from "@hono/zod-openapi";
import type { AppDeps } from "../deps.ts";
import { jsonBody, jsonResponse, problems } from "../http/openapi.ts";
import { router } from "../http/router.ts";
import {
  PairingFound,
  PairingPickup,
  PairingStarted,
  SealPairing,
  StartPairing,
} from "../http/schemas.ts";
import { findPairing, sealPairing, startPairing, takePairing } from "../services/pairing.ts";
import { nowOf } from "../services/time.ts";

const idParam = z.object({ id: z.uuid() });

/**
 * Approving a new device from an unlocked one (spec 2026-11-08 section 7.3). The server only
 * relays opaque bytes: a public key one way, the sealed data key back. Rows live 10 minutes and
 * are deleted on pickup. Assistants cannot reach any of it (scopes.ts).
 */
export function pairingRoutes(deps: AppDeps) {
  const app = router();

  app.openapi(
    createRoute({
      method: "post",
      path: "/v2/pairing",
      operationId: "startPairing",
      description:
        "The new device posts its ephemeral public key and shows the returned `code`. At most 5 unexpired requests per person (429 `too_many_pairings`); a request lives 10 minutes.",
      request: { body: jsonBody(StartPairing) },
      responses: { 201: jsonResponse(PairingStarted, "The request"), ...problems(429) },
    }),
    async (c) =>
      c.json(
        await startPairing(deps.db, c.get("userId"), c.req.valid("json").publicKey, nowOf(deps)),
        201,
      ),
  );

  app.openapi(
    createRoute({
      method: "get",
      path: "/v2/pairing",
      operationId: "findPairing",
      description:
        "The unlocked device finds the new device's request by the typed `code` (case, dashes, spaces and look-alike letters are forgiven). 404 when expired, already sealed, or not the person's.",
      request: { query: z.object({ code: z.string().min(1).max(32) }) },
      responses: { 200: jsonResponse(PairingFound, "The request"), ...problems(404) },
    }),
    async (c) =>
      c.json(
        await findPairing(deps.db, c.get("userId"), c.req.valid("query").code, nowOf(deps)),
        200,
      ),
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v2/pairing/{id}/seal",
      operationId: "sealPairing",
      description:
        "The unlocked device posts the data key sealed to the request's public key (up to 1 KiB). 404 when expired or not the person's, 409 `already_sealed`.",
      request: { params: idParam, body: jsonBody(SealPairing) },
      responses: { 204: { description: "Sealed" }, ...problems(404, 409) },
    }),
    async (c) => {
      await sealPairing(
        deps.db,
        c.get("userId"),
        c.req.valid("param").id,
        c.req.valid("json").sealed,
        nowOf(deps),
      );
      return c.body(null, 204);
    },
  );

  app.openapi(
    createRoute({
      method: "get",
      path: "/v2/pairing/{id}",
      operationId: "takePairing",
      description:
        "The new device polls. `sealed` is null until the other device seals; when it is returned the request is deleted in the same transaction, so a second read is 404.",
      request: { params: idParam },
      responses: { 200: jsonResponse(PairingPickup, "The sealed key, or null"), ...problems(404) },
    }),
    async (c) =>
      c.json(
        {
          sealed: await takePairing(deps.db, c.get("userId"), c.req.valid("param").id, nowOf(deps)),
        },
        200,
      ),
  );

  return app;
}
