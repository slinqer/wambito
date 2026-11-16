import { type Db, deletedUsers, endedSessions } from "@wambito/db";
import { eq } from "@wambito/db/orm";
import { parseCookies } from "better-auth/cookies";
import { verifyJwsAccessToken } from "better-auth/oauth2";
import { createMiddleware } from "hono/factory";
import type { Auth } from "../auth.ts";
import type { Config } from "../config.ts";
import type { AppEnv, Grant, SessionUser } from "../env.ts";
import { sha256 } from "../services/ended.ts";
import { slideLongSession } from "../services/sessions.ts";
import { clientHeader } from "./client-headers.ts";
import { ApiError } from "./problem.ts";

type AuthUser = {
  id: string;
  email: string;
  timezone: string;
  locale: string;
  isAnonymous?: boolean | null;
  suspendedAt?: Date | string | null;
};

/** A suspended account (spec §5.4) is refused on every path, as sign-in refuses it. */
const suspended = () => new ApiError(403, "account_suspended", "This account is suspended");

/**
 * Whether this user is suspended. Read from the store, since Better Auth leaves `suspendedAt`
 * (`returned: false`) out of the session's user.
 */
async function isSuspendedUser(auth: Auth, userId: string): Promise<boolean> {
  const ctx = await auth.$context;
  const found = (await ctx.internalAdapter.findUserById(userId)) as AuthUser | null;
  return found?.suspendedAt != null;
}

const toSessionUser = (u: AuthUser): SessionUser => ({
  id: u.id,
  email: u.email,
  timezone: u.timezone,
  locale: u.locale,
});

/** The issuer Better Auth stamps on its tokens: the auth routes' base URL. */
export const authIssuer = (config: Pick<Config, "API_URL">) =>
  `${config.API_URL.replace(/\/+$/, "")}/auth`;

/**
 * Resolves the caller from the cookie or `Authorization: Bearer`; 401 otherwise. The bearer is a
 * session token (the app), or an assistant's OAuth access token: a JWT signed by our `jwt` keys,
 * issued by us, for the MCP (`aud` = MCP_URL, RFC 8707). A token for any other audience is
 * refused, so a token minted for something else cannot open the API.
 *
 * A request with `x-wambito-background: 1` reads the session without refreshing it (Better Auth's
 * `disableRefresh`), so background jobs never count as activity for the guest cleanup.
 *
 * Better Auth never refreshes a `long` session (25 months; it refreshes only in the last 59 days),
 * so this slides it, at most once a day and never for a background request, and stamps the user's
 * activity (`slideLongSession`): a person using the app daily is never cleaned up as idle.
 *
 * Without a session, the 401 says why when it can (`missingSessionCode`): `device_removed`,
 * `user_deleted`, else `unauthenticated`.
 */
export function requireUser(auth: Auth, config: Pick<Config, "API_URL" | "MCP_URL">, db: Db) {
  return createMiddleware<AppEnv>(async (c, next) => {
    const background = clientHeader(c.req.raw.headers, "background") === "1";
    const result = await auth.api.getSession({
      headers: c.req.raw.headers,
      ...(background ? { query: { disableRefresh: true } } : {}),
    });
    let user: SessionUser;
    let grant: Grant;
    if (result) {
      // Suspending deletes the sessions (admin suspend); this also covers one that outlived it.
      if (await isSuspendedUser(auth, result.user.id)) throw suspended();
      user = toSessionUser(result.user as AuthUser);
      grant = { kind: "session", sessionId: result.session.id };
      if (!background && result.session.lifetime === "long")
        await slideLongSession(db, result.session.id, result.user.id, new Date());
    } else {
      const oauth = await oauthUser(auth, config, c.req.header("authorization"));
      if (!oauth) {
        const cookieName = (await auth.$context).authCookies.sessionToken.name;
        const code = await missingSessionCode(db, c.req.raw.headers, cookieName);
        throw new ApiError(401, code, UNAUTHENTICATED_DETAIL[code]);
      }
      ({ user, grant } = oauth);
    }
    c.set("userId", user.id);
    c.set("user", user);
    c.set("grant", grant);
    await next();
  });
}

/**
 * The session token a request presents, without its signature: the bearer when it is not a JWT
 * (an assistant's access token), else the session cookie; URL-decoded (Better Auth's signed
 * token may be), cut at the first `.`; null without one. Only
 * hashed and looked up for a 401's code; Better Auth alone decides whether it signs in.
 */
export function presentedSessionToken(headers: Headers, cookieName: string): string | null {
  const bearer = /^Bearer\s+(\S+)$/i.exec(headers.get("authorization") ?? "")?.[1];
  const signed =
    bearer !== undefined && bearer.split(".").length !== 3
      ? bearer
      : parseCookies(headers.get("cookie") ?? "").get(cookieName);
  if (signed === undefined) return null;
  let value = signed;
  try {
    value = decodeURIComponent(signed);
  } catch {}
  return value.split(".")[0] || null;
}

export type MissingSessionCode = "device_removed" | "user_deleted" | "unauthenticated";

const UNAUTHENTICATED_DETAIL: Record<MissingSessionCode, string> = {
  device_removed: "This device was removed from the account",
  user_deleted: "This account was deleted",
  unauthenticated: "Sign in to continue",
};

/**
 * Why a request has no session (spec 2026-11-15 §10): `device_removed` when its token's hash is in
 * `ended_sessions` (a removed device), else `user_deleted` when its `x-wambito-user`'s hash is in
 * `deleted_users` (the cleanup deleted that account), else `unauthenticated`. It tells nothing
 * beyond what the token or the id the client sent already names.
 */
export async function missingSessionCode(
  db: Db,
  headers: Headers,
  cookieName: string,
): Promise<MissingSessionCode> {
  const token = presentedSessionToken(headers, cookieName);
  if (token !== null) {
    const [ended] = await db
      .select({ reason: endedSessions.reason })
      .from(endedSessions)
      .where(eq(endedSessions.sessionHash, sha256(token)))
      .limit(1);
    if (ended) return "device_removed";
  }
  const userId = clientHeader(headers, "user");
  if (userId) {
    const [deleted] = await db
      .select({ at: deletedUsers.deletedAt })
      .from(deletedUsers)
      .where(eq(deletedUsers.userHash, sha256(userId)))
      .limit(1);
    if (deleted) return "user_deleted";
  }
  return "unauthenticated";
}

async function oauthUser(
  auth: Auth,
  config: Pick<Config, "API_URL" | "MCP_URL">,
  header: string | undefined,
): Promise<{ user: SessionUser; grant: Grant } | null> {
  const token = /^Bearer\s+(\S+)$/i.exec(header ?? "")?.[1];
  if (!config.MCP_URL || !token || token.split(".").length !== 3) return null;
  let payload: Awaited<ReturnType<typeof verifyJwsAccessToken>>;
  try {
    payload = await verifyJwsAccessToken(token, {
      jwksFetch: () => auth.api.getJwks(),
      jwksCacheKey: auth,
      verifyOptions: { audience: config.MCP_URL, issuer: authIssuer(config) },
    });
  } catch {
    return null;
  }
  const clientId = typeof payload.azp === "string" ? payload.azp : payload.client_id;
  if (typeof payload.sub !== "string" || typeof clientId !== "string") return null;
  const ctx = await auth.$context;
  const found = (await ctx.internalAdapter.findUserById(payload.sub)) as AuthUser | null;
  if (!found) return null;
  // Guests cannot connect an assistant (main spec, Guest mode); the consent screen offers to save
  // their progress instead. This refuses a token minted for one anyway.
  if (found.isAnonymous)
    throw new ApiError(403, "guest_cannot_authorize", "Save your progress first");
  // An access token lives 15 minutes after a suspend; it opens nothing meanwhile.
  if (found.suspendedAt != null) throw suspended();
  const scopes = typeof payload.scope === "string" ? payload.scope.split(" ").filter(Boolean) : [];
  return { user: toSessionUser(found), grant: { kind: "oauth", clientId, scopes } };
}
