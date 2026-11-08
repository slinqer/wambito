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

- `GET /v1/transactions`: `kind` (expense/income), `q` and `category` may repeat, `match=all|any`, `totals=true` adds the count and sums of every match.
- MCP `list_transactions`: `text` and `category` take lists, plus `kind` and `match`; with text or a category and no dates it searches every month; it returns `totals` (count, expense, income). The category filter now works (it was never sent to the API).

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
