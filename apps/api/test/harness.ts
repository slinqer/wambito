import { createHash, randomBytes } from "node:crypto";
import type { ClientMetadataResourceFetch } from "@better-auth/oauth-provider";
import { categories, createDb, type Db, user } from "@wambito/db";
import { eq } from "@wambito/db/orm";
import { startTestDatabase } from "@wambito/db/testing";
import { createApp } from "../src/app.ts";
import type { Config } from "../src/config.ts";
import type { SyncHooks } from "../src/deps.ts";
import { MemoryMailer } from "../src/mailer.ts";

export type TestApp = Awaited<ReturnType<typeof createTestApp>>;

export const TEST_CONFIG = {
  BETTER_AUTH_SECRET: "test-secret-test-secret-test-secret-0000",
  API_URL: "http://localhost:3000",
  WEB_URL: "http://localhost:5173",
  MAIL_FROM: "Wambito <test@wambito.test>",
  PORT: 3000,
  NODE_ENV: "test" as const,
  CLIENT_IP_HEADER: "x-forwarded-for",
  GUEST_SIGNUP: true,
  TRUSTED_PROXIES: ["10.0.0.0/8"],
  ADMIN_USER_IDS: [],
  E2E_PREVIEW_USER_IDS: [] as string[],
  MCP_URL: "http://localhost:3001/mcp",
};

/** Where Claude sends people back after consent; the test clients use it too. */
export const ASSISTANT_REDIRECT = "https://claude.ai/api/mcp/auth_callback";

export interface AssistantTokens {
  accessToken: string;
  refreshToken: string;
  clientId: string;
}

export function codeFrom(subject: string): string {
  const match = /(\d{6})$/.exec(subject);
  if (!match?.[1]) throw new Error(`No code in subject: ${subject}`);
  return match[1];
}

/** A fresh database + app per test file. Requests go through `app.request` (no network). */
export async function createTestApp(
  overrides: Partial<Config> = {},
  {
    now,
    fetchClientMetadata,
    syncHooks,
  }: {
    now?: () => Date;
    fetchClientMetadata?: ClientMetadataResourceFetch;
    syncHooks?: SyncHooks;
  } = {},
) {
  const database = await startTestDatabase();
  const app$ = createDb(database.appUrl);
  const admin = createDb(database.adminUrl);
  const mailer = new MemoryMailer();
  const config: Config = {
    ...TEST_CONFIG,
    DATABASE_URL: database.appUrl,
    DATABASE_ADMIN_URL: database.adminUrl,
    ...overrides,
  };
  const app = createApp({
    config,
    db: app$.db,
    mailer,
    now,
    fetchClientMetadata,
    syncHooks,
  });

  // Distinct fake client IPs (behind a trusted 10.x proxy) keep the per-IP auth rate limit out of
  // unrelated tests.
  let ipCounter = 0;
  const nextIp = () => `198.51.${Math.floor(++ipCounter / 250)}.${ipCounter % 250}, 10.0.0.1`;

  async function request(
    method: string,
    path: string,
    { body, headers = {} }: { body?: unknown; headers?: Record<string, string> } = {},
  ): Promise<Response> {
    const init: RequestInit = {
      method,
      headers: {
        "x-forwarded-for": nextIp(),
        ...(body !== undefined && !(body instanceof FormData)
          ? { "content-type": "application/json" }
          : {}),
        ...headers,
      },
    };
    if (body !== undefined) init.body = body instanceof FormData ? body : JSON.stringify(body);
    return app.request(path, init);
  }

  /** Runs the email-code sign-in for `email`; returns the sign-in response and the user id. */
  async function signInResponse(
    email: string,
    starterCategories: boolean,
  ): Promise<{ res: Response; userId: string }> {
    const existed =
      (await admin.db.select({ id: user.id }).from(user).where(eq(user.email, email))).length > 0;
    const sent = await request("POST", "/auth/email-otp/send-verification-otp", {
      body: { email, type: "sign-in" },
    });
    if (sent.status !== 200)
      throw new Error(`send otp failed: ${sent.status} ${await sent.text()}`);
    const mail = mailer.lastTo(email);
    if (!mail) throw new Error("no sign-in mail");
    const res = await request("POST", "/auth/sign-in/email-otp", {
      body: { email, otp: codeFrom(mail.subject) },
    });
    if (res.status !== 200) throw new Error(`sign-in failed: ${res.status} ${await res.text()}`);
    const json = (await res.clone().json()) as { user: { id: string } };
    if (!existed && !starterCategories) {
      await admin.db.delete(categories).where(eq(categories.userId, json.user.id));
    }
    return { res, userId: json.user.id };
  }

  /**
   * Signs `email` in. A new account starts with the suggested categories (auth.ts); this helper
   * clears them on the account's first sign-in, so a test builds its categories on a blank slate.
   * Pass `{ starterCategories: true }` to keep them (guests.test.ts tests them directly).
   */
  async function signIn(
    email: string,
    { starterCategories = false }: { starterCategories?: boolean } = {},
  ): Promise<{ userId: string; headers: { authorization: string } }> {
    const { res, userId } = await signInResponse(email, starterCategories);
    const token = res.headers.get("set-auth-token");
    return { userId, headers: { authorization: `Bearer ${token}` } };
  }

  /**
   * Signs `email` in as the web does: the session travels in the cookie the sign-in set, not in a
   * bearer token (the admin panel accepts only that).
   */
  async function signInCookie(
    email: string,
  ): Promise<{ userId: string; headers: { cookie: string } }> {
    const { res, userId } = await signInResponse(email, false);
    const cookie = res.headers
      .getSetCookie()
      .map((c) => c.split(";")[0])
      .join("; ");
    if (!cookie) throw new Error("sign-in set no cookie");
    return { userId, headers: { cookie } };
  }

  /** Registers an assistant by Dynamic Client Registration; returns its client_id. */
  async function registerAssistant(name = "Claude"): Promise<string> {
    const res = await request("POST", "/auth/oauth2/register", {
      body: {
        client_name: name,
        client_uri: "https://claude.ai",
        redirect_uris: [ASSISTANT_REDIRECT],
        token_endpoint_auth_method: "none",
        grant_types: ["authorization_code", "refresh_token"],
        response_types: ["code"],
      },
    });
    if (res.status !== 201) throw new Error(`register failed: ${res.status} ${await res.text()}`);
    return ((await res.json()) as { client_id: string }).client_id;
  }

  /** POSTs a form to the token endpoint, as OAuth clients do. */
  async function tokenRequest(form: Record<string, string>): Promise<Response> {
    return app.request("/auth/oauth2/token", {
      method: "POST",
      headers: {
        "content-type": "application/x-www-form-urlencoded",
        "x-forwarded-for": nextIp(),
      },
      body: new URLSearchParams(form).toString(),
    });
  }

  /**
   * Runs the whole authorization code flow with PKCE for `email`, as Claude would: authorize
   * (signed in), consent, then the code for tokens, for `resource` (the MCP by default).
   */
  async function authorize(
    email: string,
    {
      scope = "finance:read finance:write offline_access",
      resource = config.MCP_URL,
      clientId,
      headers,
    }: {
      scope?: string;
      resource?: string;
      clientId?: string;
      headers?: { authorization: string };
    } = {},
  ): Promise<AssistantTokens> {
    const client = clientId ?? (await registerAssistant());
    const session = headers ?? (await signIn(email)).headers;
    const verifier = randomBytes(32).toString("base64url");
    const query = new URLSearchParams({
      response_type: "code",
      client_id: client,
      redirect_uri: ASSISTANT_REDIRECT,
      scope,
      state: "state",
      code_challenge: createHash("sha256").update(verifier).digest("base64url"),
      code_challenge_method: "S256",
      ...(resource ? { resource } : {}),
    });
    const auth = await request("GET", `/auth/oauth2/authorize?${query}`, { headers: session });
    const consentUrl = auth.headers.get("location") ?? "";
    if (!consentUrl.startsWith(`${config.WEB_URL}/oauth/consent`)) {
      throw new Error(`authorize did not ask for consent: ${auth.status} ${consentUrl}`);
    }
    const consent = await request("POST", "/auth/oauth2/consent", {
      headers: session,
      body: { accept: true, oauth_query: new URL(consentUrl).search.slice(1) },
    });
    if (consent.status !== 200) {
      throw new Error(`consent failed: ${consent.status} ${await consent.text()}`);
    }
    const back = new URL(((await consent.json()) as { url: string }).url);
    const res = await tokenRequest({
      grant_type: "authorization_code",
      code: back.searchParams.get("code") ?? "",
      redirect_uri: ASSISTANT_REDIRECT,
      client_id: client,
      code_verifier: verifier,
      ...(resource ? { resource } : {}),
    });
    if (res.status !== 200) throw new Error(`token failed: ${res.status} ${await res.text()}`);
    const tokens = (await res.json()) as { access_token: string; refresh_token: string };
    return {
      accessToken: tokens.access_token,
      refreshToken: tokens.refresh_token,
      clientId: client,
    };
  }

  return {
    app,
    config,
    registerAssistant,
    tokenRequest,
    authorize,
    db: app$.db as Db,
    admin: admin.db as Db,
    mailer,
    request,
    signIn,
    signInCookie,
    async stop() {
      await app$.close();
      await admin.close();
      await database.stop();
    },
  };
}
