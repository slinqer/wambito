import { z } from "zod";

const configSchema = z.object({
  /** This server's public URL (`https://…/mcp`): its resource identifier, and the tokens' audience. */
  MCP_URL: z.string().url(),
  /** Where the MCP reaches the API, with its path prefix (`http://api:3000/api` in the install). */
  MCP_API_URL: z.string().url(),
  /** The authorization server's issuer, as it stamps tokens: the API's public URL plus `/auth`. */
  AUTH_ISSUER: z.string().url(),
  /** The issuer's signing keys. Default: `${MCP_API_URL}/auth/jwks`. */
  JWKS_URL: z.string().url().optional(),
  /** Requests one assistant may make per minute; a looping assistant gets 429 past it. */
  RATE_LIMIT_PER_MINUTE: z.coerce.number().int().positive().default(120),
  MCP_PORT: z.coerce.number().int().default(3001),
  /**
   * The private half of the key the API seals the assistant secret to (the access token's `wk`
   * claim), a JWK as a JSON string. Without it, a token with `wk` (an encrypted account) gets the
   * reconnect error.
   */
  MCP_WK_PRIVATE_KEY: z
    .preprocess((v) => (v === "" ? undefined : v), z.string().trim().optional())
    .optional()
    .refine(
      (v) => v === undefined || isPrivateJwk(v),
      "MCP_WK_PRIVATE_KEY must be a private X25519 or P-256 JWK (with `d`)",
    ),
  /** As the API's /health, the build's version. */
  WAMBITO_VERSION: z
    .preprocess((v) => (v === "" ? undefined : v), z.string().trim().optional())
    .optional(),
});

/**
 * A private key that opens `ECDH-ES`: X25519 (`OKP`) with `x` and `d`, or P-256 (`EC`) with `x`, `y`
 * and `d`, and no symmetric part (`k`).
 */
function isPrivateJwk(value: string): boolean {
  try {
    const jwk = JSON.parse(value) as Record<string, unknown> | null;
    if (typeof jwk !== "object" || jwk === null || Array.isArray(jwk)) return false;
    if ("k" in jwk || typeof jwk.d !== "string" || typeof jwk.x !== "string") return false;
    if (jwk.kty === "OKP") return jwk.crv === "X25519";
    if (jwk.kty === "EC") return jwk.crv === "P-256" && typeof jwk.y === "string";
    return false;
  } catch {
    return false;
  }
}

export type Config = z.infer<typeof configSchema>;

export function loadConfig(env: NodeJS.ProcessEnv): Config {
  const parsed = configSchema.safeParse(env);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `  ${i.path.join(".")}: ${i.message}`);
    throw new Error(`Invalid MCP configuration:\n${issues.join("\n")}`);
  }
  return parsed.data;
}

export const jwksUrl = (config: Pick<Config, "JWKS_URL" | "MCP_API_URL">) =>
  config.JWKS_URL ?? `${config.MCP_API_URL.replace(/\/+$/, "")}/auth/jwks`;
