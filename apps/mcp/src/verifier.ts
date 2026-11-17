import type { AuthInfo, OAuthTokenVerifier } from "@modelcontextprotocol/server";
import { OAuthError, OAuthErrorCode } from "@modelcontextprotocol/server";
import { createRemoteJWKSet, type JWTVerifyGetKey, jwtVerify } from "jose";
import { type Config, jwksUrl } from "./config.ts";

/** The person behind a token, which the tools act for. */
export interface TokenUser {
  userId: string;
  /**
   * An encrypted account's `wk` claim, still encrypted (a JWE to the MCP's key, holding the
   * assistant secret `S`): the vault path opens it per request. Absent for plain accounts.
   */
  wk?: string;
}

/**
 * Checks an assistant's access token before anything runs: signed by the issuer's keys, from the
 * issuer, for this server (RFC 8707 audience), not expired. The API checks it again on every call;
 * this gate answers 401 with `WWW-Authenticate` early, as MCP clients expect.
 */
export function jwtVerifier(
  config: Pick<Config, "AUTH_ISSUER" | "MCP_URL" | "JWKS_URL" | "MCP_API_URL">,
  keys: JWTVerifyGetKey = createRemoteJWKSet(new URL(jwksUrl(config))),
): OAuthTokenVerifier {
  return {
    async verifyAccessToken(token: string): Promise<AuthInfo> {
      try {
        const { payload } = await jwtVerify(token, keys, {
          issuer: config.AUTH_ISSUER,
          audience: config.MCP_URL,
        });
        const clientId = typeof payload.azp === "string" ? payload.azp : payload.client_id;
        if (typeof payload.sub !== "string" || typeof clientId !== "string" || !payload.exp) {
          throw new Error("missing claims");
        }
        return {
          token,
          clientId,
          scopes: typeof payload.scope === "string" ? payload.scope.split(" ").filter(Boolean) : [],
          expiresAt: payload.exp,
          resource: new URL(config.MCP_URL),
          extra: {
            userId: payload.sub,
            ...(typeof payload.wk === "string" ? { wk: payload.wk } : {}),
          } satisfies TokenUser,
        };
      } catch {
        throw new OAuthError(OAuthErrorCode.InvalidToken, "Invalid or expired access token");
      }
    },
  };
}
