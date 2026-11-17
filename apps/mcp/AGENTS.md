# apps/mcp: the MCP server (`@wambito/mcp`)

Lets AI assistants (Claude, ChatGPT…) read and write the person's finances. Holds no data: every
tool calls the API with the assistant's token. For an encrypted account it opens the records in
memory for the request (below) and keeps only their ciphertext.

## Entry points

- `src/server.ts`: wires `wambitoFor: createWambitoFor(...)` (`src/vault-wambito.ts`): a token
  without a `wk` claim → `apiWambito(MCP_API_URL, token)` over `/v1`; with one → `vaultWambito`;
  with one and no `MCP_WK_PRIVATE_KEY` → every call is the `reconnect` tool error.
- `src/app.ts`: MCP server `{ name: "wambito", title: "Wambito" }`, tools and prompts from
  `@wambito/ai-assistant-tools`, protected-resource metadata, rate limit (`src/rate-limit.ts`).
- `src/api-wambito.ts`: the `Wambito` interface over the HTTP API (bearer token); 401 and 403
  `encrypted_account` are the `reconnect` tool error (`RECONNECT_MESSAGE`).
- `src/vault-wambito.ts`: encrypted accounts (spec 2026-11-16 §7). Per MCP request, under the
  account's lock: `wk` (a JWE) → `S`, `GET /v2/keys/assistant` → wrap and links → record keys
  (`S` and data keys zeroed once derived), a memory store rebuilt from the cache, one `/v2/sync`
  run, then `apiWambito(apiUrl, token, backend.fetch)` over `@wambito/vault`'s local backend
  (`source: "mcp"`, ids from the `Idempotency-Key`). A write runs the sync once more and is the
  `not_saved` tool error unless every change was acknowledged; a read never pushes. `app.ts` runs
  each tool inside `inRequest` (the lock for the whole tool call, the vault dropped at its end); a
  method called outside one is a request of its own.
- `src/vault-cache.ts`: per account, only what `/v2/sync` sent (ciphertext, tombstones) and the
  cursor; LRU by accounts and bytes, 30 minutes idle (`VAULT_CACHE_DEFAULTS`), dropped on `410
  resync_required` or a new key version; `lock(userId, fn)` runs one request per account.
- `src/verifier.ts`: token checks; `extra` = `{ userId, wk? }`. `src/config.ts`: env
  (`MCP_WK_PRIVATE_KEY`, the JWK that opens `wk`; dev pair in the root `.env.example`).
- `src/api/schema.d.ts`: generated API types (command: root `AGENTS.md`; CI diffs it).

## MCP → API

- The assistant's OAuth access token is a JWT from the API's `/auth`, `aud` = MCP_URL; the MCP
  forwards it, the API checks scopes (`apps/api/src/http/scopes.ts`).
- Dev: MCP_URL `http://localhost:3001/mcp`, MCP_API_URL `http://localhost:3000/api`
  (`.env.example`). In production Caddy routes `/mcp` to it (`deploy/personal/routes.caddy`).

## Run and test (repo root)

- `pnpm --filter @wambito/mcp dev` (API running).
- `pnpm vitest run apps/mcp`. `test/end-to-end.test.ts`, `test/api-wambito.test.ts` and
  `test/vault-wambito.test.ts` start the API test app: Docker needed. The vault test plays the web
  with a vault of its own (memory store, sync engine) to seal records, wrap `S` and rotate keys; its
  helpers live in `test/support/encrypted-account.ts` (`encryptedSupport(() => t)`).
  `test/vault-end-to-end.test.ts`: the SDK client through `createMcpApp` on a preview account, all 14
  tools, revoke with a live token, rotation, a retried consent, a write-only grant, and a scan of
  every table for plain text.
- Scopes on the vault path: a read tool needs `finance:read` and a write tool `finance:write`
  (the MCP's `scopeChallenge` asks for the missing one first); the vault pull (`GET /v2/sync`,
  `GET /v1/me`) needs `finance:read`, so a token with only `finance:write` gets the tool error
  `insufficient_scope` ("This assistant cannot do that") on every tool, and nothing is written.

## Traps

- Every change here that clients can see goes under "Unreleased" in the root `CHANGELOG.md`.
- Tool names, scopes and the `/mcp` path are a public contract: changing them breaks connected
  assistants.
- Tool behaviour and wording live in `packages/ai-assistant-tools`, not here.
- Nothing the vault path logs may carry a body, an amount, a name, `S` or a key: codes and counts
  only (`log` in `src/vault-wambito.ts`; a test captures the console).
