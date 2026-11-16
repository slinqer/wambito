# E2E stage 4: the MCP reads encrypted accounts

Date: 2026-11-16. Status: design agreed in conversation, under review.

Parent spec: `2026-11-08-end-to-end-encryption-design.md` (sections 9 and 14, stage 4). Stage 0
evidence: `docs/superpowers/reports/2026-11-08-e2e-spikes.md`, "Assistant secret in tokens". This
document settles what section 9 left open and amends it where the founder decided otherwise
(section 3).

## 1. Intent

When the switch of stage 5 turns on, every account becomes encrypted. A connected AI assistant
(Claude, ChatGPT, through the remote MCP) must keep working for those accounts, with the same 14
tools and the same answers, while the server still never stores anything that opens the data.

Today an encrypted (`preview`) account gets 403 `encrypted_account` from every finance tool,
because the MCP calls the `/v1` finance routes, which refuse such accounts
(`apps/api/src/http/preview.ts`). Stage 4 makes the MCP read and write the account's encrypted
records instead, opening them in memory during each request with a key the assistant itself
carries.

### Goals

- A `preview` account connects an assistant from the web consent page and every tool works:
  reads give the same figures the web shows, writes appear on the web and the phone after a sync.
- The server never stores `S`, the data key or any plaintext; the MCP holds them only in memory
  during one request.
- Revoking an assistant cuts its access at once, from anywhere, without asking for anything.
- `plain` accounts see no change (stages ship behind the switch).

### Non-goals

- Connecting an assistant from the phone (the consent page is on the web; the phone has no
  assistants screen today).
- A local MCP that pairs as a device (parent spec section 16, later).
- Changing what the tools return (they keep returning computed totals, not raw rows).
- The migration of `plain` accounts (stage 5).

### Anti-goals (a failure even if it works)

- The MCP and the web disagreeing on a figure for the same data.
- `S`, the data key or a decrypted body reaching a database column, a log line, an error
  message or a cache.
- An assistant that keeps reading after it was revoked, or after a device removal rotated the
  keys, beyond the request already in flight.
- Tokens issued without `S` for an encrypted account (the assistant would look connected and fail
  on every call).

## 2. Approaches considered

| | What | Trade-off |
|---|---|---|
| **A (chosen)** | Move the web's local backend and sync engine into a shared package; the MCP runs them over an in-memory store | The largest stage: code the web already uses moves. One implementation, so the MCP and the web cannot disagree |
| B | Copy the record-to-answer logic into the MCP | Faster, but a third copy of the rules (after the web and Dart) that drifts; the parent spec names drift as a main risk |
| C | A minimal MCP that only computes what `packages/core` already exposes | Several of the 14 tools would not work for encrypted accounts, so stage 5 could not turn on |

Rejected outright: keeping decrypted data in a server cache to answer faster (the parent spec
allows only ciphertext in memory, never plaintext or keys).

What makes A cheap: the web's local backend (`apps/web/app/local/backend.ts`) is already a
`fetch` that answers the `/api/v1/*` routes from a `FinanceStore` with the API's shapes, rules,
validation and error codes, and the MCP's `apiWambito(baseUrl, token, fetchImpl)` already takes a
`fetch`. The MCP can hand its tools that backend's `fetch` and keep `api-wambito.ts` almost as it
is. The backend lacks three things the MCP uses today, which it gains (section 6): `POST
/v1/transactions/batch`, `POST /v1/transactions/batch-delete` and the `Idempotent-Replayed`
answer header.

## 3. Decisions taken with the founder

| Question | Decision |
|---|---|
| How the code is shared | Approach A: a shared package (section 6) |
| How the consent page gets the data key | From this browser's open vault when it has one (its `device` wrap, no touch); otherwise a passkey with PRF or the recovery key. This amends parent spec 7.4, which asked for a passkey touch every time |
| What "Revoke" does | Deletes the assistant's wrap and its tokens at once, **without rotating**. Rotation stays available on its own in Settings → Security |
| Rotation (removing a device) | Unchanged: it rotates, which disconnects every assistant (they hold no wrap under the new key). Now it also revokes them, so the list stays honest (section 8) |

Why no rotation on revoke: a rotation needs the recovery key (to wrap the new data key), so it
would make revoking as heavy as removing a device. The assistant's company holds only `S`, which
opens nothing once its wrap is deleted. Rotation would only add protection against a server that
kept the data key while the assistant was connected, and a compromised server can already take
the key from the web page (parent spec section 3). This amends parent spec 7.5 and section 9
("Disconnecting deletes the wrap and rotates the key").

## 4. Tokens carry `S` (API)

As built in the stage 0 spike, now in production code.

- **New `apps/api/src/http/assistant-secret.ts`:** a wrapper in front of Better Auth's
  `/auth/oauth2/*` handler, mounted before the `/auth/*` route in `app.ts`.
  - **Consent** (`POST /auth/oauth2/consent`): takes an optional `wk` (base64url, exactly 32
    bytes) out of the JSON before Better Auth sees it, forwards the rest, reads `code` from the
    answer's `url` and keeps `code → { S, expiresAt: now + 10 min }` in a process-memory map
    (swept on expiry).
  - **Code exchange** (`grant_type=authorization_code`): takes the entry for `code` (deleted
    whatever happens) and runs Better Auth inside an `AsyncLocalStorage` holding `S`;
    `customAccessTokenClaims` adds `wk` to the access token and the wrapper appends `.` + `S` to
    the refresh token.
  - **Refresh**: splits `.S` off the last `.`, forwards the plain token, runs the handler in the
    store with that `S`, appends `.S` to the new refresh token.
  - **Revoke and introspect**: strip the suffix before Better Auth sees the token (RFC 7009
    answers 200 for an unknown token, so a missed strip would revoke nothing).
- **The `wk` claim** is `S` encrypted to the MCP: a compact JWE, `ECDH-ES` with `A256GCM`, to the
  MCP's public key, with `jose` (already in `apps/mcp`; added to `apps/api`, pinned exactly). Only the MCP can read it; the
  refresh token carries `S` in the clear to the assistant's company, by design.
- **Refusal instead of silent loss:** the token endpoint refuses (`400 invalid_grant`, the OAuth
  shape) to issue or refresh tokens for an account that `isPreviewAccount` marks as encrypted
  when it has no `S` for the request (the map lost it on a restart, an old connection without
  `S` refreshes, or a reused refresh token killed the family). The refusal also revokes that
  client for the account (consent, tokens, wrap: the revoke of section 8), so the next connect
  starts clean. A `plain` account without `S` gets exactly today's tokens.
- **The consent page always shows for encrypted accounts:** Better Auth skips the consent page
  when a consent already covers the scopes, which would send a code without `S`. The wrapper adds
  `prompt=consent` to `/auth/oauth2/authorize` when the signed-in account is encrypted, so every
  connect of such an account goes through the page of section 5 and carries `S`.
- **The account's state comes from the token's user** (the code's or the refresh token's), never
  from the request body.
- **Never logged:** `S` travels only in POST bodies, the refresh token and the JWE; no log line,
  error detail or problem+json carries them. A test checks the API's log output during a full
  connect-refresh-revoke run.
- **Config:** `MCP_WK_PUBLIC_KEY` (API) and `MCP_WK_PRIVATE_KEY` (MCP), JWK strings, in both
  `.env.example` files and `deploy/personal` (compose, `.env.example`, `AGENTS.md`), with the
  command that makes a pair. With no public key configured the API refuses a consent that carries
  `wk` (`503 assistant_keys_missing`), so a misconfigured server fails loudly instead of issuing
  tokens without `S`.
- **`GET /v2/keys/assistant`** also returns the account's key links (the previous data keys
  sealed under the newer ones), so the MCP can open a record still under an older key version.
  This changes its answer's shape: OpenAPI, the generated types of the web and the MCP, and a
  `CHANGELOG.md` line. (`GET /v2/keys`, which has the links, stays out of an assistant's reach.)
- `CHANGELOG.md` (Unreleased): the consent body's `wk`, the refresh token's format for encrypted
  accounts, the `wk` claim, `400 invalid_grant` without `S`, `503 assistant_keys_missing`, the
  links on `GET /v2/keys/assistant`, and the revoke and rotation changes of section 8.

## 5. The consent page (web)

`apps/web/app/features/assistants/Consent.tsx` (with `consent-api.ts`, `consent-model.ts`).

- For a `plain` account: unchanged.
- For an encrypted account, "Allow" first gets the data key:
  1. **This browser has the vault open** (a vault session for this account): DK from its own
     `device` wrap, as `withDataKey` in `apps/web/app/local/keys.ts` does. No touch.
  2. **Otherwise:** the page offers the passkey (PRF) and the recovery key, reusing the Unlock
     screen's pieces. DK stays in memory for this step; nothing is stored and no device is
     enrolled.
- Then, in this order:
  1. makes `S` (32 random bytes) and the `assistant` wrap of DK under `S` (`wrapDataKey` in
     `packages/crypto`, kind `assistant`, ref = the OAuth client id, the current `keyV`);
  2. posts the consent with `wk` = `S`;
  3. `PUT /v2/keys/{id}` the wrap (the server accepts an `assistant` wrap only for a client the
     person has consented to, so it comes after the consent; a reconnect of the same client
     replaces its wrap);
  4. forgets DK and `S` and follows the redirect.

  If step 3 fails after step 2 succeeded, the page says so and offers "Try again" (steps 1–3
  again with a new `S`: the code already issued carries the old `S`, so the page also revokes that
  consent first through the revoke route, then consents again). The assistant never gets a working
  connection without a wrap.
- **Copy** (parent spec section 9, in the four languages): while connected, Wambito opens your
  data on its server only to answer your assistant, and the assistant's company reads what it is
  given. Revoking cuts it at once.
- Settings → Assistants: the `off` mode for preview accounts (`AssistantsSection.tsx`) goes; the
  list and "Revoke" work for every account.

## 6. The shared package

New `packages/vault` (`@wambito/vault`, with its `AGENTS.md` and a row in the root map). It holds
what the web and the MCP both run, with nothing tied to the browser:

- the local backend (`backend.ts` today), unchanged in behaviour for the web, plus:
  - `POST /v1/transactions/batch` and `POST /v1/transactions/batch-delete`, with the API's
    shapes and codes;
  - the `Idempotent-Replayed: true` header on a replayed `Idempotency-Key`;
  - an option that forces the `source` of every movement it creates (the MCP passes `mcp`, as the
    API forces it for OAuth grants today), whatever the body says;
  - an option that derives the ids of a batch create from its `Idempotency-Key` (section 7);
- the store contract (`FinanceStore`, `StoreOps`, the shared contract tests) and the memory store;
- the sync engine (`sync.ts`), over an `EncryptedStore` **interface** (outbox, cursors,
  quarantine, set-aside) rather than the IndexedDB class, with an option that turns off the
  upgrade pass (re-sealing records under an older key version), which the MCP never runs;
- an in-memory `EncryptedStore` that passes the same contract tests as the IndexedDB one;
- `ids.ts` (UUID v5 and v7) and the keyring type.

What stays in `apps/web`: the IndexedDB store and `db.ts`, `keys.ts` (non-extractable `CryptoKey`s
in IndexedDB), `rotate.ts`, `pairing.ts`, `prf.ts`, `vault-session.ts`, Web Locks, the
`x-wambito-user` header's session check, and the screens.

The move is a refactor first: the web's unit tests and e2e must pass unchanged on the moved code
before the MCP uses it. `pnpm --filter @wambito/web` imports change; behaviour does not.

## 7. The MCP's encrypted implementation

`apps/mcp` gains `@wambito/crypto` and `@wambito/vault`.

- **Which path:** a verified access token with a `wk` claim takes the encrypted path; one without
  it takes today's `api-wambito.ts` against `/v1`. An encrypted account reaching `/v1` (an old
  connection) still gets 403 `encrypted_account`, which the MCP turns into a tool error asking the
  person to connect the assistant again.
- **Each request** (tools are stateless today, `app.ts`):
  1. decrypt `wk` with `MCP_WK_PRIVATE_KEY` → `S`;
  2. `GET /v2/keys/assistant` with the token → the wrap and the key links; open DK with `S`
     (404 = revoked or rotated away: a tool error "this assistant was disconnected, connect it
     again"; the request ends);
  3. derive the record keys for the current version and, through the links, the older ones;
  4. build an in-memory encrypted store from the account's cached ciphertext (below), run one
     sync pass with the token (`/v2/sync`), which pulls only what changed since the cached cursor;
  5. build the local backend over that store, with `now`, the profile from `GET /v1/me` (allowed
     for encrypted accounts) and `source: "mcp"` on every movement it creates;
  6. run the tool through `apiWambito(baseUrl, token, backend.fetch)`;
  7. after a writing tool, one more sync pass pushes the changes. The tool fails if any change
     it made is not acknowledged (parked, dropped, or the run stopped); its error says that part
     of it may have been saved and that trying again is safe (ids are stable, section below).
     Nothing is kept to retry later: the MCP has no outbox between requests. A read tool never
     pushes (no re-seal: the upgrade pass is off), so a `finance:read` token never needs `POST
     /v2/sync`;
  8. store the pulled ciphertext and the cursor back into the cache; drop DK, `S`, the keys and
     the decrypted store.
- **The cache:** per account, in process memory, only what `/v2/sync` sent (encrypted bodies,
  versions, `keyV`) and the cursor. Bounded (least recently used out, a fixed budget of accounts
  and bytes) and dropped after 30 minutes without a request. A new key version or
  `410 resync_required` empties that account's entry.
- **One request at a time per account** in the process, so two tool calls of one assistant do not
  push conflicting copies of the same record from two stores.
- **Idempotency without plaintext:** the local backend keeps `Idempotency-Key` answers in memory,
  which do not survive the request. For `add_transactions`, the ids of the new movements are
  derived from the key (UUID v5 of the user id, the key and the item's index). A retried call
  finds every derived id already in the store after the pull, writes nothing and answers as a
  replay (`Idempotent-Replayed`), so the tool says `alreadySaved` exactly as today. If only some
  ids exist (the first push was partly acknowledged), the missing ones are created and the answer
  is not a replay. Nothing about the request is cached.
- **Records it cannot open or validate** are left out, as on the web. Tool answers do not change
  shape for it: the person sees the "could not read N items" line on the web and the phone, as
  today. The MCP logs only the count.
- **Never logged:** no body, amount, name, `S` or key in a log line or error; only ids, types and
  counts, as the sync engine already does.

## 8. Revoking and rotation

- **`DELETE /v1/me/assistants/{clientId}`** also deletes that client's `assistant` wraps, in the
  same transaction as the tokens and consent. So does `revokeAllAssistants` (the admin's suspend
  action; people have no revoke-all route). The next request of that
  assistant gets 404 from `GET /v2/keys/assistant` and stops, even with an access token still
  inside its 15 minutes.
- **`POST /v2/keys/rotate`** (removing a device, or "Change keys" in Security) replaces every wrap
  with the ones it carries, and no client can make an `assistant` wrap under the new key without
  that assistant's `S`. So a rotation now refuses `assistant` wraps (`422 assistant_wrap_in_rotation`)
  and revokes every assistant of the account (tokens and consent) in the same transaction, so
  Settings → Assistants no longer lists them as connected.
- **Copy:** the remove-device sheet (web and phone) and "Change keys" say that connected assistants
  are disconnected and must be connected again. The web's `rotate.ts` comment about assistants
  (stage 4) is updated.

## 9. Testing

- **API** (testcontainers, extending `apps/api/test/oauth.test.ts` with the spike's assertions):
  `S` round-trips through consent, exchange and three refreshes; an encrypted account's authorize
  always shows the consent page; a refusal without `S` revokes the client; every access token has a `wk`
  that the MCP key opens to `S`; reusing a refresh token kills the family; revoke with the
  suffixed token works; no table column holds `S` (base64url, hex or base64) after the run, with a
  positive control; an encrypted account without `S` gets `400 invalid_grant`; a `plain` account
  gets today's tokens; revoke and rotate delete the wraps and revoke the assistants; the log
  output of the run never contains `S`.
- **`packages/vault`:** the moved tests, plus the in-memory `EncryptedStore` against the shared
  store contract.
- **MCP:** against the real API (the existing stack tests' pattern): connect a `preview` account
  through the consent flow, then each of the 14 tools; the read tools' answers equal the web local
  backend's over the same records (one fixture, both paths); a write appears in `/v2/sync` sealed,
  with `source: "mcp"` inside; a retried `add_transactions` with the same key writes once and says `alreadySaved`; a read tool
  with a `finance:read` token sends no `POST /v2/sync`; a token
  without `wk` on an encrypted account gives the reconnect error; revoke, then the next call fails;
  a rotation, then the next call fails; `psql` finds no plaintext of the run's words in any table.
- **Web:** unit tests of the consent page's three ways to the data key and of the order consent →
  wrap; an e2e that connects an assistant on the preview account with the vault open, and one with
  the recovery key.
- **Phone:** the remove-device sheet's new line.

## 10. Docs

`apps/mcp/AGENTS.md` (the two paths, the cache, the key config), `apps/api/AGENTS.md` (the
wrapper), `apps/web/AGENTS.md` (consent, the move), `packages/vault/AGENTS.md` (new), root
`AGENTS.md` map, `deploy/personal/AGENTS.md` (the key pair), the parent spec's sections 7.4, 7.5
and 9 pointing here.

## 11. Left to the builder

- The exact module boundaries inside `packages/vault`, as long as nothing in it touches a browser
  API.
- The cache's budget numbers.
- Whether the MCP's per-request work is shared between the tools of one MCP request.
- The JWK curve (X25519 or P-256), as long as both apps use `jose`'s compact JWE.

## 12. Calls made while writing (not decided with the founder)

- An encrypted account's authorize always shows the consent page, and a token refusal without `S`
  revokes that client (section 4).
- A retried `add_transactions` answers `alreadySaved` when every derived id exists (section 7).
- Tool answers keep their shape; unreadable records show only on the web and the phone (section 7).
- The MCP never re-seals and a read tool never pushes (sections 6 and 7).
- A rotation refuses `assistant` wraps and revokes every assistant (section 8).
- The shared backend gains the batch routes, the replay header and a forced `source` (section 6).
