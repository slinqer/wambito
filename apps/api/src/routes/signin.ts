import { randomUUID } from "node:crypto";
import { createRoute, z } from "@hono/zod-openapi";
import { createMiddleware } from "hono/factory";
import type { Auth } from "../auth.ts";
import type { AppDeps } from "../deps.ts";
import type { AppEnv } from "../env.ts";
import { clientHeader } from "../http/client-headers.ts";
import { clientIp } from "../http/client-ip.ts";
import { IpOpenCount, IpWindowLimit } from "../http/ip-limit.ts";
import { jsonBody, jsonResponse, problems } from "../http/openapi.ts";
import { ApiError } from "../http/problem.ts";
import { router } from "../http/router.ts";
import {
  PairingApprover,
  PairingReveal,
  SealPairing,
  SigninFound,
  SigninPickup,
  SigninPoll,
  SigninStarted,
  SigninView,
  StartSignin,
} from "../http/schemas.ts";
import { requireUser } from "../http/session.ts";
import { signInAs } from "../http/sign-in-response.ts";
import {
  findSignin,
  MAX_OPEN_SIGNINS_PER_IP,
  pollSignin,
  revealSignin,
  SIGNIN_OPEN_LIMIT,
  SIGNIN_TTL_MS,
  sealSignin,
  setSigninApprover,
  startSignin,
  takeSignin,
  viewSignin,
} from "../services/signin.ts";
import { nowOf } from "../services/time.ts";

const idParam = z.object({ id: z.uuid() });
const pollHeader = z.object({
  "x-wambito-poll": z.string().optional().openapi({
    description: "The request's `pollSecret`; only the browser that opened it has it",
  }),
});

const insufficientScope = () =>
  new ApiError(403, "insufficient_scope", "This assistant cannot do that");

/** An assistant's OAuth access token: a JWT, three dot-separated parts (a session token has two). */
const isJwtBearer = (header: string | undefined) => {
  const token = /^Bearer\s+(\S+)$/i.exec(header ?? "")?.[1];
  return token !== undefined && token.split(".").length === 3;
};

/** The poll secret a browser call carries; 404 without one, as for a wrong one. */
const pollSecretOf = (headers: Headers): string => {
  const secret = clientHeader(headers, "poll");
  if (!secret) throw new ApiError(404, "not_found");
  return secret;
};

/**
 * Signing in on the web through the phone (spec 2026-11-15 section 8). The browser opens a request
 * with no session and proves itself with the poll secret (`x-wambito-poll`); the phone approves,
 * checks and seals with its session. The relay checks are pairing's (`services/relay.ts`). Mounted
 * before `/v2/*`'s `requireUser` (app.ts): the session routes run it themselves. Assistants get 403
 * on every route.
 */
export function signinRoutes(deps: AppDeps, auth: Auth) {
  const app = router();
  // Opening a request: a window per address (real time: it protects the live server), and the
  // requests an address holds open, by the API's clock like the requests' own expiry.
  const opens = new IpWindowLimit(SIGNIN_OPEN_LIMIT);
  const held = new IpOpenCount(MAX_OPEN_SIGNINS_PER_IP);
  const session = requireUser(auth, deps.config, deps.db);
  const sessionOnly = createMiddleware<AppEnv>(async (c, next) => {
    if (c.get("grant").kind !== "session") throw insufficientScope();
    await next();
  });

  for (const path of ["/v2/signin", "/v2/signin/*"]) {
    app.use(path, async (c, next) => {
      if (isJwtBearer(c.req.header("authorization"))) throw insufficientScope();
      await next();
    });
  }

  app.openapi(
    createRoute({
      method: "post",
      path: "/v2/signin",
      operationId: "startSignin",
      description: `The browser opens a sign-in request, signed out: a commitment to its X25519 public key (SHA-256 with a domain tag), \`remember\` (the "Keep me signed in" box) and a \`label\` for the phone to show. It shows the returned \`code\` and a QR of \`id\` and its public key, and keeps \`pollSecret\`. A request lives ${SIGNIN_TTL_MS / 60_000} minutes. 429 \`too_many_requests\` past ${SIGNIN_OPEN_LIMIT.max} requests per address in ${SIGNIN_OPEN_LIMIT.windowMs / 60_000} minutes, \`too_many_signins\` past ${MAX_OPEN_SIGNINS_PER_IP} open ones.`,
      request: { body: jsonBody(StartSignin) },
      responses: { 201: jsonResponse(SigninStarted, "The request"), ...problems(403, 422, 429) },
    }),
    async (c) => {
      const ip = clientIp(c.req.raw.headers, deps.config);
      if (opens.hit(ip, Date.now())) {
        c.header("retry-after", String(SIGNIN_OPEN_LIMIT.windowMs / 1000));
        throw new ApiError(429, "too_many_requests", "Too many sign-in requests; try again later");
      }
      const now = nowOf(deps);
      // Counted before the insert under a placeholder, so two opens at once cannot both pass.
      const slot = `pending:${randomUUID()}`;
      if (!held.tryOpen(ip, slot, now.getTime() + SIGNIN_TTL_MS, now.getTime())) {
        throw new ApiError(429, "too_many_signins", "Too many open sign-in requests");
      }
      try {
        const started = await startSignin(deps.db, c.req.valid("json"), now);
        held.close(slot);
        held.tryOpen(ip, started.id, Date.parse(started.expiresAt), now.getTime());
        return c.json(started, 201);
      } catch (error) {
        held.close(slot);
        throw error;
      }
    },
  );

  app.openapi(
    createRoute({
      method: "get",
      path: "/v2/signin",
      operationId: "findSignin",
      middleware: [session, sessionOnly] as const,
      description:
        "The phone finds a request by the typed `code` (case, dashes, spaces and look-alike letters are forgiven) and gets its `commitment` and `label`. 404 when expired or once an approver is set.",
      request: { query: z.object({ code: z.string().min(1).max(32) }) },
      responses: { 200: jsonResponse(SigninFound, "The request"), ...problems(401, 403, 404) },
    }),
    async (c) => c.json(await findSignin(deps.db, c.req.valid("query").code, nowOf(deps)), 200),
  );

  app.openapi(
    createRoute({
      method: "get",
      path: "/v2/signin/{id}",
      operationId: "getSignin",
      description:
        "With `x-wambito-poll`, the browser polls: `approverKey` (null until the phone approves), `ready` (sealed: pick it up) and `expiresAt`; 404 for a wrong secret. Without it, the phone reads the request with its session (a scanned QR): `commitment`, `label`, `expiresAt` and the browser's revealed `publicKey` (null until revealed); once approved, 404 for any other user. 404 when expired.",
      request: { params: idParam, headers: pollHeader },
      responses: {
        200: jsonResponse(z.union([SigninPoll, SigninView]), "The request"),
        ...problems(401, 403, 404),
      },
    }),
    async (c) => {
      const { id } = c.req.valid("param");
      const secret = clientHeader(c.req.raw.headers, "poll");
      if (secret) return c.json(await pollSignin(deps.db, id, secret, nowOf(deps)), 200);
      // The phone's view: the session is checked here, as the session routes' middleware does.
      await session(c, async () => {});
      if (c.get("grant").kind !== "session") throw insufficientScope();
      return c.json(await viewSignin(deps.db, c.get("userId"), id, nowOf(deps)), 200);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v2/signin/{id}/approver",
      operationId: "setSigninApprover",
      middleware: [session, sessionOnly] as const,
      description:
        "The phone approves: its ephemeral public key, once; the request is bound to the phone's user. 404 when expired, 409 `already_set` for any later call.",
      request: { params: idParam, body: jsonBody(PairingApprover) },
      responses: { 204: { description: "Stored" }, ...problems(401, 403, 404, 409) },
    }),
    async (c) => {
      await setSigninApprover(
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
      path: "/v2/signin/{id}/reveal",
      operationId: "revealSignin",
      description:
        "The browser reveals its public key after it sees the approver key, with `x-wambito-poll`. 404 for a wrong or missing secret or when expired, 409 `not_ready` (no approver yet) or `already_set`, 422 `commitment_mismatch`.",
      request: { params: idParam, headers: pollHeader, body: jsonBody(PairingReveal) },
      responses: { 204: { description: "Stored" }, ...problems(403, 404, 409, 422) },
    }),
    async (c) => {
      await revealSignin(
        deps.db,
        c.req.valid("param").id,
        pollSecretOf(c.req.raw.headers),
        c.req.valid("json").publicKey,
        nowOf(deps),
      );
      return c.body(null, 204);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v2/signin/{id}/seal",
      operationId: "sealSignin",
      middleware: [session, sessionOnly] as const,
      description:
        "The approving phone posts the data key sealed to the browser's revealed key with the key version, as `POST /v2/pairing/{id}/seal`: 409 `not_ready`, `already_sealed`, `key_version_mismatch`, 422 `approver_mismatch`. 404 for any other user or when expired.",
      request: { params: idParam, body: jsonBody(SealPairing) },
      responses: { 204: { description: "Sealed" }, ...problems(401, 403, 404, 409, 422) },
    }),
    async (c) => {
      const { sealed, keyV } = c.req.valid("json");
      await sealSignin(
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
      method: "post",
      path: "/v2/signin/{id}/pickup",
      operationId: "pickupSignin",
      description:
        "The browser takes the sealed data key, with `x-wambito-poll`, and is signed in as the phone's user: the session travels in the `set-cookie` headers. With `remember` it is a 60-day session renewed on use; without, a 12-hour one whose cookie has no Max-Age (Better Auth's \"don't remember me\") and is never renewed. The request is deleted, so a second pickup is 404. 409 `not_ready` while unsealed; 403 `account_suspended`; 404 for a wrong secret or when expired.",
      request: { params: idParam, headers: pollHeader },
      responses: {
        200: jsonResponse(SigninPickup, "The sealed key; the session is in the headers"),
        ...problems(403, 404, 409),
      },
    }),
    async (c) => {
      const { id } = c.req.valid("param");
      const taken = await takeSignin(deps.db, id, pollSecretOf(c.req.raw.headers), nowOf(deps));
      held.close(id);
      await signInAs(auth, c, taken.userId, taken.remember ? "standard" : "short");
      return c.json({ sealed: taken.sealed, keyV: taken.keyV, userId: taken.userId }, 200);
    },
  );

  return app;
}
