import { createRoute, z } from "@hono/zod-openapi";
import { oauthClient, oauthConsent, oauthRefreshToken } from "@wambito/db";
import { and, desc, eq, inArray, max } from "@wambito/db/orm";
import type { AppDeps } from "../deps.ts";
import { jsonResponse, problems } from "../http/openapi.ts";
import { ApiError } from "../http/problem.ts";
import { router } from "../http/router.ts";
import { revokeAssistant } from "../services/account.ts";

const Assistant = z
  .object({
    clientId: z.string(),
    name: z.string(),
    icon: z.string().nullable(),
    uri: z.string().nullable(),
    /**
     * Where the assistant comes from: the host its client_id lives on (a Client ID Metadata
     * Document), else its website's. This is what tells a real Claude from a copy.
     */
    domain: z.string().nullable(),
    scopes: z.array(z.string()),
    connectedAt: z.string(),
    /** When it last got a token (it refreshes about every 15 minutes while in use). */
    lastUsedAt: z.string().nullable(),
  })
  .openapi("Assistant");
const AssistantList = z.object({ items: z.array(Assistant) }).openapi("AssistantList");

const hostOf = (url: string | null) => {
  if (!url) return null;
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" || parsed.protocol === "http:" ? parsed.host : null;
  } catch {
    return null;
  }
};

/**
 * "Conecta tu asistente" (spec §6.2): the assistants the person let in, and revoking one. The
 * OAuth tables belong to Better Auth and have no row-level security, so every query here filters
 * by the caller.
 */
export function assistantRoutes(deps: AppDeps) {
  const app = router();

  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/me/assistants",
      operationId: "listAssistants",
      responses: { 200: jsonResponse(AssistantList, "Connected assistants, newest first") },
    }),
    async (c) => {
      const userId = c.get("userId");
      const rows = await deps.db
        .select({
          clientId: oauthConsent.clientId,
          scopes: oauthConsent.scopes,
          connectedAt: oauthConsent.createdAt,
          name: oauthClient.name,
          icon: oauthClient.icon,
          uri: oauthClient.uri,
        })
        .from(oauthConsent)
        .innerJoin(oauthClient, eq(oauthClient.clientId, oauthConsent.clientId))
        .where(eq(oauthConsent.userId, userId))
        .orderBy(desc(oauthConsent.createdAt));
      const clientIds = rows.map((r) => r.clientId);
      const used = clientIds.length
        ? await deps.db
            .select({ clientId: oauthRefreshToken.clientId, at: max(oauthRefreshToken.createdAt) })
            .from(oauthRefreshToken)
            .where(
              and(
                eq(oauthRefreshToken.userId, userId),
                inArray(oauthRefreshToken.clientId, clientIds),
              ),
            )
            .groupBy(oauthRefreshToken.clientId)
        : [];
      const lastUsed = new Map(used.map((u) => [u.clientId, u.at]));
      return c.json(
        {
          items: rows.map((r) => ({
            clientId: r.clientId,
            name: r.name ?? r.clientId,
            icon: r.icon,
            uri: r.uri,
            domain: hostOf(r.clientId) ?? hostOf(r.uri),
            scopes: r.scopes,
            connectedAt: r.connectedAt.toISOString(),
            lastUsedAt: lastUsed.get(r.clientId)?.toISOString() ?? null,
          })),
        },
        200,
      );
    },
  );

  app.openapi(
    createRoute({
      method: "delete",
      path: "/v1/me/assistants/{clientId}",
      operationId: "revokeAssistant",
      description:
        "Deletes the consent and the refresh tokens: the assistant cannot get a new access token, so it loses access within 15 minutes at most. With `x-wambito-user` naming another account than the signed-in one, 409 `session_changed` and nothing is removed.",
      request: { params: z.object({ clientId: z.string().min(1) }) },
      responses: { 204: { description: "Revoked" }, ...problems(404, 409) },
    }),
    async (c) => {
      const userId = c.get("userId");
      const { clientId } = c.req.valid("param");
      const removed = await deps.db.transaction((tx) => revokeAssistant(tx, userId, clientId));
      if (!removed) throw new ApiError(404, "not_found", "Assistant not found");
      return c.body(null, 204);
    },
  );

  return app;
}
