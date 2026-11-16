import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";
import type { AuthenticationResponseJSON } from "@simplewebauthn/server";
import { adminAudit } from "@wambito/db";
import { and, desc, eq, sql } from "@wambito/db/orm";
import { type Auth, isSignInAllowed } from "../auth.ts";
import type { AppDeps } from "../deps.ts";
import type { AdminEnv } from "../env.ts";
import { ADMIN_VERIFY_MS, requireAdmin } from "../http/admin.ts";
import { jsonBody, jsonResponse, problems } from "../http/openapi.ts";
import { ApiError, notFound, validationHook } from "../http/problem.ts";
import { Problem } from "../http/schemas.ts";
import { isDeliverable } from "../mailer.ts";
import {
  type ActionContext,
  deleteUser,
  disconnectAssistant,
  reactivateUser,
  removePasskey,
  signOutEverywhere,
  suspendUser,
} from "../services/admin/actions.ts";
import { requestEmailChange } from "../services/admin/email-change.ts";
import { lookupUser } from "../services/admin/lookup.ts";
import { adminMetrics } from "../services/admin/metrics.ts";
import { adminVerifyOptions, verifyAdminAssertion } from "../services/admin/verify.ts";
import { nowOf } from "../services/time.ts";

/** The reason an admin gives for an action (spec §5): required, 1–300 characters. */
export const reasonField = z.string().trim().min(1).max(300);

const tags = ["admin"];

const ReasonBody = z.object({ reason: reasonField }).openapi("AdminActionReason");
const DeleteBody = z
  .object({
    reason: reasonField,
    /** The account's email, or its id for a guest, as the app's own deletion asks. */
    confirm: z.string().min(1),
  })
  .openapi("AdminDeleteUser");
const EmailChangeBody = z
  .object({
    reason: reasonField,
    /** Trimmed and lowercased, as sign-in reads an email. */
    newEmail: z
      .string()
      .trim()
      .toLowerCase()
      .pipe(z.email().max(254))
      .refine(isDeliverable, { message: "An address under .invalid cannot receive mail" }),
  })
  .openapi("AdminEmailChange");
const UserParam = z.object({ id: z.string().min(1) });

const AdminMe = z
  .object({
    id: z.string(),
    /** When this session's passkey verification runs out (ISO 8601). */
    verifiedUntil: z.string(),
  })
  .openapi("AdminMe");

const AdminUser = z
  .object({
    id: z.string(),
    /** `null` for a guest. */
    email: z.string().nullable(),
    isAnonymous: z.boolean(),
    locale: z.string(),
    createdAt: z.string(),
    lastActiveAt: z.string().nullable(),
    suspendedAt: z.string().nullable(),
    sessionCount: z.number().int(),
    passkeys: z.array(
      z.object({
        id: z.string(),
        name: z.string().nullable(),
        deviceType: z.string(),
        createdAt: z.string().nullable(),
      }),
    ),
    assistants: z.array(
      z.object({ clientId: z.string(), name: z.string(), consentedAt: z.string() }),
    ),
  })
  .openapi("AdminUser");

const AdminMetrics = z
  .object({
    total: z.number().int(),
    withEmail: z.number().int(),
    guests: z.number().int(),
    active30d: z.number().int(),
    suspended: z.number().int(),
    signups7d: z.number().int(),
    signupsPrev7d: z.number().int(),
    weekly: z.array(
      z.object({
        /** Monday of the ISO week (UTC), YYYY-MM-DD. */
        weekStart: z.string(),
        withEmail: z.number().int(),
        guests: z.number().int(),
      }),
    ),
    /** 90 days ending today (UTC), oldest first, zero-filled. */
    dailyActive: z.array(z.object({ day: z.string(), count: z.number().int() })),
    /** Last 12 sign-up weeks; `weekN` is null while that week has not ended. */
    cohorts: z.array(
      z.object({
        weekStart: z.string(),
        size: z.number().int(),
        week1: z.number().int().nullable(),
        week4: z.number().int().nullable(),
        week12: z.number().int().nullable(),
      }),
    ),
    installsByPlatform: z.array(
      z.object({
        platform: z.enum(["android", "ios", "web", "unknown"]),
        count: z.number().int(),
      }),
    ),
    /** Users seen in the last 30 days, by platform and app version. */
    versions: z.array(
      z.object({ platform: z.string(), appVersion: z.string(), users: z.number().int() }),
    ),
  })
  .openapi("AdminMetrics");

const AuditEntry = z
  .object({
    id: z.string(),
    at: z.string(),
    adminUserId: z.string().nullable(),
    action: z.string(),
    targetUserId: z.string().nullable(),
    emailHash: z.string().nullable(),
    reason: z.string().nullable(),
    detail: z.record(z.string(), z.string()).nullable(),
  })
  .openapi("AdminAuditEntry");

const AuditPage = z
  .object({
    entries: z.array(AuditEntry),
    /** Pass as `before` for the next page; `null` at the end. */
    next: z.string().nullable(),
  })
  .openapi("AdminAuditPage");

const AUDIT_PAGE = 50;

const MICROS_AT = sql<string>`to_char(${adminAudit.at} at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`;
const CURSOR_AT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/;

/** The audit cursor: `(at, id)` of the last entry, `at` at microsecond precision; opaque to callers. */
const encodeCursor = (at: string, id: string) =>
  Buffer.from(JSON.stringify([at, id])).toString("base64url");

function decodeCursor(raw: string): { at: string; id: string } | null {
  try {
    const [at, id] = JSON.parse(Buffer.from(raw, "base64url").toString("utf8")) as unknown[];
    if (typeof at !== "string" || typeof id !== "string" || !CURSOR_AT.test(at) || !id) return null;
    return { at, id };
  } catch {
    return null;
  }
}

const Credential = z.object({
  id: z.string(),
  type: z.literal("public-key"),
  transports: z.array(z.string()).optional(),
});

/** WebAuthn request options, as `navigator.credentials.get` takes them (in their JSON form). */
const PasskeyRequestOptions = z
  .object({
    challenge: z.string(),
    timeout: z.number().optional(),
    rpId: z.string().optional(),
    allowCredentials: z.array(Credential).optional(),
    userVerification: z.string().optional(),
    extensions: z.record(z.string(), z.unknown()).optional(),
  })
  .openapi("PasskeyRequestOptions");

/** A WebAuthn assertion in its JSON form (SimpleWebAuthn's `AuthenticationResponseJSON`). */
const PasskeyAssertion = z
  .object({
    id: z.string().min(1),
    rawId: z.string().min(1),
    type: z.literal("public-key"),
    response: z.object({
      clientDataJSON: z.string(),
      authenticatorData: z.string(),
      signature: z.string(),
      userHandle: z.string().optional(),
    }),
    authenticatorAttachment: z.enum(["platform", "cross-platform"]).optional(),
    clientExtensionResults: z.record(z.string(), z.unknown()),
  })
  .openapi("PasskeyAssertion");

/**
 * The admin panel's API (spec §4–§7). Mounted before `requireUser` (app.ts), so every request is
 * judged by `requireAdmin` alone: a refused one gets the same 404 as a path that does not exist.
 */
export function adminRoutes(deps: AppDeps, auth: Auth) {
  const app = new OpenAPIHono<AdminEnv>({ defaultHook: validationHook });
  const signedIn = requireAdmin(auth, deps, { verified: false });
  const verified = requireAdmin(auth, deps, { verified: true });

  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/admin/verify/options",
      operationId: "adminVerifyOptions",
      tags,
      middleware: [signedIn] as const,
      responses: {
        200: jsonResponse(PasskeyRequestOptions, "Options for a passkey assertion"),
        ...problems(404),
      },
    }),
    async (c) => {
      const options = await adminVerifyOptions(deps, c.get("adminId"), c.get("sessionId"));
      return c.json(options, 200);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/admin/verify",
      operationId: "adminVerify",
      tags,
      middleware: [signedIn] as const,
      request: { body: jsonBody(PasskeyAssertion) },
      responses: {
        204: { description: "This session is verified for the next 15 minutes" },
        ...problems(400, 404, 422),
      },
    }),
    async (c) => {
      const assertion = c.req.valid("json") as AuthenticationResponseJSON;
      await verifyAdminAssertion(deps, c.get("adminId"), c.get("sessionId"), assertion);
      return c.body(null, 204);
    },
  );

  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/admin/me",
      operationId: "getAdminMe",
      tags,
      middleware: [verified] as const,
      responses: {
        200: jsonResponse(AdminMe, "The signed-in, verified admin"),
        ...problems(401, 404),
      },
    }),
    (c) => {
      const verifiedAt = c.get("adminVerifiedAt") ?? new Date(0);
      return c.json(
        {
          id: c.get("adminId"),
          verifiedUntil: new Date(verifiedAt.getTime() + ADMIN_VERIFY_MS).toISOString(),
        },
        200,
      );
    },
  );

  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/admin/users",
      operationId: "adminLookupUser",
      tags,
      middleware: [verified] as const,
      request: {
        query: z
          .object({ email: z.string().min(1).optional(), id: z.string().min(1).optional() })
          .refine((q) => (q.email === undefined) !== (q.id === undefined), {
            message: "Give exactly one of email or id",
          }),
      },
      responses: {
        200: jsonResponse(AdminUser, "The account"),
        ...problems(401, 404, 422),
      },
    }),
    async (c) => {
      const q = c.req.valid("query");
      const found = await lookupUser(
        deps.db,
        q.email !== undefined ? { email: q.email } : { id: q.id ?? "" },
      );
      if (!found) throw new ApiError(404, "user_not_found", "No account matches");
      return c.json(found, 200);
    },
  );

  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/admin/metrics",
      operationId: "getAdminMetrics",
      tags,
      middleware: [verified] as const,
      responses: {
        200: jsonResponse(AdminMetrics, "Account counts and sign-ups per week"),
        ...problems(401, 404),
      },
    }),
    async (c) => {
      const now = (deps.now ?? (() => new Date()))();
      return c.json(await adminMetrics(deps.db, now), 200);
    },
  );

  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/admin/audit",
      operationId: "listAdminAudit",
      tags,
      middleware: [verified] as const,
      request: {
        query: z.object({
          before: z
            .string()
            .refine((v) => decodeCursor(v) !== null, {
              message: "Not a cursor from a previous page",
            })
            .optional(),
          targetUserId: z.string().min(1).optional(),
        }),
      },
      responses: {
        200: jsonResponse(AuditPage, "The audit log, newest first"),
        ...problems(401, 404, 422),
      },
    }),
    async (c) => {
      const { before, targetUserId } = c.req.valid("query");
      const cursor = before ? decodeCursor(before) : null;
      const rows = await deps.db
        .select({ row: adminAudit, atMicros: MICROS_AT })
        .from(adminAudit)
        .where(
          and(
            cursor
              ? sql`(${adminAudit.at}, ${adminAudit.id}) < (${cursor.at}::timestamptz, ${cursor.id})`
              : undefined,
            targetUserId ? eq(adminAudit.targetUserId, targetUserId) : undefined,
          ),
        )
        .orderBy(desc(adminAudit.at), desc(adminAudit.id))
        .limit(AUDIT_PAGE + 1);
      const page = rows.slice(0, AUDIT_PAGE);
      const entries = page.map(({ row: r }) => ({
        id: r.id,
        at: r.at.toISOString(),
        adminUserId: r.adminUserId,
        action: r.action,
        targetUserId: r.targetUserId,
        emailHash: r.emailHash,
        reason: r.reason,
        detail: (r.detail as Record<string, string> | null) ?? null,
      }));
      const last = page.at(-1);
      const next =
        rows.length > AUDIT_PAGE && last ? encodeCursor(last.atMicros, last.row.id) : null;
      return c.json({ entries, next }, 200);
    },
  );

  const ctx = (c: { get(key: "adminId"): string }, reason: string): ActionContext => ({
    db: deps.db,
    mailer: deps.mailer,
    webUrl: deps.config.WEB_URL,
    adminId: c.get("adminId"),
    reason,
  });
  const done = { 204: { description: "Done; the person is notified by email" } };

  app.openapi(
    createRoute({
      method: "delete",
      path: "/v1/admin/users/{id}",
      operationId: "adminDeleteUser",
      tags,
      middleware: [verified] as const,
      request: { params: UserParam, body: jsonBody(DeleteBody) },
      responses: { ...done, ...problems(400, 401, 404, 409, 422) },
    }),
    async (c) => {
      const { id } = c.req.valid("param");
      const { reason, confirm } = c.req.valid("json");
      await deleteUser(ctx(c, reason), id, confirm);
      return c.body(null, 204);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/admin/users/{id}/email-change",
      operationId: "adminRequestEmailChange",
      tags,
      middleware: [verified] as const,
      request: { params: UserParam, body: jsonBody(EmailChangeBody) },
      responses: {
        204: { description: "A confirmation link is on its way to the new email (valid 24 hours)" },
        ...problems(401, 404, 422),
        409: {
          content: { "application/problem+json": { schema: Problem } },
          description:
            "`email_taken`, `is_guest`, or `sign_in_not_allowed` (SIGN_IN_ALLOWLIST is set and does not list the new email)",
        },
      },
    }),
    async (c) => {
      const { id } = c.req.valid("param");
      const { reason, newEmail } = c.req.valid("json");
      await requestEmailChange(
        {
          ...ctx(c, reason),
          now: nowOf(deps),
          signInAllowed: (email) => isSignInAllowed(deps.config, email),
        },
        id,
        newEmail,
      );
      return c.body(null, 204);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/admin/users/{id}/sessions/revoke",
      operationId: "adminRevokeSessions",
      tags,
      middleware: [verified] as const,
      request: { params: UserParam, body: jsonBody(ReasonBody) },
      responses: { ...done, ...problems(401, 404, 422) },
    }),
    async (c) => {
      const { id } = c.req.valid("param");
      await signOutEverywhere(ctx(c, c.req.valid("json").reason), id);
      return c.body(null, 204);
    },
  );

  app.openapi(
    createRoute({
      method: "delete",
      path: "/v1/admin/users/{id}/assistants/{clientId}",
      operationId: "adminRevokeAssistant",
      tags,
      middleware: [verified] as const,
      request: {
        params: z.object({ id: z.string().min(1), clientId: z.string().min(1) }),
        body: jsonBody(ReasonBody),
      },
      responses: { ...done, ...problems(401, 404, 422) },
    }),
    async (c) => {
      const { id, clientId } = c.req.valid("param");
      await disconnectAssistant(ctx(c, c.req.valid("json").reason), id, clientId);
      return c.body(null, 204);
    },
  );

  app.openapi(
    createRoute({
      method: "delete",
      path: "/v1/admin/users/{id}/passkeys/{passkeyId}",
      operationId: "adminRemovePasskey",
      tags,
      middleware: [verified] as const,
      request: {
        params: z.object({ id: z.string().min(1), passkeyId: z.string().min(1) }),
        body: jsonBody(ReasonBody),
      },
      responses: { ...done, ...problems(401, 404, 422) },
    }),
    async (c) => {
      const { id, passkeyId } = c.req.valid("param");
      await removePasskey(ctx(c, c.req.valid("json").reason), id, passkeyId);
      return c.body(null, 204);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/admin/users/{id}/suspend",
      operationId: "adminSuspendUser",
      tags,
      middleware: [verified] as const,
      request: { params: UserParam, body: jsonBody(ReasonBody) },
      responses: { ...done, ...problems(401, 404, 409, 422) },
    }),
    async (c) => {
      const { id } = c.req.valid("param");
      await suspendUser(ctx(c, c.req.valid("json").reason), id);
      return c.body(null, 204);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/admin/users/{id}/reactivate",
      operationId: "adminReactivateUser",
      tags,
      middleware: [verified] as const,
      request: { params: UserParam, body: jsonBody(ReasonBody) },
      responses: { ...done, ...problems(401, 404, 422) },
    }),
    async (c) => {
      const { id } = c.req.valid("param");
      await reactivateUser(ctx(c, c.req.valid("json").reason), id);
      return c.body(null, 204);
    },
  );

  // Any other admin path: the same 404, before `requireUser` could answer 401 for it.
  app.all("/v1/admin/*", (c) => notFound(c));

  return app;
}
