import { describe, expect, test } from "vitest";
import { loadConfig } from "../src/config.ts";

const env = {
  MCP_URL: "http://localhost:3001/mcp",
  MCP_API_URL: "http://localhost:3000",
  AUTH_ISSUER: "http://localhost:3000/auth",
};

const x25519 =
  '{"kty":"OKP","crv":"X25519","x":"CMdyb71RFPM5XsuizCiPU7FSFoa-3_D3pGaX9uFe3Ek","d":"EEE_hOXo4OQuqVq9GdvY3uGfzM-vGm1FeX4GD9p2xlc"}';
const p256 =
  '{"kty":"EC","crv":"P-256","x":"f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU","y":"x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0","d":"jpsQnnGQmL-YBIffH1136cspYG6-0iY7X1fCE9-E9LI"}';

describe("MCP_WK_PRIVATE_KEY", () => {
  test("takes a private X25519 or P-256 key; blank means none", () => {
    expect(loadConfig({ ...env, MCP_WK_PRIVATE_KEY: x25519 }).MCP_WK_PRIVATE_KEY).toBe(x25519);
    expect(loadConfig({ ...env, MCP_WK_PRIVATE_KEY: p256 }).MCP_WK_PRIVATE_KEY).toBe(p256);
    expect(loadConfig(env).MCP_WK_PRIVATE_KEY).toBeUndefined();
    expect(loadConfig({ ...env, MCP_WK_PRIVATE_KEY: "" }).MCP_WK_PRIVATE_KEY).toBeUndefined();
  });

  test("refuses anything else", () => {
    for (const value of [
      "not json",
      "[]",
      // The public half only.
      '{"kty":"OKP","crv":"X25519","x":"CMdyb71RFPM5XsuizCiPU7FSFoa-3_D3pGaX9uFe3Ek"}',
      // A symmetric key, or a key with a symmetric part.
      '{"kty":"oct","k":"GawgguFyGrWKav7AX4VKUg","d":"x"}',
      '{"kty":"OKP","crv":"X25519","x":"CMdyb71RFPM5XsuizCiPU7FSFoa-3_D3pGaX9uFe3Ek","d":"EEE_hOXo4OQuqVq9GdvY3uGfzM-vGm1FeX4GD9p2xlc","k":"GawgguFyGrWKav7AX4VKUg"}',
      // A signing curve, not an ECDH-ES one.
      '{"kty":"OKP","crv":"Ed25519","x":"11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo","d":"nWGxne_9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A"}',
      // A kty and crv that do not go together.
      '{"kty":"EC","crv":"X25519","x":"CMdyb71RFPM5XsuizCiPU7FSFoa-3_D3pGaX9uFe3Ek","d":"EEE_hOXo4OQuqVq9GdvY3uGfzM-vGm1FeX4GD9p2xlc"}',
    ]) {
      expect(() => loadConfig({ ...env, MCP_WK_PRIVATE_KEY: value })).toThrow(/MCP_WK_PRIVATE_KEY/);
    }
  });
});
