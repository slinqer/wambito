# Restore after delete on encrypted accounts: design

Status: approach chosen by the founder 2026-11-17 ("A, borrado con contenido"). Follows ruling R9
of stage 4 (`2026-11-16-e2e-stage-4-mcp-design.md`, `packages/vault/AGENTS.md` "Known limit").

## 1. Intent

On a `plain` account a deleted movement can be brought back at any time (`POST
/v1/transactions/{id}/restore`, the MCP's `restore_transactions`). On an encrypted account a
delete pushed to `/v2/sync` is a tombstone with no body: the `records` table refuses a body on a
deleted row (`records_deleted_body`) and the push schema refuses one too. So:

- the device that deleted can undo, because its local store keeps the body;
- any other device, or the same one after a full download, cannot;
- the MCP rebuilds the account from the server on every request, so it can never undo a delete
  made in an earlier request, and answers `not_found`.

This blocks the stage 5 switch: after it, every account is encrypted, and the assistant's
"deletes can be undone" (`packages/ai-assistant-tools/src/instructions.ts`) would be false.

## 2. Goals, non-goals, anti-goals

Goals:

- A delete made by an updated client can be undone from any device and from the MCP, until the
  server purges the tombstone (180 days, unchanged).
- Same rule for every record type, not only transactions; only the restore routes that exist today
  use it (`restore_transactions` and the web's and phone's undo).

Non-goals:

- No new restore routes or tools for other types.
- No change to the 180-day purge or to the restore window of `plain` accounts.
- Deletes made before this change (no body on the server) stay unrecoverable except on the device
  that made them, as today.

Anti-goals (a failure even if it works):

- The server can read a deleted record. The body stays sealed exactly like a live one.
- A restored record differs from the deleted one (fields lost, wrong key version that no device
  can open).
- An old client breaks on a tombstone that now has a body.

## 3. Approaches

- **A. The tombstone carries its sealed body (chosen).** A delete pushes `deleted: true` with the
  record's sealed body; the server keeps it until the 180-day purge. Restoring is an ordinary update
  of that record with the same body. Small change, uses the existing purge, works for every type.
  Cost: the server keeps the ciphertext of deleted records for up to 180 days (it already keeps
  that a delete happened, and when), and key rotation must re-seal those bodies too.
- **B. A soft-delete flag inside the sealed body.** The server never learns that a record was
  deleted. Rejected: every read path on web, phone and MCP must filter, deleted records count
  against `MAX_LIVE_RECORDS`, the server cannot purge them, and a missed filter shows a deleted
  movement.
- **C. MCP-only memory of deleted bodies.** Rejected: the cache expires after 30 minutes and does
  nothing for other devices.

## 4. Protocol

### 4.1 Server (`apps/api`, `packages/db`)

- Migration: drop the check `records_deleted_body` and add one that only requires a live record to
  have a body (`deleted or body is not null`).
- Push schema (`apps/api/src/http/schemas.ts`): a deleted change may carry a body or `null`; a live
  change must carry one. The same size limits (`MIN_RECORD_BODY`, `MAX_RECORD_BODY`) apply to a
  deleted change's body.
- `pushRecords` stores the body with the tombstone. The idempotent-replay comparison already
  compares body bytes; a tombstone with a body and one without are different writes.
- Pull returns `body` on a tombstone when it has one. The OpenAPI descriptions say so: "null when
  deleted" becomes "always present on a live record; on a deleted one, null unless the client sent
  the sealed body so the record can be restored".
- Restore is an update with `deleted: false`, `baseVersion` = the tombstone's version and the body.
  `pushRecords` already turns a tombstone live (it counts it against the live limit again).
- The purge (`purgeTombstones`) is unchanged: after 180 days the row goes, body and all.
- Root `CHANGELOG.md` "Unreleased": a line for the push and pull change.

### 4.2 Sync engine (`packages/vault/src/sync.ts`, `apps/mobile/lib/local/sync.dart`)

The two engines change the same way (the Dart one is the twin of the TypeScript one).

- **Push.** A delete seals the local tombstone's body under the current key, as for a live record,
  and sends it. A local tombstone with no body (a delete downloaded before this change) sends
  `null`.
- **Pull.** A downloaded tombstone with a body is opened like a live record and stored as a
  tombstone holding that body, so a device that never had the record can restore it. A tombstone
  body that fails to open does not quarantine the record: the tombstone is stored without a body
  and the delete still applies (a delete must never be blocked by a body nobody needs).
- **Conflicts.** Unchanged in meaning. Where the server's copy is a tombstone, its body (if any)
  becomes the local tombstone's body.
- **Key rotation (upgrade pass).** Tombstones with a body under an older `keyV` get a `reseal`
  outbox entry like live records, so no tombstone body stays sealed only under a dropped key, and
  old keys can still be dropped once nothing local the server has is under them. A tombstone
  without a body needs no re-seal.

### 4.3 Stores (`packages/vault` stores, the web's IndexedDB store, the phone's SQLite store)

- The stores already keep the body on a local delete (`includeDeleted` shows it). They gain a way
  for a remote write to set a tombstone *with* a given body (today a remote delete keeps whatever
  body was local). Both store contracts (`storeContract`, `encryptedStoreContract`, and the Dart
  contract tests) gain the case.

### 4.4 Clients

- **MCP.** Inherits from `packages/vault`. `restore_transactions` works across requests. The
  "Known limit" in `packages/vault/AGENTS.md` and the stage 4 test that expects `not_found` change
  to expect the restore.
- **Web and phone.** Their undo paths already put the tombstone's body back; nothing else changes.
  They now also work for a delete made on another device.

## 5. Compatibility

- An old client's delete (no body) is still accepted; that delete simply cannot be restored
  elsewhere.
- An old client that downloads a tombstone with a body ignores the body today (web `sync.ts` and
  Dart `sync.dart` apply a downloaded tombstone with `body: null`). This must be confirmed by a test
  on both engines before the server change ships.
- Only `preview` accounts use `/v2` before stage 5, so there is no migration of existing tombstones.

## 6. Testing

- API (testcontainers): a delete with a body is stored and pulled with it; a delete without a body
  still works; a live change without a body is still refused; restore through an update makes it
  live and counts it against the limit; the purge removes a tombstone with a body; a replay of a
  delete with a body answers the stored version.
- `packages/vault`: push seals the tombstone body; pull stores a downloaded tombstone body; a body
  that fails to open keeps the delete; the upgrade pass re-seals tombstone bodies; the contract
  cases for a remote tombstone with a body.
- Dart: the same engine and store cases, against the shared fixtures where they exist.
- MCP: delete in one request, restore in the next, against the real API
  (`apps/mcp/test/vault-end-to-end.test.ts`); the plaintext scan still finds nothing in `records`.
- The phone's stack e2e (`test_stack/`): delete on one phone, restore on the other.

## 7. Calls made after the builder check

- **A tombstone for a record the device never had.** Today a remote delete of an unknown id writes
  nothing (`sqlite_store.dart` returns early, and the other stores do the same). A downloaded
  tombstone with a body now creates a tombstone row: the server's version and `keyV`, the opened
  body, no outbox entry. It follows the same `pending` and `skipIfPending` rules as a remote write.
  This is required in all three stores (memory, IndexedDB, SQLite): without it nothing is
  restorable from the MCP or a second device.
- **Key versions.** `keyVersionsInUse` counts tombstones that hold a body and have been pushed,
  like live records, so an old key is not dropped while a tombstone body still needs it.
  `queueReseal` queues those tombstones too. A reseal of a tombstone pushes `deleted: true` with
  the body re-sealed; the current `entry.deleted || row.deleted` already gives that.
- **A local unsent edit meets a server tombstone.** The deletion still wins and the person is still
  told (`server_deleted`), as today. The local tombstone keeps the person's own latest body, not
  the server's: restoring then brings back what they last saw. With no local edit, the server's
  body is kept.
- **The restore route already exists.** `backend.ts` answers `POST /v1/transactions/{id}/restore`
  by reading the tombstone with `includeDeleted` and putting its body back. It needs no change; it
  fails today only because the body is missing.
- **Recurrences.** `backend.ts` reads tombstones when it materializes occurrences ("one per rule
  and month, deleted or not") and when it drops pending ones. On the deleting device the
  tombstone has its body, so a deleted occurrence is not made again; on another device or the MCP
  it has none, so the result can differ. With bodies everywhere every client behaves like the
  deleting device: intended. The plan adds a test that the MCP does not re-create an occurrence
  deleted on another device, and the CHANGELOG line mentions it.
- **Order.** One change, one PR. The tests that pin what an engine does with a downloaded
  tombstone with a body are written first; the server change comes after them. Only `preview`
  accounts use `/v2`, so no separate client release has to ship first.
- **Limits.** A deleted change's body goes through the same checks as a live one (base64url,
  `MIN_RECORD_BODY`, `MAX_RECORD_BODY`).

## 8. Left to the builder

- The migration's name and the exact check expression.
- How each store exposes "remote tombstone with a body" (an option on `delete`, or a `put` with a
  deleted flag).
- Whether the reseal of tombstones shares the 500-per-pass limit with live records (it should, so a
  pass stays bounded).
