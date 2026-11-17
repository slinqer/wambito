import { AsyncLocalStorage } from "node:async_hooks";
import { createHash } from "node:crypto";
import { oauthRefreshToken } from "@wambito/db";
import { eq } from "@wambito/db/orm";
import { createMiddleware } from "hono/factory";
import { CompactEncrypt, importJWK } from "jose";
import type { Auth } from "../auth.ts";
import { type Config, isPreviewAccount } from "../config.ts";
import type { AppDeps } from "../deps.ts";
import type { AppEnv } from "../env.ts";
import { revokeAssistant } from "../services/account.ts";
import { accountEncryption } from "../services/encryption.ts";
import { clientHeader } from "./client-headers.ts";
import { ApiError } from "./problem.ts";

/**
 * The assistant secret `S` (spec 2026-11-16 §4): 32 random bytes, base64url, made by the web's
 * consent page for an encrypted account. It opens the account's `assistant` key wrap, so it is
 * never stored, logged or put in an error: it travels in the consent body (`wk`), then in the
 * refresh token (`<Better Auth's token>.<S>`) and in every access token's `wk` claim (a compact
 * JWE, `ECDH-ES` + `A256GCM`, to `MCP_WK_PUBLIC_KEY`; its plaintext is `S` as base64url text).
 *
 * This wrapper sits in front of Better Auth's `/auth/oauth2/*` (mounted before `/auth/*`):
 * - authorize: an encrypted account always gets the consent page (`prompt=consent`), since a code
 *   Better Auth hands out without it carries no `S`;
 * - consent: takes `wk` out of the body, and keeps `code → S` in process memory for 10 minutes
 *   (the newest 10,000 codes); with `x-wambito-user` naming another account than the signed-in
 *   one, 409 `session_changed` and no consent;
 * - token: runs Better Auth inside an AsyncLocalStorage holding `S` (`assistantSecretClaims` adds
 *   the claim), appends `.S` to the refresh token, and strips it from a presented one; an encrypted
 *   account without `S` is refused (400 `invalid_grant`) and that client is revoked for it;
 * - revoke and introspect: strip the suffix (RFC 7009 answers 200 for an unknown token, so an
 *   unstripped one would silently revoke nothing).
 */

/** How long a consented code keeps its `S` waiting for the exchange (the code's own lifetime). */
export const PENDING_SECRET_MS = 10 * 60 * 1000;

/** 43 base64url characters that decode to exactly 32 bytes (canonical: re-encoding gives them back). */
function isSecret(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^[A-Za-z0-9_-]{43}$/.test(value) &&
    Buffer.from(value, "base64url").toString("base64url") === value
  );
}

/**
 * A presented refresh token split on its last `.`: Better Auth's own tokens have no dot, so a
 * token ending in `.` + a well-formed `S` is ours; anything else (a JWT access token has two
 * dots) goes to Better Auth as it came.
 */
function splitToken(token: string): { token: string; secret?: string } {
  const dot = token.lastIndexOf(".");
  if (dot <= 0) return { token };
  const head = token.slice(0, dot);
  const tail = token.slice(dot + 1);
  if (head.includes(".") || !isSecret(tail)) return { token };
  return { token: head, secret: tail };
}

/** At most this many codes wait for their exchange; past it the oldest go (their connect fails). */
export const PENDING_SECRET_LIMIT = 10_000;

/** Oldest first: every entry lives `PENDING_SECRET_MS`, so this is also expiry order. */
const pending = new Map<string, { secret: string; expiresAt: number }>();

function sweep(now: number): void {
  for (const [code, entry] of pending) {
    if (entry.expiresAt > now) break;
    pending.delete(code);
  }
}

/** Keeps `S` for `code` until the exchange or `PENDING_SECRET_MS`, the newest `PENDING_SECRET_LIMIT`. */
export function rememberSecret(code: string, secret: string): void {
  const now = Date.now();
  sweep(now);
  pending.delete(code);
  pending.set(code, { secret, expiresAt: now + PENDING_SECRET_MS });
  for (const oldest of pending.keys()) {
    if (pending.size <= PENDING_SECRET_LIMIT) break;
    pending.delete(oldest);
  }
}

/** Takes (and deletes, whatever happens next) the `S` a consent left for `code`. */
function takePending(code: string): string | undefined {
  const now = Date.now();
  sweep(now);
  const entry = pending.get(code);
  pending.delete(code);
  return entry?.secret;
}

/** Empties the code → `S` map, as an API restart does. Tests only. */
export function forgetPendingSecrets(): void {
  pending.clear();
}

/** The codes waiting, oldest first. Tests only. */
export function pendingSecretCodes(): string[] {
  return [...pending.keys()];
}

/** The `S` of the token request being handled, for `assistantSecretClaims`. */
const tokenSecret = new AsyncLocalStorage<{ secret?: string }>();

let importedKey: { jwk: string; key: Promise<CryptoKey | Uint8Array> } | undefined;

function mcpKey(jwk: string): Promise<CryptoKey | Uint8Array> {
  if (importedKey?.jwk !== jwk) {
    importedKey = { jwk, key: importJWK(JSON.parse(jwk) as Record<string, unknown>, "ECDH-ES") };
  }
  return importedKey.key;
}

/**
 * The oauthProvider's `customAccessTokenClaims`: the `wk` claim, when the token request being
 * handled carries `S`. Better Auth gives this hook no request, hence the AsyncLocalStorage.
 */
export function assistantSecretClaims(config: Pick<Config, "MCP_WK_PUBLIC_KEY">) {
  return async (): Promise<Record<string, string>> => {
    const secret = tokenSecret.getStore()?.secret;
    // The token route checked the key before it let a request with `S` in.
    if (!secret || !config.MCP_WK_PUBLIC_KEY) return {};
    const wk = await new CompactEncrypt(new TextEncoder().encode(secret))
      .setProtectedHeader({ alg: "ECDH-ES", enc: "A256GCM" })
      .encrypt(await mcpKey(config.MCP_WK_PUBLIC_KEY));
    return { wk };
  };
}

/** No MCP key configured: refuse rather than issue tokens the MCP could not open. */
const keysMissing = () =>
  new ApiError(503, "assistant_keys_missing", "The server cannot connect assistants right now");

/** The OAuth error shape Better Auth's endpoints answer with. */
const oauthError = (status: number, error: string, description: string) =>
  Response.json(
    { error, error_description: description },
    { status, headers: { "cache-control": "no-store" } },
  );

/** `request` with another body, same method, URL and headers (bar the length). */
function withBody(request: Request, body: string): Request {
  const headers = new Headers(request.headers);
  headers.delete("content-length");
  return new Request(request.url, { method: request.method, headers, body });
}

/** `res` with a new JSON body, same status and headers (bar the length). */
function withJson(res: Response, json: unknown): Response {
  const headers = new Headers(res.headers);
  headers.delete("content-length");
  return new Response(JSON.stringify(json), { status: res.status, headers });
}

/**
 * Which bodies Better Auth parses, the way its body parser (better-call) decides: on the
 * lower-cased content type, a form when it contains the media type anywhere, JSON when it starts
 * with `application/json` or `application/…+json`. Any narrower test here would let a request
 * Better Auth accepts past the wrapper (no refusal, no strip).
 */
const contentType = (request: Request) => (request.headers.get("content-type") ?? "").toLowerCase();
const isForm = (request: Request) =>
  contentType(request).includes("application/x-www-form-urlencoded");
const isJson = (request: Request) =>
  /^application\/([a-z0-9.+-]*\+)?json/.test(contentType(request));

/** Who the tokens Better Auth just issued belong to: its refresh token's row, else the JWT. */
async function tokensHolder(
  deps: AppDeps,
  tokens: { access_token?: unknown; refresh_token?: unknown },
): Promise<{ userId: string; clientId: string } | undefined> {
  if (typeof tokens.refresh_token === "string") {
    // Stored as the SHA-256 of the token, base64url (as `refreshTokenUser` in auth.ts reads it).
    const hashed = createHash("sha256").update(tokens.refresh_token).digest("base64url");
    const [row] = await deps.db
      .select({ userId: oauthRefreshToken.userId, clientId: oauthRefreshToken.clientId })
      .from(oauthRefreshToken)
      .where(eq(oauthRefreshToken.token, hashed));
    if (row?.userId) return { userId: row.userId, clientId: row.clientId };
  }
  // Without offline_access there is no refresh token; the access token is a JWT just signed here.
  // (An opaque access token, asked for without the MCP resource, opens nothing at the API.)
  const parts = typeof tokens.access_token === "string" ? tokens.access_token.split(".") : [];
  if (parts.length !== 3) return undefined;
  try {
    const payload = JSON.parse(Buffer.from(parts[1] ?? "", "base64url").toString()) as {
      sub?: unknown;
      azp?: unknown;
    };
    if (typeof payload.sub === "string" && typeof payload.azp === "string") {
      return { userId: payload.sub, clientId: payload.azp };
    }
  } catch {
    // Not a JWT after all.
  }
  return undefined;
}

async function isEncrypted(deps: AppDeps, userId: string): Promise<boolean> {
  return isPreviewAccount(deps.config, {
    id: userId,
    encryption: await accountEncryption(deps.db, userId),
  });
}

/**
 * The wrapper in front of Better Auth's `/auth/oauth2/*`. Mounted before `/auth/*`; requests it
 * leaves alone (and a plain account's, bar the authorize lookup) go on to Better Auth unchanged.
 */
export function assistantSecret(deps: AppDeps, auth: Auth) {
  const { config } = deps;

  async function authorize(request: Request): Promise<Response | undefined> {
    const session = await auth.api.getSession({
      headers: request.headers,
      query: { disableRefresh: true },
    });
    if (!session || !(await isEncrypted(deps, session.user.id))) return undefined;
    const url = new URL(request.url);
    const prompt = new Set((url.searchParams.get("prompt") ?? "").split(" ").filter(Boolean));
    if (prompt.has("consent")) return undefined;
    prompt.add("consent");
    url.searchParams.set("prompt", [...prompt].join(" "));
    return auth.handler(new Request(url, request));
  }

  async function consent(request: Request): Promise<Response | undefined> {
    if (!isJson(request)) return undefined;
    let body: unknown;
    try {
      body = await request.clone().json();
    } catch {
      return undefined;
    }
    if (typeof body !== "object" || body === null || !("wk" in body)) return undefined;
    const { wk, ...rest } = body as Record<string, unknown>;
    if (!isSecret(wk)) return oauthError(400, "invalid_request", "wk must be 32 bytes, base64url");
    if (!config.MCP_WK_PUBLIC_KEY) throw keysMissing();
    // The page names the account it was loaded for: a cookie that now belongs to another one
    // (signed in as someone else in another tab) gets no consent row, as `expectedUser` answers.
    const expected = clientHeader(request.headers, "user");
    if (expected !== undefined) {
      const session = await auth.api.getSession({
        headers: request.headers,
        query: { disableRefresh: true },
      });
      if (session?.user.id !== expected) {
        throw new ApiError(409, "session_changed", "The signed-in account is not the one expected");
      }
    }
    const res = await auth.handler(withBody(request, JSON.stringify(rest)));
    if (res.status !== 200) return res;
    const answer = (await res.clone().json()) as { url?: unknown };
    const code =
      typeof answer.url === "string" ? new URL(answer.url).searchParams.get("code") : null;
    if (code) rememberSecret(code, wk);
    return res;
  }

  async function token(request: Request): Promise<Response | undefined> {
    if (!isForm(request)) return undefined;
    const form = new URLSearchParams(await request.clone().text());
    const grant = form.get("grant_type");
    let secret: string | undefined;
    let forwarded = request;
    if (grant === "authorization_code") {
      secret = takePending(form.get("code") ?? "");
    } else if (grant === "refresh_token") {
      const split = splitToken(form.get("refresh_token") ?? "");
      secret = split.secret;
      if (secret) {
        form.set("refresh_token", split.token);
        forwarded = withBody(request, form.toString());
      }
    } else {
      return undefined;
    }
    if (secret && !config.MCP_WK_PUBLIC_KEY) throw keysMissing();

    const res = await tokenSecret.run({ secret }, () => auth.handler(forwarded));
    if (res.status !== 200) return res;
    const tokens = (await res.clone().json()) as {
      access_token?: unknown;
      refresh_token?: unknown;
    };
    if (!secret) {
      const holder = await tokensHolder(deps, tokens);
      // An encrypted account's assistant without `S` could open nothing: refuse, and revoke that
      // client for the account so the next connect starts clean through the consent page.
      if (holder && (await isEncrypted(deps, holder.userId))) {
        await revokeAssistant(deps.db, holder.userId, holder.clientId);
        return oauthError(400, "invalid_grant", "Connect the assistant again");
      }
      return res;
    }
    if (typeof tokens.refresh_token !== "string") return res;
    return withJson(res, { ...tokens, refresh_token: `${tokens.refresh_token}.${secret}` });
  }

  /** Revoke and introspect: Better Auth must see the token it issued, without `.S`. */
  async function stripPresented(request: Request): Promise<Response | undefined> {
    if (!isForm(request)) return undefined;
    const form = new URLSearchParams(await request.clone().text());
    const split = splitToken(form.get("token") ?? "");
    if (!split.secret) return undefined;
    form.set("token", split.token);
    return auth.handler(withBody(request, form.toString()));
  }

  return createMiddleware<AppEnv>(async (c, next) => {
    const request = c.req.raw;
    const endpoint = new URL(request.url).pathname.split("/").pop();
    let res: Response | undefined;
    if (request.method === "GET" && endpoint === "authorize") res = await authorize(request);
    else if (request.method === "POST" && endpoint === "consent") res = await consent(request);
    else if (request.method === "POST" && endpoint === "token") res = await token(request);
    else if (request.method === "POST" && (endpoint === "revoke" || endpoint === "introspect")) {
      res = await stripPresented(request);
    }
    if (res) return res;
    await next();
  });
}
