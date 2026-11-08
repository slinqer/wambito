import { createRoute, z } from "@hono/zod-openapi";
import type { AppDeps } from "../deps.ts";
import { jsonBody, jsonResponse, problems } from "../http/openapi.ts";
import { router } from "../http/router.ts";
import {
  PairingApprover,
  PairingFound,
  PairingReveal,
  PairingStarted,
  PairingState,
  SealPairing,
  StartPairing,
} from "../http/schemas.ts";
import {
  findPairing,
  revealPairing,
  sealPairing,
  setApprover,
  startPairing,
  takePairing,
} from "../services/pairing.ts";
import { nowOf } from "../services/time.ts";

const idParam = z.object({ id: z.uuid() });

/**
 * Approving a new device from an unlocked one (stage 1b spec section 1). The server relays opaque
 * bytes: the new device's key commitment, the approver's ephemeral key, the new device's revealed
 * key (checked against the commitment) and the sealed data key. Rows live 10 minutes and are
 * deleted on pickup. Assistants cannot reach any of it (scopes.ts).
 */
export function pairingRoutes(deps: AppDeps) {
  const app = router();

  app.openapi(
    createRoute({
      method: "post",
      path: "/v2/pairing",
      operationId: "startPairing",
      description:
        "The new device posts a commitment to its public key (SHA-256 with a domain tag) and shows the returned `code`. At most 5 unexpired requests per person (429 `too_many_pairings`); a request lives 10 minutes.",
      request: { body: jsonBody(StartPairing) },
      responses: { 201: jsonResponse(PairingStarted, "The request"), ...problems(429) },
    }),
    async (c) =>
      c.json(
        await startPairing(deps.db, c.get("userId"), c.req.valid("json").commitment, nowOf(deps)),
        201,
      ),
  );

  app.openapi(
    createRoute({
      method: "get",
      path: "/v2/pairing",
      operationId: "findPairing",
      description:
        "The unlocked device finds the new device's request by the typed `code` (case, dashes, spaces and look-alike letters are forgiven) and gets its `commitment`. 404 when expired, when an approver key is already set, or when it is not the person's.",
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
      path: "/v2/pairing/{id}/approver",
      operationId: "setPairingApprover",
      description:
        "The unlocked device posts its ephemeral public key for this pairing, once. 404 when expired or not the person's, 409 `already_set`.",
      request: { params: idParam, body: jsonBody(PairingApprover) },
      responses: { 204: { description: "Stored" }, ...problems(404, 409) },
    }),
    async (c) => {
      await setApprover(
        deps.db,
        c.get("userId"),
        c.req.valid("param").id,
        c.req.valid("json").publicKey,
        nowOf(deps),
      );
      return c.body(null, 204);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v2/pairing/{id}/reveal",
      operationId: "revealPairing",
      description:
        "The new device reveals its public key after it sees the approver key. 404 when expired or not the person's, 409 `not_ready` (no approver key yet) or `already_set`, 422 `commitment_mismatch` when the key does not match the commitment.",
      request: { params: idParam, body: jsonBody(PairingReveal) },
      responses: { 204: { description: "Stored" }, ...problems(404, 409, 422) },
    }),
    async (c) => {
      await revealPairing(
        deps.db,
        c.get("userId"),
        c.req.valid("param").id,
        c.req.valid("json").publicKey,
        nowOf(deps),
      );
      return c.body(null, 204);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v2/pairing/{id}/seal",
      operationId: "sealPairing",
      description:
        "The unlocked device posts the data key sealed to the revealed key (up to 1 KiB) with the key version. 404 when expired or not the person's, 409 `not_ready` (no revealed key) or `already_sealed`, 422 `approver_mismatch` when the first 32 bytes of `sealed` are not the approver key.",
      request: { params: idParam, body: jsonBody(SealPairing) },
      responses: { 204: { description: "Sealed" }, ...problems(404, 409, 422) },
    }),
    async (c) => {
      const { sealed, keyV } = c.req.valid("json");
      await sealPairing(
        deps.db,
        c.get("userId"),
        c.req.valid("param").id,
        sealed,
        keyV,
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
        "Both devices poll. Returns `commitment`, `approverKey`, `publicKey`, `sealed`, `keyV` (null until set) and `expiresAt`. When `sealed` is returned the request is deleted in the same transaction, so a later read is 404.",
      request: { params: idParam },
      responses: { 200: jsonResponse(PairingState, "The request's state"), ...problems(404) },
    }),
    async (c) =>
      c.json(
        await takePairing(deps.db, c.get("userId"), c.req.valid("param").id, nowOf(deps)),
        200,
      ),
  );

  return app;
}
