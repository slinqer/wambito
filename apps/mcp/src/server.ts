import { serve } from "@hono/node-server";
import { createMcpApp } from "./app.ts";
import { loadConfig } from "./config.ts";
import { createVaultCache, VAULT_CACHE_DEFAULTS } from "./vault-cache.ts";
import { createWambitoFor, importWkPrivateKey } from "./vault-wambito.ts";
import { jwtVerifier } from "./verifier.ts";

const config = loadConfig(process.env);
const app = createMcpApp({
  config,
  verifier: jwtVerifier(config),
  // A token with `wk` (an encrypted account) opens the vault in memory; others go to `/v1`.
  wambitoFor: createWambitoFor({
    apiUrl: config.MCP_API_URL,
    privateKey: await importWkPrivateKey(config.MCP_WK_PRIVATE_KEY),
    cache: createVaultCache(VAULT_CACHE_DEFAULTS),
  }),
});

serve({ fetch: app.fetch, port: config.MCP_PORT }, (info) => {
  console.log(`Wambito MCP on :${info.port}, serving ${config.MCP_URL}`);
});
