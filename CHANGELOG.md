# Changelog: the Wambito server

What changes in the server (the API in `apps/api` and the MCP server in `apps/mcp`) between
versions. The version is the root `package.json`'s `"version"`; `/health` reports it with the
commit it was built from (`1.0.0+1e5ccc2`). The Android app has its own version and notes
(`mobile-v*` tags, `apps/mobile/fastlane/metadata/android/*/changelogs`).

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/). A breaking change for clients (the web, the app, a
connected assistant) raises the major version and says what they must do.

How to add to it:

- Each pull request that changes the API or the MCP (routes, fields, errors, auth, scopes, MCP
  tools or prompts, limits) adds a line under **Unreleased**, in the group that fits: Added,
  Changed, Deprecated, Removed, Fixed, Security.
- To release, raise `"version"` in the root `package.json` and move the Unreleased lines under a
  new `## X.Y.Z - YYYY-MM-DD` heading, in the same commit (`chore: version X.Y.Z`). Optionally tag
  that commit `server-vX.Y.Z`. Every merge to `main` still deploys; a version only names a set of
  changes.

## Unreleased

### Added

- `GET`/`POST /v2/sync` (`pullRecords`, `pushRecords`): encrypted records, not yet used by clients. Pull by version (`since`, `limit` 1–1000, `next`, `latest`); push up to 500 changes and 4 MiB, each a new version, a conflict with the current record (a stale `baseVersion` or another `type`: a record's type never changes), `id_taken` (someone else's id) or `not_found` (an update of a record the server does not have: resync in full); ids are lower-case UUIDs (any other form, upper case included, is 422 `validation_failed`; never lower-cased by the server); a live body is 28 bytes (nonce and tag) to 64 KiB, 100,000 live records per account (409 `record_limit`), tombstones purged after 180 days. Assistants pull with `finance:read` and push with `finance:write`.
- `GET`/`PUT`/`DELETE /v2/keys`, `POST /v2/keys/rotate`, `GET /v2/keys/assistant` (`listKeyWraps`, `putKeyWrap`, `deleteKeyWrap`, `rotateKeys`, `getAssistantWrap`): the wrapped copies of the account's data key (passkey, recovery, device, assistant), stored as opaque bytes, not yet used by clients. Wrap ids are lower-case UUIDs (else 422 `validation_failed`). An account's first wrap is its recovery wrap (422 `recovery_required` otherwise); a wrap carries the current key version (409 `key_version_mismatch`); a passkey wrap names one of the person's passkeys (422 `unknown_passkey`), an assistant wrap a connected assistant (422 `unknown_assistant`); the recovery wrap is never deleted (409 `recovery_required`), only replaced; a rotation replaces every wrap with key version + 1 and exactly one recovery wrap. Deleting a passkey deletes its wrap. Assistants reach only `GET /v2/keys/assistant` (their own wrap, with `finance:read` or `finance:write`). `PUT /v2/keys/{id}` with `If-None-Match: *` stores the wrap only while the account has no other wrap (409 `already_set_up`): a first setup sends it with its recovery wrap, so two setups at once cannot give an account two data keys.
- `POST /v2/pairing`, `GET /v2/pairing?code=`, `POST /v2/pairing/{id}/seal`, `GET /v2/pairing/{id}`, `POST /v2/pairing/{id}/pickup` (`startPairing`, `findPairing`, `sealPairing`, `getPairing`, `pickupPairing`): relay to approve a new device from an unlocked one, opaque bytes only, not yet used by clients. See Changed for the commitment flow.
- `GET /v1/transactions`: `kind` (expense/income), `q` and `category` may repeat, `match=all|any`, `totals=true` adds the count and sums of every match (ask for it on the first page only).
- MCP `list_transactions`: `text` and `category` take lists, plus `kind` and `match`; it returns `totals` (count, expense, income), which include pending and to-review movements (pass `status: "paid"` for money already spent).
- `GET /v1/me` (and every profile answer): `encryption`, `"plain"` or `"preview"`. `preview` marks an account in the end-to-end encryption preview (env `E2E_PREVIEW_USER_IDS`, comma-separated user ids, unset by default): its finances live only as encrypted records under `/v2`, and signing up seeds no default account or categories for it (the web creates them as records). Its `/v1` finance routes (transactions, categories and budgets, recurrences, summary, reports, captures, imports, `GET /v1/me/export`) answer 403 `encrypted_account`, for its sessions and assistants' tokens alike, and so does `PATCH /v1/me` with a `currency` (it lives in the records); the account routes stay (`GET`/`PATCH`/`DELETE /v1/me`, the assistants list, claiming an email).

### Changed

- `/v2/keys` (unreleased): a `device` wrap needs a 32-byte `attestation` next to its `publicKey` (`PUT /v2/keys/{id}` and `POST /v2/keys/rotate`; else 422 `attestation_required`), and `GET /v2/keys` returns it (`null` for other kinds). The server stores it and cannot verify it; devices check it before sealing the data key to a device.
- `GET /v2/sync` (unreleased): optional `base` (the `latest` the pull cycle started from; 0 for a full download; defaults to `since`). 410 `resync_required` when `0 < base` and `base` is below the newest version of a tombstone the daily purge deleted; the device downloads everything again from `since=0&base=0`, which paging never trips.
- Pairing relay (`/v2/pairing`, unreleased): the new device commits first. `POST /v2/pairing` takes `{ commitment }` (SHA-256 of a domain tag and its public key) instead of a public key; `GET /v2/pairing?code=` returns `{ id, commitment, expiresAt }` and is 404 once an approver key is set; new `POST /v2/pairing/{id}/approver` (the approving device's ephemeral key, once: 409 `already_set`) and `POST /v2/pairing/{id}/reveal` (the new device's key, checked against the commitment: 409 `not_ready` or `already_set`, 422 `commitment_mismatch`); `POST /v2/pairing/{id}/seal` takes `{ sealed, keyV }`, needs the revealed key (409 `not_ready`) and a blob that starts with the approver key (422 `approver_mismatch`); `GET /v2/pairing/{id}` returns `{ commitment, approverKey, publicKey, sealed, keyV, expiresAt }` (null until set) and never deletes; new `POST /v2/pairing/{id}/pickup` returns `{ sealed, keyV }` and deletes the row in the same transaction (409 `not_ready` while unsealed, 404 when unknown, expired or foreign); `seal` needs `keyV` to be the account's current key version (409 `key_version_mismatch`).
- MCP `list_transactions` searches every month when given text or a category and no dates (before, it covered the current month only). Its page line now reads "On this page: N …" so it is not mistaken for the total.

### Fixed

- MCP `list_transactions` category filter: it was sent as `categoryId` and the API ignored it.

## 1.0.0 - 2026-11-05

The first numbered version: what the server offers today.

### Added

- HTTP API with an OpenAPI document ("Wambito API"): accounts, categories and budgets,
  transactions (with restore after delete), recurring payments, the month summary and reports,
  CSV imports.
- Sign-in by email code or magic link, guest accounts that can add an email later, and passkeys.
  Sign-in emails in Spanish, English, Italian and Portuguese.
- Automatic capture: `POST /v1/captures` saves a bank-notification capture to review, merges
  duplicates within 10 minutes and remembers the category per merchant. Captures are confirmed
  with `PATCH /v1/transactions/{id}` or `POST /v1/transactions/review`.
- Account deletion by the person.
- Admin panel API (`/v1/admin/*`): find accounts, change an email, sign out sessions, remove a
  passkey, disconnect an assistant, suspend, reactivate and delete. Each action takes a reason,
  writes an audit row and mails the person. Also metrics and the audit log. It needs a passkey
  check and is hidden (404) from everyone not in `ADMIN_USER_IDS`. It never returns finances.
- MCP server at `/mcp` for AI assistants, over OAuth with scopes checked by the API. Tools:
  `add_transactions`, `list_transactions`, `update_transaction`, `delete_transactions`,
  `restore_transactions`, `list_categories`, `create_category`, `update_category`, `set_budget`,
  `get_month_overview`, `spending_by_category`, `spending_trend`, `list_recurring`,
  `manage_recurring`. Prompts: `gastos` and `month`.
- `/health` reports the server's version (root `package.json` plus the commit).
