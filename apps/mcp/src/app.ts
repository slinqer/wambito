import {
  type AuthInfo,
  type CallToolResult,
  createMcpHandler,
  getOAuthProtectedResourceMetadataUrl,
  McpServer,
  type OAuthTokenVerifier,
  requireBearerAuth,
} from "@modelcontextprotocol/server";
import {
  type AssistantTool,
  PROMPTS,
  type Profile,
  serverInstructions,
  TOOLS,
  ToolError,
  type Wambito,
} from "@wambito/ai-assistant-tools";
import { Hono } from "hono";
import { z } from "zod";
import type { Config } from "./config.ts";
import { rateLimiter } from "./rate-limit.ts";
import { inRequest } from "./vault-wambito.ts";

/** Who the token is for, and (for prompt requests) the language to answer in. */
interface Caller {
  userId: string;
  /** An encrypted account's `wk` claim (still encrypted): the vault path opens it. */
  wk?: string;
  locale?: Profile["locale"];
}

export interface McpDeps {
  config: Pick<Config, "MCP_URL" | "AUTH_ISSUER" | "RATE_LIMIT_PER_MINUTE" | "WAMBITO_VERSION">;
  verifier: OAuthTokenVerifier;
  /**
   * The person's Wambito, acting with their assistant's token: over the vault when the token
   * carries `wk` (an encrypted account), else over the API's `/v1`.
   */
  wambitoFor(token: string, wk: string | undefined): Wambito;
  now?: () => Date;
}

const SCOPES = ["finance:read", "finance:write", "offline_access"];

/** JSON-RPC messages in a body, whether it is one message or a batch. */
const messagesOf = (body: unknown): { method?: unknown }[] =>
  (Array.isArray(body) ? body : [body]).filter(
    (m): m is { method?: unknown } => typeof m === "object" && m !== null,
  );

function toolResult(tool: AssistantTool<z.ZodObject, z.ZodObject>) {
  return async (
    input: Record<string, unknown>,
    wambito: Wambito,
    caller: Caller,
    now: () => Date,
  ): Promise<CallToolResult> => {
    try {
      // One tool call is one request on an encrypted account: the vault holds the account's lock
      // for all of it, so two calls never decide on a store the other is changing.
      const result = await inRequest(wambito, () =>
        tool.handler(input, { wambito, userId: caller.userId, now }),
      );
      return {
        content: [{ type: "text", text: result.text }],
        structuredContent: result.structured as Record<string, unknown>,
      };
    } catch (error) {
      if (!(error instanceof ToolError)) throw error;
      // Shown to the model, which can fix it: a category to choose, a field to correct.
      const data = error.data === undefined ? "" : `\n${JSON.stringify(error.data)}`;
      return {
        isError: true,
        content: [{ type: "text", text: `${error.code}: ${error.message}${data}` }],
      };
    }
  };
}

/**
 * The MCP server (spec §2.2): `POST /mcp` serves the assistant tools to clients of MCP 2026-07-28
 * and, through the SDK's stateless fallback, 2025-11-25. It holds no state between requests: each
 * one is checked (token, then the per-assistant rate limit) and served by a fresh McpServer acting
 * with that request's token. The OAuth discovery (RFC 9728) names the API's authorization server.
 */
export function createMcpApp(deps: McpDeps) {
  const { config } = deps;
  const now = deps.now ?? (() => new Date());
  const resource = new URL(config.MCP_URL);
  const resourceMetadataUrl = getOAuthProtectedResourceMetadataUrl(resource);
  const gate = requireBearerAuth({
    verifier: deps.verifier,
    expectedResource: resource,
    resourceMetadataUrl,
  });
  const limiter = rateLimiter(config.RATE_LIMIT_PER_MINUTE);
  const instructions = serverInstructions();

  const handler = createMcpHandler(
    ({ authInfo }) => {
      const server = new McpServer(
        { name: "wambito", title: "Wambito", version: config.WAMBITO_VERSION ?? "0.0.0" },
        {
          instructions,
          // The catalog only changes with a deploy.
          cacheHints: {
            "tools/list": { ttlMs: 300_000 },
            "prompts/list": { ttlMs: 300_000 },
            "server/discover": { ttlMs: 300_000 },
          },
        },
      );
      const caller = (authInfo?.extra ?? {}) as unknown as Caller;
      const token = authInfo?.token ?? "";
      let wambito: Wambito | undefined;
      const wambitoNow = () => {
        wambito ??= deps.wambitoFor(token, caller.wk);
        return wambito;
      };
      for (const tool of TOOLS as AssistantTool<z.ZodObject, z.ZodObject>[]) {
        const run = toolResult(tool);
        server.registerTool(
          tool.name,
          {
            title: tool.title,
            description: tool.description,
            inputSchema: tool.input,
            outputSchema: tool.output,
            annotations: { title: tool.title, ...tool.annotations },
            // A token without the tool's scope gets a challenge for it (step-up), not a failure
            // halfway through: the API would refuse the call anyway.
            scopeChallenge: ({ authInfo: info }) =>
              info?.scopes.includes(tool.scope)
                ? undefined
                : {
                    scopes: [...new Set([...(info?.scopes ?? []), tool.scope])] as [
                      string,
                      ...string[],
                    ],
                    errorDescription: `This needs ${tool.scope}`,
                  },
          },
          (input: Record<string, unknown>) => run(input, wambitoNow(), caller, now),
        );
      }
      const locale = caller.locale ?? "es";
      for (const prompt of PROMPTS) {
        const argsSchema = z.object(
          Object.fromEntries(
            prompt.args.map((a) => [a.name, z.string().optional().describe(a.description(locale))]),
          ),
        );
        server.registerPrompt(
          prompt.name,
          { title: prompt.title(locale), description: prompt.description(locale), argsSchema },
          (args: Record<string, string | undefined>) => ({
            messages: prompt
              .messages(locale, args)
              .map((m) => ({ role: m.role, content: { type: "text" as const, text: m.text } })),
          }),
        );
      }
      return server;
    },
    { legacy: "stateless" },
  );

  /**
   * The person's language for prompts. A Wambito that cannot answer (an encrypted account whose
   * assistant was disconnected) leaves the default: a prompt is text, not data.
   */
  async function localeOf(token: string, extra: Caller): Promise<Pick<Caller, "locale">> {
    try {
      return { locale: (await deps.wambitoFor(token, extra.wk).profile()).locale };
    } catch (error) {
      if (error instanceof ToolError) return {};
      throw error;
    }
  }

  const app = new Hono();

  app.get("/health", (c) =>
    c.json({
      status: "ok",
      ...(config.WAMBITO_VERSION ? { version: config.WAMBITO_VERSION } : {}),
    }),
  );

  // RFC 9728: what this resource is, and which authorization server issues its tokens.
  const metadata = () => ({
    resource: config.MCP_URL,
    authorization_servers: [config.AUTH_ISSUER],
    scopes_supported: SCOPES,
    bearer_methods_supported: ["header"],
    resource_name: "Wambito",
  });
  app.get("/.well-known/oauth-protected-resource", (c) => c.json(metadata()));
  app.get(`/.well-known/oauth-protected-resource${resource.pathname}`, (c) => c.json(metadata()));

  app.all(resource.pathname, async (c) => {
    const auth: AuthInfo | Response = await gate(c.req.raw);
    if (auth instanceof Response) return auth;
    if (!limiter.take(auth.clientId)) {
      return c.json({ error: "rate_limited", error_description: "Too many requests" }, 429, {
        "Retry-After": "60",
      });
    }
    const parsedBody =
      c.req.method === "POST" ? await c.req.json().catch(() => undefined) : undefined;
    // Prompts are titled and written in the person's language: only those requests ask for it.
    const wantsLocale = messagesOf(parsedBody).some(
      (m) => typeof m.method === "string" && m.method.startsWith("prompts/"),
    );
    const extra = auth.extra as unknown as Caller;
    const caller: Caller = { ...extra, ...(wantsLocale ? await localeOf(auth.token, extra) : {}) };
    return handler.fetch(c.req.raw, {
      authInfo: { ...auth, extra: caller as unknown as Record<string, unknown> },
      ...(parsedBody === undefined ? {} : { parsedBody }),
    });
  });

  return app;
}
