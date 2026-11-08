# End-to-end encryption, stages 0 and 1: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the two risky assumptions (passkey PRF on real devices, the assistant secret inside
Better Auth tokens), then build the crypto package and the server side of the new format, unused
by any client yet.

**Architecture:** `packages/crypto` (TypeScript, WebCrypto) implements records, wraps, recovery
keys, device sealing and pairing codes, pinned by shared test vectors. The API gains `records`,
`key_wraps` and `pairing_requests` (RLS on `user_id`) and the `/v2/sync`, `/v2/keys` and
`/v2/pairing` routes. Nothing in the web, the app or the MCP calls them in this plan.

**Tech Stack:** TypeScript, WebCrypto (`globalThis.crypto.subtle`, Node 22), `@noble/curves`
(X25519 fallback only), Hono + `@hono/zod-openapi`, Drizzle, Better Auth 1.7, Vitest +
testcontainers.

**Spec:** `docs/superpowers/specs/2026-11-08-end-to-end-encryption-design.md` (sections 4–7, 9 for
the spike, 13, 14).

## Global Constraints

- Branch: `docs/e2e-encryption-spec` (rename to `feat/e2e-encryption` at the first code task).
- AES-256-GCM, random 96-bit nonce; HKDF-SHA256 infos exactly `wambito/v1/record`,
  `wambito/v1/dedupe`, `wambito/v1/wrap/<kind>`; PRF salt `SHA-256("wambito/v1/prf")`.
- Record associated data `wambito/v1/record/<user id>/<type>/<id>/<key_v>`; wrap associated data
  `wambito/v1/wrap/<kind>/<user id>/<key_v>`.
- Plaintext padded with spaces to a multiple of 64 bytes; `body` = nonce (12) || ciphertext+tag.
- Recovery secret 128 bits, 26 Crockford base32 characters in groups of four plus one check
  character.
- Limits: `body` ≤ 64 KiB; ≤ 500 changes and ≤ 4 MiB per `POST /v2/sync`; ≤ 100,000 live records
  per account; pairing rows live 10 minutes; tombstones purged after 180 days.
- Types: `transaction`, `category`, `budget`, `recurrence`, `merchant`, `settings`, `account`.
- Wrap kinds: `passkey`, `recovery`, `device`, `assistant`; one live `recovery` wrap per account.
- `finance:read` may only `GET /v2/sync`; `finance:write` may also `POST /v2/sync`; both may
  `GET /v2/keys/assistant` (the wrap whose `ref` is the token's OAuth client id); nothing else
  under `/v2` for OAuth tokens.
- The server never logs a `/v2` request body and stores bodies only in `records`.
- Tests first. No personal names, emails or paths in the repo. Commits `feat(crypto): …`,
  `feat(api): …`, `docs: …`; stage by path; no `Co-Authored-By` line.
- Every new route goes under "Unreleased" in `CHANGELOG.md`; regenerate `apps/web/app/api/schema.d.ts`,
  `apps/mcp/src/api/schema.d.ts` and `apps/mobile/lib/api/gen` with their commands.

## Review Focus

1. **Two writes of the same person committing out of order** would let a device that synced in
   between skip a record forever (it asks `since` a version it already passed). Writes for one
   person must be serialized so versions become visible in order: a per-user advisory lock in
   `POST /v2/sync` (Task 6, test "versions are visible in commit order").
2. **A retried upload after a lost response** (`baseVersion: null`, same id, same body) must
   answer the stored version, not a conflict (Task 6, test "retrying a create is idempotent").
3. **A body sealed for another user, type, id or key_v** pasted into a request must fail to open
   on the client; the server cannot check it, so the test lives in `packages/crypto` (Task 2,
   "swapped associated data fails").
4. **A typo in the recovery key** must say "check the key", not open nothing silently or throw a
   generic error (Task 3, "one wrong character is caught by the check character").
5. **A pairing code guessed by another account** must never reach another person's pairing row:
   RLS plus a per-user lookup (Task 8, "another user's code is not found").

---

## Stage 0: spikes (throwaway, report only)

### Task 1: PRF and token-secret spikes

**Files:**
- Create: `docs/superpowers/reports/2026-11-08-e2e-spikes.md`
- Create (deleted before commit): `apps/api/test/spike-token-secret.test.ts`

- [ ] **Step 1: PRF on the web with existing passkeys.** The founder opens `app.wambito.com`
  signed out, in Chrome (Google Password Manager passkey) and in Safari (iCloud Keychain), opens
  the developer console and runs this; then the same in Chrome on the Android phone through
  `chrome://inspect` remote debugging.

```js
const salt = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode("wambito/v1/prf")));
const cred = await navigator.credentials.get({ publicKey: {
  challenge: crypto.getRandomValues(new Uint8Array(32)), rpId: location.hostname,
  userVerification: "required", extensions: { prf: { eval: { first: salt } } } } });
const prf = cred.getClientExtensionResults().prf;
console.log(prf?.results?.first ? `PRF ok, ${prf.results.first.byteLength} bytes` : "no PRF", prf);
```

  Expected: `PRF ok, 32 bytes` per provider, or `no PRF`. Run it twice with the same passkey and
  check the two outputs are equal (log `btoa(String.fromCharCode(...new Uint8Array(prf.results.first)))`).
  The founder runs it; the outputs are secrets of that passkey and are not pasted anywhere.

- [ ] **Step 2: PRF through Android Credential Manager.** On a local branch only, add
  `"extensions":{"prf":{"eval":{"first":"<base64url salt>"}}}` to the request JSON that
  `PasskeyChannel.kt` passes to `GetPublicKeyCredentialOption`, log whether the response JSON has
  `clientExtensionResults.prf.results.first`, build a release-signed APK (`docs/mobile/release.md`)
  pointed at production, sign in with the passkey. Expected: the field is present. Discard the
  branch.

- [ ] **Step 3: assistant secret through Better Auth tokens.** In
  `apps/api/test/spike-token-secret.test.ts`, with `createTestApp`, `registerAssistant`,
  `authorize` and `tokenRequest` from `test/harness.ts`, check:
  - `oauthProvider({ customAccessTokenClaims })` can add a claim `wk` read from a per-request value
    (an `AsyncLocalStorage` set by a middleware in front of `/auth/oauth2/token`);
  - a middleware can rewrite the token response's `refresh_token` to `<original>.<S>` and, on
    `grant_type=refresh_token`, strip `.<S>` before Better Auth sees it and put `S` back after;
  - the consent step can carry `S` to the code exchange without writing it to a table (keep it in a
    short-lived in-memory map keyed by the authorization code, deleted on exchange).
  Expected: a refresh issued 3 times in a row returns tokens that still carry `S`; the database has
  no column containing `S` (`select` every text column of the OAuth tables and assert no match).

- [ ] **Step 4: Write the report** in `docs/superpowers/reports/2026-11-08-e2e-spikes.md`: per
  provider PRF yes/no and stable yes/no; Credential Manager yes/no; the token approach that worked
  (hooks and files it needs) or why it did not. If any answer is "no", stop and bring it to the
  founder before Task 2 (spec section 9 says the fallback needs a new decision).

- [ ] **Step 5: Delete the spike test and commit the report.**

```bash
git rm --cached apps/api/test/spike-token-secret.test.ts 2>/dev/null; rm -f apps/api/test/spike-token-secret.test.ts
git add docs/superpowers/reports/2026-11-08-e2e-spikes.md
git commit -m "docs: end-to-end encryption spikes report"
```

---

## Stage 1: crypto package and server

### Task 2: `packages/crypto`: keys and records

**Files:**
- Create: `packages/crypto/package.json` (`@wambito/crypto`, same shape as `packages/core/package.json`), `tsconfig.json`, `AGENTS.md`, `CLAUDE.md` (`@AGENTS.md`), `src/index.ts`, `src/bytes.ts`, `src/keys.ts`, `src/records.ts`
- Test: `packages/crypto/test/records.test.ts`
- Modify: root `AGENTS.md` (map row for `packages/crypto`)

**Interfaces:**
- Produces:
  - `type RecordType = "transaction" | "category" | "budget" | "recurrence" | "merchant" | "settings" | "account"`
  - `interface RecordContext { userId: string; type: RecordType; id: string; keyV: number }`
  - `interface RecordKeys { record: CryptoKey; dedupe: CryptoKey }`
  - `generateDataKey(): Uint8Array` (32 bytes)
  - `deriveRecordKeys(dataKey: Uint8Array, extractable?: boolean): Promise<RecordKeys>` (default `false`)
  - `sealRecord(keys: RecordKeys, ctx: RecordContext, value: unknown, nonce?: Uint8Array): Promise<Uint8Array>`
  - `openRecord(keys: RecordKeys, ctx: RecordContext, body: Uint8Array): Promise<unknown>`, throws `CryptoError` with `code: "cannot_open"`
  - `dedupeTag(keys: RecordKeys, text: string): Promise<string>` (base64url HMAC-SHA256)
  - `class CryptoError extends Error { code: "cannot_open" | "bad_recovery_key" | "bad_input" }`
  - `toBase64Url(bytes: Uint8Array): string`, `fromBase64Url(text: string): Uint8Array` in `bytes.ts`

- [ ] **Step 1: Write the failing tests** in `test/records.test.ts`:
  - `seal then open returns the same value` (an object with a name, an amount 1800000, a note with "ñ").
  - `body length is 12 + 16 + a multiple of 64` for plaintexts of 1, 63, 64 and 65 bytes.
  - `two seals of the same value differ` (random nonce).
  - `swapped associated data fails`: open with each of `userId`, `type`, `id`, `keyV` changed → `CryptoError` `cannot_open`.
  - `a flipped byte or a truncated body fails` → `cannot_open`.
  - `record keys are not extractable by default` (`crypto.subtle.exportKey` rejects).
  - `dedupe tags are stable and key-dependent`.

- [ ] **Step 2: Run them**: `pnpm vitest run --project @wambito/crypto`. Expected: FAIL, module not found.

- [ ] **Step 3: Implement** the interfaces above with `crypto.subtle` only: `importKey("raw", dk, "HKDF")`,
  `deriveKey` to `AES-GCM` 256 and `HMAC` SHA-256 with an empty salt and the Global Constraints
  infos; JSON-encode, pad with spaces, seal with the record associated data.

- [ ] **Step 4: Run the tests.** Expected: PASS. Also `pnpm --filter @wambito/crypto typecheck`.

- [ ] **Step 5: Commit**

```bash
git switch -c feat/e2e-encryption
git add packages/crypto AGENTS.md pnpm-lock.yaml
git commit -m "feat(crypto): data key, record sealing and dedupe tags"
```

### Task 3: `packages/crypto`: wraps, recovery key, device sealing, pairing

**Files:**
- Create: `packages/crypto/src/wraps.ts`, `src/recovery.ts`, `src/devices.ts`, `src/pairing.ts`
- Test: `packages/crypto/test/wraps.test.ts`, `test/recovery.test.ts`, `test/devices.test.ts`

**Interfaces:**
- Consumes: `CryptoError`, base64url helpers (Task 2).
- Produces:
  - `type WrapKind = "passkey" | "recovery" | "device" | "assistant"`
  - `interface WrapContext { kind: WrapKind; userId: string; keyV: number }`
  - `PRF_SALT: Uint8Array` (32 bytes)
  - `wrapDataKey(secret: Uint8Array, ctx: WrapContext, dataKey: Uint8Array, nonce?: Uint8Array): Promise<Uint8Array>` and `unwrapDataKey(secret, ctx, wrapped): Promise<Uint8Array>` (for `passkey`, `recovery`, `assistant`; `secret` is the PRF output, the recovery secret or `S`)
  - `newRecoverySecret(): Uint8Array` (16 bytes), `formatRecoveryKey(secret: Uint8Array): string`, `parseRecoveryKey(text: string): Uint8Array` (ignores spaces, dashes and case; maps I/L→1, O→0; throws `bad_recovery_key`)
  - `generateDeviceKeyPair(): Promise<{ publicKey: Uint8Array; privateKey: CryptoKey }>` (X25519; non-extractable private key; `@noble/curves` fallback with the same shape when WebCrypto lacks X25519)
  - `sealToDevice(publicKey: Uint8Array, ctx: WrapContext, dataKey: Uint8Array): Promise<Uint8Array>` = ephemeral public key (32) || nonce (12) || ciphertext
  - `openFromDevice(privateKey: CryptoKey, ctx: WrapContext, sealed: Uint8Array): Promise<Uint8Array>`
  - `pairingCode(): string` (8 Crockford base32 characters), `pairingNumber(a: Uint8Array, b: Uint8Array): string` (6 digits from SHA-256 of `wambito/v1/pairing` || sorted keys, the same whichever side computes it)

- [ ] **Step 1: Write the failing tests:**
  - wraps: round trip per kind; wrong secret, another `userId`, another `keyV` or another kind → `cannot_open`.
  - recovery: `formatRecoveryKey` gives 7 groups (`/^([0-9A-Z]{4}-){6}[0-9A-Z]{3}$/`, 26 + 1 characters); round trip; lower case and spaces accepted; `one wrong character is caught by the check character` (every single-character change of 50 random keys throws `bad_recovery_key`); `O` and `0`, `I` and `1` read the same.
  - devices: seal to a public key, open with its private key; another key pair cannot open; tampered ephemeral key fails.
  - pairing: `pairingNumber(a, b) === pairingNumber(b, a)`, 6 digits with leading zeros kept; codes are 8 characters from the Crockford alphabet.

- [ ] **Step 2: Run**: `pnpm vitest run --project @wambito/crypto`. Expected: FAIL.

- [ ] **Step 3: Implement.** Check character: Crockford's mod-37 check symbol over the 128-bit value
  (alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ*~$=U`). Device sealing: ECDH(ephemeral, device public)
  → HKDF with info `wambito/v1/wrap/device` → AES-GCM with the wrap associated data. Add
  `@noble/curves` to `packages/crypto/package.json`.

- [ ] **Step 4: Run the tests.** Expected: PASS.

- [ ] **Step 5: Commit**: `git add packages/crypto pnpm-lock.yaml && git commit -m "feat(crypto): key wraps, recovery key, device sealing and pairing codes"`

### Task 4: Shared test vectors

**Files:**
- Create: `packages/crypto/scripts/gen-vectors.ts`, `packages/crypto/test-vectors.json`
- Test: `packages/crypto/test/vectors.test.ts`

**Interfaces:**
- Produces: `test-vectors.json`, read by the Dart tests in stage 3:
  `{ records: [{ dataKey, ctx, nonce, value, body }], wraps: [{ secret, ctx, nonce, dataKey, wrapped }], recovery: [{ secret, text }], devices: [{ privateKey, publicKey, ctx, sealed, dataKey }], pairing: [{ a, b, number }] }`, bytes as base64url.

- [ ] **Step 1: Write the failing test** `vectors.test.ts`: for every entry, opening `body` /
  `wrapped` / `sealed` gives the expected value; sealing with the fixed `nonce` gives the exact
  `body` and `wrapped`; `parseRecoveryKey(text)` equals `secret`; `pairingNumber` equals `number`.
  At least 3 records (one with non-ASCII text, one exactly 64 bytes before padding), every wrap
  kind, 2 devices.
- [ ] **Step 2: Run.** Expected: FAIL (file missing).
- [ ] **Step 3: Write `gen-vectors.ts`** (fixed inputs, run with `node --experimental-strip-types`, writes the JSON) and a `vectors` script in `package.json`; run it once.
- [ ] **Step 4: Run the tests.** Expected: PASS. Run the generator again and `git diff --exit-code packages/crypto/test-vectors.json` (deterministic).
- [ ] **Step 5: Commit**: `git add packages/crypto && git commit -m "feat(crypto): shared test vectors"`

### Task 5: Tables `records`, `key_wraps`, `pairing_requests`

**Files:**
- Modify: `packages/db/src/schema/domain.ts` (tables and `RLS_TABLES`), `packages/db/src/index.ts`
- Create: `packages/db/drizzle/0010_end_to_end_records.sql` (+ `meta`) via `pnpm --filter @wambito/db generate`, then the RLS lines added by hand as in `0009`
- Test: `packages/db/test/records-rls.test.ts`

**Interfaces:**
- Produces (Drizzle):
  - `records`: `id uuid pk`, `userId text → user.id cascade`, `type text`, `version bigint not null default nextval('records_version_seq')`, `deleted boolean default false`, `keyV smallint`, `encV smallint`, `body bytea null`, `updatedAt timestamptz`; index `(user_id, version)`; check `deleted = (body is null)`.
  - `keyWraps`: `id uuid pk`, `userId`, `kind text` (check in the four kinds), `ref text null`, `keyV smallint`, `wrapped bytea`, `publicKey bytea null`, `label text null`, `createdAt`, `lastUsedAt null`; unique `(user_id) where kind = 'recovery'`; unique `(user_id, kind, ref) where ref is not null`.
  - `pairingRequests`: `id uuid pk`, `userId`, `code text`, `publicKey bytea`, `sealed bytea null`, `expiresAt timestamptz`; unique `(user_id, code)`.
  - A `bytea` custom type in `domain.ts` mapping to `Uint8Array`.

- [ ] **Step 1: Write the failing test** `records-rls.test.ts` (as the runtime role with `withUser`): user A cannot select, update or delete B's rows in each of the three tables; inserting a row with B's `user_id` while acting as A fails; `version` grows across inserts and updates (`update … set version = default`).
- [ ] **Step 2: Run**: `pnpm vitest run --project @wambito/db`. Expected: FAIL.
- [ ] **Step 3: Add the schema, generate the migration, append ENABLE/FORCE RLS and the `tenant_isolation` policy for the three tables**, add them to `RLS_TABLES`.
- [ ] **Step 4: Run the db tests.** Expected: PASS.
- [ ] **Step 5: Commit**: `git add packages/db && git commit -m "feat(db): records, key wraps and pairing tables"`

### Task 6: `/v2/sync`

**Files:**
- Create: `apps/api/src/routes/sync.ts`, `apps/api/src/services/sync.ts`
- Modify: `apps/api/src/app.ts` (mount), `apps/api/src/http/scopes.ts`, `apps/api/src/http/schemas.ts`, `apps/api/src/server.ts` (tombstone purge schedule next to `scheduleGuestCleanup`), `CHANGELOG.md`
- Test: `apps/api/test/sync.test.ts`

**Interfaces:**
- Consumes: tables from Task 5.
- Produces (OpenAPI operations):
  - `pullRecords`: `GET /v2/sync?since=<int ≥ 0>&limit=<1..1000, default 500>` → `200 { records: SyncRecord[], next: number | null, latest: number }`; `SyncRecord = { id, type, version, deleted, keyV, encV, body: string | null }` (`body` base64url).
  - `pushRecords`: `POST /v2/sync` `{ changes: Change[] }`, `Change = { id, type, baseVersion: number | null, deleted, keyV, encV, body: string | null }` → `200 { results: ({ id, version } | { id, conflict: SyncRecord } | { id, error: "id_taken" })[] }` in request order.
  - Errors: `413 payload_too_large` (> 4 MiB), `422 validation_failed` (> 500 changes, body > 64 KiB decoded, `deleted` and `body` inconsistent, unknown type), `409 record_limit` (> 100,000 live records).
  - `purgeTombstones(db, now): Promise<number>` in `services/sync.ts` (deletes `deleted` rows older than 180 days) and `scheduleTombstonePurge({ db })`.

- [ ] **Step 1: Write the failing tests** in `sync.test.ts`:
  - `pull from 0 returns every record in version order`, with `next` paging at `limit` and `latest`.
  - `create, update with the right baseVersion, delete` → versions grow; the delete pulls back with `deleted: true, body: null`.
  - `a stale baseVersion is a conflict carrying the current record`; other changes in the batch still apply.
  - `retrying a create is idempotent` (same id, same body, `baseVersion: null` → the stored `{ id, version }`); same id with a different body → conflict.
  - `versions are visible in commit order`: two concurrent pushes for one user with a delay injected in the first (a `deps` hook in the service); a pull between them never returns the second version without the first.
  - `two users never see each other's records`; a create by A with an id that B already owns gets `{ id, error: "id_taken" }` for that change, never B's record.
  - limits: 501 changes, a 64 KiB + 1 body, a request over 4 MiB, the 100,001st live record (insert 100,000 tombstones-free rows with SQL first).
  - scopes: an assistant with `finance:read` can pull and gets `403 insufficient_scope` on push; `finance:write` can push.
  - `purgeTombstones` removes a 181-day-old tombstone and keeps a 179-day-old one and every live record.
  - `no request body is logged`: spy on `console` during a push with a body containing a marker; the marker never appears.
- [ ] **Step 2: Run**: `pnpm vitest run apps/api/test/sync.test.ts`. Expected: FAIL.
- [ ] **Step 3: Implement.** Push runs in one `withUser` transaction that first takes
  `pg_advisory_xact_lock(hashtextextended('records:' || user_id, 0))`; each change is an
  `insert … on conflict do nothing` or an `update … where version = baseVersion` with
  `version = nextval`, and a per-change savepoint so one failure does not abort the rest. Request
  size via `hono/body-limit`. Add `/v2/sync` to `ASSISTANT_PATHS` handling: `GET` needs
  `finance:read`, `POST` needs `finance:write`.
- [ ] **Step 4: Run the tests**, then `pnpm vitest run apps/api` (nothing else breaks). Expected: PASS.
- [ ] **Step 5: Regenerate client types** (root `AGENTS.md` commands for web, mcp, mobile), add the
  CHANGELOG line ("Added: `GET`/`POST /v2/sync`, encrypted records, not yet used by clients").
- [ ] **Step 6: Commit**: `git add apps/api CHANGELOG.md apps/web/app/api/schema.d.ts apps/mcp/src/api/schema.d.ts apps/mobile/lib/api/gen && git commit -m "feat(api): sync encrypted records"`

### Task 7: `/v2/keys`

**Files:**
- Create: `apps/api/src/routes/keys.ts`
- Modify: `apps/api/src/app.ts`, `apps/api/src/http/scopes.ts`, `apps/api/src/auth.ts` (after-hook on the passkey delete endpoint), `CHANGELOG.md`
- Test: `apps/api/test/keys.test.ts`

**Interfaces:**
- Produces:
  - `listKeyWraps`: `GET /v2/keys` → `{ wraps: KeyWrap[] }`, `KeyWrap = { id, kind, ref, keyV, wrapped, publicKey, label, createdAt, lastUsedAt }` (bytes base64url).
  - `putKeyWrap`: `PUT /v2/keys/{id}` with `{ kind, ref, keyV, wrapped, publicKey?, label? }` → `200 KeyWrap`. `passkey`: `ref` must be one of the person's passkey credential ids (else `422 unknown_passkey`); `assistant`: `ref` must be an OAuth client the person has a consent for (else `422 unknown_assistant`); `device`: `publicKey` required (32 bytes); `recovery`: replaces the existing recovery wrap. `keyV` must equal the account's current `keyV` (the max over its wraps, or any value for the first wrap) else `409 key_version_mismatch`.
  - `deleteKeyWrap`: `DELETE /v2/keys/{id}` → `204`; refusing to delete the last `recovery` wrap (`409 recovery_required`).
  - `rotateKeys`: `POST /v2/keys/rotate` `{ keyV, wraps: Omit<KeyWrap, "createdAt" | "lastUsedAt">[] }` → `200 { wraps }`; `keyV` must be current + 1; replaces every wrap in one transaction; must include exactly one `recovery`.
  - `getAssistantWrap`: `GET /v2/keys/assistant` → `200 KeyWrap` for the token's `grant.clientId`, `404 not_found` otherwise; sets `lastUsedAt`. Sessions get `404`.

- [ ] **Step 1: Write the failing tests:** each rule above; deleting a passkey through Better Auth
  (`/passkey/delete-passkey`, via `test/soft-passkey.ts`) removes its wrap; an assistant token gets
  `403` on every `/v2/keys` route except `GET /v2/keys/assistant`, which returns only its own
  client's wrap even when the person connected two assistants; RLS between two users.
- [ ] **Step 2: Run**: `pnpm vitest run apps/api/test/keys.test.ts`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Regenerate client types, CHANGELOG line, commit**: `git commit -m "feat(api): key wraps and rotation"` (stage the same generated paths as Task 6).

### Task 8: `/v2/pairing`

**Files:**
- Create: `apps/api/src/routes/pairing.ts`
- Modify: `apps/api/src/app.ts`, `CHANGELOG.md`
- Test: `apps/api/test/pairing.test.ts`

**Interfaces:**
- Consumes: `pairingCode` from `@wambito/crypto` (server makes the code).
- Produces:
  - `startPairing`: `POST /v2/pairing` `{ publicKey }` (32 bytes) → `201 { id, code, expiresAt }`; at most 5 unexpired requests per person (`429 too_many_pairings`).
  - `findPairing`: `GET /v2/pairing?code=<8 chars>` → `200 { id, publicKey, expiresAt }` or `404 not_found` (expired, sealed, or not the person's).
  - `sealPairing`: `POST /v2/pairing/{id}/seal` `{ sealed }` (≤ 1 KiB) → `204`; `409 already_sealed`.
  - `takePairing`: `GET /v2/pairing/{id}` → `200 { sealed: string | null }`; when `sealed` is returned the row is deleted in the same transaction.
  - Expired rows are deleted by the tombstone purge schedule (Task 6) as well.

- [ ] **Step 1: Write the failing tests:** the full flow with `sealToDevice`/`openFromDevice`
  from `@wambito/crypto` (the new device opens the data key); `another user's code is not found`;
  an expired request (clock `now` + 11 minutes) is 404 everywhere; a second take after pickup is
  404; the sixth open request is 429; assistant tokens get 403.
- [ ] **Step 2: Run**: `pnpm vitest run apps/api/test/pairing.test.ts`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the tests**, then the whole repo check: `pnpm lint && pnpm typecheck && pnpm test`. Expected: PASS.
- [ ] **Step 5: Regenerate client types, CHANGELOG line, update `apps/api/AGENTS.md`** (the `/v2` routes, the advisory lock, "bodies never logged"), commit: `git commit -m "feat(api): device pairing relay"`.

### Task 9: Branch review and PR

- [ ] **Step 1:** `pnpm lint && pnpm typecheck && pnpm test` and `scripts/check-old-name.sh`. Expected: all pass.
- [ ] **Step 2:** Push `feat/e2e-encryption` and open a PR (title `feat: end-to-end encryption, stage 1 (crypto and server)`), body: what exists, that no client uses it yet, link to the spec and the spikes report.
