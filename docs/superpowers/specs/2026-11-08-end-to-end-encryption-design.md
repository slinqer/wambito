# End-to-end encryption: design

Date: 2026-11-08. Status: approved in conversation, spec under review.

## 1. Goal

Nobody but the person can read their finance data: not the server, not its database or backups,
not anyone on the network, not the people who run Wambito. Every device the person uses keeps its
own copy, decrypts it with keys only the person holds, and computes everything locally. The server
stores and relays ciphertext.

An AI assistant (the MCP) is a separate product the person opts into. Connecting one hands the
assistant the data it asks for, and only while it stays connected; the consent screen says so.

Success means:

- A Postgres dump or an R2 backup contains no name, amount, note, date, category name, merchant or
  setting of any person.
- Daily use feels the same or faster: adding, the widget, automatic capture, search, Analysis, and
  works offline.
- Changing phones takes one passkey touch (or a QR approval, or the recovery key).
- The public release in Play and F-Droid happens after this ships (store preparation goes on).

This replaces the "vault mode" idea in `2026-10-29-stage-4-mcp-design.md` (section 11): encryption
is on for every account, not an option.

## 2. Decisions taken

| Question | Decision |
|---|---|
| Optional "vault mode" or everyone | Everyone, existing accounts included, migrated by the client |
| Where data lives | A local copy on every device (SQLite on Android, IndexedDB on the web); the server keeps a full encrypted copy for sync, new devices and backups |
| Sync model | Versioned rows: one version per record, the server orders changes, a stale write is rejected and merged by the client (as Bitwarden and Standard Notes do). No CRDT |
| Server tables | One generic `records` table of opaque encrypted records with a type; no month, category or amount in clear |
| Unlocking a device | Passkey with the WebAuthn PRF extension, a mandatory recovery key, or approval from another device by QR. No password |
| Email code | Signs in, never decrypts |
| Remote MCP | The person's device wraps the data key with a secret `S` that travels only inside the assistant's tokens; the server never stores `S` |
| Order | Migration last, once web, Android and the MCP all read the new format |

## 3. Threat model

Protects against: a copy of the database or a backup; someone with read access to the server's
disk; a network observer (TLS already covers it, encryption adds the server itself); a curious
operator; a legal request for content (there is none to hand over).

Does not protect against, and the copy never claims it does:

- **Metadata.** The server sees the email, how many records of each type a person has, when they
  change, from which IP, and their sizes in coarse buckets (bodies are padded, section 4.2).
- **A compromised web server** can serve JavaScript that reads the key while the page is open. The
  Android app, signed and (on F-Droid) reproducibly built, does not have that weakness. The privacy
  policy says so.
- **A connected assistant** reads what its tools return; while it is connected, the MCP server
  decrypts in memory during each request (section 9).
- **A stolen, unlocked device.** Device security (screen lock, Keystore) is the boundary there.
- **Losing every passkey and the recovery key.** The data is gone. That is the price of nobody
  else being able to open it.

## 4. Cryptography

### 4.1 Keys

```
data key DK: 32 random bytes, one per account (one current version, key_v)
  ├─ HKDF-SHA256(DK, info "wambito/v1/record")  → record key   (AES-256-GCM)
  └─ HKDF-SHA256(DK, info "wambito/v1/dedupe")  → dedupe key   (HMAC-SHA256)

wraps of DK kept on the server (table key_wraps), one per way in:
  ├─ passkey     wrap key = HKDF(PRF output of that passkey, info "wambito/v1/wrap/passkey")
  ├─ recovery    wrap key = HKDF(recovery secret, info "wambito/v1/wrap/recovery")
  ├─ device      sealed to the device's X25519 public key (ECDH + HKDF + AES-GCM)
  └─ assistant   wrap key = HKDF(S, info "wambito/v1/wrap/assistant")
```

- Every wrap is AES-256-GCM with a random 96-bit nonce and associated data
  `wambito/v1/wrap/<kind>/<user id>/<key_v>`, so a wrap cannot be moved to another account.
- **Why AES-GCM and not XChaCha20:** it is native in WebCrypto, which is the only way to keep keys
  non-extractable in the browser, and hardware-accelerated on Android (`javax.crypto` and the Dart
  `cryptography` package, no Google dependency, fine for F-Droid). Nonces are random; a person
  writes far fewer than the 2^32 messages per key where random 96-bit nonces become a concern.
- **PRF salt:** the fixed 32 bytes `SHA-256("wambito/v1/prf")`, the same for every passkey. The PRF
  output differs per credential.
- **Recovery secret:** 128 random bits, shown as 26 Crockford base32 characters in groups of four
  plus one check character (`WMB1-7KQ3-…`). It is random, so no slow KDF is needed.
- **Device keys:** each device makes an X25519 key pair on its first unlock. The private key never
  leaves the device (Android Keystore through `flutter_secure_storage`; a non-extractable
  `CryptoKey` in IndexedDB on the web, with `@noble/curves` only where WebCrypto lacks X25519).

### 4.2 Records

- Plaintext: UTF-8 JSON `{ "s": <schema version>, ...fields }`, padded with spaces to the next
  multiple of 64 bytes, so a note's length shows only in coarse steps.
- `body` = `nonce (12 bytes) || AES-256-GCM ciphertext and tag`.
- Associated data: `wambito/v1/record/<user id>/<type>/<id>/<key_v>`. The server cannot move a body
  to another record, type or account without the open failing.
- `<user id>` is the account's id exactly as stored (Better Auth ids: letters, digits, `-` and `_`); record and wrap ids are lower-case UUIDs.
- Shared test vectors (`packages/crypto/test-vectors.json`): fixed keys, nonces and plaintexts with
  their expected bodies and wraps. The TypeScript and Dart implementations must both pass them, so
  a record written on the web always opens on the phone and the other way round.

### 4.3 Where the code lives

- `packages/crypto` (new, TypeScript, WebCrypto): keys, records, wraps, recovery format, pairing,
  test vectors. Used by the web, the MCP and the API tests. No other crypto library except
  `@noble/curves` as the X25519 fallback.
- `apps/mobile/lib/crypto` (Dart): the same operations on `cryptography`; the vectors run in its
  tests. Kotlin never decrypts (section 8.3).

## 5. Data model on the server

### 5.1 `records`

```sql
create table records (
  id          uuid primary key,          -- made by the client (UUID v7)
  user_id     uuid not null,             -- RLS: tenant_isolation, as today
  type        text not null,             -- transaction, category, budget, recurrence, merchant, settings, account
  version     bigint not null,           -- from a global sequence, raised on every write
  deleted     boolean not null default false,
  key_v       smallint not null,         -- which data key version encrypted body
  enc_v       smallint not null,         -- format version (1)
  body        bytea,                     -- null once deleted
  updated_at  timestamptz not null
);
create index on records (user_id, version);
```

- `type` stays in clear: it lets a new device fetch categories before movements and helps debugging.
  It reveals counts per type (section 3).
- A deleted record keeps its row (`deleted = true`, `body = null`) so other devices learn about the
  deletion. Tombstones older than 180 days are purged; a device that has not synced for longer does
  a full resync.
- Limits: `body` up to 64 KiB; at most 100,000 live records per account (several decades of use),
  checked on write.
- Ids are made by the client, so a retried upload is the same record: `idempotency_keys` is no
  longer needed for finance writes.

### 5.2 `key_wraps`

```sql
create table key_wraps (
  id          uuid primary key,
  user_id     uuid not null,             -- RLS
  kind        text not null,             -- passkey | recovery | device | assistant
  ref         text,                      -- passkey credential id, device id, or OAuth client id
  key_v       smallint not null,
  wrapped     bytea not null,
  public_key  bytea,                     -- device kind: the device's X25519 public key
  label       text,                      -- "Pixel 9", "Firefox on Mac": shown in Settings
  created_at  timestamptz not null,
  last_used_at timestamptz
);
```

One live recovery wrap per account. Deleting a passkey in Better Auth deletes its wrap in the same
transaction.

### 5.3 What leaves the old tables

Every column listed as sensitive in today's schema (`accounts`, `categories`, `category_budgets`,
`recurrences`, `imports`, `transactions`, `merchant_categories`, `idempotency_keys.body`) moves into
records and is dropped at the end of the migration (section 11). `user.timezone` and `user.locale`
stay in clear: the server uses them for email and for guest cleanup. The currency moves into the
`settings` record.

## 6. Sync API

All under `/v2`, documented in the OpenAPI, with `requireUser` as today.

- `GET /v2/sync?since=<version>&limit=<1..1000>` → `{ records: [...], next: <version> | null,
  latest: <version> }`, ordered by `version`. `since=0` downloads everything (a new device).
- `POST /v2/sync` with `{ changes: [{ id, type, baseVersion | null, deleted, keyV, encV, body }] }`,
  up to 500 changes and 4 MiB → per change either `{ id, version }` or
  `{ id, conflict: <current record> }`.
  - `baseVersion: null` creates; it is a conflict if the id already exists with a different body.
  - Otherwise the write applies only when `baseVersion` equals the stored version.
  - Each change applies on its own; one conflict does not reject the batch.
- `GET /v2/keys` → the account's wraps; `PUT /v2/keys/{id}` adds or replaces a wrap; `DELETE
  /v2/keys/{id}` removes one.
- `POST /v2/keys/rotate` takes the new wraps for every remaining way in, plus `key_v + 1`, in one
  transaction. Records are re-encrypted by the client through `/v2/sync` afterwards.
- Pairing relay (section 7.3): `POST /v2/pairing`, `GET /v2/pairing/{id}`,
  `POST /v2/pairing/{id}/seal`. Rows expire after 10 minutes and are deleted on pickup.
- OAuth scopes: `finance:read` may only `GET /v2/sync`; `finance:write` may also `POST`. Both may
  read `GET /v2/keys/assistant`, which returns only the wrap whose `ref` is the token's OAuth client.
  Neither can list, add or delete wraps, rotate, or use pairing.

Conflict handling on the client: download the current record, merge field by field (a field the
local change did not touch takes the server's value; a field both changed takes the local value),
upload again with the new `baseVersion`. When both sides decrypt to the same content (two devices
making the same recurrence occurrence, section 8.1), the client takes the server's record and
uploads nothing. A merge that cannot apply (the record was deleted) keeps
the deletion and tells the person if it was one of their unsent edits.

## 7. Keys in practice

### 7.1 New account

On sign-up the client makes DK, its device key, the recovery secret, and (when signing up with a
passkey that returns PRF) the passkey wrap. The recovery key screen comes before the first use:
shown once, downloadable as a small PDF or text file, and confirmed by typing four characters
back. The `settings` record and the suggested categories are created as records by the client
(today `auth.ts` seeds them on the server).

### 7.2 Unlocking a new device

After signing in (email code or passkey), the device is "locked" until one of these succeeds:

1. **Passkey with PRF.** The sign-in itself asks for PRF with the fixed salt; if the result opens a
   passkey wrap, the device is unlocked in the same touch.
2. **Approval from another device** (section 7.3).
3. **Recovery key**, typed or pasted.

The device then makes its key pair, adds its `device` wrap, and downloads every record.

Existing passkeys need no replacement when their provider supports PRF (Google Password Manager,
iCloud Keychain on macOS 15 and iOS 18.4+, per the sources checked on 2026-11-08). When a passkey
returns no PRF, the client says so and offers to add a passkey in a provider that does; the other
two ways keep working. Stage 0 checks this with real passkeys before anything is built.

### 7.3 Approving from another device

1. The new device makes an ephemeral X25519 key pair and calls `POST /v2/pairing` with its public
   key. It shows a QR (pairing id and public key) and an 8-character code.
2. The unlocked device scans the QR or types the code, then fetches the public key.
3. Both show the same 6-digit number derived from both public keys; the person confirms on the old
   device that they match. This stops a server that swaps keys.
4. The old device seals DK to the new device's public key and posts it; the new device picks it up,
   and the relay deletes the row.

### 7.4 Daily use

- **Android:** DK and the device private key live in `flutter_secure_storage` (Keystore). The app
  opens without asking for anything, as today.
- **Web:** after unlocking, the device private key and the derived record and dedupe keys are kept
  as non-extractable `CryptoKey`s in IndexedDB. DK itself is not kept; operations that need it
  (adding a passkey, connecting an assistant, rotating, showing a new recovery key) ask for a
  passkey touch or the recovery key again.
- Signing out deletes the local keys and the local database on that device.

### 7.5 Removing access and rotating

- Removing a passkey or the recovery key deletes its wrap. DK never left the device in clear, so no
  rotation is needed.
- Removing a **device** or disconnecting an **assistant** deletes its wrap and **rotates**: an
  unlocked device makes a new DK, posts new wraps for the passkeys, the recovery key, the remaining
  devices (sealed to their public keys, so they do not need to unlock again) and the remaining
  assistants (impossible without their `S`: they are disconnected and must reconnect), then
  re-encrypts every record with `key_v + 1`. A few thousand records take seconds.
- A web browser that sees a new `key_v` opens its `device` wrap with its non-extractable private
  key and derives the new record keys; DK is in memory only during that step.
- Until re-encryption finishes, records of both `key_v` coexist; every device keeps the previous DK
  until it sees no record with the old `key_v`.
- Making a new recovery key replaces the recovery wrap (no rotation).

## 8. Clients

### 8.1 Shared rules

- Each record type has a zod schema in `packages/core` (and the Dart model mirrors it). A record
  that fails to open or to validate is kept aside, never shown and never overwritten, and counted in
  a "could not read N items" line in Settings.
- Everything the server used to compute moves to the client:

| Today on the server | After |
|---|---|
| Summary, budgets, reports, cost of living | `packages/core` on the web and the MCP; the same rules in Dart |
| Search (`LIKE`) and its totals; category suggestions | Queries on the local database |
| Recurrence materialization on read | The client creates each occurrence with a deterministic id: UUID v5 of the rule id and the month. Two devices create the same record, never a duplicate |
| CSV import, file and row hashes | Parsed on the client (`packages/importers` on the web; a Dart port on the phone); duplicates detected with `HMAC(dedupe key, row)` kept inside the records |
| Capture merge and merchant → category memory | On the phone; the memory is `merchant` records |
| Category name uniqueness, currency lock | Checked by the client |
| Export | Built on the client: an encrypted file by default, plain JSON or CSV when the person asks |

- The rules that exist only in TypeScript today (`monthSummary`, `effectiveBudget`,
  `costOfLiving`, search folding and totals) get a Dart port that passes the same test cases, kept
  as shared JSON fixtures next to `packages/core`, like `quick-capture/cases.json`.

### 8.2 Web

- Local database in IndexedDB (records decrypted into typed stores, plus the sync cursor).
- TanStack Query reads from the local store instead of the API. `optimistic.ts` and the demo
  backend already compute with `core`; the demo backend's logic becomes the real local backend.
- Sync runs on open, on focus, after each write, and every 60 seconds while visible.
- New screens: unlock (passkey, QR, recovery key), recovery key setup, "approve a device" (QR shown
  or scanned with the camera, code typed), and Settings → Security (passkeys, devices, assistants,
  new recovery key).

### 8.3 Android

- Local SQLite database (`sqflite` or `drift`, chosen in the stage 3 plan; both are F-Droid safe),
  replacing `home.cache` and the offline save queue: a save is a local write plus a pending change.
- Automatic capture: Kotlin keeps parsing notifications and queueing the merchant and amount, as
  today, but no longer posts to `/v1/captures`. A WorkManager job starts a headless Dart entry
  point that drains the queue into local records (merge, merchant category, needs review), syncs,
  and refreshes the widget snapshot. Kotlin never holds DK.
- The widget reads the snapshot that Dart writes after each sync or save; `SummaryFetcher.kt` and
  the Kotlin notices calls go away.
- The same new screens as the web, plus scanning the QR shown by the web.

## 9. Remote MCP

- **Connecting** (the consent page on the web, which asks for a passkey touch to get DK): the web
  makes `S` (32 random bytes), posts the `assistant` wrap, and sends `S` with the approval. The
  server keeps `S` only next to the authorization code (deleted on exchange or after 10 minutes).
- **Tokens:** the refresh token handed to the assistant is Better Auth's refresh token plus `.` plus
  `S` in base64url. The access token carries `S` encrypted to the MCP server's key (a `wk` claim).
  On refresh, a wrapper around the token endpoint splits `S` off, lets Better Auth refresh, and puts
  `S` back into both new tokens. `S` is never written to the database or logs.
- **Each tool call:** the MCP reads `S` from the token, fetches the `assistant` wrap, opens DK in
  memory, syncs the records it needs (`/v2/sync`, with the same token), decrypts, computes with
  `core`, answers, and drops DK and the decrypted data when the request ends. A small in-memory cache
  of ciphertext per account is allowed; never of plaintext or keys.
- The `Wambito` interface in `packages/ai-assistant-tools` does not change; a new implementation
  replaces `api-wambito.ts`. Tools keep returning computed totals, not raw rows, because models add
  badly and should see only what they need.
- Writes are encrypted records posted with the token; `source: "mcp"` is set inside the body by the
  MCP (the server can no longer enforce it).
- **Disconnecting** deletes the wrap and rotates the key (section 7.5).
- The consent screen says: while connected, Wambito decrypts your data on its server only to
  answer your assistant, and the assistant's company reads what it is given.
- If stage 0 shows the token wrapper is not workable with Better Auth, the fallback is to keep `S`
  on the server encrypted with an MCP secret; that weakens the promise (the operator could decrypt
  connected accounts at any time) and needs a new decision, not a silent switch.

## 10. Guests

Guest (anonymous) accounts get DK and a device key but no recovery key and no passkey wrap: their
data lives only on that device and the server's encrypted copy. Turning a guest into a real account
asks for the recovery key setup at that moment.

## 11. Migration

1. Stages 1–4 ship with the new format switched off. Nothing changes for anyone.
2. The switch is per account (`user.encryption_state`: `plain` → `migrating` → `encrypted`). When
   an updated client opens a `plain` account:
   1. it sets up the keys and the recovery key (section 7.1);
   2. downloads everything through the current endpoints (`GET /v1/me/export` in JSON);
   3. writes it as records through `/v2/sync`;
   4. calls `POST /v2/migration/finish` with the counts per type. The server checks them against
      the old tables, then deletes that account's plaintext rows in the same transaction and sets
      `encrypted`.
3. An `encrypted` account gets `426 update_required` from the old `/v1` finance endpoints, so an
   old app or web tab says "update Wambito" instead of showing empty data.
4. Once no `plain` account remains, the old tables, routes, reports and `idempotency_keys` usage are
   dropped in a migration, and the OpenAPI loses them (a major server version, `CHANGELOG.md`).
5. Old plaintext in backups expires with the existing 14-day retention, locally and in R2. The
   privacy policy says the date after which no plaintext copy exists.

## 12. Copy, policy and stores

- Privacy policy (`docs/privacy-policy.md`), landing FAQ and the store listings describe what the
  server can and cannot see, including the metadata and the web caveat. The landing tests that
  forbid "end-to-end" claims today (`overclaims`) change on the day the migration switch turns on,
  not before.
- Play's data safety form: data encrypted in transit; the developer cannot read financial info.
- The automatic capture copy already avoids saying who reads what on the server
  (`2026-11-05-automatic-capture-how-it-works-design.md`); it needs no change.

## 13. Testing

- `packages/crypto`: test vectors, wrong key, swapped associated data, truncated body, every wrap
  kind, recovery format and check character, pairing short code.
- Dart: the same vectors; the shared `core` fixtures for summary, budgets, search, cost of living.
- API (testcontainers): sync paging, conflicts, tombstones, limits, RLS between two users, scopes
  (`finance:read` cannot POST), key routes, pairing expiry, migration finish with good and bad
  counts, `426` after migration.
- A test that the server never logs or stores a request body of `/v2/sync` outside `records`.
- MCP: `S` round-trips through refresh; a token without `S` cannot read; disconnect then read fails.
- Web e2e: sign up, recovery key, add movements, a second browser context unlocks by recovery key
  and by pairing, offline edit then sync, conflict merge.
- Android: unit tests on the local database and the sync loop; the capture worker with a fake
  queue; the widget snapshot after sync.
- A migration rehearsal on a copy of the production database (restored from R2 into a local
  Postgres) before the switch turns on in production.

## 14. Stages

Each stage gets its own implementation plan.

0. **Spikes (throwaway code):** PRF with the founder's real passkeys on the web and through Android
   Credential Manager (does the extension pass through `PasskeyChannel.kt`, does Google Password
   Manager return it); the token wrapper around Better Auth's refresh flow. The design is adjusted
   before stage 1 if either fails.
1. **Crypto and server:** `packages/crypto` (with its `AGENTS.md` and a row in the root map), test
   vectors, `records`, `key_wraps`, `/v2/sync`, `/v2/keys`, pairing relay, `CHANGELOG.md` lines.
   Unused by clients.
2. **Web:** local store, sync, local computation, key screens, Settings → Security.
3. **Android:** Dart crypto, SQLite, sync, Dart ports of the core rules, capture worker, widget,
   key screens.
4. **MCP:** the decrypting `Wambito` implementation, the token wrapper, the consent copy.
5. **Migration:** the switch, the rehearsal, policy and store copy, then dropping the old tables.
   The public store release follows.

## 15. Risks

- **PRF support varies** by password manager (Samsung Pass and some third-party managers are
  unconfirmed). Mitigation: recovery key and QR approval always work; stage 0 measures it.
- **Two implementations** (TypeScript and Dart) can drift. Mitigation: shared vectors and fixtures,
  run in CI for both.
- **Support for "I lost everything".** No technical fix exists by design; the recovery key screen
  and periodic reminders in Settings are the mitigation.
- **The web is the weak client.** Documented honestly; later, a signed and versioned web bundle or
  a browser extension could reduce it.
- **Better Auth token internals** may change across versions; the wrapper is covered by tests that
  fail on upgrade.
- **Size of the change.** It touches every client. Mitigation: stages ship behind the switch;
  nobody's data changes until stage 5.

## 16. Later (not in this spec)

- Semantic search on the device (`semantic-search-later`), on-device chat about finances.
- A local MCP (stdio) that pairs as a device, for people who want no server-side decryption at all.
- Shared budgets between people (would revisit the sync model).
- Hiding `type` and record counts.
