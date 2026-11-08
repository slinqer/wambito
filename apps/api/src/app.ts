import { oauthProviderAuthServerMetadata } from "@better-auth/oauth-provider";
import { OpenAPIHono } from "@hono/zod-openapi";
import { getPath } from "hono/utils/url";
import { createAuth } from "./auth.ts";
import { apiPathPrefix } from "./config.ts";
import type { AppDeps } from "./deps.ts";
import type { AppEnv } from "./env.ts";
import { previewOnlyV2 } from "./http/preview.ts";
import { notFound, onError, validationHook } from "./http/problem.ts";
import { assistantScopes } from "./http/scopes.ts";
import { requireUser } from "./http/session.ts";
import { adminRoutes } from "./routes/admin.ts";
import { assistantRoutes } from "./routes/assistants.ts";
import { captureRoutes } from "./routes/captures.ts";
import { categoryRoutes } from "./routes/categories.ts";
import { emailChangeRoutes } from "./routes/email-change.ts";
import { importRoutes } from "./routes/imports.ts";
import { keyRoutes } from "./routes/keys.ts";
import { meRoutes } from "./routes/me.ts";
import { pairingRoutes } from "./routes/pairing.ts";
import { recurrenceRoutes } from "./routes/recurrences.ts";
import { reportRoutes } from "./routes/reports.ts";
import { summaryRoutes } from "./routes/summary.ts";
import { syncRoutes } from "./routes/sync.ts";
import { transactionRoutes } from "./routes/transactions.ts";

export type { AppDeps } from "./deps.ts";

/** A path no route matches: requests outside the API_URL prefix fall through to the 404. */
const OUTSIDE_PREFIX = "/\u0000outside-api-path";

/**
 * Routes are declared without the API_URL path prefix and matched after stripping it, so they all
 * live under the prefix while the OpenAPI document keeps prefix-free paths (its `servers` entry
 * carries API_URL instead).
 */
function stripPrefix(path: string, prefix: string): string {
  if (!prefix) return path;
  if (path === prefix) return "/";
  return path.startsWith(`${prefix}/`) ? path.slice(prefix.length) : OUTSIDE_PREFIX;
}

export function createApp(deps: AppDeps) {
  const auth = createAuth(deps);
  const prefix = apiPathPrefix(deps.config);
  const app = new OpenAPIHono<AppEnv>({
    defaultHook: validationHook,
    getPath: (request) => stripPrefix(getPath(request), prefix),
  });

  app.onError(onError);
  app.notFound(notFound);

  // The build's version, when it was given one (Settings in the app shows it). A pinned clock
  // (E2E_NOW) is reported, so the e2e suite can check the stack it runs against.
  app.get("/health", (c) =>
    c.json({
      status: "ok",
      ...(deps.config.WAMBITO_VERSION ? { version: deps.config.WAMBITO_VERSION } : {}),
      ...(deps.now ? { now: deps.now().toISOString() } : {}),
    }),
  );
  app.on(["GET", "POST"], "/auth/*", (c) => auth.handler(c.req.raw));
  // RFC 8414 puts an issuer's metadata at the well-known path followed by the issuer's path
  // (`/auth`, under API_URL), which is where MCP clients look for it; the bare path stays too.
  const authServerMetadata = oauthProviderAuthServerMetadata(auth);
  app.get("/.well-known/oauth-authorization-server", (c) => authServerMetadata(c.req.raw));
  app.get("/.well-known/oauth-authorization-server/auth", (c) => authServerMetadata(c.req.raw));

  // The admin panel's routes come before `requireUser`: `requireAdmin` judges them alone, and a
  // refused request gets a 404 (not requireUser's 401 or the scopes' 403), so the panel does not
  // announce itself.
  app.route("/", adminRoutes(deps, auth));
  // Public: the person confirming an admin's email change is usually signed out (rate-limited).
  app.route("/", emailChangeRoutes(deps));
  app.use("/v1/*", requireUser(auth, deps.config));
  app.use("/v1/*", assistantScopes());
  // A preview account's finances are records under /v2 only (403 `encrypted_account` on /v1's).
  app.use("/v1/*", previewOnlyV2(deps.config));
  app.use("/v2/*", requireUser(auth, deps.config));
  app.use("/v2/*", assistantScopes());
  app.route("/", meRoutes(deps));
  app.route("/", assistantRoutes(deps));
  app.route("/", categoryRoutes(deps));
  app.route("/", transactionRoutes(deps));
  app.route("/", captureRoutes(deps));
  app.route("/", recurrenceRoutes(deps));
  app.route("/", summaryRoutes(deps));
  app.route("/", reportRoutes(deps));
  app.route("/", importRoutes(deps));
  app.route("/", syncRoutes(deps));
  app.route("/", keyRoutes(deps));
  app.route("/", pairingRoutes(deps));

  app.doc31("/openapi.json", {
    openapi: "3.1.0",
    info: { title: "Wambito API", version: "1.0.0" },
    servers: [{ url: deps.config.API_URL }],
  });

  return app;
}
